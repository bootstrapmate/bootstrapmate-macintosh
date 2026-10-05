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
    /// When the baseline run ended.
    public var endTime: Date
    /// `completed`, `partial_failure` or `failed`.
    public var status: String
    /// Unsuccessful baselines in a row, counting this one. 0 when it completed.
    public var consecutiveFailures: Int

    public init(endTime: Date, status: String, consecutiveFailures: Int) {
        self.endTime = endTime
        self.status = status
        self.consecutiveFailures = consecutiveFailures
    }

    enum CodingKeys: String, CodingKey {
        case endTime = "end_time"
        case status
        case consecutiveFailures = "consecutive_failures"
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

    /// Decides, without touching the network, whether this run may go ahead.
    ///
    /// - A run with no recorded baseline runs: a Mac being provisioned has
    ///   none, and a provisioning run clears it.
    /// - The force file always lets the run go ahead.
    /// - After a completed baseline, the next waits `minIntervalHours`.
    /// - After an unsuccessful baseline, one retry is allowed after
    ///   `failureRetryHours`; if that retry fails as well, the full interval
    ///   applies again.
    public static func decide(
        state: BaselineState?,
        now: Date = Date(),
        minIntervalHours: Int = defaultMinIntervalHours,
        forceFilePresent: Bool = false
    ) -> Decision {
        if forceFilePresent {
            return .run(reason: "force file present")
        }
        guard let state else {
            return .run(reason: "no baseline recorded")
        }
        guard minIntervalHours > 0 else {
            return .run(reason: "baseline throttle disabled (baselineMinIntervalHours <= 0)")
        }

        let ageHours = now.timeIntervalSince(state.endTime) / 3600
        let age = String(format: "%.1f", ageHours)

        if state.status == "completed" {
            if ageHours < Double(minIntervalHours) {
                return .skip(reason: "last baseline completed \(age)h ago, under the \(minIntervalHours)h minimum interval")
            }
            return .run(reason: "last baseline completed \(age)h ago")
        }

        // An unsuccessful baseline: allow one retry after a day, never sooner.
        let retryHours = min(failureRetryHours, minIntervalHours)
        if state.consecutiveFailures <= 1 {
            if ageHours < Double(retryHours) {
                return .skip(reason: "last baseline ended \(state.status) \(age)h ago; its one retry waits \(retryHours)h")
            }
            return .run(reason: "retrying the \(state.status) baseline from \(age)h ago")
        }
        if ageHours < Double(minIntervalHours) {
            return .skip(reason: "last \(state.consecutiveFailures) baselines did not complete; the retry is used, next run after \(minIntervalHours)h (\(age)h so far)")
        }
        return .run(reason: "last baseline ended \(state.status) \(age)h ago")
    }

    /// The state after a baseline run ends with `status`.
    public static func next(after previous: BaselineState?, status: String, endTime: Date = Date()) -> BaselineState {
        let failures = status == "completed" ? 0 : (previous.map { $0.status == "completed" ? 0 : $0.consecutiveFailures } ?? 0) + 1
        return BaselineState(endTime: endTime, status: status, consecutiveFailures: failures)
    }

    public static func load(from path: String = defaultPath) -> BaselineState? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
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
