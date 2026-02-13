# EchoPanel Implementation Roadmap v0.2 → v1.0

**Document Version**: 1.0
**Created**: 2026-02-12
**Purpose**: Phased implementation plan to bridge gaps between current state (v0.2 beta) and production launch (v1.0)

---

## Executive Summary

EchoPanel v0.2 is feature-complete for core functionality but has **critical gaps** in business-critical flows. This roadmap provides a **phased approach** to production readiness.

**Current State**:
- ✅ Core Runtime: 100% complete (12/12 flows)
- ✅ UX & Copy: 100% complete (69/69 flows)
- ✅ Lifecycle/Admin: 100% complete (20/20 flows)
- ✅ Security/Privacy: 100% complete (15/15 flows)
- ❌ Monetization: 0% complete (0/4 flows)
- ❌ Authentication: 0% complete (0/4 flows)

**Total Effort**: 27-40 weeks across 3 phases

**Recommended Priority**: Phase 1 (Monetization) → Phase 2 (Features) → Phase 3 (Infrastructure)

---

## Phase 1: Critical Business Flows (v0.3)

**Timeline**: 16-24 weeks
**Priority**: P0 - Required for commercial launch
**Business Impact**: Enables revenue generation and user tier management

### 1.1 Free Beta Gating (MON-001)

**Effort**: 2-3 weeks
**Dependencies**: None

**Scope**:
- Invite code validation system
- Session limits (e.g., 20 sessions/month)
- Upgrade prompts when limits reached
- Beta waitlist management (optional)

**Acceptance Criteria**:
- [ ] Invite code entry UI in Settings or Onboarding
- [ ] Session counter persisted in SessionStore
- [ ] Session limit enforcement with grace period
- [ ] Upgrade prompt appears when limit reached
- [ ] Grace period allows existing session to complete
- [ ] Admin tool to generate invite codes
- [ ] Audit log of invite code usage

**Technical Requirements**:
- Swift: `BetaGatingManager.swift` - manage invite codes, session counts
- Swift: `SessionStore` extension - add session count tracking
- Swift: `OnboardingView` modification - invite code input step
- Swift: `AppState` modification - check session limits before starting
- Python: Optional admin endpoint for invite code generation
- Storage: JSON file for invite codes (or use simple hardcoded list)
- Testing: Unit tests for session counting, limit enforcement

**UI Copy Required**:
```
"Enter Invite Code"
"Invalid invite code"
"Session Limit Reached"
"You've used X/Y sessions this month. Upgrade to Pro for unlimited sessions."
"Upgrade to Pro"
```

**Risks**:
- User frustration with session limits during beta
- Need migration path when inviting existing users

**Mitigation**:
- Generous session limit (20+ sessions/month)
- Graceful degradation (allow session completion)
- Admin tool to reset limits for specific users

---

### 1.2 Pro/Paid Subscription (MON-002)

**Effort**: 4-6 weeks
**Dependencies**: None

**Scope**:
- StoreKit integration for in-app purchases (IAP)
- Subscription management (Monthly/Annual tiers)
- Purchase flow (from upgrade prompt or Settings)
- Receipt validation
- Subscription status tracking
- Restore purchases flow

**Acceptance Criteria**:
- [ ] StoreKit products configured in App Store Connect
- [ ] Purchase UI available from upgrade prompt and Settings
- [ ] Monthly and Annual subscription tiers
- [ ] Receipt validation with Apple servers
- [ ] Subscription status persisted in Keychain
- [ ] Restore Purchases functionality
- [ ] Entitlement checks before Pro features
- [ ] Handle subscription expiry/cancellation
- [ ] Error handling for network failures

**Technical Requirements**:
- Swift: `SubscriptionManager.swift` - StoreKit wrapper
- Swift: `ReceiptValidator.swift` - receipt validation
- Swift: `EntitlementsManager.swift` - feature gating based on subscription
- Swift: `SettingsView` modification - add subscription section
- Swift: `UpgradePromptView.swift` - new component for upgrade prompts
- Keychain: `SubscriptionStatus` - store receipt data
- Entitlements.plist: add StoreKit capability
- Testing: Sandbox testing, receipt validation tests

**UI Copy Required**:
```
"Upgrade to Pro"
"EchoPanel Pro Features:"
"Unlimited sessions"
"Advanced ASR models"
"Priority support"
"Monthly ($X/month)"
"Annual ($X/year, Save Y%)"
"Restore Purchases"
"Subscription Active"
"Subscribed since [date]"
"Manage Subscription"
```

