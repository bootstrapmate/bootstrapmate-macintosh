import Testing
import Foundation
import CryptoKit
import Network
@testable import BootstrapMateCore

@Suite("BootstrapMateCore Tests")
struct BootstrapMateCoreTests {
    @Test("Placeholder test")
    func placeholder() {
        #expect(true)
    }
}

// MARK: - ReportManager Tests

@Suite("ReportManager Tests")
struct ReportManagerTests {

    @Test("Payload contains the core run-summary fields")
    func payloadShape() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_000_042)
        let payload = ReportManager.buildPayload(
            success: true,
            startTime: start,
            endTime: end,
            version: "2026.06.14.1200",
            runId: "test-run-id",
            manifestUrl: "https://example.com/manifest.json",
            phases: ["Userland": ["stage": "Completed", "exitCode": 0]]
        )

        #expect(payload["tool"] as? String == "BootstrapMate")
        #expect(payload["platform"] as? String == "macOS")
        #expect(payload["success"] as? Bool == true)
        #expect(payload["runId"] as? String == "test-run-id")
        #expect(payload["version"] as? String == "2026.06.14.1200")
        #expect(payload["durationSeconds"] as? Int == 42)
        #expect(payload["manifestUrl"] as? String == "https://example.com/manifest.json")
        #expect(payload["phases"] != nil)
    }

    @Test("Payload serializes to JSON")
    func payloadSerializes() throws {
        let payload = ReportManager.buildPayload(
            success: false,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 5),
            version: "v",
            runId: "r",
            manifestUrl: "",
            phases: [:]
        )
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(data.isEmpty == false)
    }
}

// MARK: - SignatureVerifier Tests

@Suite("SignatureVerifier Tests")
struct SignatureVerifierTests {

    private static let sampleSignedOutput = """
    Package "Example.pkg":
       Status: signed by a certificate trusted by macOS
       Certificate Chain:
        1. Developer ID Installer: Example Corp (AB12CD34EF)
           SHA256 Fingerprint:
               ...
        2. Developer ID Certification Authority
        3. Apple Root CA
    """

    @Test("Parses Team ID from leaf certificate line")
    func parsesTeamID() {
        #expect(SignatureVerifier.parseTeamID(from: Self.sampleSignedOutput) == "AB12CD34EF")
    }

    @Test("Returns nil when no Team ID is present")
    func noTeamID() {
        let output = "Package \"x.pkg\":\n   Status: no signature"
        #expect(SignatureVerifier.parseTeamID(from: output) == nil)
    }

    @Test("Signed package is allowed")
    func signedAllowed() {
        let decision = SignatureVerifier.shared.decide(.signed(teamID: "AB12CD34EF"), allowUnsigned: false)
        #expect(decision == .allow)
    }

    @Test("Untrusted package is denied by default")
    func untrustedDeniedByDefault() {
        let decision = SignatureVerifier.shared.decide(.untrusted(reason: "no signature"), allowUnsigned: false)
        if case .deny = decision { } else { Issue.record("expected deny") }
    }

    @Test("Untrusted package is allowed when allowUnsigned is set")
    func untrustedAllowedWhenOptedIn() {
        let decision = SignatureVerifier.shared.decide(.untrusted(reason: "no signature"), allowUnsigned: true)
        #expect(decision == .allow)
    }

    @Test("Team ID mismatch is denied even when allowUnsigned is set")
    func mismatchNeverBypassed() {
        let decision = SignatureVerifier.shared.decide(
            .teamIDMismatch(found: "ZZ99ZZ99ZZ", expected: "AB12CD34EF"),
            allowUnsigned: true
        )
        if case .deny = decision { } else { Issue.record("expected deny on Team ID mismatch") }
    }
}

// MARK: - ManifestDecoder Tests

@Suite("ManifestDecoder Tests")
struct ManifestDecoderTests {

    // Minimal valid manifest in both formats for testing
    private static let jsonManifest = """
    {
        "preflight": [
            {
                "file": "/tmp/preflight.sh",
                "hash": "abc123",
                "url": "https://example.com/preflight.sh",
                "type": "rootscript",
                "name": "Preflight"
            }
        ],
        "setupassistant": [],
        "userland": []
    }
    """

    private static let yamlManifest = """
    preflight:
      - file: /tmp/preflight.sh
        hash: abc123
        url: https://example.com/preflight.sh
        type: rootscript
        name: Preflight
    setupassistant: []
    userland: []
    """

    // MARK: - JSON Decoding

    @Test("Decode JSON manifest with .json URL hint")
    func decodeJSONWithHint() throws {
        let data = Data(Self.jsonManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data,
            urlHint: "https://example.com/manifest.json"
        )
        #expect(manifest.preflight?.count == 1)
        #expect(manifest.preflight?.first?.name == "Preflight")
        #expect(manifest.preflight?.first?.type == "rootscript")
        #expect(manifest.setupassistant?.isEmpty == true)
    }

