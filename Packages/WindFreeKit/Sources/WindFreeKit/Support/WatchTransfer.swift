import Foundation

/// Mensagens entre o iPhone e o Apple Watch (WatchConnectivity). Só são enviadas com o app do relógio aberto
/// (`sendMessage`), para que a credencial não fique gravada fora do Keychain em filas de entrega.
public enum WatchTransfer {
    public static let credentialKey = "credential"
    public static let signOutKey = "signOut"

    public static func message(for credential: StoredCredential) throws -> [String: Any] {
        [credentialKey: try JSONEncoder().encode(credential)]
    }

    public static var signOutMessage: [String: Any] { [signOutKey: true] }

    public enum Received: Sendable, Equatable {
        case credential(StoredCredential)
        case signOut
    }

    public static func decode(_ message: [String: Any]) -> Received? {
        if message[signOutKey] as? Bool == true { return .signOut }
        guard let data = message[credentialKey] as? Data,
              let credential = try? JSONDecoder().decode(StoredCredential.self, from: data)
        else { return nil }
        return .credential(credential)
    }
}
