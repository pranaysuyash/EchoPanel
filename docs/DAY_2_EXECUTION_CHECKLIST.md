# 🧪 Day 2 Manual Testing Execution Checklist

**Date:** February 17, 2026
**Time Required:** 2-3 hours
**Purpose:** Validate production readiness under real-world conditions

---

## 🎯 **TESTING EXECUTION PLAN**

### **Setup (5 minutes)**
1. **Restart Mac** (clean memory state)
2. **Open Activity Monitor** → Memory and CPU tabs
3. **Open EchoPanel** app
4. **Open this checklist** for recording results

---

## 📊 **TEST 1: Memory Baseline (30 minutes)**

### **Start Recording**
- [ ] **Note baseline memory:** ______ MB
- [ ] **Start recording** with test audio (YouTube video, etc.)
- [ ] **Wait 30 minutes**

### **Memory Measurements** (Every 5 minutes)
- [ ] **5 min:** ______ MB | CPU: _____ %
- [ ] **10 min:** ______ MB | CPU: _____ %
- [ ] **15 min:** ______ MB | CPU: _____ %
- [ ] **20 min:** ______ MB | CPU: _____ %
- [ ] **25 min:** ______ MB | CPU: _____ %
- [ ] **30 min:** ______ MB | CPU: _____ %

### **Analysis**
- [ ] **Memory Growth:** ______ MB total
- [ ] **Trend:** Stable/Growing/Volatile
- [ ] **Pass/Fail:** ______

---

## 🔄 **TEST 2: Lifecycle Stress (15 minutes)**

### **Rapid Start/Stop Cycles**
- [ ] **Perform 20 cycles:** Start → Wait 10s → Stop
- [ ] **Observe:** Any crashes?
- [ ] **Observe:** UI freezes?
- [ ] **Check:** Transcript data integrity?

### **Results**
- [ ] **Crashes:** 0/20 cycles
- [ ] **UI Freezes:** None/Multiple
- [ ] **Data Corruption:** Yes/No
- [ ] **Pass/Fail:** ______

---

## 📱 **TEST 3: Core Scenarios (30 minutes)**

### **Scenario A: Active Call Recording**
- [ ] **Start Zoom/Teams call**
- [ ] **Start EchoPanel recording**
- [ ] **Talk for 5 minutes**
- [ ] **Stop recording**
- [ ] **Check:** Transcript captured correctly?
- [ ] **Pass/Fail:** ______

### **Scenario B: No Audio Input**
- [ ] **Disconnect all audio**
- [ ] **Start EchoPanel recording**
- [ ] **Wait 2 minutes**
- [ ] **Stop recording**
- [ ] **Check:** Graceful silence handling?
- [ ] **Pass/Fail:** ______

### **Scenario C: Backend Switch**
- [ ] **Start with Native MLX**
- [ ] **Switch to Cloud** (if available)
- [ ] **Switch back to Native MLX**
- [ ] **Stop recording**
- [ ] **Check:** Continuous transcript?
- [ ] **Pass/Fail:** ______

---

## 🔥 **TEST 4: Backend Failures (20 minutes)**

### **Scenario A: Network Disconnect**
- [ ] **Start recording with Cloud backend**
- [ ] **Wait 1 minute**
- [ ] **Disable WiFi**
- [ ] **Continue 2 minutes**
- [ ] **Re-enable WiFi**
- [ ] **Stop recording**
- [ ] **Check:** Graceful recovery?
- [ ] **Pass/Fail:** ______

### **Scenario B: Backend Process Death**
- [ ] **Start recording**
- [ ] **Find backend PID:** `ps aux | grep python`
- [ ] **Kill backend process**
- [ ] **Try to continue recording**
- [ ] **Stop recording**
- [ ] **Check:** Proper error handling?
- [ ] **Pass/Fail:** ______

---

## 💾 **TEST 5: Transcript Archival (20 minutes)**

### **Large Transcript Test**
- [ ] **Start recording** (or use mock data)
- [ ] **Add 6,000+ segments** (if testing manually, let recording run long)
- [ ] **Monitor memory:** Final usage ______ MB
- [ ] **Check segment count:** ______ active segments
- [ ] **Verify:** Count ≈ 5,000 (archival working)?
- [ ] **Pass/Fail:** ______

---

## 🔧 **TEST 6: OCR Throttling (15 minutes)**

