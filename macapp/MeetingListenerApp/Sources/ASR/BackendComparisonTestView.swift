import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backend Comparison Test View

/// A/B testing view for comparing native vs cloud transcription
public struct BackendComparisonTestView: View {
    @StateObject private var asrManager = ASRContainer.shared.hybridASRManager
    @StateObject private var featureFlags = FeatureFlagManager.shared
    
    @State private var selectedAudioURL: URL?
    @State private var isRunningTest = false
    @State private var testResults: [TestRun] = []
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            
            Divider()
            
            testControlsSection
            
            if isRunningTest {
                progressSection
            }
            
            if !testResults.isEmpty {
                Divider()
                resultsSection
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio, .wav, .mp3, .aiff],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flask.fill")
                    .foregroundStyle(.orange)
                Text("Backend A/B Testing")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("Compare Native MLX and Python Cloud transcription quality and performance on the same audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            #if DEBUG
            if featureFlags.isDevMode {
                Label("Dev Mode Active - All features enabled", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            #endif
        }
    }
    
    private var testControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Configuration")
                .font(.headline)
            
            HStack {
                // File selection
                VStack(alignment: .leading) {
                    Text("Audio File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(selectedAudioURL?.lastPathComponent ?? "No file selected")
                            .foregroundStyle(selectedAudioURL == nil ? .secondary : .primary)
                        
                        Spacer()
                        
                        Button("Select File...") {
                            showingFilePicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Language selection
            HStack {
                Text("Language:")
                Picker("", selection: .constant(Language.english)) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .frame(width: 150)
            }
            
            // Run button
            HStack {
                Spacer()
                
                Button("Clear Results") {
                    testResults.removeAll()
                }
                .buttonStyle(.bordered)
                .disabled(testResults.isEmpty || isRunningTest)
                
                Button("Run Comparison") {
                    Task {
                        await runComparison()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAudioURL == nil || isRunningTest)
            }
        }
    }
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Running Test...")
                .font(.headline)
            
            HStack {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Transcribing with both backends...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Results")
                .font(.headline)
            
            ForEach(testResults) { result in
                TestResultCard(run: result)
            }
            
            // Summary statistics
            if testResults.count > 1 {
                Divider()
                SummaryStatsView(results: testResults)
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedAudioURL = url
            }
        case .failure(let error):
            errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func runComparison() async {
        guard let audioURL = selectedAudioURL else { return }
        
        isRunningTest = true
        errorMessage = nil
        
        do {
            // Load audio data
            let audioData = try Data(contentsOf: audioURL)
            
            let config = TranscriptionConfig(
                language: .english,
                enableDiarization: false,
                enablePunctuation: true
            )
            
            // Run comparison
            let startTime = Date()
            let comparison = try await asrManager.compareBackends(audio: audioData, config: config)
            let totalTime = Date().timeIntervalSince(startTime)
            
            // Create test run record
            let testRun = TestRun(
                timestamp: Date(),
                audioFile: audioURL.lastPathComponent,
                nativeResult: comparison.nativeResult,
                pythonResult: comparison.pythonResult,
                nativeRTF: comparison.nativeMetrics.realtimeFactor,
                pythonRTF: comparison.pythonMetrics.realtimeFactor,
                speedup: comparison.speedup,
                wer: comparison.wordErrorRate,
                totalTime: totalTime
            )
            
            await MainActor.run {
                testResults.insert(testRun, at: 0)
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Test failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isRunningTest = false
        }
    }
}

// MARK: - Test Run Model

struct TestRun: Identifiable {
    let id = UUID()
    let timestamp: Date
    let audioFile: String
    let nativeResult: TranscriptionResult
    let pythonResult: TranscriptionResult
    let nativeRTF: Double
    let pythonRTF: Double
    let speedup: Double
    let wer: Double
    let totalTime: TimeInterval
}

// MARK: - Test Result Card

struct TestResultCard: View {
    let run: TestRun
    @State private var showingNativeText = false
    @State private var showingPythonText = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(run.audioFile)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(run.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Winner badge
                if run.speedup > 1.5 {
                    Label("Native \(String(format: "%.1f", run.speedup))× Faster", systemImage: "bolt.fill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .cornerRadius(4)
                } else if run.speedup < 0.67 {
                    Label("Cloud \(String(format: "%.1f", 1/run.speedup))× Faster", systemImage: "cloud.fill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .foregroundStyle(.purple)
                        .cornerRadius(4)
                }
            }
            
            // Metrics
            HStack(spacing: 16) {
                MetricBadge(
                    label: "Native RTF",
                    value: String(format: "%.2f×", run.nativeRTF),
                    color: .green
                )
                
                MetricBadge(
                    label: "Cloud RTF",
                    value: String(format: "%.2f×", run.pythonRTF),
                    color: .purple
                )
                
                MetricBadge(
                    label: "Speedup",
                    value: String(format: "%.2f×", run.speedup),
                    color: run.speedup > 1 ? .green : .orange
                )
                
                MetricBadge(
                    label: "WER",
                    value: String(format: "%.1f%%", run.wer * 100),
                    color: run.wer < 0.1 ? .green : .orange
                )
            }
            
            // Transcription previews
            HStack(spacing: 12) {
                TranscriptionPreview(
                    title: "Native",
                    text: run.nativeResult.fullText,
                    isExpanded: $showingNativeText
                )
                
                TranscriptionPreview(
                    title: "Cloud",
                    text: run.pythonResult.fullText,
                    isExpanded: $showingPythonText
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct MetricBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(minWidth: 60)
    }
}

struct TranscriptionPreview: View {
    let title: String
    let text: String
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(isExpanded ? "Less" : "More") {
                    isExpanded.toggle()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            
            Text(text)
                .font(.caption)
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Summary Statistics

struct SummaryStatsView: View {
    let results: [TestRun]
    
    var avgSpeedup: Double {
        results.map { $0.speedup }.reduce(0, +) / Double(results.count)
    }
    
    var avgWER: Double {
        results.map { $0.wer }.reduce(0, +) / Double(results.count)
    }
    
    var nativeWinCount: Int {
        results.filter { $0.speedup > 1 }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary (\(results.count) tests)")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatBox(
                    label: "Avg Speedup",
                    value: String(format: "%.2f×", avgSpeedup),
                    detail: avgSpeedup > 1 ? "Native faster" : "Cloud faster"
                )
                
                StatBox(
                    label: "Avg WER",
                    value: String(format: "%.1f%%", avgWER * 100),
                    detail: avgWER < 0.1 ? "Good match" : "Variance"
                )
                
                StatBox(
                    label: "Native Wins",
                    value: "\(nativeWinCount)/\(results.count)",
                    detail: "\(Int(Double(nativeWinCount) / Double(results.count) * 100))%"
                )
            }
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let detail: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    BackendComparisonTestView()
        .frame(width: 700, height: 500)
}
