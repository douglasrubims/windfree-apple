import Foundation
import Observation
import os

/// Situação que a interface precisa comunicar.
public enum SyncIssue: Sendable, Equatable {
    case notAuthenticated
    case sessionExpired
    case deviceOffline
    case rateLimited(until: Date)
    case failure(SmartThingsError)
    /// O aparelho não refletiu o ajuste depois das tentativas de confirmação.
    case unconfirmed(Set<ACSetting>)
    /// A plataforma recusou o comando.
    case rejected(Set<ACSetting>)

    public var blocksPolling: Bool {
        self == .notAuthenticated || self == .sessionExpired
    }
}

/// Mantém o estado de um ar-condicionado, separando o que foi pedido do que foi confirmado.
///
/// - `pending`: pedidos ainda não enviados (agrupados por `debounce`, ou retidos com o ar desligado).
/// - `inflight`: enviados, aguardando confirmação pela leitura do status.
/// - `confirmed`: último estado lido do aparelho.
///
/// Nunca há duas operações de rede simultâneas para o mesmo aparelho.
@MainActor
@Observable
public final class ACSyncEngine {
    public struct Configuration: Sendable {
        /// Espera depois do último toque antes de enviar (agrupa vários cliques).
        public var debounce: Duration = .milliseconds(600)
        public var firstConfirmDelay: Duration = .milliseconds(800)
        public var confirmAttempts = 4
        public var confirmInterval: Duration = .milliseconds(1500)
        /// Pausa entre ligar e enviar os ajustes de clima no mesmo lote.
        public var postPowerOnDelay: Duration = .seconds(1)
        /// Ajustes que só são enviados com o ar ligado.
        public var heldWhileOff: Set<ACSetting> = ACSetting.climate
        /// Por quanto tempo o aviso de ajuste não confirmado continua visível.
        public var unconfirmedNoticeDuration: TimeInterval = 20

        public init() {}
    }

    public enum Activity: Sendable, Equatable {
        case idle, refreshing, sending, confirming
    }

    public let deviceID: String

    public private(set) var confirmed: ACState?
    public private(set) var capabilities = ACCapabilities()
    public private(set) var health: DeviceHealth = .unknown
    public private(set) var pending: [ACSetting: ACValue] = [:]
    public private(set) var inflight: [ACSetting: ACValue] = [:]
    public private(set) var unconfirmed: Set<ACSetting> = []
    public private(set) var activity: Activity = .idle
    public private(set) var issue: SyncIssue?
    public private(set) var lastUpdated: Date?
    public private(set) var consecutiveFailures = 0
    public private(set) var retryNotBefore: Date?

    /// Último status bruto, usado no diagnóstico. Não participa da observação.
    @ObservationIgnored public private(set) var rawStatus: DeviceStatus?

    @ObservationIgnored private let api: any SmartThingsAPI
    @ObservationIgnored private let configuration: Configuration
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var unconfirmedAt: Date?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.douglasrubims.WindFree", category: "sync")

    public init(deviceID: String, api: any SmartThingsAPI, configuration: Configuration = Configuration(),
                now: @escaping @Sendable () -> Date = Date.init)
    {
        self.deviceID = deviceID
        self.api = api
        self.configuration = configuration
        self.now = now
    }

    // MARK: - Estado derivado

    /// Estado exibido: confirmado + enviados + pedidos.
    public var displayed: ACState? {
        confirmed?.applying(inflight).applying(pending)
    }

    /// Pedidos que podem ser enviados agora.
    public var sendable: [ACSetting: ACValue] {
        let willBeOn = pending[.power]?.bool ?? confirmed?.isOn ?? false
        return pending.filter { willBeOn || !configuration.heldWhileOff.contains($0.key) }
    }

    /// Pedidos aguardando o ar ser ligado.
    public var held: Set<ACSetting> {
        Set(pending.keys).subtracting(sendable.keys)
    }

    public var isSyncing: Bool {
        activity == .sending || activity == .confirming || (!sendable.isEmpty && health != .offline)
    }

    public var isLoaded: Bool { confirmed != nil }

    public func isAwaiting(_ setting: ACSetting) -> Bool {
        pending[setting] != nil || inflight[setting] != nil
    }

    // MARK: - Pedidos

    public func request(_ setting: ACSetting, _ value: ACValue) {
        let alreadyThere = value.matches(confirmed?.value(for: setting)) && inflight[setting] == nil
        if alreadyThere {
            pending[setting] = nil
        } else {
            pending[setting] = value
        }
        if unconfirmed.remove(setting) != nil, unconfirmed.isEmpty { clearCommandIssue() }
        scheduleFlush(after: configuration.debounce)
    }

    /// Cancela tarefas agendadas. Chame antes de descartar o motor.
    public func stop() {
        flushTask?.cancel()
        flushTask = nil
    }

    // MARK: - Leitura

    /// Lê o status. Ignorada se outra operação estiver em andamento (sem consultas sobrepostas).
    public func refresh(force: Bool = false) async {
        guard activity == .idle else { return }
        if !force, let until = retryNotBefore, until > now() { return }
        activity = .refreshing
        log.info("Leitura de status")
        do {
            try await readDevice(includeHealth: true)
            recordSuccess()
        } catch {
            record(error)
        }
        activity = .idle
        expireUnconfirmedNotice()
        if !sendable.isEmpty { scheduleFlush(after: configuration.debounce) }
    }

    // MARK: - Envio

