# Voice Notes - Manual Testing Checklist

## Test Environment
- [ ] macOS version: _________________
- [ ] EchoPanel build: _________________
- [ ] Server running: _________________

## Phase 1: Core Recording

### Hotkey Testing
- [ ] Press ⌘F8 to start recording
- [ ] Verify: Recording indicator appears (pulsing red circle)
- [ ] Verify: "Recording voice note" text appears
- [ ] Verify: Audio level meter shows activity
- [ ] Speak into microphone for 5-10 seconds
- [ ] Press ⌘F8 to stop recording
- [ ] Verify: Recording indicator changes to gray
- [ ] Verify: Transcript appears in Full mode Notes tab
- [ ] Verify: Transcript appears in Roll/Compact mode as orange marker
- [ ] Test: Multiple sequential recordings (start, stop, start, stop)

### Button Testing
- [ ] Click "Record voice note" button
- [ ] Verify: Same behavior as hotkey
- [ ] Verify: Button icon changes between "record.circle.fill" and "waveform"
- [ ] Verify: Button disabled when session is idle

### Error Handling
- [ ] Test: Start recording without microphone permission
- [ ] Verify: Error message appears
- [ ] Verify: App does not crash
- [ ] Test: Backend unavailable during recording
- [ ] Verify: Graceful error handling

### Max Duration Auto-Stop
- [ ] Start recording and speak continuously
- [ ] Wait for 60 seconds
- [ ] Verify: Recording stops automatically
- [ ] Verify: Transcript is received
- [ ] Verify: Voice note appears in list

## Phase 2: Timeline Markers

### Roll Mode
- [ ] Start a session
- [ ] Record a voice note during session
- [ ] Verify: Orange badge marker appears in Roll mode
- [ ] Verify: Badge shows timestamp (format: MM:SS)
- [ ] Verify: Badge shows "Voice Note" label
- [ ] Verify: Badge limited to 1 line
- [ ] Test: Multiple voice notes create multiple markers

### Compact Mode
- [ ] Switch to Compact mode
- [ ] Verify: Same Roll mode behavior in Compact
- [ ] Verify: Badges work correctly in narrow layout

### Full Mode (No Markers)
- [ ] Switch to Full mode
- [ ] Verify: Voice notes do NOT appear as markers
- [ ] Verify: Voice notes only appear in Notes tab

## Phase 3: Export Integration

### JSON Export
- [ ] Create several voice notes
- [ ] Export as JSON
- [ ] Verify: `voice_notes` array exists in export
- [ ] Verify: Each note has: id, text, start_time, end_time, created_at, confidence, is_pinned, tags

### Markdown Export
- [ ] Export as Markdown
- [ ] Verify: "## Voice Notes" section exists
- [ ] Verify: Each note shows: timestamp, pinned emoji (📌), text
- [ ] Verify: Format: `- [MM:SS] (optional emoji) Note text`

### Session Bundle
- [ ] Export session bundle
- [ ] Verify: `voice_notes.json` file exists in bundle
- [ ] Verify: JSON format is correct
- [ ] Verify: Tags are included

## Phase 4: Editing & Organization

### Note Editing
- [ ] Tap pencil icon on voice note card
- [ ] Verify: TextField appears in place of text
- [ ] Type new text and press Enter
- [ ] Verify: Text updates in card
- [ ] Verify: Edit mode exits
- [ ] Verify: Update persists across app restart
- [ ] Test: Edit note then delete it

### Pin/Unpin
- [ ] Click pin icon on unpinned note
- [ ] Verify: Icon changes to "pin.fill"
- [ ] Verify: Orange pin emoji appears in Markdown export
- [ ] Verify: Note sorts to top of list
- [ ] Click pin.slash icon to unpin
- [ ] Verify: Note sorts by creation time again

### Delete
- [ ] Click trash icon on note
- [ ] Verify: Note disappears from list
- [ ] Verify: Success notice appears
- [ ] Verify: Deletion persists across app restart
- [ ] Test: Delete current playing voice note (if implemented)

### Tags
- [ ] [TODO] Test tag adding/removing functionality
- [ ] [TODO] Verify tags in export

## UI Polish

### Recording Indicator
- [ ] Verify: Pulsing red circle when recording
- [ ] Verify: Animation is smooth
- [ ] Verify: Gray circle when idle
- [ ] Verify: "Recording voice note" text updates

### Voice Note Card
- [ ] Verify: Time badge shows correctly (MM:SS format)
- [ ] Verify: Text truncates to 3 lines in card
- [ ] Verify: Hover effects on card
- [ ] Verify: All buttons have tooltips

### Notes Tab
- [ ] Verify: Empty state when no notes exist
- [ ] Verify: Empty state shows mic icon and hotkey hint
- [ ] Verify: Notes sorted by pinned, then creation time
- [ ] Verify: Scrollable list when many notes

## Performance

- [ ] Record 10 voice notes in a session
- [ ] Verify: UI remains responsive
- [ ] Verify: Memory usage is reasonable
- [ ] Verify: No crashes or hangs

## Edge Cases

- [ ] Record voice note with 0 duration (immediate stop)
- [ ] Record very long note (near 60s limit)
- [ ] Record voice note with special characters
- [ ] Record voice note with emojis
- [ ] Switch modes while recording

## Notes & Issues

Document any issues found during testing:
1. 
2. 
3. 

---

**Tested By:** _________________  
**Date:** _________________  
**Build Version:** _________________
