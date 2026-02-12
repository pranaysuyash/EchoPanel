import Foundation

/// BetaGatingManager manages beta access control including invite codes, session limits, and upgrade prompts.
final class BetaGatingManager: ObservableObject {
    
    static let shared = BetaGatingManager()
    
    @Published var isBetaAccessGranted: Bool = false
    @Published var validatedInviteCode: String?
    @Published var sessionsThisMonth: Int = 0
    @Published var sessionLimit: Int = 20
    @Published var monthStartDate: Date?
    @Published var shouldShowUpgradePrompt: Bool = false
    
    private let fileManager = FileManager.default
    private var betaDataFile: URL?
    
    private let inviteCodes = [
        "ECHOPANEL-BETA-2024",
        "ECHOPANEL-EARLY-ACCESS",
        "ECHOPANEL-ALPHA-V2"
    ]
    
    struct BetaData: Codable {
        var inviteCode: String?
        var sessionsThisMonth: Int
        var monthStartDate: Date?
        var isBetaAccessGranted: Bool
        
        static let empty = BetaData(inviteCode: nil, sessionsThisMonth: 0, monthStartDate: nil, isBetaAccessGranted: false)
    }
    
    private var currentData: BetaData = .empty
    
    private init() {
        setupDataFile()
        loadData()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionEnded(_:)),
            name: .sessionEnded,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleSessionEnded(_ notification: Notification) {
        guard isBetaAccessGranted else { return }
        
        NSLog("BetaGatingManager: Session ended, incrementing count")
        incrementSessionCount()
    }
    
    private func setupDataFile() {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("BetaGatingManager: Failed to get Application Support directory")
            return
        }
        
        let bundleId = Bundle.main.bundleIdentifier ?? "com.echopanel"
        let supportDir = appSupport.appendingPathComponent(bundleId)
        betaDataFile = supportDir.appendingPathComponent("beta_access.json")
        
        NSLog("BetaGatingManager: Data file: \(betaDataFile?.path ?? "nil")")
    }
    
    private func loadData() {
        guard let dataFile = betaDataFile else { return }
        
        guard fileManager.fileExists(atPath: dataFile.path) else {
            NSLog("BetaGatingManager: No existing beta data file")
            return
        }
        
        do {
            let data = try Data(contentsOf: dataFile)
            currentData = try JSONDecoder().decode(BetaData.self, from: data)
            
            isBetaAccessGranted = currentData.isBetaAccessGranted
            validatedInviteCode = currentData.inviteCode
            sessionsThisMonth = currentData.sessionsThisMonth
            monthStartDate = currentData.monthStartDate
            
            checkMonthReset()
            
            NSLog("BetaGatingManager: Loaded data - access: \(isBetaAccessGranted), sessions: \(sessionsThisMonth)")
        } catch {
            NSLog("BetaGatingManager: Failed to load beta data: \(error)")
        }
    }
    
    private func saveData() {
        guard let dataFile = betaDataFile else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(currentData)
            try data.write(to: dataFile)
            NSLog("BetaGatingManager: Saved beta data")
        } catch {
            NSLog("BetaGatingManager: Failed to save beta data: \(error)")
        }
    }
    
    func validateInviteCode(_ code: String) -> Bool {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        let isValid = inviteCodes.contains(trimmedCode)
        
        if isValid {
            currentData.inviteCode = trimmedCode
            currentData.isBetaAccessGranted = true
            validatedInviteCode = trimmedCode
            isBetaAccessGranted = true
            saveData()
            NSLog("BetaGatingManager: Invite code validated: \(trimmedCode)")
        } else {
            NSLog("BetaGatingManager: Invalid invite code: \(trimmedCode)")
        }
        
        return isValid
    }
    
    func checkMonthReset() {
        let calendar = Calendar.current
        let now = Date()
        
        guard let startDate = currentData.monthStartDate else {
            currentData.monthStartDate = calendar.startOfMonth(for: now)
            return
        }
        
        let currentMonthStart = calendar.startOfMonth(for: now)
        
        if currentMonthStart > startDate {
            currentData.sessionsThisMonth = 0
            currentData.monthStartDate = currentMonthStart
            sessionsThisMonth = 0
            monthStartDate = currentMonthStart
            shouldShowUpgradePrompt = false
            saveData()
            NSLog("BetaGatingManager: Month reset - sessions reset to 0")
        }
    }
    
    func incrementSessionCount() {
        checkMonthReset()
        
        currentData.sessionsThisMonth += 1
        sessionsThisMonth = currentData.sessionsThisMonth
        
        if sessionsThisMonth >= sessionLimit {
            shouldShowUpgradePrompt = true
            NSLog("BetaGatingManager: Session limit reached (\(sessionsThisMonth)/\(sessionLimit))")
        }
        
        saveData()
    }
    
    func canStartSession() -> Bool {
        if isBetaAccessGranted {
            return true
        }
        
        checkMonthReset()
        
        if sessionsThisMonth >= sessionLimit {
            shouldShowUpgradePrompt = true
            return false
        }
        
        return true
    }
    
    func sessionsRemaining() -> Int {
        return max(0, sessionLimit - sessionsThisMonth)
    }
    
    func resetUpgradePrompt() {
        shouldShowUpgradePrompt = false
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components)!
    }
}
