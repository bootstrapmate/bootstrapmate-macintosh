//
//  Logger.swift
//  BootstrapMate
//
//  Comprehensive logging with file output, levels, and os_log integration.
//  macOS equivalent of Windows Logger.cs.
//
//  File lines follow the shared management-tool convention:
//  "[yyyy-MM-dd HH:mm:ss] LEVEL message" in local time, where LEVEL is one of
//  DEBUG, INFO, WARN or ERROR padded to five characters. Console output keeps
//  its own styling and is not the log.
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

    /// Level label written to the log file. Only DEBUG, INFO, WARN and ERROR
    /// are valid on disk; SUCCESS is an INFO line.
    var fileLabel: String {
        switch self {
        case .debug: return "DEBUG"
        case .info, .success: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

public final class Logger {
    nonisolated(unsafe) private static var shared: Logger?

    /// Log files older than this are removed at the start of every run.
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private static let fileTimestampFormat = "yyyy-MM-dd HH:mm:ss"

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

        self.dateFormatter = Logger.makeTimestampFormatter()

        // Create log directory if needed
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDirectory) {
            try? fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
        }

        // Retention: drop log files older than the retention window before opening a new one
        let prunedCount = Logger.pruneLogFiles(in: logDirectory, olderThan: Logger.retentionInterval)

        // Create log file with timestamp (matching Windows format: YYYY-MM-DD-HHmmss.log)
        let logFileName = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd-HHmmss"
            $0.locale = Locale(identifier: "en_US_POSIX")
        }.string(from: Date()) + ".log"

        self.logFilePath = (logDirectory as NSString).appendingPathComponent(logFileName)

        // Create file and get handle
        fileManager.createFile(atPath: logFilePath, contents: nil)
        self.fileHandle = FileHandle(forWritingAtPath: logFilePath)

        // Write session header
        writeToFile(level: .info, "=== BootstrapMate Session Started ===")
        writeToFile(level: .info, "Version: \(version)")
        writeToFile(level: .info, "Session Start Time: \(dateFormatter.string(from: sessionStartTime))")
        writeToFile(level: .info, "Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        writeToFile(level: .info, "User: \(NSUserName())")
        writeToFile(level: .info, "Machine: \(Host.current().localizedName ?? "Unknown")")
        writeToFile(level: .info, "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        writeToFile(level: .info, "Architecture: \(getArchitecture())")
        writeToFile(level: .info, "Working Directory: \(FileManager.default.currentDirectoryPath)")
        writeToFile(level: .info, "Command Line: \(CommandLine.arguments.joined(separator: " "))")
        writeToFile(level: .info, "Verbose Console: \(verboseConsole)")
        writeToFile(level: .info, "Silent Mode: \(silentMode)")
        if prunedCount > 0 {
            writeToFile(level: .info, "Removed \(prunedCount) log file(s) older than 30 days")
        }
    }

    public static func initialize(
        logDirectory: String = BootstrapMateConstants.logsDirectory,
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

    /// Console output captured from a script or installer, one record per
    /// line, tagged `[OUTPUT]` and named for its source so a reader can tell
    /// the tool's own lines from what it ran: stdout at INFO, stderr at WARN.
    /// Blank lines are dropped by the writer.
    public static func output(from source: String, stdout: String? = nil, stderr: String? = nil) {
        let name = (source as NSString).lastPathComponent
        if let text = stdout, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log(level: .info, message: prefixLines(text, with: "[OUTPUT] \(name): "))
        }
        if let text = stderr, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log(level: .warning, message: prefixLines(text, with: "[OUTPUT] \(name): "))
        }
    }

    static func prefixLines(_ text: String, with prefix: String) -> String {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    /// Legacy compatibility method
    public static func log(_ message: String) {
        info(message)
    }

    // MARK: - Structured Output Methods

    public static func writeHeader(_ title: String) {
        let timestamp = shared?.dateFormatter.string(from: Date()) ?? ""
        shared?.writeToFile(level: .info, "=== \(title) ===")
        guard shared?.silentMode != true else { return }
        print()
        print("══ \(title) ══")
        print("Started: \(timestamp)")
    }

    public static func writeSection(_ section: String) {
        shared?.writeToFile(level: .info, "[SECTION] \(section)")
        guard shared?.silentMode != true else { return }
        print()
        print("[>] \(section)")
    }

    public static func writeProgress(_ operation: String, _ item: String) {
        shared?.writeToFile(level: .info, "[PROGRESS] \(operation): \(item)")
        guard shared?.silentMode != true else { return }
        print("   [*] \(operation): \(item)")
    }

    public static func writeSubProgress(_ status: String, _ details: String = "") {
        let message = details.isEmpty ? status : "\(status): \(details)"
        shared?.writeToFile(level: .info, "[SUB-PROGRESS] \(message)")
        guard shared?.silentMode != true else { return }
        print("      • \(message)")
    }

    public static func writeSuccess(_ message: String) {
        shared?.writeToFile(level: .info, "[SUCCESS] \(message)")
        guard shared?.silentMode != true else { return }
        print("      ✓ \(message)")
    }

    public static func writeWarning(_ message: String) {
        shared?.writeToFile(level: .warning, message)
        guard shared?.silentMode != true else { return }
        print("      ⚠ \(message)")
    }

    public static func writeError(_ message: String) {
        shared?.writeToFile(level: .error, message)
        guard shared?.silentMode != true else { return }
        print("      ✗ \(message)")
    }

    public static func writeSkipped(_ message: String) {
        shared?.writeToFile(level: .info, "[SKIPPED] \(message)")
        guard shared?.silentMode != true else { return }
        print("      - \(message)")
    }

    public static func writeCompletion(_ message: String) {
        let timestamp = shared?.dateFormatter.string(from: Date()) ?? ""
        let duration = shared?.getSessionDuration() ?? 0
        shared?.writeToFile(level: .info, "[COMPLETION] \(message) (Total Duration: \(String(format: "%.1f", duration))s)")
        guard shared?.silentMode != true else { return }
        print()
        print("✓ \(message)")
        print("Completed: \(timestamp)")
        print("Total Duration: \(String(format: "%.1f", duration / 60)) minutes (\(String(format: "%.1f", duration)) seconds)")
        print()
    }

    public static func writeSessionSummary() {
        let duration = shared?.getSessionDuration() ?? 0
        shared?.writeToFile(level: .info, "=== BootstrapMate Session Ended === (Duration: \(String(format: "%.1f", duration))s)")
        shared?.writeToFile(level: .info, "Total Session Duration: \(String(format: "%.2f", duration / 60)) minutes")
    }

    public static func getLogFilePath() -> String? {
        return shared?.logFilePath
    }

    public static func getSessionDuration() -> TimeInterval {
        return shared?.getSessionDuration() ?? 0
    }

    // MARK: - Line Format and Retention

    /// Formats one log file line: "[yyyy-MM-dd HH:mm:ss] LEVEL message".
    /// The level label is padded to five characters so messages align.
    static func formatLine(level: LogLevel, message: String, date: Date, formatter: DateFormatter? = nil) -> String {
        let timestampFormatter = formatter ?? makeTimestampFormatter()
        let label = level.fileLabel.padding(toLength: 5, withPad: " ", startingAt: 0)
        return "[\(timestampFormatter.string(from: date))] \(label) \(message)"
    }

    /// One stamped record per non-blank line of `message`, in order. Carriage
    /// returns are treated as line breaks so captured console output splits
    /// cleanly, and trailing whitespace on each line is dropped.
    static func fileLines(level: LogLevel, message: String, date: Date, formatter: DateFormatter? = nil) -> [String] {
        let timestampFormatter = formatter ?? makeTimestampFormatter()
        return message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { formatLine(level: level, message: $0, date: date, formatter: timestampFormatter) }
    }

    /// Removes ".log" files in `directory` whose modification date is older
    /// than `maxAge` relative to `now`. Non-recursive and error-tolerant:
    /// a file that cannot be inspected or removed is skipped. Returns the
    /// number of files removed.
    @discardableResult
    static func pruneLogFiles(in directory: String, olderThan maxAge: TimeInterval, now: Date = Date()) -> Int {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return 0 }

        let cutoff = now.addingTimeInterval(-maxAge)
        var removed = 0

        for entry in entries where entry.hasSuffix(".log") {
            let path = (directory as NSString).appendingPathComponent(entry)
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let modified = attributes[.modificationDate] as? Date,
                  modified < cutoff else { continue }

            if (try? fileManager.removeItem(atPath: path)) != nil {
                removed += 1
            }
        }

        return removed
    }

    private static func makeTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = fileTimestampFormat
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }

    // MARK: - Private Methods

    private static func log(level: LogLevel, message: String) {
        // Ensure logger is initialized with defaults if not already
        if shared == nil {
            initialize()
        }

        guard let logger = shared else { return }

        // Always write to log file with full detail
        logger.writeToFile(level: level, message)

        // Write to os_log
        logger.writeToOSLog(level: level, message: message)

        // Write to console based on level and verbose setting
        logger.writeToConsole(level: level, message: message)
    }

    private func writeToFile(level: LogLevel, _ message: String) {
        // Every physical line in the file carries its own stamp and level: a
        // message with embedded newlines is written as one record per line,
        // and blank lines are dropped, so nothing in the file is ever unstamped.
        let entry = Logger.fileLines(level: level, message: message, date: Date(), formatter: dateFormatter)
        guard !entry.isEmpty, let data = (entry.joined(separator: "\n") + "\n").data(using: .utf8) else { return }
        fileHandle?.write(data)
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
        case .debug: return ("[~]", "gray")
        case .info: return ("[i]", nil)
        case .warning: return ("[!]", "yellow")
        case .error: return ("[x]", "red")
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
