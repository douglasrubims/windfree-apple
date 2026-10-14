import Foundation
import Testing
@testable import WindFreeKit

/// Transporte falso: responde em sequência e guarda as requisições.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    var recorded: [URLRequest] { lock.withLock { requests } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "{}") : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

/// Provedor que troca o token uma vez quando recebe 401.
actor RotatingTokens: AccessTokenProvider {
    var token = "old"
    var recoveries = 0
    let canRecover: Bool

    init(canRecover: Bool) { self.canRecover = canRecover }

    func accessToken() async throws -> String { token }

    func recoverFromUnauthorized(rejected: String) async -> Bool {
        recoveries += 1
        guard canRecover else { return false }
        token = "new"
        return true
    }
}

@Suite("Cliente SmartThings")
struct ClientTests {
    @Test func listsDevicesAcrossPagesWithBearerToken() async throws {
        let transport = StubTransport([
            .init(status: 200, body: """
            {"items":[{"deviceId":"a","name":"Samsung Room A/C","label":"Sala",
              "components":[{"id":"main","capabilities":[{"id":"switch"},{"id":"airConditionerMode"}]}]}],
             "_links":{"next":{"href":"https://api.smartthings.com/v1/devices?page=1"}}}
            """),
            .init(status: 200, body: """
            {"items":[{"deviceId":"b","name":"Lâmpada","components":[{"id":"main","capabilities":[{"id":"switch"}]}]}],
             "_links":{}}
            """),
        ])
        let client = SmartThingsClient(tokens: StaticTokenProvider(token: "abc"), transport: transport)
        let devices = try await client.listDevices()
        #expect(devices.map(\.id) == ["a", "b"])
        #expect(devices.filter(\.isAirConditioner).map(\.displayName) == ["Sala"])
        #expect(transport.recorded.count == 2)
        #expect(transport.recorded.first?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(transport.recorded.first?.url?.absoluteString == "https://api.smartthings.com/v1/devices")
    }

