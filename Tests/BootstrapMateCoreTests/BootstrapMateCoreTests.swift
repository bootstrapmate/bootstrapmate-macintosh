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

// MARK: - Managed preference Tests

@Suite("Managed preference Tests")
struct ManagedPreferenceTests {

    @Test("Defaults: the cache is kept and the network wait is 120 seconds")
    func defaults() {
        let config = BootstrapMateConfig()
        #expect(config.retainCache == true)
        #expect(config.networkTimeout == 120)
        #expect(config.enableDialog == true)
    }

    @Test("Dialog settings come from the preferences")
    func dialogFromPreferences() {
        var prefs = BootstrapMateConfig()
        prefs.enableDialog = false
        prefs.dialogTitle = "Title"
        prefs.dialogMessage = "Message"
        prefs.dialogIcon = "/tmp/icon.png"
        prefs.blurScreen = true

        let config = IAOrchestrator.OrchestratorConfig(preferences: prefs)
        #expect(config.enableDialog == false)
        #expect(config.dialogTitle == "Title")
        #expect(config.dialogMessage == "Message")
        #expect(config.dialogIcon == "/tmp/icon.png")
        #expect(config.blurScreen == true)
    }

    @Test("CLI title and message override the preferences; --no-dialog and --silent win over enableDialog")
    func cliOverrides() {
        let prefs = BootstrapMateConfig(enableDialog: true, dialogTitle: "Pref title", dialogMessage: "Pref message")

        let fromCLI = IAOrchestrator.OrchestratorConfig(preferences: prefs, title: "CLI title", message: "CLI message")
        #expect(fromCLI.enableDialog == true)
        #expect(fromCLI.dialogTitle == "CLI title")
        #expect(fromCLI.dialogMessage == "CLI message")

        #expect(IAOrchestrator.OrchestratorConfig(preferences: prefs, noDialog: true).enableDialog == false)
        #expect(IAOrchestrator.OrchestratorConfig(preferences: prefs, silent: true).enableDialog == false)
    }

    @Test("The keys that were never used are listed as unsupported")
    func unsupportedKeys() {
        for key in ["installPath", "iapath", "daemonIdentifier", "ldidentifier", "agentIdentifier", "laidentifier"] {
            #expect(ConfigManager.unsupportedKeys.contains(key))
        }
    }

    @Test("Cleaning the cache empties the directory and keeps it")
    func cleanCache() throws {
        let dir = NSTemporaryDirectory() + "bootstrapmate-cache-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/sub", withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: dir + "/a.pkg"))
        try Data("y".utf8).write(to: URL(fileURLWithPath: dir + "/sub/b.sh"))

        CleanupManager.shared.cleanCache(at: dir)

        #expect(FileManager.default.fileExists(atPath: dir))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir).isEmpty)
    }
}

// MARK: - App rename upgrade Tests

/// Runs the real postinstall against a scratch root laid out like a Mac with
/// the pre-rename BootstrapMate.app installed, after the installer has laid
/// down the new payload. launchd is never touched under a test root.
@Suite("App rename upgrade Tests")
struct AppRenameUpgradeTests {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private let newApp = "/Applications/Utilities/Managed Bootstrap Install.app"
    private let oldApp = "/Applications/Utilities/BootstrapMate.app"

