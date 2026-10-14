import Foundation
@testable import WindFreeKit

/// Status fictício no formato da API. Valores e identificadores são inventados.
enum Fixtures {
    static let statusJSON = """
    {
      "components": {
        "main": {
          "switch": { "switch": { "value": "on", "timestamp": "2026-01-01T00:00:00Z" } },
          "thermostatCoolingSetpoint": { "coolingSetpoint": { "value": 21, "unit": "C" } },
          "custom.thermostatSetpointControl": {
            "minimumSetpoint": { "value": 16, "unit": "C" },
            "maximumSetpoint": { "value": 30, "unit": "C" }
          },
          "temperatureMeasurement": { "temperature": { "value": 26, "unit": "C" } },
          "relativeHumidityMeasurement": { "humidity": { "value": 61, "unit": "%" } },
          "airConditionerMode": {
            "airConditionerMode": { "value": "cool" },
            "supportedAcModes": { "value": ["cool", "dry", "wind", "auto"] }
          },
          "airConditionerFanMode": {
            "fanMode": { "value": "auto" },
            "supportedAcFanModes": { "value": ["auto", "low", "medium", "high", "turbo"] }
          },
          "fanOscillationMode": {
            "fanOscillationMode": { "value": "vertical" },
            "supportedFanOscillationModes": { "value": ["fixed", "vertical", "horizontal", "all"] }
          },
          "custom.airConditionerOptionalMode": {
            "acOptionalMode": { "value": "windFreeSleep" },
            "supportedAcOptionalMode": { "value": ["off", "windFree", "sleep", "windFreeSleep", "speed"] }
          },
          "samsungce.airConditionerLighting": { "lighting": { "value": "on" } },
          "execute": { "data": { "value": { "payload": {} } } },
          "audioVolume": { "volume": { "value": 0, "unit": "%" } },
          "custom.autoCleaningMode": { "autoCleaningMode": { "value": "on" } },
          "custom.dustFilter": {
            "dustFilterUsage": { "value": 17 },
            "dustFilterStatus": { "value": "normal" }
          },
          "samsungce.dustFilterAlarm": {
            "alarmThreshold": { "value": 300, "unit": "Hour" },
            "supportedAlarmThresholds": { "value": [180, 300, 500, 700], "unit": "Hour" }
          },
          "powerConsumptionReport": {
            "powerConsumption": { "value": { "energy": 676400, "power": 640, "deltaEnergy": 12 } }
          },
          "custom.disabledCapabilities": {
            "disabledCapabilities": { "value": ["samsungce.airConditionerLighting", "custom.airConditionerTropicalNightMode"] }
          },
          "ocf": {
            "di": { "value": "00000000-1111-2222-3333-444444444444" },
            "n": { "value": "Nome pessoal" },
            "mnmo": { "value": "MODELO-FICTICIO" }
          }
        }
      }
    }
    """

