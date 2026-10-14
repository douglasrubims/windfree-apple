import Foundation

/// Traduz o status bruto do SmartThings em estado e capacidades do ar-condicionado.
///
/// Modelos diferentes expõem o mesmo recurso por capacidades diferentes. Exemplo verificado num WindFree
/// 2026: `fanOscillationMode` vem desativada e a direção do vento usa `samsungce.airConditionerAirFlowDirection`;
/// a iluminação do display está ativa e aceita `setLightingLevel`; o bipe tem capacidade própria.
public enum ACInterpreter {
    public static func state(from status: DeviceStatus) -> ACState {
        let caps = capabilities(from: status)
        var state = ACState()
        if let value = status.value(Capability.switchCapability, "switch")?.stringValue {
            state.isOn = value == "on"
        }
        if let setpoint = status[Capability.coolingSetpoint, "coolingSetpoint"] {
            state.targetTemperature = setpoint.value?.doubleValue
            state.temperatureUnit = unit(setpoint.unit) ?? .celsius
        }
        state.ambientTemperature = status.value(Capability.temperature, "temperature")?.doubleValue
        state.humidity = status.value(Capability.humidity, "humidity")?.doubleValue
        state.mode = status.value(Capability.airConditionerMode, "airConditionerMode")?.stringValue
        state.fanMode = status.value(Capability.fanMode, "fanMode")?.stringValue
        if !caps.oscillationModes.isEmpty {
            state.oscillation = status.value(Capability.oscillation, "fanOscillationMode")?.stringValue
        }
        if !caps.verticalAirflowOptions.isEmpty {
            state.verticalAirflow = AirFlow.position(
                direction: status.value(Capability.airFlowDirection, "verticalDirection")?.stringValue,
                step: status.value(Capability.airFlowDirection, "verticalAngleStep")?.stringValue
            )
        }
        if !caps.horizontalAirflowOptions.isEmpty {
            state.horizontalAirflow = AirFlow.position(
                direction: status.value(Capability.airFlowDirection, "horizontalDirection")?.stringValue,
                step: status.value(Capability.airFlowDirection, "horizontalAngleStep")?.stringValue
            )
        }
        state.verticalStepHint = status.value(Capability.airFlowDirection, "verticalAngleStep")?.stringValue
            .flatMap { Int($0) }
        state.horizontalStepHint = status.value(Capability.airFlowDirection, "horizontalAngleStep")?.stringValue
            .flatMap { Int($0) }
        if !caps.horizontalSwingRanges.isEmpty {
            state.horizontalSwingRange = status.value(Capability.airFlowDirection, "horizontalSwingRange")?.stringValue
        }
        state.optionalMode = status.value(Capability.optionalMode, "acOptionalMode")?.stringValue
        if let lighting = status.value(Capability.lighting, "lighting")?.stringValue {
            state.displayOn = lighting == "on"
        }
        switch caps.beepControl {
        case .beepSwitch:
            state.beepOn = status.value(Capability.beep, "beep")?.stringValue.map { $0 == "on" }
        case .volume:
            state.beepOn = status.value(Capability.audioVolume, "volume")?.doubleValue.map { $0 > 0 }
        }
        if let autoClean = status.value(Capability.autoCleaning, "autoCleaningMode")?.stringValue {
            state.autoCleanOn = autoClean == "on"
        }
        state.filterUsage = status.value(Capability.dustFilter, "dustFilterUsage")?.doubleValue
        state.filterStatus = status.value(Capability.dustFilter, "dustFilterStatus")?.stringValue
        state.filterAlarmThreshold = status.value(Capability.dustFilterAlarm, "alarmThreshold")?.doubleValue
        if let report = status.value(Capability.powerReport, "powerConsumption") {
            state.powerWatts = report["power"]?.doubleValue
            state.energyKWh = report["energy"]?.doubleValue.map { $0 / 1000 }
            state.averagePowerWatts = averagePower(report)
        }
        return state
    }

