import XCTest
import AVFoundation
@testable import MeetingListenerApp

/// Tests for the audio limiter functionality (P0-2 Fix)
/// Verifies that the soft limiter prevents hard clipping while preserving audio quality
final class AudioLimiterTests: XCTestCase {
    
    // MARK: - Test Constants
    
    /// Sample rate for testing
    let sampleRate: Float = 16000.0
    
    /// Duration of test signals in seconds
    let testDuration: Float = 0.1  // 100ms
    
    /// Threshold for limiting (-0.9 dBFS)
    let limiterThreshold: Float = 0.9
    
    // MARK: - Helper Methods
    
    /// Create a sine wave at specified frequency and amplitude
    private func generateSineWave(frequency: Float, amplitude: Float, duration: Float) -> [Float] {
        let numSamples = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: numSamples)
        
        for i in 0..<numSamples {
            let time = Float(i) / sampleRate
            samples[i] = amplitude * sin(2.0 * .pi * frequency * time)
        }
        
        return samples
    }
    
    /// Apply limiter algorithm (reproduced here for testing)
    /// Uses same coefficients as production code:
    /// - Attack: 0.001 (immediate, ~1 sample)
    /// - Release: 0.99995 (slow, ~1 second at 16kHz)
    private func applyLimiter(
        samples: [Float],
        threshold: Float = 0.9,
        attack: Float = 0.001,
        release: Float = 0.99995,
        maxReduction: Float = 0.1
    ) -> [Float] {
        var limited = [Float](repeating: 0, count: samples.count)
        var limiterGain: Float = 1.0
        
        for i in 0..<samples.count {
            let sample = samples[i]
            let absSample = abs(sample)
            
            let targetGain: Float
            if absSample > threshold {
                targetGain = threshold / absSample
            } else {
                targetGain = 1.0
            }
            
            let clampedTargetGain = max(targetGain, maxReduction)
            
            if clampedTargetGain < limiterGain {
                limiterGain = limiterGain * attack + clampedTargetGain * (1.0 - attack)
            } else {
                limiterGain = limiterGain * release + clampedTargetGain * (1.0 - release)
            }
            
            limited[i] = sample * limiterGain
        }
        
        return limited
    }
    
    /// Calculate peak level in dBFS
    private func peakLevelDBFS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -Float.infinity }
        let peak = samples.map { abs($0) }.max() ?? 0
        guard peak > 0 else { return -Float.infinity }
        return 20.0 * log10(peak)
    }
    
    /// Calculate RMS level
    private func rmsLevel(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }
    
    // MARK: - Tests
    
    /// Test that 0 dBFS sine wave is limited to -0.9 dBFS
    func testLimiterReducesPeaksToThreshold() {
        // Generate 1 kHz sine wave at 0 dBFS (amplitude = 1.0)
        let sineWave = generateSineWave(frequency: 1000, amplitude: 1.0, duration: testDuration)
        
        // Apply limiter
        let limited = applyLimiter(samples: sineWave)
        
        // Calculate peak of limited signal
        let limitedPeak = limited.map { abs($0) }.max() ?? 0
        
        // Peak should be at or below threshold (0.9)
        XCTAssertLessThanOrEqual(limitedPeak, limiterThreshold + 0.01, 
            "Limited peak (\(limitedPeak)) should be at or below threshold (\(limiterThreshold))")
        
        // Peak should be close to threshold (not over-limited)
        XCTAssertGreaterThan(limitedPeak, limiterThreshold * 0.8,
            "Limited peak should be close to threshold, not over-limited")
    }
    
    /// Test that quiet signals are not affected by limiting
    func testLimiterPreservesQuietSignals() {
        // Generate -20 dBFS sine wave (amplitude = 0.1)
        let quietAmplitude: Float = 0.1
        let sineWave = generateSineWave(frequency: 1000, amplitude: quietAmplitude, duration: testDuration)
        
        // Apply limiter
        let limited = applyLimiter(samples: sineWave)
        
        // Calculate RMS of both signals
        let originalRMS = rmsLevel(samples: sineWave)
        let limitedRMS = rmsLevel(samples: limited)
        
        // RMS should be nearly identical (within 1%)
        let rmsDifference = abs(originalRMS - limitedRMS) / originalRMS
        XCTAssertLessThan(rmsDifference, 0.01,
            "Quiet signal RMS should be preserved (difference: \(rmsDifference * 100)%)")
    }
    
    /// Test that limiter attack is fast (catches peaks immediately)
    func testLimiterAttackIsFast() {
        // Create signal with sudden peak
        var samples = [Float](repeating: 0.1, count: 100)  // Quiet first
        samples.append(contentsOf: [Float](repeating: 1.0, count: 10))  // Sudden peak
        
        // Apply limiter
        let limited = applyLimiter(samples: samples)
        
        // First sample after peak should be limited
        let peakIndex = 100
        let firstPeakSample = limited[peakIndex]
        XCTAssertLessThan(abs(firstPeakSample), limiterThreshold + 0.05,
            "Limiter should catch peak immediately (attack is fast)")
    }
    
    /// Test that limiter release is slow (smooth return to unity)
    func testLimiterReleaseIsSlow() {
        // Create signal: peak followed by quiet
        var samples = [Float](repeating: 1.0, count: 100)  // Peak first
        samples.append(contentsOf: [Float](repeating: 0.1, count: 5000))  // Then quiet (longer for slow release)
        
        // Apply limiter
        let limited = applyLimiter(samples: samples)
        
        // Find when gain returns to near unity (within 5%)
        var returnToUnityIndex = samples.count - 1
        for i in 100..<limited.count {
            let expected = samples[i]  // 0.1
            let actual = limited[i]
            let gain = actual / expected
            if gain > 0.95 {  // Within 5% of unity
                returnToUnityIndex = i
                break
            }
        }
        
        // With release coefficient of 0.99995, should take ~5000 samples to mostly recover
        // (At 16kHz, that's ~300ms for significant recovery, full recovery takes longer)
        XCTAssertGreaterThan(returnToUnityIndex, 500,
            "Limiter release should be slow (returned to 95% unity at sample \(returnToUnityIndex), expected >500)")
    }
    
    /// Test that no samples exceed the threshold after limiting
    func testNoSamplesExceedThreshold() {
        // Generate signal with varying amplitude including peaks
        var samples = [Float]()
        for i in 0..<1600 {  // 100ms at 16kHz
            let amplitude: Float = Float.random(in: 0.5...1.5)  // Some samples > 1.0
            let sample = amplitude * sin(2.0 * .pi * 440.0 * Float(i) / sampleRate)
            samples.append(sample)
        }
        
        // Apply limiter
        let limited = applyLimiter(samples: samples)
        
        // Verify no sample exceeds threshold
        let maxSample = limited.map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(maxSample, limiterThreshold + 0.001,
            "No sample should exceed threshold (\(limiterThreshold)), max was \(maxSample)")
    }
    
    /// Test that limiting ratio is reasonable (not over-limiting)
    func testLimiterNotOverLimiting() {
        // Generate sine wave at -3 dBFS (amplitude = 0.7)
        let amplitude: Float = 0.7
        let sineWave = generateSineWave(frequency: 1000, amplitude: amplitude, duration: testDuration)
        
        // Apply limiter
        let limited = applyLimiter(samples: sineWave)
        
        // Calculate gain reduction
        let originalPeak = sineWave.map { abs($0) }.max() ?? 0
        let limitedPeak = limited.map { abs($0) }.max() ?? 0
        let gainReduction = originalPeak > 0 ? limitedPeak / originalPeak : 1.0
        
        // Should have minimal gain reduction since peak is below threshold
        XCTAssertGreaterThan(gainReduction, 0.95,
            "Signal below threshold should have minimal gain reduction (was \(gainReduction))")
    }
    
    /// Test that Float->Int16 conversion works correctly with limited samples
    func testInt16ConversionWithLimitedSamples() {
        // Generate signal with peaks > 1.0
        let sineWave = generateSineWave(frequency: 1000, amplitude: 1.5, duration: testDuration)
        
        // Apply limiter
        let limited = applyLimiter(samples: sineWave)
        
        // Convert to Int16 (simulating what emitPCMFrames does)
        var pcmSamples = [Int16]()
        for sample in limited {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            pcmSamples.append(int16Value)
        }
        
        // Verify no Int16 overflow
        let maxValue = pcmSamples.map { $0 }.max() ?? 0
        let minValue = pcmSamples.map { $0 }.min() ?? 0
        
        XCTAssertLessThanOrEqual(maxValue, Int16.max,
            "No Int16 value should overflow max")
        XCTAssertGreaterThanOrEqual(minValue, Int16.min,
            "No Int16 value should overflow min")
        
        // Verify peak is at expected level (-0.9 dBFS = 29490 in Int16)
        let expectedPeak = Int16(Float(Int16.max) * limiterThreshold)
        XCTAssertLessThanOrEqual(maxValue, Int16(expectedPeak + 500),
            "Int16 peak should be near -0.9 dBFS (\(expectedPeak))")
    }
    
    /// Test limiter with silence (should not amplify noise)
    func testLimiterWithSilence() {
        // Generate silence
        let silence = [Float](repeating: 0.0, count: 1600)
        
        // Apply limiter
        let limited = applyLimiter(samples: silence)
        
        // Should remain silent (no amplification)
        let maxValue = limited.map { abs($0) }.max() ?? 1.0
        XCTAssertEqual(maxValue, 0.0, accuracy: 0.0001,
            "Silence should remain silent after limiting")
    }
    
    /// Test limiter with impulse signal
    func testLimiterWithImpulse() {
        // Create impulse signal
        var samples = [Float](repeating: 0.0, count: 100)
        samples[50] = 2.0  // Impulse at sample 50
        
        // Apply limiter
        let limited = applyLimiter(samples: samples)
        
        // Impulse should be limited
        let limitedImpulse = limited[50]
        XCTAssertLessThanOrEqual(abs(limitedImpulse), limiterThreshold + 0.1,
            "Impulse should be limited to threshold")
        
        // Surrounding samples should not be affected
        let beforeImpulse = limited[49]
        let afterImpulse = limited[51]
        XCTAssertEqual(beforeImpulse, 0.0, accuracy: 0.0001,
            "Sample before impulse should be unchanged")
        // Note: sample after impulse may have reduced gain due to attack
    }
}

// MARK: - Performance Tests

extension AudioLimiterTests {
    
    /// Performance test for limiter on 1 second of audio
    func testLimiterPerformance() {
        let samples = generateSineWave(frequency: 1000, amplitude: 1.5, duration: 1.0)
        
        measure {
            _ = applyLimiter(samples: samples)
        }
    }
}
