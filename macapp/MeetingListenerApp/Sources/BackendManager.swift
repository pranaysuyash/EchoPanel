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
    @Published var recoveryPhase: RecoveryPhase = .idle
    
    enum ServerStatus: String {
        case stopped = "Stopped"
        case starting = "Starting..."
        case running = "Running"
        case runningNeedsSetup = "Running (Needs setup)"
        case error = "Error"
    }

    enum RecoveryPhase: Equatable {
        case idle
        case retryScheduled(attempt: Int, maxAttempts: Int, delay: TimeInterval)
        case failed(attempts: Int, maxAttempts: Int)
    }
    
    private var serverProcess: Process?
    private var healthCheckTimer: Timer?
    private var stopRequested: Bool = false
    private var serverPort: Int { BackendConfig.port }
    private var serverHost: String { BackendConfig.host }
    private var healthCheckURL: URL { BackendConfig.healthURL }
    
    // Crash recovery state
    private var restartAttempts: Int = 0
    private let maxRestartAttempts: Int = 3
    private var restartDelay: TimeInterval = 1.0
    private let maxRestartDelay: TimeInterval = 10.0
    private var restartTimer: Timer?
    
    private init() {
    }
    
    // MARK: - Server Lifecycle
    
    func startServer(isRecoveryAttempt: Bool = false) {
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

        if !isRecoveryAttempt {
            restartAttempts = 0
            restartDelay = 1.0
            recoveryPhase = .idle
        }

        // If something is already serving on the configured host/port, adopt it (or
        // surface a clear "port in use" error) instead of failing with bind errors.
        switch probeExistingBackend(timeout: 0.25) {
        case .healthy(let detail):
            usingExternalBackend = true
            isServerReady = true
            serverStatus = .running
            healthDetail = "Using existing backend · \(detail)"
            recoveryPhase = .idle
            return
        case .needsSetup(let reason):
            usingExternalBackend = true
            isServerReady = false
            serverStatus = .runningNeedsSetup
            healthDetail = reason
            recoveryPhase = .idle
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
        
        // Determine launch strategy: bundled executable or Python
        let launchConfig = determineLaunchStrategy()
        
        guard let executablePath = launchConfig.executable else {
            NSLog("BackendManager: Could not find server executable or Python")
            serverStatus = .error
            healthDetail = "Server not found. Please reinstall EchoPanel."
            recoveryPhase = .failed(attempts: restartAttempts, maxAttempts: maxRestartAttempts)
            return
        }
        
        NSLog("BackendManager: Starting server using \(launchConfig.mode)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = launchConfig.arguments
        if let workingDir = launchConfig.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }
        
        // Set environment
        var env = ProcessInfo.processInfo.environment
        env["ECHOPANEL_DEBUG"] = "1"
        env["ECHOPANEL_WHISPER_MODEL"] = sanitizeWhisperModel(UserDefaults.standard.string(forKey: "whisperModel"))
        
        // Ensure token is migrated from UserDefaults to Keychain
        _ = KeychainHelper.migrateFromUserDefaults()

        // Secure local backend by default: if no token is configured yet, generate one and
        // start the backend with it. The app will automatically send it in WS/HTTP headers.
        if BackendConfig.isLocalHost {
            _ = KeychainHelper.ensureBackendToken()
        }

        if let hfToken = KeychainHelper.loadHFToken(), !hfToken.isEmpty {
            env["ECHOPANEL_HF_TOKEN"] = hfToken
            env["ECHOPANEL_DIARIZATION"] = "1"
        }
        if let backendToken = KeychainHelper.loadBackendToken(), !backendToken.isEmpty {
            env["ECHOPANEL_WS_AUTH_TOKEN"] = backendToken
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
            
            // Log file is in temporary directory, path may contain PII (username)
            // Only log the filename, not the full path
            let sanitizedPath = logURL.lastPathComponent
            NSLog("BackendManager: Redirecting server output to tmp/\(sanitizedPath)")
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
                self?.serverProcess = nil
                self?.isServerReady = false
                
                if self?.stopRequested == true {
                    // User-initiated stop
                    self?.serverStatus = .stopped
                    self?.healthDetail = ""
                    self?.restartAttempts = 0
                    self?.restartDelay = 1.0
                    self?.recoveryPhase = .idle
                } else {
                    // Unexpected termination - attempt restart if not maxed out
                    let wasError = code != 0
                    if wasError && (self?.restartAttempts ?? 0) < (self?.maxRestartAttempts ?? 3) {
                        self?.attemptRestart()
                    } else {
                        self?.serverStatus = wasError ? .error : .stopped
                        self?.healthDetail = wasError ? "Server exited (code \(code))" : ""
                        if wasError {
                            self?.recoveryPhase = .failed(
                                attempts: self?.restartAttempts ?? 0,
                                maxAttempts: self?.maxRestartAttempts ?? 3
                            )
                        } else {
                            self?.recoveryPhase = .idle
                        }
                    }
                }
            }
        }
        
        do {
            try process.run()
            serverProcess = process
            startHealthCheck()
        } catch {
            NSLog("BackendManager: Failed to start server: \(error)")
            serverStatus = .error
            recoveryPhase = .failed(attempts: restartAttempts, maxAttempts: maxRestartAttempts)
        }
    }
    
    func stopServer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        restartTimer?.invalidate()
        restartTimer = nil
        
        guard let process = serverProcess, process.isRunning else {
            serverProcess = nil
            return
        }
        
        NSLog("BackendManager: Stopping server")
        stopRequested = true
        recoveryPhase = .idle
        terminateGracefully(process: process)
        serverStatus = .stopped
        isServerReady = false
    }
    
    /// Terminates a process gracefully with SIGTERM, then SIGKILL if needed.
    /// Prevents zombie processes by ensuring the process actually exits.
    private func terminateGracefully(process: Process, timeout: TimeInterval = 2.0) {
        process.terminate() // SIGTERM
        
        // Schedule force kill if process doesn't exit gracefully
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard self != nil else { return }
            if process.isRunning {
                NSLog("BackendManager: Process did not terminate gracefully, forcing kill")
                process.interrupt() // SIGINT first (gentler than SIGKILL)
                
                // Final SIGKILL after additional delay if still running
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if process.isRunning {
                        kill(pid_t(process.processIdentifier), SIGKILL)
                    }
                }
            }
        }
    }
    
    /// Attempts to restart the server after an unexpected termination.
    /// Uses exponential backoff and limits total restart attempts.
    private func attemptRestart() {
        guard restartAttempts < maxRestartAttempts else {
            NSLog("BackendManager: Max restart attempts reached, giving up")
            serverStatus = .error
            healthDetail = "Server failed to start after \(maxRestartAttempts) attempts"
            recoveryPhase = .failed(attempts: restartAttempts, maxAttempts: maxRestartAttempts)
            restartAttempts = 0
            restartDelay = 1.0
            return
        }
        
        restartAttempts += 1
        let delay = min(restartDelay, maxRestartDelay)
        restartDelay *= 2 // Exponential backoff
        
        NSLog("BackendManager: Attempting restart #\(restartAttempts) in \(delay)s")
        serverStatus = .starting
        healthDetail = "Restarting (attempt \(restartAttempts)/\(maxRestartAttempts))..."
        recoveryPhase = .retryScheduled(attempt: restartAttempts, maxAttempts: maxRestartAttempts, delay: delay)

        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startServer(isRecoveryAttempt: true)
        }
    }
    
    // MARK: - Health Check
    
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }
    
    private func checkHealth() {
        var request = URLRequest(url: healthCheckURL)
        request.timeoutInterval = BackendConfig.healthCheckTimeout
        if let token = KeychainHelper.loadBackendToken(),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "x-echopanel-token")
        }
        
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
                    self.recoveryPhase = .idle
                    self.restartAttempts = 0
                    self.restartDelay = 1.0
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