**Pricing Strategy** (from docs/PRICING.md):
- Monthly: $12-15/month
- Annual: $120-150/year (2 months free)
- Free tier: 20 sessions/month

**Risks**:
- App Store Connect configuration complexity
- Receipt validation security
- Subscription expiry handling
- Test environment setup

**Mitigation**:
- Follow Apple StoreKit documentation
- Use Apple's recommended validation approach
- Implement grace period for expiry
- Test extensively in sandbox

---

### 1.3 License Key Validation (MON-003)

**Effort**: 2-3 weeks
**Dependencies**: None

**Scope**:
- License key entry UI
- Gumroad API integration (or manual validation)
- License validation on app launch
- License status persistence
- Feature gating based on license

**Acceptance Criteria**:
- [ ] License key entry field in Settings
- [ ] Gumroad API integration (or validation API)
- [ ] License validation on app launch
- [ ] License status persisted in Keychain
- [ ] Feature gates based on license type (Standard/Pro)
- [ ] Handle license expiry
- [ ] Error messages for invalid/expired keys
- [ ] "Validate License" button

**Technical Requirements**:
- Swift: `LicenseManager.swift` - license validation logic
- Swift: `GumroadAPI.swift` - Gumroad integration (optional)
- Swift: `SettingsView` modification - add license key field
- Keychain: `LicenseKey` and `LicenseStatus` storage
- Python (optional): Gumroad webhook handler for license fulfillment
- Testing: Valid/invalid/expired license scenarios

**UI Copy Required**:
```
"License Key"
"Enter your EchoPanel license key"
"Validate License"
"Valid License"
"License expired"
"Invalid license key"
"License Type: Pro"
```

**Alternative Approaches**:
1. **Gumroad Webhook**: Automate license fulfillment via Gumroad
2. **Manual Validation**: Admin dashboard to validate keys offline
3. **No Backend**: Local key validation (less secure)

**Recommended**: Gumroad webhook for automation, with manual fallback

**Risks**:
- Gumroad API reliability
- License key security (stolen keys)
- Backend dependency for validation

**Mitigation**:
- Implement offline validation fallback
- Rate limit validation attempts
- Use key signatures for security

---

### 1.4 Usage Limits Enforcement (MON-004)

**Effort**: 1-2 weeks
**Dependencies**: MON-001 (Free Beta Gating)

**Scope**:
- Feature-based limits (Free vs Pro)
- Session-based limits (Free tier only)
- Feature gates for Pro features
- Usage display in Settings
- Limit exceeded handling

**Acceptance Criteria**:
- [ ] Feature gates implemented for:
  - ASR model selection (Free: Base only, Pro: All)
  - Diarization (Free: Optional, Pro: Enabled)
  - Export formats (Free: Markdown only, Pro: All formats)
  - Session history (Free: Last 10 sessions, Pro: Unlimited)
- [ ] Session limits for Free tier (e.g., 20/month)
- [ ] Usage statistics display in Settings
- [ ] Graceful error messages when limits exceeded
- [ ] Upgrade prompts for limited features
- [ ] Reset mechanism for monthly limits

**Technical Requirements**:
- Swift: `UsageTracker.swift` - track usage metrics
- Swift: `FeatureGates.swift` - define Free/Pro features
- Swift: `SettingsView` modification - add usage display
- Swift: `AppState` modification - check feature gates
- Storage: `UsageStats.json` - persist usage data
- Testing: Feature gate tests, limit enforcement tests

**UI Copy Required**:
```
"Usage"
"Sessions this month: X/Y"
"Feature: Pro only"
"Upgrade to Pro to use this feature"
"Limit Reached"
```

**Feature Gates Definition**:

| Feature | Free Tier | Pro Tier |
|---------|-----------|----------|
| ASR Models | Base English only | All models |
| Diarization | Optional | Enabled by default |
| Export Formats | Markdown only | JSON, Markdown, Bundle |
| Session History | Last 10 sessions | Unlimited |
| RAG Documents | 5 documents | Unlimited |
| API Access | None | Full access |

**Risks**:
- Over-gating frustrates free users
- Complex limit tracking
- Need clear communication