    @Test func readsRoomsAndDeviceLocation() async throws {
        let transport = StubTransport([
            .init(status: 200, body: """
            {"items":[{"deviceId":"a","label":"Ar condicionado","locationId":"casa","roomId":"r1",
              "components":[{"id":"main","capabilities":[{"id":"airConditionerMode"}]}]}]}
            """),
            .init(status: 200, body: #"{"items":[{"roomId":"r1","name":"Quarto","locationId":"casa"}]}"#),
        ])
        let client = SmartThingsClient(tokens: StaticTokenProvider(token: "t"), transport: transport)
        let devices = try await client.listDevices()
        #expect(devices.first?.locationID == "casa")
        #expect(devices.first?.roomID == "r1")
        let rooms = try await client.rooms(locationID: "casa")
        #expect(rooms == [Room(id: "r1", name: "Quarto")])
        #expect(transport.recorded.last?.url?.absoluteString == "https://api.smartthings.com/v1/locations/casa/rooms")
        #expect(devices.withRoomNames(rooms).first?.roomName == "Quarto")
    }

    @Test func titlesDisambiguateTwins() {
        let quarto = DeviceSummary(id: "1", name: "AC", label: "Ar condicionado", capabilityIDs: [], roomID: "r1")
        let escritorio = DeviceSummary(id: "2", name: "AC", label: "Ar condicionado", capabilityIDs: [], roomID: "r2")
        let sala = DeviceSummary(id: "3", name: "AC", label: "Ar da sala", capabilityIDs: [])

        // Sem cômodos: nomes repetidos ganham número; nomes únicos ficam como estão.
        let plain = [quarto, escritorio, sala]
        #expect(plain.title(for: quarto) == "Ar condicionado (1)")
        #expect(plain.title(for: escritorio) == "Ar condicionado (2)")
        #expect(plain.title(for: sala) == "Ar da sala")

        // Com cômodos: "nome · cômodo".
        let named = plain.withRoomNames([Room(id: "r1", name: "Quarto"), Room(id: "r2", name: "Escritório")])
        #expect(named.title(for: named[0]) == "Ar condicionado · Quarto")
        #expect(named.title(for: named[1]) == "Ar condicionado · Escritório")
    }

    @Test func ignoresPaginationToForeignHosts() async throws {
        let transport = StubTransport([
            .init(status: 200, body: #"{"items":[],"_links":{"next":{"href":"https://example.com/steal"}}}"#),
        ])
        let client = SmartThingsClient(tokens: StaticTokenProvider(token: "abc"), transport: transport)
        _ = try await client.listDevices()
        #expect(transport.recorded.count == 1)
    }

    @Test func retriesOnceAfterTokenRecovery() async throws {
        let transport = StubTransport([
            .init(status: 401, body: "{}"),
            .init(status: 200, body: #"{"state":"ONLINE"}"#),
        ])
        let tokens = RotatingTokens(canRecover: true)
        let client = SmartThingsClient(tokens: tokens, transport: transport)
        #expect(try await client.health(deviceID: "x") == .online)
        #expect(transport.recorded.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new")
        #expect(await tokens.recoveries == 1)
    }

    @Test func unauthorizedWithoutRecovery() async {
        let transport = StubTransport([.init(status: 401, body: "{}")])
        let client = SmartThingsClient(tokens: RotatingTokens(canRecover: false), transport: transport)
        await #expect(throws: SmartThingsError.unauthorized) { try await client.health(deviceID: "x") }
        #expect(transport.recorded.count == 1)
    }

    @Test func mapsRateLimitWithRetryAfter() async {
        let transport = StubTransport([.init(status: 429, body: "{}", headers: ["Retry-After": "12"])])
        let client = SmartThingsClient(tokens: StaticTokenProvider(token: "t"), transport: transport)
        await #expect(throws: SmartThingsError.rateLimited(retryAfter: 12)) {
            try await client.status(deviceID: "x")
        }
    }

    @Test func sendsCommandsAndDetectsFailures() async throws {
        let transport = StubTransport([
            .init(status: 200, body: #"{"results":[{"id":"1","status":"ACCEPTED"}]}"#),
            .init(status: 200, body: #"{"results":[{"id":"2","status":"FAILED"}]}"#),
        ])
        let client = SmartThingsClient(tokens: StaticTokenProvider(token: "t"), transport: transport)
        let commands = ACCommandBuilder.commands(for: .fanMode, value: .text("low"))
        #expect(try await client.execute(deviceID: "dev 1", commands: commands))
        #expect(try await !client.execute(deviceID: "dev 1", commands: commands))

        let request = try #require(transport.recorded.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.smartthings.com/v1/devices/dev%201/commands")
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody))
        #expect(body["commands"]?.arrayValue?.first?["command"] == "setFanMode")
    }

    @Test func mapsTransportErrors() {
        #expect(SmartThingsError.from(URLError(.notConnectedToInternet)) == .offlineNetwork)
        #expect(SmartThingsError.from(URLError(.timedOut)) == .timedOut)
        #expect(SmartThingsError.from(URLError(.cancelled)) == .cancelled)
        #expect(SmartThingsError.from(CancellationError()) == .cancelled)
    }
}

@Suite("OAuth e credenciais")
struct AuthTests {
    let client = OAuthClientConfiguration(clientID: "client-id", clientSecret: "client-secret",
                                          redirectURI: OAuthService.smartThingsRedirectURI)

    @Test func buildsAuthorizationURL() throws {
        let url = try OAuthService().authorizationURL(for: client, state: "xyz")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(url.host == "api.smartthings.com")
        #expect(value("response_type") == "code")
        #expect(value("client_id") == "client-id")
        #expect(value("redirect_uri") == "https://api.smartthings.com/installedapp")
        #expect(value("scope") == "r:devices:* x:devices:* r:locations:*")
        #expect(value("state") == "xyz")
        // O segredo nunca vai na URL.
        #expect(!url.absoluteString.contains("client-secret"))
    }

    /// O SmartThings responde 403 a `localhost`/`127.0.0.1` no `redirect_uri` da autorização.
    @Test func rejectsBlockedLoopbackRedirect() {
        for redirect in ["http://localhost:53682/callback", "http://127.0.0.1:53682/callback", "http://LOCALHOST:1/cb"] {
            var loopback = client
            loopback.redirectURI = redirect
            #expect(throws: OAuthError.blockedRedirect) { try OAuthService().authorizationURL(for: loopback, state: "s") }
        }
        #expect(!OAuthService.isBlockedRedirect("https://localhost.example.com/cb"))
        #expect(!OAuthService.isBlockedRedirect(OAuthService.smartThingsRedirectURI))
    }

    @Test func parsesCallbackAndChecksState() throws {
        let good = URL(string: "http://127.0.0.1:53682/callback?code=abc&state=s1")!
        #expect(try OAuthService.code(fromCallback: good, expectedState: "s1") == "abc")
        #expect(throws: OAuthError.stateMismatch) {
            try OAuthService.code(fromCallback: good, expectedState: "other")
        }
        let denied = URL(string: "http://127.0.0.1/callback?error=access_denied&state=s1")!
        #expect(throws: OAuthError.denied("access_denied")) {
            try OAuthService.code(fromCallback: denied, expectedState: "s1")
        }
    }

