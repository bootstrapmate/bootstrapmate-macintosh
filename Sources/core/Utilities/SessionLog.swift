//
//  SessionLog.swift
//  BootstrapMate
//
//  The structured half of a run's logs.
//
//  Every run owns a session directory under the tool's logs root,
//      /Library/Managed Bootstrap/logs/YYYY-MM-DD/HHMMSS/
//  holding bootstrap.log (the human log, written by Logger), events.jsonl
//  (one JSON record per line, appended as the run proceeds) and session.json
//  (the run as a whole, written when it starts and rewritten when it ends).
//  The layout and field names match Cimian's session logger and the Munki
//  fork's, so the same readers work on every managed tool.
//

import Foundation

/// One line of events.jsonl.
struct SessionEvent: Codable {
    var eventId: String
    var sessionId: String
    var timestamp: String
    var level: String
    var eventType: String
    var action: String?
    var status: String?
    var message: String
    var error: String?
    var context: [String: String]?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case sessionId = "session_id"
        case timestamp
        case level
        case eventType = "event_type"
        case action
        case status
        case message
        case error
        case context
    }
}

/// Counts for the run, written into session.json.
struct SessionSummary: Codable {
    var events = 0
    var errors = 0
    var warnings = 0
    var packagesHandled = [String]()

    enum CodingKeys: String, CodingKey {
        case events
        case errors
        case warnings
        case packagesHandled = "packages_handled"
    }
}

/// The record written to session.json.
struct SessionRecord: Codable {
    var sessionId: String
    var startTime: String
    var endTime: String?
    var durationSeconds: Int?
    var runType: String
    var status: String
    var toolVersion: String
    var environment: [String: String]
    var summary: SessionSummary

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case runType = "run_type"
        case status
        case toolVersion = "tool_version"
        case environment
        case summary
    }
}

/// Owns one run's session directory and the two machine-readable files in it.
public final class SessionLog {
    /// Day directories older than this are removed when a run starts.
    public static let retentionDays = 30
    /// Session directories kept across all days, newest first. A tool that runs
    /// often would otherwise accumulate directories faster than the age sweep
    /// removes them, which is the shape that stalls a collection walk.
    public static let maxSessions = 100

    public let sessionId: String
    public let sessionDir: String
    public let logFilePath: String

    private let startTime: Date
    private let runType: String
    private let version: String
    private let eventsHandle: FileHandle?
    private let isoFormatter: ISO8601DateFormatter
    private var summary = SessionSummary()
    private var eventIndex = 0

    /// Creates `logs/YYYY-MM-DD/HHMMSS/`, appending `_2` through `_9` when a
    /// previous run started in the same second. Returns nil when the directory
    /// cannot be created, which leaves the caller to fall back to a flat file.
    public init?(logsDirectory: String, version: String, runType: String, start: Date = Date()) {
        let dayFormatter = SessionLog.formatter("yyyy-MM-dd")
        let timeFormatter = SessionLog.formatter("HHmmss")
        let day = dayFormatter.string(from: start)
        let time = timeFormatter.string(from: start)
        let dayDir = (logsDirectory as NSString).appendingPathComponent(day)

        var chosenDir = (dayDir as NSString).appendingPathComponent(time)
        var chosenName = time
        let fm = FileManager.default
        if fm.fileExists(atPath: chosenDir) {
            var placed = false
            for suffix in 2...9 {
                let candidate = (dayDir as NSString).appendingPathComponent("\(time)_\(suffix)")
                if !fm.fileExists(atPath: candidate) {
                    chosenDir = candidate
                    chosenName = "\(time)_\(suffix)"
                    placed = true
                    break
                }
            }
            if !placed { return nil }
        }
        guard (try? fm.createDirectory(atPath: chosenDir, withIntermediateDirectories: true)) != nil else { return nil }

        self.sessionDir = chosenDir
        self.sessionId = "\(day)-\(chosenName)"
        self.logFilePath = (chosenDir as NSString).appendingPathComponent("bootstrap.log")
        self.startTime = start
        self.runType = runType
        self.version = version
        self.isoFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        let eventsPath = (chosenDir as NSString).appendingPathComponent("events.jsonl")
        fm.createFile(atPath: eventsPath, contents: nil)
        self.eventsHandle = FileHandle(forWritingAtPath: eventsPath)

        writeSessionFile(status: "running")
    }

