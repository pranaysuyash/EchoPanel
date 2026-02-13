# EchoPanel Audit Verification & Remediation Agent Prompt

## Mission
You are an expert software engineering agent tasked with independently verifying the EchoPanel streaming ASR audit, selecting remediation tasks, implementing fixes, testing them, and documenting your work.

## Context
EchoPanel is a real-time audio transcription system with:
- macOS client capturing system audio via ScreenCaptureKit
- FastAPI WebSocket server with faster-whisper ASR
- Real-time NLP analysis (entities, actions, decisions, risks)
- Diarization support (currently disabled)

## Step 1: Audit Review & Verification (30-60 minutes)

### 1.1 Read the Audit Document
Locate and read: `docs/audit/STREAMING_ASR_AUDIT_2026-02.md`

**Verify the audit structure matches this expected format:**
- Executive Summary with issue counts
- Architecture Map (system diagram, component map, capability surface)
- Issues Fixed section
- Remaining Issues (P1/P2) with detailed analysis
- Web Research Findings
- Test Results
- 6 numbered audit sections (Dataflow, Audio Pipeline, Diarization, Reliability, Security, Observability)
- Testing Strategy Audit
- Issue Log + Execution Backlog

### 1.2 Verify Audit Claims
**For each major claim in the audit, verify by examining code:**

**Architecture Claims:**
- [ ] WebSocket handler uses `SessionState` with `started_sources` set
- [ ] Audio queues are bounded (maxsize=48) with drop-oldest policy
- [ ] ASR tasks are spawned per source using `started_sources` check
- [ ] Stop handler waits for ASR flush before final analysis
- [ ] Diarization is disabled (commented out) due to multi-source issues

**Issue Claims:**
- [ ] P0-4: No authentication - verify WS accepts any connection
- [ ] P0-5: Unencrypted transport - verify `ws://` usage
- [ ] P1-5: Timestamp drift - verify server uses processed samples, not client time
- [ ] P1-11: No rate limiting - verify unlimited connections possible
- [ ] P2-2: Diarization disabled - verify pyannote code is commented out

**Test Claims:**
- [ ] Run `pytest tests/ -v` and verify 4 tests pass
- [ ] Check test coverage claims (currently low)
- [ ] Verify uv migration (check `uv.lock` exists)

### 1.3 Codebase Familiarization
**Examine these key files:**
- `server/api/ws_live_listener.py` - WebSocket handler & session state
- `server/services/provider_faster_whisper.py` - ASR implementation
- `server/services/asr_stream.py` - ASR pipeline abstraction
- `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` - Client WS logic
- `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` - Audio capture
- `pyproject.toml` - Dependencies & uv config
- `.gitignore` - Exclusion rules

## Step 2: Task Selection (15-30 minutes)

### 2.1 Review Issue Backlog
From the audit's "Issue Log + Execution Backlog" section, select ONE task to work on.

**Selection Criteria:**
- Choose based on your expertise and available time
- Prefer P0/P1 issues over P2 for maximum impact
- Consider issues you can fully test and document
- Avoid issues requiring external dependencies (HF tokens, etc.)

**Recommended First Tasks (easier to verify):**
- P2-9: Standardize log levels (grep for inconsistent logging)
- P2-10: Add structured logging (JSON format)
- P2-13: Add debug hooks for audio dumping
- P1-5: Investigate timestamp drift (add client timestamps)

### 2.2 Task Documentation
**Document your selection:**
```
Selected Task: P[X]-[Y]: [Issue Title]
Rationale: [Why this task - your expertise match, impact, feasibility]
Estimated Time: [X hours]
Success Criteria: [How you'll know it's fixed]
Testing Plan: [How you'll verify the fix]
```

## Step 3: Investigation & Analysis (30-90 minutes)

### 3.1 Deep Dive into the Issue
**For your selected task:**

**Code Analysis:**
- Find all relevant code locations
- Understand current implementation
- Identify root cause
- Document dependencies and side effects

**Impact Assessment:**
- Who/what is affected?
- When does the issue occur?
- What are the failure modes?
- How critical is it?

**Current State Verification:**
- Reproduce the issue if possible
- Check if audit description matches reality
- Identify any missing context

### 3.2 Solution Design
**Design a fix:**
- Minimal viable solution
- Backward compatibility considerations
- Performance impact assessment
- Testing strategy
- Documentation updates needed

**Implementation Plan:**
- Files to modify
- Code changes required
- Configuration changes
- Migration considerations

## Step 4: Implementation (60-180 minutes)

### 4.1 Code Changes
**Implement your fix following these principles:**
- Follow existing code patterns and style
- Add comprehensive error handling
- Include debug logging for new features
- Update comments and docstrings
- Consider edge cases and failure modes

**Quality Standards:**
- Code compiles without errors
- Existing tests still pass
- No breaking changes to public APIs
- Performance impact is acceptable

### 4.2 Configuration Updates
**If needed:**
- Update environment variables
- Modify `pyproject.toml` dependencies
- Update `.gitignore` rules
- Add new configuration options

### 4.3 Documentation Updates
**Update relevant docs:**
- Code comments and docstrings
- README files
- Configuration documentation
- API documentation

## Step 5: Testing & Verification (30-60 minutes)

### 5.1 Unit Testing
**Add or update tests:**
- Unit tests for new functionality
- Integration tests for end-to-end flows
- Regression tests for the fixed issue
- Edge case testing

**Test Execution:**
- Run full test suite: `pytest tests/ -v`
- Verify no regressions
- Check test coverage if possible

### 5.2 Manual Testing
**For your specific fix:**
- Test the happy path
- Test edge cases and error conditions
- Verify performance impact
- Test with real audio if applicable

