# EchoPanel v0.2 - Status & Roadmap

**Last Updated:** 2026-02-12  
**Current Version:** 0.2.0

---

## ✅ Completed (v0.2)

### Core Features

- Multi-source audio capture (System/Mic/Both)
- ASR provider abstraction (FasterWhisperProvider, WhisperCppProvider, VoxtralProvider)
- 10-minute sliding window analysis with incremental updates
- Entity tracking with counts & recency
- Card deduplication & rolling summary
- Speaker diarization (batch at session end)
- Session storage with auto-save (30s)
- Crash recovery support
- First-run onboarding wizard
- Embedded backend (auto-start/stop)

### Distribution & Packaging ⭐ NEW

- **Self-contained .app bundle** — PyInstaller backend (74MB) + Swift executable (10MB)
- **DMG installer** — Ready for distribution (73MB)
- **No Python required** — Runs on clean macOS 13+
- **Launch strategy** — Automatic bundled/development mode detection

### User Experience & UI

- **Source-tagged Audio**: Internal JSON protocol for separate System/Mic processing
- **Level Meters**: Dual meters for System and Mic in Side Panel
- **Recovery UI**: "Recover/Discard" options in main menu
- **Diarization Config**: Token input in Onboarding
- **Transcript Persistence**: Real-time append-to-disk logic

### De-risking & Quality

- **Pseudo-diarization**: Live labels "You" vs "System" based on source
- **Self-test**: "Test Audio" button in onboarding
- **Trust**: "Needs review" labels for low-confidence
- **Silence Detection**: Banner after 10s of no audio
- **Backend Error UI**: Onboarding alerts if server fails to start

### Audio Pipeline Hardening ⭐ NEW

- **Thread Safety**: All EMA metrics use proper NSLock synchronization
- **Device Change Monitoring**: AVFoundation notifications for input device changes
- **Error Handling**: Structured logging, buffer/conversion failure detection
- **Permission Revocation Detection**: ~2s interval checks during capture
- **Metrics**: framesProcessed, framesDropped, bufferUnderruns

### Circuit Breaker Consolidation ⭐ NEW

- **Unified Implementation**: Single shared CircuitBreaker for all resilience patterns
- **WebSocket Resilience**: Exponential backoff, message buffering, health monitoring
- **UI Integration**: CircuitBreakerStatusView for real-time status

### Beta Gating & Monetization ⭐ NEW

- **Invite Code System**: Hardcoded + admin-generated codes
- **Session Limits**: 20 sessions/month for beta tier
- **StoreKit Integration**: Monthly/Annual subscription tiers
- **Entitlements**: Unlimited sessions, all ASR models, advanced diarization

---

## 🔧 Pending Items (Post-Launch)

### Open Tickets (Not Started)

| Ticket | Type | Description | Priority |
|--------|------|-------------|----------|
| TCK-20260212-005 | FEATURE | License Key Validation (Gumroad) | P0 |
| TCK-20260212-006 | FEATURE | Usage Limits Enforcement | P0 |
| TCK-20260212-007 | FEATURE | User Account Creation (AUTH-001) | P0 |
| TCK-20260212-008 | FEATURE | Login/Sign In (AUTH-002) | P0 |
| TCK-20260212-009 | FEATURE | User Logout/Sign Out (AUTH-003) | P0 |
| TCK-20260212-010 | FEATURE | User Profile Management (AUTH-004) | P0 |

### Blocked (Needs Product/Architecture Decision)

| Flow ID | Description | Blocker |
|---------|-------------|---------|
| INT-008 | Topic Extraction (GLiNER) | Model selection pending |
| INT-009 | RAG Embedding Pipeline | Architecture decision needed |
| INT-010 | Incremental Analysis Diffing | Algorithm complexity review |

### Feature Backlog (v0.3 Candidates)

| Item | Description | Effort |
|------|-------------|--------|
| Cloud ASR provider | Implement OpenAI Whisper API provider | 4h |
| Export to Notion/Slack | Push summary to integrations | 8h |
| Custom entity detection | Allow user-defined entity patterns | 4h |
| Multi-language UI | Localization support | 4h |
| Real-time speaker labels | Streaming diarization | 8h |

---

## 🚫 Known Limitations

1. **Code Signing**: App bundle is unsigned (requires Apple Developer Program $99/year)
2. **VAD**: Client-side Silero VAD implemented but requires Core ML model bundling
3. **Clock Drift**: Multi-source synchronization groundwork laid but not fully implemented
4. **Notarization**: DMG not notarized (blocked by code signing)

---

## 📊 Build Artifacts

| Artifact | Size | Location | Status |
|----------|------|----------|--------|
| EchoPanel.app | 81 MB | `dist/EchoPanel.app` | ✅ Ready |
| DMG Installer | 73 MB | `dist/EchoPanel-0.2.0.dmg` | ✅ Ready |
| Backend (standalone) | 74 MB | `dist/echopanel-server` | ✅ Ready |

---

## 📋 Pre-Launch Checklist

- [x] Test on clean macOS install (verified — self-contained)
- [x] Bundle Python runtime (PyInstaller — 74MB backend)
- [x] Create DMG installer (73MB)
- [ ] Test with no internet (graceful degradation)
- [ ] Test with denied permissions
- [ ] Code signing (requires Apple Developer Program)
- [ ] App icon design
- [ ] App Store metadata
- [ ] Privacy policy for audio capture

---

## 🚀 v0.3 Ideas

- **Real-time speaker labels** (streaming diarization)
- **Meeting templates** (standup, 1:1, retrospective)
- **AI-powered action owner detection**
- **Calendar integration** (link to meeting events)
- **Team sharing** (share summaries with attendees)
- **Custom prompts** for summary generation

---

## 📚 Key Documentation

- **Worklog/Tickets**: `docs/WORKLOG_TICKETS.md` — All active/completed work
- **Launch Readiness**: `docs/audit/LAUNCH_READINESS_AUDIT_2026-02-12.md` — Top 10 critical tasks
- **Flow Atlas**: `docs/FLOW_ATLAS.md` — 88 flows documented across all domains
- **Audio Pipeline**: `docs/audit/audio-pipeline-deep-dive-20260211.md` — Complete audio flow analysis
- **Build Instructions**: `scripts/build_app_bundle.py --help`

---

## 🔗 Quick Commands

```bash
# Build release app bundle
python scripts/build_app_bundle.py --release

# Build with cached artifacts
python scripts/build_app_bundle.py --release --skip-swift --skip-backend

# Run Swift tests
cd macapp/MeetingListenerApp && swift test

# Run Python tests
.venv/bin/pytest -q tests/

# Test app launch
open dist/EchoPanel.app
```
