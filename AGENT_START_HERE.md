# 👋 Agent Start Here

**Welcome to EchoPanel!** This document is your entry point to understand the current state of the project.

---

## 🎯 TL;DR — Current Status (2026-02-12)

| Area | Status | Notes |
|------|--------|-------|
| **Core Runtime** | ✅ 95% Complete | Audio capture, ASR, transcript, cards — all working |
| **Distribution** | ✅ 85% Complete | .app bundle (81MB) + DMG (73MB) built and tested |
| **Monetization** | ✅ 80% Complete | StoreKit subscriptions + Beta gating implemented |
| **Code Signing** | ❌ 0% Complete | Blocked: needs Apple Developer Program ($99/year) |
| **Authentication** | ❌ Not Started | Post-launch: user accounts, login, profiles |

**Launch Readiness: 72/100** (was 58/100 at start of sprint)

---

## 📂 Key Files to Read First

1. **[docs/STATUS_AND_ROADMAP.md](./docs/STATUS_AND_ROADMAP.md)** — Current status, what's done, what's pending
2. **[docs/WORKLOG_TICKETS.md](./docs/WORKLOG_TICKETS.md)** — All tickets (DONE/OPEN/BLOCKED)
3. **[docs/BUILD.md](./docs/BUILD.md)** — How to build the app
4. **[docs/audit/LAUNCH_READINESS_AUDIT_2026-02-12.md](./docs/audit/LAUNCH_READINESS_AUDIT_2026-02-12.md)** — Detailed launch blockers

---

## ✅ Recently Completed (This Sprint)

### 1. Self-Contained .app Bundle (Task 2) ✅
- **What:** PyInstaller backend + Swift executable in .app bundle
- **Size:** 81MB app, 73MB DMG
- **Location:** `dist/EchoPanel.app`, `dist/EchoPanel-0.2.0.dmg`
- **Ticket:** TCK-20260212-012

### 2. StoreKit Subscription (Task 1) ✅
- **What:** In-app purchases, receipt validation, entitlements
- **Files:** `SubscriptionManager.swift`, `EntitlementsManager.swift`
- **Ticket:** TCK-20260212-004

### 3. Beta Gating ✅
- **What:** Invite codes, session limits (20/month)
- **Files:** `BetaGatingManager.swift`, `scripts/generate_invite_code.py`
- **Ticket:** TCK-20260212-003

### 4. Audio Pipeline Hardening ✅
- **What:** Thread safety, device change monitoring, error handling
- **Files:** `MicrophoneCaptureManager.swift`, `AudioCaptureManager.swift`
- **Ticket:** TCK-20260212-014

### 5. Circuit Breaker Consolidation ✅
- **What:** Unified resilience patterns for WebSocket
- **Files:** `CircuitBreaker.swift`, `ResilientWebSocket.swift`
- **Ticket:** TCK-20260211-013

---

## 🚧 Open Work (Do Not Duplicate)

These tickets are OPEN but not yet started. Check WORKLOG_TICKETS.md before working on them:

| Ticket | Description | Priority |
|--------|-------------|----------|
| TCK-20260212-005 | License Key Validation (Gumroad) | P0 |
| TCK-20260212-006 | Usage Limits Enforcement | P0 |
| TCK-20260212-007 | User Account Creation | P0 |
| TCK-20260212-008 | Login/Sign In | P0 |
| TCK-20260212-009 | User Logout | P0 |
| TCK-20260212-010 | User Profile Management | P0 |

---

## 🔴 Blocked Items

| Item | Blocked By | Notes |
|------|------------|-------|
| Code Signing | Apple Developer Program ($99/year) | Required for distribution |
| Notarization | Code signing | Required for Gatekeeper |
| INT-008 | Product decision | Topic extraction model selection |
| INT-009 | Architecture decision | RAG embedding pipeline design |

---

## 🛠️ Quick Commands

```bash
# Build release app
python scripts/build_app_bundle.py --release

# Run tests
cd macapp/MeetingListenerApp && swift test
.venv/bin/pytest -q tests/

# Test bundled app
open dist/EchoPanel.app
```

---

## 📝 Documentation Structure

```
docs/
├── STATUS_AND_ROADMAP.md          ← Start here
├── WORKLOG_TICKETS.md             ← All work tracked here
├── BUILD.md                       ← Build instructions
├── FLOW_ATLAS.md                  ← 88 flows documented
├── audit/
│   ├── LAUNCH_READINESS_AUDIT_2026-02-12.md  ← Launch blockers
│   ├── audio-pipeline-deep-dive-20260211.md  ← Audio analysis
│   └── ... (30+ audit documents)
└── flows/                         ← Individual flow specs
    ├── AUD-001.md .. AUD-013.md   ← Audio flows
    ├── MOD-001.md .. MOD-007.md   ← Model lifecycle flows
    └── ... (69 flow documents)
```

---

## ⚠️ Common Traps (Don't Fall For These)

1. **"Bundle Python runtime" is DONE** — See dist/EchoPanel.app (81MB)
2. **StoreKit is DONE** — Don't reimplement, check SubscriptionManager.swift
3. **Thread safety is DONE** — NSLock everywhere, don't add more
4. **Swift build errors are FIXED** — If you see compilation errors, check your environment
5. **Check tickets before starting work** — Many items already have TCK-XXXXXX tickets

---

## 🔗 Important Links

- **Main App:** `macapp/MeetingListenerApp/`
- **Backend:** `server/`
- **Build Script:** `scripts/build_app_bundle.py`
- **Tests:** `tests/` (Python), `macapp/MeetingListenerAppTests/` (Swift)

---

## 🆘 Need Help?

1. Check [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)
2. Check [docs/WORKLOG_TICKETS.md](./docs/WORKLOG_TICKETS.md) for similar completed work
3. Look at the Flow Atlas: `docs/FLOW_ATLAS.md`
4. Check audit documents in `docs/audit/`

---

**Last Updated:** 2026-02-12  
**Version:** 0.2.0  
**Status:** Ready for code signing + distribution
