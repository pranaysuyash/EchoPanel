import Foundation

enum BackendConfig {
    static var host: String {
        UserDefaults.standard.string(forKey: "backendHost") ?? "127.0.0.1"
    }

    static var port: Int {
        let port = UserDefaults.standard.integer(forKey: "backendPort")
        return port == 0 ? 8000 : port
    }

    static var webSocketURL: URL {
        URL(string: "ws://\(host):\(port)/ws/live-listener")!
    }

    static var healthURL: URL {
        URL(string: "http://\(host):\(port)/health")!
    }
}

