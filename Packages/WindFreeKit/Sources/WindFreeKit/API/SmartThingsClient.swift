import Foundation

/// Cliente da API REST do SmartThings (https://api.smartthings.com/v1).
public struct SmartThingsClient: SmartThingsAPI {
    public static let defaultBaseURL = URL(string: "https://api.smartthings.com/v1/")!

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let tokens: any AccessTokenProvider

    public init(tokens: any AccessTokenProvider, transport: any HTTPTransport = URLSessionTransport(),
                baseURL: URL = SmartThingsClient.defaultBaseURL)
    {
        self.tokens = tokens
        self.transport = transport
        self.baseURL = baseURL
    }

    public func listDevices() async throws -> [DeviceSummary] {
        var devices: [DeviceSummary] = []
        var next: URL? = url("devices")
        var pages = 0
        while let pageURL = next, pages < 20 {
            pages += 1
            let page = try await get(pageURL)
            for item in page["items"]?.arrayValue ?? [] {
                if let device = Self.device(from: item) { devices.append(device) }
            }
            next = page["_links"]?["next"]?["href"]?.stringValue.flatMap(URL.init(string:))
            // Só seguimos links que apontam para o próprio servidor da API.
            if let host = next?.host, host != baseURL.host { next = nil }
        }
        return devices
    }

    public func rooms(locationID: String) async throws -> [Room] {
        let json = try await get(url("locations/\(escaped(locationID))/rooms"))
        return (json["items"]?.arrayValue ?? []).compactMap { item in
            guard let id = item["roomId"]?.stringValue, let name = item["name"]?.stringValue else { return nil }
            return Room(id: id, name: name)
        }
    }

    public func status(deviceID: String) async throws -> DeviceStatus {
        DeviceStatus(json: try await get(url("devices/\(escaped(deviceID))/status")))
    }

    public func health(deviceID: String) async throws -> DeviceHealth {
        let json = try await get(url("devices/\(escaped(deviceID))/health"))
        return DeviceHealth(rawValue: json["state"]?.stringValue ?? "") ?? .unknown
    }

    public func execute(deviceID: String, commands: [DeviceCommand]) async throws -> Bool {
        struct Body: Encodable { let commands: [DeviceCommand] }
        let body = try JSONEncoder().encode(Body(commands: commands))
        let json = try await send(url("devices/\(escaped(deviceID))/commands"), method: "POST", body: body)
        let statuses = json["results"]?.arrayValue?.compactMap { $0["status"]?.stringValue } ?? []
        return !statuses.contains("FAILED")
    }

    // MARK: - Internos

    static func device(from item: JSONValue) -> DeviceSummary? {
        guard let id = item["deviceId"]?.stringValue else { return nil }
        let components = item["components"]?.arrayValue ?? []
        let main = components.first { $0["id"]?.stringValue == "main" } ?? components.first
        let capabilities = main?["capabilities"]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
        return DeviceSummary(
            id: id,
            name: item["name"]?.stringValue ?? "Aparelho",
            label: item["label"]?.stringValue,
            capabilityIDs: Set(capabilities),
            locationID: item["locationId"]?.stringValue,
            roomID: item["roomId"]?.stringValue
        )
    }

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private func escaped(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? id
    }

    private func get(_ url: URL) async throws -> JSONValue {
        try await send(url, method: "GET", body: nil)
    }

    private func send(_ url: URL, method: String, body: Data?) async throws -> JSONValue {
        var token = try await tokens.accessToken()
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.data(for: request)
            } catch {
                throw SmartThingsError.from(error)
            }
            switch response.statusCode {
            case 200..<300:
                guard !data.isEmpty else { return .null }
                do { return try JSONDecoder().decode(JSONValue.self, from: data) } catch {
                    throw SmartThingsError.invalidResponse
                }
            case 401 where attempt == 0:
                // Uma renovação por requisição; se não houver token novo, a sessão expirou.
                guard await tokens.recoverFromUnauthorized(rejected: token) else { throw SmartThingsError.unauthorized }
                token = try await tokens.accessToken()
            case 401:
                throw SmartThingsError.unauthorized
            case 403:
                throw SmartThingsError.forbidden
            case 404:
                throw SmartThingsError.notFound
            case 429:
                throw SmartThingsError.rateLimited(retryAfter: Self.retryAfter(response))
            default:
                throw SmartThingsError.server(status: response.statusCode)
            }
        }
        throw SmartThingsError.unauthorized
    }

    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        if let value = response.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(value) {
            return seconds
        }
        // A API também informa o reset do limite em milissegundos.
        if let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let millis = TimeInterval(value) {
            return millis / 1000
        }
        return nil
    }
}