**Mitigation**:
- Generous free tier limits
- Clear UI communication
- Easy upgrade path

---

### 1.5 User Account Creation (AUTH-001)

**Effort**: 3-4 weeks
**Dependencies**: None

**Scope**:
- Account signup UI
- Email verification flow
- Password strength validation
- Account creation API
- User profile storage

**Acceptance Criteria**:
- [ ] Signup screen with email/password
- [ ] Email verification flow
- [ ] Password strength requirements
- [ ] Account creation API endpoint
- [ ] User profile stored in local database
- [ ] Error handling for duplicate emails
- [ ] Onboarding integration (signup after onboarding or during)

**Technical Requirements**:
- Swift: `SignupView.swift` - new signup UI
- Swift: `AccountManager.swift` - account management
- Swift: `EmailVerificationView.swift` - verification UI
- Python: `server/api/accounts.py` - account creation endpoint
- Python: `server/services/auth.py` - authentication service
- Storage: SQLite database for user accounts
- Email service (e.g., SendGrid) for verification emails
- Testing: Signup flow tests, verification tests

**UI Copy Required**:
```
"Create Account"
"Email"
"Password"
"Confirm Password"
"Sign Up"
"Verification email sent"
"Check your email for verification link"
"Account created"
"Email already in use"
"Password too weak"
```

**Database Schema**:
```sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  email TEXT UNIQUE,
  password_hash TEXT,
  created_at TIMESTAMP,
  verified BOOLEAN DEFAULT FALSE,
  tier TEXT DEFAULT 'free'
);
```

**Risks**:
- Email deliverability issues
- Password security
- Account recovery complexity

**Mitigation**:
- Use reliable email service
- Strong password hashing (bcrypt)
- Implement password reset flow

---

### 1.6 Login/Sign In (AUTH-002)

**Effort**: 2-3 weeks
**Dependencies**: AUTH-001 (User Account Creation)

**Scope**:
- Login UI
- Authentication API
- Session management
- Remember me functionality
- Password reset flow

**Acceptance Criteria**:
- [ ] Login screen with email/password
- [ ] Authentication API endpoint
- [ ] Session token generation and storage
- [ ] "Remember me" checkbox
- [ ] Password reset flow (email link)
- [ ] Auto-login on app launch (if "remember me")
- [ ] Error handling for invalid credentials
- [ ] Rate limiting for login attempts

**Technical Requirements**:
- Swift: `LoginView.swift` - new login UI
- Swift: `AccountManager.swift` extension - login logic
- Swift: `PasswordResetView.swift` - reset flow UI
- Python: `server/api/auth.py` - login endpoint
- Python: `server/services/auth.py` - JWT token generation
- Storage: JWT tokens in Keychain
- Testing: Login flow tests, reset flow tests

**UI Copy Required**:
```
"Sign In"
"Email"
"Password"
"Remember me"
"Sign In"
"Forgot Password?"
"Reset Password"
"Invalid email or password"
"Password reset email sent"
"Sign in successful"
```

**Authentication Flow**:
1. User enters email/password
2. Client sends POST /auth/login
3. Server validates credentials
4. Server returns JWT token
5. Client stores token in Keychain
6. Client includes token in subsequent requests

**Risks**:
- Token security (XSS, storage)
- Password reset security
- Session management complexity

**Mitigation**:
- Secure token storage (Keychain)
- Short-lived tokens with refresh
- Rate limiting on auth endpoints

---

### 1.7 User Logout/Sign Out (AUTH-003)

**Effort**: 1 week
**Dependencies**: AUTH-002 (Login/Sign In)

**Scope**:
- Logout UI
- Session invalidation
- Clear local data (optional)
- Return to login screen

**Acceptance Criteria**:
- [ ] Logout button in Settings or Menu Bar
- [ ] Client-side session invalidation
- [ ] Server-side session invalidation (optional)
- [ ] Option to clear local data on logout
- [ ] Confirmation dialog before logout
- [ ] Return to login screen after logout

**Technical Requirements**:
- Swift: `SettingsView` modification - add logout button
- Swift: `AccountManager.swift` extension - logout logic
- Python: Optional session invalidation endpoint
- Testing: Logout flow tests

**UI Copy Required**:
```
"Sign Out"
"Are you sure you want to sign out?"
"Sign Out"
"Cancel"
"Signed out successfully"
```