    public static func capabilities(from status: DeviceStatus) -> ACCapabilities {
        let present = status.mainCapabilities
        let disabled = Set(status.value(Capability.disabledCapabilities, "disabledCapabilities")?.stringArray ?? [])
        let unavailableCommands = Set(
            status.value(Capability.unavailableCapabilities, "unavailableCommands")?.stringArray ?? []
        )
        func available(_ capability: String) -> Bool {
            present.contains(capability) && !disabled.contains(capability)
        }
        func canSend(_ capability: String, _ command: String) -> Bool {
            available(capability) && !unavailableCommands.contains("\(capability).\(command)")
        }

        var caps = ACCapabilities()
        caps.power = available(Capability.switchCapability)
        if available(Capability.coolingSetpoint) {
            caps.targetTemperature = temperatureRange(from: status)
        }
        if available(Capability.airConditionerMode) {
            caps.modes = status.value(Capability.airConditionerMode, "supportedAcModes")?.stringArray ?? []
        }
        if available(Capability.fanMode) {
            caps.fanModes = status.value(Capability.fanMode, "supportedAcFanModes")?.stringArray
                ?? status.value(Capability.fanMode, "availableAcFanModes")?.stringArray ?? []
        }

        // Direção: a capacidade padrão quando ativa; senão, as pás de `samsungce.airConditionerAirFlowDirection`
        // (oscilação ou posição exata, vertical e lateral), como no app SmartThings.
        if available(Capability.oscillation) {
            caps.oscillationModes = status.value(Capability.oscillation, "supportedFanOscillationModes")?.stringArray
                ?? status.value(Capability.oscillation, "availableFanOscillationModes")?.stringArray ?? []
        }
        if caps.oscillationModes.isEmpty, available(Capability.airFlowDirection) {
            func options(_ axis: String) -> [String] {
                let directions = status.value(Capability.airFlowDirection, "supported\(axis)Directions")?.stringArray ?? []
                let steps = status.value(Capability.airFlowDirection, "supported\(axis)AngleSteps")?.stringArray ?? []
                return AirFlow.options(
                    directions: canSend(Capability.airFlowDirection, "set\(axis)Direction") ? directions : [],
                    steps: canSend(Capability.airFlowDirection, "set\(axis)AngleStep") ? steps : []
                )
            }
            caps.verticalAirflowOptions = options("Vertical")
            caps.horizontalAirflowOptions = options("Horizontal")
            if caps.horizontalAirflowOptions.contains(AirFlow.swing),
               canSend(Capability.airFlowDirection, "setHorizontalSwingRange")
            {
                let ranges = status.value(Capability.airFlowDirection, "supportedHorizontalSwingRanges")?.stringArray ?? []
                caps.horizontalSwingRanges = ranges.count > 1 ? ranges : []
            }
        }

        if available(Capability.optionalMode) {
            caps.optionalModes = status.value(Capability.optionalMode, "supportedAcOptionalMode")?.stringArray ?? []
        }
        caps.ambientTemperature = available(Capability.temperature)
            && status.value(Capability.temperature, "temperature") != nil
        caps.humidity = available(Capability.humidity) && status.value(Capability.humidity, "humidity") != nil

        // Display: comando próprio quando a capacidade está ativa. No aparelho do projeto de referência ela
        // vinha desativada e só o comando `execute` (com a opção invertida) funcionava.
        let lightingLevels = status.value(Capability.lighting, "supportedLightingLevels")?.stringArray ?? []
        if status.value(Capability.lighting, "lighting") != nil {
            if canSend(Capability.lighting, "setLightingLevel"), lightingLevels.isEmpty
                || (lightingLevels.contains("on") && lightingLevels.contains("off"))
            {
                caps.display = true
                caps.displayControl = .lightingLevel
            } else if available(Capability.execute) {
                caps.display = true
                caps.displayControl = .samsungExecute
            }
        }

        if available(Capability.beep), status.value(Capability.beep, "beep") != nil {
            caps.beep = true
            caps.beepControl = .beepSwitch
        } else if available(Capability.audioVolume), status.value(Capability.audioVolume, "volume") != nil {
            caps.beep = true
            caps.beepControl = .volume
        }

        caps.autoClean = available(Capability.autoCleaning)
            && status.value(Capability.autoCleaning, "autoCleaningMode") != nil
        caps.filter = available(Capability.dustFilter) && status.value(Capability.dustFilter, "dustFilterUsage") != nil
        caps.filterReset = caps.filter && canSend(Capability.dustFilter, "resetDustFilter")
        if available(Capability.dustFilterAlarm) {
            caps.filterAlarmThresholds = status.value(Capability.dustFilterAlarm, "supportedAlarmThresholds")?
                .arrayValue?.compactMap(\.doubleValue) ?? []
        }
        caps.energy = available(Capability.powerReport)
            && status.value(Capability.powerReport, "powerConsumption")?["power"] != nil
        return caps
    }

