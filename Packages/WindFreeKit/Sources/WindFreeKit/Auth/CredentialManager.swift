import Foundation

/// Fornece o token de acesso para cada requisição.
public protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String
    /// Chamado depois de um 401. Devolve `true` se já existe um token novo para tentar de novo.
    func recoverFromUnauthorized(rejected token: String) async -> Bool
}

/// Token fixo, usado para validar uma credencial antes de salvá-la e no modo simulado.
public struct StaticTokenProvider: AccessTokenProvider {
    private let token: String
    public init(token: String) { self.token = token }
    public func accessToken() async throws -> String { token }
    public func recoverFromUnauthorized(rejected token: String) async -> Bool { false }
}

/// Credencial guardada no Keychain.
public enum StoredCredential: Sendable, Hashable, Codable {
    /// Token pessoal (PAT). Os novos valem 24 horas: serve só para validar a integração.
    case personalToken(token: String, expiresAt: Date?)
    case oauth(client: OAuthClientConfiguration, tokens: OAuthTokens)
}

public struct CredentialSummary: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case personalToken, oauth }
    public var kind: Kind
    /// Validade do token de acesso (PAT: a informada pelo usuário; OAuth: renovada automaticamente).
    public var accessExpiresAt: Date?
    /// OAuth: data em que a autorização expira se o app não renovar o token.
    public var refreshExpiresAt: Date?
}

/// Guarda a credencial ativa e renova o token OAuth quando necessário.
public actor CredentialManager: AccessTokenProvider {
    static let storageKey = "credential"
    /// Renovamos antes do fim para não perder requisições na virada.
    static let refreshMargin: TimeInterval = 10 * 60

    private let store: any SecureStore
    private let oauth: OAuthService
    private let now: @Sendable () -> Date
    private var credential: StoredCredential?
    private var loaded = false
    private var refreshTask: Task<OAuthTokens, Error>?

    public init(store: any SecureStore, oauth: OAuthService = OAuthService(),
                now: @escaping @Sendable () -> Date = Date.init)
    {
        self.store = store
        self.oauth = oauth
        self.now = now
    }

    public func summary() throws -> CredentialSummary? {
        try loadIfNeeded()
        switch credential {
        case .personalToken(_, let expiresAt):
            return CredentialSummary(kind: .personalToken, accessExpiresAt: expiresAt, refreshExpiresAt: nil)
        case .oauth(_, let tokens):
            return CredentialSummary(kind: .oauth, accessExpiresAt: tokens.expiresAt,
                                     refreshExpiresAt: tokens.refreshTokenExpiresAt)
        case nil:
            return nil
        }
    }

    /// App OAuth configurado neste aparelho (para autorizar outro aparelho, como o Apple Watch, sem redigitar).
    public func oauthClient() throws -> OAuthClientConfiguration? {
        try loadIfNeeded()
        if case .oauth(let client, _) = credential { return client }
        return nil
    }

    public func save(_ credential: StoredCredential) throws {
        refreshTask?.cancel()
        refreshTask = nil
        try store.write(try JSONEncoder().encode(credential), for: Self.storageKey)
        self.credential = credential
        loaded = true
    }

    public func clear() throws {
        refreshTask?.cancel()
        refreshTask = nil
        try store.delete(Self.storageKey)
        credential = nil
        loaded = true
    }

    public func accessToken() async throws -> String {
        try loadIfNeeded()
        switch credential {
        case nil:
            throw SmartThingsError.notAuthenticated
        case .personalToken(let token, _):
            // A validade informada é só um aviso: quem decide é a API (401).
            return token
        case .oauth(_, let tokens):
            if tokens.expiresAt.timeIntervalSince(now()) > Self.refreshMargin { return tokens.accessToken }
            return try await refreshOAuth().accessToken
        }
    }

    public func recoverFromUnauthorized(rejected token: String) async -> Bool {
        guard case .oauth(_, let tokens) = credential else { return false }
        // Outra requisição já renovou o token.
        if tokens.accessToken != token { return true }
        return (try? await refreshOAuth()) != nil
    }

    /// Renova o token quando estiver perto de expirar. Mantém vivo o refresh token,
    /// que vence após 29 dias sem uso.
    public func refreshIfNeeded() async throws {
        try loadIfNeeded()
        guard case .oauth(_, let tokens) = credential,
              tokens.expiresAt.timeIntervalSince(now()) <= Self.refreshMargin
        else { return }
        _ = try await refreshOAuth()
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        if let data = try store.read(Self.storageKey) {
            credential = try? JSONDecoder().decode(StoredCredential.self, from: data)
        }
        loaded = true
    }

    /// Uma renovação por vez: chamadas simultâneas aguardam o mesmo resultado.
    private func refreshOAuth() async throws -> OAuthTokens {
        if let refreshTask { return try await refreshTask.value }
        guard case .oauth(let client, let tokens) = credential else { throw SmartThingsError.notAuthenticated }
        let task = Task { [oauth] in try await oauth.refresh(tokens, client: client) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            try save(.oauth(client: client, tokens: fresh))
            return fresh
        } catch OAuthError.invalidGrant {
            throw SmartThingsError.unauthorized
        }
    }
}
