import Foundation

/// Aparelho listado na conta. Só o necessário para escolher e identificar o ar-condicionado.
public struct DeviceSummary: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let label: String?
    /// Capacidades do componente `main`, conforme a listagem de aparelhos.
    public let capabilityIDs: Set<String>
    public let locationID: String?
    public let roomID: String?
    /// Nome do cômodo (exige a permissão `r:locations:*`; vazio quando não disponível).
    public var roomName: String?

    public init(id: String, name: String, label: String? = nil, capabilityIDs: Set<String>,
                locationID: String? = nil, roomID: String? = nil, roomName: String? = nil)
    {
        self.id = id
        self.name = name
        self.label = label
        self.capabilityIDs = capabilityIDs
        self.locationID = locationID
        self.roomID = roomID
        self.roomName = roomName
    }

    public var displayName: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return name
    }

    public var isAirConditioner: Bool {
        capabilityIDs.contains(Capability.airConditionerMode)
    }
}

/// Cômodo de uma casa (local) do SmartThings.
public struct Room: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public extension [DeviceSummary] {
    /// Nome para listas e menus. Com o cômodo conhecido: "Ar condicionado · Quarto". Sem ele, nomes repetidos
    /// ganham um número ("Ar condicionado (2)") para que os aparelhos não fiquem iguais.
    func title(for device: DeviceSummary) -> String {
        if let room = device.roomName, !room.isEmpty { return "\(device.displayName) · \(room)" }
        let twins = filter { $0.displayName == device.displayName && ($0.roomName ?? "").isEmpty }
        guard twins.count > 1, let index = twins.firstIndex(where: { $0.id == device.id }) else {
            return device.displayName
        }
        return "\(device.displayName) (\(index + 1))"
    }

    /// Preenche o nome do cômodo a partir dos cômodos conhecidos.
    func withRoomNames(_ rooms: [Room]) -> [DeviceSummary] {
        let names = Dictionary(rooms.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return map { device in
            var copy = device
            if let roomID = device.roomID { copy.roomName = names[roomID] }
            return copy
        }
    }
}

/// Valor de um atributo no status do aparelho.
public struct AttributeState: Sendable, Hashable {
    public var value: JSONValue?
    public var unit: String?

    public init(value: JSONValue?, unit: String? = nil) {
        self.value = value
        self.unit = unit
    }
}

/// Status bruto: componente → capacidade → atributo.
public struct DeviceStatus: Sendable, Hashable {
    public var components: [String: [String: [String: AttributeState]]]

    public init(components: [String: [String: [String: AttributeState]]]) {
        self.components = components
    }

    public subscript(capability: String, attribute: String) -> AttributeState? {
        components["main"]?[capability]?[attribute]
    }

    public func value(_ capability: String, _ attribute: String) -> JSONValue? {
        guard let value = self[capability, attribute]?.value, value != .null else { return nil }
        return value
    }

    /// Capacidades que aparecem no componente principal.
    public var mainCapabilities: Set<String> {
        Set(components["main"].map { Array($0.keys) } ?? [])
    }

    /// Converte o JSON de `GET /devices/{id}/status` sem falhar em atributos inesperados.
    public init(json: JSONValue) {
        var result: [String: [String: [String: AttributeState]]] = [:]
        for (componentID, capabilities) in json["components"]?.objectValue ?? [:] {
            var capabilityMap: [String: [String: AttributeState]] = [:]
            for (capabilityID, attributes) in capabilities.objectValue ?? [:] {
                var attributeMap: [String: AttributeState] = [:]
                for (attributeID, state) in attributes.objectValue ?? [:] {
                    attributeMap[attributeID] = AttributeState(value: state["value"], unit: state["unit"]?.stringValue)
                }
                capabilityMap[capabilityID] = attributeMap
            }
            result[componentID] = capabilityMap
        }
        components = result
    }
}

public enum DeviceHealth: String, Sendable, Hashable {
    case online = "ONLINE"
    case offline = "OFFLINE"
    case unknown
}

/// Comando no formato de `POST /devices/{id}/commands`.
public struct DeviceCommand: Sendable, Hashable, Encodable {
    public var component: String
    public var capability: String
    public var command: String
    public var arguments: [JSONValue]

    public init(capability: String, command: String, arguments: [JSONValue] = [], component: String = "main") {
        self.component = component
        self.capability = capability
        self.command = command
        self.arguments = arguments
    }
}

/// Identificadores de capacidades usadas pelo app.
public enum Capability {
    public static let switchCapability = "switch"
    public static let airConditionerMode = "airConditionerMode"
    public static let fanMode = "airConditionerFanMode"
    public static let oscillation = "fanOscillationMode"
    public static let coolingSetpoint = "thermostatCoolingSetpoint"
    public static let setpointControl = "custom.thermostatSetpointControl"
    public static let temperature = "temperatureMeasurement"
    public static let humidity = "relativeHumidityMeasurement"
    public static let optionalMode = "custom.airConditionerOptionalMode"
    public static let lighting = "samsungce.airConditionerLighting"
    public static let execute = "execute"
    public static let audioVolume = "audioVolume"
    public static let autoCleaning = "custom.autoCleaningMode"
    public static let dustFilter = "custom.dustFilter"
    public static let dustFilterAlarm = "samsungce.dustFilterAlarm"
    public static let powerReport = "powerConsumptionReport"
    public static let disabledCapabilities = "custom.disabledCapabilities"
    public static let unavailableCapabilities = "samsungce.unavailableCapabilities"
    public static let airFlowDirection = "samsungce.airConditionerAirFlowDirection"
    public static let beep = "samsungce.airConditionerBeep"
}
