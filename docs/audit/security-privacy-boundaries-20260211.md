# Security & Privacy Boundary Analysis — EchoPanel

**Date:** 2026-02-11  
**Analyst:** Security & Privacy Boundary Analyst  
**Document ID:** SP-AUDIT-20260211  
**Version:** 1.0

---

## Update (2026-02-13)

This audit was authored on **2026-02-11**. Since then, backend auth/token handling has been hardened and some protocol details have changed. Key deltas observed as of **2026-02-13**:

- ✅ **Secure-by-default localhost backend auth**: when the app manages a localhost backend, it auto-generates a backend token (Keychain) and starts the backend with `ECHOPANEL_WS_AUTH_TOKEN`. Evidence: `macapp/MeetingListenerApp/Sources/BackendManager.swift`, `macapp/MeetingListenerApp/Sources/KeychainHelper.swift`.
- ✅ **Client sends auth via headers (not URL query params)**: WebSocket and HTTP requests include `Authorization: Bearer <token>` and `x-echopanel-token: <token>`. Evidence: `macapp/MeetingListenerApp/Sources/BackendConfig.swift`, `macapp/MeetingListenerApp/Sources/BackendManager.swift`.
- ⚠️ **Server still accepts `?token=` for backward compatibility** (priority order includes query param), so URL-token risk remains server-side until query-token support is removed. Evidence: `server/api/ws_live_listener.py`, `server/main.py`, and `docs/WS_CONTRACT.md`.
- ✅ **HTTP endpoints require auth when token is set**: `/health`, `/model-status`, etc. enforce `_require_http_auth(...)` when `ECHOPANEL_WS_AUTH_TOKEN` is configured. Evidence: `server/main.py`.

## 1. Executive Summary

This document provides a comprehensive analysis of EchoPanel's trust boundaries, data movement patterns, permission gating, redaction paths, and storage mechanisms. The analysis covers the macOS menu bar application (`macapp/`), local FastAPI backend (`server/`), and their interactions.

### Key Findings

- **11 distinct boundary crossings identified** spanning permission-gated capture, credential storage, WebSocket transmission, and logging
- **Strong credential security**: KeychainHelper uses macOS Keychain with `kSecAttrAccessibleAfterFirstUnlock` (acceptable for local-first app)
- **Partial TLS enforcement**: BackendConfig correctly uses WSS/HTTPS for non-localhost but allows unencrypted localhost for development
- **Effective redaction**: StructuredLogger implements regex-based PII redaction with 5 patterns (API tokens, Bearer tokens, file paths, etc.)
- **Missing privacy guard**: No explicit user consent dialog for audio data transmission beyond macOS permission prompts
- **Session data persistence**: PCM buffers and transcripts stored in memory during session with optional debug dump to disk

---

## 2. Boundary Inventory

| Flow ID | Boundary | Direction | Data Type | Status |
|---------|----------|-----------|-----------|--------|
| SP-001 | Screen Recording Permission | macOS → App | System audio (PCM16) | Implemented |
| SP-002 | Microphone Permission | macOS → App | Mic audio (PCM16) | Implemented |
| SP-003 | Keychain Storage | App → macOS Keychain | API tokens | Implemented |
| SP-004 | WebSocket TX (Local) | App → Localhost | Audio frames, tokens | Implemented |
| SP-005 | WebSocket TX (Remote) | App → Remote Server | Audio frames, tokens | Implemented |
| SP-006 | WebSocket RX | Server → App | Transcripts, entities | Implemented |
| SP-007 | Logging (Console) | App → stdout | Structured JSON logs | Implemented |
| SP-008 | Logging (File) | App → Disk | Debug logs | Implemented |
| SP-009 | Session State | Server Memory | Transcripts, PCM buffers | Implemented |
| SP-010 | Debug Audio Dump | Server → Disk | Raw PCM files | Partial |
| SP-011 | Config Storage | App → UserDefaults | Settings (non-sensitive) | Implemented |

---

