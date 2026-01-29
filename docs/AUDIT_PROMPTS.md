# EchoPanel v0.2 - Specialized Audit Prompts

This document contains detailed prompts for ChatGPT/Claude to audit specific areas of the EchoPanel codebase before launch.

## 🔑 IMPORTANT: Repository Access

**All prompts assume ChatGPT/Claude has direct access to the repository.**

- **Repository Path**: `/Users/pranay/Projects/EchoPanel/`
- **Access Method**: File reading capabilities (Read tool, Glob, Grep, etc.)
- **No manual file pasting needed**: The AI can read files directly from the repository

### How to Use These Prompts

1. **Copy the prompt** from the relevant section below
2. **Paste into ChatGPT/Claude** (with repository access enabled)
3. **The AI will automatically read** the specified files from the repository
4. **Review the audit findings** and prioritize fixes

**You do NOT need to manually paste file contents** - the prompts tell the AI which files to read directly.

---

## 📊 AUDIT PRIORITY MATRIX

Based on current state and launch readiness:

| Audit Area | Priority | Impact | Effort | When to Run |
|------------|----------|--------|--------|-------------|
| **UX/Onboarding** | 🔴 **CRITICAL** | High | 1-2h | Before first invite wave |
| **Distribution/Install** | 🔴 **CRITICAL** | High | 1-2h | Before packaging app |
| **First-Run Experience** | 🟡 **HIGH** | High | 1h | After bundling complete |
| **Error Messages & Recovery** | 🟡 **HIGH** | Medium | 1-2h | Before public beta |
| **Security & Privacy** | 🟡 **HIGH** | Medium | 1-2h | Before any data storage |
| **Performance** | 🟢 **MEDIUM** | Medium | 2h | After beta feedback |
| **Accessibility** | 🟢 **MEDIUM** | Low | 1h | v0.3 planning |
| **UI Consistency** | 🟢 **LOW** | Low | 1h | Post-launch polish |

---

## 🔴 CRITICAL PRIORITY AUDITS

### 1. UX & Onboarding Flow Audit

**Goal**: Ensure first-time users can successfully complete onboarding without confusion or drop-off.

**What to audit**:
- Onboarding wizard clarity and flow
- Permission request timing and messaging
- Error states during onboarding
- Success criteria for each step
- Drop-off points and friction

**Prompt for ChatGPT/Claude**:

```markdown
# UX & Onboarding Audit for EchoPanel v0.2

You are a UX researcher conducting a heuristic evaluation of a macOS meeting notes app's onboarding flow.

## Context
EchoPanel is a menu bar app that captures meeting audio and generates AI-powered transcripts and summaries. It requires Screen Recording permission and optionally Microphone permission.

## Repository Access
You have full access to the EchoPanel codebase at `/Users/pranay/Projects/EchoPanel/`. You can read any file directly using your file reading capabilities.

## Your Task
Audit the onboarding flow for usability issues, confusing messaging, and potential drop-off points.

## Files to Analyze
Please read and analyze these files directly from the repository:
1. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/OnboardingView.swift` - Onboarding UI implementation
2. `/Users/pranay/Projects/EchoPanel/docs/ONBOARDING_COPY.md` - Onboarding messaging (if exists)
3. `/Users/pranay/Projects/EchoPanel/docs/UX.md` - UX guidelines
4. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/AppState.swift` - App state and flow logic

**Start by reading these files, then proceed with the audit.**

## Analysis Framework

### 1. Heuristic Evaluation
For each onboarding step, evaluate against:
- **Visibility of system status**: Does user know where they are in the process?
- **Match between system and real world**: Is language user-friendly?
- **User control and freedom**: Can users go back if they make a mistake?
- **Consistency**: Is terminology/styling consistent across steps?
- **Error prevention**: Are errors prevented proactively?
- **Recognition over recall**: Is information presented clearly?
- **Flexibility**: Can power users skip optional steps?
- **Aesthetic and minimalist design**: Is copy concise and focused?

### 2. Flow Analysis
Map the onboarding journey:
```
[Welcome] → [Permissions] → [Audio Source] → [Diarization (optional)] → [Model Download] → [Ready]
```

For each transition:
- What triggers the transition?
- What can go wrong?
- How are errors handled?
- What happens if user quits mid-flow?

### 3. Copy & Messaging Audit
Review all user-facing text:
- **Clarity**: Is technical jargon avoided?
- **Brevity**: Is copy scannable (not walls of text)?
- **Tone**: Is it friendly and encouraging (not intimidating)?
- **Actionability**: Does each screen have clear next steps?
- **Error messages**: Are they helpful (not just "Error occurred")?

### 4. Permission Flow Audit
For Screen Recording and Microphone permissions:
- **Timing**: Are permissions requested at the right moment?
- **Context**: Do users understand WHY permission is needed?
- **Instructions**: If permission denied, are recovery steps clear?
- **Validation**: Does app verify permission was granted?
- **Edge cases**: What if user denies then manually grants later?

### 5. First Launch Scenarios
Consider these user personas:
1. **Non-technical user**: Works in sales, uses Zoom daily, not familiar with macOS permissions
2. **Power user**: Developer, understands tech, wants to skip optional steps
3. **Slow internet user**: Hotel WiFi, model download takes 30+ minutes
4. **Privacy-conscious user**: Skeptical about HuggingFace token, wants to skip diarization

For each persona:
- Where will they struggle?
- Where might they drop off?
- What questions will they have?

### 6. Model Download UX
Specifically audit the model download step:
- Is progress visible?
- Can user cancel?
- What happens if download fails?
- What happens if user quits during download?
- Is there a way to pause/resume?
- Is time estimate shown?

## Output Format

### Summary
- Overall onboarding experience rating (1-10)
- Top 3 critical UX issues
- Top 3 quick wins for improvement

### Detailed Findings
For each issue found:
```
[SEVERITY: Critical/High/Medium/Low]
Issue: [One-line description]
Location: [File:line or screenshot reference]
Impact: [What happens to user]
Recommendation: [Specific fix]
Example: [Mock-up or copy suggestion if applicable]
```

### Comparison to Best Practices
Compare EchoPanel's onboarding to:
- macOS app onboarding patterns (e.g., Raycast, Alfred, Bartender)
- Permission request flows (how other apps handle Screen Recording)
- First-run experiences (Notion, Obsidian desktop apps)

### Priority Roadmap
Group issues by:
1. **Pre-launch blockers** (Fix before any users)
2. **Beta fixes** (Fix after first feedback)
3. **Polish items** (Nice to have for v0.3)

## Example Issue Format

```
[SEVERITY: Critical]
Issue: No feedback when Screen Recording permission is granted
Location: OnboardingView.swift:120, permissionsStep
Impact: User grants permission in System Settings but doesn't know if app detected it. May think app is frozen.
Recommendation: Add visual checkmark ✓ next to "Screen Recording" when permission detected. Poll permission status every 2s while on this step.
Example: "Screen Recording ✓ Enabled" with green checkmark animation
```
```

