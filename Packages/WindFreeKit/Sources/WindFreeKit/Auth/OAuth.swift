import Foundation

/// Dados do app OAuth registrado pelo próprio usuário no SmartThings (app "API Access").
/// O segredo do cliente nunca é embutido no aplicativo distribuído: ele é informado pelo usuário
/// e guardado apenas no Keychain deste aparelho.
public struct OAuthClientConfiguration: Sendable, Hashable, Codable {
    public var clientID: String
    public var clientSecret: String
    public var redirectURI: String
    public var scopes: [String]

    /// `r:locations:*` só é usada para ler os nomes dos cômodos; o app OAuth precisa incluí-la.
    public static let defaultScopes = ["r:devices:*", "x:devices:*", "r:locations:*"]

    public init(clientID: String, clientSecret: String, redirectURI: String, scopes: [String] = defaultScopes) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes
    }
}

public struct OAuthTokens: Sendable, Hashable, Codable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    /// Último uso do refresh token. Ele expira depois de 29 dias sem uso.
    public var refreshedAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date, refreshedAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshedAt = refreshedAt
    }

    public static let refreshTokenLifetime: TimeInterval = 29 * 24 * 3600
    public var refreshTokenExpiresAt: Date { refreshedAt.addingTimeInterval(Self.refreshTokenLifetime) }
}

public enum OAuthError: Error, Sendable, Equatable {
    case invalidConfiguration
    case stateMismatch
    case missingCode
    case denied(String)
    case invalidGrant
    /// Recusa do servidor na troca do código, com o motivo informado por ele (`error_description`).
    case tokenEndpoint(status: Int, detail: String?)
    case invalidResponse
    /// `localhost`/`127.0.0.1`: o servidor de autorização do SmartThings responde 403.
    case blockedRedirect

    public var userMessage: String {
        switch self {
        case .invalidConfiguration: "Confira o Client ID, o segredo e o endereço de retorno."
        case .stateMismatch: "A resposta de autorização não corresponde a este pedido. Tente de novo."
        case .missingCode: "O endereço colado não contém o código de autorização."
        case .denied(let reason): "Autorização recusada: \(reason)"
        case .invalidGrant: "A autorização expirou ou foi revogada. Conecte a conta de novo."
        case .tokenEndpoint(let status, let detail):
            "O SmartThings recusou a troca do código (\(status))" + (detail.map { ": \($0)" } ?? "")
                + ". O código é de uso único: autorize de novo para gerar outro."
        case .invalidResponse: "Resposta inesperada do servidor de autorização."
        case .blockedRedirect:
            "O SmartThings bloqueia localhost como endereço de retorno. Use \(OAuthService.smartThingsRedirectURI)."
        }
    }
}

/// Fluxo OAuth 2.0 `authorization_code` documentado pelo SmartThings para acesso contínuo.
public struct OAuthService: Sendable {
    public static let defaultAuthorizeURL = URL(string: "https://api.smartthings.com/oauth/authorize")!
    public static let defaultTokenURL = URL(string: "https://api.smartthings.com/oauth/token")!

    /// Endereço de retorno recomendado: página do próprio SmartThings (responde 404, mas mostra o código na
    /// barra do navegador, que o usuário cola no app). Verificado em 11/10/2026:
    /// - o cadastro exige `https` (exceto `localhost`), o que exclui loopback IPv6 e esquemas próprios;
    /// - o servidor de autorização responde 403 a `localhost`/`127.0.0.1` no `redirect_uri`;
    /// - sem `redirect_uri`, o fluxo termina nesta mesma página, mas a troca do código é recusada.
    public static let smartThingsRedirectURI = "https://api.smartthings.com/installedapp"

    private let authorizeURL: URL
    private let tokenURL: URL
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    public init(transport: any HTTPTransport = URLSessionTransport(),
                authorizeURL: URL = OAuthService.defaultAuthorizeURL,
                tokenURL: URL = OAuthService.defaultTokenURL,
                now: @escaping @Sendable () -> Date = Date.init)
    {
        self.transport = transport
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.now = now
    }

    public static func makeState() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func authorizationURL(for client: OAuthClientConfiguration, state: String) throws -> URL {
        guard !client.clientID.isEmpty, URL(string: client.redirectURI)?.scheme != nil,
              var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        else { throw OAuthError.invalidConfiguration }
        guard !Self.isBlockedRedirect(client.redirectURI) else { throw OAuthError.blockedRedirect }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: client.redirectURI),
            URLQueryItem(name: "scope", value: client.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw OAuthError.invalidConfiguration }
        return url
    }

    public static func isBlockedRedirect(_ redirectURI: String) -> Bool {
        guard let host = URL(string: redirectURI)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1"
    }

    /// Extrai o código do endereço de retorno, verificando o `state`.
    public static func code(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = item("error") {
            throw OAuthError.denied(item("error_description") ?? error)
        }
        guard item("state") == expectedState else { throw OAuthError.stateMismatch }
        guard let code = item("code"), !code.isEmpty else { throw OAuthError.missingCode }
        return code
    }

    /// O endereço de retorno precisa ser idêntico ao enviado na autorização.
    public func exchange(code: String, client: OAuthClientConfiguration) async throws -> OAuthTokens {
        try await requestTokens(client: client, form: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": client.clientID,
            "redirect_uri": client.redirectURI,
        ], previousRefreshToken: nil)
    }

    public func refresh(_ tokens: OAuthTokens, client: OAuthClientConfiguration) async throws -> OAuthTokens {
        try await requestTokens(client: client, form: [
            "grant_type": "refresh_token",
            "client_id": client.clientID,
            "refresh_token": tokens.refreshToken,
        ], previousRefreshToken: tokens.refreshToken)
    }

    private func requestTokens(client: OAuthClientConfiguration, form: [String: String],
                               previousRefreshToken: String?) async throws -> OAuthTokens
    {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        let basic = Data("\(client.clientID):\(client.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncode(form).utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw SmartThingsError.from(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder().decode(JSONValue.self, from: data)
            // Na renovação, autorização inválida significa sessão expirada. Na troca do código, o motivo
            // exato ajuda a corrigir a configuração.
            if previousRefreshToken != nil,
               body?["error"]?.stringValue == "invalid_grant" || response.statusCode == 401
            {
                throw OAuthError.invalidGrant
            }
            throw OAuthError.tokenEndpoint(status: response.statusCode, detail: Self.errorDetail(body))
        }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let access = json["access_token"]?.stringValue
        else { throw OAuthError.invalidResponse }
        // Se a resposta não trouxer um refresh token novo, o anterior continua valendo.
        guard let refresh = json["refresh_token"]?.stringValue ?? previousRefreshToken else {
            throw OAuthError.invalidResponse
        }
        let lifetime = json["expires_in"]?.doubleValue ?? 86_400
        let issuedAt = now()
        return OAuthTokens(accessToken: access, refreshToken: refresh,
                           expiresAt: issuedAt.addingTimeInterval(lifetime), refreshedAt: issuedAt)
    }

    /// Só os campos padronizados de erro do OAuth, limitados em tamanho.
    static func errorDetail(_ body: JSONValue?) -> String? {
        let parts = [body?["error"]?.stringValue, body?["error_description"]?.stringValue].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return String(parts.joined(separator: " — ").prefix(200))
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.keys.sorted().map { key in
            let value = form[key]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
    }
}
