# ASR Module

Hybrid ASR backend supporting both Native MLX (local) and Python Cloud transcription.

## Files

| File | Purpose |
|------|---------|
| `ASRTypes.swift` | Types, enums, errors |
| `ASRBackendProtocol.swift` | Protocol definition |
| `HybridASRManager.swift` | Smart selection manager |
| `NativeMLXBackend.swift` | MLX Audio Swift integration |
| `PythonBackend.swift` | WebSocket wrapper |
| `BackendSelectionView.swift` | Settings UI |
| `FeatureFlagManager.swift` | Rollout control |
| `ASRIntegration.swift` | App integration helpers |
| `BackendComparisonTestView.swift` | A/B testing |

## Dev Mode

All features are enabled by default in dev mode (`isDevMode = true`). No payment blockers.

## Usage

```swift
let asrManager = ASRContainer.shared.hybridASRManager
await asrManager.initialize()

// Transcribe
let result = try await asrManager.transcribe(audio: data, config: config)
```