    private func write(_ text: String, to path: String, executable: Bool = false) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
    }

    private func programArgument(_ plistPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String] else { return nil }
        return args.first
    }

    @Test("The LaunchDaemon runs the CLI at the path the code expects")
    func daemonPathMatchesConstant() {
        let plist = repoRoot.appendingPathComponent("packaging/LaunchDaemons/com.github.bootstrapmate.plist").path
        #expect(programArgument(plist) == BootstrapMateConstants.executablePath)
        #expect(BootstrapMateConstants.executablePath.hasPrefix(newApp + "/"))
    }

    @Test("An upgrade from BootstrapMate.app leaves one app, repointed links and the state untouched")
    func upgradeOverOldLayout() throws {
        _ = try runUpgrade(runningPid: nil)
    }

    @Test("An upgrade during a run never boots the running job out; an idle one is reloaded")
    func upgradeLeavesRunningJobAlone() throws {
        // The daemon's own bootout, not the helper's (.helper suffix).
        func bootsOutDaemon(_ log: String) -> Bool {
            log.split(separator: "\n").contains { $0.hasSuffix("skipped: launchctl bootout system/com.github.bootstrapmate") }
        }

        let busy = try runUpgrade(runningPid: "4242")
        #expect(busy.contains("run is in progress (pid 4242)"))
        #expect(!bootsOutDaemon(busy))
        #expect(!busy.contains("skipped: launchctl load"))

        let idle = try runUpgrade(runningPid: nil)
        #expect(bootsOutDaemon(idle))
        #expect(idle.contains("skipped: launchctl load"))
    }

    /// Runs the postinstall over the pre-rename layout and returns its log.
    private func runUpgrade(runningPid: String?) throws -> String {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "bootstrapmate-upgrade-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: root) }
        let stub = "#!/bin/sh\necho 2026.10.04.1228\n"

        // The layout an install of the pre-rename build leaves behind.
        for binary in ["managedbootstrapinstall", "BootstrapMateGUI", "BootstrapMateHelper"] {
            try write(stub, to: root + oldApp + "/Contents/MacOS/" + binary, executable: true)
        }
        try fm.createDirectory(atPath: root + "/usr/local/bootstrapmate", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/usr/local/bin", withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: root + "/usr/local/bootstrapmate/managedbootstrapinstall",
            withDestinationPath: root + oldApp + "/Contents/MacOS/managedbootstrapinstall"
        )
        try fm.createSymbolicLink(
            atPath: root + "/usr/local/bin/managedbootstrapinstall",
            withDestinationPath: root + oldApp + "/Contents/MacOS/managedbootstrapinstall"
        )
        try write("{}", to: root + "/Library/Managed Bootstrap/installed.json")
        try write("{\"status\":\"completed\"}", to: root + "/Library/Managed Bootstrap/last-run.json")
        // An earlier build, or anything else, left the tree writable by others.
        for path in ["/Library/Managed Bootstrap", "/Library/Managed Bootstrap/installed.json"] {
            try fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root + path)
        }
        try fm.createDirectory(atPath: root + "/tmp", withIntermediateDirectories: true)

        // The new payload, as the installer lays it down before postinstall.
        for binary in ["managedbootstrapinstall", "BootstrapMateGUI", "BootstrapMateHelper"] {
            try write(stub, to: root + newApp + "/Contents/MacOS/" + binary, executable: true)
        }
        try fm.createDirectory(atPath: root + newApp + "/Contents/Library/LaunchDaemons", withIntermediateDirectories: true)
        try fm.copyItem(
            atPath: repoRoot.appendingPathComponent("packaging/LaunchDaemons/com.github.bootstrapmate.helper.plist").path,
            toPath: root + newApp + "/Contents/Library/LaunchDaemons/com.github.bootstrapmate.helper.plist"
        )
        try fm.createDirectory(atPath: root + "/Library/LaunchDaemons", withIntermediateDirectories: true)
        try fm.copyItem(
            atPath: repoRoot.appendingPathComponent("packaging/LaunchDaemons/com.github.bootstrapmate.plist").path,
            toPath: root + "/Library/LaunchDaemons/com.github.bootstrapmate.plist"
        )

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [repoRoot.appendingPathComponent("packaging/scripts/postinstall").path]
        var environment = ["BOOTSTRAPMATE_TEST_ROOT": root, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        if let runningPid { environment["BOOTSTRAPMATE_TEST_RUNNING_PID"] = runningPid }
        task.environment = environment
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        #expect(task.terminationStatus == 0)

        // One app: the old bundle is gone, the new one is in place.
        #expect(fm.fileExists(atPath: root + oldApp) == false)
        #expect(fm.isExecutableFile(atPath: root + newApp + "/Contents/MacOS/managedbootstrapinstall"))

        // Both CLI links point into the new bundle.
        let newCLI = root + newApp + "/Contents/MacOS/managedbootstrapinstall"
        #expect(try fm.destinationOfSymbolicLink(atPath: root + "/usr/local/bin/managedbootstrapinstall") == newCLI)
        #expect(try fm.destinationOfSymbolicLink(atPath: root + "/usr/local/bootstrapmate/managedbootstrapinstall") == newCLI)

        // launchd runs both jobs from the new bundle on the boot volume.
        #expect(programArgument(root + "/Library/LaunchDaemons/com.github.bootstrapmate.plist") == BootstrapMateConstants.executablePath)
        #expect(programArgument(root + "/Library/LaunchDaemons/com.github.bootstrapmate.helper.plist")
                == newApp + "/Contents/MacOS/BootstrapMateHelper")

        // The managed tree is writable by its owner alone.
        for path in ["", "/logs", "/cache", "/installed.json", "/last-run.json"] {
            let mode = (try fm.attributesOfItem(atPath: root + "/Library/Managed Bootstrap" + path)[.posixPermissions] as? Int) ?? 0o777
            #expect(mode & 0o022 == 0, "\(path) is writable by group or others")
        }

        // State under /Library/Managed Bootstrap survives.
        #expect(fm.contents(atPath: root + "/Library/Managed Bootstrap/installed.json") == Data("{}".utf8))
        #expect(fm.fileExists(atPath: root + "/Library/Managed Bootstrap/last-run.json"))
        return (try? String(contentsOfFile: root + "/tmp/bootstrapmate-postinstall.log", encoding: .utf8)) ?? ""
    }
}

// MARK: - Baseline throttle Tests

