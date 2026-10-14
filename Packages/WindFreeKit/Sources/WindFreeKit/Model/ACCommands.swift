import Foundation

/// Ações pontuais (não são estados que se mantêm).
public enum ACAction: Sendable, Hashable {
    case resetFilter
}

/// Converte ajustes em comandos SmartThings.
public enum ACCommandBuilder {
    public static func commands(for setting: ACSetting, value: ACValue,
                                capabilities caps: ACCapabilities = ACCapabilities()) -> [DeviceCommand]
    {
        switch (setting, value) {
        case (.power, .bool(let on)):
            return [DeviceCommand(capability: Capability.switchCapability, command: on ? "on" : "off")]
        case (.targetTemperature, .number(let temperature)):
            return [DeviceCommand(capability: Capability.coolingSetpoint, command: "setCoolingSetpoint",
                                  arguments: [.number(temperature)])]
        case (.mode, .text(let mode)):
            return [DeviceCommand(capability: Capability.airConditionerMode, command: "setAirConditionerMode",
                                  arguments: [.string(mode)])]
        case (.fanMode, .text(let fan)):
            return [DeviceCommand(capability: Capability.fanMode, command: "setFanMode", arguments: [.string(fan)])]
        case (.verticalAirflow, .text(let position)):
            return AirFlow.commands(axis: "Vertical", position: position)
        case (.horizontalAirflow, .text(let position)):
            return AirFlow.commands(axis: "Horizontal", position: position)
        case (.horizontalSwingRange, .text(let range)):
            return [DeviceCommand(capability: Capability.airFlowDirection, command: "setHorizontalSwingRange",
                                  arguments: [.string(range)])]
        case (.oscillation, .text(let mode)):
            return [DeviceCommand(capability: Capability.oscillation, command: "setFanOscillationMode",
                                  arguments: [.string(mode)])]
        case (.optionalMode, .text(let mode)):
            return [DeviceCommand(capability: Capability.optionalMode, command: "setAcOptionalMode",
                                  arguments: [.string(mode)])]
        case (.display, .bool(let on)) where caps.displayControl == .lightingLevel:
            return [DeviceCommand(capability: Capability.lighting, command: "setLightingLevel",
                                  arguments: [.string(on ? "on" : "off")])]
        case (.display, .bool(let on)):
            // Observado no projeto de referência: a capacidade de iluminação ignora comandos e a opção OCF
            // da Samsung é invertida ("Light_On" apaga o display). Precisa ser confirmado em cada aparelho.
            let option = on ? "Light_Off" : "Light_On"
            return [DeviceCommand(capability: Capability.execute, command: "execute",
                                  arguments: ["mode/vs/0", ["x.com.samsung.da.options": [.string(option)]]])]
        case (.beep, .bool(let on)) where caps.beepControl == .beepSwitch:
            return [DeviceCommand(capability: Capability.beep, command: on ? "on" : "off")]
        case (.beep, .bool(let on)):
            return [DeviceCommand(capability: Capability.audioVolume, command: "setVolume",
                                  arguments: [.number(on ? 100 : 0)])]
        case (.autoClean, .bool(let on)):
            return [DeviceCommand(capability: Capability.autoCleaning, command: "setAutoCleaningMode",
                                  arguments: [.string(on ? "on" : "off")])]
        case (.filterAlarmThreshold, .number(let hours)):
            return [DeviceCommand(capability: Capability.dustFilterAlarm, command: "setAlarmThreshold",
                                  arguments: [.number(hours)])]
        default:
            return []
        }
    }

    public static func commands(for action: ACAction) -> [DeviceCommand] {
        switch action {
        case .resetFilter:
            [DeviceCommand(capability: Capability.dustFilter, command: "resetDustFilter")]
        }
    }

    /// Etapas de envio: ligar vem antes dos demais ajustes e desligar vem por último,
    /// para que o aparelho não descarte ajustes enviados enquanto ainda está desligado.
    public static func steps(for changes: [ACSetting: ACValue],
                             capabilities caps: ACCapabilities = ACCapabilities()) -> [Step]
    {
        var steps: [Step] = []
        if let power = changes[.power], power == .bool(true) {
            steps.append(Step(settings: [.power], commands: commands(for: .power, value: power), isPowerOn: true))
        }
        for setting in changes.keys.sorted() where setting != .power {
            let built = commands(for: setting, value: changes[setting]!, capabilities: caps)
            if !built.isEmpty { steps.append(Step(settings: [setting], commands: built, isPowerOn: false)) }
        }
        if let power = changes[.power], power == .bool(false) {
            steps.append(Step(settings: [.power], commands: commands(for: .power, value: power), isPowerOn: false))
        }
        return steps
    }

    public struct Step: Sendable, Hashable {
        public var settings: [ACSetting]
        public var commands: [DeviceCommand]
        public var isPowerOn: Bool
    }
}
