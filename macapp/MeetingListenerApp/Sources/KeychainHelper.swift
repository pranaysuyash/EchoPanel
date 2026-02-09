import Foundation
import Security

/// KeychainHelper provides secure storage for sensitive credentials.
/// Replaces UserDefaults for secrets like HuggingFace tokens.
enum KeychainHelper {
    private static let service = "com.echopanel.MeetingListenerApp"
    private static let hfTokenKey = "hfToken"
    private static let backendTokenKey = "backendToken"
    
    // MARK: - HuggingFace Token
    
    static func saveHFToken(_ token: String) -> Bool {
        guard !token.isEmpty else {
            _ = deleteHFToken()
            return true
        }
        
        guard let data = token.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hfTokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    static func loadHFToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hfTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    static func deleteHFToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hfTokenKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Backend WS Token

    static func saveBackendToken(_ token: String) -> Bool {
        guard !token.isEmpty else {
            _ = deleteBackendToken()
            return true
        }

        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backendTokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func loadBackendToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backendTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func deleteBackendToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backendTokenKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Migration
    
    /// Migrates HF token from UserDefaults to Keychain if present.
    /// Returns true if migration occurred or no migration was needed.
    @discardableResult
    static func migrateFromUserDefaults() -> Bool {
        var success = true

        if loadHFToken() == nil,
           let legacyHFToken = UserDefaults.standard.string(forKey: "hfToken"),
           !legacyHFToken.isEmpty {
            if saveHFToken(legacyHFToken) {
                UserDefaults.standard.removeObject(forKey: "hfToken")
            } else {
                success = false
            }
        }

        if loadBackendToken() == nil,
           let legacyBackendToken = UserDefaults.standard.string(forKey: "backendToken"),
           !legacyBackendToken.isEmpty {
            if saveBackendToken(legacyBackendToken) {
                UserDefaults.standard.removeObject(forKey: "backendToken")
            } else {
                success = false
            }
        }

        return success
    }
}
