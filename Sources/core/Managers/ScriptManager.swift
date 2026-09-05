//
//  ScriptManager.swift
//  BootstrapMate
//
//  Manages execution of rootscripts and userscripts from the manifest.
//

import Foundation

public final class ScriptManager {
    nonisolated(unsafe) public static let shared = ScriptManager()

    private init() {}

    /// Run only the manifest's `userscript` items.
    /// Returns true when every script succeeded, false when any failed.
    @discardableResult
    public func runUserScriptOnly() -> Bool {
        Logger.info("Running user script only mode.")
        guard let manifest = ManifestManager.shared.getManifest(),
              let userland = manifest.userland else {
            Logger.warning("No userland items to run.")
            return true
        }

        let scripts = userland.filter { $0.type == "userscript" }
        if scripts.isEmpty {
            Logger.warning("No userland items to run.")
            return true
        }

        // Invoked as root (from the daemon) every script has to be handed to the
        // console user; invoked as the user already (from a LaunchAgent) it runs
        // in the right context and needs no dispatch.
        let needsUserDispatch = geteuid() == 0
        let consoleUser = SessionManager.shared.getValidConsoleUser()

        var failures: [String] = []

        for item in scripts {
            let displayName = item.name ?? item.file

            if needsUserDispatch {
                guard let user = consoleUser else {
                    Logger.error("Cannot run \(displayName) as a user: no console user is logged in")
                    failures.append(displayName)
                    continue
                }
                if !runAsUser(item, uid: user.uid, username: user.username) {
                    failures.append(displayName)
                }
            } else if !runScript(item) {
                failures.append(displayName)
            }
        }

        if failures.isEmpty {
            Logger.success("All \(scripts.count) user script(s) completed successfully")
            return true
        }

        Logger.error("\(failures.count) of \(scripts.count) user script(s) failed: \(failures.joined(separator: ", "))")
        return false
    }

    /// Run a script and return success/failure (true = exit 0, false = non-zero)
    @discardableResult
    public func runScript(_ item: ManifestItem) -> Bool {
        let exitCode = runScriptWithExitCode(item)
        return exitCode == 0
    }
    
    /// Run a script and return the actual exit code
    /// Returns: Exit code (0+ for actual codes, -1 for execution errors)
    public func runScriptWithExitCode(_ item: ManifestItem) -> Int32 {
        Logger.debug("Running script: \(item.file) donotwait=\(item.donotwait == true)")
        
        // Ensure script is downloaded
        let ok = ManifestManager.shared.downloadIfNeeded(item)
        if !ok {
            Logger.error("Failed to prepare script: \(item.file)")
            return -1
        }

        // Set executable permission
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.file)
        } catch {
            Logger.warning("Could not set executable permission: \(error.localizedDescription)")
        }

        // Handle async execution (donotwait)
        if item.donotwait == true {
            return runAsyncScript(item)
        } else {
            return runSyncScript(item)
        }
    }
    
    /// Run script asynchronously (fire and forget)
    private func runAsyncScript(_ item: ManifestItem) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: item.file)
        
        // Set environment
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment
        
        do {
            try task.run()
            Logger.info("Launched script asynchronously: \(item.file)")
            // For async scripts, we return 0 to indicate successful launch
            return 0
        } catch {
            Logger.error("Could not launch script: \(error.localizedDescription)")
            return -1
        }
    }
    
    /// Run script synchronously and wait for completion
    private func runSyncScript(_ item: ManifestItem) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: item.file)
        
        // Set working directory to script location
        if let scriptDir = URL(fileURLWithPath: item.file).deletingLastPathComponent() as URL? {
            task.currentDirectoryURL = scriptDir
        }
        
        // Set environment
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment
        
        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Logger.error("Could not run script: \(error.localizedDescription)")
            return -1
        }
        
        // Log output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        Logger.output(
            from: item.file,
            stdout: String(data: outputData, encoding: .utf8),
            stderr: String(data: errorData, encoding: .utf8)
        )
        
        let exitCode = task.terminationStatus
        
        if exitCode == 0 {
            Logger.success("Script succeeded: \(item.file)")
        } else {
            Logger.info("Script exited with code \(exitCode): \(item.file)")
        }
        
        return exitCode
    }
    
    /// Run a script in the console user's context.
    ///
    /// `launchctl asuser` only moves the process into the target user's GUI
    /// bootstrap namespace — it does not drop privileges — so the script is
    /// handed to `sudo -u` as well. Without that the script would still run as
    /// root, with root's HOME and user defaults domain, which is exactly what a
    /// `userscript` must not do.
    public func runAsUser(_ item: ManifestItem, uid: uid_t, username: String) -> Bool {
        Logger.debug("Running user script as \(username) (uid \(uid)): \(item.file)")

        let ok = ManifestManager.shared.downloadIfNeeded(item)
        if !ok {
            Logger.error("Failed to prepare user script: \(item.file)")
            return false
        }

        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.file)
        } catch {
            Logger.warning("Could not set executable permission: \(error.localizedDescription)")
        }

        // Use launchctl to enter the user's GUI domain, and sudo to become them
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["asuser", String(uid), "/usr/bin/sudo", "-u", username, item.file]

        // Set working directory to script location
        task.currentDirectoryURL = URL(fileURLWithPath: item.file).deletingLastPathComponent()

        // Set environment
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment

        // Async execution (donotwait): fire and forget, no pipes to drain
        if item.donotwait == true {
            do {
                try task.run()
                Logger.info("Launched user script asynchronously: \(item.file)")
                return true
            } catch {
                Logger.error("Could not launch user script: \(error.localizedDescription)")
                return false
            }
        }

        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            Logger.error("Could not run user script: \(error.localizedDescription)")
            return false
        }

        // Drain the pipes before waiting: a script that writes more than the
        // pipe buffer holds would otherwise block forever on a full pipe with
        // waitUntilExit() never returning.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        // Log output
        Logger.output(
            from: item.file,
            stdout: String(data: outputData, encoding: .utf8),
            stderr: String(data: errorData, encoding: .utf8)
        )

        let exitCode = task.terminationStatus

        if exitCode == 0 {
            Logger.success("User script completed: \(item.file)")
            return true
        }

        Logger.error("User script exited with code \(exitCode): \(item.file)")
        return false
    }
}