**Risks**:
- User accidentally logs out
- Data loss on logout

**Mitigation**:
- Confirmation dialog
- Preserve local data by default
- Option to clear data manually

---

### 1.8 User Profile Management (AUTH-004)

**Effort**: 2-3 weeks
**Dependencies**: AUTH-001 (User Account Creation)

**Scope**:
- Profile settings UI
- Email change flow
- Password change flow
- Account deletion flow
- Profile display

**Acceptance Criteria**:
- [ ] Profile settings screen
- [ ] Display account email, tier, created date
- [ ] Change email flow (with verification)
- [ ] Change password flow
- [ ] Delete account flow (with confirmation)
- [ ] Update account settings API
- [ ] Error handling for all flows

**Technical Requirements**:
- Swift: `ProfileView.swift` - new profile UI
- Swift: `AccountManager.swift` extension - profile management
- Python: `server/api/accounts.py` - profile endpoints
- Testing: Profile management tests

**UI Copy Required**:
```
"Profile"
"Email"
"Tier: Free/Pro"
"Member since: [date]"
"Change Email"
"Change Password"
"Delete Account"
"Are you sure you want to delete your account?"
"This will delete all your data and cannot be undone."
"Delete Account"
"Cancel"
"Profile updated"
```

**Risks**:
- Account deletion data loss
- Email change verification complexity

**Mitigation**:
- Clear warning before deletion
- Email verification for changes
- Soft delete with data retention period

---

## Phase 2: Feature Enhancement (v0.4)

**Timeline**: 6-9 weeks
**Priority**: P1 - Improves product competitiveness
**Business Impact**: Better intelligence, reduced compute waste

### 2.1 Embedding Generation (FG-001)

**Effort**: 2-3 weeks
**Dependencies**: None

**Scope**:
- Integrate embedding model (e.g., sentence-transformers)
- Generate embeddings for RAG documents
- Store embeddings in vector database or JSON
- Update indexing flow

**Acceptance Criteria**:
- [ ] Embedding model integrated (sentence-transformers/all-MiniLM-L6-v2)
- [ ] Embedding generation for indexed documents
- [ ] Embeddings stored in vector-compatible format
- [ ] Update RAG indexing flow to generate embeddings
- [ ] Model warmup for embeddings
- [ ] Fallback to lexical-only if embedding generation fails

**Technical Requirements**:
- Python: `server/services/embeddings.py` - new embeddings service
- Python: `server/services/rag_store.py` modification - add embedding storage
- Python: `server/api/documents.py` modification - trigger embedding generation
- Model: sentence-transformers/all-MiniLM-L6-v2 (384 dimensions)
- Storage: JSON or SQLite for embeddings
- Testing: Embedding generation tests, semantic search tests

**Model Selection**:
- **Recommended**: all-MiniLM-L6-v2 (384d, ~80MB, fast)
- **Alternative**: all-mpnet-base-v2 (768d, ~420MB, better quality)

**Risks**:
- Embedding generation latency
- Memory usage for embedding model
- Storage size for embeddings

**Mitigation**:
- Use lightweight model (MiniLM)
- Batch embedding generation
- Lazy load embedding model

---

### 2.2 Semantic Search (FG-002)

**Effort**: 1-2 weeks
**Dependencies**: FG-001 (Embedding Generation)

**Scope**:
- Implement vector similarity search
- Update RAG query flow to use embeddings
- Combine lexical and semantic results (hybrid search)
- Result ranking and scoring

**Acceptance Criteria**:
- [ ] Vector similarity search implemented (cosine similarity)
- [ ] RAG query flow updated to use semantic search
- [ ] Hybrid search (lexical + semantic) with weighting
- [ ] Result ranking by relevance score
- [ ] Fallback to lexical-only if embeddings missing
- [ ] Search results include relevance scores

**Technical Requirements**:
- Python: `server/services/rag_store.py` modification - add semantic search
- Python: `server/api/documents.py` modification - query with semantic search
- Math: NumPy for vector operations
- Testing: Semantic search tests, hybrid search tests

**Search Flow**:
1. User submits query
2. Generate query embedding
3. Calculate cosine similarity with document embeddings
4. Combine with lexical BM25 score (weighted)
5. Return top N results

**Hybrid Search Weighting**:
- Semantic: 70%
- Lexical: 30%
- Tunable via config

**Risks**:
- Query embedding latency
- Complex result ranking
- Poor quality for short queries