**Integration Testing:**
- Full end-to-end flow testing
- Client-server integration
- Error handling verification

### 5.3 Verification Checklist
**Confirm:**
- [ ] Issue is resolved
- [ ] No new issues introduced
- [ ] Performance is acceptable
- [ ] Error handling works
- [ ] Logging is appropriate
- [ ] Documentation is updated

## Step 6: Documentation & Reporting (30-45 minutes)

### 6.1 Update Audit Document
**Modify `docs/audit/STREAMING_ASR_AUDIT_2026-02.md`:**

**Mandatory provenance & evidence requirements (add these fields for every audit):**
- **Requested by / Trigger:** who asked for the audit and why (ticket id / PR / meeting). Example: `Requested by: TCK-20260212-011 (Launch Readiness)`.
- **Source documents that motivated the audit:** list exact file paths + section lines (e.g. `docs/flows/MOD-003.md:lines 20-40`).
- **Tests executed (commands + results):** include exact commands run and their stdout/stderr or test IDs (e.g. `pytest tests/test_model_preloader.py -q -> 3 passed`).
- **Evidence citations:** for every claim add an evidence line citing file path + line range, log filename + line, or test name + assertion. Never state "fixed" without an evidence citation.

> Rationale: audits must be reproducible — reviewers must be able to rerun the verification steps and find the same artifacts.

**Update Issue Status:**
- Move your task from "open" to "completed" only after adding provenance & evidence entries.
- Update confidence levels if findings differ
- Add implementation notes (see template below)

**Add Implementation Details (use `docs/audit/AUDIT_RECORD_TEMPLATE.md`):**
```
## Implementation Details

**Files Modified:**
- `path/to/file.py`: [description of changes]

**Code Changes:**
```python
# Before
old_code()

# After
new_code()
```

**Testing:**
- Commands run: `pytest tests/test_foo.py -q` → `3 passed`
- Manual steps: `curl /health` → `200 OK {"model_ready": true}`
- Evidence citations: `server.log:13-16`, `macapp/.../SessionBundle.swift:240-260`

**Configuration:**
- New env var: `NEW_SETTING=value`
- Updated dependencies: [if any]

**Breaking Changes:** [none/minor/major]
```

> Use the dedicated template `docs/audit/AUDIT_RECORD_TEMPLATE.md` (added to the repo) when updating audit documents.

### 6.2 Create Work Log
**Add to `docs/WORKLOG_TICKETS.md`:**

```
## [Date] - [Your Agent Name] - Task P[X]-[Y]: [Issue Title]

### Summary
[Brief description of work completed]

### Request Origin
- Requested by: [user / ticket / PR]
- Source docs: [list of audit/flow docs that led to this task]

### Investigation
[What you found during analysis]

### Implementation
[Technical details of the fix]

### Tests Executed
- Unit: `pytest tests/test_xyz.py -q` → [results]
- Integration: [commands and results]

### Evidence
- `server.log:12-15` — model warmup error
- `tests/test_model_preloader.py::test_warmup` — added assertion

### Impact
[What changed, any side effects]

### Time Spent: [X hours]
```

> If an audit claim cannot be evidenced, mark it as **Still open** and add the exact reason why (missing test, environment precondition, not reproducible locally).

### 6.3 Update Status Documents
**If applicable:**
- Update `docs/STATUS_AND_ROADMAP.md`
- Update `docs/IMPLEMENTATION_PLAN.md`
- Update any relevant feature docs

**Note:** Audits are *evidence-first*. If you cannot provide reproducible evidence for a closure claim, do NOT mark it closed.

## Step 7: Final Review & Submission

### 7.1 Self-Review Checklist
- [ ] All code changes are committed
- [ ] Tests pass: `pytest tests/ -v`
- [ ] Documentation is complete and accurate
- [ ] No sensitive information committed
- [ ] Code follows project conventions
- [ ] Performance impact is acceptable

### 7.2 Submission
**Create a summary report:**

```
## Audit Task Completion Report

**Agent:** [Your Name/ID]
**Task:** P[X]-[Y]: [Issue Title]
**Date:** [Date]
**Time Spent:** [X hours]

### Summary
[What was accomplished]

### Files Changed
- [list of modified files]

### Tests Added/Modified
- [list of test changes]

### Documentation Updated
- [list of docs modified]

### Verification
- [How you tested the fix]
- [Test results]
- [Any issues found]

### Next Steps
[Recommendations for follow-up work]

### Audit Feedback
[Any suggestions for improving the audit document itself]
```

## Guidelines for Success

### Quality Standards
- **Thoroughness**: Don't rush - understand the problem deeply
- **Correctness**: Verify your understanding matches the code
- **Testing**: Every change must be tested
- **Documentation**: Document as you go, not at the end
- **Communication**: Clear commit messages and documentation

### Time Management
- **Investigation**: 20-30% of time
- **Implementation**: 40-50% of time
- **Testing**: 20-30% of time
- **Documentation**: 10-15% of time

### When to Ask for Help
- Stuck on technical implementation details
- Need clarification on audit findings
- Discovered new issues during investigation
- Major architectural changes needed

### Success Metrics
- Issue is fully resolved and tested
- No regressions introduced
- Documentation is complete and accurate
- Code follows project standards
- Other agents can understand and maintain your changes

---

**Remember:** This is a real codebase with real users. Your work directly impacts product quality and user experience. Take pride in your contributions and maintain the high standards established by the existing codebase.</content>
<parameter name="filePath">/Users/pranay/Projects/EchoPanel/docs/audit/AUDIT_AGENT_PROMPT.md