    static func unit(_ raw: String?) -> TemperatureUnit? {
        guard let raw else { return nil }
        return TemperatureUnit(rawValue: raw.uppercased())
    }

    /// `deltaEnergy` (Wh) dividido pela duração da janela do relatório.
    static func averagePower(_ report: JSONValue) -> Double? {
        guard let delta = report["deltaEnergy"]?.doubleValue,
              let start = report["start"]?.stringValue.flatMap(parseDate),
              let end = report["end"]?.stringValue.flatMap(parseDate)
        else { return nil }
        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0, delta >= 0 else { return nil }
        return delta / hours
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    static func temperatureRange(from status: DeviceStatus) -> TemperatureRange {
        let unit = unit(status[Capability.coolingSetpoint, "coolingSetpoint"]?.unit) ?? .celsius
        if let range = status.value(Capability.coolingSetpoint, "coolingSetpointRange"),
           let minimum = range["minimum"]?.doubleValue, let maximum = range["maximum"]?.doubleValue,
           minimum < maximum
        {
            return TemperatureRange(minimum: minimum, maximum: maximum, step: range["step"]?.doubleValue ?? 1)
        }
        if let minimum = status.value(Capability.setpointControl, "minimumSetpoint")?.doubleValue,
           let maximum = status.value(Capability.setpointControl, "maximumSetpoint")?.doubleValue,
           minimum < maximum
        {
            return TemperatureRange(minimum: minimum, maximum: maximum)
        }
        // Sem limites declarados: faixa genérica, sinalizada como suposta.
        return unit == .celsius
            ? TemperatureRange(minimum: 16, maximum: 30, isAssumed: true)
            : TemperatureRange(minimum: 60, maximum: 86, isAssumed: true)
    }
}

/// Pás de `samsungce.airConditionerAirFlowDirection`. No app, cada eixo é `swing` (oscilar), uma posição fixa
/// (`"1"`…`"6"`, os passos declarados pelo aparelho) ou `fixed` se o aparelho não declarar posições.
public enum AirFlow {
    public static let swing = "swing"
    public static let fixed = "fixed"

    static func options(directions: [String], steps: [String]) -> [String] {
        var result: [String] = []
        if directions.contains(swing) { result.append(swing) }
        if directions.contains(fixed) {
            result.append(contentsOf: steps.isEmpty ? [fixed] : steps)
        }
        // Só faz sentido oferecer o controle se houver mais de uma opção.
        return result.count > 1 ? result : []
    }

    /// Posições numéricas entre as opções, em ordem (para o controle deslizante).
    public static func steps(in options: [String]) -> [Int] {
        options.compactMap { Int($0) }.sorted()
    }

    static func position(direction: String?, step: String?) -> String? {
        switch direction {
        case swing: swing
        case fixed: step ?? fixed
        default: nil
        }
    }

    /// Comandos para chegar a uma posição. A direção vai antes do passo, para parar a oscilação primeiro.
    static func commands(axis: String, position: String) -> [DeviceCommand] {
        let capability = Capability.airFlowDirection
        switch position {
        case swing, fixed:
            return [DeviceCommand(capability: capability, command: "set\(axis)Direction", arguments: [.string(position)])]
        default:
            return [
                DeviceCommand(capability: capability, command: "set\(axis)Direction", arguments: [.string(fixed)]),
                DeviceCommand(capability: capability, command: "set\(axis)AngleStep", arguments: [.string(position)]),
            ]
        }
    }
}
