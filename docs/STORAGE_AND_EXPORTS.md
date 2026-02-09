# Storage and Exports (current)

## Local session storage (Observed)
Session persistence is local-only on disk via `SessionStore`.

Base path:
- `~/Library/Application Support/<bundle-id>/sessions/`

Per-session files:
- `sessions/<session_id>/metadata.json`
  - session id, start timestamp, selected audio source, app version
- `sessions/<session_id>/transcript.jsonl`
  - append-only finalized transcript events
- `sessions/<session_id>/snapshot.json`
  - periodic autosave snapshot
- `sessions/<session_id>/final_snapshot.json`
  - final snapshot on session end

Recovery marker:
- `sessions/recovery.json`
  - tracks unfinished session for crash recovery prompt

Session history management:
- app supports listing stored sessions and deleting individual session folders.

## Local context/RAG storage (Observed)
Document retrieval store persists to:
- default: `~/.echopanel/rag_store.json`
- override: `ECHOPANEL_DOC_STORE_PATH`

Stored content:
- document metadata (`document_id`, title, source, indexed timestamp, preview)
- chunked text with tokenized chunks for lexical scoring

## Secrets storage (Observed)
Sensitive tokens are stored in macOS Keychain via `KeychainHelper`:
- HuggingFace token
- backend auth token (`ECHOPANEL_WS_AUTH_TOKEN` value source)

## Export actions (Observed)
### Copy Markdown
- Copies final summary markdown if available.
- Otherwise copies a generated live markdown view from current transcript/cards/entities state.

### Export JSON
- Writes a JSON file containing:
  - session metadata
  - transcript entries (including source/speaker when present)
  - actions/decisions/risks/entities
  - final summary markdown/json object

### Export Markdown
- Writes notes markdown to a file (`echopanel-notes.md` default filename).

### Export Debug Bundle
- Bundles current session payload and backend log into a zip archive.

## Retention and privacy notes
- Session and document data persist locally until deleted.
- No automatic cloud sync is implemented in the current app/backend.
- Users can remove individual sessions from history; there is no global “delete all” UI yet.
