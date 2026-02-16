# MLX Audio Swift - Quick Start for EchoPanel

**Date:** 2026-02-14  
**Goal:** Test MLX Audio Swift as replacement for Python ASR backend

---

## Step 1: Add Dependency to macOS App

### Option A: Using Xcode

1. Open `macapp/MeetingListenerApp/MeetingListenerApp.xcodeproj`
2. Select project → Package Dependencies
3. Click `+` button
4. Add: `https://github.com/Blaizzy/mlx-audio-swift.git`
5. Select branch: `main`
6. Add products:
   - `MLXAudioSTT`
   - `MLXAudioVAD` (if you want diarization)

### Option B: Using Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeetingListenerApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
    ],
    targets: [
        .target(
            name: "MeetingListenerApp",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioVAD", package: "mlx-audio-swift")
            ]
        )
    ]
)
```

---

## Step 2: Create Native ASR Manager

Create file: `macapp/MeetingListenerApp/Sources/NativeASRManager.swift`

```swift
import Foundation
import MLXAudioSTT
import MLXAudioCore
import Combine

/// Native ASR manager using MLX Audio Swift
@MainActor
class NativeASRManager: ObservableObject {
    // MARK: - Published State
    @Published var isModelLoaded: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var currentTranscription: String = ""
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var asrModel: GLMASRModel?
    private let modelName = "mlx-community/GLM-ASR-Nano-2512-4bit"
    
    // MARK: - Initialization
    