    @Test("Decode JSON manifest without URL hint (fallback)")
    func decodeJSONNoHint() throws {
        let data = Data(Self.jsonManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data
        )
        #expect(manifest.preflight?.count == 1)
        #expect(manifest.preflight?.first?.hash == "abc123")
    }

    // MARK: - YAML Decoding

    @Test("Decode YAML manifest with .yaml URL hint")
    func decodeYAMLWithYamlHint() throws {
        let data = Data(Self.yamlManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data,
            urlHint: "https://example.com/manifest.yaml"
        )
        #expect(manifest.preflight?.count == 1)
        #expect(manifest.preflight?.first?.name == "Preflight")
        #expect(manifest.preflight?.first?.url == "https://example.com/preflight.sh")
    }

    @Test("Decode YAML manifest with .yml URL hint")
    func decodeYAMLWithYmlHint() throws {
        let data = Data(Self.yamlManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data,
            urlHint: "https://example.com/manifest.yml"
        )
        #expect(manifest.preflight?.count == 1)
        #expect(manifest.preflight?.first?.type == "rootscript")
    }

    @Test("Decode YAML manifest without URL hint (fallback from JSON)")
    func decodeYAMLNoHint() throws {
        let data = Data(Self.yamlManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data
        )
        #expect(manifest.preflight?.count == 1)
        #expect(manifest.preflight?.first?.file == "/tmp/preflight.sh")
    }

    // MARK: - Format Detection

    @Test("URL with query params still detects extension")
    func urlWithQueryParams() throws {
        let data = Data(Self.yamlManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data,
            urlHint: "https://example.com/manifest.yaml?token=abc"
        )
        #expect(manifest.preflight?.count == 1)
    }

    @Test("Extensionless URL falls back correctly for JSON")
    func extensionlessJSON() throws {
        let data = Data(Self.jsonManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data,
            urlHint: "https://example.com/api/manifest"
        )
        #expect(manifest.preflight?.count == 1)
    }

    @Test("Extensionless URL falls back correctly for YAML")
    func extensionlessYAML() throws {
        let data = Data(Self.yamlManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data,
            urlHint: "https://example.com/api/manifest"
        )
        #expect(manifest.preflight?.count == 1)
    }

    // MARK: - Error Cases

    @Test("Invalid data throws error")
    func invalidDataThrows() {
        let garbage = Data("not valid json or yaml content ][}{".utf8)
        #expect(throws: Error.self) {
            try ManifestDecoder.decode(
                BootstrapManifest.self,
                from: garbage,
                urlHint: "https://example.com/bad.json"
            )
        }
    }

    // MARK: - BootstrapConfig (ConfigManager path)

    private static let jsonConfig = """
    {
        "preflight": [
            {
                "file": "/tmp/pre.sh",
                "hash": "def456",
                "url": "https://example.com/pre.sh",
                "type": "rootscript"
            }
        ],
        "setupassistant": [],
        "userland": []
    }
    """

    private static let yamlConfig = """
    preflight:
      - file: /tmp/pre.sh
        hash: def456
        url: https://example.com/pre.sh
        type: rootscript
    setupassistant: []
    userland: []
    """

    @Test("Decode BootstrapConfig from JSON")
    func decodeConfigJSON() throws {
        let data = Data(Self.jsonConfig.utf8)
        let config = try ManifestDecoder.decode(
            BootstrapConfig.self,
            from: data,
            urlHint: "https://example.com/config.json"
        )
        #expect(config.preflight.count == 1)
        #expect(config.preflight.first?.hash == "def456")
    }

    @Test("Decode BootstrapConfig from YAML")
    func decodeConfigYAML() throws {
        let data = Data(Self.yamlConfig.utf8)
        let config = try ManifestDecoder.decode(
            BootstrapConfig.self,
            from: data,
            urlHint: "https://example.com/config.yaml"
        )
        #expect(config.preflight.count == 1)
        #expect(config.preflight.first?.hash == "def456")
    }

    // MARK: - Full Manifest with All Fields

    private static let fullYAMLManifest = """
    preflight:
      - file: /tmp/preflight.sh
        hash: abc123
        url: https://example.com/preflight.sh
        type: rootscript
        name: Preflight Check
        retries: 3
        retrywait: 5
        followRedirects: true
        donotwait: false
    setupassistant:
      - file: /tmp/munki.pkg
        hash: def456
        url: https://example.com/munki.pkg
        type: package
        name: Munki Tools
        packageid: com.googlecode.munki.core
        version: "6.0.0"
        retries: 2
        retrywait: 10
    userland:
      - file: /tmp/user.sh
        hash: ghi789
        url: https://example.com/user.sh
        type: userscript
        name: User Setup
        skipIf: x86_64
    """

    @Test("Decode full YAML manifest with all item fields")
    func fullYAMLManifestAllFields() throws {
        let data = Data(Self.fullYAMLManifest.utf8)
        let manifest = try ManifestDecoder.decode(
            BootstrapManifest.self,
            from: data,
            urlHint: "https://example.com/full.yml"
        )

        // Preflight
        let pre = try #require(manifest.preflight?.first)
        #expect(pre.name == "Preflight Check")
        #expect(pre.retries?.value == 3)
        #expect(pre.retrywait?.value == 5)
        #expect(pre.followRedirects == true)
        #expect(pre.donotwait == false)

        // Setup assistant
        let setup = try #require(manifest.setupassistant?.first)
        #expect(setup.type == "package")
        #expect(setup.packageid == "com.googlecode.munki.core")
        #expect(setup.version == "6.0.0")

        // Userland
        let user = try #require(manifest.userland?.first)
        #expect(user.skipIf == "x86_64")
    }
}

