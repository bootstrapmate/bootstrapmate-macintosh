//
//  BaselineThrottle.swift
//  BootstrapMate
//
//  Keeps baseline runs from repeating more often than intended. Every run
//  fetches the manifest and may download payloads, so a baseline that fires
//  again too soon costs bandwidth for nothing.
//

import Foundation

/// The outcome of the most recent baseline run, kept in its own file because
/// last-run.json is rewritten by every run, including a throttled one.
public struct BaselineState: Codable, Equatable, Sendable {
    /// When the record was last written: the end of the baseline run, or its
    /// start while it is `running`.
    public var endTime: Date
    /// `completed`, `partial_failure`, `failed`, `running` or `interrupted`.
    public var status: String
    /// Unsuccessful baselines in a row, counting this one. 0 when it completed.
    /// An interrupted run does not count.
    public var consecutiveFailures: Int
    /// The BootstrapMate version that ran this baseline.
    public var toolVersion: String?
    /// The BootstrapMate version of the last baseline that completed. A
    /// different running version is exempt from the minimum interval.
    public var completedVersion: String?

    public init(
        endTime: Date,
        status: String,
        consecutiveFailures: Int,
        toolVersion: String? = nil,
        completedVersion: String? = nil
    ) {
        self.endTime = endTime
        self.status = status
        self.consecutiveFailures = consecutiveFailures
        self.toolVersion = toolVersion
        self.completedVersion = completedVersion
    }

    enum CodingKeys: String, CodingKey {
        case endTime = "end_time"
        case status
        case consecutiveFailures = "consecutive_failures"
        case toolVersion = "tool_version"
        case completedVersion = "completed_version"
    }
}

public enum BaselineThrottle {
    public static let defaultPath = "/Library/Managed Bootstrap/baseline.json"
    /// Six days: short enough that a weekly schedule always runs.
    public static let defaultMinIntervalHours = 144
    /// How soon one unsuccessful baseline may be retried.
    public static let failureRetryHours = 24
    /// The file that exempts the next run from the throttle. The preflight
    /// consumes it; the throttle only looks.
    public static let defaultForceFile = "/Library/Managed Bootstrap/.bootstrapmate-force-run"

    public enum Decision: Equatable, Sendable {
        case run(reason: String)
        case skip(reason: String)
    }

    /// The status of a baseline that has started and not ended.
    public static let runningStatus = "running"

    /// Decides, without touching the network, whether this run may go ahead.
    ///
    /// - A run with no recorded baseline runs: a Mac being provisioned has
    ///   none, and a provisioning run clears it.
    /// - The force file always lets the run go ahead.
    /// - A baseline that was interrupted (stopped by SIGTERM, or left
    ///   `running` by a restart or crash) is retried by the next run, however
    ///   recent it was, until one ends.
    /// - After an unsuccessful baseline, the next run waits
    ///   `failureRetryHours`.
    /// - A BootstrapMate version other than the one that last completed a
    ///   baseline is exempt from `minIntervalHours`: a new build always runs
    ///   its baseline.
    /// - Otherwise, after a completed baseline the next waits
    ///   `minIntervalHours`; after an unsuccessful one, one retry is allowed
    ///   after `failureRetryHours`, and if that fails as well the full
    ///   interval applies again.
    public static func decide(
        state: BaselineState?,
        now: Date = Date(),
        minIntervalHours: Int = defaultMinIntervalHours,
        forceFilePresent: Bool = false,
        currentVersion: String? = nil
    ) -> Decision {
        if forceFilePresent {
            return .run(reason: "force file present")
        }
        guard let state else {
            return .run(reason: "no baseline recorded")
        }
        if state.status == runningStatus || state.status == LastRun.interruptedStatus {
            return .run(reason: "the last baseline (v\(state.toolVersion ?? "unknown")) was interrupted before it ended; retrying it")
        }
        guard minIntervalHours > 0 else {
            return .run(reason: "baseline throttle disabled (baselineMinIntervalHours <= 0)")
        }

        let ageHours = now.timeIntervalSince(state.endTime) / 3600
        let age = String(format: "%.1f", ageHours)
        let newVersion: String? = {
            guard let currentVersion, currentVersion != state.completedVersion else { return nil }
            return "BootstrapMate v\(currentVersion) has not completed a baseline (last completed: \(state.completedVersion.map { "v" + $0 } ?? "unrecorded"))"
        }()

        if state.status == "completed" {
            if let newVersion {
                return .run(reason: newVersion)
            }
            if ageHours < Double(minIntervalHours) {
                return .skip(reason: "last baseline completed \(age)h ago, under the \(minIntervalHours)h minimum interval")
            }
            return .run(reason: "last baseline completed \(age)h ago")
        }

        // An unsuccessful baseline waits a day before any retry.
        let retryHours = min(failureRetryHours, minIntervalHours)
        if ageHours < Double(retryHours) {
            return .skip(reason: "last baseline ended \(state.status) \(age)h ago; a retry waits \(retryHours)h")
        }
        if state.consecutiveFailures <= 1 {
            return .run(reason: "retrying the \(state.status) baseline from \(age)h ago")
        }
        if let newVersion {
            return .run(reason: "\(newVersion); retrying the \(state.status) baseline from \(age)h ago")
        }
        if ageHours < Double(minIntervalHours) {
            return .skip(reason: "last \(state.consecutiveFailures) baselines did not complete; the retry is used, next run after \(minIntervalHours)h (\(age)h so far)")
        }
        return .run(reason: "last baseline ended \(state.status) \(age)h ago")
    }

    /// The state while a baseline run is going. Saved when the run starts, so
    /// a run that never reaches its end is retried rather than throttled.
    public static func started(after previous: BaselineState?, version: String, startTime: Date = Date()) -> BaselineState {
        BaselineState(
            endTime: startTime,
            status: runningStatus,
            consecutiveFailures: previous.map { $0.status == "completed" ? 0 : $0.consecutiveFailures } ?? 0,
            toolVersion: version,
            completedVersion: previous?.completedVersion
        )
    }

    /// The state after a baseline run ends with `status`.
    public static func next(
        after previous: BaselineState?,
        status: String,
        endTime: Date = Date(),
        version: String? = nil
    ) -> BaselineState {
        let failures = status == "completed" ? 0 : (previous.map { $0.status == "completed" ? 0 : $0.consecutiveFailures } ?? 0) + 1
        return BaselineState(
            endTime: endTime,
            status: status,
            consecutiveFailures: failures,
            toolVersion: version ?? previous?.toolVersion,
            completedVersion: status == "completed" ? (version ?? previous?.toolVersion) : previous?.completedVersion
        )
    }

    /// Marks a baseline left `running` as `interrupted`. Call it only while
    /// holding the run lock, or from the run's own SIGTERM handler.
    public static func markInterrupted(at path: String = defaultPath) {
        guard var state = load(from: path), state.status == runningStatus else { return }
        state.status = LastRun.interruptedStatus
        save(state, to: path)
    }

    /// The recorded state, or nil when there is none or the file is not one
    /// only root could have written; a run then goes ahead rather than be
    /// held back by a record it cannot trust.
    public static func load(from path: String = defaultPath) -> BaselineState? {
        guard FileTrust.isTrustedFile(path), let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BaselineState.self, from: data)
    }

    @discardableResult
    public static func save(_ state: BaselineState, to path: String = defaultPath) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return false }
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }

    /// A provisioning run starts the record over, so the first baseline after
    /// it is never throttled.
    public static func clear(at path: String = defaultPath) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
