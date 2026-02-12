# Circuit Breaker Implementation (Consolidated)

## Summary

EchoPanel now uses a single circuit-breaker implementation in `macapp/MeetingListenerApp/Sources/CircuitBreaker.swift` for both:

- backend restart orchestration (`CircuitBreakerManager`)
- WebSocket reconnect resilience (`ResilientWebSocket` via `ReconnectionConfiguration.circuitBreaker`)

The previous WS-local implementation in `ResilientWebSocket.swift` was removed to prevent semantic drift.

## Shared Component

`CircuitBreaker` is `@MainActor` + `ObservableObject` and preserves:

- states: `closed`, `open`, `halfOpen`
- threshold-based open behavior
- half-open recovery probing after `resetTimeout`
- failure-window tracking (`failureWindow`)
- structured logs for state changes and failures
- SwiftUI compatibility (`CircuitBreakerStatusView`)

Primary API:

- `canExecute() -> Bool`
- `recordSuccess()`
- `recordFailure(_ error: Error)`
- `reset()`
- `execute(operation:name:)`

## WebSocket Usage

`ResilientWebSocket` consumes the shared breaker through `ReconnectionConfiguration`:

- checks `canExecute()` before connect/reconnect
- records failures in `handleError(_:)`
- records success in `onConnectionSuccess()`
- publishes `.circuitOpen(until:)` using the breaker's `resetTimeout`

Default WS profile remains functionally aligned:

- failure threshold: `5`
- reset timeout: `60s`
- aggressive profile threshold: `3`
- aggressive profile reset timeout: `30s`

`failureWindow` is explicitly set large for WS profiles to preserve reconnect behavior without introducing tight window-based suppression.

## Backend Usage

`CircuitBreakerManager` remains the global access point:

- `backendRestartBreaker`
- `healthCheckBreaker`

No API changes were required for existing backend-facing usage.

## Migration Notes

1. Removed duplicate WS-local circuit breaker type from `ResilientWebSocket.swift`.
2. Updated `ReconnectionConfiguration.circuitBreaker` type to shared `CircuitBreaker`.
3. Kept UI and observability contracts intact (`CircuitBreakerStatusView`, `StructuredLogger` metadata, manager singletons).
4. Added tests to cover shared breaker state transitions and WS integration path.

## Verification

Run:

```bash
cd macapp/MeetingListenerApp
swift test --filter CircuitBreakerConsolidationTests
swift test --filter DeviceHotSwapManagerTests
swift test --filter AppStateNoticeTests
swift test
```
