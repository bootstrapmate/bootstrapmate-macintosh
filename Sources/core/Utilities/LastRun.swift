//
//  LastRun.swift
//  BootstrapMate
//
//  A durable summary of the most recent run, kept outside the session
//  directories so it survives log retention and can be read by anything that
//  can run a shell command, such as an MDM custom attribute:
//
//      /Library/Managed Bootstrap/last-run.json
//
//  It is written when a run starts, with status "running", so a run that
//  crashes or is killed still leaves evidence, and rewritten with the final
//  status when the run ends. `managedbootstrapinstall --last-run` prints it as
//  one line.
//

import Foundation

/// Where one item ran.
public enum RunItemStage: String, Codable, Sendable {
    case setupassistant
    case userland
}

/// What happened to one item.
public enum RunItemResult: String, Codable, Sendable {
    case installed
    case skipped
    case failed
}

/// One item's outcome, in the order the run reached it.
public struct RunItem: Codable, Equatable, Sendable {
    public var name: String
    public var stage: RunItemStage
    public var result: RunItemResult
    /// A short reason, for failures only.
    public var error: String?

    public init(name: String, stage: RunItemStage, result: RunItemResult, error: String? = nil) {
        self.name = name
        self.stage = stage
        self.result = result
        self.error = result == .failed ? error : nil
    }
}

/// The record written to last-run.json.
public struct LastRunRecord: Codable, Equatable, Sendable {
    public var sessionId: String
    public var runType: String
    public var status: String
    public var toolVersion: String
    public var startTime: String
    public var endTime: String?
    public var durationSeconds: Int?
    public var errors: Int
    public var warnings: Int
    public var items: [RunItem]

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case runType = "run_type"
        case status
        case toolVersion = "tool_version"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case errors
        case warnings
        case items
    }

    // Write end_time and duration_seconds as null while the run is going,
    // rather than leaving the keys out, so every reader sees the same shape.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(runType, forKey: .runType)
        try c.encode(status, forKey: .status)
        try c.encode(toolVersion, forKey: .toolVersion)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(errors, forKey: .errors)
        try c.encode(warnings, forKey: .warnings)
        try c.encode(items, forKey: .items)
    }
}

public enum LastRun {
    /// The longest line `summaryLine` returns. MDM custom attributes and
    /// script results are short fields; this keeps the line whole in them.
    public static let maxLineLength = 1000

    /// Writes the record atomically, so a reader never sees half a file.
    @discardableResult
    public static func write(_ record: LastRunRecord, to path: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else { return false }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }

    public static func read(from path: String) -> LastRunRecord? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(LastRunRecord.self, from: data)
    }

    /// The line `--last-run` prints for the file at `path`.
    public static func summaryLine(path: String = BootstrapMateConstants.lastRunPath) -> String {
        guard FileManager.default.fileExists(atPath: path) else { return "no run recorded" }
        guard let record = read(from: path) else { return "last run unreadable: \(path)" }
        return summaryLine(for: record)
    }

    /// `<time> <run_type> <status> v<version> installed=N skipped=N failed=N[: <name>: <error>; ...]`
    /// The time is the end time, or the start time while the run is going,
    /// in UTC to the minute.
    public static func summaryLine(for record: LastRunRecord) -> String {
        let installed = record.items.filter { $0.result == .installed }.count
        let skipped = record.items.filter { $0.result == .skipped }.count
        let failures = record.items.filter { $0.result == .failed }

        var line = "\(minuteStamp(record.endTime ?? record.startTime)) \(record.runType) \(record.status) "
            + "v\(record.toolVersion) installed=\(installed) skipped=\(skipped) failed=\(failures.count)"
        if !failures.isEmpty {
            line += ": " + failures
                .map { "\(oneLine($0.name)): \(oneLine($0.error ?? "failed"))" }
                .joined(separator: "; ")
        }
        return truncate(line, to: maxLineLength)
    }

    /// Cuts `text` to at most `limit` UTF-8 bytes, marking the cut with "...".
    /// Bytes rather than characters, because that is what a field limit counts.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        let marker = "..."
        var cut = Substring(text)
        while cut.utf8.count > limit - marker.utf8.count { cut = cut.dropLast() }
        return String(cut) + marker
    }

    /// An ISO 8601 timestamp reduced to the minute, in UTC: 2026-10-04T21:32Z.
    /// Anything that does not parse is passed through.
    static func minuteStamp(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) ?? plain.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return f.string(from: date)
    }

    private static func oneLine(_ text: String) -> String {
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
