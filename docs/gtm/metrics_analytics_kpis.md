# Metrics & Analytics Deep Dive - KPIs, Tracking Schema, Dashboards

**Date:** February 17, 2026
**Type:** Analytics Research
**Status:** IN PROGRESS
**Priority:** MEDIUM (P1)

---

## Executive Summary

This document provides comprehensive metrics and analytics framework for EchoPanel's GTM execution. The research focuses on defining KPIs for all funnel stages, creating event tracking schema, designing dashboard mockups, and establishing instrumentation plan.

**IMPORTANT CONSTRAINT:** EchoPanel's privacy-first stance means NO analytics or telemetry that sends data to cloud. All metrics must be:

1. Local-only (stored on user's device)
2. User-opt-in only (explicit consent required)
3. Privacy-respecting (no PII, no session content)
4. Aggregated only (no individual session tracking)

---

## 1. KPI Definitions by Funnel Stage

### 1.1 Awareness Stage KPIs

**Primary KPIs:**

**KPI 1: Website Visitors**
- **Definition:** Unique visitors to landing page per time period
- **Source:** Web server logs (privacy-respecting, no user tracking)
- **Target:** 1,000-5,000 visitors/month (launch phase)
- **Measurement:** Simple page view counter (no cookies, no user tracking)

**KPI 2: Traffic Sources**
- **Definition:** How users find EchoPanel (direct, social media, referrals)
- **Source:** URL tracking parameters (e.g., ?utm_source=producthunt)
- **Target:** 30%+ from social media (launch), 20%+ from referrals (long-term)
- **Measurement:** URL parameter parsing on server

**KPI 3: Content Engagement**
- **Definition:** Blog post views, social media engagement
- **Source:** Blog platform analytics, social media APIs
- **Target:** 100+ views per blog post, 50+ engagements per social post
- **Measurement:** Platform-provided metrics (user-opt-in for social media)

### 1.2 Acquisition Stage KPIs

**Primary KPIs:**

**KPI 4: Email Signups**
- **Definition:** Number of email addresses collected via waitlist form
- **Source:** Landing page form submissions
- **Target:** 200-500 signups/month (launch), 50-100/month (steady)
- **Measurement:** Form submission counter (email stored locally)

**KPI 5: Email Signup Rate**
- **Definition:** Email signups / Website visitors
- **Source:** Calculated from KPI 1 and KPI 4
- **Target:** 15-25% conversion rate
- **Measurement:** Server-side calculation

**KPI 6: Waitlist Sources**
- **Definition:** Where signups come from (Product Hunt, Twitter, etc.)
- **Source:** Email signup form (source field)
- **Target:** 40%+ from Product Hunt (launch), 20%+ from social media (steady)
- **Measurement:** Form field aggregation

### 1.3 Activation Stage KPIs

**Primary KPIs:**

**KPI 7: App Downloads**
- **Definition:** Number of EchoPanel downloads from App Store
- **Source:** App Store Connect analytics
- **Target:** 500-1,000 downloads/month (launch), 100-200/month (steady)
- **Measurement:** App Store Connect (requires Apple developer account)

**KPI 8: App Installations**
- **Definition:** Unique installations of EchoPanel
- **Source:** Local analytics (user-opt-in)
- **Target:** 80%+ of downloads result in installation
- **Measurement:** Local install counter (no cloud transmission)

**KPI 9: Permission Grant Rate**
- **Definition:** Users who grant required permissions / Total installs
- **Source:** Local event tracking
- **Target:** 90%+ grant both mic and screen recording permissions
- **Measurement:** Local permission event tracking

### 1.4 Retention Stage KPIs

**Primary KPIs:**

**KPI 10: First Session Completion Rate**
- **Definition:** Users who complete first session / Total installs
- **Source:** Local session tracking
- **Target:** 70%+ complete first session
- **Measurement:** Local session event tracking

**KPI 11: Day 1 Retention**
- **Definition:** Users who return day after first use / First session completions
- **Source:** Local event tracking
- **Target:** 60%+ return on Day 1
- **Measurement:** Local app launch events

**KPI 12: Week 1 Retention**
- **Definition:** Users who use app in first week / First session completions
- **Source:** Local event tracking
- **Target:** 50%+ use in Week 1
- **Measurement:** Local app launch events

**KPI 13: Month 1 Retention**
- **Definition:** Users who use app in first month / First session completions
- **Source:** Local event tracking
- **Target:** 40%+ use in Month 1
- **Measurement:** Local app launch events

### 1.5 Revenue Stage KPIs

**Primary KPIs:**

**KPI 14: Free-to-Paid Conversion**
- **Definition:** Users who purchase Pro / Free users with ≥3 sessions
- **Source:** StoreKit (local), local purchase events
- **Target:** 10-15% conversion within 90 days
- **Measurement:** Local purchase event tracking

**KPI 15: Monthly Recurring Revenue (MRR)**
- **Definition:** Monthly subscription revenue
- **Source:** StoreKit (local)
- **Target:** $1,000/month MRR (Year 1), $10,000/month MRR (Year 2)
- **Measurement:** Local subscription tracking

**KPI 16: Customer Lifetime Value (LTV)**
- **Definition:** Average revenue per customer over their lifetime
- **Source:** Calculated from KPI 14 and KPI 15
- **Target:** $50-100 LTV (initial), $100-200 LTV (Year 2)
- **Measurement:** Server-side calculation (no PII)

**KPI 17: Customer Acquisition Cost (CAC)**
- **Definition:** Marketing spend / New customers acquired
- **Source:** Marketing expense tracking / KPI 7
- **Target:** <30% of LTV (healthy ratio)
- **Measurement:** Manual calculation (spend / customers)

### 1.6 Engagement Stage KPIs

**Primary KPIs:**

**KPI 18: Sessions Per User Per Week**
- **Definition:** Average number of sessions per active user per week
- **Source:** Local session tracking
- **Target:** 3-5 sessions/week for active users
- **Measurement:** Local aggregation (no PII)

**KPI 19: Average Session Duration**
- **Definition:** Average duration of completed sessions
- **Source:** Local session tracking
- **Target:** 30-60 minutes (typical meeting length)
- **Measurement:** Local aggregation (no PII)

**KPI 20: Feature Usage Rates**
- **Definition:** % users who use each major feature
- **Source:** Local feature usage tracking
- **Target:** 80%+ use core features (transcription, export), 50%+ use advanced features (voice notes, RAG)
- **Measurement:** Local feature usage counters (no PII)

---

## 2. Event Tracking Schema

### 2.1 Local Event Tracking Framework

**Constraint:** No cloud transmission. All events stored locally, user-opt-in only.

**Implementation:** `StructuredLogger.swift` already exists (540 lines). Extend for metrics.

**Event Schema:**

```swift
enum AnalyticsEvent {
    // App Lifecycle
    case appLaunch(version: String)
    case appBackground
    case appForeground
    
    // Onboarding
    case onboardingStarted
    case onboardingStepCompleted(step: String)
    case onboardingCompleted(timeToComplete: TimeInterval)
    
    // Permissions
    case permissionRequest(permission: String, granted: Bool)
    case permissionDenied(permission: String)
    
    // Sessions
    case sessionStarted(audioSource: AudioSource)
    case sessionEnded(duration: TimeInterval, segments: Int)
    case sessionFailed(reason: String)
    
    // Features
    case featureUsed(feature: String)
    case export(format: String)
    case voiceNoteStarted
    case voiceNoteEnded(duration: TimeInterval)
    case search(queryLength: Int, results: Int)
    
    // Errors
    case errorOccurred(errorType: String, context: String?)
    
    // Purchases
    case purchaseStarted(product: String)
    case purchaseCompleted(product: String, price: Decimal)
    case purchaseFailed(product: String, reason: String)
    case subscriptionCancelled(product: String)
    
    // User Opt-In
    case analyticsOptIn(enabled: Bool)
}
```

### 2.2 Privacy-Respecting Aggregation

**Constraint:** Only aggregate metrics, no PII, no individual session tracking.

**Aggregation Schema:**

```swift
struct AggregatedMetrics {
    // App Lifecycle
    var appLaunchesCount: Int = 0
    var totalAppUsageTime: TimeInterval = 0
    
    // Onboarding
    var onboardingCompletionsCount: Int = 0
    var avgOnboardingTime: TimeInterval = 0
    
    // Sessions
    var totalSessionsCount: Int = 0
    var totalSessionDuration: TimeInterval = 0
    var avgSessionDuration: TimeInterval = 0
    var sessionSuccessRate: Double = 0.0
    
    // Features
    var featureUsage: [String: Int] = [:]
    var exportUsage: [String: Int] = [:]
    
    // Errors
    var errorCounts: [String: Int] = [:]
    
    // Purchases
    var totalPurchasesCount: Int = 0
    var totalRevenue: Decimal = 0.0
    var subscriptionCancellationsCount: Int = 0
    
    // No PII - Only aggregates
}
```

### 2.3 User Opt-In Flow

**Requirement:** Explicit user consent before any analytics collection.

**UI Flow:**

**Step 1: First Launch**
```
"EchoPanel collects anonymous usage statistics to improve the app.

This helps us:
• Understand how the app is used
• Identify and fix bugs
• Prioritize features based on usage

All data is stored locally on your device and never sent to the cloud.

You can change this setting anytime in Preferences.

[Allow Anonymous Analytics]
[Don't Allow]
```

**Step 2: Preference Persistence**
```
Store user's analytics preference in UserDefaults.

Key: "analyticsEnabled" (Bool)
Default: false (require opt-in)
```

**Step 3: Runtime Check**
```
Before logging any analytics event:
if UserDefaults.standard.bool(forKey: "analyticsEnabled") {
    logEvent()
}
```

---

## 3. Dashboard Design Mockups

### 3.1 Developer Dashboard (Local Only)

**Purpose:** Solo developer visibility into app performance and user issues.

**Dashboard Sections:**

**Section 1: App Performance**
```
Average Session Duration: [45 minutes]
Session Success Rate: [98.2%]
Crash-Free Sessions: [99.5%]
Memory Usage (Peak): [450MB]
CPU Usage (Average): [35%]
```

**Section 2: Feature Usage**
```
Transcription: [95% of users]
Export (Markdown): [80% of users]
Export (JSON): [45% of users]
Voice Notes: [30% of users]
Context Search: [25% of users]
Engineering MOM: [35% of users]
```

**Section 3: Error Rates**
```
Permission Denied: [2.1%]
Session Failed: [1.8%]
Export Failed: [0.5%]
Crash Reports: [0.3%]
```

**Section 4: User Feedback (Manual Import)**
```
Total Feedback Count: [142]
Top Feature Request: [Integrate with Slack]
Top Complaint: [Side panel too large]
NPS Score: [62 (from 50 responses)]
```

**Implementation:**
- [ ] Build local developer dashboard (SwiftUI app)
- [ ] Import crash reports from `CrashReporter.swift`
- [ ] Import user feedback (manual or from emails)
- [ ] Visualize metrics (charts, graphs)

### 3.2 User Dashboard (Local Only, Optional)

**Purpose:** User visibility into their own usage (self-reflection).

**Dashboard Sections:**

**Section 1: Usage Summary**
```
Total Sessions: [47]
Total Duration: [35 hours 15 minutes]
This Week: [5 sessions, 3 hours 45 minutes]
This Month: [22 sessions, 16 hours 30 minutes]
```

**Section 2: Feature Breakdown**
```
Transcription: 47 sessions
Voice Notes: 12 notes
Exports (Markdown): 23 files
Exports (JSON): 8 files
Engineering MOM: 15 files
```

**Section 3: Settings Quick Access**
```
[Link to Privacy Settings]
[Link to Data Retention]
[Link to Export All Data]
[Link to Delete All Data]
```

**Implementation:**
- [ ] Add "My Usage" section to Settings view
- [ ] Calculate metrics locally (no cloud)
- [ ] Display aggregated metrics
- [ ] Provide quick access to key settings

---

## 4. Server-Side Analytics (Privacy-Respecting)

### 4.1 Server Metrics (No PII)

**Constraint:** Server logs should NOT contain user data, only system health.

**Metrics to Track:**

**System Health:**
```
Uptime: [99.8%]
API Response Time: [150ms avg]
Error Rate: [0.5%]
Concurrent Connections: [45]
Memory Usage: [2.1GB]
CPU Usage: [35%]
```

**System Logs:**
```
2026-02-17T10:15:23Z INFO Health check: OK, model_ready: true
2026-02-17T10:15:45Z INFO Connection accepted: session_id=abc123
2026-02-17T10:16:12Z WARN High memory usage: 4.2GB
2026-02-17T10:17:34Z ERROR Transcription failed: model_timeout
```

**Privacy Note:** Server logs should NOT include:
- [x] User email addresses
- [x] User IP addresses (mask or omit)
- [x] Transcript content
- [x] Audio file identifiers
- [x] Personal identifiers

**Implementation:**
- [ ] Configure logging to redact PII (already in `StructuredLogger.swift`)
- [ ] Aggregate metrics (no individual session logs)
- [ ] Store logs locally, not transmit to third-party services

### 4.2 User Analytics (No Cloud Transmission)

**Constraint:** User analytics stored ONLY on user's device, never transmitted to cloud.

**Implementation:**

**Option 1: No Cloud Analytics**
```
All user analytics stored locally on device.

Pros:
• Maximum privacy
• No data breach risk
• Complies with GDPR/CCPA perfectly

Cons:
• Solo developer cannot see aggregate metrics
• Cannot identify broad trends

Recommendation: Use this approach for MVP launch.
```

**Option 2: User-Initiated Data Share**
```
User analytics stored locally.

User can voluntarily share anonymous metrics:
"Help improve EchoPanel by sharing anonymous usage stats. This helps us prioritize features and fix bugs. [Share Anonymous Stats] [Cancel]"

Pros:
• User control (explicit opt-in)
• Can see aggregate trends
• Privacy-respecting

Cons:
• More complex implementation
• Requires user education

Recommendation: Add this option in v1.1 after launch.
```

---

## 5. Key Performance Indicators Dashboard

### 5.1 Primary KPIs (North Star Metrics)

**North Star 1: Monthly Active Users (MAU)**
- **Definition:** Users who complete ≥1 session in last 30 days
- **Target:** 500 MAU (Year 1), 2,000 MAU (Year 2)
- **Measurement:** Local aggregation (no cloud)

**North Star 2: Free-to-Paid Conversion**
- **Definition:** % of free users who purchase Pro within 90 days
- **Target:** 10-15% conversion
- **Measurement:** Local purchase tracking

**North Star 3: NPS Score**
- **Definition:** Net Promoter Score from user surveys
- **Target:** 50+ (excellent)
- **Measurement:** User surveys (manual aggregation)

### 5.2 Secondary KPIs (Operational Metrics)

**Operational 1: App Stability**
```
Crash-Free Sessions: >98%
Session Success Rate: >95%
Permission Grant Rate: >90%
```

**Operational 2: User Engagement**
```
Avg Sessions/Week: 3-5 for active users
Avg Session Duration: 30-60 minutes
Feature Adoption: 80%+ for core features
```

**Operational 3: Revenue**
```
MRR: $1,000/month (Year 1)
LTV: $50-100 (Year 1)
CAC: <$15 (healthy ratio)
```

---

## 6. Instrumentation Plan

### 6.1 Code Instrumentation

**Areas to Instrument:**

**App Lifecycle:**
- [ ] App launch/quit events
- [ ] Background/foreground transitions
- [ ] Crash reports (already implemented in `CrashReporter.swift`)

**Onboarding Flow:**
- [ ] Onboarding start
- [ ] Onboarding step completion (each step)
- [ ] Onboarding completion
- [ ] Time to complete

**Permissions:**
- [ ] Permission request
- [ ] Permission grant/deny
- [ ] Permission retry attempts

**Session Lifecycle:**
- [ ] Session start
- [ ] Session end (success/failure)
- [ ] Session duration
- [ ] Audio source selected

**Feature Usage:**
- [ ] Transcription started/ended
- [ ] Export (each format)
- [ ] Voice note started/ended
- [ ] Search queries
- [ ] MOM template selection

**Purchases:**
- [ ] Purchase started
- [ ] Purchase completed
- [ ] Purchase failed
- [ ] Subscription cancellation

**Errors:**
- [ ] All error events with context

### 6.2 Dashboard Implementation

**Developer Dashboard (Local):**
- [ ] Create SwiftUI developer dashboard app
- [ ] Import crash reports from file system
- [ ] Visualize metrics (charts, graphs)
- [ ] Display error rates
- [ ] Display feature usage

**User Dashboard (Local):**
- [ ] Add "My Usage" section to Settings
- [ ] Calculate metrics locally
- [ ] Display session count and duration
- [ ] Display feature usage breakdown
- [ ] Provide quick access to settings

### 6.3 Testing & Validation

**Validation Steps:**

**Step 1: Verify No PII**
```
Audit all logging code:
- [x] StructuredLogger.swift has redaction patterns (confirmed)
- [ ] No email addresses in logs
- [ ] No IP addresses in logs
- [ ] No transcript content in logs
```

**Step 2: Verify No Cloud Transmission**
```
Audit all network code:
- [ ] WebSocketStreamer.swift - no user data to cloud (confirmed)
- [ ] No analytics services configured
- [ ] No third-party analytics SDKs
```

**Step 3: Verify User Opt-In**
```
Test analytics flow:
- [ ] First launch shows opt-in prompt
- [ ] Default is disabled
- [ ] Preference persisted correctly
- [ ] Analytics only collected when enabled
```

---

## 7. Action Plan

### 7.1 Analytics Implementation (Week 1-2)

**Week 1:**
- [ ] Define complete event schema
- [ ] Extend `StructuredLogger.swift` for analytics
- [ ] Implement user opt-in flow
- [ ] Add analytics opt-in to Settings

**Week 2:**
- [ ] Instrument app lifecycle events
- [ ] Instrument onboarding events
- [ ] Instrument session events
- [ ] Instrument feature usage events
- [ ] Instrument purchase events

### 7.2 Dashboard Development (Week 3-4)

**Week 3:**
- [ ] Create developer dashboard app structure
- [ ] Implement crash report import
- [ ] Implement metrics visualization
- [ ] Implement error rate display

**Week 4:**
- [ ] Add "My Usage" section to Settings
- [ ] Implement local metric calculation
- [ ] Implement feature usage display
- [ ] Test all dashboards

### 7.3 Privacy Validation (Week 5)

**Week 5:**
- [ ] Audit all logging code for PII
- [ ] Audit all network code for cloud transmission
- [ ] Test user opt-in flow
- [ ] Verify no data sent to cloud
- [ ] Document privacy compliance

---

## 8. Evidence Log

### Files Analyzed:
- `macapp/MeetingListenerApp/Sources/StructuredLogger.swift` (logging with redaction)
- `macapp/MeetingListenerApp/Sources/CrashReporter.swift` (crash reporting)
- `macapp/MeetingListenerApp/Sources/SubscriptionManager.swift` (purchase tracking)

### Code Evidence Citations:
- `StructuredLogger.swift:1-540` - Comprehensive logging with PII redaction
- `CrashReporter.swift` - Crash capture and reporting
- `SubscriptionManager.swift:1-150` - Purchase event tracking

---

## 9. Status & Next Steps

**Current Status:** IN PROGRESS

**Completed:**
- [x] KPIs defined for all funnel stages
- [x] Event tracking schema designed
- [x] Privacy-respecting aggregation framework defined
- [x] Dashboard mockups created
- [x] Instrumentation plan documented
- [x] Action plan created

**Pending:**
- [ ] Event schema implemented in code
- [ ] User opt-in flow implemented
- [ ] App instrumentation completed
- [ ] Developer dashboard built
- [ ] User dashboard section added
- [ ] Privacy validation completed
- [ ] Documentation updated

**Next Steps:**
1. Implement analytics event schema
2. Create user opt-in flow
3. Instrument all app events
4. Build developer dashboard
5. Validate no PII in logs

---

**Document Status:** Metrics framework complete, awaiting implementation
**Next Document:** Launch Execution Deep Dive (day-by-day plan, checklists, crisis response)
