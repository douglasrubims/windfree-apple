import Foundation
import Testing
@testable import WindFreeKit

@MainActor
@Suite("Fila de comandos, agrupamento e confirmação")
struct SyncEngineTests {
    func makeEngine(_ state: ACState = .sample()) async -> (ACSyncEngine, FakeAPI) {
        let api = FakeAPI(state: state)
        let engine = ACSyncEngine(deviceID: "test", api: api, configuration: .fast)
        await engine.refresh()
        return (engine, api)
    }

    func settled(_ engine: ACSyncEngine) async -> Bool {
        await waitUntil { engine.activity == .idle && engine.sendable.isEmpty && engine.inflight.isEmpty }
    }

    @Test func refreshLoadsConfirmedState() async {
        let (engine, api) = await makeEngine()
        #expect(engine.confirmed?.targetTemperature == 22)
        #expect(engine.health == .online)
        #expect(engine.issue == nil)
        #expect(await api.statusReads == 1)
    }

    @Test func rapidTapsBecomeOneCommand() async {
        let (engine, api) = await makeEngine()
        for temperature in [23.0, 24, 25, 26, 25] {
            engine.request(.targetTemperature, .number(temperature))
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.displayed?.targetTemperature == 25)
        #expect(engine.isAwaiting(.targetTemperature))
        #expect(await settled(engine))

        let commands = await api.allCommands
        #expect(commands.count == 1)
        #expect(commands.first?.arguments == [.number(25)])
        #expect(engine.confirmed?.targetTemperature == 25)
        #expect(!engine.isAwaiting(.targetTemperature))
        #expect(engine.unconfirmed.isEmpty)
    }

    @Test func requestEqualToConfirmedSendsNothing() async {
        let (engine, api) = await makeEngine()
        engine.request(.targetTemperature, .number(23))
        engine.request(.targetTemperature, .number(22))
        #expect(engine.pending.isEmpty)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await api.executed.isEmpty)
    }

    @Test func distinguishesRequestedFromConfirmed() async {
        let (engine, api) = await makeEngine()
        await api.setLatency(.milliseconds(40))
        engine.request(.mode, .text("dry"))
        #expect(engine.pending[.mode] == .text("dry"))
        #expect(engine.confirmed?.mode == "cool")
        #expect(engine.displayed?.mode == "dry")
        #expect(await waitUntil { engine.inflight[.mode] != nil })
        #expect(engine.confirmed?.mode == "cool")
        #expect(engine.isSyncing)
        #expect(await settled(engine))
        #expect(engine.confirmed?.mode == "dry")
        #expect(!engine.isSyncing)
    }

    @Test func climateIsHeldWhileOffAndAppliedOnPowerOn() async {
        let (engine, api) = await makeEngine(.sample(on: false))
        engine.request(.targetTemperature, .number(19))
        engine.request(.fanMode, .text("high"))
        engine.request(.beep, .bool(true))
        #expect(engine.held == [.targetTemperature, .fanMode])
        #expect(engine.displayed?.targetTemperature == 19)
        #expect(await settled(engine))

        // Só o bipe saiu; o clima continua retido.
        #expect(await api.allCommands.map(\.capability) == ["audioVolume"])
        #expect(engine.held == [.targetTemperature, .fanMode])

        engine.request(.power, .bool(true))
        #expect(engine.held.isEmpty)
        #expect(await settled(engine))
        let batch = await api.executed.dropFirst().map { $0.map(\.command) }
        #expect(batch == [["on"], ["setCoolingSetpoint"], ["setFanMode"]])
        #expect(engine.confirmed?.isOn == true)
        #expect(engine.confirmed?.targetTemperature == 19)
        #expect(engine.confirmed?.fanMode == "high")
        #expect(engine.pending.isEmpty)
    }

    @Test func heldSettingsFlushWhenTurnedOnElsewhere() async {
        let (engine, api) = await makeEngine(.sample(on: false))
        engine.request(.mode, .text("dry"))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await api.executed.isEmpty)

