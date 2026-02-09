import Foundation
import Security

/// KeychainHelper provides secure storage for sensitive credentials.
/// Replaces UserDefaults for secrets like HuggingFace tokens.
enum KeychainHelper {
    private static let service = "com.echopanel.MeetingListenerApp"
    private static let tokenKey = "hfToken"
    
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
            kSecAttrAccount as String: tokenKey,
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
            kSecAttrAccount as String: tokenKey,
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
            kSecAttrAccount as String: tokenKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Migration
    
    /// Migrates HF token from UserDefaults to Keychain if present.
    /// Returns true if migration occurred or no migration was needed.
    @discardableResult
    static func migrateFromUserDefaults() -> Bool {
        // Check if already in Keychain
        guard loadHFToken() == nil else { return true }
        
        // Check UserDefaults for legacy token
        guard let legacyToken = UserDefaults.standard.string(forKey: "hfToken"),
              !legacyToken.isEmpty else {
            return true
        }
        
        // Migrate to Keychain
        if saveHFToken(legacyToken) {
            // Delete from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: "hfToken")
            return true
        }
        
        return false
    }
}