## 3. Detailed Boundary Analysis

### SP-001: Screen Recording Permission → Application

**What Data Crosses the Boundary:**
- System audio stream: 16kHz mono PCM16, 320-byte frames (20ms chunks)
- Source: macOS ScreenCaptureKit (SCStream)
- Data volume: ~128 KB/minute per audio source

**Trust Boundaries Involved:**
1. User's macOS security boundary (Screen Recording permission grant)
2. Application sandbox boundary
3. ScreenCaptureKit framework trust boundary

**Permission Requirements:**
- `CGRequestScreenCaptureAccess()` - prompts user for Screen Recording permission
- `SCStreamConfiguration.capturesAudio = true` - enables audio capture
- `SCStreamConfiguration.excludesCurrentProcessAudio = true` - prevents self-capture

**Encryption in Transit:** N/A (macOS IPC)

**Data Retention:**
- Audio processed frame-by-frame in memory
- No persistent storage of raw system audio in app
- Server-side: optional debug dump to `/tmp/echopanel_audio_dump` (SP-010)

**User Controls:**
- System Preference Pane → Security & Privacy → Screen Recording
- User can revoke permission at any time
- App checks permission status via `CGPreflightScreenCaptureAccess()`

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Unauthorized screen recording | High | Low | macOS permission gate |
| Process injection during capture | Medium | Low | App sandbox |
| Audio data exfiltration | High | Low | No network access from capture |
| Permission persistence abuse | Medium | Low | User-controlled in System Prefs |

**Failure Modes:**
1. **Permission Denied**: App cannot capture system audio, degrades to mic-only mode
2. **Permission Revoked Mid-Session**: Capture stops, no error recovery implemented (Observed: `AudioCaptureManager.swift:98-103` silently ignores errors)
3. **ScreenCaptureKit Failure**: `CaptureError.noDisplay` thrown, app shows error state
4. **OS Version Incompatibility**: `CaptureError.unsupportedOS` for macOS < 13
5. **Content Filter Invalid**: `SCContentFilter` validation failure prevents capture start
6. **Concurrent Process Conflict**: Other screen recorder may block access

**Observability:**
- `NSLog` debug output (conditionally via `--debug` flag)
- `AudioQuality` callbacks (`.ok`, `.good`, `.poor`)
- `AudioLevelUpdate` callbacks for RMS monitoring
- Missing: No explicit permission change notifications

**Status:** Implemented

**Proof:**
- `AudioCaptureManager.swift:61-66` - permission request
- `AudioCaptureManager.swift:68-95` - capture initialization
- `AudioCaptureManager.swift:73` - `SCShareableContent.excludingDesktopWindows`

---

### SP-002: Microphone Permission → Application

**What Data Crosses the Boundary:**
- Microphone audio stream: 16kHz mono PCM16, 320-byte frames
- Source: AVFoundation AudioEngine input node
- Data volume: ~128 KB/minute per audio source

**Trust Boundaries Involved:**
1. User's macOS privacy boundary (Microphone permission grant)
2. Application sandbox boundary
3. AVFoundation framework trust boundary

**Permission Requirements:**
- `AVCaptureDevice.requestAccess(for: .audio)` - prompts user
- `AVCaptureDevice.authorizationStatus(for: .audio)` - check status

**Encryption in Transit:** N/A (macOS IPC)

**Data Retention:** Same as SP-001

**User Controls:**
- System Preference Pane → Security & Privacy → Microphone
- App provides `checkPermission()` and `requestPermission()` methods

**Threat Points:** Same pattern as SP-001, plus:
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Unauthorized mic access | High | Low | macOS permission gate |
| Background recording | Medium | Low | App must be active for capture |

**Failure Modes:**
1. **Permission Denied**: Cannot start mic capture, throws or returns false
2. **Permission Revoked Mid-Session**: `AVAudioEngine` input node may error
3. **Audio Engine Start Failure**: `audioEngine.start()` throws
4. **Format Conversion Failure**: AVAudioConverter creation fails
5. **Input Node Tap Failure**: `installTap(onBus:)` fails
6. **Device Disconnection**: USB microphone disconnect causes error

