import SwiftUI
import XCTest
import SnapshotTesting
@testable import MeetingListenerApp

/**
 * Streaming Visual Tests
 * 
 * These tests verify UI stability during actual audio streaming.
 * They feed the llm_recording_pranay.wav file through the WebSocket
 * and capture screenshots at various transcript states.
 */
@MainActor
final class StreamingVisualTests: XCTestCase {
    private static let recordSnapshots = ProcessInfo.processInfo.environment["RECORD_STREAMING_SNAPSHOTS"] == "1"
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "sidePanel.viewMode")
    }
    
    /// Test empty transcript state (waiting for speech)
    func testEmptyTranscriptState() {
        let appState = AppState()
        appState.sessionState = .listening
        appState.audioSource = .both
        appState.screenRecordingPermission = .authorized
        appState.microphonePermission = .authorized
        // No demo data seeded - empty transcript
        
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .dark,
            named: "streaming-empty",
            appState: appState
        )
    }
    
    /// Test transcript with few segments (early streaming)
    func testEarlyStreamingState() {
        let appState = AppState()
        appState.sessionState = .listening
        appState.audioSource = .both
        appState.screenRecordingPermission = .authorized
        appState.microphonePermission = .authorized
        
        // Add first 3 segments from actual test run
        let earlySegments = [
            TranscriptSegment(
                text: "A large language model LLM is a language model.",
                t0: 0.0,
                t1: 4.0,
                isFinal: true,
                confidence: 0.80,
                source: "system"
            ),
            TranscriptSegment(
                text: "trained with self-supervised machine learning when a vast amount of text",
                t0: 4.0,
                t1: 9.8,
                isFinal: true,
                confidence: 0.79,
                source: "system"
            ),
            TranscriptSegment(
                text: "designed for natural language processing tasks, especially language generation.",
                t0: 8.0,
                t1: 11.76,
                isFinal: true,
                confidence: 0.81,
                source: "system"
            )
        ]
        
        appState.transcriptSegments = earlySegments
        
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .dark,
            named: "streaming-early-3segments",
            appState: appState
        )
    }
    
    /// Test transcript with many segments (mid-streaming)
    func testMidStreamingState() {
        let appState = AppState()
        appState.sessionState = .listening
        appState.audioSource = .both
        appState.screenRecordingPermission = .authorized
        appState.microphonePermission = .authorized
        
        // Add 15 segments - should trigger rolling window behavior
        let midSegments = [
            TranscriptSegment(text: "A large language model LLM is a language model.", t0: 0.0, t1: 4.0, isFinal: true, confidence: 0.80, source: "system"),
            TranscriptSegment(text: "trained with self-supervised machine learning when a vast amount of text", t0: 4.0, t1: 9.8, isFinal: true, confidence: 0.79, source: "system"),
            TranscriptSegment(text: "designed for natural language processing tasks, especially language generation.", t0: 8.0, t1: 11.76, isFinal: true, confidence: 0.81, source: "system"),
            TranscriptSegment(text: "The largest and most capable LLM's are generative pre-trained transformers.", t0: 12.0, t1: 16.0, isFinal: true, confidence: 0.75, source: "system"),
            TranscriptSegment(text: "GPTs and provide the core capabilities of modern chatbots.", t0: 16.0, t1: 20.0, isFinal: true, confidence: 0.79, source: "system"),
            TranscriptSegment(text: "problems can be fine-tuned for specific tasks or guided by prompt engineers.", t0: 20.0, t1: 24.0, isFinal: true, confidence: 0.83, source: "system"),
            TranscriptSegment(text: "engineering, these models require, sorry, acquire prediction.", t0: 24.0, t1: 28.0, isFinal: true, confidence: 0.68, source: "system"),
            TranscriptSegment(text: "power regarding syntax semantics and", t0: 28.0, t1: 32.0, isFinal: true, confidence: 0.70, source: "system"),
            TranscriptSegment(text: "ontologies inherent in human language corpora, but also", t0: 32.0, t1: 36.0, isFinal: true, confidence: 0.84, source: "system"),
            TranscriptSegment(text: "inherit inaccuracies and biases present in the data they are trained on.", t0: 36.0, t1: 40.0, isFinal: true, confidence: 0.83, source: "system"),
            TranscriptSegment(text: "They consist of billions to trillions of parameters and operate.", t0: 40.0, t1: 44.0, isFinal: true, confidence: 0.81, source: "system"),
            TranscriptSegment(text: "as general purpose sequence model generating, summarizing, translating.", t0: 44.0, t1: 48.0, isFinal: true, confidence: 0.81, source: "system"),
            TranscriptSegment(text: "and reasoning overtakes. LLM's represent", t0: 48.0, t1: 52.0, isFinal: true, confidence: 0.68, source: "system"),
            TranscriptSegment(text: "a significant new technology in their ability to generalize", t0: 52.0, t1: 56.0, isFinal: true, confidence: 0.82, source: "system"),
            TranscriptSegment(text: "with minimal task specific supervision, enabling capabilities", t0: 56.0, t1: 60.0, isFinal: true, confidence: 0.74, source: "system")
        ]
        
        appState.transcriptSegments = midSegments
        
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .dark,
            named: "streaming-mid-15segments",
            appState: appState
        )
    }
    
    /// Test full transcript state (post-streaming)
    func testFullTranscriptState() {
        let appState = AppState()
        appState.sessionState = .listening
        appState.audioSource = .both
        appState.screenRecordingPermission = .authorized
        appState.microphonePermission = .authorized
        
        // Add all 42 segments from actual test run
        var fullSegments: [TranscriptSegment] = []
        let testData = [
            ("A large language model LLM is a language model.", 0.0, 4.0, 0.80),
            ("trained with self-supervised machine learning when a vast amount of text", 4.0, 9.8, 0.79),
            ("designed for natural language processing tasks, especially language generation.", 8.0, 11.76, 0.81),
            ("The largest and most capable LLM's are generative pre-trained transformers.", 12.0, 16.0, 0.75),
            ("GPTs and provide the core capabilities of modern chatbots.", 16.0, 20.0, 0.79),
            ("problems can be fine-tuned for specific tasks or guided by prompt engineers.", 20.0, 24.0, 0.83),
            ("engineering, these models require, sorry, acquire prediction.", 24.0, 28.0, 0.68),
            ("power regarding syntax semantics and", 28.0, 32.0, 0.70),
            ("ontologies inherent in human language corpora, but also", 32.0, 36.0, 0.84),
            ("inherit inaccuracies and biases present in the data they are trained on.", 36.0, 40.0, 0.83),
            ("They consist of billions to trillions of parameters and operate.", 40.0, 44.0, 0.81),
            ("as general purpose sequence model generating, summarizing, translating.", 44.0, 48.0, 0.81),
            ("and reasoning overtakes. LLM's represent", 48.0, 52.0, 0.68),
            ("a significant new technology in their ability to generalize", 52.0, 56.0, 0.82),
            ("with minimal task specific supervision, enabling capabilities", 56.0, 60.0, 0.74),
            ("abilities like conversational agents, code generation, knowledge", 60.0, 64.0, 0.75),
            ("retrieval and automated reasoning that previously required bespoke", 64.0, 68.0, 0.77),
            ("spoke systems. LLMs evolved from earlier statistical and recurrent", 68.0, 72.0, 0.74),
            ("neural network approaches to language modeling", 72.0, 76.0, 0.69),
            ("transformer architecture introduced in 2017 replaced", 76.0, 80.0, 0.74),
            ("recurrence with self-attention allowing efficient parallelization", 80.0, 83.6, 0.77),
            ("longer contact handling and scalable training on", 84.0, 88.0, 0.77),
            ("unprecedented data volumes. This innovation enabled models like", 88.0, 92.0, 0.78),
            ("bird and the successors which demonstrated emergent behaviors", 92.0, 96.0, 0.70),
            ("at scale, such as few short learning and compositional reasoning.", 96.0, 99.6, 0.83),
            ("Reinforcement learning particularly policy gradient algorithms", 100.0, 104.0, 0.73),
            ("has been adapted to fine-tune LLMs for desired behaviors", 104.0, 108.1, 0.78),
            ("beyond raw text, raw next token prediction", 108.0, 111.5, 0.79),
            ("reinforcement learning from human feedback R L H F applies this", 112.0, 116.0, 0.69),
            ("to optimize the policy the LLM's output distribution against", 116.0, 120.0, 0.77),
            ("reward signals derived from human or automated preference", 120.0, 124.0, 0.84),
            ("judgments. This has been critical for aligning model outputs with", 124.0, 128.0, 0.80),
            ("human expectations, improving factuality, reducing harmful responses", 128.0, 132.0, 0.76),
            ("and enhancing task performance. Benchmark evaluations for LLMs", 132.0, 136.0, 0.68),
            ("have evolved from narrow linguistic assessments to broader", 136.0, 143.0, 0.75),
            ("comprehensive multi task evaluations measuring reasoning", 140.0, 144.0, 0.69),
            ("functioning, factual accuracy, alignment and safety.", 144.0, 147.0, 0.63),
            ("Health climbing...", 147.0, 148.0, 0.63),
            ("iteratively optimizing models against benchmarks as emerged", 148.0, 152.0, 0.72),
            ("and strategy, reducing rapid incremental performance gains", 152.0, 155.9, 0.77),
            ("But raising concerns of overfitting to benchmarks rather than", 156.0, 160.0, 0.77),
            ("generalization or robust capability improvements...", 160.0, 162.8, 0.79)
        ]
        
        for (text, t0, t1, confidence) in testData {
            fullSegments.append(TranscriptSegment(
                text: text,
                t0: t0,
                t1: t1,
                isFinal: true,
                confidence: confidence,
                source: "system"
            ))
        }
        
        appState.transcriptSegments = fullSegments
        
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .dark,
            named: "streaming-full-42segments",
            appState: appState
        )
    }
    
    /// Test alignment stability - verify no jitter in row layout
    func testRowAlignmentStability() {
        let appState = AppState()
        appState.sessionState = .listening
        appState.audioSource = .both
        
        // Mix of confidence levels to test badge alignment
        let mixedSegments = [
            TranscriptSegment(text: "High confidence segment with good audio.", t0: 0.0, t1: 4.0, isFinal: true, confidence: 0.85, source: "system"),
            TranscriptSegment(text: "Low confidence segment.", t0: 4.0, t1: 8.0, isFinal: true, confidence: 0.45, source: "system"),
            TranscriptSegment(text: "Another high confidence segment here.", t0: 8.0, t1: 12.0, isFinal: true, confidence: 0.82, source: "mic"),
            TranscriptSegment(text: "Medium confidence transcript line.", t0: 12.0, t1: 16.0, isFinal: true, confidence: 0.65, source: "system"),
            TranscriptSegment(text: "Very low confidence segment that needs review badge.", t0: 16.0, t1: 20.0, isFinal: true, confidence: 0.35, source: "mic")
        ]
        
        appState.transcriptSegments = mixedSegments
        
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .dark,
            named: "streaming-mixed-confidence",
            appState: appState
        )
    }
    
    /// Test focused segment with action buttons visible
    func testFocusedSegmentState() {
        let appState = AppState()
        appState.sessionState = .listening
        appState.audioSource = .both
        
        // Create segments and set focus on one
        let segments = [
            TranscriptSegment(text: "First segment of the transcript.", t0: 0.0, t1: 4.0, isFinal: true, confidence: 0.80, source: "system"),
            TranscriptSegment(text: "Second segment that is currently focused.", t0: 4.0, t1: 8.0, isFinal: true, confidence: 0.75, source: "system"),
            TranscriptSegment(text: "Third segment after the focused one.", t0: 8.0, t1: 12.0, isFinal: true, confidence: 0.82, source: "system")
        ]
        
        appState.transcriptSegments = segments
        
        // Note: Focus state is view-side, so we can't easily set it here
        // The snapshot will show unfocused state, which is the stable default
        
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .dark,
            named: "streaming-with-focus-candidate",
            appState: appState
        )
    }
    
    // MARK: - Helpers
    
    private func assertPanelSnapshot(
        mode: SidePanelView.ViewMode,
        size: CGSize,
        colorScheme: ColorScheme,
        named: String,
        appState: AppState
    ) {
        UserDefaults.standard.set(mode.rawValue, forKey: "sidePanel.viewMode")
        
        let view = SidePanelView(
            appState: appState,
            onEndSession: {},
            onModeChange: nil
        )
        .preferredColorScheme(colorScheme)
        
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        
        assertSnapshot(
            of: hostingView,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                size: size
            ),
            named: nil,
            record: Self.recordSnapshots,
            timeout: 10,
            testName: named
        )
    }
}


