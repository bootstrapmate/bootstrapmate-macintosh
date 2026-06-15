//
//  ReportManager.swift
//  BootstrapMate
//
//  Posts a vendor-neutral run summary to an optional reporting endpoint when a
//  bootstrap run completes. This turns "did this Mac provision cleanly?" into a
//  fleet-dashboard query instead of an SSH/ARD expedition.
//
//  The payload is plain JSON and intentionally NOT specific to any one backend
//  (ReportMate, MunkiReport, a custom collector, …) — any service that accepts a
//  JSON POST can consume it.
//

import Foundation
import IOKit

public final class ReportManager {
    nonisolated(unsafe) public static let shared = ReportManager()

    private init() {}

    /// Build and POST the run summary to `config.reportingUrl`, if configured.
    /// Best-effort: failures are logged and never abort the run.
    public func sendRunSummary(success: Bool, startTime: Date, endTime: Date = Date()) {
        let config = ConfigManager.shared.config
        guard let urlString = config.reportingUrl, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return
        }

        let payload = Self.buildPayload(
            success: success,
            startTime: startTime,
            endTime: endTime,
            version: BootstrapMateConstants.version,
            runId: StatusManager.shared.getCurrentRunId(),
            manifestUrl: config.jsonUrl ?? "",
            phases: collectPhases()
        )

        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            Logger.warning("Could not serialize reporting payload")
            return
        }

        Logger.info("Posting run summary to reporting endpoint: \(urlString)")
        postJSON(body, to: url, authHeader: config.reportingHeader)
    }

    /// Assemble the vendor-neutral summary dictionary. Pure function for testing.
    public static func buildPayload(
        success: Bool,
        startTime: Date,
        endTime: Date,
        version: String,
        runId: String,
        manifestUrl: String,
        phases: [String: [String: Any]]
    ) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "tool": "BootstrapMate",
            "platform": "macOS",
            "schemaVersion": 1,
            "version": version,
            "runId": runId,
            "success": success,
            "startTime": iso.string(from: startTime),
            "endTime": iso.string(from: endTime),
            "durationSeconds": Int(endTime.timeIntervalSince(startTime).rounded()),
            "architecture": currentArchitecture(),
            "hostname": ProcessInfo.processInfo.hostName,
            "serialNumber": serialNumber() ?? "",
            "manifestUrl": manifestUrl,
            "phases": phases
        ]
    }

    // MARK: - Private

    /// Read the persisted per-phase status and flatten it for the report.
    private func collectPhases() -> [String: [String: Any]] {
        var phases: [String: [String: Any]] = [:]
        for phase in [InstallationPhase.preflight, .setupAssistant, .userland] {
            guard let status = StatusManager.shared.getPhaseStatus(phase: phase) else { continue }
            phases[phase.rawValue] = [
                "stage": status.stage.rawValue,
                "exitCode": status.exitCode,
                "startTime": status.startTime,
                "completionTime": status.completionTime,
                "lastError": status.lastError
            ]
        }
        return phases
    }

    private func postJSON(_ body: Data, to url: URL, authHeader: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BootstrapMate/\(BootstrapMateConstants.version)", forHTTPHeaderField: "User-Agent")
        if let authHeader = authHeader, !authHeader.isEmpty {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        request.timeoutInterval = 30

        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let error = error {
                Logger.warning("Reporting POST failed: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    Logger.info("Run summary reported (HTTP \(http.statusCode))")
                } else {
                    Logger.warning("Reporting endpoint returned HTTP \(http.statusCode)")
                }
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 35)
    }

    private static func currentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let chars = machineMirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8($0))) }
        return String(chars).contains("arm64") ? "ARM64" : "X64"
    }

    /// Best-effort hardware serial number via IOKit.
    private static func serialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }
        guard let cf = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String, !cf.isEmpty else {
            return nil
        }
        return cf
    }
}
