import Foundation
import CryptoKit

public struct ManifestGenerator {

    public struct ManifestItem: Codable {
        public let name: String?
        public let file: String
        public let url: String
        public let hash: String
        public let type: String
        public let retries: Int?
        public let retrywait: Int?
        public let packageid: String?
        public let version: String?
        public let skip_if: String?
        public let donotwait: Bool?
    }

    public struct Manifest: Codable {
        public var preflight: [ManifestItem] = []
        public var setupassistant: [ManifestItem] = []
        public var userland: [ManifestItem] = []
    }

    public static func generateManifestJSON(from items: [BootstrapItem],
                                            baseURL: String,
                                            outputPath: String) throws {
        var manifest = Manifest()

        for item in items {
            guard let data = FileManager.default.contents(atPath: item.file) else {
                throw NSError(
                    domain: "ManifestGenerator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "File not found: \(item.file)"]
                )
            }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

            let manifestItem = ManifestItem(
                name: item.name,
                file: "/Library/bootstrapmate/\(URL(fileURLWithPath: item.file).lastPathComponent)",
                url: "\(baseURL)/\(item.type)/\(URL(fileURLWithPath: item.file).lastPathComponent)",
                hash: hash,
                type: item.type,
                retries: item.retries,
                retrywait: item.retrywait,
                packageid: item.packageid,
                version: item.version,
                skip_if: nil,
                donotwait: nil
            )

            switch item.type {
            case "rootscript":
                manifest.preflight.append(manifestItem)
            case "package":
                manifest.setupassistant.append(manifestItem)
            case "userscript":
                manifest.userland.append(manifestItem)
            default:
                continue
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(manifest)
        try jsonData.write(to: URL(fileURLWithPath: outputPath))
    }
}