## Files in Repository
All files are available in the repository at `/Users/pranay/Projects/EchoPanel/`. Key files for this audit:
- `macapp/MeetingListenerApp/Sources/OnboardingView.swift`
- `docs/ONBOARDING_COPY.md` (if exists)
- `docs/UX.md`
- `macapp/MeetingListenerApp/Sources/AppState.swift`

---

### 2. Distribution & Installation Audit

**Goal**: Ensure users can successfully download, install, and launch the app without technical support.

**What to audit**:
- DMG user experience
- Gatekeeper handling
- Permission prompts on first launch
- Installation failure scenarios
- Uninstall process

**Prompt for ChatGPT/Claude**:

```markdown
# Distribution & Installation Audit for EchoPanel v0.2

You are a macOS distribution specialist reviewing the installation experience for a menu bar app.

## Context
EchoPanel will be distributed as a signed and notarized DMG file. Users download it from a website, drag to Applications, and launch. The app requires Screen Recording permission and bundles Python runtime + AI models.

## Repository Access
You have full access to the EchoPanel codebase at `/Users/pranay/Projects/EchoPanel/`. You can read any file directly using your file reading capabilities.

## Your Task
Audit the distribution and installation process for friction points, failure scenarios, and support burden.

## Files to Analyze
Please read and analyze these files directly from the repository:
1. `/Users/pranay/Projects/EchoPanel/docs/DISTRIBUTION_PLAN_v0.2.md` - Distribution strategy
2. `/Users/pranay/Projects/EchoPanel/docs/TROUBLESHOOTING.md` - Troubleshooting guide (if exists)
3. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/BackendManager.swift` - Backend startup logic
4. `/Users/pranay/Projects/EchoPanel/pyproject.toml` - Python dependencies

**Start by reading these files, then proceed with the audit.**

## Analysis Framework

### 1. Download Experience
- **File size**: Is 1.8GB DMG size acceptable? Will users expect this?
- **Download time**: On slow connections (5-10 Mbps), how long?
- **Failed downloads**: What if download corrupts? Can user resume?
- **Browser warnings**: Will browsers flag large DMG as suspicious?
- **CDN strategy**: Is Vercel/hosting reliable for large files?

### 2. DMG Experience
- **Visual design**: Is DMG window intuitive (drag to Applications)?
- **EULA/License**: Is license agreement needed?
- **Version number**: Is version visible in DMG window?
- **Background image**: Does DMG have visual instructions?
- **Ejection**: After install, does DMG auto-eject?

### 3. Gatekeeper & Security
- **Code signing**: Is app signed with valid Developer ID?
- **Notarization**: Has app been notarized by Apple?
- **First launch**: What does Gatekeeper dialog say?
- **Quarantine**: Does `xattr -d com.apple.quarantine` work if needed?
- **Malware scan**: Will macOS scan app (long pause on first launch)?

