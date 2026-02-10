# Implementation Tickets Roadmap

**Date**: 2026-02-11  
**Status**: Tickets Created → Ready for Prioritization  
**Total Estimated Effort**: 89-128 hours (~3-4 weeks)

---

## Ticket Summary

| Ticket | Title | Priority | Effort | Impact | Status |
|--------|-------|----------|--------|--------|--------|
| TCK-20260211-005 | PR4: Model Preloading + Warmup | P2 | 13-17h | Medium | 🔵 OPEN |
| TCK-20260211-006 | PR5: Concurrency Limiting | P2 | 12-16h | High | 🔵 OPEN |
| TCK-20260211-007 | PR6: WebSocket Reconnect Resilience | P1 | 16-21h | High | 🔵 OPEN |
| TCK-20260211-008 | whisper.cpp Provider | P1 | 13-19h | High | 🔵 OPEN |
| TCK-20260211-009 | Capability Detection | P3 | 8-12h | Medium | 🔵 OPEN |
| TCK-20260211-010 | Adaptive Degrade Ladder | P3 | 15-21h | Medium | 🔵 OPEN |
| TCK-20260211-011 | Voxtral Fix (Streaming) | P4 | 15-22h | High | 🔵 OPEN |

---

## Priority Groups

### Phase 1: Safety & Stability (P1)
**Duration**: 2-3 weeks  
**Effort**: 29-40 hours

1. **TCK-20260211-007**: PR6 WebSocket Reconnect Resilience
   - Prevents infinite retry loops
   - Circuit breaker pattern
   - Message buffering

2. **TCK-20260211-008**: whisper.cpp Provider
   - 3-5× performance improvement on Apple Silicon
   - True streaming transcription
   - Lower memory usage

### Phase 2: Scalability (P2)
**Duration**: 2 weeks  
**Effort**: 25-33 hours

3. **TCK-20260211-006**: PR5 Concurrency Limiting
   - Prevents ASR overload
   - Bounded priority queues
   - Adaptive chunk sizing

4. **TCK-20260211-005**: PR4 Model Preloading
   - Eliminates cold start latency
   - Fixes voxtral architecture

### Phase 3: Polish (P3)
**Duration**: 1-2 weeks  
**Effort**: 23-33 hours

5. **TCK-20260211-010**: Adaptive Degrade Ladder
   - Automatic quality reduction under load
   - Recovery when conditions improve

6. **TCK-20260211-009**: Capability Detection
   - Auto-select optimal provider
   - Eliminates manual configuration

### Phase 4: Experimental (P4)
**Duration**: 2-3 weeks  
**Effort**: 15-22 hours

7. **TCK-20260211-011**: Voxtral Streaming Fix
   - High effort, high risk
   - Depends on voxtral.c stability
   - May be superseded by whisper.cpp

---

## Dependencies Graph

```
TCK-20260211-008 (whisper.cpp)
    └── Can be done independently

TCK-20260211-009 (Capability Detection)
    └── Depends on: TCK-20260211-008 (needs whisper.cpp as option)

TCK-20260211-005 (Model Preloading)
    └── Can be done independently
    └── But benefits from: TCK-20260211-008 (whisper.cpp loads faster)

TCK-20260211-006 (Concurrency Limiting)
    └── Can be done independently

TCK-20260211-007 (Reconnect Resilience)
    └── Can be done independently
    └── Server-side changes don't conflict with others

TCK-20260211-010 (Degrade Ladder)
    └── Depends on: TCK-20260211-006 (concurrency metrics)
    └── Depends on: TCK-20260211-005 (model switching)

TCK-20260211-011 (Voxtral Fix)
    └── Can be done independently
    └── Low priority (whisper.cpp may be better)
```

---

## Recommended Implementation Order

### Minimal Viable (Highest Impact)
1. **TCK-20260211-007** (PR6 Reconnect) - 16-21h
2. **TCK-20260211-008** (whisper.cpp) - 13-19h

