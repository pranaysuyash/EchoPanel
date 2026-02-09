# Visual Testing

Automated visual regression coverage exists for the macOS side panel via `swift-snapshot-testing`.

## Automated snapshots
- Test target: `macapp/MeetingListenerApp/Tests/SidePanelVisualSnapshotTests.swift`
- Modes covered: Roll, Compact, Full
- Color schemes covered: Light and Dark
- Baseline snapshots: `macapp/MeetingListenerApp/Tests/__Snapshots__/SidePanelVisualSnapshotTests/`

Run snapshot assertions:

```bash
cd macapp/MeetingListenerApp
swift test --filter SidePanelVisualSnapshotTests
```

Re-record baselines (intentional UI changes only):

```bash
cd macapp/MeetingListenerApp
RECORD_SNAPSHOTS=1 swift test --filter SidePanelVisualSnapshotTests
```

## Manual checklist
- Three lanes are visible in Full mode: transcript, session/context rail, insight surface.
- Transcript rows show timestamp, speaker marker, confidence, and low-confidence badge.
- Entity highlights open details/filter actions from pointer and accessibility paths.
- Cmd+Shift+L toggles Start/Stop and Cmd+C copies Markdown.