    /// Load the ASR model
    func loadModel() async {
        do {
            print("📥 Loading MLX Audio model: \(modelName)")
            asrModel = try await GLMASRModel.fromPretrained(modelName)
            isModelLoaded = true
            print("✅ Model loaded successfully")
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            print("❌ Error loading model: \(error)")
        }
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio file
    func transcribeAudioFile(url: URL) async {
        guard let model = asrModel else {
            errorMessage = "Model not loaded"
            return
        }
        
        isTranscribing = true
        currentTranscription = ""
        
        do {
            print("🎙️ Loading audio from: \(url.path)")
            let (sampleRate, audioData) = try loadAudioArray(from: url)
            print("🎙️ Audio loaded: \(audioData.count) samples at \(sampleRate)Hz")
            
            print("📝 Starting transcription...")
            let output = model.generate(audio: audioData)
            
            await MainActor.run {
                self.currentTranscription = output.text
                self.isTranscribing = false
            }
            
            print("✅ Transcription complete: \(output.text)")
        } catch {
            await MainActor.run {
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                self.isTranscribing = false
            }
            print("❌ Transcription error: \(error)")
        }
    }
    
    /// Transcribe audio data directly
    func transcribeAudioData(_ data: [Float], sampleRate: Int = 16000) async {
        guard let model = asrModel else {
            errorMessage = "Model not loaded"
            return
        }
        
        isTranscribing = true
        
        do {
            let audioArray = MLXArray(data)
            let output = model.generate(audio: audioArray)
            
            await MainActor.run {
                self.currentTranscription = output.text
                self.isTranscribing = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                self.isTranscribing = false
            }
        }
    }
    
    // MARK: - Streaming (for real-time)
    
    /// Stream transcription from audio chunks
    func streamTranscribe(audioStream: AsyncStream<[Float]>) async {
        guard let model = asrModel else {
            errorMessage = "Model not loaded"
            return
        }
        
        isTranscribing = true
        currentTranscription = ""
        
        do {
            for await audioChunk in audioStream {
                let audioArray = MLXArray(audioChunk)
                
                // Note: Streaming API may vary based on model
                // This is a conceptual example
                for try await event in model.generateStream(audio: audioArray) {
                    switch event {
                    case .token(let token):
                        await MainActor.run {
                            self.currentTranscription += token
                        }
                    case .info(let info):
                        print("Stream info: \(info)")
                    default:
                        break
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Streaming error: \(error.localizedDescription)"
                self.isTranscribing = false
            }
        }
    }
    
    // MARK: - Utility
    
    func clearTranscription() {
        currentTranscription = ""
    }
}
```

---

## Step 3: Create Test View

Create file: `macapp/MeetingListenerApp/Sources/NativeASRTestView.swift`

```swift
import SwiftUI

struct NativeASRTestView: View {
    @StateObject private var asrManager = NativeASRManager()
    @State private var selectedFile: URL?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("MLX Audio Swift Test")
                .font(.largeTitle)
                .padding()
            
            // Model Status
            HStack {
                Circle()
                    .fill(asrManager.isModelLoaded ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(asrManager.isModelLoaded ? "Model Loaded" : "Model Not Loaded")
            }
            
            // Load Model Button
            Button("Load Model") {
                Task {
                    await asrManager.loadModel()
                }
            }
            .disabled(asrManager.isModelLoaded)
            .buttonStyle(.borderedProminent)
            
            Divider()
            
            // File Selection
            Button("Select Audio File") {
                selectAudioFile()
            }
            .buttonStyle(.bordered)
            
            if let file = selectedFile {
                Text("Selected: \(file.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Transcribe Button
            Button("Transcribe") {
                guard let file = selectedFile else { return }
                Task {
                    await asrManager.transcribeAudioFile(url: file)
                }
            }
            .disabled(!asrManager.isModelLoaded || selectedFile == nil || asrManager.isTranscribing)
            .buttonStyle(.borderedProminent)
            
            // Progress
            if asrManager.isTranscribing {
                ProgressView()
                    .padding()
            }
            
            // Results
            VStack(alignment: .leading, spacing: 10) {
                Text("Transcription:")
                    .font(.headline)
                
                ScrollView {
                    Text(asrManager.currentTranscription)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 200)
            }
            .padding()
            
            // Error Display
            if let error = asrManager.errorMessage {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private func selectAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio]
        
        if panel.runModal() == .OK {
            selectedFile = panel.url
        }
    }
}

// Preview
#Preview {
    NativeASRTestView()
}
```

---

## Step 4: Add to App Menu (Temporary)

In `MeetingListenerApp.swift`, add a menu item for testing:

```swift
import SwiftUI

@main
struct MeetingListenerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        #if DEBUG
        // Debug window for MLX Audio testing
        Window("MLX Audio Test", id: "mlx-audio-test") {
            NativeASRTestView()
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        #endif
    }
}
```

---

## Step 5: Test with Sample Audio

1. **Build and run** the macOS app
2. **Open MLX Audio Test window** (Cmd+Shift+M)
3. **Click "Load Model"** (downloads on first run, ~100-500MB)
4. **Select an audio file** (use `test_speech.wav` from project root)
5. **Click "Transcribe"**
6. **Compare results** with Python backend

---

## Step 6: Compare with Python Backend

Create a comparison test:

```swift
import Foundation

class ASRComparisonTest {
    let nativeASR = NativeASRManager()
    let pythonBackend = BackendManager() // existing
    
    func compareTranscription(audioURL: URL) async {
        // Native MLX Audio
        let startNative = Date()
        await nativeASR.transcribeAudioFile(url: audioURL)
        let nativeTime = Date().timeIntervalSince(startNative)
        let nativeResult = nativeASR.currentTranscription
        
        // Python backend
        let startPython = Date()
        let pythonResult = await pythonBackend.transcribe(audioURL)
        let pythonTime = Date().timeIntervalSince(startPython)
        
        // Print comparison
        print("=== ASR Comparison ===")
        print("Audio: \(audioURL.lastPathComponent)")
        print("")
        print("Native MLX Audio:")
        print("  Time: \(String(format: "%.3f", nativeTime))s")
        print("  Result: \(nativeResult)")
        print("")
        print("Python Backend:")
        print("  Time: \(String(format: "%.3f", pythonTime))s")
        print("  Result: \(pythonResult)")
        print("")
        print("Speedup: \(String(format: "%.2f", pythonTime/nativeTime))×")
        print("Match: \(nativeResult == pythonResult ? "✅" : "❌")")
    }
}
```

---

## Expected Results

### Performance Targets

| Metric | Python Backend | MLX Audio Swift | Expected Improvement |
|--------|---------------|-----------------|---------------------|
| Cold start | 2-5s | 1-3s | 2× faster |
| Transcription (4s audio) | 0.5-1s | 0.1-0.3s | 3-5× faster |
| Memory usage | 500MB-1GB | 300-600MB | 30-40% less |
| Latency | 50-100ms | 0ms (local) | Eliminated |

### Quality Expectations

- Transcription accuracy should be **equivalent** or **better**
- Qwen3-ASR may outperform Whisper on multilingual content
- MLX Whisper should match Python Whisper exactly

---

## Next Steps After Testing

### If Successful ✅

1. **Gradual Migration**
   - Add MLX Audio Swift as optional backend
   - A/B test with users
   - Make default for macOS 14+

2. **Remove Python Backend**
   - Simplify deployment
   - Reduce bundle size
   - Improve reliability

3. **Add Advanced Features**
   - Real-time streaming
   - Speaker diarization
   - Voice activity detection

### If Issues Found ❌

1. **Hybrid Approach**
   - Keep Python backend as fallback
   - Use MLX Audio Swift for offline mode
   - User-selectable backend

2. **Report Issues**
   - GitHub issues on mlx-audio-swift
   - Model-specific problems
   - Performance regressions

---

## Resources

- **MLX Audio Swift:** https://github.com/Blaizzy/mlx-audio-swift
- **Example App:** See `Examples/VoicesApp` in the repo
- **Model Hub:** https://huggingface.co/mlx-community

---

## Troubleshooting

### Model Download Fails
```swift
// Check internet connection
// HuggingFace may be rate-limited
// Try downloading manually and loading from local path
```

### Out of Memory
```swift
// Use smaller quantized models
// 4-bit or 8-bit quantization
// e.g., "mlx-community/Qwen3-ASR-0.6B-8bit" instead of fp16
```

### Slow First Run
```swift
// First model load compiles Metal kernels
// Subsequent runs are much faster
// Expected: 10-30s first run, <1s after
```

### macOS Version Issues
```swift
// Requires macOS 14.0+
// Check at runtime:
if #available(macOS 14.0, *) {
    // Use MLX Audio Swift
} else {
    // Fallback to Python backend
}
```