**Total**: 29-40 hours (~1 week)  
**Impact**: Fixes stability issues + 3-5× performance gain

### Standard Release (Recommended)
1. **TCK-20260211-007** (PR6 Reconnect) - 16-21h
2. **TCK-20260211-008** (whisper.cpp) - 13-19h
3. **TCK-20260211-006** (PR5 Concurrency) - 12-16h
4. **TCK-20260211-005** (PR4 Preloading) - 13-17h

**Total**: 54-73 hours (~2-3 weeks)  
**Impact**: Full stability + performance + scalability

### Complete Release
Add:
5. **TCK-20260211-010** (Degrade Ladder) - 15-21h
6. **TCK-20260211-009** (Capability Detection) - 8-12h

**Total**: 77-106 hours (~3-4 weeks)

---

## Key Technical Decisions

### 1. whisper.cpp vs Voxtral
**Decision**: Prioritize whisper.cpp (TCK-20260211-008) over Voxtral fix (TCK-20260211-011)

**Rationale**:
- whisper.cpp: Proven stability, active community, Metal support
- Voxtral: Experimental, requires significant rewrite, uncertain gains
- whisper.cpp effort: 13-19h vs Voxtral: 15-22h

### 2. Concurrency Control Pattern
**Decision**: Semaphore + bounded priority queues (not token bucket)

**Rationale**:
- Semaphore: Simple, Pythonic, low overhead
- Priority queues: Natural for mic > system prioritization
- Bounded: Natural backpressure via QueueFull

### 3. Reconnect Strategy
**Decision**: Exponential backoff + jitter + circuit breaker + buffering

**Rationale**:
- All four patterns address different failure modes
- Backoff: Prevents server overload
- Jitter: Prevents thundering herd
- Circuit breaker: Fail fast during outages
- Buffering: Prevents data loss during transient disconnects

---

## Success Metrics

| Metric | Current | Target (Phase 1) | Target (Complete) |
|--------|---------|------------------|-------------------|
| Cold start latency | 2-5s | <500ms | <500ms |
| Real-time factor (M1) | 0.5x | 2.0x | 2.0x |
| Max concurrent sessions | Unlimited (crashes) | 10 (enforced) | 10 (adaptive) |
| Reconnect loops | Infinite | Max 15 | Max 15 |
| Memory usage | 500MB+ | 300MB | 300MB |
| Frame drops | Silent | Zero (explicit) | Zero (explicit) |

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| whisper.cpp Metal issues | Medium | High | Fallback to CPU, test thoroughly |
| Reconnect logic bugs | Medium | High | Extensive testing, gradual rollout |
| Concurrency deadlocks | Low | High | Code review, timeout everywhere |
| Voxtral streaming broken | High | Medium | Deprioritize, focus on whisper.cpp |
| Memory leaks in long sessions | Medium | Medium | Profiling, session limits |

---

## Documentation References

- `docs/RESEARCH_SYNTHESIS_PR4-PR6_AND_ASR.md` - Executive summary
- `docs/ASR_MODEL_PRELOADING_PATTERNS.md` - Model loading research (58KB)
- `docs/ASR_CONCURRENCY_PATTERNS_RESEARCH.md` - Concurrency research (45KB)
- `docs/WEBSOCKET_RECONNECTION_RESILIENCE_RESEARCH.md` - Resilience research (52KB)
- `docs/whisper_cpp_integration_research.md` - whisper.cpp research (38KB)
- `docs/WORKLOG_TICKETS.md` - Detailed tickets (Section TCK-20260211-005 through 011)

---

## Next Steps

1. **Review** this roadmap and ticket priorities
2. **Select** implementation approach (Minimal/Standard/Complete)
3. **Assign** owner to first ticket
4. **Begin** TCK-20260211-007 (PR6 Reconnect) or TCK-20260211-008 (whisper.cpp)

---

*Tickets ready for implementation*
