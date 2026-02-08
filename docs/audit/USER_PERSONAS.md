# User Personas for EchoPanel

## 1. Sarah - The Busy Product Manager
**Archetype for:** Efficiency, "Jobs-to-be-done", Output Quality.

- **Profile:** 32, uses a MacBook Air (M2). Jumps between Zoom, Huddles, and Meet all day.
- **Goals:**
  - Needs meeting notes *immediately* to paste into Slack/Notion.
  - Wants the app to "just work" in the background without managing windows.
  - Wants to quickly identify "Who said what" (Speaker Diarization).
- **Frustrations:**
  - Configuring audio inputs (doesn't know what "Aggregate Device" means).
  - Heavy apps that drain battery.
  - **Window Juggling:** The large EchoPanel window covers her Zoom screen, forcing her to constantly Cmd+Tab or move windows. She needs it to "snap" to the side.
  - "Techy" setup steps (e.g., Tokens).
- **Key Audit Scenario:** "The 9AM Standup"
  - Launch app -> Join Zoom -> Minimize app -> …Meeting… -> Copy Summary -> Quit.

## 2. David - The Senior Engineer
**Archetype for:** Control, Power User, Customization.

- **Profile:** 28, MacBook Pro (M3 Max). 3 monitors. Uses Raycast, Vim, Obsidian.
- **Goals:**
  - Complete control over audio routing (System vs Mic).
  - Keyboard-only navigation.
  - Data portability (wants JSON to script against).
  - Visibility into system resources (CPU/RAM usage).
- **Frustrations:**
  - Mouse-heavy UIs.
  - "Black box" processing (wants logs/status).
  - **Context Switching:** He has to leave the app to search his localized PDF specs to verify what is being discussed. He wants to "query" the meeting against his docs *in-app*.
  - Inability to tweak model parameters (Base vs Large).
- **Key Audit Scenario:** "The Debug Session"
  - Change Model -> Toggle Inputs -> Monitor "Entities" extraction live -> Export JSON -> Inspect JSON structure.

## 3. Elena - The Privacy Advocate / Consultant
**Archetype for:** Trust, Security, Reliability.

- **Profile:** 40, MacBook Pro (Security Hardened). Works with sensitive client IP.
- **Goals:**
  - Zero network egress for audio data.
  - Clear visual confirmation of recording state.
  - "Kill switch" capability (Stop means Stop).
  - Local file storage only.
- **Frustrations:**
  - "Cloud" processing (dealbreaker).
  - Vague privacy policies.
  - Apps that keep listening after the window closes.
- **Key Audit Scenario:** "The Confidential 1:1"
  - Offline Mode Test -> Verify "Processing Locally" indicators -> End Session -> "Delete Forever" workflow.
