import Foundation

/// Operações usadas pelo app. A implementação real fala com a API; a simulada roda em memória.
public protocol SmartThingsAPI: Sendable {
    func listDevices() async throws -> [DeviceSummary]
    /// Cômodos de uma casa. Exige a permissão `r:locations:*`.
    func rooms(locationID: String) async throws -> [Room]
    func status(deviceID: String) async throws -> DeviceStatus
    func health(deviceID: String) async throws -> DeviceHealth
    /// Envia comandos e devolve `false` quando a plataforma informa falha em algum deles.
    func execute(deviceID: String, commands: [DeviceCommand]) async throws -> Bool
}

public enum SmartThingsError: Error, Sendable, Equatable {
    /// Nenhuma credencial configurada.
    case notAuthenticated
    /// Token recusado ou expirado e sem renovação possível.
    case unauthorized
    /// Token válido, mas sem permissão (escopos insuficientes).
    case forbidden
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case invalidResponse
    case offlineNetwork
    case timedOut
    case cancelled
    case transport(String)

    public var userMessage: String {
        switch self {
        case .notAuthenticated: "Conta SmartThings não configurada."
        case .unauthorized: "Sessão expirada. Conecte a conta de novo."
        case .forbidden: "O token não tem permissão para este aparelho."
        case .notFound: "Aparelho não encontrado na conta."
        case .rateLimited: "Limite de consultas do SmartThings atingido."
        case .server(let status): "O SmartThings respondeu com erro (\(status))."
        case .invalidResponse: "Resposta inesperada do SmartThings."
        case .offlineNetwork: "Sem conexão com a internet."
        case .timedOut: "Sem resposta do SmartThings."
        case .cancelled: "Operação cancelada."
        case .transport: "Falha de comunicação com o SmartThings."
        }
    }

    public static func from(_ error: Error) -> SmartThingsError {
        if let error = error as? SmartThingsError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled:
                return .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
                return .offlineNetwork
            case .timedOut:
                return .timedOut
            default:
                return .transport(error.code.rawValue.description)
            }
        }
        return .transport(String(describing: type(of: error)))
    }
}

/// Camada de transporte injetável para testes.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    /// Sessão sem cache nem cookies: as respostas contêm identificadores pessoais e não devem ir para o disco.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SmartThingsError.invalidResponse }
        return (data, http)
    }
}