**Observability:**
- `NSLog` debug output
- `onAudioLevelUpdate` callbacks
- `onError` callbacks

**Status:** Implemented

**Proof:**
- `MicrophoneCaptureManager.swift:29-39` - permission handling
- `MicrophoneCaptureManager.swift:41-65` - capture start
- `MicrophoneCaptureManager.swift:67-74` - capture stop

---

### SP-003: Keychain Credential Storage

**What Data Crosses the Boundary:**
- HuggingFace API token (saved as `hfToken`)
- Backend WebSocket authentication token (saved as `backendToken`)
- Plaintext UTF-8 encoded before storage

**Trust Boundaries Involved:**
1. Application process boundary
2. macOS Keychain Services (Security framework)
3. User's login keychain

**Permission Requirements:**
- Keychain access does not require explicit user permission
- App must be signed with appropriate entitlements

**Encryption at Rest:**
- Keychain uses AES-256-GCM (hardware-accelerated via Secure Enclave on T2/Apple Silicon)
- Access control: `kSecAttrAccessibleAfterFirstUnlock` - available after first unlock
- Data encrypted before storage in Keychain.db

**Data Retention:**
- Tokens persist until explicitly deleted via KeychainHelper
- Migration from UserDefaults on first run (SP-011)
- No automatic expiration

**User Controls:**
- No user-facing Keychain management UI
- Tokens deleted via Settings → Clear Credentials (inferred from app architecture)

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Keychain extraction (malware) | Critical | Low | Sandbox, SIP |
| Memory dump of tokens | Critical | Low | Process memory encryption |
| Keychain backup extraction | High | Medium | Backup encryption |
| Token leakage via logs | High | Low | StructuredLogger redaction (SP-007) |
| UserDefaults migration artifact | Medium | Low | Migration deletes old values |

**Failure Modes:**
1. **Keychain Unavailable**: `SecItemAdd`/`SecItemCopyMatching` fails with `errSecItemNotFound`
2. **Encoding Failure**: `token.data(using: .utf8)` returns nil for invalid UTF-8
3. **Migration Failure**: `migrateFromUserDefaults()` may partially succeed
4. **Race Condition**: Concurrent access during migration (mitigated by single-threaded startup)
5. **Accessibility Change**: `kSecAttrAccessibleAfterFirstUnlock` may not suit headless servers

**Observability:**
- `StructuredLogger` captures Keychain errors (line 227-228)
- No dedicated Keychain health metrics

**Status:** Implemented

**Proof:**
- `KeychainHelper.swift:13-34` - HF token save/load
- `KeychainHelper.swift:70-89` - backend token save/load
- `KeychainHelper.swift:26,83` - `kSecAttrAccessibleAfterFirstUnlock`
- `KeychainHelper.swift:126-150` - UserDefaults migration

---

### SP-004: Local WebSocket Transmission (localhost)

**What Data Crosses the Boundary:**
- Audio frames: Base64-encoded PCM16 (320 bytes → ~440 bytes Base64)
- Session metadata: session_id, attempt_id, connection_id
- Start/Stop control messages
- ASR responses: transcripts, entities, cards, metrics
- Authentication token via headers (client) and optionally query parameter (server backward compatibility)

**Trust Boundaries Involved:**
1. Application process boundary
2. Localhost TCP loopback (no network interface)
3. Same-machine privilege boundary

**Permission Requirements:**
- No additional macOS permissions for localhost
- localhost connections bypass App Transport Security (ATS)

**Encryption in Transit:**
- **Status: NOT ENCRYPTED**
- Uses `ws://` scheme for localhost (BackendConfig.swift:18-20)
- Loopback traffic technically readable by root user
- **Risk**: Local malware with root access could intercept

**Data Retention:**
- Server: In-memory session state (SP-009)
- Optional debug audio dump (SP-010)
- Client: No persistent storage of transmitted audio

