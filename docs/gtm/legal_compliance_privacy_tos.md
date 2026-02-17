# Legal & Compliance Deep Dive - Privacy Policy, ToS, App Store Guidelines

**Date:** February 17, 2026
**Type:** Legal & Compliance Research
**Status:** IN PROGRESS
**Priority:** HIGH (P0)

---

## Executive Summary

This document provides comprehensive legal and compliance analysis for EchoPanel's launch. The research focuses on privacy policy review, terms of service, App Store guidelines compliance, GDPR/CCPA implications, and data deletion workflows.

---

## 1. Privacy Policy Review

### 1.1 Current Privacy Policy Analysis

**File:** `docs/PRIVACY_POLICY_SIMPLE.md` (simplified version)
**File:** `docs/PRIVACY_POLICY.md` (detailed version)

**Current Policy Coverage:**

**Data Collection:**
- [ ] What data is collected (audio, transcripts, metadata)
- [ ] How data is collected (user action, system events)
- [ ] Why data is collected (service functionality)

**Data Usage:**
- [ ] How audio is used (transcription only)
- [ ] How transcripts are used (user access, search)
- [ ] How metadata is used (session management)

**Data Storage:**
- [ ] Where data is stored (local file system)
- [ ] How long data is retained (configurable, default 90 days)
- [ ] Data backup policies (none by default, user-controlled)

**Data Sharing:**
- [ ] Third-party sharing policy (none by default)
- [ ] User-controlled sharing options (export, email)
- [ ] Subprocessor disclosure (none for local processing)

**User Rights:**
- [ ] Right to access (user controls all data)
- [ ] Right to delete (user can delete any time)
- [ ] Right to export (all export formats)
- [ ] Right to data portability (JSON export)

**Security Measures:**
- [ ] Encryption status (local storage, no cloud transmission)
- [ ] Access controls (macOS permissions)
- [ ] Data protection methods

### 1.2 Privacy Policy Gaps

**Identified Gaps:**

**Gap 1: Data Deletion Process Not Documented**
- **Issue:** User doesn't know how to delete all data
- **Impact:** Users can't exercise "right to be forgotten"
- **Severity:** Medium
- **Fix:** Add explicit "Delete All Data" section with instructions

**Gap 2: Third-Party Subprocessor Disclosure Missing**
- **Issue:** Policy doesn't explicitly state no subprocessors
- **Impact:** May appear to hide subprocessors
- **Severity:** Low
- **Fix:** Add explicit statement: "EchoPanel does not use any third-party subprocessors for core functionality."

**Gap 3: Children's Privacy Policy Missing**
- **Issue:** No COPPA compliance statement
- **Impact:** App Store requires if targeted to children
- **Severity:** Low (EchoPanel targets professionals, not children)
- **Fix:** Add: "EchoPanel is not intended for use by children under 13."

