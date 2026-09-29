import Foundation
import Security

enum TrustKeychain {
    private static let service = "com.collapsetechnologies.trust.session"

    /// Xcode's ad hoc simulator signature has no application-identifier entitlement,
    /// so Security returns errSecMissingEntitlement. UI tests use isolated disposable
    /// accounts; keep their persistence behavior testable without changing Release or
    /// ordinary Debug keychain behavior.
    private static var usesUITestStorage: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TRUST_UI_TEST"] == "1"
        #else
        false
        #endif
    }

    private static func testStorageKey(account: String) -> String {
        "trust.ui-test.keychain.\(service).\(account)"
    }

    static func set(_ value: String, account: String) {
        if usesUITestStorage {
            UserDefaults.standard.set(value, forKey: testStorageKey(account: account))
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        if usesUITestStorage {
            return UserDefaults.standard.string(forKey: testStorageKey(account: account))
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func delete(account: String) {
        if usesUITestStorage {
            UserDefaults.standard.removeObject(forKey: testStorageKey(account: account))
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
