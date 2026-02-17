# EchoPanel Manual Testing Guide

**Date:** February 17, 2026
**Purpose:** Manual testing procedures for production readiness validation
**Status:** Ready for execution

---

## 🧪 **DAY 2 TESTING SCENARIOS**

### **Test Environment Setup**
1. **Build the app:** `swift build`
2. **Open Activity Monitor** (to monitor resources)
3. **Have a test audio source ready** (YouTube video, Zoom meeting, etc.)
4. **Set aside 2-3 hours** for comprehensive testing

---

## 📊 **TEST 1: Memory Profiling Baseline (30 minutes)**

### **Objective**
Establish memory usage baseline for a typical recording session

### **Procedure**
1. **Restart Mac** to start with clean memory state
2. **Open Activity Monitor** → Memory tab
3. **Launch EchoPanel** (don't start recording yet)
4. **Note baseline memory:** ______ MB
5. **Start 30-minute recording** with test audio
6. **Every 5 minutes record memory:**
   - 5 min: ______ MB
   - 10 min: ______ MB
   - 15 min: ______ MB
   - 20 min: ______ MB
   - 25 min: ______ MB
   - 30 min: ______ MB

### **Success Criteria**
- Memory growth <100 MB over 30 minutes
- No memory spikes >200 MB
- Memory stabilizes (not continuous growth)

### **Issues to Look For**
- Continuous memory growth (memory leak)
- Large memory spikes during transcript updates
- Memory not freed after recording stops

---

## 🔄 **TEST 2: Recording Lifecycle Stress (15 minutes)**

### **Objective**
Validate rapid start/stop cycles don't crash the app

### **Procedure**
1. **Start recording** → wait 10 seconds → **Stop recording**
2. **Repeat 20 times** as fast as possible
3. **Observe:**
   - Does the app crash?
   - Any error messages?
   - UI freezes?
   - Data corruption in transcripts?

### **Success Criteria**
- Zero crashes across 20 cycles
- No data corruption
- UI remains responsive

### **Issues to Look For**
- Crashes on start/stop
- Transcript data corruption
- Memory growing with each cycle
- UI not updating properly

---

## 📱 **TEST 3: Core Feature Scenarios (30 minutes)**

### **Scenario A: Recording During Active Call**
1. **Start a Zoom/Teams call** with test audio
2. **Start EchoPanel recording**
3. **Talk for 5 minutes**
4. **Stop recording**
5. **Check:** Transcript captured correctly?

### **Scenario B: No Audio Input**
1. **Disconnect all audio sources**
2. **Start EchoPanel recording**
3. **Wait 2 minutes** (should detect silence)
4. **Stop recording**
5. **Check:** App handles silence gracefully?

### **Scenario C: Backend Switch**
1. **Start recording with Native MLX**
2. **Switch to Cloud backend** (if available)
3. **Switch back to Native MLX**
4. **Stop recording**
5. **Check:** Transcript continuous across switches?

### **Success Criteria**
- All scenarios complete without crashes
- Proper error messages when appropriate
- Data integrity maintained

---

## 🔥 **TEST 4: Backend Failure Scenarios (20 minutes)**

### **Scenario A: Network Disconnect During Recording**
1. **Start recording with Cloud backend**
2. **Wait 1 minute**
3. **Disconnect WiFi** (disable network)
4. **Continue recording for 2 minutes**
5. **Reconnect WiFi**
6. **Stop recording**
7. **Check:** Does it recover gracefully?

### **Scenario B: Backend Process Death**
1. **Start recording**
2. **Kill backend process** (find PID and kill)
3. **Try to continue recording**
4. **Stop recording**
5. **Check:** Proper error handling?

### **Success Criteria**
- Graceful degradation (not hard crashes)
- Clear error messages to user
- Option to recover or restart

---

## 💾 **TEST 5: Transcript Archival System (20 minutes)**

### **Objective**
Validate that transcript archival prevents unbounded memory growth

### **Procedure**
1. **Start recording**
2. **Let it run for 1 hour** (or simulate with mock data)
3. **Monitor memory usage** in Activity Monitor
4. **Check transcript count** in the app
5. **Verify:** Segments are being archived?

### **Quick Test (Mock Data)**
1. **Use the transcript stress test** in Swift tests
2. **Add 6,000+ segments** rapidly
3. **Verify:** Only ~5,000 segments in active memory?
4. **Check memory:** Does it remain bounded?

### **Success Criteria**
- Memory growth stops after archival threshold
- Active segment count stays near 5,000
- No crashes with large transcripts

---

## 🔧 **TEST 6: OCR Resource Throttling (15 minutes)**

### **Objective**
Validate OCR throttling under resource pressure

### **Procedure**
1. **Start recording with OCR enabled**
2. **Start screen sharing** (show content with frequent changes)
3. **Monitor Activity Monitor:**
   - CPU usage
   - Memory usage
4. **Let it run for 10 minutes**
5. **Observe:** OCR captures happening?

### **Manual Pressure Test**
1. **Open several heavy apps** (Chrome with many tabs, etc.)
2. **Start EchoPanel with OCR**
3. **Check:** Does OCR throttle appropriately?

### **Success Criteria**
- OCR interval increases under pressure
- No CPU overload (>80% continuous)
- App remains responsive

---

## 🚨 **TEST 7: Error Recovery (20 minutes)**

### **Scenario A: Export During Recording**
1. **Start recording**
2. **After 2 minutes, try to export**
3. **Continue recording for 2 more minutes**
4. **Stop recording**
5. **Check:** Both operations succeeded?

### **Scenario B: Settings Changes During Recording**
1. **Start recording**
2. **Change VAD threshold** during recording
3. **Switch audio source** during recording
4. **Stop recording**
5. **Check:** Settings applied safely?

### **Success Criteria**
- No crashes during concurrent operations
- Settings changes apply appropriately
- Data integrity maintained

---

## 🎯 **TEST 8: Real-World Usage Simulation (1 hour)**

### **Objective**
Simulate typical user workflow for extended period

### **Procedure**
1. **Start recording** (simulated meeting)
2. **Let it run for 30 minutes**
3. **During recording:**
   - Switch between tabs/views
   - Export transcripts
   - Change settings
   - Check memory usage
4. **Stop recording**
5. **Review transcript quality**

### **Success Criteria**
- App remains stable throughout
- Acceptable performance
- No memory leaks
- Transcript quality good

---

## 📋 **ISSUE TRACKING**

### **Record Any Issues Found:**

| Issue | Severity | Memory Impact | Reproducible? |
|-------|----------|---------------|---------------|
| ______ | High/Med/Low | Yes/No | Yes/No |
| ______ | High/Med/Low | Yes/No | Yes/No |
| ______ | High/Med/Low | Yes/No | Yes/No |

### **Priority Fixes:**
1. **Any crashes** → Critical → Fix immediately
2. **Memory leaks** → High → Fix before launch
3. **UI freezes** → Medium → Polish before launch
4. **Minor glitches** → Low → Can defer

---

## ✅ **SIGN-OFF CRITERIA**

### **Ready for Next Phase If:**
- [ ] Zero crashes during all tests
- [ ] Memory usage stable and bounded
- [ ] All core scenarios work reliably
- [ ] Error handling graceful and clear
- [ ] Performance acceptable throughout

### **Need More Work If:**
- Any crashes or data corruption
- Unbounded memory growth
- Poor performance under normal load
- Confusing error messages
- UI becomes unresponsive

---

## 📝 **TEST RESULTS SUMMARY**

**Date:** ______
**Tester:** ______
**Mac Model:** ______
**macOS Version:** ______
**Available RAM:** ______ GB

### **Test Results:**
- Test 1 (Memory): PASS/FAIL - Notes: ______
- Test 2 (Lifecycle): PASS/FAIL - Notes: ______
- Test 3 (Core Features): PASS/FAIL - Notes: ______
- Test 4 (Backend Failures): PASS/FAIL - Notes: ______
- Test 5 (Archival): PASS/FAIL - Notes: ______
- Test 6 (OCR): PASS/FAIL - Notes: ______
- Test 7 (Error Recovery): PASS/FAIL - Notes: ______
- Test 8 (Real-World): PASS/FAIL - Notes: ______

### **Overall Assessment:**
READY FOR NEXT PHASE: YES/NO

**If NO, what must be fixed first?**
______
______
______

---

**This manual testing approach will catch issues that automated tests miss, especially around resource usage and real-world usage patterns.**