// MARK: - Logger Tests

@Suite("Logger Tests")
struct LoggerTests {

    private static let linePattern = #"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] (DEBUG|INFO |WARN |ERROR) \S.*$"#

    private static func localDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: components)!
    }

    private static func makeTempDirectory() throws -> String {
        let path = NSTemporaryDirectory() + "bootstrapmate-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test("Line format is timestamp, padded level, message")
    func lineFormat() {
        let date = Self.localDate(year: 2026, month: 9, day: 1, hour: 13, minute: 15, second: 14)
        #expect(Logger.formatLine(level: .info, message: "Session started", date: date)
            == "[2026-09-01 13:15:14] INFO  Session started")
        #expect(Logger.formatLine(level: .error, message: "Failed to load manifest", date: date)
            == "[2026-09-01 13:15:14] ERROR Failed to load manifest")
        #expect(Logger.formatLine(level: .warning, message: "Retrying", date: date)
            == "[2026-09-01 13:15:14] WARN  Retrying")
        #expect(Logger.formatLine(level: .debug, message: "Detail", date: date)
            == "[2026-09-01 13:15:14] DEBUG Detail")
        #expect(Logger.formatLine(level: .success, message: "Done", date: date)
            == "[2026-09-01 13:15:14] INFO  Done")
    }

    @Test func fileLinesStampEveryLineAndDropBlanks() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = formatter.string(from: date)
        let lines = Logger.fileLines(level: .info, message: "first\r\n\nsecond  \r\n", date: date)
        #expect(lines == ["[\(stamp)] INFO  first", "[\(stamp)] INFO  second"])
        #expect(Logger.fileLines(level: .info, message: "\n  \n", date: date).isEmpty)
    }

    @Test func outputLinesAreTaggedAndNamedForTheirSource() {
        let text = Logger.prefixLines("Starting cleanup...\n\nDone.\n", with: "[OUTPUT] preflight.sh: ")
        #expect(text == "[OUTPUT] preflight.sh: Starting cleanup...\n[OUTPUT] preflight.sh: Done.")
    }

    @Test("Every line written to the log file matches the convention")
    func fileLinesMatchConvention() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        Logger.initialize(logDirectory: directory, version: "test", verboseConsole: false, silentMode: true)
        Logger.info("Session started")
        Logger.warning("Something odd")
        Logger.error("Failed to load manifest")
        Logger.debug("Detail")
        Logger.writeSection("Preflight")
        Logger.writeSuccess("Installed")

        let path = try #require(Logger.getLogFilePath())
        #expect(path.hasPrefix(directory))
        // The run's log lives in its session directory: logs/YYYY-MM-DD/HHMMSS/bootstrap.log.
        let relative = String(path.dropFirst(directory.count + 1))
        #expect(relative.range(of: #"^\d{4}-\d{2}-\d{2}/\d{6}(_\d)?/bootstrap\.log$"#, options: .regularExpression) != nil,
                "unexpected log path: \(relative)")
        let sessionDirectory = (path as NSString).deletingLastPathComponent
        #expect(FileManager.default.fileExists(atPath: sessionDirectory + "/events.jsonl"))
        #expect(FileManager.default.fileExists(atPath: sessionDirectory + "/session.json"))

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.split(separator: "\n").map(String.init)
        #expect(lines.count >= 18)
        for line in lines {
            #expect(line.range(of: Self.linePattern, options: .regularExpression) != nil, "unexpected line: \(line)")
        }
        #expect(lines.contains { $0.hasSuffix("] INFO  Session started") })
        #expect(lines.contains { $0.hasSuffix("] WARN  Something odd") })
        #expect(lines.contains { $0.hasSuffix("] ERROR Failed to load manifest") })
        #expect(lines.contains { $0.hasSuffix("] DEBUG Detail") })
        #expect(lines.contains { $0.hasSuffix("] INFO  [SECTION] Preflight") })
        #expect(!content.contains("WARNING"))
        #expect(!content.contains("] SUCCESS"))
    }

    @Test("Retention removes only .log files older than the window")
    func retentionSweep() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let fm = FileManager.default
        let now = Date()
        let day: TimeInterval = 24 * 60 * 60

        func create(_ name: String, ageInDays: Double) throws {
            let path = (directory as NSString).appendingPathComponent(name)
            fm.createFile(atPath: path, contents: Data("x".utf8))
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-ageInDays * day)], ofItemAtPath: path)
        }

        try create("2026-07-01-120000.log", ageInDays: 45)
        try create("2026-07-20-120000.log", ageInDays: 31)
        try create("2026-08-25-120000.log", ageInDays: 7)
        try create("notes.txt", ageInDays: 90)
        let subdir = (directory as NSString).appendingPathComponent("archive.log")
        try fm.createDirectory(atPath: subdir, withIntermediateDirectories: false)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-90 * day)], ofItemAtPath: subdir)

        let removed = Logger.pruneLogFiles(in: directory, olderThan: Logger.retentionInterval, now: now)
        #expect(removed == 2)

        let remaining = Set(try fm.contentsOfDirectory(atPath: directory))
        #expect(remaining == ["2026-08-25-120000.log", "notes.txt", "archive.log"])
    }

    @Test("Retention tolerates a missing directory")
    func retentionMissingDirectory() {
        let missing = NSTemporaryDirectory() + "bootstrapmate-missing-" + UUID().uuidString
        #expect(Logger.pruneLogFiles(in: missing, olderThan: Logger.retentionInterval) == 0)
    }
}

