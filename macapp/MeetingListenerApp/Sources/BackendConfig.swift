import Foundation

enum BackendConfig {
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

    private static func buildURL(path: String, includeToken: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = path.hasPrefix("/ws/") ? webSocketScheme : httpScheme
        components.host = host
        components.port = port
        components.path = path
        if includeToken,
           let token = KeychainHelper.loadBackendToken(),
           !token.isEmpty {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        guard let url = components.url else {
            fatalError("Invalid backend URL components for path: \(path)")
        }
        return url
    }

    static var webSocketURL: URL {
        buildURL(path: "/ws/live-listener", includeToken: true)
    }

    static var healthURL: URL {
        buildURL(path: "/health")
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
}