**Mitigation**:
- Cache query embeddings
- Simple linear weighting
- Fallback to lexical for short queries

---

### 2.3 GLiNER NER Integration (FG-003)

**Effort**: 2-3 weeks
**Dependencies**: None

**Scope**:
- Integrate GLiNER model for NER
- Replace or augment regex-based NER
- Support custom entity types
- Entity confidence scores

**Acceptance Criteria**:
- [ ] GLiNER model integrated (urchade/gliner_multi-v2.1)
- [ ] Entity extraction using GLiNER
- [ ] Support for custom entity types
- [ ] Entity confidence scores
- [ ] Fallback to regex if GLiNER fails
- [ ] Performance optimization (batching)

**Technical Requirements**:
- Python: `server/services/ner_gliner.py` - new GLiNER NER service
- Python: `server/services/analysis_stream.py` modification - use GLiNER
- Model: urchade/gliner_multi-v2.1 (~440MB)
- Testing: NER tests, entity type tests

**Entity Types**:
- Person
- Organization
- Date/Time
- Location
- Project/Task
- Money
- Custom types

**GLiNER vs Regex**:
- GLiNER: Semantic understanding, better quality, slower
- Regex: Fast, simple, pattern-based, poor quality
- Recommendation: Use GLiNER with regex fallback

**Risks**:
- GLiNER model size (440MB)
- Latency for entity extraction
- Training data bias

**Mitigation**:
- Lazy load GLiNER model
- Batch entity extraction
- Fallback to regex for speed

---

### 2.4 Topic Extraction (FG-004)

**Effort**: 1-2 weeks
**Dependencies**: GLiNER integration (optional)

**Scope**:
- Extract topics from transcript
- Topic clustering
- Topic timeline visualization
- Topic search/filter

**Acceptance Criteria**:
- [ ] Topic extraction algorithm implemented
- [ ] Topics clustered by semantic similarity
- [ ] Topic timeline in summary view
- [ ] Topic search/filter in session history
- [ ] Fallback if topic extraction fails

**Technical Requirements**:
- Python: `server/services/topic_extraction.py` - new topic service
- Python: `server/services/analysis_stream.py` modification - extract topics
- Algorithm: Keyword extraction + clustering (e.g., BERTopic)
- Testing: Topic extraction tests, clustering tests

**Topic Extraction Approaches**:
1. **Keyword-based**: TF-IDF + clustering (simple, fast)
2. **BERTopic**: BERT embeddings + HDBSCAN (better quality, slower)
3. **GLiNER**: Use as topic classifier (if trained)

**Recommendation**: Start with keyword-based, upgrade to BERTopic later

**Risks**:
- Topic quality varies
- Clustering parameter sensitivity
- Computationally expensive

**Mitigation**:
- Simple keyword extraction first
- Tunable clustering parameters
- Async topic extraction

---

### 2.5 Client-Side VAD (FG-005)

**Effort**: 1-2 weeks
**Dependencies**: None

**Scope**:
- Integrate Silero VAD model on client side
- Filter silence before transmission
- Reduce bandwidth and compute waste
- Visual VAD indicator in UI

**Acceptance Criteria**:
- [ ] Silero VAD integrated in Swift
- [ ] Silence filtering before WebSocket transmission
- [ ] Bandwidth reduction (target: 40% reduction)
- [ ] VAD status indicator in UI
- [ ] Toggle to enable/disable client-side VAD
- [ ] Fallback to server-side VAD

**Technical Requirements**:
- Swift: `ClientVAD.swift` - new VAD service
- Swift: `AudioCaptureManager.swift` modification - integrate VAD
- Model: Silero VAD (CoreML converted, ~66MB)
- UI: VAD status indicator in SidePanelView
- Testing: VAD accuracy tests, bandwidth tests

**VAD Benefits**:
- 40% compute reduction (no silence processing)
- Bandwidth savings (no silence frames)
- Improved ASR accuracy (cleaner audio)

**VAD Trade-offs**:
- Client-side: Faster, saves bandwidth, but uses client resources
- Server-side: Slower, no bandwidth savings, but offloads client

**Recommendation**: Client-side VAD for local-first architecture

**Risks**:
- Model size (66MB)
- Client CPU/memory usage
- False positives/negatives

