# EchoPanel Memory Profiling & Optimization Guide

**Date:** February 17, 2026
**Purpose:** Identify and fix memory issues for production readiness
**Priority:** 🚨 **HIGH** - Memory leaks will crash user Macs

---

## 🎯 **MEMORY PROFILING SETUP**

### **Tools Required**
- **Xcode Instruments** (built into Xcode)
- **Swift Heap Allocations** instrument
- **Leaks** instrument
- **Time Profiler** (for CPU + memory correlation)

### **Getting Started**
```bash
# 1. Build for profiling
cd macapp/MeetingListenerApp
swift build -c release

# 2. Open Instruments
open -a "Instruments" # Build for profiling

# 3. Choose "Leaks" template
# 4. Select your app target
# 5. Start recording and reproduce scenarios
```

---

## 🚨 **CRITICAL MEMORY SCENARIOS TO TEST**

### **1. Long Recording Sessions (2+ hours)**
**Scenario:** Continuous recording for 2 hours
**Expected:** Memory usage should stabilize
**Warning Signs:**
- Continuous memory growth
- Memory usage >1GB for simple meeting
- Spikes during transcript updates

**Profile:**
- Start Instruments with Leaks template
- Begin 2-hour recording
- Take memory snapshot every 15 minutes
- Look for continuous growth

### **2. Large Transcript Handling (1000+ segments)**
**Scenario:** Very long meeting with many segments
**Expected:** Handle 10,000+ segments without slowdown
**Warning Signs:**
- UI freezes when scrolling
- Memory grows with segment count
- Crashes when searching large transcripts

**Profile:**
- Mock 10,000 transcript segments
- Test scrolling, searching, filtering
- Monitor memory during UI operations

### **3. OCR Frame Buffer Management**
**Scenario:** Screen sharing with frequent changes
**Expected:** OCR frame buffer stays bounded
**Warning Signs:**
- Continuous memory growth during screen sharing
- Large memory allocations every 30s
- Memory not freed after recording stops

**Profile:**
- Start screen sharing during recording
- Monitor OCR-related allocations
- Check buffer cleanup on recording stop

### **4. Vector Store Growth**
**Scenario:** Multiple recordings with RAG enabled
**Expected:** Vector store has max size with LRU eviction
**Warning Signs:**
- Unbounded vector store growth
- No LRU eviction happening
- Memory grows with each recording

**Profile:**
- Record 10+ sessions with embeddings
- Monitor vector store size
- Verify LRU eviction is working

### **5. Backend Switching Stress**
**Scenario:** Rapid switching between backends
**Expected:** Clean up old backend resources
**Warning Signs:**
- Memory not freed when switching backends
- Multiple backend instances loaded
- Memory grows with each switch

**Profile:**
- Switch backends 20 times rapidly
- Monitor memory after each switch
- Check for cleanup

---

## 🔍 **SPECIFIC MEMORY HOTSPOTS TO CHECK**

### **High Priority**

#### **1. Transcript Segment Storage**
**Location:** `AppState.swift` transcriptSegments array
**Issue:** Array can grow unbounded
**Fix:** Implement archival system for old segments
**Profile Check:**
- Monitor Array allocations
- Check for retained old segments
- Verify deletion actually frees memory

#### **2. OCR Frame Buffer**
**Location:** `OCRFrameCapture.swift` frame buffer
**Issue:** Can accumulate many frames
**Fix:** Limit buffer size, aggressive cleanup
**Profile Check:**
- Look for retained image data
- Check frame deallocation
- Verify cleanup on recording stop

#### **3. Embedding Cache**
**Location:** `server/services/embeddings.py` cache
**Issue:** Unbounded dict growth
**Fix:** Implement LRU eviction (already in roadmap)
**Profile Check:**
- Monitor cache size over time
- Check for unbounded growth
- Verify eviction is triggered

#### **4. Audio Sample Buffers**
**Location:** `AudioCaptureManager.swift` audio buffers
**Issue:** Circular buffers may not free properly
**Fix:** Ensure proper buffer lifecycle
**Profile Check:**
- Look for retained audio data
- Check buffer reuse vs allocation
- Verify cleanup on recording stop

### **Medium Priority**