// MARK: - SessionLog Tests

@Suite("SessionLog Tests")
struct SessionLogTests {

    private func temporaryLogs() -> String {
        let path = NSTemporaryDirectory() + "bootstrapmate-session-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test("A run writes its files into logs/YYYY-MM-DD/HHMMSS")
    func sessionDirectoryIsSecondResolution() throws {
        let logs = temporaryLogs()
        let start = SessionLog.formatter("yyyy-MM-dd HH:mm:ss").date(from: "2026-09-03 04:11:07")!
        let session = try #require(SessionLog(logsDirectory: logs, version: "2026.09.03.0411", runType: "provisioning", start: start))

        #expect(session.sessionId == "2026-09-03-041107")
        #expect(session.sessionDir == logs + "/2026-09-03/041107")
        #expect(session.logFilePath.hasSuffix("/041107/bootstrap.log"))

        session.append(level: "INFO", message: "[SUCCESS] Installed Google Chrome", date: start)
        session.append(level: "ERROR", message: "postinstall returned 1", date: start)
        session.finish(end: start.addingTimeInterval(45))

        let events = try String(contentsOfFile: session.sessionDir + "/events.jsonl", encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(events.count == 2)
        let first = try #require(try JSONSerialization.jsonObject(with: Data(events[0].utf8)) as? [String: Any])
        #expect(first["event_type"] as? String == "item")
        #expect(first["status"] as? String == "SUCCESS")
        #expect(first["message"] as? String == "Installed Google Chrome")
        #expect(first["session_id"] as? String == "2026-09-03-041107")

        let record = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: session.sessionDir + "/session.json"))) as? [String: Any])
        #expect(record["status"] as? String == "partial_failure")
        #expect(record["duration_seconds"] as? Int == 45)
        #expect(record["tool_version"] as? String == "2026.09.03.0411")
        let summary = try #require(record["summary"] as? [String: Any])
        #expect(summary["errors"] as? Int == 1)
        #expect(summary["events"] as? Int == 2)
    }

    @Test("A second run in the same second gets a suffix")
    func sameSecondCollision() throws {
        let logs = temporaryLogs()
        let start = SessionLog.formatter("yyyy-MM-dd HH:mm:ss").date(from: "2026-09-03 04:11:07")!
        _ = try #require(SessionLog(logsDirectory: logs, version: "v", runType: "provisioning", start: start))
        let second = try #require(SessionLog(logsDirectory: logs, version: "v", runType: "provisioning", start: start))
        #expect(second.sessionId == "2026-09-03-041107_2")
    }

    @Test("A tagged message becomes an event type and status")
    func classification() {
        #expect(SessionLog.classify(level: "INFO", message: "[PROGRESS] Installing: Chrome").0 == "progress")
        #expect(SessionLog.classify(level: "INFO", message: "[PROGRESS] Installing: Chrome").1 == "PROGRESS")
        #expect(SessionLog.classify(level: "INFO", message: "[SKIPPED] Already current").1 == "SKIPPED")
        #expect(SessionLog.classify(level: "ERROR", message: "download failed").1 == "FAILED")
        #expect(SessionLog.classify(level: "INFO", message: "[OUTPUT] preinstall: hello").2 == "preinstall: hello")
        // An unknown bracket is left in the message rather than invented into a type.
        #expect(SessionLog.classify(level: "INFO", message: "[MDM] enrolled").2 == "[MDM] enrolled")
    }

    @Test("Retention removes day directories past the window")
    func retentionRemovesOldDays() throws {
        let logs = temporaryLogs()
        let now = SessionLog.formatter("yyyy-MM-dd HH:mm:ss").date(from: "2026-09-03 04:11:07")!
        let fm = FileManager.default
        for day in ["2026-07-01", "2026-08-30", "2026-09-03"] {
            try fm.createDirectory(atPath: logs + "/" + day + "/120000", withIntermediateDirectories: true)
        }

        let removed = SessionLog.prune(logsDirectory: logs, now: now)

        #expect(removed == 1)
        #expect(Set(try fm.contentsOfDirectory(atPath: logs)) == ["2026-08-30", "2026-09-03"])
    }
}