        var on = await api.state
        on.isOn = true
        await api.setState(on)
        await engine.refresh()
        #expect(await settled(engine))
        #expect(await api.allCommands.map(\.command) == ["setAirConditionerMode"])
        #expect(engine.confirmed?.mode == "dry")
    }

    @Test func turningOffHoldsNewClimateChanges() async {
        let (engine, api) = await makeEngine()
        engine.request(.power, .bool(false))
        engine.request(.targetTemperature, .number(18))
        #expect(engine.held == [.targetTemperature])
        #expect(await settled(engine))
        #expect(await api.allCommands.map(\.command) == ["off"])
        #expect(engine.pending[.targetTemperature] == .number(18))
    }

    @Test func ignoredCommandIsReportedAsUnconfirmed() async {
        let (engine, api) = await makeEngine()
        await api.setIgnored([.optionalMode])
        engine.request(.optionalMode, .text("windFree"))
        engine.request(.fanMode, .text("low"))
        #expect(await settled(engine))
        #expect(engine.unconfirmed == [.optionalMode])
        #expect(engine.issue == .unconfirmed([.optionalMode]))
        // Volta a exibir o estado real.
        #expect(engine.displayed?.optionalMode == "off")
        #expect(engine.displayed?.fanMode == "low")
        // Confirmação limitada: 1 leitura inicial + 4 tentativas.
        #expect(await api.statusReads == 1 + ACSyncEngine.Configuration.fast.confirmAttempts)

        engine.request(.optionalMode, .text("off"))
        #expect(engine.issue == nil)
    }

    @Test func rejectedCommandIsReported() async {
        let (engine, api) = await makeEngine()
        await api.setRejectAll(true)
        engine.request(.fanMode, .text("low"))
        #expect(await settled(engine))
        #expect(engine.issue == .rejected([.fanMode]))
        #expect(await api.statusReads == 1)
    }

    @Test func overlappingRefreshesAreSkipped() async {
        let (engine, api) = await makeEngine()
        await api.setLatency(.milliseconds(50))
        async let first: Void = engine.refresh()
        async let second: Void = engine.refresh()
        async let third: Void = engine.refresh()
        _ = await (first, second, third)
        #expect(await api.statusReads == 2)
        #expect(await api.maxConcurrent == 1)
    }

    @Test func requestsDuringSendGoInNextBatch() async {
        let (engine, api) = await makeEngine()
        await api.setLatency(.milliseconds(40))
        engine.request(.targetTemperature, .number(24))
        #expect(await waitUntil { engine.activity == .sending })
        engine.request(.targetTemperature, .number(26))
        #expect(engine.displayed?.targetTemperature == 26)
        #expect(await settled(engine))
        let sent = await api.allCommands.map { $0.arguments }
        #expect(sent == [[.number(24)], [.number(26)]])
        #expect(engine.confirmed?.targetTemperature == 26)
        #expect(await api.maxConcurrent == 1)
    }

    @Test func refreshDuringSendIsSkipped() async {
        let (engine, api) = await makeEngine()
        await api.setLatency(.milliseconds(40))
        engine.request(.mode, .text("auto"))
        #expect(await waitUntil { engine.activity == .sending })
        let readsBefore = await api.statusReads
        await engine.refresh()
        #expect(await api.statusReads == readsBefore)
    }

    @Test func unauthorizedMarksSessionExpired() async {
        let (engine, api) = await makeEngine()
        await api.queueStatusError(.unauthorized)
        await engine.refresh()
        #expect(engine.issue == .sessionExpired)
        #expect(engine.issue?.blocksPolling == true)
        await engine.refresh()
        #expect(engine.issue == nil)
    }

    @Test func rateLimitDefersRefreshAndCommands() async {
        let (engine, api) = await makeEngine()
        await api.queueStatusError(.rateLimited(retryAfter: 30))
        await engine.refresh()
        guard case .rateLimited = engine.issue else {
            Issue.record("esperava limite de consultas")
            return
        }
        #expect(engine.retryNotBefore != nil)
        let reads = await api.statusReads
        await engine.refresh()
        #expect(await api.statusReads == reads)

        engine.request(.fanMode, .text("high"))
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await api.executed.isEmpty)
        #expect(engine.pending[.fanMode] != nil)
    }

    @Test func networkFailuresIncreaseBackoffAndRecover() async {
        let (engine, api) = await makeEngine()
        await api.queueStatusError(.timedOut)
        await api.queueStatusError(.offlineNetwork)
        await engine.refresh()
        await engine.refresh()
        #expect(engine.consecutiveFailures == 2)
        #expect(engine.issue == .failure(.offlineNetwork))
        await engine.refresh()
        #expect(engine.consecutiveFailures == 0)
        #expect(engine.issue == nil)
    }

    @Test func commandFailureDropsInflightAndReports() async {
        let (engine, api) = await makeEngine()
        await api.queueExecuteError(.timedOut)
        engine.request(.fanMode, .text("high"))
        #expect(await settled(engine))
        #expect(engine.issue == .failure(.timedOut))
        #expect(engine.displayed?.fanMode == "auto")
        #expect(engine.inflight.isEmpty)
    }

    @Test func offlineDeviceKeepsRequestsPending() async {
        let api = FakeAPI(state: .sample())
        await api.setHealth(.offline)
        let engine = ACSyncEngine(deviceID: "test", api: api, configuration: .fast)
        await engine.refresh()
        #expect(engine.issue == .deviceOffline)
        engine.request(.fanMode, .text("high"))
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await api.executed.isEmpty)
        #expect(engine.pending[.fanMode] == .text("high"))

        await api.setHealth(.online)
        await engine.refresh()
        #expect(engine.issue == nil)
        #expect(await settled(engine))
        #expect(engine.confirmed?.fanMode == "high")
    }

    @Test func resetFilterIsConfirmed() async {
        let (engine, api) = await makeEngine()
        #expect(await engine.perform(.resetFilter))
        #expect(await api.allCommands.map(\.command) == ["resetDustFilter"])
        #expect(engine.confirmed?.filterUsage == 0)
    }

    @Test func endToEndWithSimulator() async {
        let api = SimulatedSmartThings(latency: .milliseconds(2))
        let engine = ACSyncEngine(deviceID: "sim-sala", api: api, configuration: .fast)
        await engine.refresh()
        #expect(engine.capabilities.supportsWindFree)
        #expect(engine.capabilities.display)
        engine.request(.targetTemperature, .number(20))
        engine.request(.mode, .text("dry"))
        #expect(await settled(engine))
        #expect(engine.confirmed?.targetTemperature == 20)
        #expect(engine.confirmed?.mode == "dry")

        // O simulador só aceita WindFree no modo resfriar.
        engine.request(.optionalMode, .text("windFree"))
        #expect(await settled(engine))
        #expect(engine.unconfirmed == [.optionalMode])
    }
}

