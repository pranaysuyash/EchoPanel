import Foundation
import StoreKit

/// ReceiptValidator validates App Store receipts using StoreKit 2.
final class ReceiptValidator {
    
    /// Validate that the user has an active subscription.
    func hasActiveSubscription() async -> Bool {
        do {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    switch transaction.productType {
                    case .autoRenewable:
                        if let expirationDate = transaction.expirationDate {
                            return expirationDate > Date()
                        } else {
                            return true
                        }
                        
                    default:
                        continue
                    }
                }
            }
            return false
        } catch {
            NSLog("ReceiptValidator: Error checking subscription status: \(error)")
            return false
        }
    }
    
    /// Get subscription expiration date if active.
    func getSubscriptionExpirationDate() async -> Date? {
        do {
            var latestExpiration: Date?
            
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    switch transaction.productType {
                    case .autoRenewable:
                        if let expirationDate = transaction.expirationDate {
                            if latestExpiration == nil || expirationDate > latestExpiration! {
                                latestExpiration = expirationDate
                            }
                        }
                        
                    default:
                        continue
                    }
                }
            }
            
            return latestExpiration
        } catch {
            NSLog("ReceiptValidator: Error getting expiration date: \(error)")
            return nil
        }
    }
    
    /// Get subscription tier (monthly or annual).
    func getSubscriptionTier() async -> String? {
        do {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    switch transaction.productType {
                    case .autoRenewable:
                        if let expirationDate = transaction.expirationDate {
                            if expirationDate > Date() {
                                return transaction.productID
                            }
                        } else {
                            return transaction.productID
                        }
                        
                    default:
                        continue
                    }
                }
            }
            return nil
        } catch {
            NSLog("ReceiptValidator: Error getting subscription tier: \(error)")
            return nil
        }
    }
}
