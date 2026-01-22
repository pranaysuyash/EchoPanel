import Foundation

/// BackendManager handles the Python server lifecycle.
/// Starts the server as a subprocess when the app launches and manages health checks.
final class BackendManager: ObservableObject {
    
    static let shared = BackendManager()
    
    @Published var isServerReady = false
    @Published var serverStatus: ServerStatus = .stopped
    
    enum ServerStatus: String {
        case stopped = "Stopped"
        case starting = "Starting..."
        case running = "Running"
        case error = "Error"
    }
    
    private var serverProcess: Process?
    private var healthCheckTimer: Timer?
    private let serverPort = 8000
    private let healthCheckURL: URL
    
    private init() {
        healthCheckURL = URL(string: "http://127.0.0.1:\(serverPort)/health")!
    }
    
    // MARK: - Server Lifecycle
    
    func startServer() {
        guard serverProcess == nil else {
            NSLog("BackendManager: Server already running")
            return
        }
        
        serverStatus = .starting
        
        // Find the server directory
        guard let serverPath = findServerPath() else {
            NSLog("BackendManager: Could not find server path")
            serverStatus = .error
            return
        }
        
        // Find Python executable
        guard let pythonPath = findPythonPath(serverDir: serverPath) else {
            NSLog("BackendManager: Could not find Python executable")
            serverStatus = .error
            return
        }
        
        NSLog("BackendManager: Starting server at \(serverPath) with Python \(pythonPath)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "uvicorn", "server.main:app", "--host", "127.0.0.1", "--port", "\(serverPort)"]
        process.currentDirectoryURL = URL(fileURLWithPath: serverPath).deletingLastPathComponent()
        
        // Set environment
        var env = ProcessInfo.processInfo.environment
        env["ECHOPANEL_DEBUG"] = "1"
        env["ECHOPANEL_WHISPER_MODEL"] = UserDefaults.standard.string(forKey: "whisperModel") ?? "large-v3-turbo"
        if let hfToken = UserDefaults.standard.string(forKey: "hfToken"), !hfToken.isEmpty {
            env["ECHOPANEL_HF_TOKEN"] = hfToken
            env["ECHOPANEL_DIARIZATION"] = "1"
        }
        process.environment = env
        
        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                NSLog("BackendManager: Server terminated with code \(proc.terminationStatus)")
                self?.serverStatus = .stopped
                self?.isServerReady = false
                self?.serverProcess = nil
            }
        }
        
        do {
            try process.run()
            serverProcess = process
            startHealthCheck()
        } catch {
            NSLog("BackendManager: Failed to start server: \(error)")
            serverStatus = .error
        }
    }
    
    func stopServer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        
        guard let process = serverProcess, process.isRunning else { return }
        
        NSLog("BackendManager: Stopping server")
        process.terminate()
        serverProcess = nil
        serverStatus = .stopped
        isServerReady = false
    }
    
    // MARK: - Health Check
    
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }
    
    private func checkHealth() {
        var request = URLRequest(url: healthCheckURL)
        request.timeoutInterval = 2.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if self?.isServerReady == false {
                        NSLog("BackendManager: Server is ready")
                        self?.isServerReady = true
                        self?.serverStatus = .running
                        self?.healthCheckTimer?.invalidate()
                        self?.healthCheckTimer = nil
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Path Discovery
    
    private func findServerPath() -> String? {
        // Priority 1: Bundled in app Resources
        if let resourcePath = Bundle.main.resourcePath {
            let bundledServer = (resourcePath as NSString).appendingPathComponent("server")
            if FileManager.default.fileExists(atPath: bundledServer) {
                return bundledServer
            }
        }
        
        // Priority 2: Development path (relative to app)
        var devPath = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        devPath = (devPath as NSString).deletingLastPathComponent
        devPath = (devPath as NSString).deletingLastPathComponent // Go up from .build/debug/
        let serverDir = (devPath as NSString).appendingPathComponent("server")
        if FileManager.default.fileExists(atPath: serverDir) {
            return serverDir
        }
        
        // Priority 3: Hardcoded development path
        let hardcodedPath = "/Users/pranay/Projects/EchoPanel/server"
        if FileManager.default.fileExists(atPath: hardcodedPath) {
            return hardcodedPath
        }
        
        return nil
    }
    
    private func findPythonPath(serverDir: String) -> String? {
        let projectRoot = (serverDir as NSString).deletingLastPathComponent
        
        // Priority 1: Project venv
        let venvPython = (projectRoot as NSString).appendingPathComponent(".venv/bin/python")
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        
        // Priority 2: Bundled Python (future)
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPython = (resourcePath as NSString).appendingPathComponent("python/bin/python3")
            if FileManager.default.fileExists(atPath: bundledPython) {
                return bundledPython
            }
        }
        
        // Priority 3: System Python
        for path in ["/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"] {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    // MARK: - Wait for Server
    
    func waitForServer(timeout: TimeInterval = 30) async -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            if isServerReady {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        return false
    }
}
