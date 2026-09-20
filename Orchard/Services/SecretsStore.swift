import Foundation
import Security

/// Minimal secret storage keyed by an account string. Production uses the keychain so
/// credentials never sit in UserDefaults; tests inject the in-memory variant so they
/// never touch the real keychain.
protocol SecretsStore: Sendable {
    func secret(for account: String) -> String?
    /// nil or empty removes the stored secret. Throws when the store refuses the write:
    /// a credential that silently failed to save looks exactly like one that saved, which
    /// is what made a rejected keychain write impossible to tell from a rejected API key
    /// (#110).
    func setSecret(_ value: String?, for account: String) throws
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

    func setSecret(_ value: String?, for account: String) throws {
        // Deleting what was never there is the normal path for a first save, not a failure.
        let deleted = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if deleted != errSecSuccess, deleted != errSecItemNotFound {
            throw Self.error(deleted, doing: "clear")
        }
        guard let value, !value.isEmpty else { return }
        var add = baseQuery(account: account)
        add[kSecValueData as String] = Data(value.utf8)
        let added = SecItemAdd(add as CFDictionary, nil)
        if added != errSecSuccess {
            throw Self.error(added, doing: "save")
        }
    }

    /// Turn an `OSStatus` into something a user can act on. The numeric code goes in
    /// alongside the message because the common failures here (a locked keychain, a
    /// signature the keychain won't accept) are searchable by code and not much else.
    private static func error(_ status: OSStatus, doing verb: String) -> Error {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "unknown keychain error"
        return OrchardError.generic("Could not \(verb) the API key in the keychain: \(detail) (\(status)).")
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

    func setSecret(_ value: String?, for account: String) throws {
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
