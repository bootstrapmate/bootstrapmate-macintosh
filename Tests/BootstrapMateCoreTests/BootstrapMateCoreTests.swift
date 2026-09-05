import Testing
import Foundation
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