**User Controls:**
- Backend host configurable via Settings → Backend Host
- Default: `127.0.0.1:8000`
- Token auto-loaded from Keychain (SP-003)

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Local network sniffing | Medium | Low | Loopback only, root access required |
| Process injection (app) | Critical | Low | Sandbox, code signing |
| Token interception (local) | High | Low | Keychain storage, short-lived sessions |
| MITM via port hijack | Medium | Very Low | Localhost only |

**Failure Modes:**
1. **Connection Refused**: Server not running on localhost:8000
2. **Authentication Failure**: Token mismatch → server closes with code 1008
3. **WebSocket Protocol Error**: Invalid JSON, server closes connection
4. **Send Timeout**: 5-second semaphore wait (WebSocketStreamer.swift:246)
5. **Queue Overflow**: >100 queued sends drops frames (WebSocketStreamer.swift:219-228)
6. **Token Encoding Error**: Invalid UTF-8 in token (query/header)

**Observability:**
- `StructuredLogger` with correlation IDs
- `onStatus` callback for connection state
- `onMetrics` callback for queue/health metrics
- Debug logging sanitizes URL (removes query params from logs)

**Status:** Implemented

**Proof:**
- `BackendConfig.swift:18-20` - ws:// for localhost
- `WebSocketStreamer.swift:71-112` - connection establishment
- `WebSocketStreamer.swift:157-169` - audio frame send
- `WebSocketStreamer.swift:108-110` - URL sanitization for logs

---

### SP-005: Remote WebSocket Transmission (non-localhost)

**What Data Crosses the Boundary:**
- Same as SP-004
- Audio frames transmitted over network

**Trust Boundaries Involved:**
1. Application process boundary
2. User's network boundary (WiFi/Ethernet)
3. Internet boundary
4. Server hosting boundary

**Permission Requirements:**
- Outbound network access (implicit for App Store apps)
- No specific macOS permission for network access

**Encryption in Transit:**
- **Status: ENFORCED**
- Uses `wss://` scheme for non-localhost (BackendConfig.swift:18-20)
- TLS 1.2+ enforced by URLSession (default)
- Certificate validation: Default (System root CAs)

**Data Retention:** Same as SP-004

**User Controls:**
- User can configure remote backend URL
- User can choose to use local-only mode

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Network sniffing | High | Medium | TLS (WSS) encryption |
| MITM attack | High | Low | Certificate validation |
| Server compromise | Critical | Medium | Token-limited access |
| Data center access | High | Low | Server-side controls |
| ISP logging | Medium | Low | TLS hides content |

**Failure Modes:**
1. **TLS Handshake Failure**: Invalid certificate, server mismatch
2. **Network Timeout**: Slow/unavailable server
3. **Certificate Pinning Bypass**: Not implemented (uses system defaults)
4. **Token Leakage**: Server supports URL query token for backward compatibility; client prefers headers. Query-token may be visible in proxy logs if used.
5. **Protocol Downgrade**: Not applicable (WebSocketStreamer uses URLSession defaults)

**Observability:**
- Same as SP-004
- Missing: No TLS certificate validation feedback to user

**Status:** Implemented

**Proof:**
- `BackendConfig.swift:18-20` - wss:// for remote
- `WebSocketStreamer.swift:49` - URLSession configuration

---

### SP-006: WebSocket Response (Server → Client)

**What Data Crosses the Boundary:**
- ASR partial results (interim transcription)
- ASR final results (confirmed transcription)
- Entities (people, orgs, dates, projects, topics)
- Action/Decision/Risk cards
- Session metrics (queue depth, RTF, dropped frames)
- Final summary (markdown + structured JSON)

**Trust Boundaries Involved:** Same as SP-004/SP-005

**Permission Requirements:** Same as SP-004/SP-005

**Encryption in Transit:** Same as SP-004/SP-005

