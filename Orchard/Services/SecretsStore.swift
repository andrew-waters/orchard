import Foundation
import Security

/// Minimal secret storage keyed by an account string. Production uses the keychain so
/// credentials never sit in UserDefaults; tests inject the in-memory variant so they
/// never touch the real keychain.
protocol SecretsStore: Sendable {
    func secret(for account: String) -> String?
    /// nil or empty removes the stored secret.
    func setSecret(_ value: String?, for account: String)
    func allSecrets() -> [String: String]
}

/// Generic-password keychain items under a single service name, one item per account.
struct KeychainSecretsStore: SecretsStore {
    let service: String

    init(service: String = "dev.andon.orchard.model-api-keys") {
        self.service = service
    }

    func secret(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String?, for account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = baseQuery(account: account)
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    func allSecrets() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let attributeList = items as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for attributes in attributeList {
            if let account = attributes[kSecAttrAccount as String] as? String,
               let data = attributes[kSecValueData as String] as? Data,
               let value = String(data: data, encoding: .utf8) {
                result[account] = value
            }
        }
        return result
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Test double: a locked dictionary, no keychain involvement.
final class InMemorySecretsStore: SecretsStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func secret(for account: String) -> String? {
        lock.withLock { storage[account] }
    }

    func setSecret(_ value: String?, for account: String) {
        lock.withLock {
            if let value, !value.isEmpty {
                storage[account] = value
            } else {
                storage.removeValue(forKey: account)
            }
        }
    }

    func allSecrets() -> [String: String] {
        lock.withLock { storage }
    }
}
