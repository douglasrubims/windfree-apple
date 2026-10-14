import Foundation
import Network
import Observation
import OSLog
import WindFreeKit

/// Estado global do app, comum a macOS, iOS e iPadOS: credenciais, origem dos dados, aparelho escolhido e
/// ciclo de vida. Cada plataforma informa quando a interface fica visível (`panelVisible`) e quando o app
/// deve pausar ou retomar as consultas (`suspend`/`resume`).
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case needsSetup
        case loadingDevices
        case noDevices
        case ready
        case sessionExpired
        case failed(String)
    }

    let preferences = Preferences()

    private(set) var phase: Phase = .starting
    private(set) var devices: [DeviceSummary] = []
    /// A credencial atual não tem a permissão `r:locations:*`, então os cômodos não aparecem.
    private(set) var roomsUnavailable = false
    private(set) var engine: ACSyncEngine?
    private(set) var credentialSummary: CredentialSummary?
    /// Pedido de autorização OAuth em andamento.
    private(set) var oauthRequest: OAuthRequest?
    /// Autorização em andamento para o Apple Watch (feita no iPhone).
    private(set) var companionRequest: OAuthRequest?

    /// Controles visíveis (painel aberto no Mac, app em primeiro plano no iPhone): controla a frequência de
    /// consultas e as animações.
    var panelVisible = false {
        didSet {
            guard panelVisible != oldValue else { return }
            scheduler?.setPanelVisible(panelVisible)
        }
    }

    @ObservationIgnored private let credentials = CredentialManager(store: KeychainStore(service: AppModel.keychainService))
    @ObservationIgnored private var simulator: SimulatedSmartThings?
    @ObservationIgnored private var api: (any SmartThingsAPI)?
    @ObservationIgnored private var scheduler: RefreshScheduler?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var networkAvailable = true
    @ObservationIgnored private let log = Logger(subsystem: "io.github.douglasrubims.WindFree", category: "app")

    static let keychainService = "io.github.douglasrubims.WindFree"

    init() {
        observePowerState()
        observeNetwork()
        Task { await bootstrap() }
    }

    var isSimulated: Bool { preferences.useSimulation }

    var selectedDevice: DeviceSummary? {
        devices.first { $0.id == engine?.deviceID }
    }

    /// Nome para menus e listas ("Ar condicionado · Quarto").
    func title(for device: DeviceSummary) -> String {
        devices.title(for: device)
    }

    // MARK: - Inicialização

    func bootstrap() async {
        stopEngine()
        devices = []
        if preferences.useSimulation {
            let simulator = simulator ?? SimulatedSmartThings()
            self.simulator = simulator
            api = simulator
            credentialSummary = nil
            await loadDevices()
            return
        }
        do {
            credentialSummary = try await credentials.summary()
        } catch {
            log.error("Falha ao ler o Keychain: \(String(describing: error), privacy: .public)")
            credentialSummary = nil
        }
        guard credentialSummary != nil else {
            api = nil
            phase = .needsSetup
            return
        }
        api = SmartThingsClient(tokens: credentials)
        await loadDevices()
    }

    func loadDevices() async {
        guard let api else {
            phase = .needsSetup
            return
        }
        phase = .loadingDevices
        do {
            let found = await withRoomNames(try await api.listDevices().filter(\.isAirConditioner), api: api)
            devices = found.sorted { found.title(for: $0).localizedStandardCompare(found.title(for: $1)) == .orderedAscending }
            guard !devices.isEmpty else {
                phase = .noDevices
                return
            }
            let preferred = devices.first { $0.id == preferences.selectedDeviceID } ?? devices[0]
            select(preferred.id)
        } catch {
            let failure = SmartThingsError.from(error)
            log.error("Falha ao listar aparelhos: \(String(describing: failure), privacy: .public)")
            phase = failure == .unauthorized ? .sessionExpired : .failed(failure.userMessage)
        }
    }

    /// Os cômodos são um complemento: sem a permissão ou com falha, os aparelhos aparecem sem eles.
    private func withRoomNames(_ devices: [DeviceSummary], api: any SmartThingsAPI) async -> [DeviceSummary] {
        var rooms: [Room] = []
        var forbidden = false
        for locationID in Set(devices.compactMap(\.locationID)) {
            do {
                rooms += try await api.rooms(locationID: locationID)
            } catch SmartThingsError.forbidden {
                forbidden = true
            } catch {
                log.error("Falha ao ler cômodos: \(String(describing: SmartThingsError.from(error)), privacy: .public)")
            }
        }
        roomsUnavailable = forbidden
        return devices.withRoomNames(rooms)
    }

    func select(_ deviceID: String) {
        guard let api, engine?.deviceID != deviceID || phase != .ready else { return }
        stopEngine()
        let engine = ACSyncEngine(deviceID: deviceID, api: api)
        let scheduler = RefreshScheduler(engine: engine)
        scheduler.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)
        self.engine = engine
        self.scheduler = scheduler
        preferences.selectedDeviceID = deviceID
        phase = .ready
        scheduler.start()
        scheduler.setPanelVisible(panelVisible)
    }

    func refreshNow() {
        switch phase {
        case .ready: scheduler?.refreshNow()
        case .failed, .noDevices, .sessionExpired: Task { await loadDevices() }
        default: break
        }
    }

    private func stopEngine() {
        scheduler?.stop()
        engine?.stop()
        scheduler = nil
        engine = nil
    }

    // MARK: - Credenciais

    func setSimulation(_ enabled: Bool) async {
        preferences.useSimulation = enabled
        if !enabled { simulator = nil }
        await bootstrap()
    }

    /// Valida o token pessoal listando os aparelhos antes de guardá-lo.
    func savePersonalToken(_ token: String, expiresAt: Date?) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SmartThingsError.notAuthenticated }
        _ = try await SmartThingsClient(tokens: StaticTokenProvider(token: trimmed)).listDevices()
        try await credentials.save(.personalToken(token: trimmed, expiresAt: expiresAt))
        preferences.useSimulation = false
        await bootstrap()
    }

    /// Prepara a autorização e devolve o endereço para abrir no navegador. Depois o usuário cola em
    /// `completeOAuth` o endereço final, que contém o código (o SmartThings não permite retorno automático
    /// para o app; ver `OAuthService`).
    func beginOAuth(client: OAuthClientConfiguration) throws -> URL {
        cancelOAuth()
        let state = OAuthService.makeState()
        let url = try OAuthService().authorizationURL(for: client, state: state)
        oauthRequest = OAuthRequest(client: client, state: state)
        return url
    }

    /// Autoriza de novo com o app OAuth já guardado (sem redigitar o segredo), pedindo as permissões atuais.
    func beginReauthorization() async throws -> URL {
        guard var client = try await credentials.oauthClient() else { throw OAuthError.invalidConfiguration }
        client.scopes = OAuthClientConfiguration.defaultScopes
        return try beginOAuth(client: client)
    }

    func completeOAuth(callbackURL: URL) async throws {
        guard let request = oauthRequest else { throw OAuthError.stateMismatch }
        let tokens: OAuthTokens
        do {
            let code = try OAuthService.code(fromCallback: callbackURL, expectedState: request.state)
            tokens = try await OAuthService().exchange(code: code, client: request.client)
        } catch {
            // Só o tipo do erro e o motivo do servidor; nunca o código ou o segredo.
            log.error("OAuth falhou: \(String(describing: error), privacy: .public)")
            throw error
        }
        // Confere o acesso antes de substituir a credencial atual.
        _ = try await SmartThingsClient(tokens: StaticTokenProvider(token: tokens.accessToken)).listDevices()
        try await credentials.save(.oauth(client: request.client, tokens: tokens))
        cancelOAuth()
        preferences.useSimulation = false
        await bootstrap()
    }

    static let defaultRedirectURI = OAuthService.smartThingsRedirectURI

    func cancelOAuth() {
        oauthRequest = nil
    }

    static func message(for error: Error) -> String {
        switch error {
        case let error as OAuthError: error.userMessage
        case let error as SmartThingsError: error.userMessage
        case is KeychainError: "Não foi possível gravar no Keychain."
        default: "Falha inesperada."
        }
    }

    func signOut() async {
        cancelOAuth()
        try? await credentials.clear()
        preferences.selectedDeviceID = nil
        await bootstrap()
    }

    // MARK: - Apple Watch

    /// iPhone: inicia uma autorização própria para o relógio, com o mesmo app OAuth deste aparelho.
    /// Cada aparelho fica com a sua autorização e renova a sua, sem invalidar a do outro.
    func beginCompanionAuthorization() async throws -> URL {
        guard var client = try await credentials.oauthClient() else { throw OAuthError.invalidConfiguration }
        // Autorizações novas pedem as permissões atuais (incluindo cômodos), mesmo que a do iPhone seja antiga.
        client.scopes = OAuthClientConfiguration.defaultScopes
        let state = OAuthService.makeState()
        let url = try OAuthService().authorizationURL(for: client, state: state)
        companionRequest = OAuthRequest(client: client, state: state)
        return url
    }

    /// Troca o código por uma autorização nova, que não é guardada aqui: vai para o relógio.
    func completeCompanionAuthorization(callbackURL: URL) async throws -> StoredCredential {
        guard let request = companionRequest else { throw OAuthError.stateMismatch }
        let code = try OAuthService.code(fromCallback: callbackURL, expectedState: request.state)
        let tokens: OAuthTokens
        do {
            tokens = try await OAuthService().exchange(code: code, client: request.client)
        } catch {
            log.error("OAuth do relógio falhou: \(String(describing: error), privacy: .public)")
            throw error
        }
        _ = try await SmartThingsClient(tokens: StaticTokenProvider(token: tokens.accessToken)).listDevices()
        companionRequest = nil
        return .oauth(client: request.client, tokens: tokens)
    }

    func cancelCompanionAuthorization() {
        companionRequest = nil
    }

    /// Relógio: guarda no próprio Keychain a credencial recebida do iPhone.
    func installTransferredCredential(_ credential: StoredCredential) async throws {
        try await credentials.save(credential)
        preferences.useSimulation = false
        await bootstrap()
    }

    // MARK: - Diagnóstico

    /// Grava um relatório sem identificadores pessoais e devolve o arquivo (o Mac mostra no Finder; o iPhone
    /// oferece compartilhar).
    func exportDiagnostics() throws -> URL {
        guard let engine, let status = engine.rawStatus else { throw SmartThingsError.invalidResponse }
        let data = try DiagnosticReport.make(status: status, health: engine.health,
                                             capabilities: engine.capabilities, state: engine.confirmed)
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            .appendingPathComponent("WindFree", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = folder.appendingPathComponent("diagnostico-\(formatter.string(from: Date())).json")
        try data.write(to: file, options: [.atomic])
        return file
    }

    // MARK: - Ciclo de vida, energia e rede

    /// Ninguém vê os controles (Mac suspenso ou com a tela apagada, app em segundo plano): para as consultas.
    func suspend() {
        scheduler?.stop()
    }

    /// Volta a consultar depois de `suspend`, com uma pequena espera para a rede voltar.
    func resume() {
        log.info("Retomando consultas")
        switch phase {
        case .ready:
            scheduler?.systemDidWake()
        case .failed:
            Task {
                try? await Task.sleep(for: .seconds(3))
                await loadDevices()
            }
        default:
            break
        }
    }

    private func observePowerState() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduler?.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
        })
    }

    /// Quando a rede volta depois de uma falha, tenta de novo sem esperar a espera progressiva.
    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(available: available) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "WindFree.NetworkMonitor", qos: .utility))
    }

    private func networkChanged(available: Bool) {
        defer { networkAvailable = available }
        guard available, !networkAvailable else { return }
        log.info("Rede disponível novamente")
        switch (phase, engine?.issue) {
        case (.ready, .failure?): scheduler?.systemDidWake()
        case (.failed, _): Task { await loadDevices() }
        default: break
        }
    }

}

struct OAuthRequest: Sendable {
    let client: OAuthClientConfiguration
    let state: String
}