**Data Retention:**
- Client: In-memory session state
- Server: Session transcript in memory (SP-009)

**User Controls:**
- No user control over incoming data structure
- UI displays all received data

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Malicious server response | High | Low | App validates message types |
| Injection attacks | Medium | Low | JSON parsing with type checks |
| Large response DoS | Medium | Low | Queue-based processing |
| Sensitive entity extraction | Medium | Low | No PII redaction on server |

**Failure Modes:**
1. **Malformed JSON**: `JSONSerialization` fails, message dropped
2. **Invalid Message Type**: Unknown types ignored (ws_live_listener.py:380-382)
3. **Queue Overflow**: Client-side queue >100 drops frames
4. **Decoder Errors**: Entity/ActionItem decoding fails silently
5. **Callback Threading Issues**: MainActor dispatch ensures thread safety

**Observability:**
- `onASRPartial`, `onASRFinal`, `onCardsUpdate`, `onEntitiesUpdate` callbacks
- `onMetrics` callback for health monitoring
- Missing: No explicit parsing error logging to user

**Status:** Implemented

**Proof:**
- `WebSocketStreamer.swift:296-383` - message handling
- `WebSocketStreamer.swift:385-436` - response decoding

---

### SP-007: Structured Logging (Console)

**What Data Crosses the Boundary:**
- Debug/error/info messages with metadata
- Correlation IDs (session_id, attempt_id, connection_id)
- Error details (localized descriptions)
- Performance metrics (timing, queue depths)

**Trust Boundaries Involved:**
1. Application process boundary
2. Terminal/output stream (stdout)

**Permission Requirements:** None

**Encryption in Transit:** N/A

**Data Retention:**
- Console logs ephemeral (stdout)
- Rotated to file (SP-008)

**User Controls:**
- `--debug` flag enables verbose logging
- Log level configurable via StructuredLogger.Configuration

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| PII leakage in logs | High | Medium | Redaction patterns |
| Token leakage | Critical | Medium | Regex redaction |
| Credential logging | Critical | Medium | URL sanitization |
| File path exposure | Medium | Low | Home directory redaction |

**Failure Modes:**
1. **Regex Bypass**: Novel token format not matched
2. **Performance Impact**: Regex matching on every log message
3. **Metadata Logging**: Non-string metadata not redacted
4. **Error LocalizedDescription**: May contain sensitive info

**Observability:**
- JSON formatted logs (machine-parseable)
- Correlation context automatically included
- Sampling for high-frequency events

**Status:** Implemented

**Proof:**
- `StructuredLogger.swift:87-117` - RedactionPattern.defaults
- `StructuredLogger.swift:333-347` - redact() implementation
- `StructuredLogger.swift:288` - message redaction
- `StructuredLogger.swift:301-305` - error redaction

**Redaction Patterns Implemented:**
1. `hf_[a-zA-Z0-9]{20,}` → `***` (HuggingFace tokens)
2. `sk-[a-zA-Z0-9]{20,}` → `***` (Generic API keys)
3. `Bearer\s+[a-zA-Z0-9_\-\.]{20,}` → `Bearer ***`
4. `/Users/[^/]+/` → `~/` (Home directory paths)
5. `token=[a-zA-Z0-9_\-\.]{10,}` → `token=***`

---

### SP-008: File-Based Logging

**What Data Crosses the Boundary:**
- Same as SP-007
- Persistent JSON log files

**Trust Boundaries Involved:**
1. Application sandbox boundary
2. Filesystem (Application Support directory)

**Permission Requirements:**
- `com.apple.security.app-sandbox` (entitlement)
- File write to `~/Library/Application Support/com.echopanel.MeetingListenerApp/logs/`

**Encryption at Rest:**
- **Status: NOT ENCRYPTED**
- Log files written in plaintext
- Filesystem encryption (FileVault) provides at-rest protection

**Data Retention:**
- Max 5 log files (StructuredLogger.swift:428)
- Max 10 MB per file (StructuredLogger.swift:75)
- Log rotation automatically manages size

