import Foundation

/// BackendManager handles the Python server lifecycle.
/// Starts the server as a subprocess when the app launches and manages health checks.
final class BackendManager: ObservableObject {
    
    static let shared = BackendManager()
    
    @Published var isServerReady = false
    @Published var serverStatus: ServerStatus = .stopped
    @Published var healthDetail: String = ""
    @Published var lastExitCode: Int?
    @Published var usingExternalBackend: Bool = false
    
    enum ServerStatus: String {
        case stopped = "Stopped"
        case starting = "Starting..."
        case running = "Running"
        case runningNeedsSetup = "Running (Needs setup)"
        case error = "Error"
    }
    
    private var serverProcess: Process?
    private var healthCheckTimer: Timer?
    private var stopRequested: Bool = false
    private var serverPort: Int { BackendConfig.port }
    private var serverHost: String { BackendConfig.host }
    private var healthCheckURL: URL { BackendConfig.healthURL }
    
    private init() {
    }
    
    // MARK: - Server Lifecycle
    
    func startServer() {
        guard serverProcess == nil else {
            NSLog("BackendManager: Server already running")
            return
        }

        serverStatus = .starting
        isServerReady = false
        healthDetail = ""
        lastExitCode = nil
        stopRequested = false
        usingExternalBackend = false

        // If something is already serving on the configured host/port, adopt it (or
        // surface a clear "port in use" error) instead of failing with bind errors.
        switch probeExistingBackend(timeout: 0.6) {
        case .healthy(let detail):
            usingExternalBackend = true
            isServerReady = true
            serverStatus = .running
            healthDetail = "Using existing backend · \(detail)"
            return
        case .needsSetup(let reason):
            usingExternalBackend = true
            isServerReady = false
            serverStatus = .runningNeedsSetup
            healthDetail = reason
            return
        case .portInUse:
            usingExternalBackend = false
            isServerReady = false
            serverStatus = .error
            healthDetail = "Port \(serverPort) is already in use. Quit the other server or change the port in Settings."
            return
        case .notRunning:
            break
        }
        
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
        process.arguments = ["-m", "uvicorn", "server.main:app", "--host", serverHost, "--port", "\(serverPort)"]
        process.currentDirectoryURL = URL(fileURLWithPath: serverPath).deletingLastPathComponent()
        
        // Set environment
        var env = ProcessInfo.processInfo.environment
        env["ECHOPANEL_DEBUG"] = "1"
        env["ECHOPANEL_WHISPER_MODEL"] = sanitizeWhisperModel(UserDefaults.standard.string(forKey: "whisperModel"))
        if let hfToken = UserDefaults.standard.string(forKey: "hfToken"), !hfToken.isEmpty {
            env["ECHOPANEL_HF_TOKEN"] = hfToken
            env["ECHOPANEL_DIARIZATION"] = "1"
        }
        process.environment = env
        
        // Create log file
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("echopanel_server.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        
        do {
            let fileHandle = try FileHandle(forWritingTo: logURL)
            fileHandle.seekToEndOfFile()
            
            process.standardOutput = fileHandle
            process.standardError = fileHandle
            
            NSLog("BackendManager: Redirecting server output to \(logURL.path)")
        } catch {
            NSLog("BackendManager: Failed to create log file handle: \(error)")
            // Fallback to pipes/dev null if needed, but for now just log it
        }
        
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                let code = Int(proc.terminationStatus)
                self?.lastExitCode = code
                NSLog("BackendManager: Server terminated with code \(code)")
                self?.healthCheckTimer?.invalidate()
                self?.healthCheckTimer = nil
                if self?.stopRequested == true {
                    self?.serverStatus = .stopped
                } else {
                    self?.serverStatus = code == 0 ? .stopped : .error
                }
                self?.isServerReady = false
                self?.healthDetail = code == 0 ? "" : "Server exited (code \(code))"
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
        stopRequested = true
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
                guard let self else { return }

                if let error {
                    self.healthDetail = error.localizedDescription
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else { return }
                let statusCode = httpResponse.statusCode
                let payload = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
                let root: [String: Any]
                if let detail = payload["detail"] as? [String: Any] {
                    root = detail
                } else {
                    root = payload
                }
                let status = (root["status"] as? String) ?? ""
                let provider = (root["provider"] as? String) ?? ""
                let model = (root["model"] as? String) ?? ""

                if statusCode == 200 && status == "ok" {
                    if self.isServerReady == false {
                        NSLog("BackendManager: Server is ready")
                    }
                    self.isServerReady = true
                    self.healthDetail = "ASR: \(provider.isEmpty ? "ready" : provider) \(model.isEmpty ? "" : "(\(model))")"
                    self.serverStatus = .running
                    self.healthCheckTimer?.invalidate()
                    self.healthCheckTimer = nil
                    return
                }

                // Server is reachable, but not ready (ASR missing / loading / misconfigured).
                if statusCode == 503 {
                    self.isServerReady = false
                    let reason = (root["reason"] as? String) ?? "Backend not ready"
                    self.healthDetail = reason
                    self.serverStatus = .runningNeedsSetup
                    return
                }

                // Any other code: treat as error but keep retrying briefly.
                self.isServerReady = false
                self.healthDetail = "Health check failed (\(statusCode))"
                self.serverStatus = .error
            }
        }.resume()
    }

    private enum ProbeResult {
        case healthy(detail: String)
        case needsSetup(reason: String)
        case portInUse
        case notRunning
    }

    private func probeExistingBackend(timeout: TimeInterval) -> ProbeResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: ProbeResult = .notRunning

        var request = URLRequest(url: healthCheckURL)
        request.timeoutInterval = timeout

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if error != nil {
                result = .notRunning
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                result = .portInUse
                return
            }

            let statusCode = httpResponse.statusCode
            let payload = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
            let root: [String: Any]
            if let detail = payload["detail"] as? [String: Any] {
                root = detail
            } else {
                root = payload
            }

            if statusCode == 200, (root["status"] as? String) == "ok" {
                let provider = (root["provider"] as? String) ?? ""
                let model = (root["model"] as? String) ?? ""
                let detail = "ASR: \(provider.isEmpty ? "ready" : provider) \(model.isEmpty ? "" : "(\(model))")"
                result = .healthy(detail: detail)
                return
            }

            // Our backend can return 503 until ASR deps/model are ready.
            if statusCode == 503 {
                let reason = (root["reason"] as? String) ?? "Backend not ready yet"
                result = .needsSetup(reason: reason)
                return
            }

            // Something responded on that port but it isn't our expected health response.
            result = .portInUse
        }.resume()

        _ = semaphore.wait(timeout: .now() + timeout + 0.2)
        return result
    }

    private func sanitizeWhisperModel(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "base"
        }
        // faster-whisper supports Whisper model family names. Keep this conservative.
        let allowed: Set<String> = ["tiny", "base", "small", "medium", "large-v2", "large-v3", "large"]
        if allowed.contains(value) { return value }
        return "base"
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
