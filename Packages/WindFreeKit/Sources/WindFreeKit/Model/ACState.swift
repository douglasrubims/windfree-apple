import Foundation

/// Ajustes que o usuário pode pedir ao aparelho.
public enum ACSetting: String, Sendable, Hashable, CaseIterable, Codable, Comparable {
    case power
    case targetTemperature
    case mode
    case fanMode
    case oscillation
    case optionalMode
    /// Pás verticais: `swing` ou a posição fixa (`"1"`…`"6"`), em `samsungce.airConditionerAirFlowDirection`.
    case verticalAirflow
    /// Pás laterais: `swing` ou a posição fixa.
    case horizontalAirflow
    /// Alcance da oscilação lateral: `all`, `left`, `right`.
    case horizontalSwingRange
    case display
    case beep
    case autoClean
    case filterAlarmThreshold

    /// Ajustes de clima. No aparelho de referência eles são ignorados com o ar desligado.
    public static let climate: Set<ACSetting> = [
        .targetTemperature, .mode, .fanMode, .oscillation, .optionalMode,
        .verticalAirflow, .horizontalAirflow, .horizontalSwingRange,
    ]

    public static func < (lhs: ACSetting, rhs: ACSetting) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public enum ACValue: Sendable, Hashable {
    case bool(Bool)
    case number(Double)
    case text(String)

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    /// Igualdade tolerante para temperaturas (22 e 22.0, conversões de unidade).
    public func matches(_ other: ACValue?) -> Bool {
        guard let other else { return false }
        if case .number(let lhs) = self, case .number(let rhs) = other {
            return abs(lhs - rhs) < 0.05
        }
        return self == other
    }
}

public enum TemperatureUnit: String, Sendable, Hashable {
    case celsius = "C"
    case fahrenheit = "F"

    public var symbol: String { self == .celsius ? "°C" : "°F" }
}

/// Estado interpretado do ar-condicionado. Campos ausentes significam "não informado".
public struct ACState: Sendable, Hashable {
    public var isOn: Bool?
    public var targetTemperature: Double?
    public var temperatureUnit: TemperatureUnit = .celsius
    public var ambientTemperature: Double?
    public var humidity: Double?
    public var mode: String?
    public var fanMode: String?
    public var oscillation: String?
    public var optionalMode: String?
    public var verticalAirflow: String?
    public var horizontalAirflow: String?
    public var horizontalSwingRange: String?
    /// Última posição informada pelo aparelho, inclusive enquanto as pás oscilam (para o controle deslizante).
    public var verticalStepHint: Int?
    public var horizontalStepHint: Int?
    public var displayOn: Bool?
    public var beepOn: Bool?
    public var autoCleanOn: Bool?
    /// Uso do filtro em porcentagem do limite de alerta.
    public var filterUsage: Double?
    public var filterStatus: String?
    public var filterAlarmThreshold: Double?
    public var powerWatts: Double?
    /// Potência média da última janela do relatório, quando a potência instantânea vem zerada.
    public var averagePowerWatts: Double?
    public var energyKWh: Double?

    public init() {}

    public var windFreeOn: Bool { OptionalMode.hasWindFree(optionalMode) }

    /// Movimento das pás no formato de `fanOscillationMode`, para o desenho do fluxo de ar.
    public var swingSummary: String? {
        if let oscillation { return oscillation }
        guard verticalAirflow != nil || horizontalAirflow != nil else { return nil }
        switch (verticalAirflow == AirFlow.swing, horizontalAirflow == AirFlow.swing) {
        case (true, true): return "all"
        case (true, false): return "vertical"
        case (false, true): return "horizontal"
        case (false, false): return "fixed"
        }
    }
    public var sleepOn: Bool { OptionalMode.hasSleep(optionalMode) }

    public func value(for setting: ACSetting) -> ACValue? {
        switch setting {
        case .power: isOn.map(ACValue.bool)
        case .targetTemperature: targetTemperature.map(ACValue.number)
        case .mode: mode.map(ACValue.text)
        case .fanMode: fanMode.map(ACValue.text)
        case .oscillation: oscillation.map(ACValue.text)
        case .optionalMode: optionalMode.map(ACValue.text)
        case .verticalAirflow: verticalAirflow.map(ACValue.text)
        case .horizontalAirflow: horizontalAirflow.map(ACValue.text)
        case .horizontalSwingRange: horizontalSwingRange.map(ACValue.text)
        case .display: displayOn.map(ACValue.bool)
        case .beep: beepOn.map(ACValue.bool)
        case .autoClean: autoCleanOn.map(ACValue.bool)
        case .filterAlarmThreshold: filterAlarmThreshold.map(ACValue.number)
        }
    }

    public mutating func apply(_ value: ACValue, for setting: ACSetting) {
        switch setting {
        case .power: isOn = value.bool ?? isOn
        case .targetTemperature: targetTemperature = value.number ?? targetTemperature
        case .mode: mode = value.text ?? mode
        case .fanMode: fanMode = value.text ?? fanMode
        case .oscillation: oscillation = value.text ?? oscillation
        case .optionalMode: optionalMode = value.text ?? optionalMode
        case .verticalAirflow: verticalAirflow = value.text ?? verticalAirflow
        case .horizontalAirflow: horizontalAirflow = value.text ?? horizontalAirflow
        case .horizontalSwingRange: horizontalSwingRange = value.text ?? horizontalSwingRange
        case .display: displayOn = value.bool ?? displayOn
        case .beep: beepOn = value.bool ?? beepOn
        case .autoClean: autoCleanOn = value.bool ?? autoCleanOn
        case .filterAlarmThreshold: filterAlarmThreshold = value.number ?? filterAlarmThreshold
        }
    }

    public func applying(_ changes: [ACSetting: ACValue]) -> ACState {
        var copy = self
        for (setting, value) in changes { copy.apply(value, for: setting) }
        return copy
    }
}

/// O WindFree e o modo sono dividem o mesmo atributo (`acOptionalMode`).
public enum OptionalMode {
    public static let off = "off"
    public static let windFree = "windFree"
    public static let sleep = "sleep"
    public static let windFreeSleep = "windFreeSleep"

    public static func hasWindFree(_ value: String?) -> Bool {
        value == windFree || value == windFreeSleep
    }

    public static func hasSleep(_ value: String?) -> Bool {
        value == sleep || value == windFreeSleep
    }

    /// Valor para a combinação pedida, respeitando o que o aparelho declara suportar.
    /// Se a combinação de WindFree e sono não existir, o último ajuste pedido prevalece.
    public static func compose(windFree: Bool, sleep: Bool, changed: Changed, supported: [String]) -> String? {
        switch (windFree, sleep) {
        case (false, false):
            return supported.isEmpty || supported.contains(off) ? off : nil
        case (true, false):
            return supported.contains(Self.windFree) ? Self.windFree : nil
        case (false, true):
            return supported.contains(Self.sleep) ? Self.sleep : nil
        case (true, true):
            if supported.contains(windFreeSleep) { return windFreeSleep }
            switch changed {
            case .windFree: return supported.contains(Self.windFree) ? Self.windFree : nil
            case .sleep: return supported.contains(Self.sleep) ? Self.sleep : nil
            }
        }
    }

    public enum Changed: Sendable { case windFree, sleep }
}