@Suite("Baseline throttle Tests")
struct BaselineThrottleTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(_ status: String, hoursAgo: Double, failures: Int = 0) -> BaselineState {
        BaselineState(endTime: now.addingTimeInterval(-hoursAgo * 3600), status: status, consecutiveFailures: failures)
    }

    private func skips(_ decision: BaselineThrottle.Decision) -> Bool {
        if case .skip = decision { return true }
        return false
    }

    @Test("A young completed baseline skips the run")
    func youngBaselineSkips() {
        #expect(skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 24), now: now)))
        #expect(skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 143.9), now: now)))
    }

    @Test("An old completed baseline runs, so a weekly schedule still runs")
    func oldBaselineRuns() {
        #expect(!skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 144), now: now)))
        #expect(!skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 168), now: now)))
    }

    @Test("A failed baseline retries once after 24 hours, never sooner")
    func failedRetriesAfterADay() {
        for status in ["failed", "partial_failure"] {
            #expect(skips(BaselineThrottle.decide(state: state(status, hoursAgo: 2, failures: 1), now: now)))
            #expect(skips(BaselineThrottle.decide(state: state(status, hoursAgo: 23.9, failures: 1), now: now)))
            #expect(!skips(BaselineThrottle.decide(state: state(status, hoursAgo: 24, failures: 1), now: now)))
        }
    }

    @Test("Once the retry has failed too, the full interval applies")
    func retryUsedWaitsFullInterval() {
        #expect(skips(BaselineThrottle.decide(state: state("partial_failure", hoursAgo: 30, failures: 2), now: now)))
        #expect(!skips(BaselineThrottle.decide(state: state("partial_failure", hoursAgo: 144, failures: 2), now: now)))
    }

    @Test("The force file always lets the run go ahead")
    func forceFileRuns() {
        #expect(!skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 1), now: now, forceFilePresent: true)))
        #expect(!skips(BaselineThrottle.decide(state: state("failed", hoursAgo: 1, failures: 3), now: now, forceFilePresent: true)))
    }

    @Test("No recorded baseline runs, and an interval of 0 turns the throttle off")
    func noStateAndDisabled() {
        #expect(!skips(BaselineThrottle.decide(state: nil, now: now)))
        #expect(!skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 1), now: now, minIntervalHours: 0)))
    }

    @Test("The interval follows the preference")
    func customInterval() {
        #expect(!skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 25), now: now, minIntervalHours: 24)))
        #expect(skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 25), now: now, minIntervalHours: 48)))
    }

    @Test("Consecutive failures count up and reset on a completed baseline")
    func nextState() {
        let first = BaselineThrottle.next(after: nil, status: "partial_failure", endTime: now)
        #expect(first.consecutiveFailures == 1)
        let second = BaselineThrottle.next(after: first, status: "partial_failure", endTime: now)
        #expect(second.consecutiveFailures == 2)
        let done = BaselineThrottle.next(after: second, status: "completed", endTime: now)
        #expect(done.consecutiveFailures == 0)
        #expect(BaselineThrottle.next(after: done, status: "failed", endTime: now).consecutiveFailures == 1)
    }

    @Test("The state survives a save and load, and clearing removes it")
    func persistence() throws {
        let path = NSTemporaryDirectory() + "baseline-\(UUID().uuidString)/baseline.json"
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let saved = state("completed", hoursAgo: 3)
        #expect(BaselineThrottle.save(saved, to: path))
        #expect(BaselineThrottle.load(from: path) == saved)
        BaselineThrottle.clear(at: path)
        #expect(BaselineThrottle.load(from: path) == nil)
    }

    private func versioned(_ status: String, hoursAgo: Double, failures: Int = 0, completed: String?) -> BaselineState {
        BaselineState(
            endTime: now.addingTimeInterval(-hoursAgo * 3600), status: status, consecutiveFailures: failures,
            toolVersion: completed, completedVersion: completed
        )
    }

    @Test("A new BootstrapMate version runs its baseline however recent the last one")
    func versionChangeRuns() {
        let young = versioned("completed", hoursAgo: 1, completed: "2026.10.01.1000")
        #expect(!skips(BaselineThrottle.decide(state: young, now: now, currentVersion: "2026.10.05.0926")))
        // A record from a build that kept no version counts as a different one.
        #expect(!skips(BaselineThrottle.decide(state: state("completed", hoursAgo: 1), now: now, currentVersion: "2026.10.05.0926")))
    }

    @Test("The same version with a young completed baseline still skips")
    func sameVersionYoungSkips() {
        let young = versioned("completed", hoursAgo: 1, completed: "2026.10.05.0926")
        #expect(skips(BaselineThrottle.decide(state: young, now: now, currentVersion: "2026.10.05.0926")))
        let old = versioned("completed", hoursAgo: 144, completed: "2026.10.05.0926")
        #expect(!skips(BaselineThrottle.decide(state: old, now: now, currentVersion: "2026.10.05.0926")))
    }

    @Test("An interrupted or still-running baseline is retried at once, however recent")
    func interruptedRunsImmediately() {
        for status in ["interrupted", "running"] {
            let s = versioned(status, hoursAgo: 0.1, failures: 3, completed: "2026.10.05.0926")
            #expect(!skips(BaselineThrottle.decide(state: s, now: now, currentVersion: "2026.10.05.0926")))
        }
    }

    @Test("A failed baseline waits 24 hours, even on a new version")
    func failedWaitsADayEvenOnNewVersion() {
        for status in ["failed", "partial_failure"] {
            let s = versioned(status, hoursAgo: 2, failures: 1, completed: "2026.10.01.1000")
            #expect(skips(BaselineThrottle.decide(state: s, now: now, currentVersion: "2026.10.05.0926")))
            let day = versioned(status, hoursAgo: 24, failures: 1, completed: "2026.10.01.1000")
            #expect(!skips(BaselineThrottle.decide(state: day, now: now, currentVersion: "2026.10.05.0926")))
        }
    }

    @Test("A new version lifts the full interval after repeated failures, but not the 24 hours")
    func versionLiftsIntervalAfterRetry() {
        let used = versioned("partial_failure", hoursAgo: 30, failures: 2, completed: "2026.10.01.1000")
        #expect(skips(BaselineThrottle.decide(state: used, now: now, currentVersion: "2026.10.01.1000")))
        #expect(!skips(BaselineThrottle.decide(state: used, now: now, currentVersion: "2026.10.05.0926")))
        let recent = versioned("partial_failure", hoursAgo: 10, failures: 2, completed: "2026.10.01.1000")
        #expect(skips(BaselineThrottle.decide(state: recent, now: now, currentVersion: "2026.10.05.0926")))
    }

    @Test("The state records the running version and the last completed one")
    func versionsRecorded() {
        let done = BaselineThrottle.next(after: nil, status: "completed", endTime: now, version: "A")
        #expect(done.completedVersion == "A" && done.toolVersion == "A")
        let running = BaselineThrottle.started(after: done, version: "B", startTime: now)
        #expect(running.status == "running" && running.toolVersion == "B" && running.completedVersion == "A")
        let failed = BaselineThrottle.next(after: running, status: "partial_failure", endTime: now, version: "B")
        #expect(failed.completedVersion == "A" && failed.consecutiveFailures == 1)
        let rerun = BaselineThrottle.started(after: failed, version: "B", startTime: now)
        #expect(rerun.consecutiveFailures == 1)
        let fixed = BaselineThrottle.next(after: rerun, status: "completed", endTime: now, version: "B")
        #expect(fixed.completedVersion == "B" && fixed.consecutiveFailures == 0)
    }

    @Test("A record left running is marked interrupted; a finished one is left alone")
    func markInterrupted() throws {
        let dir = NSTemporaryDirectory() + "baseline-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/baseline.json"
        BaselineThrottle.save(BaselineThrottle.started(after: nil, version: "A", startTime: now), to: path)
        BaselineThrottle.markInterrupted(at: path)
        #expect(BaselineThrottle.load(from: path)?.status == "interrupted")
        BaselineThrottle.save(BaselineThrottle.next(after: nil, status: "completed", endTime: now, version: "A"), to: path)
        BaselineThrottle.markInterrupted(at: path)
        #expect(BaselineThrottle.load(from: path)?.status == "completed")
    }

    @Test("A record from a build that kept no versions still loads")
    func legacyRecordLoads() throws {
        let dir = NSTemporaryDirectory() + "baseline-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/baseline.json"
        try Data(#"{"consecutive_failures":0,"end_time":"2026-10-04T20:00:00Z","status":"completed"}"#.utf8)
            .write(to: URL(fileURLWithPath: path))
        let loaded = try #require(BaselineThrottle.load(from: path))
        #expect(loaded.status == "completed" && loaded.completedVersion == nil)
    }

    @Test("A baseline record that another account could have written is ignored")
    func untrustedRecordIgnored() throws {
        let dir = NSTemporaryDirectory() + "baseline-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/baseline.json"
        BaselineThrottle.save(state("completed", hoursAgo: 1), to: path)
        #expect(BaselineThrottle.load(from: path) != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: path)
        #expect(BaselineThrottle.load(from: path) == nil)
    }

    @Test("The default interval is 144 hours")
    func defaults() {
        #expect(BootstrapMateConfig().baselineMinIntervalHours == 144)
    }
}