**Mitigation**:
- Use optimized CoreML model
- Toggle to disable VAD
- Tune VAD threshold

---

### 2.6 Clock Drift Compensation (FG-006)

**Effort**: 2-3 weeks
**Dependencies**: None

**Scope**:
- Implement clock drift detection
- Adjust timestamps for multi-source sync
- CACurrentMediaTime-based synchronization
- Drift compensation algorithm

**Acceptance Criteria**:
- [ ] Clock drift detection implemented
- [ ] Timestamp adjustment for multi-source audio
- [ ] Drift compensation algorithm (linear interpolation)
- [ ] Metrics for drift detection
- [ ] Sync quality indicator in UI
- [ ] Testing with long-duration sessions

**Technical Requirements**:
- Swift: `ClockDriftManager.swift` - new drift detection service
- Swift: `RedundantAudioCaptureManager.swift` modification - track drift
- Algorithm: Linear interpolation for timestamp adjustment
- Testing: Drift compensation tests, sync quality tests

**Drift Detection**:
- Compare CACurrentMediaTime() between sources
- Calculate drift over time
- Trigger compensation when drift exceeds threshold (e.g., 10ms)

**Drift Compensation**:
1. Measure drift between system and mic clocks
2. Calculate offset for each mic sample
3. Adjust timestamps linearly
4. Realign diarization labels

**Risks**:
- Complex implementation
- Performance overhead
- Incorrect compensation

**Mitigation**:
- Simple linear interpolation
- Optional drift compensation (toggle)
- Extensive testing with long sessions

---

## Phase 3: Infrastructure & Observability (v0.5)

**Timeline**: 4-6 weeks
**Priority**: P2 - Improves reliability and data management
**Business Impact**: Better troubleshooting, data compliance

### 3.1 Metrics Persistence (IG-001)

**Effort**: 1-2 weeks
**Dependencies**: None

**Scope**:
- Persist metrics to disk
- Long-term metrics storage
- Metrics query API
- Metrics visualization UI

**Acceptance Criteria**:
- [ ] Metrics persisted to disk (JSON/SQLite)
- [ ] Metrics query API endpoint
- [ ] Metrics visualization in Diagnostics view
- [ ] Export metrics functionality
- [ ] Data retention policy (e.g., 30 days)

**Technical Requirements**:
- Python: `server/services/metrics_persistence.py` - new persistence service
- Python: `server/api/metrics.py` - new metrics API
- Storage: SQLite for metrics
- Swift: `DiagnosticsView` modification - add metrics chart
- Testing: Metrics persistence tests, query tests

**Metrics to Persist**:
- Queue depth
- RTF (realtime factor)
- Dropped frames
- ASR latency
- Memory usage
- CPU usage

**Data Retention**:
- Default: 30 days
- Configurable via Settings
- Automatic cleanup

**Risks**:
- Storage size growth
- Query performance
- Data aggregation complexity

**Mitigation**:
- Data retention policy
- Time-series optimization
- Aggregate older data

---

### 3.2 Crash Reporting (IG-002)

**Effort**: 1-2 weeks
**Dependencies**: None

**Scope**:
- Crash detection and logging
- Crash report generation
- Crash report upload (optional)
- Crash rate monitoring

**Acceptance Criteria**:
- [ ] Crash detection and logging
- [ ] Crash report generation (bundle with logs)
- [ ] Optional crash report upload to analytics service
- [ ] Crash rate tracking
- [ ] Crash report UI in Diagnostics

**Technical Requirements**:
- Swift: Crash handler (e.g., Crashlytics or custom)
- Python: Crash report API endpoint (optional)
- Integration: Crashlytics or Sentry (optional)
- Swift: `DiagnosticsView` modification - show crash history
- Testing: Crash simulation tests

**Crash Report Contents**:
- Stack trace
- System info (OS version, device)
- App version
- Session context (if available)
- Logs (last N lines)

**Crash Reporting Services**:
- **Firebase Crashlytics**: Free, easy integration
- **Sentry**: More features, paid tier
- **Custom**: Local-only, no cloud upload

**Recommendation**: Start with custom local crash reporting, add Firebase later

**Risks**:
- Crash handler overhead
- Privacy concerns (crash reports)
- False positives

**Mitigation**:
- Minimal overhead implementation
- Anonymized crash reports
- Manual review threshold

---

### 3.3 Analytics/Telemetry (IG-003)

