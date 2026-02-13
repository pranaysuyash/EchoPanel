import Foundation
import SwiftUI
import Combine

/// EntitlementsManager checks if features are enabled based on subscription tier and entitlements.
@MainActor
final class EntitlementsManager: ObservableObject {
    
    static let shared = EntitlementsManager()
    
    @Published var isPro: Bool = false
    
    private init() {
        Task {
            await updateEntitlements()
            
            NotificationCenter.default.publisher(for: .subscriptionStatusChanged)
                .sink { _ in
                    Task {
                        await self.updateEntitlements()
                    }
                }
                .store(in: &self.cancellables)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Feature Entitlements
    
    private struct FeatureEntitlement {
        let feature: String
        let requiresPro: Bool
        let betaOverride: Bool
    }
    
    private let featureEntitlements: [FeatureEntitlement] = [
        FeatureEntitlement(feature: "unlimited_sessions", requiresPro: true, betaOverride: false),
        FeatureEntitlement(feature: "all_asr_models", requiresPro: true, betaOverride: false),
        FeatureEntitlement(feature: "diarization_enabled", requiresPro: false, betaOverride: true),
        FeatureEntitlement(feature: "all_export_formats", requiresPro: true, betaOverride: false),
        FeatureEntitlement(feature: "export_json", requiresPro: false, betaOverride: false),
        FeatureEntitlement(feature: "export_markdown", requiresPro: false, betaOverride: false),
        FeatureEntitlement(feature: "export_bundle", requiresPro: false, betaOverride: false),
        FeatureEntitlement(feature: "unlimited_session_history", requiresPro: true, betaOverride: false),
        FeatureEntitlement(feature: "unlimited_rag_documents", requiresPro: true, betaOverride: false),
        FeatureEntitlement(feature: "priority_support", requiresPro: true, betaOverride: false),
        FeatureEntitlement(feature: "api_access", requiresPro: true, betaOverride: false),
        FeatureEntitlement(feature: "speaker_labels", requiresPro: false, betaOverride: true),
        FeatureEntitlement(feature: "realtime_entities", requiresPro: false, betaOverride: false),
        FeatureEntitlement(feature: "realtime_cards", requiresPro: false, betaOverride: false),
    ]
    
    // MARK: - Entitlement Checking
    
    func isFeatureEnabled(_ feature: String) async -> Bool {
        guard let entitlement = featureEntitlements.first(where: { $0.feature == feature }) else {
            return true
        }
        
        if entitlement.betaOverride {
            return BetaGatingManager.shared.isBetaAccessGranted
        }
        
        if !entitlement.requiresPro {
            return true
        }
        
        return isPro
    }
    
    func canAccessFeature(_ feature: String) async -> Bool {
        return await isFeatureEnabled(feature)
    }
    
    func getFeatureAccessMessage(_ feature: String) async -> String? {
        guard let entitlement = featureEntitlements.first(where: { $0.feature == feature }) else {
            return nil
        }
        
        let enabled = await isFeatureEnabled(feature)
        
        if enabled {
            return nil
        }
        
        if entitlement.betaOverride {
            return "This feature requires a valid invite code."
        }
        
        return "This feature is available with EchoPanel Pro."
    }
    
    // MARK: - ASR Model Entitlements
    
    func canAccessModel(_ model: String) async -> Bool {
        if model == "base.en" {
            return true
        }
        
        return await isFeatureEnabled("all_asr_models")
    }
    
    func getModelRestrictionMessage(_ model: String) async -> String? {
        if model == "base.en" {
            return nil
        }
        
        let canAccess = await canAccessModel(model)
        
        if canAccess {
            return nil
        }
        
        if BetaGatingManager.shared.isBetaAccessGranted {
            return nil
        }
        
        return "This model is available with EchoPanel Pro."
    }
    
    // MARK: - Session History Entitlements
    
    func getSessionHistoryLimit() async -> Int? {
        if await isFeatureEnabled("unlimited_session_history") {
            return nil
        }
        
        return 10
    }
    
    // MARK: - RAG Document Entitlements
    
    func getRAGDocumentLimit() async -> Int? {
        if await isFeatureEnabled("unlimited_rag_documents") {
            return nil
        }
        
        return 5
    }
    
    // MARK: - Export Entitlements
    
    func canExportFormat(_ format: String) async -> Bool {
        if format == "json" || format == "markdown" {
            return true
        }
        
        return await isFeatureEnabled("all_export_formats")
    }
    
    func getExportRestrictionMessage(_ format: String) async -> String? {
        if format == "json" || format == "markdown" {
            return nil
        }
        
        let canAccess = await canExportFormat(format)
        
        if canAccess {
            return nil
        }
        
        return "\(format.capitalized) export is available with EchoPanel Pro."
    }
    
    // MARK: - Update Handler
    
    private func updateEntitlements() async {
        let wasPro = isPro
        isPro = await SubscriptionManager.shared.isProFeatureEnabled()
        
        NSLog("EntitlementsManager: Pro status updated - was: \(wasPro), now: \(isPro)")
    }
}

extension Notification.Name {
    static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
}