**User Controls:**
- Log files accessible via `StructuredLogger.getLogFileURLs()`
- `readRecentLogs()` API for log retrieval
- Manual log deletion possible

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Log file theft | High | Low | Sandbox, FileVault |
| Disk forensics | Medium | Low | No encryption at app level |
| Log injection | Low | Very Low | JSON format enforcement |

**Failure Modes:**
1. **Disk Full**: Log write fails silently
2. **Permission Denied**: Sandbox prevents directory access
3. **Rotation Failure**: File handle leak prevents rotation
4. **Corrupted JSON**: Partial write corrupts log file

**Observability:**
- Log file URLs returned via API
- Rotation errors logged but non-fatal

**Status:** Implemented

**Proof:**
- `StructuredLogger.swift:377-405` - log file setup
- `StructuredLogger.swift:421-449` - log rotation
- `StructuredLogger.swift:84` - logs directory path

---

### SP-009: Server Session State (Memory)

**What Data Crosses the Boundary:**
- Transcript segments (ASR results with timestamps)
- PCM audio buffers (for diarization)
- Speaker labels (if diarization enabled)
- Extracted entities, actions, decisions, risks
- Final summary (markdown + JSON)

**Trust Boundaries Involved:**
1. Server process boundary
2. Memory isolation (process memory)

**Permission Requirements:**
- Server running locally (SP-004) or remotely (SP-005)
- No additional permissions

**Encryption in Transit:** N/A (in-memory)

**Data Retention:**
- Session lifetime only
- Server retains in memory during session
- Optionally dumped to disk for debugging (SP-010)
- Released on session close (ws_live_listener.py:839-870)

**User Controls:**
- No user control over session data retention
- Debug audio dump controlled via `ECHOPANEL_DEBUG_AUDIO_DUMP` env var

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Memory dump extraction | Critical | Low | Server security |
| Process memory access | High | Low | Process isolation |
| Cross-session data leak | High | Very Low | Session-scoped state |
| Sensitive transcript exposure | High | Medium | No PII redaction on server |

**Failure Modes:**
1. **Memory Pressure**: Server OOM kills session
2. **Session State Leak**: Error messages leak session data
3. **Diarization Buffer Overflow**: `diarization_max_bytes` cap (1.8GB default for 30min)
4. **Transcript Corruption**: Out-of-order ASR results
5. **Session Hijacking**: Token reuse across sessions (mitigated: token validated per-connection)

**Observability:**
- Session metrics logged at close (ws_live_listener.py:866-870)
- Transcript segment count logged

**Status:** Implemented

**Proof:**
- `ws_live_listener.py:33-72` - SessionState dataclass
- `ws_live_listener.py:42` - transcript storage
- `ws_live_listener.py:44` - PCM buffers
- `ws_live_listener.py:839-870` - session cleanup

---

### SP-010: Debug Audio Dump (Optional)

**What Data Crosses the Boundary:**
- Raw PCM16 audio chunks (not Base64-encoded)
- Written to disk in `/tmp/echopanel_audio_dump/`
- Per-source files: `{session_id}_{source}_{timestamp}.pcm`

**Trust Boundaries Involved:**
1. Server process boundary
2. Filesystem (temp directory)

**Permission Requirements:**
- `ECHOPANEL_DEBUG_AUDIO_DUMP=1` environment variable
- Server must have write access to `/tmp/`

**Encryption at Rest:**
- **Status: NOT ENCRYPTED**
- Raw PCM files written in plaintext
- No automatic cleanup (file handles closed but files remain)

**Data Retention:**
- Debug files persist until manually deleted
- No retention policy enforced
- Located in `/tmp/` (survives reboot, cleared on OS update)

**User Controls:**
- Only enabled via server environment variable
- No runtime toggle in app
- No UI for debug file access

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Audio file theft | High | Low | Temp directory protection |
| Disk forensics | Medium | Low | No encryption |
| Accidental persistence | Medium | Low | Debug-only feature |
| Sensitive meeting content | High | Medium | Not production-enabled |