// MARK: - ArchitectureSkip Tests

@Suite("ArchitectureSkip Tests")
struct ArchitectureSkipTests {

    @Test("An item is skipped on the architecture its skipIf names")
    func skipsNamedArchitecture() {
        #expect(ArchitectureSkip.shouldSkip("arm64", currentArch: "arm64") == true)
        #expect(ArchitectureSkip.shouldSkip("apple_silicon", currentArch: "arm64") == true)
        #expect(ArchitectureSkip.shouldSkip("x86_64", currentArch: "x86_64") == true)
        #expect(ArchitectureSkip.shouldSkip("intel", currentArch: "x86_64") == true)
    }

    @Test("An item runs on the other architecture")
    func runsOnOtherArchitecture() {
        #expect(ArchitectureSkip.shouldSkip("arm64", currentArch: "x86_64") == false)
        #expect(ArchitectureSkip.shouldSkip("apple_silicon", currentArch: "x86_64") == false)
        #expect(ArchitectureSkip.shouldSkip("x86_64", currentArch: "arm64") == false)
        #expect(ArchitectureSkip.shouldSkip("intel", currentArch: "arm64") == false)
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        #expect(ArchitectureSkip.shouldSkip("ARM64", currentArch: "arm64") == true)
        #expect(ArchitectureSkip.shouldSkip("Intel", currentArch: "x86_64") == true)
        #expect(ArchitectureSkip.shouldSkip("Apple_Silicon", currentArch: "x86_64") == false)
    }

    @Test("An unrecognized value never skips")
    func unknownValueRuns() {
        #expect(ArchitectureSkip.shouldSkip("", currentArch: "arm64") == false)
        #expect(ArchitectureSkip.shouldSkip("ppc", currentArch: "arm64") == false)
        #expect(ArchitectureSkip.shouldSkip("ppc", currentArch: "x86_64") == false)
    }

    @Test("The current architecture is one of the two we support")
    func currentArchitectureIsKnown() {
        #expect(["arm64", "x86_64"].contains(ArchitectureSkip.currentArchitecture()))
    }
}

// MARK: - PreflightDecision Tests

@Suite("PreflightDecision Tests")
struct PreflightDecisionTests {

    @Test("Exit 0 skips the bootstrap")
    func exitZeroSkips() {
        #expect(PreflightDecision.from(exitCode: 0) == .skip)
    }

    @Test("Exit 2 selects baseline mode")
    func exitTwoIsBaseline() {
        #expect(PreflightDecision.baselineExitCode == 2)
        #expect(PreflightDecision.from(exitCode: 2) == .baseline)
    }

    @Test("Other positive exits run the full bootstrap")
    func positiveExitsProvision() {
        #expect(PreflightDecision.from(exitCode: 1) == .provision)
        #expect(PreflightDecision.from(exitCode: 3) == .provision)
        #expect(PreflightDecision.from(exitCode: 255) == .provision)
    }

    @Test("Negative exits fail the stage")
    func negativeExitsFail() {
        #expect(PreflightDecision.from(exitCode: -1) == .failed)
    }

    @Test("Items run in baseline unless they opt out")
    func baselineOptOut() throws {
        let json = """
        [
          {"file": "/tmp/a.pkg", "hash": "h", "url": "https://example.com/a.pkg", "type": "package"},
          {"file": "/tmp/b.sh", "hash": "h", "url": "https://example.com/b.sh", "type": "rootscript", "baseline": false}
        ]
        """
        let items = try JSONDecoder().decode([ManifestItem].self, from: Data(json.utf8))
        #expect(items[0].runsInBaseline == true)
        #expect(items[1].runsInBaseline == false)
    }
}

// MARK: - InstallLedger Tests

@Suite("InstallLedger Tests")
struct InstallLedgerTests {

    @Test("A recorded hash is found again, case-insensitively")
    func recordsAndFinds() {
        let path = NSTemporaryDirectory() + "ledger-\(UUID().uuidString)/installed.json"
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let ledger = InstallLedger(path: path)

        #expect(ledger.contains(hash: "abc123") == false)
        ledger.record(hash: "ABC123", name: "Example")
        #expect(ledger.contains(hash: "abc123") == true)
        #expect(InstallLedger(path: path).contains(hash: "other") == false)
    }

    @Test("An empty hash is never recorded or matched")
    func ignoresEmptyHash() {
        let path = NSTemporaryDirectory() + "ledger-\(UUID().uuidString)/installed.json"
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let ledger = InstallLedger(path: path)

        ledger.record(hash: "", name: "Example")
        #expect(ledger.contains(hash: "") == false)
    }
}

// MARK: - LastRun Tests

@Suite("LastRun Tests")
struct LastRunTests {

