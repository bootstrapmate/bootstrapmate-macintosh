import Foundation

public final class PackageManager {
    nonisolated(unsafe) public static let shared = PackageManager()

    private init() {}

    public func isPackageInstalled(packageID: String, minVersion: String?) -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/pkgutil"
        task.arguments = ["--pkg-info-plist", packageID]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
              let installedVersion = plist["pkg-version"] as? String else {
            return false
        }

        if let minVer = minVersion {
            return versionCompare(installedVersion, minVer) >= 0
        }
        return true
    }

    @discardableResult
    public func installPackage(atPath pkgPath: String) -> Bool {
        Logger.log("Installing package at \(pkgPath)")
        let task = Process()
        task.launchPath = "/usr/sbin/installer"
        task.arguments = ["-pkg", pkgPath, "-target", "/"]
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            Logger.log("Installed \(pkgPath) successfully.")
            return true
        } else {
            Logger.log("Failed installing \(pkgPath).")
            return false
        }
    }

    private func versionCompare(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return -1 }
            if p1 > p2 { return 1 }
        }
        return 0
    }
}