    /// Envia os pedidos acumulados agora (normalmente chamado pelo agendamento).
    public func flush() async {
        guard activity == .idle else { return } // reagendado ao fim da operação atual
        if let until = retryNotBefore, until > now() {
            scheduleFlush(after: .seconds(until.timeIntervalSince(now())))
            return
        }
        guard health != .offline else { return }
        let batch = sendable
        guard !batch.isEmpty else { return }

        for key in batch.keys { pending[key] = nil }
        inflight = batch
        unconfirmed.subtract(batch.keys)
        activity = .sending
        log.info("Enviando \(batch.count, privacy: .public) ajuste(s)")

        do {
            var rejected: Set<ACSetting> = []
            let steps = ACCommandBuilder.steps(for: batch, capabilities: capabilities)
            for (index, step) in steps.enumerated() {
                let accepted = try await api.execute(deviceID: deviceID, commands: step.commands)
                if !accepted { rejected.formUnion(step.settings) }
                if step.isPowerOn, accepted, index < steps.count - 1 {
                    try await Task.sleep(for: configuration.postPowerOnDelay)
                }
            }
            activity = .confirming
            let missing = try await confirm(batch, skipping: rejected)
            recordSuccess()
            unconfirmed = missing.union(rejected)
            if !rejected.isEmpty {
                setIssue(.rejected(rejected))
            } else if !missing.isEmpty {
                setIssue(.unconfirmed(missing))
            } else {
                clearCommandIssue()
            }
            unconfirmedAt = unconfirmed.isEmpty ? nil : now()
        } catch {
            record(error)
        }

        inflight = [:]
        activity = .idle
        if !sendable.isEmpty { scheduleFlush(after: configuration.debounce) }
    }

    /// Executa uma ação pontual (como zerar o filtro) e confere o resultado.
    @discardableResult
    public func perform(_ action: ACAction) async -> Bool {
        for _ in 0..<40 where activity != .idle {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard activity == .idle else { return false }
        activity = .sending
        defer { activity = .idle }
        do {
            guard try await api.execute(deviceID: deviceID, commands: ACCommandBuilder.commands(for: action)) else {
                return false
            }
            activity = .confirming
            for attempt in 0..<configuration.confirmAttempts {
                try await Task.sleep(for: attempt == 0 ? configuration.firstConfirmDelay : configuration.confirmInterval)
                try await readDevice(includeHealth: false)
                switch action {
                case .resetFilter where (confirmed?.filterUsage ?? 1) == 0: return true
                default: continue
                }
            }
            recordSuccess()
            return false
        } catch {
            record(error)
            return false
        }
    }

    // MARK: - Internos

    /// Reinicia a espera de agrupamento. Cancelar a espera nunca interrompe um envio em andamento:
    /// o envio roda numa tarefa própria.
    private func scheduleFlush(after delay: Duration) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            Task { await self.flush() }
        }
    }

    /// Lê o status até que os ajustes enviados apareçam ou acabem as tentativas.
    private func confirm(_ batch: [ACSetting: ACValue], skipping rejected: Set<ACSetting>) async throws
        -> Set<ACSetting>
    {
        var remaining = Set(batch.keys).subtracting(rejected)
        guard !remaining.isEmpty else { return [] }
        for attempt in 0..<configuration.confirmAttempts {
            try await Task.sleep(for: attempt == 0 ? configuration.firstConfirmDelay : configuration.confirmInterval)
            try await readDevice(includeHealth: false)
            remaining = remaining.filter { !batch[$0]!.matches(confirmed?.value(for: $0)) }
            if remaining.isEmpty { break }
        }
        return remaining
    }

    private func readDevice(includeHealth: Bool) async throws {
        let api = api
        let deviceID = deviceID
        async let statusRead = api.status(deviceID: deviceID)
        async let healthRead: DeviceHealth? = includeHealth ? (try? await api.health(deviceID: deviceID)) : nil
        let status = try await statusRead
        let health = await healthRead

        rawStatus = status
        let state = ACInterpreter.state(from: status)
        if state != confirmed { confirmed = state }
        let caps = ACInterpreter.capabilities(from: status)
        if caps != capabilities { capabilities = caps }
        if let health, health != self.health { self.health = health }
        lastUpdated = now()
    }

    private func recordSuccess() {
        consecutiveFailures = 0
        retryNotBefore = nil
        switch issue {
        case .notAuthenticated, .sessionExpired, .failure, .rateLimited, .deviceOffline:
            setIssue(nil)
        default:
            break
        }
        if health == .offline, issue == nil { setIssue(.deviceOffline) }
    }

    private func record(_ error: Error) {
        let failure = (error as? OAuthError) == .invalidGrant ? .unauthorized : SmartThingsError.from(error)
        log.error("Falha: \(String(describing: failure), privacy: .public)")
        switch failure {
        case .cancelled:
            return
        case .unauthorized:
            setIssue(.sessionExpired)
        case .notAuthenticated:
            setIssue(.notAuthenticated)
        case .rateLimited(let retryAfter):
            let wait = min(max(retryAfter ?? 60, 5), 600)
            let until = now().addingTimeInterval(wait)
            retryNotBefore = until
            setIssue(.rateLimited(until: until))
        default:
            consecutiveFailures += 1
            setIssue(.failure(failure))
        }
    }

    private func setIssue(_ newIssue: SyncIssue?) {
        if issue != newIssue { issue = newIssue }
    }

    private func clearCommandIssue() {
        switch issue {
        case .unconfirmed, .rejected: setIssue(health == .offline ? .deviceOffline : nil)
        default: break
        }
    }

    private func expireUnconfirmedNotice() {
        guard let since = unconfirmedAt, now().timeIntervalSince(since) >= configuration.unconfirmedNoticeDuration
        else { return }
        unconfirmedAt = nil
        unconfirmed = []
        clearCommandIssue()
    }
}