### 4. Permission Prompts
On first launch, what prompts appear:
- **Screen Recording**: Wording, timing, clarity?
- **Microphone** (optional): Can user defer this?
- **Accessibility** (if used): Is this needed?
- **Full Disk Access**: Is this needed? (Shouldn't be)

### 5. Installation Failure Scenarios
What happens if:
1. User doesn't drag to Applications (runs from DMG or Downloads)
2. User has old macOS version (< 13.0)
3. User has no internet (can't download model)
4. User denies Screen Recording permission
5. Bundled Python runtime fails to start
6. Whisper model is corrupted

For each:
- Does app fail gracefully?
- Is error message helpful?
- Can user recover without reinstalling?

### 6. First Launch Experience
After installation:
- **Launch time**: How long until app is usable?
- **Menu bar icon**: Does icon appear immediately?
- **Onboarding**: Does onboarding auto-start?
- **Background processes**: Does backend server auto-start?
- **System resources**: CPU/memory usage on idle?

### 7. Uninstall Experience
How does user remove EchoPanel:
- Delete from Applications folder → What's left behind?
- Session data location (delete this too?)
- Python runtime bundled (cleaned up?)
- Preference files (~/Library/Preferences/)
- Application Support (~/Library/Application Support/)

Is an uninstaller script needed?

### 8. Update Experience
When v0.3 is released:
- How does user know update is available?
- How do they download update?
- What happens to existing session data?
- Do settings/preferences carry over?

## Output Format

### Summary
- Installation experience rating (1-10)
- Estimated time to install (from download to first use)
- % of users expected to succeed without support
- Top 3 installation friction points

### Critical Issues
```
[SEVERITY: Blocker/Critical/High/Medium/Low]
Issue: [Description]
Scenario: [When does this happen]
User Impact: [What user experiences]
Frequency: [How often will this occur]
Fix: [Recommended solution]
```

### Support Playbook
Create a troubleshooting guide:
1. **"App won't open"** → Check Gatekeeper, System version
2. **"Screen Recording not working"** → System Settings steps
3. **"Backend failed to start"** → Python runtime issues
4. **"Model download stuck"** → Network/firewall issues
5. **"App crashes on launch"** → Crash logs, M1 vs Intel

### Comparison to Competitors
How does EchoPanel compare to:
- **Notion** (desktop DMG installation)
- **Raycast** (menu bar app, permissions flow)
- **Obsidian** (large app bundle, plugin system)

### Installation Testing Checklist
```
Test Scenarios:
[ ] Fresh Mac (no dev tools, factory reset)
[ ] Old Mac (macOS 13.0 minimum version)
[ ] Slow internet (5 Mbps) - measure time
[ ] No internet - does onboarding handle it?
[ ] Deny Screen Recording - can user retry?
[ ] Run from Downloads (not Applications) - warning?
[ ] Corrupted DMG - error message helpful?
[ ] Multiple versions installed - conflict handling?
```
```

## Files in Repository
All files are available in the repository at `/Users/pranay/Projects/EchoPanel/`. Key files for this audit:
- `docs/DISTRIBUTION_PLAN_v0.2.md`
- `docs/TROUBLESHOOTING.md` (if exists)
- `macapp/MeetingListenerApp/Sources/BackendManager.swift`
- `pyproject.toml`

---

## 🟡 HIGH PRIORITY AUDITS

### 3. Error Messages & Recovery Audit

**Goal**: Ensure users can recover from errors without frustration or data loss.

**Prompt for ChatGPT/Claude**:

```markdown
# Error Messages & Recovery Audit for EchoPanel v0.2

You are a technical writer and UX researcher auditing error handling and recovery flows.

## Context
EchoPanel is a real-time audio capture app that runs Python backend locally. Many things can go wrong: network issues, permission denials, model loading failures, disk full, crashes, etc.

## Repository Access
You have full access to the EchoPanel codebase at `/Users/pranay/Projects/EchoPanel/`. You can read any file directly using your file reading capabilities.

## Your Task
Audit all error states for:
1. **Clarity**: Do users understand what went wrong?
2. **Actionability**: Do users know how to fix it?
3. **Recovery**: Can users recover without losing data?
4. **Tone**: Is messaging empathetic (not blaming user)?

## Files to Analyze
Please read and analyze these files directly from the repository:
1. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/AppState.swift` - Main app state and error handling
2. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/BackendManager.swift` - Backend startup errors
3. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/SessionStore.swift` - Session recovery logic
4. `/Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py` - Backend error handling
5. `/Users/pranay/Projects/EchoPanel/server/main.py` - Server startup errors

**Start by reading these files and extracting all error messages, then proceed with the audit.**

## Analysis Framework

### 1. Error Message Inventory
Create a table of all error messages:

| Error Code | Message Text | Where Shown | Severity | Actionable? |
|------------|--------------|-------------|----------|-------------|
| BACKEND_START_FAILED | "Backend failed to start" | Onboarding | Critical | ❌ No |
| PERMISSION_DENIED | "Screen Recording permission required" | Onboarding | Critical | ✅ Yes |
| MODEL_LOAD_FAILED | "Failed to load AI model" | First session | Critical | ❌ No |
| ... | ... | ... | ... | ... |

For each error:
- **Clarity**: Is technical jargon avoided?
- **Actionability**: Are next steps provided?
- **Context**: Does user understand what they were doing when error occurred?

### 2. Error Message Quality Guidelines
Compare each message against best practices:

**❌ Bad**: "Error 500"
**✅ Good**: "Could not connect to server. Check your internet connection."

**❌ Bad**: "Python process exited with code 1"
**✅ Good**: "Background processing failed. Try restarting the app."

**❌ Bad**: "Permission denied"
**✅ Good**: "EchoPanel needs Screen Recording permission to capture meeting audio. Open System Settings → Privacy & Security → Screen Recording"

### 3. Error Severity Matrix
Categorize errors:

**Critical** (App unusable):
- Backend won't start
- No Screen Recording permission
- Model won't load

**High** (Feature broken):
- Diarization failed
- WebSocket disconnected
- Export failed

**Medium** (Degraded experience):
- Audio quality poor
- Entity extraction slow
- Confidence scores missing

**Low** (Cosmetic):
- UI glitch
- Timestamp formatting wrong

For each severity:
- Is user blocked from using app?
- Can user continue with degraded experience?
- Does error require immediate fix?

### 4. Recovery Flows
For each critical error, map recovery path:

Example: **Backend Start Failure**
```
User Action: Opens app → Start Listening
Error Occurs: Python backend won't start
Error Message: "Backend server failed to start"
Recovery Options:
  1. Restart app → Retry
  2. Check Python installation → Reinstall app
  3. View logs → Debug (advanced users)
User Can: [X] Retry  [ ] Skip  [X] Report  [ ] Continue
```

For each error:
- Can user retry?
- Can user skip and continue?
- Can user report/send logs?
- Does app auto-retry?

### 5. Session Recovery Audit
Review crash recovery logic:
- Does app detect incomplete session?
- Is user prompted to recover?
- What data is recovered (transcript, summaries, settings)?
- What data is lost (audio buffer, partial ASR)?
- Can user discard recovery and start fresh?

### 6. Network Error Handling
Audit network failure scenarios:
- **WebSocket disconnected mid-session**: Does user lose transcript?
- **Model download interrupted**: Can resume or must restart?
- **Slow internet**: Does app show progress or appear frozen?
- **No internet on first launch**: Can user use app offline?

### 7. Disk Space Issues
What happens when:
- Disk full during session save?
- Disk full during model download?
- Disk full during crash recovery?

Recommendations:
- Check disk space before large operations
- Show warning when <1GB free
- Gracefully degrade (save summary only, skip model)

### 8. Permission Errors
For macOS permissions:
- **Screen Recording denied**: Can user retry after granting?
- **Microphone denied**: Does app work with system audio only?
- **Full Disk Access denied** (if needed): Clear instructions?

## Output Format

### Error Message Report Card
For each error message:
```
Error: BACKEND_START_FAILED
Current Message: "Backend server failed to start"
Grade: D- (Not actionable)

Issues:
- No explanation of what "backend" means
- No troubleshooting steps
- No way to retry
- Technical jargon

Recommended Message:
"EchoPanel couldn't start its background processing.

Try these steps:
1. Quit and restart EchoPanel
2. Check that you have internet access
3. If problem persists, reinstall the app

[Restart App] [View Help Guide] [Report Issue]"
```

### Recovery Flow Improvements
For each critical error:
```
Error: Model Download Failed
Current Flow:
  1. User sees "Failed to load model"
  2. No retry option → User stuck

Improved Flow:
  1. User sees "Model download interrupted"
  2. Options: [Retry Download] [Use Cached Model] [Skip for Now]
  3. If retry fails 3x → [Contact Support] with error log
  4. User can continue without diarization
```

### Session Recovery Improvements
Current vs. Recommended:

| Aspect | Current | Recommended |
|--------|---------|-------------|
| Detection | App startup only | App startup + background check |
| Notification | Menu bar alert | Modal dialog with details |
| Options | Recover or Discard | Recover / Discard / View Summary |
| Data shown | None | Preview of recovered transcript |

### Priority Fixes
```
[CRITICAL - Fix before launch]
1. Make backend start errors actionable (add restart button)
2. Add retry logic for WebSocket disconnections
3. Improve model download failure recovery

[HIGH - Fix in beta]
4. Better disk space warnings
5. Permission error instructions clearer
6. Session recovery preview

[MEDIUM - Post-launch]
7. Standardize error message tone
8. Add error logging/reporting
9. Auto-retry for transient errors
```
```

## Files in Repository
All files are available in the repository at `/Users/pranay/Projects/EchoPanel/`. Key files for this audit:
- `macapp/MeetingListenerApp/Sources/AppState.swift`
- `macapp/MeetingListenerApp/Sources/BackendManager.swift`
- `macapp/MeetingListenerApp/Sources/SessionStore.swift`
- `server/api/ws_live_listener.py`
- `server/main.py`

---

### 4. Security & Privacy Audit

**Goal**: Ensure user data is protected and privacy claims are accurate.

**Prompt for ChatGPT/Claude**:

```markdown
# Security & Privacy Audit for EchoPanel v0.2

You are a security researcher and privacy advocate auditing a meeting notes app.

## Context
EchoPanel captures meeting audio locally, processes it with Whisper ASR, and stores transcripts/summaries. Marketing claim: "100% private - everything runs locally on your Mac."

## Repository Access
You have full access to the EchoPanel codebase at `/Users/pranay/Projects/EchoPanel/`. You can read any file directly using your file reading capabilities.

## Your Task
Verify privacy claims, identify security vulnerabilities, and ensure compliance with data protection best practices.

## Files to Analyze
Please read and analyze these files directly from the repository:
1. `/Users/pranay/Projects/EchoPanel/docs/ARCHITECTURE.md` - System architecture
2. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/SessionStore.swift` - Data storage implementation
3. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` - Network communication
4. `/Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py` - Backend WebSocket handling
5. `/Users/pranay/Projects/EchoPanel/pyproject.toml` - Python dependencies (check for CVEs)
6. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/OnboardingView.swift` - Token storage (lines 192-195)
7. `/Users/pranay/Projects/EchoPanel/docs/SECURITY.md` - Security documentation (if exists)

**Start by reading these files, then proceed with the security audit. Pay special attention to:**
- Where HuggingFace token is stored (currently UserDefaults - potential security issue)
- All network calls (verify localhost-only)
- File permissions and encryption
- Dependency vulnerabilities

## Analysis Framework

### 1. Data Inventory
Map all data types collected:

| Data Type | Source | Storage Location | Encrypted? | Sent to Server? | User Control |
|-----------|--------|------------------|------------|-----------------|--------------|
| Audio PCM | Microphone/System | Memory only (not persisted) | N/A | Localhost only | None needed |
| Transcript text | ASR output | `~/Library/Application Support/EchoPanel/sessions/` | ❌ No | ❌ No | Export/Delete |
| Entities | NER | Session JSON | ❌ No | ❌ No | Export/Delete |
| Settings | User input | UserDefaults | ❌ No | ❌ No | Manual reset |
| HF Token | User input | UserDefaults | ❌ No | Sent to HuggingFace | User provides |
| ... | ... | ... | ... | ... | ... |

For each data type:
- Where is it stored?
- Is it encrypted at rest?
- Is it encrypted in transit?
- Can user delete it?
- Does it leave the Mac?

### 2. Privacy Claims Verification
Marketing says: **"100% private - everything runs locally"**

Verify each claim:
- ✅/❌ All processing runs locally (no cloud API calls)?
- ✅/❌ Audio never leaves the Mac?
- ✅/❌ Transcripts never uploaded to servers?
- ✅/❌ No analytics/telemetry sent to third parties?
- ✅/❌ No user account required?

**Red flags to check**:
- Does app phone home?
- Are there any API calls to external services?
- Is Whisper model downloaded from HuggingFace CDN? (This is OK, just disclose)
- Is crash reporting enabled (Sentry, etc.)? (If yes, is it opt-in?)

### 3. Network Traffic Analysis
Audit all network connections:

| Endpoint | Purpose | When | Data Sent | Required? |
|----------|---------|------|-----------|-----------|
| `huggingface.co` | Model download | First launch | None | Yes |
| `localhost:8000` | Backend WebSocket | During session | PCM audio | Yes |
| ... | ... | ... | ... | ... |

Are there any unexpected connections?
- Analytics (Google Analytics, Mixpanel)?
- Crash reporting (Sentry)?
- Update checks (Sparkle)?

### 4. Local Storage Security
Review file storage:
- **Location**: `~/Library/Application Support/EchoPanel/`
- **Permissions**: Are files readable by other apps?
- **Encryption**: Should transcripts be encrypted at rest?
- **Sandboxing**: Is app sandboxed (limited file access)?

Recommendations:
- Use App Sandbox for macOS security
- Encrypt sensitive data (transcripts, tokens)
- Set restrictive file permissions (chmod 600)
- Provide "Delete All Sessions" option

### 5. Credential Storage
HuggingFace token storage:
- **Current**: Stored in UserDefaults (plist file, unencrypted)
- **Risk**: Other apps can read UserDefaults if not sandboxed
- **Recommendation**: Use macOS Keychain for secure credential storage

```swift
// Current (insecure)
UserDefaults.standard.set(token, forKey: "hfToken")

// Recommended (secure)
Keychain.set(token, forKey: "hfToken")
```

### 6. Third-Party Dependencies
Review dependencies for security:
- **faster-whisper**: Open source, audited?
- **pyannote.audio**: License restrictions, privacy concerns?
- **FastAPI/Uvicorn**: Security vulnerabilities (CVEs)?
- **torch**: Large attack surface?

Check for:
- Known CVEs (use `pip audit`)
- Malicious packages
- Outdated versions

### 7. Permission Scope
Review requested permissions:
- **Screen Recording**: Required, legitimate use ✅
- **Microphone**: Optional, legitimate use ✅
- **Full Disk Access**: ❌ Should NOT be needed
- **Accessibility**: ❌ Should NOT be needed
- **Camera**: ❌ Should NOT be needed

If any unexpected permissions:
- Why are they needed?
- Can they be removed?

### 8. Privacy Policy Compliance
Does EchoPanel need a privacy policy?
- If app collects any data → Yes (even if local-only)
- If app uses analytics → Yes
- If app has user accounts → Yes

Key sections:
1. **Data Collection**: What data is collected and why
2. **Data Storage**: Where data is stored (local Mac)
3. **Data Sharing**: Who has access (no one)
4. **User Rights**: How to delete data
5. **Third-Party Services**: HuggingFace for models
6. **Contact**: How to report privacy concerns

### 9. Vulnerability Assessment
Common macOS app vulnerabilities:

**Injection Attacks**:
- [ ] Does app sanitize user input?
- [ ] Are shell commands constructed safely?
- [ ] Is SQL injection possible? (No database, so N/A)

**Path Traversal**:
- [ ] Does app validate file paths?
- [ ] Can user access files outside app directory?

**Code Injection**:
- [ ] Is Python runtime sandboxed?
- [ ] Can user inject code via settings?

**Denial of Service**:
- [ ] Can large inputs crash app?
- [ ] Is resource usage bounded (memory, disk)?

### 10. OWASP Top 10 (Desktop Apps)
Check against OWASP guidelines:
1. **Injection** → No SQL, check shell commands
2. **Broken Authentication** → No auth (local-only)
3. **Sensitive Data Exposure** → Unencrypted transcripts
4. **XML External Entities** → N/A
5. **Broken Access Control** → File permissions
6. **Security Misconfiguration** → Check defaults
7. **XSS** → N/A (native app)
8. **Insecure Deserialization** → Check JSON parsing
9. **Using Components with Known Vulnerabilities** → `pip audit`
10. **Insufficient Logging** → Audit logs for sensitive data

## Output Format

### Privacy Scorecard
```
Overall Rating: B+ (Good, with improvements needed)

Privacy Claims Accuracy: ✅ VERIFIED
- All processing is local
- No cloud API calls
- No telemetry

Data Protection: ⚠️ NEEDS IMPROVEMENT
- Transcripts not encrypted
- Tokens stored insecurely

Network Security: ✅ GOOD
- Only localhost connections
- Model download over HTTPS
```

### Critical Vulnerabilities
```
[SEVERITY: High]
Vulnerability: HuggingFace token stored in plaintext
Location: OnboardingView.swift:194, UserDefaults
Risk: Token readable by other apps → HuggingFace account compromise
Fix: Use macOS Keychain for secure storage
Code:
```swift
import KeychainAccess
let keychain = Keychain(service: "com.echopanel.app")
keychain["hfToken"] = token
```
```

### Privacy Policy Requirements
```
Required Sections:
1. [X] Data Collection - List all data types
2. [X] Local Processing - Emphasize no cloud
3. [X] Third-Party Services - HuggingFace models
4. [ ] Data Retention - How long sessions kept
5. [ ] User Rights - How to delete data
6. [ ] Children's Privacy - COPPA compliance (if applicable)
```

### Security Checklist
```
Before Launch:
[ ] Run `pip audit` on Python dependencies
[ ] Move HF token to Keychain
[ ] Encrypt session transcripts at rest
[ ] Set file permissions to 600 (owner-only)
[ ] Verify no unexpected network calls
[ ] Test app in sandboxed mode
[ ] Write privacy policy
[ ] Add "Delete All Data" option

Beta Testing:
[ ] Test with Wireshark (monitor network traffic)
[ ] Test with privacy-focused users
[ ] Have security researcher review

Post-Launch:
[ ] Monitor for CVEs in dependencies
[ ] Offer bug bounty for security issues
[ ] Regular security audits (quarterly)
```
```

## Files in Repository
All files are available in the repository at `/Users/pranay/Projects/EchoPanel/`. Key files for this audit:
- `docs/ARCHITECTURE.md`
- `macapp/MeetingListenerApp/Sources/SessionStore.swift`
- `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`
- `macapp/MeetingListenerApp/Sources/OnboardingView.swift`
- `server/api/ws_live_listener.py`
- `pyproject.toml`
- `docs/SECURITY.md` (if exists)

---

## 🟢 MEDIUM PRIORITY AUDITS

### 5. Performance & Resource Usage Audit

**Goal**: Ensure app doesn't drain battery, hog CPU, or fill disk.

**Prompt for ChatGPT/Claude**:

```markdown
# Performance & Resource Usage Audit for EchoPanel v0.2

You are a performance engineer auditing a real-time audio processing app for efficiency.

## Context
EchoPanel runs Whisper ASR locally (CPU/GPU-intensive), captures audio streams, and maintains WebSocket connections. App runs in background during meetings (30-120 minutes).

## Repository Access
You have full access to the EchoPanel codebase at `/Users/pranay/Projects/EchoPanel/`. You can read any file directly using your file reading capabilities.

## Your Task
Identify performance bottlenecks, excessive resource usage, and battery drain issues.

## Files to Analyze
Please read and analyze these files directly from the repository:
1. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` - Audio processing
2. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/AppState.swift` - State management
3. `/Users/pranay/Projects/EchoPanel/server/services/asr_stream.py` - ASR processing loop
4. `/Users/pranay/Projects/EchoPanel/server/services/provider_faster_whisper.py` - Whisper model usage
5. `/Users/pranay/Projects/EchoPanel/server/services/analysis_stream.py` - Analysis processing

**Start by reading these files, then analyze for performance issues.**

## Analysis Framework

### 1. CPU Usage Profile
Expected CPU usage:
- **Idle**: <1% (menu bar app, no active session)
- **Listening**: 20-40% (Whisper processing)
- **Finalizing**: 50-80% spike (diarization, summary)

Audit:
- [ ] Does app respect idle state (no background processing)?
- [ ] Is Whisper running on CPU or GPU (Metal)?
- [ ] Are there unnecessary polling loops?
- [ ] Is audio processing efficient (no redundant conversions)?

### 2. Memory Usage
Expected memory:
- **Idle**: <50 MB
- **Listening**: 200-500 MB (audio buffers, Whisper model)
- **Peak**: 1-2 GB (diarization, large model)

Audit:
- [ ] Are audio buffers freed after processing?
- [ ] Is Whisper model unloaded when not in use?
- [ ] Are there memory leaks (retain cycles in Swift)?
- [ ] Is Python subprocess memory bounded?

### 3. Disk Usage
Expected disk usage:
- **App bundle**: 1.8 GB (with base model)
- **Session data**: 1-5 MB per session (JSON/JSONL)
- **Models cache**: 3-10 GB (if user downloads multiple models)

Audit:
- [ ] Are old sessions auto-cleaned (retention policy)?
- [ ] Is disk usage shown to user?
- [ ] Is app bundle size minimized (no unused dependencies)?
- [ ] Are temp files cleaned up?

### 4. Network Usage
Expected network:
- **Model download**: 1.5-5 GB (one-time)
- **During session**: 0 bytes (fully local)

Audit:
- [ ] Is WebSocket only localhost (no WAN traffic)?
- [ ] Are models downloaded efficiently (resume on fail)?
- [ ] Is bandwidth usage disclosed to user?

### 5. Battery Impact
For MacBook users during meeting:
- How long does 1-hour session drain battery?
- Does app throttle when on battery power?
- Does app use Energy Saver API?

Audit using Xcode Instruments:
- [ ] Run Energy Log profiling
- [ ] Measure battery drain (% per hour)
- [ ] Compare to competitors (Zoom, Otter.ai)

### 6. Startup Time
Expected:
- **Cold start**: <2s (launch app)
- **Backend start**: 5-10s (Python + model load)
- **First session**: 30-60s (if model not loaded)

Audit:
- [ ] Is app launch delayed by backend start? (Should be async)
- [ ] Is Whisper model lazy-loaded (only when session starts)?
- [ ] Are UI freezes avoided during heavy operations?

## Output Format

### Performance Report Card
```
CPU Usage: B (Good, could optimize Whisper)
Memory Usage: A (Excellent, no leaks detected)
Disk Usage: C (Sessions accumulate, no cleanup)
Battery Impact: B- (Acceptable, but drains faster than Zoom)
```

### Bottlenecks Identified
```
[PRIORITY: High]
Bottleneck: Whisper model stays loaded when app idle
Impact: 500 MB memory wasted when not in use
Fix: Unload model after session ends (lazy reload on next session)
Savings: -400 MB idle memory

[PRIORITY: Medium]
Bottleneck: Audio conversion happens twice (Swift → Python)
Impact: 10-15% CPU overhead
Fix: Use shared memory or optimized binary format
Savings: -5% CPU usage
```

### Resource Usage Recommendations
```
1. Implement session data retention policy (delete >30 days old)
2. Show disk usage in Settings (with "Clear Old Sessions" button)
3. Add battery-aware mode (reduce ASR frequency on low battery)
4. Lazy-load Whisper model (unload after 5 min idle)
5. Use Metal (GPU) instead of CPU for Whisper (faster + cooler)
```
```

---

### 6. UI Consistency & Design Audit

**Goal**: Ensure UI follows macOS design guidelines and is internally consistent.

**Prompt for ChatGPT/Claude**:

```markdown
# UI Consistency & Design Audit for EchoPanel v0.2

You are a macOS design expert reviewing UI consistency and adherence to Human Interface Guidelines.

## Repository Access
You have full access to the EchoPanel codebase at `/Users/pranay/Projects/EchoPanel/`. You can read any file directly using your file reading capabilities.

## Files to Analyze
Please read and analyze these UI files directly from the repository:
1. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/SidePanelView.swift` - Main UI panel
2. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/OnboardingView.swift` - Onboarding UI
3. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift` - Menu bar UI
4. `/Users/pranay/Projects/EchoPanel/docs/UI.md` - UI guidelines

**Start by reading these files, then analyze for consistency.**

## Analysis Framework

### 1. macOS HIG Compliance
Check against Apple's guidelines:
- [ ] Uses system fonts (SF Pro, SF Mono)
- [ ] Respects dark/light mode
- [ ] Uses standard spacing (8px grid)
- [ ] Uses system colors (accent color, semantic colors)
- [ ] Follows menu bar app patterns

### 2. Visual Consistency
Audit:
- Font sizes (are headings consistent?)
- Button styles (primary vs secondary)
- Spacing (padding, margins)
- Colors (is accent color consistent?)
- Icons (SF Symbols vs custom)

### 3. Interaction Patterns
Check:
- Keyboard shortcuts (standard or custom?)
- Right-click menus (contextual?)
- Drag & drop (supported where expected?)
- Hover states (visual feedback?)

## Output Format

List inconsistencies with screenshots and recommended fixes.
```

---

### 7. Accessibility Audit

**Goal**: Ensure app is usable by people with disabilities.

**Prompt for ChatGPT/Claude**:

```markdown
# Accessibility Audit for EchoPanel v0.2

You are an accessibility specialist auditing a macOS app for WCAG 2.1 compliance.

## Repository Access
You have full access to the EchoPanel codebase at `/Users/pranay/Projects/EchoPanel/`. You can read any file directly using your file reading capabilities.

## Files to Analyze
Please read and analyze these UI files directly from the repository:
1. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/SidePanelView.swift` - Main UI
2. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/OnboardingView.swift` - Onboarding UI
3. `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift` - Menu bar

**Start by reading these files, checking for accessibility labels, keyboard navigation, and VoiceOver support.**

## Analysis Framework

### 1. Screen Reader Support
- [ ] All UI elements have accessibility labels
- [ ] VoiceOver can navigate the entire UI
- [ ] Transcript text is readable by VoiceOver

### 2. Keyboard Navigation
- [ ] All actions accessible via keyboard
- [ ] Tab order is logical
- [ ] Focus indicators visible

### 3. Visual Accessibility
- [ ] Color contrast meets WCAG AA (4.5:1)
- [ ] Text scalable (respect system font size)
- [ ] No information conveyed by color alone

### 4. Motion & Animation
- [ ] Respects "Reduce Motion" setting
- [ ] No flashing content (seizure risk)

## Output Format

List accessibility violations with severity and recommended fixes.
```

---

## 📄 HOW TO USE THESE PROMPTS

### Step 1: Choose Audit Priority
Based on launch timeline:
- **Before first beta invites**: UX/Onboarding + Distribution
- **After beta testing**: Error Handling + Performance
- **Before public launch**: Security/Privacy
- **Post-launch polish**: UI Consistency + Accessibility

### Step 2: Prepare Materials
Gather files mentioned in each prompt (Swift files, docs, etc.)

### Step 3: Run Audit
Copy prompt to ChatGPT or Claude, paste relevant files/code

### Step 4: Review Findings
Prioritize issues by severity:
1. **Blockers**: Fix before launch
2. **Critical**: Fix in beta
3. **High**: Fix before public release
4. **Medium**: Post-launch improvements
5. **Low**: Nice to have

### Step 5: Track in Issues
Create GitHub issues or linear tickets for each finding

---

## 📊 AUDIT TIMELINE RECOMMENDATION

```
Week 1 (Pre-Beta):
- Monday: UX/Onboarding audit
- Tuesday: Fix critical onboarding issues
- Wednesday: Distribution audit
- Thursday: Test installation on clean Mac

Week 2 (Beta):
- Monday: Error handling audit
- Wednesday: Security/privacy audit
- Friday: Address security findings

Week 3 (Pre-Launch):
- Monday: Performance audit
- Wednesday: Final QA pass

Week 4 (Post-Launch):
- UI consistency polish
- Accessibility improvements
```

---

## 🔍 QUICK AUDIT COMPARISON

If time is limited, prioritize based on impact:

| Audit | User Impact | Launch Risk | Effort | ROI |
|-------|-------------|-------------|--------|-----|
| UX/Onboarding | 🔴 Very High | High | 2h | 🌟🌟🌟🌟🌟 |
| Distribution | 🔴 Very High | High | 1h | 🌟🌟🌟🌟🌟 |
| Error Handling | 🟡 High | Medium | 2h | 🌟🌟🌟🌟 |
| Security/Privacy | 🟡 High | High | 2h | 🌟🌟🌟🌟 |
| Performance | 🟢 Medium | Low | 2h | 🌟🌟🌟 |
| UI Consistency | 🟢 Low | Low | 1h | 🌟🌟 |
| Accessibility | 🟢 Low | Low | 1h | 🌟🌟 |

**Recommendation**: Do audits #1, #2, and #4 before launch. Others can wait for beta feedback.

---

## 📋 QUICK REFERENCE: Copy-Paste Ready Prompts

### For UX/Onboarding Audit (Priority #1)
```
You have access to the EchoPanel repository at /Users/pranay/Projects/EchoPanel/

Please perform a UX & Onboarding audit by reading and analyzing:
1. macapp/MeetingListenerApp/Sources/OnboardingView.swift
2. macapp/MeetingListenerApp/Sources/AppState.swift
3. docs/UX.md

Then follow the audit framework in docs/AUDIT_PROMPTS.md, section 1 (UX & Onboarding Flow Audit).

Focus on: permission flows, model download UX, error states, and user drop-off points.
```

### For Distribution/Installation Audit (Priority #2)
```
You have access to the EchoPanel repository at /Users/pranay/Projects/EchoPanel/

Please perform a Distribution & Installation audit by reading and analyzing:
1. docs/DISTRIBUTION_PLAN_v0.2.md
2. macapp/MeetingListenerApp/Sources/BackendManager.swift
3. pyproject.toml

Then follow the audit framework in docs/AUDIT_PROMPTS.md, section 2 (Distribution & Installation Audit).

Focus on: DMG experience, Gatekeeper handling, installation failures, and first launch experience.
```

### For Security/Privacy Audit (Priority #3)
```
You have access to the EchoPanel repository at /Users/pranay/Projects/EchoPanel/

Please perform a Security & Privacy audit by reading and analyzing:
1. macapp/MeetingListenerApp/Sources/OnboardingView.swift (check lines 192-195 for token storage)
2. macapp/MeetingListenerApp/Sources/SessionStore.swift
3. macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift
4. server/api/ws_live_listener.py
5. docs/ARCHITECTURE.md

Then follow the audit framework in docs/AUDIT_PROMPTS.md, section 4 (Security & Privacy Audit).

Focus on: verify "100% private" claims, check HuggingFace token storage (currently UserDefaults - insecure!), analyze network traffic, and review file permissions.
```

### For Error Handling Audit
```
You have access to the EchoPanel repository at /Users/pranay/Projects/EchoPanel/

Please perform an Error Messages & Recovery audit by reading and analyzing:
1. macapp/MeetingListenerApp/Sources/AppState.swift
2. macapp/MeetingListenerApp/Sources/BackendManager.swift
3. macapp/MeetingListenerApp/Sources/SessionStore.swift
4. server/api/ws_live_listener.py
5. server/main.py

Extract all error messages and evaluate them for clarity, actionability, and recovery options.

Then follow the audit framework in docs/AUDIT_PROMPTS.md, section 3 (Error Messages & Recovery Audit).
```

### For Performance Audit
```
You have access to the EchoPanel repository at /Users/pranay/Projects/EchoPanel/

Please perform a Performance & Resource Usage audit by reading and analyzing:
1. macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift
2. macapp/MeetingListenerApp/Sources/AppState.swift
3. server/services/asr_stream.py
4. server/services/provider_faster_whisper.py
5. server/services/analysis_stream.py

Then follow the audit framework in docs/AUDIT_PROMPTS.md, section 5 (Performance & Resource Usage Audit).

Focus on: CPU usage, memory leaks, battery drain, and resource optimization opportunities.
```

---

## 🎯 FINAL CHECKLIST

Before sending to ChatGPT/Claude:

- [ ] Repository access is enabled (Claude Code or ChatGPT with file access)
- [ ] Repository path is correct: `/Users/pranay/Projects/EchoPanel/`
- [ ] Prompt specifies which audit to perform (1-7)
- [ ] Prompt lists specific files to analyze
- [ ] You're ready to review findings and prioritize fixes

**Pro Tip**: Run audits sequentially (not all at once) so you can fix critical issues before moving to the next audit.
