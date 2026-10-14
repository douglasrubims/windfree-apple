import Foundation

/// Intervalos de consulta. Mais frequente com o painel aberto, espaçado em segundo plano
/// e com espera progressiva depois de falhas.
public struct PollingPolicy: Sendable, Hashable {
    public var visibleInterval: TimeInterval = 15
    public var hiddenInterval: TimeInterval = 120
    public var lowPowerVisibleInterval: TimeInterval = 30
    public var lowPowerHiddenInterval: TimeInterval = 300
    public var maximumBackoff: TimeInterval = 600
    /// Com o painel aberto, dados mais velhos que isso são atualizados na hora.
    public var staleAfter: TimeInterval = 5

    public init() {}

    /// Próxima espera, ou `nil` quando não adianta consultar (sem sessão válida).
    public func delay(panelVisible: Bool, lowPower: Bool, consecutiveFailures: Int, retryNotBefore: Date?,
                      issue: SyncIssue?, now: Date) -> TimeInterval?
    {
        if issue?.blocksPolling == true { return nil }
        var base = switch (panelVisible, lowPower) {
        case (true, false): visibleInterval
        case (true, true): lowPowerVisibleInterval
        case (false, false): hiddenInterval
        case (false, true): lowPowerHiddenInterval
        }
        if consecutiveFailures > 0 {
            base = min(base * pow(2, Double(min(consecutiveFailures, 8))), max(maximumBackoff, base))
        }
        if let retryNotBefore {
            base = max(base, retryNotBefore.timeIntervalSince(now))
        }
        return base
    }
}

/// Repete a leitura do aparelho conforme a `PollingPolicy`. Uma única tarefa por vez.
@MainActor
public final class RefreshScheduler {
    public var policy: PollingPolicy
    public private(set) var panelVisible = false
    public private(set) var isRunning = false
    public var lowPower = false

    private weak var engine: ACSyncEngine?
    private var loop: Task<Void, Never>?
    private let now: @Sendable () -> Date

    public init(engine: ACSyncEngine, policy: PollingPolicy = PollingPolicy(),
                now: @escaping @Sendable () -> Date = Date.init)
    {
        self.engine = engine
        self.policy = policy
        self.now = now
    }

    public func start() {
        isRunning = true
        restart(refreshFirst: true)
    }

    public func stop() {
        isRunning = false
        loop?.cancel()
        loop = nil
    }

    public func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        guard isRunning else { return }
        restart(refreshFirst: visible && isStale)
    }

    public func setLowPower(_ enabled: Bool) {
        guard enabled != lowPower else { return }
        lowPower = enabled
        if isRunning { restart(refreshFirst: false) }
    }

    /// Atualiza já (por exemplo, a pedido do usuário ou depois de credenciais novas).
    public func refreshNow() {
        guard isRunning else { return }
        restart(refreshFirst: true, force: true)
    }

    /// Depois da suspensão a rede pode demorar a voltar; esperamos um pouco antes de ler.
    /// Também retoma um agendador parado na suspensão ou com a tela apagada.
    public func systemDidWake() {
        isRunning = true
        restart(refreshFirst: true, initialDelay: 3, force: true)
    }

    private var isStale: Bool {
        guard let last = engine?.lastUpdated else { return true }
        return now().timeIntervalSince(last) > policy.staleAfter
    }

    private func nextDelay() -> TimeInterval? {
        guard let engine else { return nil }
        return policy.delay(panelVisible: panelVisible, lowPower: lowPower,
                            consecutiveFailures: engine.consecutiveFailures,
                            retryNotBefore: engine.retryNotBefore, issue: engine.issue, now: now())
    }

    private func restart(refreshFirst: Bool, initialDelay: TimeInterval = 0, force: Bool = false) {
        loop?.cancel()
        loop = Task { [weak self] in
            if refreshFirst {
                if initialDelay > 0 {
                    do { try await Task.sleep(for: .seconds(initialDelay)) } catch { return }
                }
                await self?.runRefresh(force: force)
            }
            while !Task.isCancelled {
                guard let delay = self?.nextDelay() else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                await self?.runRefresh(force: false)
            }
        }
    }

    /// A leitura roda numa tarefa própria: cancelar o laço não interrompe uma requisição em andamento.
    private func runRefresh(force: Bool) async {
        guard let engine else { return }
        await Task { await engine.refresh(force: force) }.value
    }
}