**Effort**: 2 weeks
**Dependencies**: None

**Scope**:
- Usage analytics collection
- Feature usage tracking
- User journey mapping
- Opt-in/opt-out privacy controls

**Acceptance Criteria**:
- [ ] Analytics collection service
- [ ] Feature usage tracking
- [ ] User journey events
- [ ] Opt-in/opt-out in Settings
- [ ] Analytics API endpoint (optional)
- [ ] GDPR/privacy compliance

**Technical Requirements**:
- Swift: `AnalyticsManager.swift` - new analytics service
- Python: `server/api/analytics.py` - optional analytics endpoint
- Integration: Analytics provider (Mixpanel, Amplitude, or custom)
- Swift: `SettingsView` modification - add analytics toggle
- Testing: Analytics collection tests, privacy tests

**Analytics Events**:
- App launch
- Session start/stop
- Feature usage (export, search, etc.)
- Settings changes
- Errors/crashes

**Privacy Controls**:
- Opt-in/opt-out toggle
- Data anonymization
- No PII collected by default
- User can delete data

**Risks**:
- Privacy concerns
- Over-collecting data
- Performance overhead

**Mitigation**:
- Explicit opt-in
- Minimal data collection
- Async analytics upload

---

### 3.4 Data Retention Policy (DG-001)

**Effort**: 1-2 weeks
**Dependencies**: None

**Scope**:
- Define data retention policies
- Automatic data cleanup
- Retention settings in UI
- Compliance with privacy regulations

**Acceptance Criteria**:
- [ ] Data retention policies defined
- [ ] Automatic cleanup of old sessions
- [ ] Retention settings in Settings
- [ ] Manual cleanup option
- [ ] GDPR right to be forgotten

**Technical Requirements**:
- Swift: `DataRetentionManager.swift` - new retention service
- Swift: `SettingsView` modification - add retention settings
- Scheduled cleanup task (daily/weekly)
- Testing: Retention policy tests, cleanup tests

**Retention Policies**:
- Sessions: Default 90 days, configurable
- Logs: Default 30 days, configurable
- Metrics: Default 30 days, configurable
- RAG documents: Keep until deleted by user

**Cleanup Triggers**:
- On app launch (daily check)
- Manual cleanup button
- Settings change

**Risks**:
- User data loss
- Complex retention logic
- Compliance requirements

**Mitigation**:
- Generous default retention
- Clear user communication
- Manual override option

---

### 3.5 Encryption at Rest (DG-002)

**Effort**: 2-3 weeks
**Dependencies**: None

**Scope**:
- Encrypt stored session data
- Encrypt logs and metrics
- Key management
- Encryption settings in UI

**Acceptance Criteria**:
- [ ] Session data encryption (AES-256)
- [ ] Log and metric encryption
- [ ] Key management (Keychain)
- [ ] Encryption toggle in Settings
- [ ] Performance benchmarking (encryption overhead)

**Technical Requirements**:
- Swift: `EncryptionManager.swift` - new encryption service
- Swift: `SessionStore` modification - encrypt data
- Crypto: CryptoKit (Swift)
- Key storage: Keychain
- Testing: Encryption tests, performance tests

**Encryption Targets**:
- Session JSON/JSONL files
- Log files
- Metrics files
- RAG documents

**Key Management**:
- Encryption key stored in Keychain
- Key generated per-install
- Optional user-provided key (advanced)

**Performance Impact**:
- Estimated: <5% overhead for encryption
- Mitigation: Async encryption, chunked writes

**Risks**:
- Performance overhead
- Key loss (data inaccessible)
- Encryption bugs

**Mitigation**:
- Async encryption
- Key backup/restore
- Extensive testing

---

### 3.6 Log Centralization (IG-004)

**Effort**: 1-2 weeks
**Dependencies**: None

**Scope**:
- Centralized log collection
- Log aggregation (client + server)
- Log search/filter
- Log export functionality

**Acceptance Criteria**:
- [ ] Centralized log service
- [ ] Client and server log aggregation
- [ ] Log search/filter in Diagnostics
- [ ] Log export functionality
- [ ] Log level configuration

**Technical Requirements**:
- Swift: `CentralizedLogger.swift` - aggregate logs
- Python: `server/services/logging.py` modification - send to client
- Swift: `DiagnosticsView` modification - log search/filter
- Testing: Log aggregation tests, search tests

