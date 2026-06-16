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

    public func runUserScriptOnly() {
        Logger.info("Running user script only mode.")
        guard let manifest = ManifestManager.shared.getManifest(),
              let userland = manifest.userland else {
            Logger.warning("No userland items to run.")
            return
        }
        for item in userland where item.type == "userscript" {
            _ = runScript(item)
        }
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
        
        if let stdout = String(data: outputData, encoding: .utf8), !stdout.isEmpty {
            Logger.debug("Script stdout: \(stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        if let stderr = String(data: errorData, encoding: .utf8), !stderr.isEmpty {
            Logger.debug("Script stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        let exitCode = task.terminationStatus
        
        if exitCode == 0 {
            Logger.success("Script succeeded: \(item.file)")
        } else {
            Logger.info("Script exited with code \(exitCode): \(item.file)")
        }
        
        return exitCode
    }
    
    /// Run a script for the current console user
    public func runAsUser(_ item: ManifestItem, uid: uid_t) -> Bool {
        Logger.debug("Running user script as uid \(uid): \(item.file)")
        
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
        
        // Use launchctl to run as user
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["asuser", String(uid), item.file]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            
            if item.donotwait != true {
                task.waitUntilExit()
                
                if task.terminationStatus != 0 {
                    Logger.error("User script failed with exit code \(task.terminationStatus)")
                    return false
                }
            }
            
            Logger.success("User script completed: \(item.file)")
            return true
        } catch {
            Logger.error("Could not run user script: \(error.localizedDescription)")
            return false
        }
    }
}