    private func temporaryDir() -> String {
        let path = NSTemporaryDirectory() + "bootstrapmate-lastrun-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func record(status: String = "completed", items: [RunItem]) -> LastRunRecord {
        return LastRunRecord(
            sessionId: "2026-10-04-213210",
            runType: "provisioning",
            status: status,
            toolVersion: "2026.10.04.2130",
            startTime: "2026-10-04T21:32:10.512Z",
            endTime: "2026-10-04T21:47:55.020Z",
            durationSeconds: 945,
            errors: 0,
            warnings: 0,
            items: items
        )
    }

    @Test("A clean run prints counts and no failure list")
    func noFailures() {
        let line = LastRun.summaryLine(for: record(items: [
            RunItem(name: "Tools", stage: .setupassistant, result: .installed),
            RunItem(name: "Agent", stage: .setupassistant, result: .skipped),
            RunItem(name: "Dock", stage: .userland, result: .installed)
        ]))
        #expect(line == "2026-10-04T21:47Z provisioning completed v2026.10.04.2130 installed=2 skipped=1 failed=0")
    }

    @Test("Failures are listed by name and error")
    func failuresListed() {
        let line = LastRun.summaryLine(for: record(status: "partial_failure", items: [
            RunItem(name: "Tools", stage: .setupassistant, result: .installed),
            RunItem(name: "Agent", stage: .setupassistant, result: .failed, error: "Download failed"),
            RunItem(name: "Dock", stage: .userland, result: .failed, error: "Script\nfailed")
        ]))
        #expect(line == "2026-10-04T21:47Z provisioning partial_failure v2026.10.04.2130 installed=1 skipped=0 failed=2: Agent: Download failed; Dock: Script failed")
    }

    @Test("A running record uses the start time")
    func runningUsesStart() {
        var r = record(status: "running", items: [])
        r.endTime = nil
        #expect(LastRun.summaryLine(for: r).hasPrefix("2026-10-04T21:32Z provisioning running "))
    }

    @Test("A long failure list is cut to the limit")
    func truncation() {
        let items = (1...200).map {
            RunItem(name: "Package number \($0)", stage: .userland, result: .failed, error: "Installation failed")
        }
        let line = LastRun.summaryLine(for: record(status: "partial_failure", items: items))
        #expect(line.utf8.count <= LastRun.maxLineLength)
        #expect(line.utf8.count >= LastRun.maxLineLength - 3)
        #expect(line.hasSuffix("..."))
        #expect(line.contains("failed=200: Package number 1: Installation failed;"))
        #expect(!line.contains("\n"))
    }

    @Test("Truncation never splits a multi-byte character")
    func truncationIsCharacterSafe() {
        let cut = LastRun.truncate(String(repeating: "é", count: 20), to: 10)
        #expect(cut == "ééé...")
    }

    @Test("An absent file reports no run")
    func absentFile() {
        #expect(LastRun.summaryLine(path: temporaryDir() + "/last-run.json") == "no run recorded")
    }

    @Test("Error is kept only for failures")
    func errorOnlyOnFailure() {
        #expect(RunItem(name: "a", stage: .userland, result: .installed, error: "x").error == nil)
        #expect(RunItem(name: "a", stage: .userland, result: .failed, error: "x").error == "x")
    }

    @Test("A session writes last-run.json at start and at finish, with the corrected run type")
    func sessionWritesLastRun() throws {
        let root = temporaryDir()
        let logs = root + "/logs"
        let lastRunPath = root + "/last-run.json"
        let start = SessionLog.formatter("yyyy-MM-dd HH:mm:ss").date(from: "2026-10-04 14:32:10")!
        let session = try #require(SessionLog(
            logsDirectory: logs, version: "2026.10.04.1432", runType: "provisioning",
            lastRunPath: lastRunPath, start: start))

        let atStart = try #require(LastRun.read(from: lastRunPath))
        #expect(atStart.status == "running")
        #expect(atStart.runType == "provisioning")
        #expect(atStart.endTime == nil)
        let raw = try String(contentsOfFile: lastRunPath, encoding: .utf8)
        #expect(raw.contains("\"end_time\" : null"))

        session.setRunType("baseline")
        let sessionJSON = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: session.sessionDir + "/session.json"))) as? [String: Any])
        #expect(sessionJSON["run_type"] as? String == "baseline")
        #expect(LastRun.read(from: lastRunPath)?.runType == "baseline")

        session.recordItem(RunItem(name: "Tools", stage: .setupassistant, result: .installed))
        session.recordItem(RunItem(name: "Agent", stage: .setupassistant, result: .failed, error: "Download failed"))
        session.append(level: "ERROR", message: "Failed to download Agent", date: start)
        session.finish(end: start.addingTimeInterval(60))

        let atEnd = try #require(LastRun.read(from: lastRunPath))
        #expect(atEnd.status == "partial_failure")
        #expect(atEnd.runType == "baseline")
        #expect(atEnd.durationSeconds == 60)
        #expect(atEnd.errors == 1)
        #expect(atEnd.sessionId == session.sessionId)
        #expect(atEnd.items.count == 2)
        #expect(atEnd.items[1] == RunItem(name: "Agent", stage: .setupassistant, result: .failed, error: "Download failed"))
    }

    @Test("last-run.json sits beside the logs directory")
    func lastRunPathBesideLogs() {
        #expect(Logger.lastRunPath(forLogsDirectory: BootstrapMateConstants.logsDirectory) == BootstrapMateConstants.lastRunPath)
    }
}