**Failure Modes:**
1. **Write Permission Denied**: Debug dump silently fails
2. **Disk Full**: Write fails, non-fatal
3. **File Handle Leak**: Multiple open handles on rotation
4. **Path Traversal**: Session ID in filename (but controlled by app)

**Observability:**
- Debug dump initialization logged
- File path logged for debugging

**Status:** Partial (Debug-only, not enabled by default)

**Proof:**
- `ws_live_listener.py:26-28` - debug dump configuration
- `ws_live_listener.py:197-240` - audio dump functions
- `ws_live_listener.py:719,725` - dump file usage

---

### SP-011: UserDefaults Configuration Storage

**What Data Crosses the Boundary:**
- Backend host/port configuration
- Whisper model selection
- Permission state flags
- UI preferences

**Trust Boundaries Involved:**
1. Application sandbox boundary
2. `~/Library/Preferences/com.echopanel.MeetingListenerApp.plist`

**Permission Requirements:**
- None (sandbox-entitled file write)

**Encryption at Rest:**
- **Status: NOT ENCRYPTED**
- Property list stored in plaintext
- FileVault provides at-rest protection

**Data Retention:**
- Persists across app launches
- Cleared on app uninstall (mostly)
- Migration from UserDefaults to Keychain for credentials (SP-003)

**User Controls:**
- Settings UI for configuration
- `migrateFromUserDefaults()` cleans up legacy values

**Threat Points:**
| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Config manipulation | Low | Low | Validated on load |
| PII in preferences | Low | Low | Only non-sensitive data |
| Backend URL spoofing | Medium | Low | URL validation in BackendConfig |

**Failure Modes:**
1. **Corrupted plist**: App uses defaults
2. **Invalid URL**: BackendConfig.fatalError() (line 38)
3. **Migration Data Loss**: Partial migration may leave orphaned values

**Observability:**
- No logging of config changes
- Defaults logged in debug mode

**Status:** Implemented

**Proof:**
- `BackendConfig.swift:4-25` - configuration accessors
- `KeychainHelper.swift:126-150` - credential migration

---

## 4. Data Residency & Privacy Considerations

### 4.1 Data Residency Summary

| Data Type | Location | Residency | Encryption |
|-----------|----------|-----------|------------|
| Audio (transit) | Network | Session | TLS (remote), None (localhost) |
| Audio (capture) | App memory | Session | Process memory encryption |
| Audio (debug) | `/tmp/` | Until manual delete | None |
| Transcripts | Server memory | Session | None |
| Credentials | macOS Keychain | Until deleted | AES-256-GCM |
| Config | UserDefaults | Persistent | None |
| Logs | App Support | 5 files max, 10MB each | None |
| API Tokens | Keychain | Until deleted | Hardware-backed |

### 4.2 Privacy by Design Observations

**Positive:**
- Local-first architecture minimizes data exposure
- Keychain storage for all credentials
- Regex-based PII redaction in logs
- Optional debug audio dump disabled by default
- Session tokens not persisted beyond session
- No cloud upload of audio (local server by default)

**Areas for Improvement:**
1. **No explicit consent for data transmission**: Beyond macOS permissions, no explanation of what data is sent
2. **No PII redaction in transcripts**: Server returns all recognized speech, including PII
3. **No data minimization**: Full transcripts stored, no option to redact sensitive content
4. **Token in URL query param**: Query parameters may be logged by proxies/intermediate devices
5. **No user data export/delete**: Users cannot export or delete their session transcripts
6. **No retention policy**: Debug audio dump persists indefinitely in `/tmp/`

### 4.3 Compliance Considerations

| Requirement | Status | Notes |
|-------------|--------|-------|
| Data minimization | Partial | No automatic PII redaction |
| Purpose limitation | Partial | Session-scoped, but no policy |
| User consent | Partial | macOS permissions only |
| Data portability | Missing | No export feature |
| Right to deletion | Partial | No user-facing delete |
| Encryption at rest | Partial | Keychain yes, UserDefaults no |
| Access control | Implemented | Keychain access control |