// MARK: - Run bounds Tests

@Suite("Run bounds Tests")
struct RunBoundsTests {

    @Test("Download attempts are kept within 1 and the maximum")
    func attemptsClamp() {
        #expect(BootstrapMateConstants.downloadAttempts(requested: nil) == 3)
        #expect(BootstrapMateConstants.downloadAttempts(requested: 0) == 1)
        #expect(BootstrapMateConstants.downloadAttempts(requested: 1000) == BootstrapMateConstants.maxDownloadAttempts)
        #expect(BootstrapMateConstants.retryDelay(requested: 100_000) == BootstrapMateConstants.maxRetryDelay)
        #expect(BootstrapMateConstants.retryDelay(requested: -5) == 0)
    }

    @Test("The LaunchDaemon starts once at load and never relaunches itself")
    func daemonNeverLoops() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("packaging/LaunchDaemons/com.github.bootstrapmate.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["RunAtLoad"] as? Bool == true)
        for key in ["KeepAlive", "StartInterval", "StartCalendarInterval", "WatchPaths", "QueueDirectories", "StartOnMount"] {
            #expect(plist[key] == nil, "\(key) would relaunch the daemon")
        }
    }
}

// MARK: - Throttle after preflight Tests

/// Runs the orchestrator for real (no dry run) with a preflight that picks the
/// mode, and a young completed baseline on record. launchd is never touched.
/// An extension of the dry-run suite so the two never run at once: both drive
/// the shared orchestrator and the dry-run switch.
extension DryRunTests {

    private func throttleItem(_ name: String, _ contents: String, dir: String) throws -> String {
        let source = dir + "/src-" + name
        let data = Data(contents.utf8)
        try data.write(to: URL(fileURLWithPath: source))
        return """
        {"file": "\(dir)/\(name)", "hash": "\(sha256(data))", "url": "file://\(source)", "type": "rootscript", "name": "\(name)"}
        """
    }

    /// Returns whether the setupassistant script ran and whether it was
    /// downloaded, and the baseline state the run left. The recorded baseline
    /// ended an hour ago with `status`, on `completedVersion`.
    private func runWithYoungBaseline(
        preflightExit: Int,
        status: String = "completed",
        completedVersion: String? = BootstrapMateConstants.version
    ) throws -> (ran: Bool, downloaded: Bool, state: BaselineState?) {
        let dir = NSTemporaryDirectory() + "bootstrapmate-throttle-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let orchestrator = IAOrchestrator.shared
        let saved = (orchestrator.config, orchestrator.ledger, orchestrator.baselineStatePath, orchestrator.finishRun)
        defer {
            try? FileManager.default.removeItem(atPath: dir)
            orchestrator.config = saved.0
            orchestrator.ledger = saved.1
            orchestrator.baselineStatePath = saved.2
            orchestrator.finishRun = saved.3
        }

        let statePath = dir + "/baseline.json"
        BaselineThrottle.save(
            BaselineState(
                endTime: Date().addingTimeInterval(-3600), status: status, consecutiveFailures: 0,
                toolVersion: completedVersion, completedVersion: completedVersion
            ),
            to: statePath
        )

        let marker = dir + "/setup-ran"
        let preflight = try throttleItem("preflight.sh", "#!/bin/sh\nexit \(preflightExit)\n", dir: dir)
        let setup = try throttleItem("setup.sh", "#!/bin/sh\ntouch '\(marker)'\nexit 0\n", dir: dir)
        let manifest = dir + "/manifest.json"
        try Data("""
        {"preflight": [\(preflight)], "setupassistant": [\(setup)]}
        """.utf8).write(to: URL(fileURLWithPath: manifest))
        #expect(ManifestManager.shared.loadManifest(from: "file://\(manifest)", followRedirects: false, authHeader: nil, skipValidation: false))

        ManifestManager.shared.setDryRun(false)
        var config = IAOrchestrator.OrchestratorConfig()
        config.enableDialog = false
        orchestrator.config = config
        orchestrator.ledger = InstallLedger(path: dir + "/installed.json")
        orchestrator.baselineStatePath = statePath
        orchestrator.finishRun = {}

        #expect(orchestrator.runAllStages(reboot: false))
        return (
            FileManager.default.fileExists(atPath: marker),
            FileManager.default.fileExists(atPath: dir + "/setup.sh"),
            BaselineThrottle.load(from: statePath)
        )
    }