@Suite("Deployment target Tests")
struct DeploymentTargetTests {

    /// The repository root, from this file's location in Tests/<target>/.
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    @Test("Package.swift, the app's Info.plist and the preinstall gate name the same macOS")
    func floorsAgree() throws {
        let package = firstMatch(#"\.macOS\(\.v(\d+)\)"#, in: try read("Package.swift"))
        let plist = firstMatch(
            #"<key>LSMinimumSystemVersion</key>\s*<string>(\d+)\.0</string>"#,
            in: try read("packaging/resources/Info.plist.template")
        )
        let preinstall = firstMatch(#"MINIMUM_MACOS=(\d+)"#, in: try read("packaging/scripts/preinstall"))

        #expect(package != nil)
        #expect(package == plist)
        #expect(package == preinstall)
    }
}

// MARK: - DryRun Tests

/// Dry-run mode is one global switch, so these tests run one at a time and
/// always switch it back off.
@Suite("DryRun Tests", .serialized)
struct DryRunTests {

    private func temporaryDir() throws -> String {
        let path = NSTemporaryDirectory() + "bootstrapmate-dryrun-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes `contents` to a source file and returns a manifest item that
    /// downloads it (over file://) to `destination`.
    private func item(
        type: String,
        contents: String,
        in dir: String,
        destination: String,
        extra: String = ""
    ) throws -> (json: String, source: String) {
        let source = dir + "/source-" + UUID().uuidString
        let data = Data(contents.utf8)
        try data.write(to: URL(fileURLWithPath: source))
        let json = """
        {"file": "\(destination)", "hash": "\(sha256(data))", "url": "file://\(source)", "type": "\(type)", "name": "\((destination as NSString).lastPathComponent)"\(extra)}
        """
        return (json, source)
    }

    private func decode(_ json: String) throws -> ManifestItem {
        try JSONDecoder().decode(ManifestItem.self, from: Data(json.utf8))
    }

    @Test("A dry run still downloads each item and checks its hash")
    func downloadsAndVerifies() throws {
        let dir = try temporaryDir()
        defer { try? FileManager.default.removeItem(atPath: dir); DryRun.isEnabled = false }
        DryRun.isEnabled = true

        let destination = dir + "/payload.pkg"
        let good = try decode(item(type: "package", contents: "payload", in: dir, destination: destination).json)
        #expect(ManifestManager.shared.downloadIfNeeded(good))
        #expect(FileManager.default.fileExists(atPath: destination))

        // A wrong hash still fails, as it would in a real run.
        let source = dir + "/other"
        try Data("other".utf8).write(to: URL(fileURLWithPath: source))
        let bad = try decode("""
        {"file": "\(dir)/bad.pkg", "hash": "\(String(repeating: "0", count: 64))", "url": "file://\(source)", "type": "package", "retries": 1, "retrywait": 0}
        """)
        #expect(ManifestManager.shared.downloadIfNeeded(bad) == false)
    }

    @Test("A dry run never runs a root script; a real run does")
    func neverRunsScripts() throws {
        let dir = try temporaryDir()
        defer { try? FileManager.default.removeItem(atPath: dir); DryRun.isEnabled = false }
        let marker = dir + "/ran"
        let script = try decode(item(
            type: "rootscript",
            contents: "#!/bin/sh\ntouch '\(marker)'\nexit 0\n",
            in: dir,
            destination: dir + "/script.sh"
        ).json)

        DryRun.isEnabled = true
        #expect(ScriptManager.shared.runScriptWithExitCode(script) == 0)
        #expect(FileManager.default.fileExists(atPath: dir + "/script.sh"))
        #expect(FileManager.default.fileExists(atPath: marker) == false)

        DryRun.isEnabled = false
        #expect(ScriptManager.shared.runScriptWithExitCode(script) == 0)
        #expect(FileManager.default.fileExists(atPath: marker))
    }

    @Test("A dry run never hands a package to the installer")
    func neverInstalls() {
        defer { DryRun.isEnabled = false }
        let missing = NSTemporaryDirectory() + "bootstrapmate-missing-\(UUID().uuidString).pkg"

        // The installer fails on a missing package, so success proves it never ran.
        DryRun.isEnabled = true
        #expect(PackageManager.shared.installPackage(atPath: missing, verifySignature: false))

        DryRun.isEnabled = false
        #expect(PackageManager.shared.installPackage(atPath: missing, verifySignature: false) == false)
    }

    @Test("A dry run of a whole manifest installs nothing, runs nothing and leaves the ledger empty")
    func wholeRunChangesNothing() throws {
        let dir = try temporaryDir()
        let ledgerPath = dir + "/installed.json"
        let original = IAOrchestrator.shared.ledger
        let originalConfig = IAOrchestrator.shared.config
        defer {
            try? FileManager.default.removeItem(atPath: dir)
            DryRun.isEnabled = false
            IAOrchestrator.shared.ledger = original
            IAOrchestrator.shared.config = originalConfig
        }

        let preflightMarker = dir + "/preflight-ran"
        let scriptMarker = dir + "/script-ran"
        let preflight = try item(
            type: "rootscript",
            contents: "#!/bin/sh\ntouch '\(preflightMarker)'\nexit 0\n",
            in: dir,
            destination: dir + "/preflight.sh"
        )
        let package = try item(
            type: "package",
            contents: "not really a package",
            in: dir,
            destination: dir + "/tool.pkg",
            extra: #", "allowUnsigned": true"#
        )
        let script = try item(
            type: "rootscript",
            contents: "#!/bin/sh\ntouch '\(scriptMarker)'\nexit 0\n",
            in: dir,
            destination: dir + "/setup.sh"
        )
        let manifestPath = dir + "/manifest.json"
        try Data("""
        {"preflight": [\(preflight.json)], "setupassistant": [\(package.json), \(script.json)]}
        """.utf8).write(to: URL(fileURLWithPath: manifestPath))

        #expect(ManifestManager.shared.loadManifest(
            from: "file://\(manifestPath)",
            followRedirects: false,
            authHeader: nil,
            skipValidation: false
        ))

        ManifestManager.shared.setDryRun(true)
        var config = IAOrchestrator.OrchestratorConfig()
        config.enableDialog = false
        IAOrchestrator.shared.config = config
        IAOrchestrator.shared.ledger = InstallLedger(path: ledgerPath)

        #expect(IAOrchestrator.shared.runAllStages(reboot: true))

        // Everything was downloaded and verified...
        #expect(FileManager.default.fileExists(atPath: dir + "/preflight.sh"))
        #expect(FileManager.default.fileExists(atPath: dir + "/tool.pkg"))
        #expect(FileManager.default.fileExists(atPath: dir + "/setup.sh"))
        // ...and nothing ran or was recorded.
        #expect(FileManager.default.fileExists(atPath: preflightMarker) == false)
        #expect(FileManager.default.fileExists(atPath: scriptMarker) == false)
        #expect(FileManager.default.fileExists(atPath: ledgerPath) == false)
    }
}

// MARK: - Redirect Tests

/// A one-route-pair HTTP server on localhost: `/redirect` answers 302 to
/// `/target`, and `/target` answers 200 with a fixed body.
private final class RedirectServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "redirect-server")
    private(set) var port: UInt16 = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let response: String
                if request.hasPrefix("GET /redirect") {
                    response = "HTTP/1.1 302 Found\r\nLocation: /target\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                } else {
                    response = "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\ntarget"
                }
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port?.rawValue ?? 0
    }

    func stop() { listener.cancel() }
}

