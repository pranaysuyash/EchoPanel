# WORKLOG_TICKETS excerpt backup (2026-02-16)

This file preserves the original sections before updating ticket status and evidence logs.

## Original summary + open list

```
## 📊 Current Status Summary

| Category | Count | Status |
|----------|-------|--------|
| Completed (DONE ✅) | See ticket list | Mix of P0/P1/P2 across sprints |
| In Progress (IN_PROGRESS 🟡) | 0 | No active implementation tickets |
| Blocked (BLOCKED 🔴) | 1 | `DOC-002` (offline verification environment precondition) |
| Open (OPEN 🔵) | 4 | See `OPEN` tickets below |

## 🚧 Open (Post-Launch)

- DOC-003 — QA: Denied permissions behavior verification
- TCK-20260216-001 — Feature Exploration: MOM Generator
- TCK-20260216-002 — Feature Exploration: Share to Slack/Teams/Email
- TCK-20260216-003 — Feature Exploration: Meeting Templates
```

## Original TCK-20260214-074 section

```
### TCK-20260214-074 :: Privacy Dashboard - Data Transparency

**Type:** FEATURE  
**Owner:** Pranay  
**Created:** 2026-02-14  
**Status:** **DONE** ✅
**Priority:** P1

**Description:**
Add a "Data & Privacy" section to Settings that shows users what data is stored, where it's stored, and provides controls to delete data. Addresses Security/Privacy Audit P2-2 and improves user trust.

**Scope contract:**

- **In-scope:**
  - New "Data & Privacy" tab in Settings
  - Display storage location path
  - Show session count and total storage size
  - Show oldest session date
  - "Delete All Data" button with confirmation
  - "Export All Data" button
- **Out-of-scope:**
  - Per-session deletion (already exists in History)
  - Encryption at rest (separate ticket)
- **Behavior change allowed:** YES (new feature)

**Targets:**

- Surfaces: macapp
- Files:
  - `macapp/MeetingListenerApp/Sources/SettingsView.swift`
  - `macapp/MeetingListenerApp/Sources/SessionBundle.swift`

**Acceptance criteria:**

- [x] New "Data & Privacy" tab added to Settings
- [x] Shows full path to storage directory
- [x] Shows session count
- [x] Shows total storage size (MB/GB)
- [x] Shows oldest session date
- [x] "Delete All Data" button with confirmation dialog
- [x] "Export All Data" button creates ZIP
- [x] Updates in real-time as data changes

**Evidence log:**

- [2026-02-14] Identified in Security/Privacy Audit | Evidence:
  - `docs/audit/security-privacy-boundaries-20260211.md` Section SP-010
  - UI/UX Audit P2-2
- [2026-02-16] Verified implemented dashboard surfaces | Evidence:
  - `macapp/MeetingListenerApp/Sources/SettingsView.swift` (`Data & Privacy` tab, storage stats, export/delete actions)
- [2026-02-16] Implemented live refresh for storage stats | Evidence:
  - `macapp/MeetingListenerApp/Sources/SettingsView.swift` refreshes on `.sessionHistoryShouldRefresh` notifications
```

## Original TCK-20260214-075 section

```
### TCK-20260214-075 :: Data Retention - Automatic Cleanup

**Type:** FEATURE  
**Owner:** Pranay  
**Created:** 2026-02-14  
**Status:** **DONE** ✅
**Priority:** P2

**Description:**
Implement automatic data retention policy with configurable cleanup. Deletes session data older than a user-configurable threshold (default: 90 days). Prevents unbounded disk usage growth.

**Scope contract:**

- **In-scope:**
  - Add retention period setting (30/60/90/180/365 days, or Never)
  - Background cleanup job on app startup
  - Cleanup runs daily when app is running
  - Exclude "starred" or "pinned" sessions (if implemented)
  - Log cleanup actions
- **Out-of-scope:**
  - Cloud sync retention
  - Per-session retention overrides
- **Behavior change allowed:** YES (new feature, default 90 days)

**Targets:**

- Surfaces: macapp
- Files:
  - `macapp/MeetingListenerApp/Sources/DataRetentionManager.swift`
  - `macapp/MeetingListenerApp/Sources/SettingsView.swift`
  - `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift` (cleanup scheduler)
  - `macapp/MeetingListenerApp/Tests/DataRetentionManagerTests.swift`

**Acceptance criteria:**

- [x] Retention period setting in Data & Privacy tab
- [x] Options: 30/60/90/180/365 days, Never (default: 90)
- [x] Cleanup runs on app startup
- [x] Cleanup runs every 24 hours while app is running
- [x] Deletes only sessions older than threshold
- [x] Logs cleanup actions

**Evidence log:**

- [2026-02-14] Identified in Security/Privacy Audit | Evidence:
  - `docs/audit/security-privacy-boundaries-20260211.md` DG-001
  - No TTL enforcement currently exists
- [2026-02-16] Verified retention engine exists | Evidence:
  - `macapp/MeetingListenerApp/Sources/DataRetentionManager.swift` (startup run + 24h timer + cleanup logging)
  - `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift` starts `DataRetentionManager` at app launch.
- [2026-02-16] Implemented retention controls + tests | Evidence:
  - `macapp/MeetingListenerApp/Sources/SettingsView.swift` (retention picker + last cleanup)
  - `macapp/MeetingListenerApp/Sources/DataRetentionManager.swift` (default 90 days + cleanup notifications)
  - `macapp/MeetingListenerApp/Tests/DataRetentionManagerTests.swift`
  - Note: no session-level pin/star feature exists; retention applies to all sessions
```
