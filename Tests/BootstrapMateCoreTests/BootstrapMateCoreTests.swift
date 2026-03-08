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
