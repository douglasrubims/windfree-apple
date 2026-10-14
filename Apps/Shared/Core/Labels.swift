import SwiftUI
import WindFreeKit

/// Nomes em português para os valores do SmartThings. Valores desconhecidos aparecem como vieram.
enum Labels {
    static func mode(_ value: String?) -> String {
        switch value {
        case "cool": "Resfriar"
        case "dry": "Desumidificar"
        case "wind", "fan", "fanOnly": "Ventilar"
        case "auto": "Automático"
        case "heat": "Aquecer"
        case "aIComfort": "Conforto IA"
        case "dryClean": "Secagem"
        case nil: "—"
        default: readable(value!)
        }
    }

    static func modeSymbol(_ value: String?) -> String {
        switch value {
        case "cool": "snowflake"
        case "dry": "drop"
        case "wind", "fan", "fanOnly": "fan"
        case "heat": "sun.max"
        case "auto", "aIComfort": "sparkles"
        default: "air.conditioner.horizontal"
        }
    }

    static func modeColor(_ value: String?) -> Color {
        switch value {
        case "cool": .blue
        case "dry": .teal
        case "heat": .orange
        case "auto", "aIComfort": .purple
        default: .gray
        }
    }

    static func fan(_ value: String?) -> String {
        switch value {
        case "auto": "Automático"
        case "low": "Baixo"
        case "medium": "Médio"
        case "high": "Alto"
        case "turbo": "Turbo"
        case "quiet": "Silencioso"
        case nil: "—"
        default: readable(value!)
        }
    }

    static func oscillation(_ value: String?) -> String {
        switch value {
        case "fixed": "Fixa"
        case "vertical": "Vertical"
        case "horizontal": "Lateral"
        case "all": "Vertical e lateral"
        case "indirect": "Indireta"
        case "direct": "Direta"
        case "fixedCenter": "Fixa no centro"
        case "fixedLeft": "Fixa à esquerda"
        case "fixedRight": "Fixa à direita"
        case nil: "—"
        default: readable(value!)
        }
    }

    /// Pás: oscilar ou posição exata (numeração do próprio aparelho).
    static func vanePosition(_ value: String?) -> String {
        switch value {
        case "swing": "Oscilar"
        case "fixed": "Fixa"
        case nil: "—"
        default: "Posição \(value!)"
        }
    }

    static func swingRange(_ value: String?) -> String {
        switch value {
        case "all": "Toda a largura"
        case "left": "Esquerda"
        case "right": "Direita"
        case nil: "—"
        default: readable(value!)
        }
    }

    static func optionalMode(_ value: String?) -> String {
        switch value {
        case "off", nil: "Nenhum"
        case "windFree": "WindFree"
        case "sleep": "Sono"
        case "windFreeSleep": "WindFree + Sono"
        case "quiet": "Silencioso"
        case "smart": "Inteligente"
        case "speed": "Rápido"
        case "dryComfort": "Conforto seco"
        case "eco": "Econômico"
        case "longWind": "Vento longo"
        default: readable(value!)
        }
    }

    static func setting(_ setting: ACSetting) -> String {
        switch setting {
        case .power: "liga/desliga"
        case .targetTemperature: "temperatura"
        case .mode: "modo"
        case .fanMode: "vento"
        case .oscillation: "direção"
        case .optionalMode: "modo especial"
        case .verticalAirflow: "pás verticais"
        case .horizontalAirflow: "pás laterais"
        case .horizontalSwingRange: "alcance lateral"
        case .display: "display"
        case .beep: "bipe"
        case .autoClean: "limpeza automática"
        case .filterAlarmThreshold: "alerta do filtro"
        }
    }

    static func settings(_ settings: Set<ACSetting>) -> String {
        ListFormatter.localizedString(byJoining: settings.sorted().map(setting))
    }

    static func filterStatus(_ value: String?) -> String? {
        switch value {
        case "wash": "Hora de lavar o filtro"
        case "replace": "Hora de trocar o filtro"
        case "normal", nil: nil
        default: readable(value!)
        }
    }

    /// O aparelho pode informar potência instantânea zerada; nesse caso usamos a média da última janela
    /// do relatório de energia.
    static func powerReading(_ state: ACState) -> (value: String, note: String?) {
        if let watts = state.powerWatts, watts > 0 {
            return ("\(Format.decimal(watts, digits: 0)) W", "agora")
        }
        if state.isOn == true, let average = state.averagePowerWatts {
            return ("≈ \(Format.decimal(average, digits: 0)) W", "média recente")
        }
        return (state.powerWatts.map { "\(Format.decimal($0, digits: 0)) W" } ?? "—", nil)
    }

    static func filterNote(_ state: ACState) -> String {
        let usage = state.filterUsage ?? 0
        if let status = filterStatus(state.filterStatus) { return status }
        if let threshold = state.filterAlarmThreshold {
            let remaining = max(0, ((100 - usage) / 100 * threshold).rounded())
            return "Lavar daqui a cerca de \(Int(remaining)) h de uso"
        }
        return "\(Int(usage.rounded()))% de uso"
    }

    /// "fixedCenter" → "Fixed center".
    private static func readable(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}

enum Format {
    private static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func temperature(_ value: Double?) -> String {
        guard let value else { return "--" }
        return number.string(from: NSNumber(value: value)) ?? "--"
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