    @Test func exchangeUsesBasicAuthAndForm() async throws {
        let transport = StubTransport([
            .init(status: 200, body: #"{"access_token":"A","refresh_token":"R","expires_in":86399}"#),
        ])
        let issued = Date(timeIntervalSince1970: 1_000)
        let service = OAuthService(transport: transport, now: { issued })
        let tokens = try await service.exchange(code: "the-code", client: client)
        #expect(tokens.accessToken == "A")
        #expect(tokens.refreshToken == "R")
        #expect(tokens.expiresAt == issued.addingTimeInterval(86399))

        let request = try #require(transport.recorded.first)
        let basic = Data("client-id:client-secret".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(basic)")
        let form = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(form.contains("grant_type=authorization_code"))
        #expect(form.contains("code=the-code"))
        // Mesmo endereço da autorização.
        #expect(form.contains("redirect_uri=https%3A%2F%2Fapi.smartthings.com%2Finstalledapp"))
        #expect(!form.contains("client-secret"))
    }

    @Test func exchangeFailureCarriesServerReason() async {
        let transport = StubTransport([
            .init(status: 400, body: #"{"error":"invalid_grant","error_description":"Redirect URI mismatch."}"#),
        ])
        await #expect(throws: OAuthError.tokenEndpoint(status: 400, detail: "invalid_grant — Redirect URI mismatch.")) {
            try await OAuthService(transport: transport).exchange(code: "c", client: client)
        }
        #expect(OAuthError.tokenEndpoint(status: 400, detail: "x").userMessage.contains("x"))
    }

    @Test func parsesSmartThingsRedirectPage() throws {
        let url = URL(string: "https://api.smartthings.com/installedapp?code=AbC_1&state=st")!
        #expect(try OAuthService.code(fromCallback: url, expectedState: "st") == "AbC_1")
    }

    @Test func refreshKeepsPreviousRefreshTokenWhenOmitted() async throws {
        let transport = StubTransport([.init(status: 200, body: #"{"access_token":"A2","expires_in":100}"#)])
        let service = OAuthService(transport: transport)
        let old = OAuthTokens(accessToken: "A", refreshToken: "R", expiresAt: .now, refreshedAt: .now)
        let fresh = try await service.refresh(old, client: client)
        #expect(fresh.accessToken == "A2")
        #expect(fresh.refreshToken == "R")
    }

    @Test func invalidGrantBecomesSessionExpired() async throws {
        let transport = StubTransport([.init(status: 400, body: #"{"error":"invalid_grant"}"#)])
        let store = MemoryStore()
        let manager = CredentialManager(store: store, oauth: OAuthService(transport: transport))
        let expired = OAuthTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantPast, refreshedAt: .now)
        try await manager.save(.oauth(client: client, tokens: expired))
        await #expect(throws: SmartThingsError.unauthorized) { try await manager.accessToken() }
    }

    @Test func refreshesNearExpiryOnlyOnceForConcurrentCallers() async throws {
        let transport = StubTransport([
            .init(status: 200, body: #"{"access_token":"A2","refresh_token":"R2","expires_in":86400}"#),
        ])
        let store = MemoryStore()
        let manager = CredentialManager(store: store, oauth: OAuthService(transport: transport))
        let soon = OAuthTokens(accessToken: "A", refreshToken: "R", expiresAt: .now.addingTimeInterval(60),
                               refreshedAt: .now)
        try await manager.save(.oauth(client: client, tokens: soon))

        async let first = manager.accessToken()
        async let second = manager.accessToken()
        let tokens = try await [first, second]
        #expect(tokens == ["A2", "A2"])
        #expect(transport.recorded.count == 1)

        // A credencial renovada foi persistida.
        let reloaded = CredentialManager(store: store)
        #expect(try await reloaded.accessToken() == "A2")
    }

    @Test func personalTokenIsReturnedAndNeverRefreshed() async throws {
        let manager = CredentialManager(store: MemoryStore())
        await #expect(throws: SmartThingsError.notAuthenticated) { try await manager.accessToken() }
        try await manager.save(.personalToken(token: "pat", expiresAt: .now.addingTimeInterval(3600)))
        #expect(try await manager.accessToken() == "pat")
        #expect(await !manager.recoverFromUnauthorized(rejected: "pat"))
        #expect(try await manager.summary()?.kind == .personalToken)
        try await manager.clear()
        #expect(try await manager.summary() == nil)
    }
}

@Suite("Diagnóstico")
struct DiagnosticTests {
    @Test func removesPersonalIdentifiers() throws {
        let status = try Fixtures.status()
        let data = try DiagnosticReport.make(status: status, health: .online,
                                             capabilities: ACInterpreter.capabilities(from: status),
                                             state: ACInterpreter.state(from: status))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("00000000-1111-2222-3333-444444444444"))
        #expect(!text.contains("Nome pessoal"))
        #expect(text.contains("MODELO-FICTICIO"))
        #expect(text.contains("supportedAcModes"))
    }

    @Test func detectsIdentifierPatterns() {
        #expect(DiagnosticReport.looksLikeIdentifier("AA:BB:CC:DD:EE:FF"))
        #expect(DiagnosticReport.looksLikeIdentifier("https://api.smartthings.com/x"))
        #expect(!DiagnosticReport.looksLikeIdentifier("cool"))
    }
}
