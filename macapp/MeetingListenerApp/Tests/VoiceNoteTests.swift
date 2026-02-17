import XCTest
@testable import MeetingListenerApp

@MainActor
final class VoiceNoteTests: XCTestCase {
    
    func testVoiceNoteCaptureManagerPermissionCheck() {
        let captureManager = VoiceNoteCaptureManager()
        
        XCTAssertNoThrow(try? captureManager.checkPermission())
    }
    
    func testVoiceNoteModelEquality() {
        let date = Date()
        let note1 = VoiceNote(
            text: "Test note",
            startTime: 100.0,
            endTime: 105.0,
            createdAt: date,
            confidence: 0.95,
            isPinned: false
        )
        
        let note2 = VoiceNote(
            text: "Test note",
            startTime: 100.0,
            endTime: 105.0,
            createdAt: date,
            confidence: 0.95,
            isPinned: false
        )
        
        XCTAssertEqual(note1, note2)
    }
    
    func testVoiceNoteModelInequality() {
        let note1 = VoiceNote(
            text: "Test note",
            startTime: 100.0,
            endTime: 105.0,
            createdAt: Date(),
            confidence: 0.95,
            isPinned: false
        )
        
        let note2 = VoiceNote(
            text: "Different note",
            startTime: 100.0,
            endTime: 105.0,
            createdAt: note1.createdAt,
            confidence: 0.95,
            isPinned: false
        )
        
        XCTAssertNotEqual(note1, note2)
    }
    
    func testVoiceNotePinnedToggle() {
        let appState = AppState()
        XCTAssertTrue(appState.voiceNotes.isEmpty)
        
        let note = VoiceNote(
            text: "Test note",
            startTime: 100.0,
            endTime: 105.0,
            createdAt: Date(),
            confidence: 0.95,
            isPinned: false
        )
        
        appState.voiceNotes.append(note)
        XCTAssertFalse(note.isPinned)
        
        appState.toggleVoiceNotePin(id: note.id)
        XCTAssertTrue(appState.voiceNotes.first?.isPinned ?? false)
        
        appState.toggleVoiceNotePin(id: note.id)
        XCTAssertFalse(appState.voiceNotes.first?.isPinned ?? true)
    }
    
    func testVoiceNoteDelete() {
        let appState = AppState()
        
        let note1 = VoiceNote(
            text: "Note to keep",
            startTime: 100.0,
            endTime: 105.0,
            createdAt: Date(),
            confidence: 0.95,
            isPinned: false
        )
        
        let note2 = VoiceNote(
            text: "Note to delete",
            startTime: 200.0,
            endTime: 205.0,
            createdAt: Date(),
            confidence: 0.90,
            isPinned: false
        )
        
        appState.voiceNotes.append(note1)
        appState.voiceNotes.append(note2)
        XCTAssertEqual(appState.voiceNotes.count, 2)
        
        appState.deleteVoiceNote(id: note2.id)
        XCTAssertEqual(appState.voiceNotes.count, 1)
        XCTAssertEqual(appState.voiceNotes.first?.text, "Note to keep")
    }
    
    func testClearAllVoiceNotes() {
        let appState = AppState()
        
        for i in 0..<5 {
            let note = VoiceNote(
                text: "Note \(i)",
                startTime: Double(i * 100),
                endTime: Double(i * 100 + 5),
                createdAt: Date(),
                confidence: 0.95,
                isPinned: false
            )
            appState.voiceNotes.append(note)
        }
        
        XCTAssertEqual(appState.voiceNotes.count, 5)
        
        appState.clearAllVoiceNotes()
        XCTAssertTrue(appState.voiceNotes.isEmpty)
    }
    
    func testVoiceNotesSortedByPinnedFirst() {
        let appState = AppState()
        let date = Date()
        
        let pinnedNote = VoiceNote(
            text: "Pinned note",
            startTime: 200.0,
            endTime: 205.0,
            createdAt: date.addingTimeInterval(-100),
            confidence: 0.95,
            isPinned: true
        )
        
        let newerNote = VoiceNote(
            text: "Newer unpinned",
            startTime: 300.0,
            endTime: 305.0,
            createdAt: date.addingTimeInterval(-50),
            confidence: 0.90,
            isPinned: false
        )
        
        let olderNote = VoiceNote(
            text: "Older unpinned",
            startTime: 100.0,
            endTime: 105.0,
            createdAt: date.addingTimeInterval(-200),
            confidence: 0.85,
            isPinned: false
        )
        
        appState.voiceNotes = [olderNote, newerNote, pinnedNote]
        XCTAssertEqual(appState.voiceNotes.count, 3)
    }
}