private final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

@Suite("Redirect Tests")
struct RedirectTests {

    private func fetch(_ url: URL, follow: Bool) -> (Data?, Error?) {
        let done = DispatchSemaphore(value: 0)
        let result = Box<(Data?, Error?)>((nil, nil))
        NetworkManager.shared.downloadData(from: url, followRedirects: follow, authHeader: nil) { data, error in
            result.value = (data, error)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
        return result.value
    }

    private func download(_ url: URL, to path: String, follow: Bool) -> Bool {
        let done = DispatchSemaphore(value: 0)
        let ok = Box(false)
        NetworkManager.shared.downloadFile(toPath: path, from: url.absoluteString, followRedirects: follow, authHeader: nil) { result in
            if case .success = result { ok.value = true }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
        return ok.value
    }

    @Test("A redirect is followed when followRedirects is on")
    func follows() throws {
        let server = try RedirectServer()
        defer { server.stop() }
        let url = URL(string: "http://127.0.0.1:\(server.port)/redirect")!

        let (data, error) = fetch(url, follow: true)
        #expect(error == nil)
        #expect(data.flatMap { String(data: $0, encoding: .utf8) } == "target")

        let path = NSTemporaryDirectory() + "redirect-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(download(url, to: path, follow: true))
        #expect(FileManager.default.contents(atPath: path) == Data("target".utf8))
    }

    @Test("A redirect is refused, and the download fails, when followRedirects is off")
    func refuses() throws {
        let server = try RedirectServer()
        defer { server.stop() }
        let url = URL(string: "http://127.0.0.1:\(server.port)/redirect")!

        let (data, error) = fetch(url, follow: false)
        #expect(data == nil)
        #expect(error?.localizedDescription.contains("302") == true)

        let path = NSTemporaryDirectory() + "redirect-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(download(url, to: path, follow: false) == false)
        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    @Test("Redirects are followed by default")
    func defaultIsOn() {
        #expect(BootstrapMateConfig().followRedirects == true)
    }
}