#### **5. WebSocket Connections**
**Location:** `WebSocketStreamer.swift` connection state
**Issue:** May retain old connection data
**Fix:** Ensure proper connection cleanup
**Profile Check:**
- Monitor connection-related allocations
- Check for retained message buffers
- Verify cleanup on disconnect

#### **6. Session Bundle Data**
**Location:** `SessionBundle.swift` temporary storage
**Issue:** May retain data during export
**Fix:** Ensure timely cleanup after export
**Profile Check:**
- Monitor bundle allocations
- Check for retained data after export
- Verify cleanup

---

## 🛠️ **MEMORY OPTIMIZATION STRATEGIES**

### **1. Implement Object Pooling**
**For:** Frequently allocated objects (segments, frames)
**Strategy:** Reuse objects instead of allocating new ones
```swift
class SegmentPool {
    private var pool: [TranscriptSegment] = []
    func obtain() -> TranscriptSegment {
        return pool.popLast() ?? TranscriptSegment()
    }
    func recycle(_ segment: TranscriptSegment) {
        pool.append(segment)
    }
}
```

### **2. Lazy Loading for Large Data**
**For:** Historical transcripts, large exports
**Strategy:** Load data on-demand instead of all at once
```swift
// Bad: Load all historical sessions
let allSessions = sessionStore.loadAllSessions() // May use lots of memory

// Good: Load on-demand
lazy var allSessions = sessionStore.loadAllSessions()
```

### **3. Automatic Memory Pressure Handling**
**For:** Responding to system memory warnings
**Strategy:** Release non-critical data under pressure
```swift
// In AppState or main app
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.releaseNonCriticalData()
}
```

### **4. Periodic Memory Cleanup**
**For:** Long-running sessions
**Strategy:** Explicit cleanup timers
```swift
// Every 5 minutes during recording
Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
    autoreleasepool {
        // Cleanup temporary objects
    }
}
```

---

## 📊 **MEMORY TARGETS**

### **Acceptable Limits**
- **Idle (not recording):** <100 MB
- **Recording (typical):** 200-400 MB
- **Recording (large meeting):** <800 MB
- **Memory growth rate:** <10 MB per hour during recording

### **Unacceptable (Fix Required)**
- **Idle:** >200 MB
- **Recording:** >1 GB
- **Growth rate:** >50 MB per hour
- **Spikes:** >200 MB sudden increases

---

## 🧪 **TESTING PROCEDURES**

### **Automated Memory Tests**
Create a test suite that:
1. Records 1-hour session
2. Takes memory snapshots every 10 minutes
3. Verifies no continuous growth
4. Checks for leaks

### **Manual Memory Tests**
1. **Daily Use Simulation:**
   - 10 recordings of varying lengths
   - Multiple backend switches
   - Export operations
   - Settings changes

2. **Stress Test:**
   - 4-hour continuous recording
   - Rapid start/stop cycles
   - All backends tested
   - Large transcript operations

3. **Memory Warning Test:**
   - Simulate memory pressure
   - Verify graceful degradation
   - Check data integrity

---

## 🚨 **IMMEDIATE ACTION ITEMS**

### **Today:**
1. **Set up Instruments** - Choose Leaks template
2. **Profile 30-minute recording** - Establish baseline
3. **Check for obvious leaks** - Low-hanging fruit

### **Tomorrow:**
1. **2-hour recording test** - Find long-term issues
2. **Large transcript test** - Mock 10,000 segments
3. **OCR stress test** - Screen sharing for 1 hour

### **This Week:**
1. **Fix identified leaks** - Address issues found
2. **Implement LRU cache** - Vector store bounds
3. **Memory pressure handling** - System warnings

---

## 📈 **SUCCESS CRITERIA**

### **Memory Stability:**
- [ ] 2-hour recording uses <500 MB total
- [ ] Memory usage stabilizes after initial growth
- [ ] No leaks detected by Instruments
- [ ] Handles 10,000+ segments without slowdown

### **Production Ready:**
- [ ] All automated memory tests pass
- [ ] Manual stress tests completed
- [ ] Memory pressure handling implemented
- [ ] Target limits met across all scenarios

---

**Bottom Line:** Memory issues are the most common cause of crashes in Mac apps. A few hours of profiling now will prevent countless user crashes and bad reviews later.

**Let's start with a 30-minute recording profile today to establish our baseline.**