---

## 5. Failure Mode Matrix

### Critical Failure Modes (5+)

| Flow | Failure | Impact | Detection | Recovery |
|------|---------|--------|-----------|----------|
| SP-001/SP-002 | Permission revoked mid-session | Loss of audio | Silent failure | Manual re-permission |
| SP-003 | Keychain corruption | Authentication failure | Connection error | Re-enter credentials |
| SP-004/SP-005 | Network disconnection | Session interruption | Automatic reconnect | ResilientWebSocket |
| SP-004/SP-005 | Token leak | Unauthorized access | Log analysis | Token rotation |
| SP-007/SP-008 | PII in logs | Privacy breach | Audit review | Redaction patterns |
| SP-009 | Memory exhaustion | Server crash | Process monitor | Restart |
| SP-010 | Accidental debug dump | Data exposure | Log review | Manual cleanup |

---

## 6. Observability Gaps

| Gap | Impact | Recommendation |
|-----|--------|----------------|
| No permission change monitoring | Medium | Observe permission changes via distributed notifications |
| No token usage tracking | Medium | Log token access with correlation IDs |
| No transcript size monitoring | Low | Add transcript length metrics |
| No debug dump detection | Medium | Alert if debug files exist |
| No client-side queue metrics exposed | Low | Expose `sendQueue.operationCount` |
| No server-side session count limit | Medium | Implement concurrency controller (Status 2026-02-13: implemented in `server/services/concurrency_controller.py` + session acquire in WS start) |

---

## 7. Recommendations (Ranked by Priority)

### High Priority

1. **Deprecate/remove query-token support**: Client already uses `Authorization` + `x-echopanel-token` headers; server should stop accepting `?token=` to reduce accidental leakage via logs/proxies (SP-004/SP-005).
2. **Add explicit user consent dialog**: Beyond macOS permissions, show explanation of data flow
3. **Implement PII redaction in transcripts**: Server-side redaction of detected PII in ASR output

### Medium Priority

4. **Add permission change observer**: Monitor for Screen Recording/Microphone permission revocation
5. **Harden debug audio dump**: Retention cleanup exists; consider moving dumps out of `/tmp`, tightening permissions, and keeping it disabled by default (SP-010).
6. **Add user data export**: Allow users to export/delete session transcripts
7. **Document retention policy**: Formalize data retention for local server

### Low Priority

8. **Encrypt UserDefaults**: Consider encrypting sensitive configuration
9. **Add consent logging**: Log when user grants/denies permissions
10. **Certificate pinning UI**: Show TLS certificate info for remote connections

---

## 8. Files Inspected

| File | Purpose | Lines |
|------|---------|-------|
| `macapp/MeetingListenerApp/Sources/KeychainHelper.swift` | Credential storage | 152 |
| `macapp/MeetingListenerApp/Sources/BackendConfig.swift` | Security config | 67 |
| `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` | Screen recording | 381 |
| `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift` | Mic capture | 192 |
| `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` | WS client | 480 |
| `macapp/MeetingListenerApp/Sources/ResilientWebSocket.swift` | Resilience | 595 |
| `macapp/MeetingListenerApp/Sources/StructuredLogger.swift` | Logging/redaction | 540 |
| `server/api/ws_live_listener.py` | WS server | 871 |

---

## 9. References

- macOS Security Framework: https://developer.apple.com/documentation/security
- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Keychain Services: https://developer.apple.com/documentation/security/keychain_services
- StructuredLogger patterns: Internal implementation SP-007
- WebSocket security: RFC 6455
- ATS exceptions: https://developer.apple.com/documentation/security/preventing_insecure_network_connections

---

**Document Version:** 1.0  
**Created:** 2026-02-11  
**Analyst:** Security & Privacy Boundary Analyst  
**Review Status:** Pending
