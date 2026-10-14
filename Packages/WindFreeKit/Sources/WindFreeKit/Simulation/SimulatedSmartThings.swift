import Foundation

/// Conta SmartThings simulada, em memória, para desenvolver e verificar a interface sem rede.
///
/// Regras simuladas (inspiradas no comportamento descrito no projeto de referência, não validadas
/// em aparelho real):
/// - ajustes de clima enviados com o ar desligado são ignorados;
/// - o WindFree só é aceito no modo resfriar;
/// - os comandos aparecem no status depois de uma leitura, para exercitar a confirmação;
/// - um dos aparelhos fica offline.
public actor SimulatedSmartThings: SmartThingsAPI {
    public struct Profile: Sendable {
        var modes: [String]
        var fanModes: [String]
        var oscillationModes: [String]
        var optionalModes: [String]
        var range: (min: Double, max: Double)
        var declaresRangeAsSetpointControl: Bool
        var humidity: Bool
        var extras: Bool
        /// Como no WindFree 2026 validado: direção via `airConditionerAirFlowDirection`, bipe e display próprios.
        var samsung2026: Bool = false
    }

    struct SimDevice {
        var summary: DeviceSummary
        var profile: Profile
        var state: ACState
        var online: Bool
        var queued: [(setting: ACSetting, value: ACValue, readsLeft: Int)] = []
        var lastVerticalStep = "3"
        var lastHorizontalStep = "3"
    }

    private var devices: [String: SimDevice]
    private let order: [String]
    private let latency: Duration
    public private(set) var commandLog: [DeviceCommand] = []
    public private(set) var statusReads = 0

    public init(latency: Duration = .milliseconds(250)) {
        self.latency = latency
        let full = Profile(
            modes: ["auto", "cool", "dry", "fan", "heat"],
            fanModes: ["auto", "low", "medium", "high", "turbo"],
            oscillationModes: ["fixed", "vertical", "horizontal", "all"],
            optionalModes: ["off", "sleep", "quiet", "smart", "speed", "windFree", "windFreeSleep", "dryComfort"],
            range: (16, 30), declaresRangeAsSetpointControl: true, humidity: true, extras: true, samsung2026: true
        )
        let compact = Profile(
            modes: ["cool", "dry", "wind", "auto"],
            fanModes: ["auto", "low", "medium", "high"],
            oscillationModes: [],
            optionalModes: ["off", "windFree"],
            range: (18, 30), declaresRangeAsSetpointControl: false, humidity: false, extras: false
        )

        var sala = ACState()
        sala.isOn = true
        sala.targetTemperature = 22
        sala.ambientTemperature = 26.5
        sala.humidity = 61
        sala.mode = "cool"
        sala.fanMode = "auto"
        sala.verticalAirflow = "6"
        sala.horizontalAirflow = "2"
        sala.horizontalSwingRange = "all"
        sala.optionalMode = "off"
        sala.displayOn = true
        sala.beepOn = false
        sala.autoCleanOn = true
        sala.filterUsage = 17
        sala.filterStatus = "normal"
        sala.filterAlarmThreshold = 300
        sala.powerWatts = 640
        sala.energyKWh = 676.4

        var quarto = ACState()
        quarto.isOn = false
        quarto.targetTemperature = 24
        quarto.ambientTemperature = 27
        quarto.mode = "cool"
        quarto.fanMode = "low"
        quarto.optionalMode = "off"
        quarto.powerWatts = 0
        quarto.energyKWh = 212.9

        var escritorio = quarto
        escritorio.ambientTemperature = 25

        let ids = ["sim-sala", "sim-quarto", "sim-escritorio"]
        order = ids
        devices = [
            // Dois aparelhos com o mesmo nome em cômodos diferentes, como acontece em contas reais.
            ids[0]: SimDevice(summary: Self.summary(ids[0], "Ar da sala (simulado)", room: "sim-room-sala"),
                              profile: full, state: sala, online: true),
            ids[1]: SimDevice(summary: Self.summary(ids[1], "Ar condicionado (simulado)", room: "sim-room-quarto"),
                              profile: compact, state: quarto, online: true),
            ids[2]: SimDevice(summary: Self.summary(ids[2], "Ar condicionado (simulado)", room: "sim-room-escritorio"),
                              profile: compact, state: escritorio, online: false),
        ]
        devices[ids[0]]?.lastVerticalStep = sala.verticalAirflow ?? "3"
        devices[ids[0]]?.lastHorizontalStep = sala.horizontalAirflow ?? "3"
    }

    private static func summary(_ id: String, _ label: String, room: String) -> DeviceSummary {
        DeviceSummary(id: id, name: "Samsung Room A/C", label: label,
                      capabilityIDs: [Capability.switchCapability, Capability.airConditionerMode],
                      locationID: "sim-casa", roomID: room)
    }

    // MARK: - SmartThingsAPI

    public func listDevices() async throws -> [DeviceSummary] {
        try await Task.sleep(for: latency)
        return order.compactMap { devices[$0]?.summary }
    }

    public func rooms(locationID: String) async throws -> [Room] {
        try await Task.sleep(for: latency)
        return [Room(id: "sim-room-sala", name: "Sala"), Room(id: "sim-room-quarto", name: "Quarto"),
                Room(id: "sim-room-escritorio", name: "Escritório")]
    }

    public func status(deviceID: String) async throws -> DeviceStatus {
        try await Task.sleep(for: latency)
        guard var device = devices[deviceID] else { throw SmartThingsError.notFound }
        statusReads += 1
        // Aplica comandos cujo atraso terminou e simula a variação da temperatura ambiente.
        var remaining: [(setting: ACSetting, value: ACValue, readsLeft: Int)] = []
        for item in device.queued {
            if item.readsLeft <= 0 {
                device.state.apply(item.value, for: item.setting)
                if let step = item.value.text, step != AirFlow.swing {
                    if item.setting == .verticalAirflow { device.lastVerticalStep = step }
                    if item.setting == .horizontalAirflow { device.lastHorizontalStep = step }
                }
            } else {
                remaining.append((item.setting, item.value, item.readsLeft - 1))
            }
        }
        device.queued = remaining
        if device.online, device.state.isOn == true, let target = device.state.targetTemperature,
           let ambient = device.state.ambientTemperature, abs(ambient - target) > 0.2
        {
            device.state.ambientTemperature = ((ambient + (target > ambient ? 0.1 : -0.1)) * 10).rounded() / 10
        }
        devices[deviceID] = device
        return Self.status(for: device)
    }

    public func health(deviceID: String) async throws -> DeviceHealth {
        try await Task.sleep(for: latency)
        guard let device = devices[deviceID] else { throw SmartThingsError.notFound }
        return device.online ? .online : .offline
    }

    public func execute(deviceID: String, commands: [DeviceCommand]) async throws -> Bool {
        try await Task.sleep(for: latency)
        guard var device = devices[deviceID] else { throw SmartThingsError.notFound }
        commandLog.append(contentsOf: commands)
        guard device.online else { return true }
        for command in commands {
            // Pás: `setXDirection(fixed)` mantém a última posição; `setXAngleStep` define a posição.
            if command.capability == Capability.airFlowDirection, let argument = command.arguments.first?.stringValue {
                if command.command == "setHorizontalSwingRange" {
                    device.queued.append((.horizontalSwingRange, .text(argument), 1))
                    continue
                }
                let setting: ACSetting = command.command.contains("Vertical") ? .verticalAirflow : .horizontalAirflow
                if command.command.hasSuffix("AngleStep") {
                    device.queued.append((setting, .text(argument), 1))
                } else if argument == AirFlow.swing {
                    device.queued.append((setting, .text(AirFlow.swing), 1))
                } else if device.state.value(for: setting) == .text(AirFlow.swing) {
                    let last = setting == .verticalAirflow ? device.lastVerticalStep : device.lastHorizontalStep
                    device.queued.append((setting, .text(last), 1))
                }
                continue
            }
            guard let (setting, value) = Self.decode(command) else { return false }
            let isOn = device.state.isOn == true || device.queued.contains { $0.setting == .power && $0.value == .bool(true) }
            if ACSetting.climate.contains(setting), !isOn { continue }
            if setting == .optionalMode, OptionalMode.hasWindFree(value.text), device.state.mode != "cool" { continue }
            if setting == .targetTemperature, let temperature = value.number,
               temperature < device.profile.range.min || temperature > device.profile.range.max
            {
                continue
            }
            device.queued.append((setting, value, 1))
        }
        devices[deviceID] = device
        return true
    }

    // MARK: - Controle para testes

    public func setOnline(_ online: Bool, deviceID: String) {
        devices[deviceID]?.online = online
    }

    public func state(of deviceID: String) -> ACState? {
        devices[deviceID]?.state
    }

    // MARK: - Conversões

    static func decode(_ command: DeviceCommand) -> (ACSetting, ACValue)? {
        let argument = command.arguments.first
        switch (command.capability, command.command) {
        case (Capability.switchCapability, "on"): return (.power, .bool(true))
        case (Capability.switchCapability, "off"): return (.power, .bool(false))
        case (Capability.coolingSetpoint, _): return argument?.doubleValue.map { (.targetTemperature, .number($0)) }
        case (Capability.airConditionerMode, _): return argument?.stringValue.map { (.mode, .text($0)) }
        case (Capability.fanMode, _): return argument?.stringValue.map { (.fanMode, .text($0)) }
        case (Capability.oscillation, _): return argument?.stringValue.map { (.oscillation, .text($0)) }
        case (Capability.optionalMode, _): return argument?.stringValue.map { (.optionalMode, .text($0)) }
        case (Capability.audioVolume, _): return argument?.doubleValue.map { (.beep, .bool($0 > 0)) }
        case (Capability.beep, "on"): return (.beep, .bool(true))
        case (Capability.beep, "off"): return (.beep, .bool(false))
        case (Capability.lighting, "setLightingLevel"): return argument?.stringValue.map { (.display, .bool($0 == "on")) }
        case (Capability.autoCleaning, _): return argument?.stringValue.map { (.autoClean, .bool($0 == "on")) }
        case (Capability.dustFilterAlarm, _): return argument?.doubleValue.map { (.filterAlarmThreshold, .number($0)) }
        case (Capability.execute, _):
            let options = command.arguments.last?["x.com.samsung.da.options"]?.stringArray ?? []
            if options.contains("Light_Off") { return (.display, .bool(true)) }
            if options.contains("Light_On") { return (.display, .bool(false)) }
            return nil
        default: return nil
        }
    }

    static func status(for device: SimDevice) -> DeviceStatus {
        let state = device.state
        let profile = device.profile
        var main: [String: [String: AttributeState]] = [:]
        func set(_ capability: String, _ attribute: String, _ value: JSONValue?, unit: String? = nil) {
            main[capability, default: [:]][attribute] = AttributeState(value: value ?? .null, unit: unit)
        }
        set(Capability.switchCapability, "switch", .string(state.isOn == true ? "on" : "off"))
        set(Capability.coolingSetpoint, "coolingSetpoint", state.targetTemperature.map(JSONValue.number), unit: "C")
        if profile.declaresRangeAsSetpointControl {
            set(Capability.setpointControl, "minimumSetpoint", .number(profile.range.min), unit: "C")
            set(Capability.setpointControl, "maximumSetpoint", .number(profile.range.max), unit: "C")
        } else {
            set(Capability.coolingSetpoint, "coolingSetpointRange",
                ["minimum": .number(profile.range.min), "maximum": .number(profile.range.max), "step": 1], unit: "C")
        }
        set(Capability.temperature, "temperature", state.ambientTemperature.map(JSONValue.number), unit: "C")
        if profile.humidity {
            set(Capability.humidity, "humidity", state.humidity.map(JSONValue.number), unit: "%")
        }
        set(Capability.airConditionerMode, "airConditionerMode", state.mode.map(JSONValue.string))
        set(Capability.airConditionerMode, "supportedAcModes", .array(profile.modes.map(JSONValue.string)))
        set(Capability.fanMode, "fanMode", state.fanMode.map(JSONValue.string))
        set(Capability.fanMode, "supportedAcFanModes", .array(profile.fanModes.map(JSONValue.string)))
        if profile.samsung2026 {
            let vertical = state.verticalAirflow ?? "3"
            let horizontal = state.horizontalAirflow ?? "3"
            set(Capability.oscillation, "fanOscillationMode", nil)
            set(Capability.airFlowDirection, "verticalDirection", .string(vertical == AirFlow.swing ? AirFlow.swing : AirFlow.fixed))
            set(Capability.airFlowDirection, "verticalAngleStep", .string(vertical == AirFlow.swing ? device.lastVerticalStep : vertical))
            set(Capability.airFlowDirection, "horizontalDirection", .string(horizontal == AirFlow.swing ? AirFlow.swing : AirFlow.fixed))
            set(Capability.airFlowDirection, "horizontalAngleStep", .string(horizontal == AirFlow.swing ? device.lastHorizontalStep : horizontal))
            set(Capability.airFlowDirection, "horizontalSwingRange", .string(state.horizontalSwingRange ?? "all"))
            set(Capability.airFlowDirection, "supportedVerticalDirections", ["swing", "fixed"])
            set(Capability.airFlowDirection, "supportedHorizontalDirections", ["swing", "fixed"])
            set(Capability.airFlowDirection, "supportedVerticalAngleSteps", ["1", "2", "3", "4", "5", "6"])
            set(Capability.airFlowDirection, "supportedHorizontalAngleSteps", ["1", "2", "3", "4", "5"])
            set(Capability.airFlowDirection, "supportedHorizontalSwingRanges", ["all", "left", "right"])
        } else if !profile.oscillationModes.isEmpty {
            set(Capability.oscillation, "fanOscillationMode", state.oscillation.map(JSONValue.string))
            set(Capability.oscillation, "supportedFanOscillationModes",
                .array(profile.oscillationModes.map(JSONValue.string)))
        }
        set(Capability.optionalMode, "acOptionalMode", state.optionalMode.map(JSONValue.string))
        set(Capability.optionalMode, "supportedAcOptionalMode", .array(profile.optionalModes.map(JSONValue.string)))
        var disabled: [JSONValue] = []
        if profile.samsung2026 {
            disabled.append(.string(Capability.oscillation))
        }
        if profile.extras {
            set(Capability.lighting, "lighting", .string(state.displayOn == true ? "on" : "off"))
            if profile.samsung2026 {
                set(Capability.lighting, "supportedLightingLevels", ["on", "off"])
                set(Capability.beep, "beep", .string(state.beepOn == true ? "on" : "off"))
            } else {
                disabled.append(.string(Capability.lighting))
            }
            set(Capability.execute, "data", .object([:]))
            set(Capability.audioVolume, "volume", .number(state.beepOn == true ? 100 : 0), unit: "%")
            set(Capability.autoCleaning, "autoCleaningMode", .string(state.autoCleanOn == true ? "on" : "off"))
            set(Capability.dustFilter, "dustFilterUsage", state.filterUsage.map(JSONValue.number), unit: "%")
            set(Capability.dustFilter, "dustFilterStatus", state.filterStatus.map(JSONValue.string))
            set(Capability.dustFilterAlarm, "alarmThreshold", state.filterAlarmThreshold.map(JSONValue.number),
                unit: "Hour")
            set(Capability.dustFilterAlarm, "supportedAlarmThresholds", [180, 300, 500, 700], unit: "Hour")
        }
        // Como no aparelho real: potência instantânea zerada e energia da última janela em `deltaEnergy`.
        set(Capability.powerReport, "powerConsumption", [
            "power": 0,
            "energy": .number((state.energyKWh ?? 0) * 1000),
            "deltaEnergy": .number(state.isOn == true ? 140 : 0),
            "start": "2026-01-01T00:00:00Z",
            "end": "2026-01-01T00:15:00Z",
        ])
        set(Capability.disabledCapabilities, "disabledCapabilities", .array(disabled))
        return DeviceStatus(components: ["main": main])
    }
}
