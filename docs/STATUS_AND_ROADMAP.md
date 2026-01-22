# EchoPanel v0.2 - Status & Roadmap

## ✅ Completed (v0.2)

### Core Features
- Multi-source audio capture (System/Mic/Both)
- ASR provider abstraction (FasterWhisperProvider)
- 10-minute sliding window analysis
- Entity tracking with counts & recency
- Card deduplication & rolling summary
- Speaker diarization (batch at session end)
- Session storage with auto-save (30s)
- Crash recovery support
- First-run onboarding wizard
- Embedded backend (auto-start/stop)

---

## 🔧 Pending Items

### High Priority
| Item | Description | Effort |
|------|-------------|--------|
| **Test E2E flow** | Manually test full flow with all sources | 1h |
| **Bundle Python runtime** | Package Python + deps for distribution | 4h |
| **Model preloading** | Pre-download Whisper models on first launch | 2h |
| **Error recovery** | Handle server crash gracefully in UI | 2h |

### Medium Priority
| Item | Description | Effort |
|------|-------------|--------|
| Source-tagged WS protocol | Switch from raw binary to JSON audio frames | 3h |
| Cloud ASR provider | Implement OpenAI Whisper API provider | 4h |
| Transcript append to store | Write each ASR segment to JSONL immediately | 1h |
| Recovery UI | Add "Recover Previous Session" sheet | 2h |
| Level meter for system audio | Currently only mic has level meter | 1h |

### Low Priority
| Item | Description | Effort |
|------|-------------|--------|
| Keyboard shortcuts guide | Show shortcuts in Settings | 30m |
| Export to Notion/Slack | Push summary to integrations | 8h |
| Custom entity detection | Allow user-defined entity patterns | 4h |
| Multi-language UI | Localization support | 4h |

---

## ❓ Decision Items

### 1. Distribution Strategy
**Options:**
- A) **PyInstaller**: Bundle server as single executable (~200MB)
- B) **Bundled venv**: Include Python + pip install in Resources (~500MB)
- C) **Cloud-only**: No local server, require internet

**Recommendation:** Option A (PyInstaller) for smallest bundle size.

### 2. Model Download Strategy
**Options:**
- A) Pre-bundle `base` model, download larger on-demand
- B) Download on first launch with progress UI
- C) Let user choose in Settings, download then

**Recommendation:** Option A with Option C for power users.

### 3. Default Audio Source
**Options:**
- A) Default to "System Audio" (meeting capture)
- B) Default to "Both" (system + mic)
- C) Ask in onboarding (current)

**Recommendation:** Keep C (onboarding choice).

### 4. Diarization Token
**Issue:** Requires `ECHOPANEL_HF_TOKEN` for pyannote model.
**Options:**
- A) User provides own HuggingFace token in Settings
- B) Bundle a shared token (license issue)
- C) Make diarization optional/disabled by default

**Recommendation:** Option C, enable with user-provided token.

---

## 🚀 v0.3 Ideas

- **Real-time speaker labels** (streaming diarization)
- **Meeting templates** (standup, 1:1, retrospective)
- **AI-powered action owner detection**
- **Calendar integration** (link to meeting events)
- **Team sharing** (share summaries with attendees)
- **Custom prompts** for summary generation

---

## 📋 Pre-Launch Checklist

- [ ] Test on clean macOS install
- [ ] Test with no internet (graceful degradation)
- [ ] Test with denied permissions
- [ ] Bundle Python runtime
- [ ] Create DMG installer
- [ ] App icon design
- [ ] App Store metadata
- [ ] Privacy policy for audio capture
