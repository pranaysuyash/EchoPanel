> **📁 ARCHIVED (2026-02-16):** First-time user friction audit. Core onboarding improvements shipped:
> - Step labels: "Step X of Y" (`OnboardingView.swift:21`)
> - Permission explanations with clear reasons
> - Backend auto-start (no manual setup needed)
> Remaining suggestions are copywriting/naming improvements (e.g., "Diarization" → "Who's Speaking"),
> not functional bugs. These are tracked as polish items. Moved to archive.

# First-Time User Persona Audit: "60-Second Value Test"

**Date:** 2026-02-13  
**App Version:** v0.2  
**Platform:** macOS  

---

## Executive Summary

This audit evaluates EchoPanel from the perspective of a first-time user with zero context and a 60-second patience budget. The goal is to identify friction points that prevent users from achieving their first "win" (a usable transcript/note) within 60 seconds of launching the app.

**Verdict:** FAILS 60-second test. Users need ~67 seconds minimum due to onboarding asking for technical tokens they don't understand.

---

## Audit Methodology

- **Persona:** First-time user, no prior knowledge of the app
- **Patience Budget:** 60 seconds
- **Goal:** Get first useful outcome without reading docs
- **Device:** MacBook Air (M2), typical productivity user

---

## 0-10 Seconds: Initial Impression

### What the App Appears to Be

**Observed:** Menu bar shows a waveform icon with no initial explanation.

**Mental Model Formed:** "Some kind of audio recording tool?"

### Terms User Doesn't Understand

| Current Term | User's Interpretation | Proposed Replacement |
|--------------|---------------------|---------------------|
| "EchoPanel" | What is this? | "Meeting Notes" or "Meeting Assistant" |
| "Roll/Compact/Full" | What do these mean? | "Live/Quick/Full Review" |
| "Surfaces" | Abstract concept | "Highlights" or "Insights" |
| "Diarization" | Technical jargon | "Who's Speaking" |
| "ASR Model" | Confusing | "Transcription Quality" |
| "Backend" | Technical | "Processing" |
| "HuggingFace Token" | Why do I need this? | (Hide - make optional) |

---

## 10-30 Seconds: First Interaction

### What Happens

1. User clicks menu bar icon
2. Menu opens showing:
   - "EchoPanel - Ready"
   - Backend status indicator (green/orange dot)
   - Timer showing "00:00"
   - "Start Listening" button
   - Beta Access section with token field

### Doubts at This Stage

| Doubt | Seconds Wasted | Root Cause |
|-------|---------------|------------|
| "Is it already recording?" | 2s | No clear "not recording" state |
| "Where will transcript appear?" | 2s | No preview of side panel |
| "Is data sent to cloud?" | 3s | No privacy indicator |
| "What is this token field?" | 3s | Beta section visible unnecessarily |

### Empty State Analysis

**Current:** "Waiting for speech" with source info

**Missing:** 
- "Play audio in your meeting to start"
- "100% Local Processing" badge
- Expected time to first transcript

---

## 30-60 Seconds: Attempting First "Win"

### Path to Value

1. Click "Start Listening" → Side panel opens ✓
2. If no audio playing → "No audio detected" banner appears
3. User must play audio from meeting/YouTube
4. Wait for transcript to appear (2-5 seconds)

### Critical Issues

**Issue 1: Onboarding Modal**
- On first launch, onboarding modal appears
- Asks for "HuggingFace Token" - confusing for first-time users
- This is the MAIN FRICTION - users don't know what this is or why they need it

**Issue 2: Beta Access Visible**
- Token field visible in menu
- "Enter invite code" - unnecessary friction

---

## Friction Points (Ranked by Seconds Wasted)

| Rank | Friction Point | Seconds Wasted | Cumulative | Fix Priority |
|------|---------------|----------------|------------|--------------|
| 1 | Onboarding asks for HF Token (unnecessary) | 15s | 15s | P0 |
| 2 | No quit button in menu | 10s | 25s | P0 |
| 3 | No explanation of Roll/Compact/Full modes | 8s | 33s | P1 |
| 4 | No "100% Local" trust indicator | 7s | 40s | P1 |
| 5 | No first-run value proposition | 7s | 47s | P1 |
| 6 | Settings hidden in menu | 5s | 52s | P2 |
| 7 | "Backend" terminology | 5s | 57s | P2 |
| 8 | Export formats unclear | 5s | 62s | P2 |
| 9 | Mode switcher unexplained | 5s | 67s | P2 |
| 10 | Beta section in main menu | 3s | 70s | P1 |

**Total: 70 seconds minimum** - EXCEEDS 60-SECOND BUDGET

---

## Proposed First-Run Flow

### Current Flow (Broken)

```
App Launch → Onboarding Modal → Ask for HuggingFace Token → Ask for permissions → Ready
```

### Proposed Flow

```
App Launch → 
  If first time: Simple tooltip "Click to start capturing"
  Menu click → "Ready to capture"
  Start Listening → Side panel with demo transcript OR
                   "Play any audio to begin"
```

### Onboarding Changes Required

1. **Remove HF Token from onboarding** - App works without it (local models)
2. **Make diarization optional** - Enable only if user has token
3. **Simplify to 3 steps max:**
   - Welcome (10 sec value prop)
   - Permissions (Screen Recording)
   - Ready (Start capturing)
4. **Add "Skip" option** for every step except permissions

---

## Empty State Recommendations

| Current | Proposed |
|---------|----------|
| "Waiting for speech" | "Play audio in your meeting to start capturing" |
| Empty panel | Show demo transcript OR "Click Start Listening to begin" |
| "Roll / Compact / Full" | "Live View / Quick Look / Full Review" |
| "Surfaces" tab | "Highlights" |
| Server status: "running" | "Processing ready" |

---

## Menu Copy Recommendations

| Current | Proposed |
|---------|----------|
| "Backend Ready" | "Ready to capture" |
| "Export JSON" | "Export for apps (JSON)" |
| "Export Markdown" | "Export for notes (Markdown)" |
| Beta section in menu | Move to Settings only |
| No quit button | Add "Quit EchoPanel" |

---

## Acceptance Criteria

- [ ] First-time user can start recording in under 30 seconds
- [ ] No technical tokens required to start
- [ ] 100% local processing clearly communicated
- [ ] Quit button visible in menu
- [ ] All technical terms have plain-language alternatives
- [ ] Empty states guide user to first success

---

## Evidence

- OnboardingView.swift:221-250 - Diarization step asks for HF Token
- MeetingListenerApp.swift:229-275 - Beta section in main menu
- Design review found "technical jargon throughout UI" (docs/audit/UI_UX_AUDIT_MULTI_PERSONA_2026-02-13.md)

---

## Follow-Up Actions

1. **P0:** Remove HF Token requirement from onboarding
2. **P0:** Add Quit button to menu
3. **P1:** Rename technical terms (Backend → Processing, ASR → Transcription)
4. **P1:** Add "100% Local" badge
5. **P2:** Add mode tooltips
6. **P2:** Simplify export descriptions