@Suite("Política de consultas")
struct PollingPolicyTests {
    let policy = PollingPolicy()
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func visibleIsMoreFrequentThanHidden() {
        let visible = policy.delay(panelVisible: true, lowPower: false, consecutiveFailures: 0, retryNotBefore: nil,
                                   issue: nil, now: now)
        let hidden = policy.delay(panelVisible: false, lowPower: false, consecutiveFailures: 0, retryNotBefore: nil,
                                  issue: nil, now: now)
        let lowPower = policy.delay(panelVisible: false, lowPower: true, consecutiveFailures: 0, retryNotBefore: nil,
                                    issue: nil, now: now)
        #expect(visible == 15)
        #expect(hidden == 120)
        #expect(lowPower == 300)
    }

    @Test func backoffGrowsAndIsCapped() {
        let delays = (0...6).map {
            policy.delay(panelVisible: true, lowPower: false, consecutiveFailures: $0, retryNotBefore: nil,
                         issue: nil, now: now)!
        }
        #expect(delays == [15, 30, 60, 120, 240, 480, 600])
    }

    @Test func respectsRateLimit() {
        let delay = policy.delay(panelVisible: true, lowPower: false, consecutiveFailures: 0,
                                 retryNotBefore: now.addingTimeInterval(90), issue: nil, now: now)
        #expect(delay == 90)
    }

    @Test func stopsWithoutValidSession() {
        #expect(policy.delay(panelVisible: true, lowPower: false, consecutiveFailures: 0, retryNotBefore: nil,
                             issue: .sessionExpired, now: now) == nil)
    }
}

@MainActor
@Suite("Agendamento de consultas")
struct RefreshSchedulerTests {
    @Test func openingPanelRefreshesStaleDataOnce() async {
        let api = FakeAPI(state: .sample())
        let engine = ACSyncEngine(deviceID: "test", api: api, configuration: .fast)
        let scheduler = RefreshScheduler(engine: engine)
        scheduler.start()
        #expect(await waitUntil { engine.isLoaded })
        #expect(await api.statusReads == 1)

        // Dados recentes: abrir o painel não gera consulta extra.
        scheduler.setPanelVisible(true)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(await api.statusReads == 1)

        scheduler.setPanelVisible(false)
        var policy = PollingPolicy()
        policy.staleAfter = 0
        scheduler.policy = policy
        scheduler.setPanelVisible(true)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(await api.statusReads == 2)
        scheduler.stop()
    }

    @Test func wakeResumesStoppedScheduler() async {
        let api = FakeAPI(state: .sample())
        let engine = ACSyncEngine(deviceID: "test", api: api, configuration: .fast)
        let scheduler = RefreshScheduler(engine: engine)
        #expect(!scheduler.isRunning) // parado, como depois de `willSleep`
        let woke = ContinuousClock.now
        scheduler.systemDidWake()
        #expect(scheduler.isRunning)
        // A leitura acontece só depois da espera para a rede voltar (3 s).
        try? await Task.sleep(for: .seconds(1))
        #expect(await api.statusReads == 0)
        #expect(await waitUntil(timeout: .seconds(6)) { engine.isLoaded })
        #expect(ContinuousClock.now - woke >= .seconds(3))
        #expect(await api.statusReads == 1)
        scheduler.stop()
    }

    @Test func expiredSessionStopsPolling() async {
        let api = FakeAPI(state: .sample())
        await api.queueStatusError(.unauthorized)
        let engine = ACSyncEngine(deviceID: "test", api: api, configuration: .fast)
        var policy = PollingPolicy()
        policy.visibleInterval = 0.02
        let scheduler = RefreshScheduler(engine: engine, policy: policy)
        scheduler.setPanelVisible(true)
        scheduler.start()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(engine.issue == .sessionExpired)
        #expect(await api.statusReads == 1)
        scheduler.stop()
    }
}
