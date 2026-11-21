import Foundation
import Security

/// Keeps the Anthropic API key in the Keychain (a generic password item), never in files or settings.
public struct APIKeyStore: Sendable {
    public enum Failure: Error, Equatable { case keychain(OSStatus) }

    private let service: String
    private let account = "anthropic-api-key"

    public init(service: String = "com.rteves.GarageVirtus") {
        self.service = service
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    public func save(_ key: String) throws {
        delete()
        var item = baseQuery
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