#if DEBUG
    func _testSetState(
        isServerReady: Bool,
        serverStatus: ServerStatus,
        healthDetail: String,
        recoveryPhase: RecoveryPhase
    ) {
        self.isServerReady = isServerReady
        self.serverStatus = serverStatus
        self.healthDetail = healthDetail
        self.recoveryPhase = recoveryPhase
    }
#endif

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
        if let token = KeychainHelper.loadBackendToken(),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "x-echopanel-token")
        }

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
            return "base.en"
        }
        // faster-whisper supports Whisper model family names. Keep this conservative.
        let allowed: Set<String> = [
            "tiny", "tiny.en",
            "base", "base.en",
            "small", "small.en",
            "medium", "medium.en",
            "large-v1", "large-v2", "large-v3", "large",
            "distil-large-v2", "distil-medium.en", "distil-small.en", "distil-large-v3",
            "large-v3-turbo", "large-v3-turbo.en"
        ]
        if allowed.contains(value) { return value }
        // Allow HuggingFace model identifiers (they may have / or -)
        if value.contains("/") || value.contains("-") { return value }
        return "base.en"
    }
    
    // MARK: - Launch Strategy
    
    private struct LaunchConfig {
        enum Mode {
            case bundledExecutable
            case pythonModule
        }
        let mode: Mode
        let executable: String?
        let arguments: [String]
        let workingDirectory: String?
    }
    
    private func determineLaunchStrategy() -> LaunchConfig {
        // Priority 1: Bundled PyInstaller executable
        if let bundledExe = findBundledExecutable() {
            return LaunchConfig(
                mode: .bundledExecutable,
                executable: bundledExe,
                arguments: ["--host", serverHost, "--port", "\(serverPort)"],
                workingDirectory: nil
            )
        }
        
        // Priority 2: Python-based launch (development)
        if let serverPath = findDevelopmentServerPath(),
           let pythonPath = findPythonPath(serverDir: serverPath) {
            return LaunchConfig(
                mode: .pythonModule,
                executable: pythonPath,
                arguments: ["-m", "uvicorn", "server.main:app", "--host", serverHost, "--port", "\(serverPort)"],
                workingDirectory: (serverPath as NSString).deletingLastPathComponent
            )
        }
        
        return LaunchConfig(mode: .bundledExecutable, executable: nil, arguments: [], workingDirectory: nil)
    }
    
    private func findBundledExecutable() -> String? {
        // Look for echopanel-server in app Resources
        if let resourcePath = Bundle.main.resourcePath {
            let bundledExe = (resourcePath as NSString).appendingPathComponent("echopanel-server")
            if FileManager.default.fileExists(atPath: bundledExe) {
                return bundledExe
            }
        }
        
        // Look in MacOS directory (alternative location)
        let macOSExe = (Bundle.main.bundlePath as NSString)
            .appendingPathComponent("Contents/MacOS/echopanel-server")
        if FileManager.default.fileExists(atPath: macOSExe) {
            return macOSExe
        }
        
        return nil
    }
    
    // MARK: - Path Discovery (Development Fallback)
    
    private func findDevelopmentServerPath() -> String? {
        // Priority 1: Development path (relative to app)
        var devPath = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        devPath = (devPath as NSString).deletingLastPathComponent
        devPath = (devPath as NSString).deletingLastPathComponent // Go up from .build/debug/
        let serverDir = (devPath as NSString).appendingPathComponent("server")
        if FileManager.default.fileExists(atPath: serverDir) {
            return serverDir
        }
        
        // Priority 2: Hardcoded development path (DEBUG builds only)
        #if DEBUG
        let hardcodedPath = "/Users/pranay/Projects/EchoPanel/server"
        if FileManager.default.fileExists(atPath: hardcodedPath) {
            return hardcodedPath
        }
        #endif
        
        return nil
    }
    
    private func findPythonPath(serverDir: String) -> String? {
        let projectRoot = (serverDir as NSString).deletingLastPathComponent
        
        // Priority 1: Project venv
        let venvPython = (projectRoot as NSString).appendingPathComponent(".venv/bin/python")
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        
        // Priority 2: System Python
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
