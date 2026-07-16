//
//  KeychainHelper.swift
//  Reader for Language Learner
//
//  Minimal Security.framework wrapper for generic-password items. Exists so
//  cloud LLM API keys live in the Keychain instead of plaintext UserDefaults.
//  No external dependencies — SecItem* only.
//

import Foundation
import Security

enum KeychainHelper {

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Returns the stored string, or nil when absent (or unreadable).
    static func read(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Inserts or updates the item. Returns whether the write succeeded.
    @discardableResult
    static func write(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(service: service, account: account)

        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    /// Removes the item. Missing items count as success.
    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
