import SwiftUI
import StoreKit

/// UpgradePromptView displays upgrade prompts when users reach session limits or try to access Pro features.
struct UpgradePromptView: View {
    
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @ObservedObject var betaGating = BetaGatingManager.shared
    
    @Binding var isPresented: Bool
    let reason: UpgradeReason
    
    enum UpgradeReason {
        case sessionLimitReached
        case featureRestricted(String)
        case upgradeRequested
    }
    
    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }
                
                upgradeSheet
                    .padding(.horizontal, 40)
                    .transition(.opacity)
            }
        }
    }
    
    private var upgradeSheet: some View {
        VStack(spacing: 24) {
            
            header
            
            Spacer()
            
            content
            
            Spacer()
            
            footer
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Upgrade to EchoPanel Pro")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
        }
    }
    
    private var content: some View {
        VStack(spacing: 16) {
            Text(upgradeTitle)
                .font(.headline)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text(upgradeDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            benefitsList
            
            subscriptionExpirationInfo
        }
    }
    
    private var upgradeTitle: String {
        switch reason {
        case .sessionLimitReached:
            return "Session Limit Reached"
            
        case .featureRestricted(let feature):
            return "Pro Feature: \(feature.capitalized)"
            
        case .upgradeRequested:
            return "Unlock All Pro Features"
        }
    }
    
    private var upgradeDescription: String {
        switch reason {
        case .sessionLimitReached:
            let remaining = betaGating.sessionsRemaining()
            if remaining > 0 {
                return "You have \(remaining) free sessions remaining this month. Upgrade to Pro for unlimited sessions."
            } else {
                return "You've used all \(betaGating.sessionLimit) free sessions this month. Upgrade to Pro for unlimited sessions."
            }
            
        case .featureRestricted:
            return "This feature is available with EchoPanel Pro. Upgrade now to unlock all Pro features."
            
        case .upgradeRequested:
            return "Get unlimited sessions, all ASR models, and priority support with EchoPanel Pro."
        }
    }
    
    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(icon: "checkmark.circle.fill", title: "Unlimited sessions")
            benefitRow(icon: "checkmark.circle.fill", title: "All ASR models")
            benefitRow(icon: "checkmark.circle.fill", title: "Advanced diarization")
            benefitRow(icon: "checkmark.circle.fill", title: "All export formats")
            benefitRow(icon: "checkmark.circle.fill", title: "Unlimited session history")
            benefitRow(icon: "checkmark.circle.fill", title: "Priority support")
        }
    }
    
    private func benefitRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 20)
            
            Text(title)
                .font(.body)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var subscriptionExpirationInfo: some View {
        let details = subscriptionManager.getSubscriptionDetails()
        
        if details.isSubscribed,
           let tier = subscriptionManager.subscriptionType?.displayName,
           let expiresAt = details.expiresAt {
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("You already have a \(tier) subscription")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Renews on \(subscriptionManager.formatExpirationDate(expiresAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var footer: some View {
        VStack(spacing: 12) {
            pricingOptions
            
            Button("Maybe Later") {
                isPresented = false
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    private var pricingOptions: some View {
        VStack(spacing: 12) {
            
            monthlyPlan
            
            annualPlan
            
            if !subscriptionManager.isLoadingProducts {
                Button("Restore Purchases") {
                    Task {
                        _ = await subscriptionManager.restorePurchases()
                        if subscriptionManager.isSubscribed {
                            isPresented = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(subscriptionManager.isLoading)
            }
        }
    }
    
    private var monthlyPlan: some View {
        let product = subscriptionManager.products.first { $0.id == SubscriptionManager.SubscriptionTier.monthly.rawValue }
        
        return pricingCard(
            product: product,
            tier: "Monthly",
            savings: nil
        )
    }
    
    private var annualPlan: some View {
        let product = subscriptionManager.products.first { $0.id == SubscriptionManager.SubscriptionTier.annual.rawValue }
        
        let monthlyProduct = subscriptionManager.products.first { $0.id == SubscriptionManager.SubscriptionTier.monthly.rawValue }
        
        let monthlyPrice = monthlyProduct?.displayPrice ?? "$12"
        let annualPrice = product?.displayPrice ?? "$120"
        let savings = calculateAnnualSavings(monthly: monthlyPrice, annual: annualPrice)
        
        return pricingCard(
            product: product,
            tier: "Annual",
            savings: savings
        )
    }
    
    private func pricingCard(product: Product?, tier: String, savings: String?) -> some View {
        Button {
            if let product = product {
                Task {
                    _ = await subscriptionManager.purchaseSubscription(product.id)
                    if subscriptionManager.isSubscribed {
                        isPresented = false
                    }
                }
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tier)
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    if let price = product?.displayPrice {
                        Text(price + "/mo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let savings = savings {
                        Text(savings)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    if let product = product {
                        Text("Subscribe")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 2)
            )
        }
        .disabled(product == nil)
    }
    
    private func calculateAnnualSavings(monthly: String, annual: String) -> String {
        let monthlyValue = Double(monthly.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "/mo", with: "")) ?? 12
        let annualValue = Double(annual.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "/mo", with: "")) ?? 120
        
        let monthlyTotal = monthlyValue * 12
        let savings = monthlyTotal - annualValue
        let savingsPercent = Int((savings / monthlyTotal) * 100)
        
        return "Save \(savingsPercent)%"
    }
}
