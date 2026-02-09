//
//  Logger.swift
//  BootstrapMate
//
//  Comprehensive logging with file output, levels, and os_log integration.
//  macOS equivalent of Windows Logger.cs.
//

import Foundation
import os.log

public enum LogLevel: String, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case success = "SUCCESS"
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warning, .error, .success]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public final class Logger {
    nonisolated(unsafe) private static var shared: Logger?
    
    private let logDirectory: String
    private let logFilePath: String
    private var verboseConsole: Bool
    private var silentMode: Bool
    private let sessionStartTime: Date
    private let osLog: OSLog
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    
    // MARK: - Initialization
    
    private init(logDirectory: String, version: String, verboseConsole: Bool, silentMode: Bool) {
        self.logDirectory = logDirectory
        self.verboseConsole = verboseConsole
        self.silentMode = silentMode
        self.sessionStartTime = Date()
        self.osLog = OSLog(subsystem: "com.github.bootstrapmate", category: "general")
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Create log directory if needed
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDirectory) {
            try? fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
        }
        
        // Create log file with timestamp (matching Windows format: YYYY-MM-DD-HHmmss.log)
        let logFileName = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd-HHmmss"
        }.string(from: Date()) + ".log"
        
        self.logFilePath = (logDirectory as NSString).appendingPathComponent(logFileName)
        
        // Create file and get handle
        fileManager.createFile(atPath: logFilePath, contents: nil)
        self.fileHandle = FileHandle(forWritingAtPath: logFilePath)
        
        // Write session header
        writeToFile("=== BootstrapMate Session Started ===")
        writeToFile("Version: \(version)")
        writeToFile("Session Start Time: \(dateFormatter.string(from: sessionStartTime))")
        writeToFile("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        writeToFile("User: \(NSUserName())")
        writeToFile("Machine: \(Host.current().localizedName ?? "Unknown")")
        writeToFile("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        writeToFile("Architecture: \(getArchitecture())")
        writeToFile("Working Directory: \(FileManager.default.currentDirectoryPath)")
        writeToFile("Command Line: \(CommandLine.arguments.joined(separator: " "))")
        writeToFile("Verbose Console: \(verboseConsole)")
        writeToFile("Silent Mode: \(silentMode)")
    }
    
    public static func initialize(
        logDirectory: String = "/Library/Managed Bootstrap/logs",
        version: String = "Unknown",
        verboseConsole: Bool = false,
        silentMode: Bool = false
    ) {
        shared = Logger(
            logDirectory: logDirectory,
            version: version,
            verboseConsole: verboseConsole,
            silentMode: silentMode
        )
    }
    
    // MARK: - Public Logging Methods
    
    public static func debug(_ message: String) {
        log(level: .debug, message: message)
    }
    
    public static func info(_ message: String) {
        log(level: .info, message: message)
    }
    
    public static func warning(_ message: String) {
        log(level: .warning, message: message)
    }
    
    public static func error(_ message: String) {
        log(level: .error, message: message)
    }
    
    public static func success(_ message: String) {
        log(level: .success, message: message)
    }
    
    /// Legacy compatibility method
    public static func log(_ message: String) {
        info(message)
    }
    
    // MARK: - Structured Output Methods
    
    public static func writeHeader(_ title: String) {
        let timestamp = shared?.dateFormatter.string(from: Date()) ?? ""
        shared?.writeToFile("=== \(title) === (Started: \(timestamp))")
        guard shared?.silentMode != true else { return }
        print()
        print("══ \(title) ══")
        print("Started: \(timestamp)")
    }
    
    public static func writeSection(_ section: String) {
        shared?.writeToFile("[SECTION] \(section)")
        guard shared?.silentMode != true else { return }
        print()
        print("[>] \(section)")
    }
    
    public static func writeProgress(_ operation: String, _ item: String) {
        shared?.writeToFile("[PROGRESS] \(operation): \(item)")
        guard shared?.silentMode != true else { return }
        print("   [*] \(operation): \(item)")
    }
    
    public static func writeSubProgress(_ status: String, _ details: String = "") {
        let message = details.isEmpty ? status : "\(status): \(details)"
        shared?.writeToFile("[SUB-PROGRESS] \(message)")
        guard shared?.silentMode != true else { return }
        print("      • \(message)")
    }
    
    public static func writeSuccess(_ message: String) {
        shared?.writeToFile("[SUCCESS] \(message)")
        guard shared?.silentMode != true else { return }
        print("      ✓ \(message)")
    }
    
    public static func writeWarning(_ message: String) {
        shared?.writeToFile("[WARNING] \(message)")
        guard shared?.silentMode != true else { return }
        print("      ⚠ \(message)")
    }
    
    public static func writeError(_ message: String) {
        shared?.writeToFile("[ERROR] \(message)")
        guard shared?.silentMode != true else { return }
        print("      ✗ \(message)")
    }
    
    public static func writeSkipped(_ message: String) {
        shared?.writeToFile("[SKIPPED] \(message)")
        guard shared?.silentMode != true else { return }
        print("      - \(message)")
    }
    
    public static func writeCompletion(_ message: String) {
        let timestamp = shared?.dateFormatter.string(from: Date()) ?? ""
        let duration = shared?.getSessionDuration() ?? 0
        shared?.writeToFile("[COMPLETION] \(message) (Completed: \(timestamp), Total Duration: \(String(format: "%.1f", duration))s)")
        guard shared?.silentMode != true else { return }
        print()
        print("✓ \(message)")
        print("Completed: \(timestamp)")
        print("Total Duration: \(String(format: "%.1f", duration / 60)) minutes (\(String(format: "%.1f", duration)) seconds)")
        print()
    }
    
    public static func writeSessionSummary() {
        let duration = shared?.getSessionDuration() ?? 0
        let timestamp = shared?.dateFormatter.string(from: Date()) ?? ""
        shared?.writeToFile("=== BootstrapMate Session Ended === (Duration: \(String(format: "%.1f", duration))s)")
        shared?.writeToFile("Session End Time: \(timestamp)")
        shared?.writeToFile("Total Session Duration: \(String(format: "%.2f", duration / 60)) minutes")
    }
    
    public static func getLogFilePath() -> String? {
        return shared?.logFilePath
    }
    
    public static func getSessionDuration() -> TimeInterval {
        return shared?.getSessionDuration() ?? 0
    }
    
    // MARK: - Private Methods
    
    private static func log(level: LogLevel, message: String) {
        // Ensure logger is initialized with defaults if not already
        if shared == nil {
            initialize()
        }
        
        guard let logger = shared else { return }
        
        // Always write to log file with full detail
        logger.writeToFile("[\(level.rawValue)] \(message)")
        
        // Write to os_log
        logger.writeToOSLog(level: level, message: message)
        
        // Write to console based on level and verbose setting
        logger.writeToConsole(level: level, message: message)
    }
    
    private func writeToFile(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        
        if let data = logEntry.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
    
    private func writeToOSLog(level: LogLevel, message: String) {
        let osLogType: OSLogType
        switch level {
        case .debug: osLogType = .debug
        case .info: osLogType = .info
        case .warning: osLogType = .default
        case .error: osLogType = .error
        case .success: osLogType = .info
        }
        os_log("%{public}@", log: osLog, type: osLogType, message)
    }
    
    private func writeToConsole(level: LogLevel, message: String) {
        // Skip console output in silent mode
        guard !silentMode else { return }
        
        // Only show debug messages in verbose mode
        if level == .debug && !verboseConsole { return }
        
        let (icon, _) = getDisplayFormat(level: level)
        print("\(icon) \(message)")
        fflush(stdout)
    }
    
    private func getDisplayFormat(level: LogLevel) -> (String, String?) {
        switch level {
        case .debug: return ("[DBG]", "gray")
        case .info: return ("[i]", nil)
        case .warning: return ("[!]", "yellow")
        case .error: return ("[X]", "red")
        case .success: return ("[+]", "green")
        }
    }
    
    private func getSessionDuration() -> TimeInterval {
        return Date().timeIntervalSince(sessionStartTime)
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
    
    deinit {
        fileHandle?.closeFile()
    }
}

// MARK: - Helper Extensions

private extension DateFormatter {
    func apply(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}