    @Test("A young baseline does not hold back a run the preflight sends to provisioning")
    func provisionRunsDespiteYoungBaseline() throws {
        let result = try runWithYoungBaseline(preflightExit: 1)
        #expect(result.ran)
    }

    @Test("A baseline chosen by the preflight is throttled: nothing is downloaded or run")
    func baselineIsThrottled() throws {
        let result = try runWithYoungBaseline(preflightExit: Int(PreflightDecision.baselineExitCode))
        #expect(result.ran == false)
        #expect(result.downloaded == false)
    }

    @Test("A new BootstrapMate version runs its baseline and records itself as completed")
    func newVersionRunsBaseline() throws {
        let result = try runWithYoungBaseline(
            preflightExit: Int(PreflightDecision.baselineExitCode),
            completedVersion: "2000.01.01.0000"
        )
        #expect(result.ran)
        #expect(result.state?.status == "completed")
        #expect(result.state?.completedVersion == BootstrapMateConstants.version)
    }

    @Test("An interrupted baseline is retried on the next run, however recent")
    func interruptedBaselineRetries() throws {
        let result = try runWithYoungBaseline(
            preflightExit: Int(PreflightDecision.baselineExitCode),
            status: "interrupted"
        )
        #expect(result.ran)
        #expect(result.state?.status == "completed")
    }

    @Test("A cached file another account could have written is discarded and fetched again")
    func untrustedCacheRefetched() throws {
        let dir = NSTemporaryDirectory() + "bootstrapmate-cache-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/cache", withIntermediateDirectories: true)
        let good = Data("#!/bin/sh\nexit 0\n".utf8)
        try good.write(to: URL(fileURLWithPath: dir + "/source.sh"))
        let item = try JSONDecoder().decode(ManifestItem.self, from: Data("""
        {"file": "\(dir)/cache/item.sh", "hash": "\(sha256(good))", "url": "file://\(dir)/source.sh", "type": "rootscript"}
        """.utf8))

        // Right bytes, but writable by others: replaced with a fresh copy.
        try good.write(to: URL(fileURLWithPath: item.file))
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: item.file)
        #expect(ManifestManager.shared.downloadIfNeeded(item))
        #expect(FileTrust.isTrustedFile(item.file))

        // A link at the path is replaced, and what it pointed at is untouched.
        let elsewhere = dir + "/elsewhere"
        try Data("keep".utf8).write(to: URL(fileURLWithPath: elsewhere))
        try FileManager.default.removeItem(atPath: item.file)
        try FileManager.default.createSymbolicLink(atPath: item.file, withDestinationPath: elsewhere)
        #expect(ManifestManager.shared.downloadIfNeeded(item))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: item.file)) == nil)
        #expect(FileManager.default.contents(atPath: elsewhere) == Data("keep".utf8))

        // A cache directory others can write is refused outright.
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: dir + "/cache")
        #expect(ManifestManager.shared.downloadIfNeeded(item) == false)
    }
}

// MARK: - Build version Tests

@Suite("Build version Tests")
struct BuildVersionTests {

    private func makeApp(short: String, build: String) throws -> (root: String, cli: String, link: String) {
        let root = NSTemporaryDirectory() + "bootstrapmate-version-" + UUID().uuidString
        let macOS = root + "/Managed Bootstrap Install.app/Contents/MacOS"
        try FileManager.default.createDirectory(atPath: macOS, withIntermediateDirectories: true)
        let cli = macOS + "/managedbootstrapinstall"
        FileManager.default.createFile(atPath: cli, contents: Data("#!/bin/sh\n".utf8))
        let plist: [String: Any] = ["CFBundleShortVersionString": short, "CFBundleVersion": build]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: root + "/Managed Bootstrap Install.app/Contents/Info.plist"))
        try FileManager.default.createDirectory(atPath: root + "/bin", withIntermediateDirectories: true)
        let link = root + "/bin/managedbootstrapinstall"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: cli)
        return (root, cli, link)
    }

    @Test("The version comes from the bundle's Info.plist, is stable across reads, and resolves the PATH link")
    func readsInfoPlist() async throws {
        let app = try makeApp(short: "2026.10.05", build: "0926")
        defer { try? FileManager.default.removeItem(atPath: app.root) }

        let first = BuildInfo.version(executablePath: app.cli)
        try await Task.sleep(for: .seconds(1.2))
        let second = BuildInfo.version(executablePath: app.cli)
        #expect(first == "2026.10.05.0926")
        #expect(first == second)
        #expect(BuildInfo.version(executablePath: app.link) == "2026.10.05.0926")
    }

    @Test("Outside an app bundle the build-time value is used, never the clock")
    func fallbackIsNotTheClock() async throws {
        let loose = NSTemporaryDirectory() + "loose-binary"
        let first = BuildInfo.version(executablePath: loose)
        try await Task.sleep(for: .seconds(1.2))
        #expect(first == BuildVersion.value)
        #expect(BuildInfo.version(executablePath: loose) == first)

        let a = BootstrapMateConstants.version
        try await Task.sleep(for: .seconds(1.2))
        #expect(BootstrapMateConstants.version == a)
        let clock = DateFormatter()
        clock.dateFormat = "yyyy.MM.dd.HHmm"
        #expect(a != clock.string(from: Date()) || a == BuildVersion.value)
    }

    @Test("A short version that already carries the build is not doubled")
    func noDoubleBuild() throws {
        let app = try makeApp(short: "2026.10.05.0926", build: "0926")
        defer { try? FileManager.default.removeItem(atPath: app.root) }
        #expect(BuildInfo.version(executablePath: app.cli) == "2026.10.05.0926")
    }
}

