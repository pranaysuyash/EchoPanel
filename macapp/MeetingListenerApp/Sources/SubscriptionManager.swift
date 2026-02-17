import Foundation
import StoreKit
import Combine

/// SubscriptionManager handles in-app purchases, subscription management, and entitlement checks.
@MainActor
final class SubscriptionManager: ObservableObject {
    
    static let shared = SubscriptionManager()
    
    @Published var isSubscribed: Bool = false
    @Published var subscriptionType: SubscriptionTier?
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published var products: [Product] = []
    @Published var isLoadingProducts: Bool = false
    @Published var purchaseError: String?
    @Published var isLoading: Bool = false
    
    private var updateListenerTask: Task<Void, Never>?
    
    enum SubscriptionTier: String, CaseIterable {
        case monthly = "echopanel_pro_monthly"
        case annual = "echopanel_pro_annual"
        
        var displayName: String {
            switch self {
            case .monthly: return "Monthly"
            case .annual: return "Annual"
            }
        }
    }
    
    enum SubscriptionStatus: Equatable {
        case notSubscribed
        case active(expiresAt: Date)
        case expired(expiresAt: Date)
        case inBillingRetry
        case unknown
    }
    
    private init() {
        Task {
            await loadProducts()
            await checkSubscriptionStatus()
            await listenForUpdates()
        }
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        isLoadingProducts = true
        
        do {
            let productIds: Set<String> = [
                SubscriptionTier.monthly.rawValue,
                SubscriptionTier.annual.rawValue
            ]
            
            products = try await Product.products(for: productIds)
            NSLog("SubscriptionManager: Loaded \(products.count) products")
            
            products.forEach { product in
                NSLog("SubscriptionManager: Product - \(product.id): \(product.displayPrice)")
            }
        } catch {
            NSLog("SubscriptionManager: Failed to load products: \(error)")
            purchaseError = "Failed to load products. Please check your internet connection."
        }
        
        isLoadingProducts = false
    }
    
    // MARK: - Purchase Operations
    
    func purchaseSubscription(_ productId: String) async -> Bool {
        isLoading = true
        purchaseError = nil
        
        guard let product = products.first(where: { $0.id == productId }) else {
            purchaseError = "Product not found"
            isLoading = false
            return false
        }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                NSLog("SubscriptionManager: Purchase successful: \(productId)")
                await handleSuccessfulPurchase(result: verification, product: product)
                return true
                
            case .userCancelled:
                NSLog("SubscriptionManager: Purchase cancelled by user")
                purchaseError = "Purchase was cancelled."
                return false
                
            case .pending:
                NSLog("SubscriptionManager: Purchase pending")
                purchaseError = "Purchase is pending approval."
                return false
                
            @unknown default:
                NSLog("SubscriptionManager: Purchase failed: unknown result")
                purchaseError = "Purchase failed. Please try again."
                return false
            }
        } catch {
            NSLog("SubscriptionManager: Purchase error: \(error)")
            purchaseError = "Purchase failed: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    func restorePurchases() async -> Bool {
        isLoading = true
        purchaseError = nil
        
        do {
            try await AppStore.sync()
            NSLog("SubscriptionManager: AppStore.sync() completed")
            
            await checkSubscriptionStatus()
            isLoading = false
            return true
        } catch {
            NSLog("SubscriptionManager: Restore failed: \(error)")
            purchaseError = "Failed to restore purchases: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    // MARK: - Subscription Status
    
    private func checkSubscriptionStatus() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await handleTransaction(transaction)
            }
        }
        
        await updateSubscriptionStatus()
    }
    
    private func listenForUpdates() async {
        updateListenerTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await handleTransaction(transaction)
                }
            }
        }
    }
    
    private func handleTransaction(_ transaction: Transaction) async {
        switch transaction.productType {
        case .autoRenewable:
            if let expirationDate = transaction.expirationDate {
                let now = Date()
                
                if expirationDate > now {
                    subscriptionStatus = .active(expiresAt: expirationDate)
                    isSubscribed = true
                    
                    if transaction.productID == SubscriptionTier.annual.rawValue {
                        subscriptionType = .annual
                    } else {
                        subscriptionType = .monthly
                    }
                } else {
                    subscriptionStatus = .expired(expiresAt: expirationDate)
                    isSubscribed = false
                }
                
                NSLog("SubscriptionManager: Subscription status updated - active: \(isSubscribed), expires: \(expirationDate)")
            } else {
                subscriptionStatus = .active(expiresAt: Date.distantFuture)
                isSubscribed = true
            }
            
        case .nonRenewable:
            await transaction.finish()
            NSLog("SubscriptionManager: Finished non-renewable transaction: \(transaction.id)")
            
        case .consumable:
            await transaction.finish()
            NSLog("SubscriptionManager: Finished consumable transaction: \(transaction.id)")
            
        default:
            NSLog("SubscriptionManager: Unknown product type: \(transaction.productType)")
        }
    }
    
    private func updateSubscriptionStatus() async {
        do {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    switch transaction.productType {
                    case .autoRenewable:
                        if let expirationDate = transaction.expirationDate {
                            if expirationDate > Date() {
                                subscriptionStatus = .active(expiresAt: expirationDate)
                                isSubscribed = true
                                
                                if transaction.productID == SubscriptionTier.annual.rawValue {
                                    subscriptionType = .annual
                                } else {
                                    subscriptionType = .monthly
                                }
                            } else {
                                subscriptionStatus = .expired(expiresAt: expirationDate)
                                isSubscribed = false
                            }
                        } else {
                            subscriptionStatus = .active(expiresAt: Date.distantFuture)
                            isSubscribed = true
                        }
                        
                    default:
                        break
                    }
                }
            }
        } catch {
            NSLog("SubscriptionManager: Failed to update subscription status: \(error)")
        }
    }
    
    // MARK: - Purchase Handling
    
    private func handleSuccessfulPurchase(result: VerificationResult<Transaction>, product: Product) async {
        switch result {
        case .verified(let transaction):
            await handleTransaction(transaction)
            
            NSLog("SubscriptionManager: Subscription purchased: \(product.id)")
            
        case .unverified(_, let error):
            NSLog("SubscriptionManager: Purchase verification failed: \(error)")
            purchaseError = "Purchase verification failed. Please contact support."
        }
        
        isLoading = false
    }
    
    // MARK: - Entitlement Checks
    
    func isProFeatureEnabled() -> Bool {
        return isSubscribed
    }
    
    func canAccessFeature(_ feature: String) -> Bool {
        switch feature {
        case "unlimited_sessions",
             "all_asr_models",
             "diarization_enabled",
             "all_export_formats",
             "unlimited_session_history",
             "unlimited_rag_documents",
             "priority_support",
             "api_access":
            return isProFeatureEnabled()
            
        default:
            return true
        }
    }
    
    func getSubscriptionDetails() -> (isSubscribed: Bool, tier: String?, expiresAt: Date?) {
        guard isSubscribed else {
            return (false, nil, nil)
        }
        
        switch subscriptionStatus {
        case .active(let expiresAt):
            return (true, subscriptionType?.displayName, expiresAt)
            
        case .expired(let expiresAt):
            return (false, subscriptionType?.displayName, expiresAt)
            
        default:
            return (false, nil, nil)
        }
    }
    
    func formatExpirationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Cleanup
    
    deinit {
        updateListenerTask?.cancel()
    }
}

// MARK: - ASR Tier Bridge

extension SubscriptionManager {
    /// Returns true if Pro features are enabled
    var isASRTierPro: Bool {
        isProFeatureEnabled()
    }
}
