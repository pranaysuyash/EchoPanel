# Storage and Exports (v0.1)

## Local storage
v0.1 minimal storage is local-only in the app sandbox.

Persist per session:
- raw transcript segments (partial optional, finals required)
- latest cards and entities snapshots
- final summary markdown and JSON
- basic metadata (session_id, timestamps, app version)

Suggested layout (informational, not binding):
- `Sessions/<session_id>/session.json`
- `Sessions/<session_id>/summary.md`

## Export actions
### Copy Markdown
- Copies final summary markdown if available.
- If final summary is not available, copies a live markdown view composed from:
  - current transcript
  - current actions/decisions/risks/entities

### Export JSON
- Writes a single JSON file containing:
  - session metadata
  - transcript segments
  - cards and entities
  - final summary payload (if available)

## Retention
- v0.1 default: retain sessions locally until the user deletes the app data.
- Optional future: UI to delete sessions and clear storage.