// MARK: - Interrupted run Tests

@Suite("Interrupted run Tests")
struct InterruptedRunTests {

    private func record(status: String, id: String = "2026-10-04-132100") -> LastRunRecord {
        LastRunRecord(
            sessionId: id, runType: "baseline", status: status, toolVersion: "2026.10.04.1228",
            startTime: "2026-10-04T20:21:00.000Z", endTime: nil, durationSeconds: nil,
            errors: 0, warnings: 0, items: []
        )
    }

    @Test("A run left as running is recorded as interrupted, in last-run.json and its session.json")
    func orphanBecomesInterrupted() throws {
        let root = NSTemporaryDirectory() + "bootstrapmate-orphan-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let logs = root + "/logs"
        let lastRun = root + "/last-run.json"
        let sessionDir = logs + "/2026-10-04/132100"
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        try Data(#"{"session_id":"2026-10-04-132100","status":"running"}"#.utf8)
            .write(to: URL(fileURLWithPath: sessionDir + "/session.json"))
        LastRun.write(record(status: "running"), to: lastRun)

        let orphan = LastRun.recoverInterrupted(lastRunPath: lastRun, logsDirectory: logs)
        #expect(orphan?.sessionId == "2026-10-04-132100")
        #expect(LastRun.read(from: lastRun)?.status == "interrupted")
        let session = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: sessionDir + "/session.json"))
        ) as? [String: Any]
        #expect(session?["status"] as? String == "interrupted")
        #expect(LastRun.summaryLine(path: lastRun).contains("interrupted"))
    }

    @Test("A run that finished is left alone")
    func finishedRunUntouched() {
        let root = NSTemporaryDirectory() + "bootstrapmate-orphan-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let lastRun = root + "/last-run.json"
        LastRun.write(record(status: "completed"), to: lastRun)
        #expect(LastRun.recoverInterrupted(lastRunPath: lastRun, logsDirectory: root + "/logs") == nil)
        #expect(LastRun.read(from: lastRun)?.status == "completed")
        #expect(LastRun.recoverInterrupted(lastRunPath: root + "/missing.json", logsDirectory: root) == nil)
    }

    @Test("Only one run holds the lock; it frees when released")
    func singleInstance() throws {
        let path = NSTemporaryDirectory() + "bootstrapmate-lock-\(UUID().uuidString)/.run.lock"
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        var first = RunLock.acquire(at: path)
        #expect(first != nil)
        #expect(RunLock.acquire(at: path) == nil)
        first = nil
        #expect(RunLock.acquire(at: path) != nil)
    }

    @Test("A session closed as interrupted writes that status to last-run.json")
    func sigtermStatus() throws {
        let root = NSTemporaryDirectory() + "bootstrapmate-sigterm-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let lastRun = root + "/last-run.json"
        let session = try #require(SessionLog(logsDirectory: root + "/logs", version: "test", runType: "baseline", lastRunPath: lastRun))
        #expect(LastRun.read(from: lastRun)?.status == "running")
        session.finish(status: LastRun.interruptedStatus)
        #expect(LastRun.read(from: lastRun)?.status == "interrupted")
        session.finish()
        #expect(LastRun.read(from: lastRun)?.status == "interrupted")
    }
}

// MARK: - File trust Tests

@Suite("File trust Tests")
struct FileTrustTests {

    private func scratch() throws -> String {
        let dir = NSTemporaryDirectory() + "bootstrapmate-trust-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        return dir
    }

