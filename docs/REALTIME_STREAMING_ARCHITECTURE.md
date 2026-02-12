# Real-time Streaming Architecture in EchoPanel

## Overview

EchoPanel implements a sophisticated real-time streaming architecture for audio processing and ASR (Automatic Speech Recognition). This document describes the key concepts, implementation details, and design decisions that enable low-latency, high-reliability streaming.

## Core Concepts

### Streaming vs. Batch Processing

Traditional LLM inference assumes complete prompts are available upfront. However, real-time applications like voice assistants, live transcription, and robotics require processing incremental inputs with minimal latency.

**Key differences:**
- **Batch processing**: Complete input → Complete output
- **Streaming**: Incremental input → Incremental output

### Latency Requirements

For voice interfaces and real-time applications:
- **Time-To-First-Token (TTFT)**: Users expect sub-second responses
- **Natural interaction**: Systems need to listen and respond simultaneously
- **Human-like response**: Sub-second reaction times for natural conversation

## Technical Implementation

### Attention Patterns

The streaming architecture relies on specific attention mechanisms:

1. **Causal attention (uni-directional mask)**: Each position t attends only to tokens at positions j ≤ t
2. **Sliding-window attention**: Keeps computation and memory bounded for long-running applications
3. **Streaming compatibility**: Unlike bidirectional attention, causal attention supports true streaming

### Audio Processing Pipeline

EchoPanel's audio processing follows this flow:

```
Audio Capture → PCM Encoding → WebSocket Streaming → Server ASR → Partial/Final Results
```

#### Client-Side Streaming

The `AppState.swift` manages real-time audio streaming:

```swift
// Audio capture callbacks send frames immediately
audioCapture.onPCMFrame = { [weak self] frame, source in
    // Update diagnostics
    self?.markInputFrame(source: source)
    self?.lastAudioTimestamp = Date()
    
    // Send to WebSocket immediately
    self.streamer.sendPCMFrame(frame, source: source)
}
```

#### Server-Side Processing

The `ws_live_listener.py` handles streaming with:

- Per-source bounded queues
- Priority processing (mic > system audio)
- Real-time metrics emission
- Backpressure handling

### Backpressure and Concurrency Control

The system implements multi-level backpressure:

1. **Global session limiting**: Prevents resource exhaustion
2. **Per-source bounded queues**: Natural backpressure mechanism
3. **Priority processing**: Microphone audio takes precedence over system audio
4. **Adaptive chunk sizing**: Adjusts processing based on load conditions

## Circuit Breaker Implementation

### Purpose

The circuit breaker pattern prevents infinite retry loops during sustained outages and improves system resilience.

### States

- **CLOSED**: Normal operation, requests allowed
- **OPEN**: Failure threshold exceeded, requests blocked temporarily
- **HALF_OPEN**: Testing if service has recovered

### Configuration

- **Failure threshold**: 5 consecutive failures before opening
- **Recovery timeout**: 60 seconds before allowing test requests
- **Integration**: Works with exponential backoff and message buffering

## Real-time WebSocket API

### Message Types

#### Client to Server
- `session.create`: Initialize streaming session
- `input_audio_buffer.append`: Send audio chunks
- `response.create`: Request processing

#### Server to Client
- `session.created`: Acknowledge session creation
- `response.text.delta`: Partial transcription results
- `response.done`: Indicate completion

### Session Management

The system maintains persistent sessions with:
- Preserved KV cache across chunks
- Correlation IDs for request tracking
- Efficient memory management

## Performance Considerations

### Memory Management
- Sessions hold memory and aren't preempted when idle
- KV cache preservation avoids re-computation
- Bounded queues prevent memory exhaustion

### Throughput vs. Latency
- Dedicated session interface optimizes for low latency
- Adaptive chunk sizing balances throughput and responsiveness
- Priority queues ensure critical audio isn't delayed

## Implementation Specifics

### Client-Side (AppState.swift)

The `AppState` class manages the streaming lifecycle:

- **Session state management**: Tracks connection status
- **Multi-source audio**: Supports system, microphone, or both
- **Real-time diagnostics**: Monitors input freshness and ASR response times
- **Error handling**: Manages streaming errors and recovery

### Server-Side (ws_live_listener.py)

The WebSocket endpoint implements:

- **Per-source queues**: Separate processing for different audio sources
- **Real-time metrics**: Continuous monitoring of queue depth, processing times
- **Graceful degradation**: Handles overload conditions with backpressure
- **Session finalization**: Proper cleanup and summary generation

## Advanced Features

### Adaptive Performance Degradation

The system includes a degrade ladder that can:
- Reduce quality settings under load
- Switch to fallback providers
- Adjust processing parameters dynamically

### Diarization Integration

Real-time diarization is integrated into the streaming pipeline:
- Speaker identification during transcription
- Source-specific processing to avoid mixing
- Post-processing for final speaker attribution

## Best Practices

### Error Handling
- Implement circuit breakers to prevent cascading failures
- Use exponential backoff with jitter for retries
- Maintain bounded queues to prevent resource exhaustion

### Monitoring
- Emit real-time metrics for queue depth and processing times
- Track backpressure levels and dropped frames
- Monitor end-to-end latency and error rates

### Resource Management
- Limit concurrent sessions to prevent overload
- Use priority queues for critical audio sources
- Implement graceful degradation under load

## Future Enhancements

### Streaming-Specific Training
- Fine-tune models specifically for streaming inputs
- Optimize attention patterns for real-time processing
- Improve partial result quality

### Advanced Attention Mechanisms
- Implement sliding-window attention for long sessions
- Explore sparse attention patterns for efficiency
- Optimize KV cache management

This architecture enables EchoPanel to provide reliable, low-latency streaming audio processing suitable for real-time applications while maintaining resilience under varying load conditions.