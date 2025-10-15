import Foundation

public final class IAOrchestrator {
    nonisolated(unsafe) public static let shared = IAOrchestrator()

    private init() {}

    @discardableResult
    public func runAllStages(reboot: Bool) -> Bool {
        guard let manifest = ManifestManager.shared.getManifest() else {
            Logger.log("No manifest loaded.")
            return false
        }

        if let preflight = manifest.preflight {
            for item in preflight where item.type == "rootscript" {
                Logger.log("Running preflight script: \(item.file)")
                let ok = ScriptManager.shared.runScript(item)
                if ok {
                    Logger.log("Preflight script exit code = 0. Stopping all further tasks.")
                    return true
                } else {
                    Logger.log("Preflight script returned non-zero. Continuing setupassistant.")
                }
            }
        }

        if let setupassistant = manifest.setupassistant {
            for item in setupassistant {
                switch item.type {
                case "package":
                    if let pkgID = item.packageid, let ver = item.version,
                       PackageManager.shared.isPackageInstalled(packageID: pkgID, minVersion: ver) {
                        Logger.log("Skipping \(item.file), package \(pkgID) >= \(ver) already installed.")
                        continue
                    }
                    if ManifestManager.shared.downloadIfNeeded(item) {
                        _ = PackageManager.shared.installPackage(atPath: item.file)
                    }
                case "rootscript", "userscript":
                    _ = ScriptManager.shared.runScript(item)
                default:
                    Logger.log("Unknown type in setupassistant: \(item.type)")
                }
            }
        }

        if let userland = manifest.userland, !userland.isEmpty {
            waitForUserSession()
            for item in userland {
                switch item.type {
                case "package":
                    if let pkgID = item.packageid, let ver = item.version,
                       PackageManager.shared.isPackageInstalled(packageID: pkgID, minVersion: ver) {
                        Logger.log("Skipping \(item.file), package \(pkgID) >= \(ver) installed.")
                        continue
                    }
                    if ManifestManager.shared.downloadIfNeeded(item) {
                        _ = PackageManager.shared.installPackage(atPath: item.file)
                    }
                case "rootscript", "userscript":
                    _ = ScriptManager.shared.runScript(item)
                default:
                    Logger.log("Unknown type in userland: \(item.type)")
                }
            }
        }

        if reboot {
            CleanupManager.shared.triggerReboot(after: 5)
        }

        registerCleanupTasks()
        return true
    }

    private func waitForUserSession() {
        Logger.log("Waiting for real user session (not loginwindow/_mbsetupuser)...")
        while true {
            let (username, uid) = SessionManager.shared.getConsoleUser()
            if username == nil || username == "loginwindow" || username == "_mbsetupuser" {
                Logger.log("No real user yet, sleeping 2s...")
                Thread.sleep(forTimeInterval: 2)
            } else {
                Logger.log("Detected real user: \(username ?? "unknown") (uid \(uid ?? 0))")
                break
            }
        }
    }
}

public func registerCleanupTasks() {
    do {
        try CleanupManager.shared.registerLaunchDaemon(
            identifier: BootstrapMateConstants.daemonIdentifier,
            executablePath: BootstrapMateConstants.executablePath
        )

        let (username, uid) = SessionManager.shared.getConsoleUser()
        if let userUID = uid, username != nil {
            CleanupManager.shared.registerLaunchAgent(
                identifier: BootstrapMateConstants.daemonIdentifier,
                path: BootstrapMateConstants.executablePath,
                userUID: userUID
            )
        }
    } catch {
        Logger.log("Failed to register LaunchDaemon or LaunchAgent: \(error.localizedDescription)")
    }
}