### **Resource Pressure Test**
- [ ] **Start recording with OCR**
- [ ] **Start screen sharing** (frequent content changes)
- [ ] **Monitor CPU usage:** ______ %
- [ ] **Monitor memory usage:** ______ MB
- [ ] **Let run 10 minutes**
- [ ] **Observe:** OCR intervals adapting?
- [ ] **Pass/Fail:** ______

---

## 🚨 **TEST 7: Error Recovery (20 minutes)**

### **Scenario A: Export During Recording**
- [ ] **Start recording**
- [ ] **Wait 2 minutes**
- [ ] **Export transcript**
- [ ] **Continue 2 more minutes**
- [ ] **Stop recording**
- [ ] **Check:** Both succeeded?
- [ ] **Pass/Fail:** ______

### **Scenario B: Settings During Recording**
- [ ] **Start recording**
- [ ] **Change VAD threshold**
- [ ] **Switch audio source**
- [ ] **Stop recording**
- [ ] **Check:** Settings applied safely?
- [ ] **Pass/Fail:** ______

---

## 🎯 **TEST 8: Real-World Simulation (1 hour)**

### **Extended Recording**
- [ ] **Start recording** (simulated meeting)
- [ ] **During recording:**
  - [ ] Switch between tabs/views
  - [ ] Export transcripts (2-3 times)
  - [ ] Change settings
  - [ ] Monitor memory usage
- [ ] **Stop recording**
- [ ] **Check:** App stable throughout?
- [ ] **Check:** Performance acceptable?
- [ ] **Check:** Transcript quality good?
- [ ] **Pass/Fail:** ______

---

## 📋 **ISSUE TRACKING**

### **Problems Found:**

| # | Issue | Severity | Memory Impact | Reproducible? | Status |
|---|-------|----------|---------------|---------------|---------|
| 1 | ______ | High/Med/Low | Yes/No | Yes/No | Fixed/Open |
| 2 | ______ | High/Med/Low | Yes/No | Yes/No | Fixed/Open |
| 3 | ______ | High/Med/Low | Yes/No | Yes/No | Fixed/Open |

---

## ✅ **OVERALL ASSESSMENT**

### **Test Results Summary:**
- [ ] **Test 1 (Memory):** PASS/FAIL - Notes: ______
- [ ] **Test 2 (Lifecycle):** PASS/FAIL - Notes: ______
- [ ] **Test 3 (Core Features):** PASS/FAIL - Notes: ______
- [ ] **Test 4 (Backend Failures):** PASS/FAIL - Notes: ______
- [ ] **Test 5 (Archival):** PASS/FAIL - Notes: ______
- [ ] **Test 6 (OCR):** PASS/FAIL - Notes: ______
- [ ] **Test 7 (Error Recovery):** PASS/FAIL - Notes: ______
- [ ] **Test 8 (Real-World):** PASS/FAIL - Notes: ______

### **Ready for Next Phase:**
- [ ] **All tests PASS** → Ready for Week 2
- [ ] **Some tests FAIL** → Fix and retest
- [ ] **Many tests FAIL** → Major issues need addressing

### **Critical Issues (Must Fix):**
1. ______
2. ______
3. ______

---

## 🎯 **NEXT STEPS**

### **If Tests Pass:**
1. **Proceed to Week 2** (Performance & Polish)
2. **Begin App Store materials** preparation
3. **Start beta testing** with external users

### **If Tests Fail:**
1. **Address critical issues** immediately
2. **Rerun failed tests** after fixes
3. **Document all fixes** applied
4. **Reassess readiness** after fixes

---

## 📊 **PERFORMANCE METRICS**

### **Memory Usage:**
- **Starting:** ______ MB
- **Peak:** ______ MB
- **Ending:** ______ MB
- **Growth:** ______ MB (30 min recording)

### **CPU Usage:**
- **Idle:** ______ %
- **Recording:** ______ %
- **Peak:** ______ %

### **App Responsiveness:**
- **UI Freezes:** None/Minor/Major
- **Lag During Recording:** None/Minor/Major
- **Export Performance:** Good/Fair/Poor

---

**Testing Time:** ______ hours
**Tester:** ______
**Date:** ______

**Overall Assessment:** PRODUCTION READY / NEEDS WORK / NOT READY

---

**This comprehensive testing will validate that EchoPanel is ready for real-world usage and catch any issues before users encounter them.**