# ASR Backend Testing Guide

## Quick Start

### 1. Build the App
```bash
cd macapp/MeetingListenerApp
swift build
```

### 2. Start the Python Server (for Cloud Backend)
```bash
cd /Users/pranay/Projects/EchoPanel
python -m server.main
```

### 3. Run the App
```bash
swift run
```

## Testing Features

### Dev Mode (All Features Unlocked)
By default, `isDevMode = true` in `FeatureFlagManager`, which:
- Bypasses all subscription checks
- Enables all backend modes (Auto, Native, Cloud, Dual)
- Enables Dual Mode for A/B testing
- Enables verbose logging

### Accessing ASR Settings

**Option 1: Settings Tab**
- Open EchoPanel → Settings → "ASR Backend" tab
- Select backend mode, view status, initialize backends

**Option 2: Menu Bar**
- Click EchoPanel icon in menu bar → ASR Backend → A/B Testing

**Option 3: Dedicated Windows**
- ASR Backend Status: Quick view of backend health
- A/B Testing: Full comparison tool

## Test Scenarios

### Test 1: Native MLX Backend
1. Go to Settings → ASR Backend
2. Select "Native (Local)" mode
3. Click "Initialize Backends"
4. Wait for model download (first time only, ~300MB for Qwen3-ASR-0.6B)
5. Status should show "Ready"

### Test 2: Python Cloud Backend
1. Ensure Python server is running
2. Select "Cloud (Python)" mode
3. Click "Initialize Backends"
4. Status should show "Ready" if server is accessible

### Test 3: Auto-Select Mode
1. Select "Auto-Select" mode
2. System will automatically choose based on:
   - Network availability
   - Privacy requirements
   - Feature needs (diarization → Cloud)

### Test 4: Dual Mode A/B Testing
1. Enable Developer Options → "Enable Dual Mode"
2. Open "A/B Testing" window
3. Select an audio file (.wav, .mp3, .aiff)
4. Click "Run Comparison"
5. View results:
   - RTF (Real-Time Factor) comparison
   - Word Error Rate (WER) between backends
   - Speedup ratio
   - Transcription text comparison

### Test 5: Feature Flags (Gradual Rollout Testing)
1. In Developer Options:
   - Adjust "Rollout" slider (0-100%)
   - Select "Forced Mode" to override auto-selection
   - Toggle verbose logging
2. Test different configurations

## Expected Performance

| Backend | RTF | Memory | GPU | Offline |
|---------|-----|--------|-----|---------|
| Native MLX | 0.08x | ~4GB | Metal | Yes |
| Python Server | 0.15x | Server-side | N/A | No |

*RTF = Real-Time Factor (lower is faster). 0.08x means 12.5x real-time speed*

## Troubleshooting

### Native MLX Not Available
```
Solution: Check mlx-audio-swift dependency in Package.swift
```

### Python Server Not Connecting
```
1. Verify server is running: curl http://localhost:8000/health
2. Check firewall settings
3. Verify WebSocket endpoint: ws://localhost:8000/ws/transcribe
```

### Model Download Fails
```
1. Check internet connection
2. Verify HuggingFace access
3. Check disk space (~300MB for 0.6B model, ~2GB for 2B model)
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+L | Start/Stop Listening |
| Cmd+Shift+D | Open Diagnostics |
| Cmd+? | Keyboard Shortcuts |

## Debug Features

### Reset to Defaults
```swift
FeatureFlagManager.shared.resetToDefaults()
```

### Enable All Features
```swift
FeatureFlagManager.shared.enableAllForDev()
```

### Check Backend Health
```swift
let manager = ASRContainer.shared.hybridASRManager
let status = await manager.nativeBackend.health()
print(status)
```

## Next Steps

After testing:
1. Set `isDevMode = false` for production testing
2. Configure subscription tiers
3. Set rollout percentage for gradual release
4. Monitor metrics in A/B testing
