import Foundation

enum BackendConfig {
    private static let defaultHealthCheckTimeout: TimeInterval = 2.0

    static var host: String {
        UserDefaults.standard.string(forKey: "backendHost") ?? "127.0.0.1"
    }

    static var port: Int {
        let port = UserDefaults.standard.integer(forKey: "backendPort")
        return port == 0 ? 8000 : port
    }

    static var isLocalHost: Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "127.0.0.1" || normalized == "localhost" || normalized == "::1"
    }

    static var webSocketScheme: String {
        isLocalHost ? "ws" : "wss"
    }

    static var httpScheme: String {
        isLocalHost ? "http" : "https"
    }

    private static func buildURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = path.hasPrefix("/ws/") ? webSocketScheme : httpScheme
        components.host = host
        components.port = port
        components.path = path
        guard let url = components.url else {
            fatalError("Invalid backend URL components for path: \(path)")
        }
        return url
    }

    static var webSocketURL: URL {
        buildURL(path: "/ws/live-listener")
    }

    static var webSocketRequest: URLRequest {
        var request = URLRequest(url: webSocketURL)
        if let token = KeychainHelper.loadBackendToken(),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "x-echopanel-token")
        }
        return request
    }

    static var healthURL: URL {
        buildURL(path: "/health")
    }

    static var healthCheckTimeout: TimeInterval {
        let configured = UserDefaults.standard.double(forKey: "backendHealthTimeoutSeconds")
        guard configured > 0 else { return defaultHealthCheckTimeout }
        return min(max(configured, 0.2), 30.0)
    }

    static var documentsListURL: URL {
        buildURL(path: "/documents")
    }

    static var documentsIndexURL: URL {
        buildURL(path: "/documents/index")
    }

    static var documentsQueryURL: URL {
        buildURL(path: "/documents/query")
    }

    static func documentDeleteURL(documentID: String) -> URL {
        buildURL(path: "/documents/\(documentID)")
    }

    // U8 groundwork flags: telemetry + feature handshakes only (no default behavior change).
    static var clockDriftCompensationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "broadcast_useClockDriftCompensation")
    }

    static var clientVADEnabled: Bool {
        UserDefaults.standard.bool(forKey: "broadcast_useClientVAD")
    }

    // Audio transport: when enabled, the client sends PCM as binary WebSocket frames instead of base64-in-JSON.
    // Default: enabled for localhost to reduce overhead; can be overridden via UserDefaults.
    static var useBinaryAudioFrames: Bool {
        let key = "ws_useBinaryAudioFrames"
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return isLocalHost
    }
}
