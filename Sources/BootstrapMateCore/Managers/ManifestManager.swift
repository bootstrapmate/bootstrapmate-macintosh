import Foundation
import CryptoKit

private final class ResultHolder: @unchecked Sendable {
    var success = false
    var manifest: BootstrapManifest?
}

public struct IntOrString: Codable {
    public let value: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let strValue = try? container.decode(String.self),
                  let intValue = Int(strValue) {
            value = intValue
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Int or String convertible to Int."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public final class ManifestManager {
    nonisolated(unsafe) public static let shared = ManifestManager()

    private var dryRun = false
    private var manifest: BootstrapManifest?

    private init() {}

    public func setDryRun(_ enable: Bool) {
        dryRun = enable
    }

    public func loadFromMDMOrLocal() {
        Logger.log("Loading manifest from MDM or local fallback.")
        // TODO: Implement managed preferences fallback handling.
    }

    @discardableResult
    public func loadManifest(from urlString: String,
                              followRedirects: Bool,
                              authHeader: String?,
                              skipValidation: Bool) -> Bool {
        guard let url = URL(string: urlString) else {
            Logger.log("Invalid URL string: \(urlString)")
            return false
        }
        let semaphore = DispatchSemaphore(value: 0)
        let resultHolder = ResultHolder()

        NetworkManager.shared.downloadData(
            from: url,
            followRedirects: followRedirects,
            authHeader: authHeader
        ) { data, error in
            defer { semaphore.signal() }
            if let data = data {
                do {
                    // Attempt to decode the manifest
                    let decoded = try JSONDecoder().decode(BootstrapManifest.self, from: data)
                    resultHolder.manifest = decoded
                    resultHolder.success = true
                } catch {
                    Logger.log("Failed to decode BootstrapManifest: \(error.localizedDescription)")
                }
            } else if let error = error {
                Logger.log("Network error: \(error.localizedDescription)")
            } else {
                Logger.log("Network error: unknown error")
            }
        }

        _ = semaphore.wait(timeout: .now() + 60)
        if resultHolder.success, let manifest = resultHolder.manifest {
            self.manifest = manifest
        }
        return resultHolder.success
    }

    public func getManifest() -> BootstrapManifest? {
        manifest
    }

    public func downloadIfNeeded(_ item: ManifestItem) -> Bool {
        let path = item.file
        let expectedHash = item.hash

        if let arch = item.skipIf, shouldSkip(arch: arch) {
            Logger.log("Skipping \(item.name ?? path) due to skip_if: \(arch)")
            return true
        }

        if FileManager.default.fileExists(atPath: path),
           let localHash = computeSHA256(of: path),
           localHash == expectedHash {
            Logger.log("Already have valid file: \(path). Skipping re-download.")
            return true
        }

        if dryRun {
            Logger.log("[Dry Run] Would download \(item.name ?? path).")
            return true
        }

        let attempts = item.retries?.value ?? BootstrapMateConstants.defaultRetryCount
        let waitSec = item.retrywait?.value ?? BootstrapMateConstants.defaultRetryDelay

        var triesLeft = attempts
        while triesLeft > 0 {
            triesLeft -= 1
            let ok = blockingDownload(item: item)
            if ok, let localHash = computeSHA256(of: path), localHash == expectedHash {
                Logger.log("Hash validated for \(path)")
                return true
            }
            Logger.log("Hash mismatch or download failed for \(path). Retrying in \(waitSec)s...")
            Thread.sleep(forTimeInterval: TimeInterval(waitSec))
        }

        Logger.log("All retries failed for \(path).")
        return false
    }

    private func blockingDownload(item: ManifestItem) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let resultHolder = ResultHolder()

        NetworkManager.shared.downloadFile(
            toPath: item.file,
            from: item.url,
            followRedirects: item.followRedirects ?? false,
            authHeader: nil
        ) { result in
            switch result {
            case .success:
                resultHolder.success = true
            case .failure(let error):
                Logger.log("Download error: \(error.localizedDescription)")
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 120)
        return resultHolder.success
    }

    private func computeSHA256(of filePath: String) -> String? {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            return nil
        }
        defer { fileHandle.closeFile() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: 16 * 1024)
            if !data.isEmpty {
                hasher.update(data: data)
                return true
            }
            return false
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func shouldSkip(arch: String) -> Bool {
        let isArm = arch.contains("arm") || arch.contains("apple_silicon")
        let isIntel = arch.contains("x86_64") || arch.contains("intel")
        let currentArch = localArch()

        if isArm && currentArch == "arm64" {
            return false
        } else if isArm && currentArch == "x86_64" {
            return true
        } else if isIntel && currentArch == "arm64" {
            return true
        } else if isIntel && currentArch == "x86_64" {
            return false
        }
        return false
    }

    private func localArch() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let chars = machineMirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8($0))) }
        let identifier = String(chars)
        return identifier.contains("arm64") ? "arm64" : "x86_64"
    }
}

public struct BootstrapManifest: Codable {
    public let preflight: [ManifestItem]?
    public let setupassistant: [ManifestItem]?
    public let userland: [ManifestItem]?
}

public struct ManifestItem: Codable {
    public let file: String
    public let hash: String
    public let url: String
    public let name: String?
    public let packageid: String?
    public let version: String?
    public let type: String
    public let retries: IntOrString?
    public let retrywait: IntOrString?
    public let skipIf: String?
    public let followRedirects: Bool?
    public let donotwait: Bool?
}
