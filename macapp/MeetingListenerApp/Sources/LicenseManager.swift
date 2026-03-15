import Foundation
import Combine

/// License validation states
enum LicenseState: Equatable {
    case unknown           // Not checked yet
    case valid            // Valid license stored
    case invalid(String)  // Invalid with reason
    case validating       // Validation in progress
    case noLicense        // No license stored
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

/// Errors that can occur during license validation
enum LicenseError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case invalidLicense(String)
    case serverError(Int)
    case keychainError
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from license server"
        case .invalidLicense(let message):
            return message
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .keychainError:
            return "Failed to access secure storage"
        }
    }
}

/// Gumroad license validation response
struct GumroadLicenseResponse: Codable {
    let success: Bool
    let uses: Int?
    let message: String?
    let purchase: GumroadPurchase?
    
    struct GumroadPurchase: Codable {
        let id: String
        let productId: String
        let productName: String
        let createdAt: String
        let variants: String?
        let quantity: Int
        
        enum CodingKeys: String, CodingKey {
            case id
            case productId = "product_id"
            case productName = "product_name"
            case createdAt = "created_at"
            case variants
            case quantity
        }
    }
}

/// Cached license validation result for offline use
struct CachedLicenseValidation: Codable {
    let licenseKey: String
    let validatedAt: Date
    let isValid: Bool
    let productId: String
    let purchaseId: String?
    
    /// Cache is valid for 7 days
    var isCacheValid: Bool {
        let sevenDays: TimeInterval = 7 * 24 * 60 * 60
        return Date().timeIntervalSince(validatedAt) < sevenDays
    }
}

/// Manages license validation with Gumroad
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published private(set) var state: LicenseState = .unknown
    @Published private(set) var lastValidated: Date?
    
    // Gumroad API configuration
    private let gumroadApiUrl = "https://api.gumroad.com/v2/licenses/verify"
    
    // Product ID - should be set via environment or config
    // This is the default for EchoPanel - override for testing
    var productId: String {
        get {
            UserDefaults.standard.string(forKey: "gumroadProductId") ?? "DEMO_PRODUCT_ID"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "gumroadProductId")
        }
    }
    
    private let validationCacheKey = "licenseValidationCache"
    private let licenseKeyKey = "licenseKey"
    private let service = "com.echopanel.MeetingListenerApp.license"
    
    private init() {
        // Check for existing license on init
        Task {
            await checkStoredLicense()
        }
    }
    
    // MARK: - Public API
    
    /// Check if we have a valid license (cached or stored)
    func checkLicense() async -> Bool {
        // First check if we have a stored validation cache
        if let cached = loadCachedValidation(), cached.isCacheValid, cached.isValid {
            state = .valid
            lastValidated = cached.validatedAt
            return true
        }
        
        // No valid cache, check if we have a stored key
        guard let licenseKey = loadLicenseKey() else {
            state = .noLicense
            return false
        }
        
        // Validate the stored key
        do {
            let isValid = try await validateWithGumroad(licenseKey: licenseKey)
            if isValid {
                state = .valid
                lastValidated = Date()
            } else {
                state = .invalid("License validation failed")
            }
            return isValid
        } catch {
            state = .invalid(error.localizedDescription)
            return false
        }
    }
    
    /// Validate a license key against Gumroad
    func validateLicenseKey(_ licenseKey: String) async throws -> Bool {
        state = .validating
        
        do {
            let isValid = try await validateWithGumroad(licenseKey: licenseKey)
            
            if isValid {
                // Store the valid license
                guard saveLicenseKey(licenseKey) else {
                    throw LicenseError.keychainError
                }
                state = .valid
                lastValidated = Date()
            } else {
                state = .invalid("Invalid license key")
            }
            
            return isValid
        } catch {
            state = .invalid(error.localizedDescription)
            throw error
        }
    }
    
    /// Clear stored license
    func clearLicense() {
        _ = deleteLicenseKey()
        deleteCachedValidation()
        state = .noLicense
        lastValidated = nil
    }
    
    /// Get current license key (masked for display)
    var maskedLicenseKey: String? {
        guard let key = loadLicenseKey() else { return nil }
        guard key.count > 8 else { return "***" }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)****\(suffix)"
    }
    
    // MARK: - Private Methods
    
    private func checkStoredLicense() async {
        _ = await checkLicense()
    }
    
    private func validateWithGumroad(licenseKey: String) async throws -> Bool {
        guard !productId.isEmpty, productId != "DEMO_PRODUCT_ID" else {
            // In development/demo mode, accept any license key format
            #if DEBUG
            StructuredLogger.shared.info("License validation skipped in DEBUG mode", metadata: [:])
            return true
            #else
            throw LicenseError.invalidLicense("Product ID not configured")
            #endif
        }
        
        var request = URLRequest(url: URL(string: gumroadApiUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "product_id": productId,
            "license_key": licenseKey,
            "increment_uses_count": "false"
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LicenseError.serverError(httpResponse.statusCode)
        }
        
        do {
            let gumroadResponse = try JSONDecoder().decode(GumroadLicenseResponse.self, from: data)
            
            // Cache the validation result
            let cached = CachedLicenseValidation(
                licenseKey: licenseKey,
                validatedAt: Date(),
                isValid: gumroadResponse.success,
                productId: productId,
                purchaseId: gumroadResponse.purchase?.id
            )
            saveCachedValidation(cached)
            
            if !gumroadResponse.success {
                let message = gumroadResponse.message ?? "Invalid license key"
                throw LicenseError.invalidLicense(message)
            }
            
            return true
        } catch {
            if error is LicenseError {
                throw error
            }
            throw LicenseError.invalidResponse
        }
    }
    
    // MARK: - Keychain Storage
    
    private func saveLicenseKey(_ key: String) -> Bool {
        guard !key.isEmpty else {
            return deleteLicenseKey()
        }
        
        guard let data = key.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: licenseKeyKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func loadLicenseKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: licenseKeyKey,
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
    
    private func deleteLicenseKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: licenseKeyKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Cache Storage (UserDefaults - non-sensitive)
    
    private func saveCachedValidation(_ cached: CachedLicenseValidation) {
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: validationCacheKey)
        }
    }
    
    private func loadCachedValidation() -> CachedLicenseValidation? {
        guard let data = UserDefaults.standard.data(forKey: validationCacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CachedLicenseValidation.self, from: data)
    }
    
    private func deleteCachedValidation() {
        UserDefaults.standard.removeObject(forKey: validationCacheKey)
    }
}

// MARK: - SwiftUI Helpers

extension LicenseManager {
    /// Status color for UI
    var statusColor: String {
        switch state {
        case .valid:
            return "green"
        case .invalid:
            return "red"
        case .validating:
            return "yellow"
        case .noLicense, .unknown:
            return "gray"
        }
    }
    
    /// Status message for UI
    var statusMessage: String {
        switch state {
        case .valid:
            return "Licensed"
        case .invalid(let reason):
            return "Invalid: \(reason)"
        case .validating:
            return "Validating..."
        case .noLicense:
            return "No license"
        case .unknown:
            return "Checking..."
        }
    }
}