    @Test("Only an owned file, writable by no one else, in a directory the same, is trusted")
    func trustedFile() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let file = dir + "/state.json"
        try Data("{}".utf8).write(to: URL(fileURLWithPath: file))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)
        #expect(FileTrust.isTrustedFile(file))

        try FileManager.default.setAttributes([.posixPermissions: 0o664], ofItemAtPath: file)
        #expect(!FileTrust.isTrustedFile(file))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)

        let link = dir + "/link.json"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: file)
        #expect(!FileTrust.isTrustedFile(link))

        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: dir)
        #expect(!FileTrust.isTrustedFile(file))
        #expect(!FileTrust.isTrustedDirectory(dir))
    }

    @Test("A force file counts only in a directory no other account can write")
    func forceMarker() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let marker = dir + "/.force"
        FileManager.default.createFile(atPath: marker, contents: nil)
        #expect(FileTrust.isTrustedMarker(marker))
        try FileManager.default.setAttributes([.posixPermissions: 0o1777], ofItemAtPath: dir)
        #expect(!FileTrust.isTrustedMarker(marker))
        #expect(!FileTrust.isTrustedMarker(dir + "/missing"))
    }

    @Test("Securing a directory removes write access for everyone but the owner")
    func secureDirectory() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let sub = dir + "/cache"
        #expect(FileTrust.secureDirectory(sub))
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: sub)
        // Only root can repair; any other account just reports it.
        #expect(FileTrust.secureDirectory(sub) == (geteuid() == 0))
        let link = dir + "/link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: sub)
        #expect(!FileTrust.secureDirectory(link))
    }

    @Test("A ledger another account could have written is ignored")
    func untrustedLedger() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let ledger = InstallLedger(path: dir + "/installed.json")
        ledger.record(hash: "abc", name: "item")
        #expect(ledger.contains(hash: "abc"))
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: ledger.path)
        #expect(!ledger.contains(hash: "abc"))
    }

    @Test("The run lock never follows a link")
    func lockRefusesLink() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let target = dir + "/target"
        try FileManager.default.createSymbolicLink(atPath: dir + "/.run.lock", withDestinationPath: target)
        #expect(RunLock.acquire(at: dir + "/.run.lock") == nil)
        #expect(!FileManager.default.fileExists(atPath: target))
    }

    @Test("A last-run record whose session id is not a session id never names a path")
    func lastRunSessionIdChecked() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let outside = dir + "/session.json"
        try Data(#"{"status":"running"}"#.utf8).write(to: URL(fileURLWithPath: outside))
        let record = LastRunRecord(
            sessionId: "2026-10-04-../..", runType: "baseline", status: "running", toolVersion: "t",
            startTime: "2026-10-04T20:21:00.000Z", endTime: nil, durationSeconds: nil, errors: 0, warnings: 0, items: []
        )
        LastRun.write(record, to: dir + "/last-run.json")
        #expect(LastRun.recoverInterrupted(lastRunPath: dir + "/last-run.json", logsDirectory: dir + "/logs/a/b") != nil)
        #expect(FileManager.default.contents(atPath: outside) == Data(#"{"status":"running"}"#.utf8))
    }
}

// MARK: - ManagementDetector Tests

@Suite("ManagementDetector Tests")
struct ManagementDetectorTests {

    private func detector(forced: Set<String>, values: [String: String] = [:]) -> ManagementDetector {
        ManagementDetector(
            isForced: { key, _ in forced.contains(key) },
            readValue: { key, _ in values[key] }
        )
    }

    @Test("A key is managed only when a profile forces it")
    func forcedOnly() {
        let d = detector(forced: [])
        #expect(!d.isManaged(key: "jsonUrl"))
        #expect(d.allManagedKeys().isEmpty)
    }

    @Test("A forced alias locks its canonical key")
    func aliasLocksCanonical() {
        let d = detector(forced: ["ManifestURL"], values: ["ManifestURL": "https://example.com/m.json"])
        #expect(d.isManaged(key: "jsonUrl"))
        #expect(d.isManaged(key: "url"))
        #expect(d.managedValue(forKey: "jsonUrl") as? String == "https://example.com/m.json")
        #expect(d.allManagedKeys() == ["jsonUrl"])
    }

    @Test("Every GUI field can be locked by a profile")
    func everyFieldLockable() {
        let all = Set(ManagementDetector.keyAliases.values.flatMap { $0 })
        let d = detector(forced: all)
        for key in ["jsonUrl", "authorizationHeader", "followRedirects", "reboot", "silentMode",
                    "verboseMode", "dryRun", "userscriptOnly", "enableDialog", "dialogTitle",
                    "dialogMessage", "dialogIcon", "blurScreen", "retainCache", "networkTimeout"] {
            #expect(d.isManaged(key: key), "\(key) should be lockable")
        }
    }

    @Test("Save keys map to the canonical key")
    func canonicalMapping() {
        #expect(ManagementDetector.canonicalKey(for: "url") == "jsonUrl")
        #expect(ManagementDetector.canonicalKey(for: "headers") == "authorizationHeader")
        #expect(ManagementDetector.canonicalKey(for: "networkTimeout") == "networkTimeout")
    }
}

// MARK: - HelperPreferencePolicy Tests

@Suite("HelperPreferencePolicy Tests")
struct HelperPreferencePolicyTests {
    let notForced: (String) -> Bool = { _ in false }

    @Test("Accepts a known key of the right type in BootstrapMate's domain")
    func allowsKnownKey() {
        #expect(HelperPreferencePolicy.evaluate(domain: "com.github.bootstrapmate", key: "networkTimeout", kind: .int, isForced: notForced) == .allow)
        #expect(HelperPreferencePolicy.evaluate(domain: "com.github.bootstrapmate", key: "url", kind: .string, isForced: notForced) == .allow)
    }

    @Test("Refuses any other preference domain")
    func refusesOtherDomain() {
        #expect(HelperPreferencePolicy.evaluate(domain: "com.apple.loginwindow", key: "url", kind: .string, isForced: notForced) == .wrongDomain)
    }

    @Test("Refuses keys the Prefs window does not edit")
    func refusesUnknownKey() {
        #expect(HelperPreferencePolicy.evaluate(domain: "com.github.bootstrapmate", key: "Evil", kind: .string, isForced: notForced) == .unknownKey)
    }

    @Test("Refuses a value of the wrong type")
    func refusesWrongType() {
        #expect(HelperPreferencePolicy.evaluate(domain: "com.github.bootstrapmate", key: "reboot", kind: .string, isForced: notForced) == .wrongType)
    }