**Log Sources**:
- Client logs (Swift StructuredLogger)
- Server logs (Python)
- Backend process logs
- Crash reports

**Log Search**:
- Search by timestamp
- Filter by log level (ERROR, WARN, INFO, DEBUG)
- Filter by source (client/server)
- Regex search

**Risks**:
- Log volume (memory/disk)
- Search performance
- Log synchronization

**Mitigation**:
- Log rotation
- Indexed search
- Async log transfer

---

## Summary & Recommendations

### Effort Summary

| Phase | Timeline | Effort | Business Impact |
|-------|----------|--------|----------------|
| **Phase 1: Critical Business** | 16-24 weeks | 16-24 weeks | **P0 - Required for revenue** |
| **Phase 2: Feature Enhancement** | 6-9 weeks | 6-9 weeks | P1 - Competitive advantage |
| **Phase 3: Infrastructure** | 4-6 weeks | 4-6 weeks | P2 - Reliability/compliance |
| **TOTAL** | 26-39 weeks | 26-39 weeks | - |

### Recommended Priority

**Immediate (v0.2 → v0.3)**:
1. MON-001: Free Beta Gating (2-3 weeks)
2. MON-002: Pro/Paid Subscription (4-6 weeks)
3. MON-003: License Key Validation (2-3 weeks)
4. MON-004: Usage Limits Enforcement (1-2 weeks)
5. AUTH-001: User Account Creation (3-4 weeks)
6. AUTH-002: Login/Sign In (2-3 weeks)
7. AUTH-003: User Logout/Sign Out (1 week)
8. AUTH-004: User Profile Management (2-3 weeks)

**Rationale**: Monetization is required for business viability. Authentication is needed for multi-user support.

**Near-term (v0.3 → v0.4)**:
9. FG-001: Embedding Generation (2-3 weeks)
10. FG-002: Semantic Search (1-2 weeks)
11. FG-003: GLiNER NER Integration (2-3 weeks)
12. FG-004: Topic Extraction (1-2 weeks)
13. FG-005: Client-Side VAD (1-2 weeks)
14. FG-006: Clock Drift Compensation (2-3 weeks)

**Rationale**: Feature enhancements improve product quality and competitiveness.

**Long-term (v0.4 → v0.5)**:
15. IG-001: Metrics Persistence (1-2 weeks)
16. IG-002: Crash Reporting (1-2 weeks)
17. IG-003: Analytics/Telemetry (2 weeks)
18. IG-004: Log Centralization (1-2 weeks)
19. DG-001: Data Retention Policy (1-2 weeks)
20. DG-002: Encryption at Rest (2-3 weeks)

**Rationale**: Infrastructure improvements support scaling, compliance, and reliability.

### Critical Success Factors

1. **Monetization First**: Implement MON-001 through MON-004 before any other work. This enables revenue generation.
2. **User Accounts**: Implement AUTH-001 through AUTH-004 for multi-user support.
3. **Incremental Delivery**: Release v0.3 with monetization, then iterate on features.
4. **User Feedback**: Test monetization flows with beta users before v1.0 launch.
5. **Documentation**: Update docs to reflect implemented flows (not just plans).

### Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| StoreKit complexity | High | Follow Apple docs, test extensively |
| User frustration with limits | High | Generous free tier, clear communication |
| Authentication security | High | Use best practices, rate limiting |
| Model download size | Medium | Lazy loading, progress indicators |
| Performance overhead | Medium | Benchmark, optimize hot paths |
| Privacy concerns | Medium | Opt-in analytics, encryption |

### Next Actions

1. **Review this roadmap** with team/stakeholders
2. **Prioritize Phase 1 flows** based on business needs
3. **Create detailed tickets** for each flow in Phase 1
4. **Start with MON-001** (Free Beta Gating) as first implementation
5. **Update docs/PRICING.md** to reflect implementation plan
6. **Schedule regular reviews** to track progress

---

## Document Metadata

**Generated By**: Implementation Planning Session
**Based On**:
- docs/flow-atlas-v2-20260212.md
- docs/gaps-report-v2-20260212.md
- docs/coverage-report-v2-20260212.md
- docs/PRICING.md (planning doc)
- docs/LICENSING.md (planning doc)

**Confidence**: 95% - Comprehensive analysis based on flow atlas and gaps report
**Last Updated**: 2026-02-12
