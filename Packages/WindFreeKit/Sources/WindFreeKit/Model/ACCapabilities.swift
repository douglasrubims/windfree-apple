import Foundation

public struct TemperatureRange: Sendable, Hashable {
    public var minimum: Double
    public var maximum: Double
    public var step: Double
    /// `true` quando o aparelho não informou limites e usamos uma faixa genérica.
    public var isAssumed: Bool

    public init(minimum: Double, maximum: Double, step: Double = 1, isAssumed: Bool = false) {
        self.minimum = minimum
        self.maximum = maximum
        self.step = step > 0 ? step : 1
        self.isAssumed = isAssumed
    }

    public func clamp(_ value: Double) -> Double {
        let stepped = (value / step).rounded() * step
        return min(max(stepped, minimum), maximum)
    }
}

/// O que este aparelho realmente oferece, derivado do status. Nada aqui é fixo por modelo:
/// listas vazias significam que o aparelho não declarou opções.
public struct ACCapabilities: Sendable, Hashable {
    /// Como cada recurso é comandado. Modelos diferentes expõem o mesmo recurso por capacidades diferentes.
    public enum DisplayControl: Sendable, Hashable { case lightingLevel, samsungExecute }
    public enum BeepControl: Sendable, Hashable { case beepSwitch, volume }

    public var power = false
    public var targetTemperature: TemperatureRange?
    public var modes: [String] = []
    public var fanModes: [String] = []
    public var oscillationModes: [String] = []
    /// Opções das pás (`samsungce.airConditionerAirFlowDirection`): `swing`, posições `"1"`…, ou `fixed`
    /// quando o aparelho não declara posições.
    public var verticalAirflowOptions: [String] = []
    public var horizontalAirflowOptions: [String] = []
    public var horizontalSwingRanges: [String] = []
    public var optionalModes: [String] = []
    public var ambientTemperature = false
    public var humidity = false
    public var display = false
    public var displayControl: DisplayControl = .lightingLevel
    public var beep = false
    public var beepControl: BeepControl = .volume
    public var autoClean = false
    public var filter = false
    public var filterReset = false
    public var filterAlarmThresholds: [Double] = []
    public var energy = false

    public init() {}

    public var supportsWindFree: Bool { optionalModes.contains(OptionalMode.windFree) }
    public var supportsSleep: Bool {
        optionalModes.contains(OptionalMode.sleep) || optionalModes.contains(OptionalMode.windFreeSleep)
    }

    public func supports(_ setting: ACSetting) -> Bool {
        switch setting {
        case .power: power
        case .targetTemperature: targetTemperature != nil
        case .mode: !modes.isEmpty
        case .fanMode: !fanModes.isEmpty
        case .oscillation: !oscillationModes.isEmpty
        case .optionalMode: !optionalModes.isEmpty
        case .verticalAirflow: !verticalAirflowOptions.isEmpty
        case .horizontalAirflow: !horizontalAirflowOptions.isEmpty
        case .horizontalSwingRange: !horizontalSwingRanges.isEmpty
        case .display: display
        case .beep: beep
        case .autoClean: autoClean
        case .filterAlarmThreshold: !filterAlarmThresholds.isEmpty
        }
    }

    /// Recursos da página de ajustes, liberados só quando o aparelho os declara.
    public var hasExtras: Bool {
        display || beep || autoClean || filter || energy
    }
}
