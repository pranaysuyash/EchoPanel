import Foundation
import Security

/// KeychainHelper provides secure storage for sensitive credentials.
/// Replaces UserDefaults for secrets like HuggingFace tokens.
enum KeychainHelper {
    private static let service = "com.echopanel.MeetingListenerApp"
    private static let hfTokenKey = "hfToken"
    private static let backendTokenKey = "backendToken"
    private static let openAIKeyKey = "openAIKey"
    
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

    /// Ensure there is a backend auth token stored in Keychain.
    ///
    /// This allows the local backend to be token-protected by default without forcing the
    /// user to manually provision a secret.
    @discardableResult
    static func ensureBackendToken() -> String? {
        if let existing = loadBackendToken(), !existing.isEmpty {
            return existing
        }

        // 256-bit random token, base64url (no padding).
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }

        var token = Data(bytes).base64EncodedString()
        token = token.replacingOccurrences(of: "+", with: "-")
        token = token.replacingOccurrences(of: "/", with: "_")
        token = token.replacingOccurrences(of: "=", with: "")

        guard saveBackendToken(token) else { return nil }
        return token
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
    
    // MARK: - OpenAI API Key
    
    static func saveOpenAIKey(_ key: String) -> Bool {
        guard !key.isEmpty else {
            _ = deleteOpenAIKey()
            return true
        }
        
        guard let data = key.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    static func loadOpenAIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }
    
    static func deleteOpenAIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
