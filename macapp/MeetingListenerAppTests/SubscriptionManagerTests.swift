import XCTest
@testable import MeetingListenerApp

final class SubscriptionManagerTests: XCTestCase {
    
    func testSubscriptionTierDisplayNames() {
        XCTAssertEqual(SubscriptionManager.SubscriptionTier.monthly.displayName, "Monthly")
        XCTAssertEqual(SubscriptionManager.SubscriptionTier.annual.displayName, "Annual")
        XCTAssertEqual(SubscriptionManager.SubscriptionTier.monthly.rawValue, "echopanel_pro_monthly")
        XCTAssertEqual(SubscriptionManager.SubscriptionTier.annual.rawValue, "echopanel_pro_annual")
    }
    
    func testSubscriptionStatusCases() {
        let notSubscribed = SubscriptionManager.SubscriptionStatus.notSubscribed
        let active = SubscriptionManager.SubscriptionStatus.active(expiresAt: Date())
        let expired = SubscriptionManager.SubscriptionStatus.expired(expiresAt: Date())
        let inBillingRetry = SubscriptionManager.SubscriptionStatus.inBillingRetry
        let unknown = SubscriptionManager.SubscriptionStatus.unknown
        
        XCTAssertNotEqual(notSubscribed, active)
        XCTAssertNotEqual(active, expired)
    }
    
    func testCanAccessFreeFeature() {
        let manager = EntitlementsManager.shared
        
        XCTAssertTrue(Task {
            await manager.canAccessFeature("export_json")
        }.value)
        
        XCTAssertTrue(Task {
            await manager.canAccessFeature("export_markdown")
        }.value)
        
        XCTAssertTrue(Task {
            await manager.canAccessFeature("speaker_labels")
        }.value)
    }
    
    func testFeatureEntitlementMapping() {
        let entitlements = EntitlementsManager.shared
        
        XCTAssertFalse(Task {
            await entitlements.isFeatureEnabled("unlimited_sessions")
        }.value)
        
        XCTAssertFalse(Task {
            await entitlements.isFeatureEnabled("all_asr_models")
        }.value)
        
        XCTAssertFalse(Task {
            await entitlements.isFeatureEnabled("priority_support")
        }.value)
    }
    
    func testBaseModelAccess() {
        let entitlements = EntitlementsManager.shared
        
        XCTAssertTrue(Task {
            await entitlements.canAccessModel("base.en")
        }.value)
    }
    
    func testSessionHistoryLimitNotPro() {
        let entitlements = EntitlementsManager.shared
        
        XCTAssertEqual(Task {
            await entitlements.getSessionHistoryLimit()
        }.value, 10)
    }
    
    func testRAGDocumentLimitNotPro() {
        let entitlements = EntitlementsManager.shared
        
        XCTAssertEqual(Task {
            await entitlements.getRAGDocumentLimit()
        }.value, 5)
    }
    
    func testFreeExportFormats() {
        let entitlements = EntitlementsManager.shared
        
        XCTAssertTrue(Task {
            await entitlements.canExportFormat("json")
        }.value)
        
        XCTAssertTrue(Task {
            await entitlements.canExportFormat("markdown")
        }.value)
        
        XCTAssertFalse(Task {
            await entitlements.canExportFormat("bundle")
        }.value)
        
        XCTAssertFalse(Task {
            await entitlements.canExportFormat("pdf")
        }.value)
    }
    
    func testFeatureAccessMessageFree() {
        let entitlements = EntitlementsManager.shared
        
        XCTAssertNil(Task {
            await entitlements.getFeatureAccessMessage("export_json")
        }.value)
        
        XCTAssertNotNil(Task {
            await entitlements.getFeatureAccessMessage("unlimited_sessions")
        }.value)
    }
    
    func testModelRestrictionMessageFree() {
        let entitlements = EntitlementsManager.shared
        
        XCTAssertNil(Task {
            await entitlements.getModelRestrictionMessage("base.en")
        }.value)
    }
}
