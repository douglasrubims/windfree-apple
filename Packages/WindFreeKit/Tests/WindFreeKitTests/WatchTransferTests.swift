import Foundation
import Testing
@testable import WindFreeKit

@Suite("Mensagens iPhone ↔ Apple Watch")
struct WatchTransferTests {
    @Test func credentialRoundTrip() throws {
        let client = OAuthClientConfiguration(clientID: "id", clientSecret: "segredo-ficticio",
                                              redirectURI: OAuthService.smartThingsRedirectURI)
        let tokens = OAuthTokens(accessToken: "A", refreshToken: "R", expiresAt: Date(timeIntervalSince1970: 100),
                                 refreshedAt: Date(timeIntervalSince1970: 50))
        let credential = StoredCredential.oauth(client: client, tokens: tokens)
        let message = try WatchTransfer.message(for: credential)
        #expect(WatchTransfer.decode(message) == .credential(credential))
    }

    @Test func signOutAndGarbage() {
        #expect(WatchTransfer.decode(WatchTransfer.signOutMessage) == .signOut)
        #expect(WatchTransfer.decode(["credential": Data("não é json".utf8)]) == nil)
        #expect(WatchTransfer.decode([:]) == nil)
    }
}
