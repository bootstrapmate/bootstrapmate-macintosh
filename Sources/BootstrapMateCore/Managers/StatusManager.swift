//
//  StatusManager.swift
//  BootstrapMate
//
//  Tracks installation status via plist and JSON for MDM detection.
//  macOS equivalent of Windows StatusManager.cs using property lists.
//

import Foundation

public enum InstallationStage: String, Codable {
    case starting = "Starting"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case skipped = "Skipped"
}

public enum InstallationPhase: String, Codable {
    case preflight = "Preflight"
    case setupAssistant = "SetupAssistant"
    case userland = "Userland"
}

public struct InstallationStatus: Codable {
    public var stage: InstallationStage
    public var startTime: String
    public var completionTime: String
    public var exitCode: Int
    public var version: String
    public var phase: InstallationPhase
    public var architecture: String
    public var bootstrapUrl: String
    public var lastError: String
    public var runId: String
    
    public init(
        stage: InstallationStage = .starting,
        startTime: String = "",
        completionTime: String = "",
        exitCode: Int = 0,
        version: String = "",
        phase: InstallationPhase = .setupAssistant,
        architecture: String = "",
        bootstrapUrl: String = "",
        lastError: String = "",
        runId: String = ""
    ) {
        self.stage = stage
        self.startTime = startTime
        self.completionTime = completionTime
        self.exitCode = exitCode
        self.version = version
        self.phase = phase
        self.architecture = architecture
        self.bootstrapUrl = bootstrapUrl
        self.lastError = lastError
        self.runId = runId
    }
}

public final class StatusManager {
    nonisolated(unsafe) public static let shared = StatusManager()
    
    // Paths for status persistence
    // Main status plist in standard Preferences location (matches preflight.sh)
    private let statusPlistPath = "/Library/Preferences/com.github.bootstrapmate.plist"
    // Support directory for logs and JSON status
    private let baseDirectory = "/Library/Managed Bootstrap"
    private let statusJsonPath = "/Library/Managed Bootstrap/status.json"
    
    private var currentRunId: String
    private var bootstrapUrl: String = ""
    private var version: String = "1.0.0"
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    private init() {
        currentRunId = UUID().uuidString
    }
    
    // MARK: - Public API
    
    public func initialize(bootstrapUrl: String = "", version: String = "1.0.0") {
        self.bootstrapUrl = bootstrapUrl
        self.version = version
        self.currentRunId = UUID().uuidString
        
        // Ensure status directory exists
        ensureDirectoryExists()
        
        Logger.debug("StatusManager initialized with version \(version), runId: \(currentRunId)")
    }
    
    public func getCurrentRunId() -> String {
        return currentRunId
    }
    
    public func setPhaseStatus(
        phase: InstallationPhase,
        stage: InstallationStage,
        errorMessage: String = "",
        exitCode: Int = 0
    ) {
        var status = InstallationStatus(
            stage: stage,
            exitCode: exitCode,
            version: version,
            phase: phase,
            architecture: getArchitecture(),
            bootstrapUrl: bootstrapUrl,
            lastError: errorMessage,
            runId: currentRunId
        )
        
        // Set timestamps based on stage
        switch stage {
        case .starting, .running:
            status.startTime = dateFormatter.string(from: Date())
        case .completed, .failed, .skipped:
            if status.startTime.isEmpty {
                status.startTime = dateFormatter.string(from: Date())
            }
            status.completionTime = dateFormatter.string(from: Date())
        }
        
        // Write to plist
        writePlistStatus(phase: phase, status: status)
        
        // Write to JSON for troubleshooting
        writeJsonStatus(phase: phase, status: status)
        
        let logMessage = "Status updated: \(phase.rawValue) = \(stage.rawValue)" +
            (exitCode != 0 ? " (ExitCode: \(exitCode))" : "") +
            (!errorMessage.isEmpty ? " - \(errorMessage)" : "")
        Logger.debug(logMessage)
    }
    
