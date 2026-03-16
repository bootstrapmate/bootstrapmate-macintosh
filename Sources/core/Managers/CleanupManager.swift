//  CleanupManager.swift
//  BootstrapMate
//
//  Ported from the installapplications Swift migration.
//

import Foundation

public class CleanupManager {
    nonisolated(unsafe) public static let shared = CleanupManager()

    public func registerLaunchDaemon(identifier: String, executablePath: String) throws {
        let plistContent: [String: Any] = [
            "Label": identifier,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let plistPath = "/Library/LaunchDaemons/\(identifier).plist"
        let plistURL = URL(fileURLWithPath: plistPath)
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)

        try plistData.write(to: plistURL, options: [.atomic])
        try setPermissions(path: plistPath, permissions: 0o644)

        let loadTask = Process()
        loadTask.launchPath = "/bin/launchctl"
        loadTask.arguments = ["load", plistPath]
        try loadTask.run()
        loadTask.waitUntilExit()
    }

    public func registerLaunchAgent(identifier: String, path: String, userUID: uid_t) {
        let plistPath = "/Library/LaunchAgents/\(identifier).plist"
        let plist: [String: Any] = [
            "Label": identifier,
            "ProgramArguments": [path],
            "RunAtLoad": true
        ]

        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try plistData.write(to: URL(fileURLWithPath: plistPath))
            Logger.log("LaunchAgent \(identifier) registered successfully at \(plistPath).")

            try FileManager.default.setAttributes([.posixPermissions: 0o644, .ownerAccountID: userUID],
                                                  ofItemAtPath: plistPath)
            Logger.log("Set ownership to UID \(userUID) for LaunchAgent \(identifier).")

        } catch {
            Logger.log("Failed to register LaunchAgent \(identifier): \(error.localizedDescription)")
        }
    }

    public func triggerReboot(after seconds: Int) {
        Logger.log("Triggering reboot in \(seconds) seconds.")
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) {
            let script = """
            /usr/bin/osascript -e 'tell application "System Events" to restart'
            """
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", script]
            do {
                try task.run()
            } catch {
                Logger.log("Failed to trigger reboot: \(error.localizedDescription)")
            }
        }
    }

    public func removeLaunchDaemon(identifier: String) {
        Logger.log("Removing LaunchDaemon: \(identifier)")
        let removeTask = Process()
        removeTask.launchPath = "/bin/launchctl"
        removeTask.arguments = ["remove", identifier]
        removeTask.launch()
        removeTask.waitUntilExit()

        let plistPath = "/Library/LaunchDaemons/\(identifier).plist"
        if FileManager.default.fileExists(atPath: plistPath) {
            try? FileManager.default.removeItem(atPath: plistPath)
        }
    }
    
    /// Cleans the cache directory (removes all files in /Library/Managed Bootstrap/cache/)
    /// This should only be called after a successful bootstrap run when retainCache = false
    public func cleanCache() {
        let cacheDir = BootstrapMateConstants.cacheDirectory
        Logger.debug("Cleaning cache directory: \(cacheDir)")
        
        guard FileManager.default.fileExists(atPath: cacheDir) else {
            Logger.debug("Cache directory doesn't exist, nothing to clean")
            return
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: cacheDir)
            var filesRemoved = 0
            
            for file in files {
                let filePath = (cacheDir as NSString).appendingPathComponent(file)
                try FileManager.default.removeItem(atPath: filePath)
                filesRemoved += 1
            }
            
            if filesRemoved > 0 {
                Logger.info("Cache cleaned: \(filesRemoved) file(s) removed from \(cacheDir)")
            } else {
                Logger.debug("Cache directory empty, no files to remove")
            }
        } catch {
            Logger.warning("Failed to clean cache: \(error.localizedDescription)")
        }
    }
}

private func setPermissions(path: String, permissions: Int) throws {
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
}