    @Test("Refuses a key a profile forces, including removal")
    func refusesManagedKey() {
        let forced: (String) -> Bool = { $0 == "url" }
        #expect(HelperPreferencePolicy.evaluate(domain: "com.github.bootstrapmate", key: "url", kind: .string, isForced: forced) == .managed)
        #expect(HelperPreferencePolicy.evaluate(domain: "com.github.bootstrapmate", key: "url", kind: nil, isForced: forced) == .managed)
    }

    @Test("Allows removing an allowed key")
    func allowsRemoval() {
        #expect(HelperPreferencePolicy.evaluate(domain: "com.github.bootstrapmate", key: "dialogIcon", kind: nil, isForced: notForced) == .allow)
    }
}

@Suite("Managed preferences file check")
struct ManagedPreferencesFileTests {
    @Test("Finds a key set in a managed preferences plist, and only that key")
    func readsManagedFile() throws {
        let path = NSTemporaryDirectory() + "managed-\(UUID().uuidString).plist"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try (["url": "https://example.invalid/m.json"] as NSDictionary).write(to: URL(fileURLWithPath: path))
        #expect(HelperPreferencePolicy.managedFileSetsKey("url", path: path))
        #expect(!HelperPreferencePolicy.managedFileSetsKey("networkTimeout", path: path))
        #expect(!HelperPreferencePolicy.managedFileSetsKey("url", path: path + ".missing"))
    }
}

@Suite("Dialog authorisation key and empty settings")
struct DialogAuthorisationKeyTests {
    @Test("Reads a trusted key file, trimming the trailing newline")
    func readsTrustedKey() throws {
        let dir = NSTemporaryDirectory() + "authkey-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/.authkey"
        FileManager.default.createFile(atPath: path, contents: Data("secret-key\n".utf8), attributes: [.posixPermissions: 0o600])
        #expect(DialogManager.authorisationKey(at: path) == "secret-key")
    }

    @Test("Ignores a missing, empty or world-writable key file")
    func ignoresUntrustedKey() throws {
        let dir = NSTemporaryDirectory() + "authkey-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(DialogManager.authorisationKey(at: dir + "/missing") == nil)
        let empty = dir + "/empty"
        FileManager.default.createFile(atPath: empty, contents: Data("\n".utf8), attributes: [.posixPermissions: 0o600])
        #expect(DialogManager.authorisationKey(at: empty) == nil)
        let open = dir + "/open"
        FileManager.default.createFile(atPath: open, contents: Data("key".utf8), attributes: nil)
        chmod(open, 0o666)
        #expect(DialogManager.authorisationKey(at: open) == nil)
    }

    @Test("Puts the key in DIALOG_AUTH_KEY and drops an inherited one when there is none")
    func environment() {
        let base = ["PATH": "/usr/bin", "DIALOG_AUTH_KEY": "inherited"]
        #expect(DialogManager.dialogEnvironment(base: base, key: "k")["DIALOG_AUTH_KEY"] == "k")
        #expect(DialogManager.dialogEnvironment(base: base, key: nil)["DIALOG_AUTH_KEY"] == nil)
        #expect(DialogManager.dialogEnvironment(base: base, key: nil)["PATH"] == "/usr/bin")
    }

    @Test("Treats an empty Authorization header as none")
    func emptyHeader() {
        #expect(NetworkManager.usableHeader(nil) == nil)
        #expect(NetworkManager.usableHeader("") == nil)
        #expect(NetworkManager.usableHeader("  ") == nil)
        #expect(NetworkManager.usableHeader("Basic abc") == "Basic abc")
    }
}

// MARK: - Command-line redaction

@Suite("Command-line redaction")
struct CommandLineRedactionTests {

    @Test("Hides the value after --headers and --reporting-header")
    func separateValue() {
        let args = ["managedbootstrapinstall", "--jsonurl", "https://example.com/m.json", "--headers", "Bearer abc", "--verbose"]
        #expect(CommandLineRedaction.redact(args) == ["managedbootstrapinstall", "--jsonurl", "https://example.com/m.json", "--headers", "<redacted>", "--verbose"])
        #expect(CommandLineRedaction.redact(["--reporting-header", "s3cret"]) == ["--reporting-header", "<redacted>"])
    }

    @Test("Hides the value in the --headers=value form, whatever the case")
    func equalsForm() {
        #expect(CommandLineRedaction.redact(["--headers=Basic dXNlcjpwYXNz"]) == ["--headers=<redacted>"])
        #expect(CommandLineRedaction.redact(["--HEADERS=x"]) == ["--HEADERS=<redacted>"])
    }

    @Test("Hides any argument that is an Authorization value")
    func authorizationValues() {
        #expect(CommandLineRedaction.redact(["Bearer abc"]) == ["<redacted>"])
        #expect(CommandLineRedaction.redact(["basic dXNlcjpwYXNz"]) == ["<redacted>"])
        #expect(CommandLineRedaction.redact(["Authorization: Bearer abc"]) == ["<redacted>"])
    }

    @Test("Leaves a command line with no credential exactly as it was")
    func noCredential() {
        let args = ["managedbootstrapinstall", "--jsonurl", "https://example.com/m.json", "--verbose", "--dry-run", "--dialog-title", "Basics"]
        #expect(CommandLineRedaction.redact(args) == args)
        #expect(CommandLineRedaction.redactedCommandLine(args) == args.joined(separator: " "))
    }

    @Test("A trailing --headers with no value is kept")
    func trailingOption() {
        #expect(CommandLineRedaction.redact(["--headers"]) == ["--headers"])
    }
}