    public func writeSuccessfulCompletionPlist() {
        let versionData: [String: Any] = [
            "LastRunVersion": version,
            "LastUpdated": dateFormatter.string(from: Date()),
            "Architecture": getArchitecture()
        ]
        
        do {
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: versionData,
                format: .xml,
                options: 0
            )
            try plistData.write(to: URL(fileURLWithPath: statusPlistPath))
            Logger.info("Successful completion: LastRunVersion \(version) written to \(statusPlistPath)")
        } catch {
            Logger.warning("Failed to write completion status to plist: \(error.localizedDescription)")
        }
    }
    
    public func getLastRunVersion() -> String? {
        guard FileManager.default.fileExists(atPath: statusPlistPath),
              let data = FileManager.default.contents(atPath: statusPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let lastVersion = plist["LastRunVersion"] as? String else {
            return nil
        }
        return lastVersion
    }
    
    /// Checks if BootstrapMate has successfully completed by looking for LastRunVersion
    /// Used by preflight.sh to decide whether to run BootstrapMate again
    public func hasCompletedSuccessfully() -> Bool {
        return getLastRunVersion() != nil
    }
    
    public func getPhaseStatus(phase: InstallationPhase) -> InstallationStatus? {
        guard FileManager.default.fileExists(atPath: statusPlistPath),
              let data = FileManager.default.contents(atPath: statusPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]],
              let phaseData = plist[phase.rawValue] else {
            return nil
        }
        
        return InstallationStatus(
            stage: InstallationStage(rawValue: phaseData["Stage"] as? String ?? "") ?? .starting,
            startTime: phaseData["StartTime"] as? String ?? "",
            completionTime: phaseData["CompletionTime"] as? String ?? "",
            exitCode: phaseData["ExitCode"] as? Int ?? 0,
            version: phaseData["Version"] as? String ?? "",
            phase: phase,
            architecture: phaseData["Architecture"] as? String ?? "",
            bootstrapUrl: phaseData["BootstrapUrl"] as? String ?? "",
            lastError: phaseData["LastError"] as? String ?? "",
            runId: phaseData["RunId"] as? String ?? ""
        )
    }
    
    public func cleanupOldStatuses(maxAge: TimeInterval) {
        for phase in [InstallationPhase.preflight, .setupAssistant, .userland] {
            guard let status = getPhaseStatus(phase: phase),
                  status.stage != .running,
                  !status.completionTime.isEmpty,
                  let completionDate = dateFormatter.date(from: status.completionTime),
                  Date().timeIntervalSince(completionDate) > maxAge else {
                continue
            }
            
            deletePhaseStatus(phase: phase)
            Logger.debug("Cleaned up old status for \(phase.rawValue)")
        }
    }
    
    // MARK: - Private Methods
    
    private func ensureDirectoryExists() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: baseDirectory) {
            do {
                try fileManager.createDirectory(atPath: baseDirectory, withIntermediateDirectories: true)
            } catch {
                Logger.warning("Failed to create status directory: \(error.localizedDescription)")
            }
        }
    }
    
    private func getArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let chars = machineMirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8($0))) }
        let identifier = String(chars)
        return identifier.contains("arm64") ? "ARM64" : "X64"
    }
    
    private func writePlistStatus(phase: InstallationPhase, status: InstallationStatus) {
        var allStatuses: [String: [String: Any]] = [:]
        
        // Read existing statuses
        if FileManager.default.fileExists(atPath: statusPlistPath),
           let data = FileManager.default.contents(atPath: statusPlistPath),
           let existing = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]] {
            allStatuses = existing
        }
        
        // Update the specific phase
        allStatuses[phase.rawValue] = [
            "Stage": status.stage.rawValue,
            "StartTime": status.startTime,
            "CompletionTime": status.completionTime,
            "ExitCode": status.exitCode,
            "Version": status.version,
            "Phase": status.phase.rawValue,
            "Architecture": status.architecture,
            "BootstrapUrl": status.bootstrapUrl,
            "LastError": status.lastError,
            "RunId": status.runId
        ]
        
        do {
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: allStatuses,
                format: .xml,
                options: 0
            )
            try plistData.write(to: URL(fileURLWithPath: statusPlistPath))
        } catch {
            Logger.warning("Failed to write status plist: \(error.localizedDescription)")
        }
    }
    
    private func writeJsonStatus(phase: InstallationPhase, status: InstallationStatus) {
        var allStatuses: [String: InstallationStatus] = [:]
        
        // Read existing statuses
        if FileManager.default.fileExists(atPath: statusJsonPath),
           let data = FileManager.default.contents(atPath: statusJsonPath),
           let existing = try? JSONDecoder().decode([String: InstallationStatus].self, from: data) {
            allStatuses = existing
        }
        
        // Update the specific phase
        allStatuses[phase.rawValue] = status
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(allStatuses)
            try jsonData.write(to: URL(fileURLWithPath: statusJsonPath))
        } catch {
            Logger.warning("Failed to write status JSON: \(error.localizedDescription)")
        }
    }
    
    private func deletePhaseStatus(phase: InstallationPhase) {
        // Remove from plist
        if FileManager.default.fileExists(atPath: statusPlistPath),
           let data = FileManager.default.contents(atPath: statusPlistPath),
           var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]] {
            plist.removeValue(forKey: phase.rawValue)
            if let plistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? plistData.write(to: URL(fileURLWithPath: statusPlistPath))
            }
        }
        
        // Remove from JSON
        if FileManager.default.fileExists(atPath: statusJsonPath),
           let data = FileManager.default.contents(atPath: statusJsonPath),
           var json = try? JSONDecoder().decode([String: InstallationStatus].self, from: data) {
            json.removeValue(forKey: phase.rawValue)
            if let encoder = try? JSONEncoder().encode(json) {
                try? encoder.write(to: URL(fileURLWithPath: statusJsonPath))
            }
        }
    }
}