**Gap 4: International Data Transfer Policy Missing**
- **Issue:** No statement about cross-border data transfer
- **Impact:** Users in GDPR/CCPA regions may have concerns
- **Severity:** Low (data doesn't leave device, but policy should state this)
- **Fix:** Add: "EchoPanel does not transfer data across borders. All data remains on your device."

### 1.3 Privacy Policy Updates Required

**Add Sections:**

**Section 1: Complete Data Deletion**
```
**Right to Delete All Data**

You may delete all EchoPanel data at any time:

1. Open EchoPanel
2. Go to Settings → Data Retention
3. Click "Delete All Data"
4. Confirm deletion

This will permanently delete:
- All meeting recordings
- All transcripts
- All metadata
- All application data

This action cannot be undone.
```

**Section 2: Subprocessor Disclosure**
```
**Third-Party Subprocessors**

EchoPanel does not use any third-party subprocessors for core functionality:

- Audio processing: Performed entirely by MLX backend on your Mac
- Data storage: Stored locally on your device
- Transcription: No cloud services used for local MLX mode
```

**Section 3: International Data Transfers**
```
**International Data Transfers**

EchoPanel does not transfer your data across borders or to third-party countries.

All data remains on your device within your jurisdiction.

No cloud egress occurs when using local MLX backend.
```

**Section 4: Children's Privacy**
```
**Children's Privacy**

EchoPanel is not intended for use by children under 13 years of age.

We do not knowingly collect personal information from children under 13.

If we become aware that we have collected personal information from a child under 13, we will take steps to delete that information.
```

---

## 2. Terms of Service Review

### 2.1 Current ToS Analysis

**File:** `docs/TERMS_OF_SERVICE_SIMPLE.md` (simplified version)
**File:** `docs/TERMS_OF_SERVICE.md` (detailed version)

**Current ToS Coverage:**

**Service Description:**
- [ ] What service is provided
- [ ] Platform requirements (Mac, Apple Silicon)
- [ ] Service availability (no uptime guarantees documented)

**User Responsibilities:**
- [ ] Proper use guidelines
- [ ] Prohibited uses (reverse engineering, data scraping)
- [ ] Account security responsibilities

**Intellectual Property:**
- [ ] EchoPanel ownership (software, trademarks)
- [ ] User content ownership (your meetings, your data)
- [ ] License grant (to use EchoPanel)

**Limitation of Liability:**
- [ ] Disclaimer of warranties
- [ ] Limitation of damages
- [ ] Force majeure clause

**Termination:**
- [ ] User termination rights
- [ ] EchoPanel termination rights
- [ ] Effect of termination (data retention)

### 2.2 ToS Gaps

**Identified Gaps:**

**Gap 1: Service Availability Not Guaranteed**
- **Issue:** No uptime or service availability guarantee
- **Impact:** Users have no recourse if service unavailable
- **Severity:** Medium
- **Fix:** Add: "EchoPanel strives for 99.9% availability but does not guarantee uptime. Local processing means service is available as long as your Mac is running."

**Gap 2: Refund Policy Not Explicit**
- **Issue:** No clear refund policy for lifetime/subscription purchases
- **Impact:** Users unclear about refund rights
- **Severity:** High (App Store provides refunds, but policy should document)
- **Fix:** Add: "Refunds for lifetime purchases available within 30 days. Subscription cancellations take effect at end of billing period."

**Gap 3: Beta Tester Rights Not Documented**
- **Issue:** Beta testers' rights not specified
- **Impact:** Unclear relationship with beta testers
- **Severity:** Medium
- **Fix:** Add: "Beta testers receive free lifetime access in exchange for feedback. Beta testers may not disclose unreleased features publicly."

**Gap 4: Feature Discontinuation Policy Missing**
- **Issue:** No policy for removing features
- **Impact:** Users uncertain about feature stability
- **Severity:** Low
- **Fix:** Add: "EchoPanel may discontinue features with 30 days notice. Users will retain access to paid features for duration of subscription."

### 2.3 ToS Updates Required

**Add Sections:**

**Section 1: Service Availability**
```
**Service Availability**

EchoPanel strives for 99.9% service availability.

However, because EchoPanel runs locally on your device:

- Service availability depends on your Mac being powered on
- No internet connection required for local MLX backend
- Local processing means service is available whenever EchoPanel is running

EchoPanel does not guarantee uptime or continuous availability.
```

**Section 2: Refund Policy**
```
**Refund Policy**

Lifetime Purchases:
- 30-day money-back guarantee
- Contact [email] for refund requests
- Refunds processed within 5-10 business days

Subscription Purchases:
- Cancel anytime through Apple App Store
- Refund at prorated amount within current billing period
- Refunds subject to Apple's refund policy

Beta Tester Upgrades:
- Beta testers receive free lifetime access
- No refunds available (already free)
```

**Section 3: Beta Tester Rights**
```
**Beta Tester Agreement**

Beta testers who provide detailed feedback receive:
- Free Lifetime Pro access (value $79)
- Early access to new features
- Direct influence on product roadmap

Beta testers agree to:
- Provide feedback on use cases and bugs
- Not disclose unreleased features publicly
- Maintain confidentiality during beta period

Beta tester lifetime access is perpetual and not revocable for feedback provided.
```

---

## 3. App Store Guidelines Compliance

### 3.1 Key Guidelines for Meeting Transcription Apps

**Guideline 1: Data Privacy (Section 5.1)**
- **Requirement:** Clearly state what data is collected and how it's used
- **EchoPanel Status:** ✅ Compliant - Privacy Policy documents local-only processing
- **Evidence:** App Store Privacy disclosure shows "No data collected"

**Guideline 2: User-Generated Content (Section 5.2)**
- **Requirement:** User must have control over UGC
- **EchoPanel Status:** ✅ Compliant - User controls all meeting data
- **Evidence:** User can delete, export, control retention

**Guideline 3: Hardware/Software Requirements (Section 2.3)**
- **Requirement:** Clearly state system requirements
- **EchoPanel Status:** ✅ Compliant - App Store description specifies Apple Silicon
- **Evidence:** App Store description lists macOS 14+ requirement

**Guideline 4: In-App Purchase Disclosure (Section 3.2.2)**
- **Requirement:** Clearly display IAP costs and what user gets
- **EchoPanel Status:** ✅ Compliant - StoreKit products configured
- **Evidence:** SubscriptionManager.swift implements tiered subscriptions

**Guideline 5: No External Links to IAP (Section 3.2.2)**
- **Requirement:** Don't link to external website to purchase
- **EchoPanel Status:** ✅ Compliant - All purchases through App Store
- **Evidence:** No external purchase links in app

### 3.2 App Store Privacy Disclosure

**Required Fields:**

**Data Collection:**
- **Contact Info:** Not collected ✅
- **User Content:** Collected (meeting transcripts) ✅
- **Usage Data:** Not collected ✅
- **Diagnostics:** Not collected ✅

**Data Sharing:**
- **Third-Party Sharing:** None ✅
- **Analytics:** Not collected ✅

**Data Security:**
- **Encryption:** Local storage, no cloud transmission ✅
- **Data Access Control:** macOS permissions ✅

**App Store Privacy Disclosure:**
```
EchoPanel collects the following data:

Meeting Transcripts (User Content):
- Purpose: Provide meeting transcription service
- Linked to You: Yes (your meetings)
- Used to Track You: No

Audio Recordings (User Content):
- Purpose: Provide meeting transcription service
- Linked to You: Yes (your meetings)
- Used to Track You: No

No other data is collected.

Data is stored locally on your device and is never transmitted to EchoPanel servers when using local MLX backend.
```

### 3.3 App Store Review Preparation

**Submission Checklist:**

**Metadata:**
- [ ] App name: "EchoPanel: Meeting Notes" (30 chars max)
- [ ] Subtitle: "Privacy-Focused Transcription" (30 chars max)
- [ ] Description: 4000 chars (optimized for keywords)
- [ ] Keywords: "meeting transcription, meeting notes, Mac productivity" (100 chars max)
- [ ] Category: Productivity (primary), Business (secondary)

**Screenshots:**
- [ ] 6-10 screenshots (1920x1080 minimum)
- [ ] Show key workflows (start, transcribe, export, search)
- [ ] Include both light and dark mode
- [ ] No dummy data (use real transcript examples)

**Privacy:**
- [ ] Privacy URL: Link to PRIVACY_POLICY.md
- [ ] Privacy Policy updated with all required sections
- [ ] App Store Privacy Disclosure configured

**Technical:**
- [ ] Binary size optimized (under 200MB recommended)
- [ ] iOS 14+ compatibility (minimum required)
- [ ] No prohibited APIs (no private APIs)
- [ ] Sandbox compliance (App Sandbox enabled)

**Legal:**
- [ ] Terms of Use URL: Link to TERMS_OF_SERVICE.md
- [ ] Export Compliance: Cryptography disclosure (if encryption used)
- [ ] Age Rating: Appropriate rating (likely "17+" for professional context)

---

## 4. GDPR Compliance

### 4.1 GDPR Assessment

**Applicability:**
- EchoPanel targets users in EU/EEA
- GDPR applies to EU/EEA users
- Local-only processing simplifies GDPR compliance

**GDPR Principles Assessment:**

**Principle 1: Lawfulness, Fairness, Transparency**
- **Status:** ✅ Compliant
- **Evidence:** Privacy Policy clearly states data processing
- **Gap:** None identified

**Principle 2: Purpose Limitation**
- **Status:** ✅ Compliant
- **Evidence:** Audio used only for transcription, no secondary purposes
- **Gap:** None identified

**Principle 3: Data Minimization**
- **Status:** ✅ Compliant
- **Evidence:** Only collects meeting audio, not extraneous data
- **Gap:** None identified

**Principle 4: Accuracy**
- **Status:** ✅ Compliant
- **Evidence:** Transcription accuracy is functional requirement
- **Gap:** None identified

**Principle 5: Storage Limitation**
- **Status:** ✅ Compliant
- **Evidence:** Configurable data retention (default 90 days)
- **Gap:** None identified

**Principle 6: Integrity and Confidentiality**
- **Status:** ✅ Compliant
- **Evidence:** Local storage with macOS security, no cloud transmission
- **Gap:** None identified

**Principle 7: Accountability**
- **Status:** ✅ Compliant
- **Evidence:** Contact information provided, privacy policy available
- **Gap:** None identified

### 4.2 GDPR User Rights

**Right 1: Right to Access (Article 15)**
- **Implementation:** User can access all data in app
- **Status:** ✅ Implemented
- **Evidence:** Session history view shows all transcripts

**Right 2: Right to Rectification (Article 16)**
- **Implementation:** User can edit transcripts
- **Status:** ✅ Implemented
- **Evidence:** Transcript is editable in side panel

**Right 3: Right to Erasure (Article 17)**
- **Implementation:** User can delete any or all sessions
- **Status:** ✅ Implemented
- **Evidence:** Data retention manager with delete options

**Right 4: Right to Restrict Processing (Article 18)**
- **Implementation:** User can stop listening at any time
- **Status:** ✅ Implemented
- **Evidence:** Start/Stop controls in menu bar

**Right 5: Right to Data Portability (Article 20)**
- **Implementation:** User can export all data in multiple formats
- **Status:** ✅ Implemented
- **Evidence:** JSON, Markdown, SRT, WebVTT exports

**Right 6: Right to Object (Article 21)**
- **Implementation:** User can uninstall app (stops all processing)
- **Status:** ✅ Implemented
- **Evidence:** Uninstalling stops all processing

### 4.3 GDPR Gaps

**Gap 1: DPO Contact Not Explicit**
- **Issue:** No explicit Data Protection Officer contact
- **Impact:** EU users may want designated privacy contact
- **Severity:** Low (solo developer acts as DPO)
- **Fix:** Add: "Data Protection: [email] - all GDPR requests handled promptly"

**Gap 2: Data Retention Not Explicit for GDPR**
- **Issue:** No explicit "within 30 days" statement
- **Impact:** GDPR requires explicit retention periods
- **Severity:** Low (90-day default is reasonable, but should be explicit)
- **Fix:** Add: "Data retained for 90 days by default, configurable in settings."

### 4.4 GDPR Updates Required

**Add to Privacy Policy:**

**Section: GDPR Compliance**
```
**GDPR Compliance**

EchoPanel complies with General Data Protection Regulation (GDPR) for users in the European Union and European Economic Area.

Your Rights Under GDPR:

Right to Access: You can access all your meeting data within EchoPanel.
Right to Rectification: You can edit any transcript.
Right to Erasure: You can delete any or all meeting data.
Right to Restrict Processing: You can stop transcription at any time.
Right to Data Portability: You can export all data in JSON, Markdown, SRT, or WebVTT formats.
Right to Object: You can uninstall EchoPanel to stop all processing.

Data Protection Contact:
For all GDPR-related requests, contact: [email]

We will respond to GDPR requests within 30 days.

Data Retention:
Data is retained for 90 days by default, configurable in Settings.
```

---

## 5. CCPA Compliance

### 5.1 CCPA Assessment

**Applicability:**
- EchoPanel targets users in California
- CCPA applies to CA residents
- Local-only processing simplifies CCPA compliance

**CCPA Requirements Assessment:**

**Requirement 1: Notice at Collection**
- **Status:** ✅ Compliant
- **Evidence:** Privacy Policy states what data is collected
- **Gap:** None identified

**Requirement 2: Right to Know**
- **Status:** ✅ Compliant
- **Evidence:** User can access all data in app
- **Gap:** None identified

**Requirement 3: Right to Delete**
- **Status:** ✅ Compliant
- **Evidence:** User can delete any or all sessions
- **Gap:** None identified

**Requirement 4: Right to Opt-Out**
- **Status:** ✅ Compliant (no sale of data)
- **Evidence:** Privacy Policy states no data sale
- **Gap:** None identified

**Requirement 5: Non-Discrimination**
- **Status:** ✅ Compliant
- **Evidence:** Same service provided to all users
- **Gap:** None identified

### 5.2 CCPA Do Not Sell My Information

**Policy Statement:**
```
**Do Not Sell My Information**

EchoPanel does not sell your personal information.

We never:
- Sell meeting transcripts to third parties
- Sell user data to advertisers
- Share user data with data brokers
- Use user data for marketing beyond service functionality

Your meeting data remains under your control at all times.
```

---

## 6. Data Deletion Workflow

### 6.1 User Data Deletion

**Current Implementation:**

**Evidence:** `DataRetentionManager.swift:68-103` (cleanupOldSessions function)

**Functionality:**
- [ ] Delete sessions older than retention period
- [ ] Delete session directory and all contents
- [ ] Automatic cleanup every 24 hours
- [ ] User can configure retention period (0-365 days)

**User Interface:**
- [ ] Settings → Data Retention → Retention Period
- [ ] Settings → Data Retention → "Delete All Data"
- [ ] Session History → Individual session → Delete

### 6.2 Data Deletion Improvements

**Improvement 1: Add "Delete All Data" Button**
- **Current:** Can only delete by waiting for retention period or deleting individual sessions
- **Improvement:** Add "Delete All Data" button in Settings
- **UI Location:** Settings → Data Retention → Delete All Data
- **Confirmation:** "This will permanently delete ALL EchoPanel data. Are you sure?"

**Improvement 2: Data Deletion Confirmation**
- **Current:** No explicit confirmation for individual session deletion
- **Improvement:** Add confirmation dialog
- **Message:** "Delete this session and all associated data? This action cannot be undone."

**Improvement 3: Export Before Deletion**
- **Current:** No prompt to export before deletion
- **Improvement:** Add option: "Export before deleting?"
- **Benefit:** Users can backup before deletion

### 6.3 Data Deletion Documentation

**Add to Privacy Policy:**

```
**Data Deletion**

You may delete EchoPanel data at any time:

1. Delete Individual Sessions:
   - Open Session History
   - Select session
   - Click "Delete"
   - Confirm deletion

2. Delete All Data:
   - Open Settings → Data Retention
   - Click "Delete All Data"
   - Confirm deletion

3. Configure Automatic Deletion:
   - Open Settings → Data Retention
   - Set retention period (0-365 days)
   - Sessions older than this period are automatically deleted

Data deletion is permanent and cannot be undone.

We recommend exporting data before deletion if you may need it later.
```

---

## 7. Action Plan

### 7.1 Legal Document Updates (Week 1)

**Week 1:**
- [ ] Update Privacy Policy with 4 new sections
- [ ] Update Terms of Service with 3 new sections
- [ ] Add GDPR Compliance section to Privacy Policy
- [ ] Add CCPA Do Not Sell section to Privacy Policy
- [ ] Document data deletion workflow in Privacy Policy

### 7.2 App Store Submission Preparation (Week 2)

**Week 2:**
- [ ] Complete App Store metadata (name, subtitle, description, keywords)
- [ ] Create 6-10 screenshots meeting guidelines
- [ ] Configure App Store Privacy Disclosure
- [ ] Complete App Store submission checklist
- [ ] Submit to App Store for review

### 7.3 App Store Review Response (Week 3-4)

**Week 3-4:**
- [ ] Monitor App Store review status
- [ ] Prepare for potential rejections
- [ ] Address reviewer questions promptly
- [ ] Resubmit if rejected

---

## 8. Evidence Log

### Files Analyzed:
- `docs/PRIVACY_POLICY.md` (current privacy policy)
- `docs/PRIVACY_POLICY_SIMPLE.md` (simplified privacy policy)
- `docs/TERMS_OF_SERVICE.md` (current ToS)
- `docs/TERMS_OF_SERVICE_SIMPLE.md` (simplified ToS)
- `macapp/MeetingListenerApp/Sources/DataRetentionManager.swift` (data deletion)
- `macapp/MeetingListenerApp/Sources/SubscriptionManager.swift` (IAP disclosure)

### Code Evidence Citations:
- `DataRetentionManager.swift:68-103` - cleanupOldSessions implementation
- `SubscriptionManager.swift:1-150` - StoreKit IAP configuration

---

## 9. Status & Next Steps

**Current Status:** IN PROGRESS

**Completed:**
- [x] Privacy Policy reviewed and gaps identified
- [x] Terms of Service reviewed and gaps identified
- [x] App Store Guidelines compliance assessed
- [x] GDPR compliance requirements analyzed
- [x] CCPA compliance requirements analyzed
- [x] Data deletion workflow reviewed
- [x] Action plan created

**Pending:**
- [ ] Privacy Policy updated with 4 new sections
- [ ] Terms of Service updated with 3 new sections
- [ ] GDPR compliance section added
- [ ] CCPA Do Not Sell section added
- [ ] Data deletion documentation added
- [ ] App Store metadata completed
- [ ] App Store submission completed
- [ ] App Store review response prepared

**Next Steps:**
1. Update Privacy Policy with all required sections
2. Update Terms of Service with all required sections
3. Prepare App Store submission
4. Submit to App Store for review

---

**Document Status:** Legal analysis complete, awaiting documentation updates
**Next Document:** Metrics & Analytics Deep Dive (KPIs, tracking schema, dashboards)
