import Foundation
import Security

protocol KeychainServiceProtocol: Sendable {
    func save(_ value: Data, account: String) async throws
    func read(account: String) async throws -> Data?
    func delete(account: String) async throws
}

struct KeychainService: KeychainServiceProtocol {
    private let service = "de.nico.mylove-sender"

    func save(_ value: Data, account: String) async throws {
        try await delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError.storageFailed }
    }

    func read(account: String) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AppError.storageFailed }
        return item as? Data
    }

    func delete(account: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.storageFailed }
    }
}

actor InMemoryKeychainService: KeychainServiceProtocol {
    private var storage: [String: Data] = [:]

    func save(_ value: Data, account: String) async throws { storage[account] = value }
    func read(account: String) async throws -> Data? { storage[account] }
    func delete(account: String) async throws { storage.removeValue(forKey: account) }
}
