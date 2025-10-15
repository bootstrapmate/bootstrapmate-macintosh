import Foundation

public final class ScriptManager {
    nonisolated(unsafe) public static let shared = ScriptManager()

    private init() {}

    public func runUserScriptOnly() {
        Logger.log("Running user script only mode.")
        guard let manifest = ManifestManager.shared.getManifest(),
              let userland = manifest.userland else {
            Logger.log("No userland items to run.")
            return
        }
        for item in userland where item.type == "userscript" {
            _ = runScript(item)
        }
    }

    @discardableResult
    public func runScript(_ item: ManifestItem) -> Bool {
        Logger.log("Running script: \(item.file) donotwait=\(item.donotwait == true)")
        let ok = ManifestManager.shared.downloadIfNeeded(item)
        if !ok {
            Logger.log("Failed to prepare script: \(item.file)")
            return false
        }

        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.file)

        if item.donotwait == true {
            let task = Process()
            task.launchPath = item.file
            do {
                try task.run()
            } catch {
                Logger.log("Could not launch script: \(error.localizedDescription)")
                return false
            }
            Logger.log("Launched script asynchronously: \(item.file)")
            return true
        } else {
            let task = Process()
            task.launchPath = item.file
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                Logger.log("Could not run script: \(error.localizedDescription)")
                return false
            }
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: output, encoding: .utf8) {
                Logger.log("Script output: \(str)")
            }
            if task.terminationStatus == 0 {
                Logger.log("Script succeeded: \(item.file)")
                return true
            } else {
                Logger.log("Script failed: \(item.file)")
                return false
            }
        }
    }
}