    static func status(_ json: String = statusJSON) throws -> DeviceStatus {
        DeviceStatus(json: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    /// Status mínimo montado a partir de um estado, para o aparelho falso dos testes.
    static func status(for state: ACState, supportedModes: [String] = ["cool", "dry", "wind", "auto"]) -> DeviceStatus {
        var main: [String: [String: AttributeState]] = [:]
        func set(_ capability: String, _ attribute: String, _ value: JSONValue?, unit: String? = nil) {
            main[capability, default: [:]][attribute] = AttributeState(value: value ?? .null, unit: unit)
        }
        set(Capability.switchCapability, "switch", .string(state.isOn == true ? "on" : "off"))
        set(Capability.coolingSetpoint, "coolingSetpoint", state.targetTemperature.map(JSONValue.number), unit: "C")
        set(Capability.airConditionerMode, "airConditionerMode", state.mode.map(JSONValue.string))
        set(Capability.airConditionerMode, "supportedAcModes", .array(supportedModes.map(JSONValue.string)))
        set(Capability.fanMode, "fanMode", state.fanMode.map(JSONValue.string))
        set(Capability.fanMode, "supportedAcFanModes", ["auto", "low", "high"])
        set(Capability.optionalMode, "acOptionalMode", state.optionalMode.map(JSONValue.string))
        set(Capability.optionalMode, "supportedAcOptionalMode", ["off", "windFree", "sleep"])
        set(Capability.dustFilter, "dustFilterUsage", state.filterUsage.map(JSONValue.number))
        return DeviceStatus(components: ["main": main])
    }
}

/// Aparelho falso controlável, que registra cada chamada.
actor FakeAPI: SmartThingsAPI {
    var state: ACState
    var health: DeviceHealth = .online
    /// Ajustes que o aparelho aceita mas não aplica.
    var ignored: Set<ACSetting> = []
    /// Ignora ajustes de clima com o ar desligado.
    var ignoresClimateWhileOff = true
    var rejectAll = false
    var statusErrors: [SmartThingsError] = []
    var executeErrors: [SmartThingsError] = []
    var latency: Duration = .milliseconds(5)

    private(set) var executed: [[DeviceCommand]] = []
    private(set) var statusReads = 0
    private(set) var healthReads = 0
    private var concurrent = 0
    private(set) var maxConcurrent = 0

    init(state: ACState) {
        self.state = state
    }

    func configure(_ change: (FakeAPI) -> Void) { change(self) }
    func setIgnored(_ settings: Set<ACSetting>) { ignored = settings }
    func setState(_ newState: ACState) { state = newState }
    func setHealth(_ newHealth: DeviceHealth) { health = newHealth }
    func setRejectAll(_ value: Bool) { rejectAll = value }
    func queueStatusError(_ error: SmartThingsError) { statusErrors.append(error) }
    func queueExecuteError(_ error: SmartThingsError) { executeErrors.append(error) }
    func setLatency(_ value: Duration) { latency = value }

    var allCommands: [DeviceCommand] { executed.flatMap { $0 } }

    func listDevices() async throws -> [DeviceSummary] { [] }

    func rooms(locationID: String) async throws -> [Room] { [] }

    func status(deviceID: String) async throws -> DeviceStatus {
        try await track {
            statusReads += 1
            if !statusErrors.isEmpty { throw statusErrors.removeFirst() }
            return Fixtures.status(for: state)
        }
    }

    func health(deviceID: String) async throws -> DeviceHealth {
        healthReads += 1
        return health
    }

    func execute(deviceID: String, commands: [DeviceCommand]) async throws -> Bool {
        try await track {
            if !executeErrors.isEmpty { throw executeErrors.removeFirst() }
            executed.append(commands)
            if rejectAll { return false }
            for command in commands {
                if command.command == "resetDustFilter" { state.filterUsage = 0 }
                guard let (setting, value) = SimulatedSmartThings.decode(command) else { continue }
                if ignored.contains(setting) { continue }
                if ignoresClimateWhileOff, ACSetting.climate.contains(setting), state.isOn != true { continue }
                state.apply(value, for: setting)
            }
            return true
        }
    }

    private func track<T: Sendable>(_ body: () throws -> T) async throws -> T {
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        defer { concurrent -= 1 }
        try await Task.sleep(for: latency)
        return try body()
    }
}

extension ACState {
    static func sample(on: Bool = true) -> ACState {
        var state = ACState()
        state.isOn = on
        state.targetTemperature = 22
        state.mode = "cool"
        state.fanMode = "auto"
        state.optionalMode = "off"
        state.filterUsage = 40
        return state
    }
}

extension ACSyncEngine.Configuration {
    static var fast: Self {
        var configuration = Self()
        configuration.debounce = .milliseconds(60)
        configuration.firstConfirmDelay = .milliseconds(5)
        configuration.confirmInterval = .milliseconds(5)
        configuration.postPowerOnDelay = .zero
        return configuration
    }
}

/// Espera até a condição ser verdadeira ou o tempo acabar.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
