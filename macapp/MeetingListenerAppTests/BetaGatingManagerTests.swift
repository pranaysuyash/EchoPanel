import XCTest
@testable import MeetingListenerApp

final class BetaGatingManagerTests: XCTestCase {
    
    func testValidateInviteCodeValid() {
        let manager = BetaGatingManager.shared
        
        let result = manager.validateInviteCode("ECHOPANEL-BETA-2024")
        
        XCTAssertTrue(result, "Valid invite code should return true")
        XCTAssertTrue(manager.isBetaAccessGranted, "Beta access should be granted")
        XCTAssertEqual(manager.validatedInviteCode?.uppercased(), "ECHOPANEL-BETA-2024", "Invite code should be stored")
    }
    
    func testValidateInviteCodeInvalid() {
        let manager = BetaGatingManager.shared
        
        let result = manager.validateInviteCode("INVALID-CODE")
        
        XCTAssertFalse(result, "Invalid invite code should return false")
        XCTAssertFalse(manager.isBetaAccessGranted, "Beta access should not be granted")
    }
    
    func testValidateInviteCodeCaseInsensitive() {
        let manager = BetaGatingManager.shared
        
        let result = manager.validateInviteCode("echopanel-beta-2024")
        
        XCTAssertTrue(result, "Invite code should be case-insensitive")
    }
    
    func testValidateInviteCodeTrimming() {
        let manager = BetaGatingManager.shared
        
        let result = manager.validateInviteCode("  ECHOPANEL-BETA-2024  ")
        
        XCTAssertTrue(result, "Invite code should be trimmed")
    }
    
    func testSessionCountIncrement() {
        let manager = BetaGatingManager.shared
        
        let initialCount = manager.sessionsThisMonth
        
        manager.incrementSessionCount()
        
        XCTAssertEqual(manager.sessionsThisMonth, initialCount + 1, "Session count should increment")
    }
    
    func testCanStartSessionWhenLimitNotReached() {
        let manager = BetaGatingManager.shared
        
        manager.validateInviteCode("ECHOPANEL-BETA-2024")
        manager.sessionsThisMonth = 5
        
        XCTAssertTrue(manager.canStartSession(), "Should be able to start session when limit not reached")
    }
    
    func testCanStartSessionWhenLimitReached() {
        let manager = BetaGatingManager.shared
        
        manager.validateInviteCode("ECHOPANEL-BETA-2024")
        manager.sessionsThisMonth = manager.sessionLimit
        
        XCTAssertFalse(manager.canStartSession(), "Should not be able to start session when limit reached")
    }
    
    func testCanStartSessionWithoutBetaAccess() {
        let manager = BetaGatingManager.shared
        
        XCTAssertFalse(manager.canStartSession(), "Should not be able to start session without beta access")
    }
    
    func testSessionsRemaining() {
        let manager = BetaGatingManager.shared
        
        manager.validateInviteCode("ECHOPANEL-BETA-2024")
        manager.sessionsThisMonth = 5
        
        XCTAssertEqual(manager.sessionsRemaining(), 15, "Sessions remaining should be calculated correctly")
    }
    
    func testSessionsRemainingWhenAtLimit() {
        let manager = BetaGatingManager.shared
        
        manager.validateInviteCode("ECHOPANEL-BETA-2024")
        manager.sessionsThisMonth = manager.sessionLimit
        
        XCTAssertEqual(manager.sessionsRemaining(), 0, "Sessions remaining should be 0 at limit")
    }
    
    func testSessionsRemainingNeverNegative() {
        let manager = BetaGatingManager.shared
        
        manager.validateInviteCode("ECHOPANEL-BETA-2024")
        manager.sessionsThisMonth = manager.sessionLimit + 5
        
        XCTAssertEqual(manager.sessionsRemaining(), 0, "Sessions remaining should never be negative")
    }
    
    func testUpgradePromptShownWhenLimitReached() {
        let manager = BetaGatingManager.shared
        
        manager.validateInviteCode("ECHOPANEL-BETA-2024")
        manager.sessionsThisMonth = manager.sessionLimit
        
        XCTAssertTrue(manager.shouldShowUpgradePrompt, "Upgrade prompt should be shown when limit reached")
    }
    
    func testResetUpgradePrompt() {
        let manager = BetaGatingManager.shared
        
        manager.validateInviteCode("ECHOPANEL-BETA-2024")
        manager.sessionsThisMonth = manager.sessionLimit
        
        manager.resetUpgradePrompt()
        
        XCTAssertFalse(manager.shouldShowUpgradePrompt, "Upgrade prompt should be reset")
    }
}
