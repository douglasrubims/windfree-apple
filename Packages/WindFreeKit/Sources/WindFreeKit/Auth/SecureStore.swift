import Foundation
import Security

/// Armazenamento de dados sensíveis. Em produção, o Keychain; nos testes, memória.
public protocol SecureStore: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, for key: String) throws
    func delete(_ key: String) throws
}

public struct KeychainError: Error, Sendable, Equatable {
    public let status: OSStatus
}

/// Itens de senha genérica no Keychain do aparelho. Nada é sincronizado pelo iCloud
/// (`kSecAttrSynchronizable` desligado) e os itens só ficam acessíveis com o aparelho desbloqueado.
public struct KeychainStore: SecureStore {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
    }

    public func read(_ key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    public func write(_ data: Data, for key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query(key)
            insert.merge(attributes) { _, new in new }
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Armazenamento em memória para testes e para o modo simulado.
public final class MemoryStore: SecureStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func read(_ key: String) throws -> Data? {
        lock.withLock { items[key] }
    }

    public func write(_ data: Data, for key: String) throws {
        lock.withLock { items[key] = data }
    }

    public func delete(_ key: String) throws {
        _ = lock.withLock { items.removeValue(forKey: key) }
    }
}
