import Foundation

/// Relatório para validar capacidades e comandos contra o aparelho real, sem dados pessoais:
/// identificadores, nomes, números de série e endereços são removidos.
public enum DiagnosticReport {
    /// Atributos que identificam o aparelho, a conta ou a rede.
    static let sensitiveKeys: Set<String> = [
        "di", "n", "deviceId", "locationId", "roomId", "ownerId", "installedAppId", "label", "name",
        "serialNumber", "serialNumberExtra", "macAddress", "bleMac", "wifiMac", "ssid", "ip", "ipAddress",
        "pi", "icv", "dmv", "vid", "mnId", "hubId", "zigbeeEui", "userId", "binaryId", "uuid",
    ]

    public static func make(status: DeviceStatus, health: DeviceHealth, capabilities: ACCapabilities,
                            state: ACState?, generatedAt: Date = Date()) throws -> Data
    {
        var components: [String: JSONValue] = [:]
        for (componentID, capabilityMap) in status.components {
            var capabilityJSON: [String: JSONValue] = [:]
            for (capabilityID, attributes) in capabilityMap {
                var attributeJSON: [String: JSONValue] = [:]
                for (attributeID, attribute) in attributes {
                    var entry: [String: JSONValue] = ["value": redact(attribute.value ?? .null, key: attributeID)]
                    if let unit = attribute.unit { entry["unit"] = .string(unit) }
                    attributeJSON[attributeID] = .object(entry)
                }
                capabilityJSON[capabilityID] = .object(attributeJSON)
            }
            components[componentID] = .object(capabilityJSON)
        }

        let formatter = ISO8601DateFormatter()
        let report: JSONValue = [
            "aviso": "Relatório sem identificadores pessoais. Revise antes de compartilhar.",
            "geradoEm": .string(formatter.string(from: generatedAt)),
            "saude": .string(health.rawValue),
            "capacidadesInterpretadas": interpreted(capabilities),
            "estadoInterpretado": state.map(interpreted) ?? .null,
            "status": ["components": .object(components)],
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    /// Trechos de nome de atributo que indicam identificador (ex.: `otnDUID`, `serialNumberExtra`).
    static let sensitiveKeyFragments = ["duid", "uuid", "serial", "macaddress", "deviceid", "locationid", "ownerid"]

    static func isSensitive(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return sensitiveKeys.contains(key) || sensitiveKeyFragments.contains { lowered.contains($0) }
    }

    static func redact(_ value: JSONValue, key: String?) -> JSONValue {
        if let key, isSensitive(key) { return .string("<removido>") }
        switch value {
        case .string(let text):
            return looksLikeIdentifier(text) ? .string("<removido>") : value
        case .array(let items):
            return .array(items.map { redact($0, key: nil) })
        case .object(let object):
            return .object(Dictionary(uniqueKeysWithValues: object.map { ($0.key, redact($0.value, key: $0.key)) }))
        default:
            return value
        }
    }

    /// UUIDs, endereços MAC e URLs com caminho podem identificar o aparelho ou a conta.
    static func looksLikeIdentifier(_ text: String) -> Bool {
        let patterns = [
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            "([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}",
            "https?://",
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    static func interpreted(_ caps: ACCapabilities) -> JSONValue {
        func strings(_ list: [String]) -> JSONValue { .array(list.map(JSONValue.string)) }
        var range: JSONValue = .null
        if let temperature = caps.targetTemperature {
            range = ["minimo": .number(temperature.minimum), "maximo": .number(temperature.maximum),
                     "passo": .number(temperature.step), "suposto": .bool(temperature.isAssumed)]
        }
        return [
            "ligarDesligar": .bool(caps.power),
            "temperaturaDesejada": range,
            "modos": strings(caps.modes),
            "ventilador": strings(caps.fanModes),
            "oscilacao": strings(caps.oscillationModes),
            "modosOpcionais": strings(caps.optionalModes),
            "temperaturaAmbiente": .bool(caps.ambientTemperature),
            "umidade": .bool(caps.humidity),
            "display": .bool(caps.display),
            "bipe": .bool(caps.beep),
            "limpezaAutomatica": .bool(caps.autoClean),
            "filtro": .bool(caps.filter),
            "alertasDoFiltro": .array(caps.filterAlarmThresholds.map(JSONValue.number)),
            "energia": .bool(caps.energy),
            "pasVerticais": strings(caps.verticalAirflowOptions),
            "pasLaterais": strings(caps.horizontalAirflowOptions),
            "alcanceLateral": strings(caps.horizontalSwingRanges),
            "controleDisplay": .string(String(describing: caps.displayControl)),
            "controleBipe": .string(String(describing: caps.beepControl)),
        ]
    }

    static func interpreted(_ state: ACState) -> JSONValue {
        func number(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }
        func text(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
        func bool(_ value: Bool?) -> JSONValue { value.map(JSONValue.bool) ?? .null }
        return [
            "ligado": bool(state.isOn),
            "temperaturaDesejada": number(state.targetTemperature),
            "unidade": .string(state.temperatureUnit.rawValue),
            "temperaturaAmbiente": number(state.ambientTemperature),
            "umidade": number(state.humidity),
            "modo": text(state.mode),
            "ventilador": text(state.fanMode),
            "oscilacao": text(state.oscillation),
            "pasVerticais": text(state.verticalAirflow),
            "pasLaterais": text(state.horizontalAirflow),
            "alcanceLateral": text(state.horizontalSwingRange),
            "modoOpcional": text(state.optionalMode),
            "display": bool(state.displayOn),
            "bipe": bool(state.beepOn),
            "limpezaAutomatica": bool(state.autoCleanOn),
            "usoDoFiltro": number(state.filterUsage),
            "statusDoFiltro": text(state.filterStatus),
            "alertaDoFiltro": number(state.filterAlarmThreshold),
            "potenciaW": number(state.powerWatts),
            "potenciaMediaW": number(state.averagePowerWatts),
            "energiaKWh": number(state.energyKWh),
        ]
    }
}