    /// Appends one record to events.jsonl and keeps the run's counts.
    /// `message` is the same text the human log carries, with any leading
    /// `[TAG]` lifted into the event's type and status.
    public func append(level: String, message: String, date: Date = Date()) {
        let (eventType, status, text) = SessionLog.classify(level: level, message: message)
        switch level {
        case "ERROR": summary.errors += 1
        case "WARN": summary.warnings += 1
        default: break
        }
        summary.events += 1
        eventIndex += 1

        let event = SessionEvent(
            eventId: "\(sessionId)-\(String(format: "%05d", eventIndex))",
            sessionId: sessionId,
            timestamp: isoFormatter.string(from: date),
            level: level,
            eventType: eventType,
            action: nil,
            status: status,
            message: text,
            error: level == "ERROR" ? text : nil,
            context: nil
        )
        guard let handle = eventsHandle,
              let data = try? SessionLog.eventEncoder.encode(event),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        handle.write(Data(line.utf8))
    }

    /// Rewrites session.json with the run's outcome.
    public func finish(status: String? = nil, end: Date = Date()) {
        let resolved = status ?? (summary.errors > 0 ? "partial_failure" : "completed")
        writeSessionFile(status: resolved, end: end)
        try? eventsHandle?.close()
    }

    // MARK: - Files

    private func writeSessionFile(status: String, end: Date? = nil) {
        let record = SessionRecord(
            sessionId: sessionId,
            startTime: isoFormatter.string(from: startTime),
            endTime: end.map { isoFormatter.string(from: $0) },
            durationSeconds: end.map { Int($0.timeIntervalSince(startTime).rounded()) },
            runType: runType,
            status: status,
            toolVersion: version,
            environment: SessionLog.environment(),
            summary: summary
        )
        guard let data = try? SessionLog.sessionEncoder.encode(record) else { return }
        let path = (sessionDir as NSString).appendingPathComponent("session.json")
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // MARK: - Classification

    /// Lifts a leading `[TAG]` off a message into an event type and status, so
    /// the structured stream carries what the human log carries in prose.
    static func classify(level: String, message: String) -> (String, String?, String) {
        guard message.hasPrefix("["), let close = message.firstIndex(of: "]") else {
            return (level == "ERROR" ? "error" : "message", level == "ERROR" ? "FAILED" : nil, message)
        }
        let tag = String(message[message.index(after: message.startIndex)..<close]).uppercased()
        var text = String(message[message.index(after: close)...])
        if text.hasPrefix(" ") { text.removeFirst() }
        switch tag {
        case "SECTION": return ("section", nil, text)
        case "PROGRESS", "SUB-PROGRESS": return ("progress", "PROGRESS", text)
        case "SUCCESS": return ("item", "SUCCESS", text)
        case "SKIPPED": return ("item", "SKIPPED", text)
        case "COMPLETION": return ("session_end", "SUCCESS", text)
        case "OUTPUT": return ("output", nil, text)
        default:
            return (level == "ERROR" ? "error" : "message", level == "ERROR" ? "FAILED" : nil, message)
        }
    }

    // MARK: - Retention

    /// Removes day directories older than the retention window, then the oldest
    /// session directories beyond the cap. Loose per-run files left at the logs
    /// root by the flat layout this replaced are swept separately, by the same
    /// age rule, in `Logger.pruneLogFiles`.
    @discardableResult
    public static func prune(logsDirectory: String, now: Date = Date()) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: logsDirectory) else { return 0 }
        var removed = 0

        let dayFormatter = formatter("yyyy-MM-dd")
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else { return 0 }
        let dayDirs = entries.filter { isDayDirectory($0, in: logsDirectory) }.sorted(by: >)

        for day in dayDirs {
            let path = (logsDirectory as NSString).appendingPathComponent(day)
            guard let date = dayFormatter.date(from: day) else { continue }
            if date < cutoff, (try? fm.removeItem(atPath: path)) != nil { removed += 1 }
        }

        // Cap the session directories that survived the age sweep, newest first.
        var sessions: [String] = []
        for day in dayDirs.sorted(by: >) {
            let dayPath = (logsDirectory as NSString).appendingPathComponent(day)
            guard let names = try? fm.contentsOfDirectory(atPath: dayPath) else { continue }
            for name in names.sorted(by: >) {
                let full = (dayPath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue { sessions.append(full) }
            }
        }
        if sessions.count > maxSessions {
            for path in sessions[maxSessions...] where (try? fm.removeItem(atPath: path)) != nil { removed += 1 }
        }

        return removed
    }

    static func isDayDirectory(_ name: String, in parent: String) -> Bool {
        guard name.count == 10, formatter("yyyy-MM-dd").date(from: name) != nil else { return false }
        var isDir: ObjCBool = false
        let full = (parent as NSString).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Helpers

    static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    static let eventEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()

    static let sessionEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        return e
    }()

    static func environment() -> [String: String] {
        let info = ProcessInfo.processInfo
        return [
            "hostname": Host.current().localizedName ?? "Unknown",
            "os_version": info.operatingSystemVersionString,
            "user": NSUserName(),
            "pid": String(info.processIdentifier),
            "command_line": CommandLine.arguments.joined(separator: " ")
        ]
    }
}
