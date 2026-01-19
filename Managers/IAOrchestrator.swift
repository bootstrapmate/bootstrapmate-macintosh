//
//  IAOrchestrator.swift
//  BootstrapMate
//
//  Main orchestrator for package installation across all stages.
//  Handles preflight, setupassistant, and userland phases with
//  proper status tracking and optional SwiftDialog UI.
//

import Foundation

public final class IAOrchestrator {
    nonisolated(unsafe) public static let shared = IAOrchestrator()
    
    /// Configuration for the orchestrator
    public struct OrchestratorConfig {
        public var enableDialog: Bool = true
        public var dialogTitle: String = "Setting up your Mac"
        public var dialogMessage: String = "Please wait while we configure your device..."
        public var dialogIcon: String? = nil
        public var blurScreen: Bool = false
        
        public init() {}
    }
    
    public var config = OrchestratorConfig()
    
    private init() {}
    
    // MARK: - Main Entry Point
    
    @discardableResult
    public func runAllStages(reboot: Bool) -> Bool {
        let startTime = Date()
        Logger.writeHeader("BootstrapMate Installation")
        
        // Initialize status tracking
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        StatusManager.shared.initialize(
            bootstrapUrl: ConfigManager.shared.config.jsonUrl ?? "",
            version: version
        )
        
        // Get manifest
        guard let manifest = ManifestManager.shared.getManifest() else {
            Logger.error("No manifest loaded.")
            return false
        }
        
        // Count total packages for progress
        let totalPackages = countTotalPackages(manifest)
        
        // Initialize dialog if available and enabled
        if config.enableDialog {
            DialogManager.shared.initialize(
                title: config.dialogTitle,
                message: config.dialogMessage,
                totalPackages: totalPackages,
                icon: config.dialogIcon,
                blurScreen: config.blurScreen
            )
        }
        
        var success = true
        
        // Phase 1: Preflight
        if let preflight = manifest.preflight, !preflight.isEmpty {
            let preflightResult = runPreflightStage(preflight)
            
            if preflightResult == .skipBootstrap {
                // Preflight returned 0 - skip remaining stages and cleanup
                Logger.info("Preflight script returned 0. Skipping bootstrap and cleaning up.")
                StatusManager.shared.setPhaseStatus(phase: .preflight, stage: .completed)
                cleanupAndExit(success: true)
                return true
            } else if preflightResult == .failed {
                success = false
            }
        }
        
        // Phase 2: Setup Assistant
        if success, let setupassistant = manifest.setupassistant, !setupassistant.isEmpty {
            success = runSetupAssistantStage(setupassistant)
        }
        
        // Phase 3: Userland (wait for user session)
        if success, let userland = manifest.userland, !userland.isEmpty {
            success = runUserlandStage(userland)
        }
        
        // Completion
        let duration = Date().timeIntervalSince(startTime)
        
        if success {
            StatusManager.shared.writeSuccessfulCompletionPlist()
            Logger.writeCompletion("All stages completed successfully")
            
            DialogManager.shared.complete(message: "Setup Complete!")
            
            // Allow user to see completion before closing
            if config.enableDialog && DialogManager.shared.isDialogAvailable() {
                Thread.sleep(forTimeInterval: 3)
            }
        } else {
            Logger.error("Installation completed with errors")
            DialogManager.shared.updateProgressText(text: "Setup completed with errors")
        }
        
        // Close dialog
        DialogManager.shared.close()
        
        // Handle reboot
        if reboot && success {
            Logger.info("Reboot requested, triggering in 5 seconds...")
            CleanupManager.shared.triggerReboot(after: 5)
        }
        
        // Register cleanup tasks
        registerCleanupTasks()
        
        Logger.writeSessionSummary()
        return success
    }
    
    // MARK: - Preflight Stage
    
    private enum PreflightResult {
        case continueBootstrap  // Exit code 1+ = continue with setup
        case skipBootstrap      // Exit code 0 = skip remaining stages
        case failed             // Script execution failed
    }
    
    private func runPreflightStage(_ items: [ManifestItem]) -> PreflightResult {
        Logger.writeSection("Preflight Stage")
        StatusManager.shared.setPhaseStatus(phase: .preflight, stage: .running)
        DialogManager.shared.notifyPhaseStarted(phase: "Preflight")
        
        // Preflight only supports a single rootscript per InstallApplications spec
        guard let firstScript = items.first(where: { $0.type == "rootscript" }) else {
            Logger.info("No preflight rootscript found, continuing with bootstrap")
            StatusManager.shared.setPhaseStatus(phase: .preflight, stage: .skipped)
            return .continueBootstrap
        }
        
        let displayName = firstScript.name ?? firstScript.file
        DialogManager.shared.addListItem(name: displayName, status: .pending)
        
        Logger.writeProgress("Running preflight script", displayName)
        DialogManager.shared.updateListItem(name: displayName, status: .wait, statusText: "Running...")
        
        // Download if needed
        if !ManifestManager.shared.downloadIfNeeded(firstScript) {
            Logger.error("Failed to download preflight script: \(displayName)")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Download failed")
            StatusManager.shared.setPhaseStatus(phase: .preflight, stage: .failed, errorMessage: "Download failed")
            return .failed
        }
        
        // Run the script and capture exit code
        let exitCode = ScriptManager.shared.runScriptWithExitCode(firstScript)
        
        if exitCode == 0 {
            // Exit 0 = Skip bootstrap, machine is already configured
            Logger.success("Preflight script exited 0 - skipping bootstrap")
            DialogManager.shared.updateListItem(name: displayName, status: .success, statusText: "Already configured")
            StatusManager.shared.setPhaseStatus(phase: .preflight, stage: .completed, exitCode: 0)
            return .skipBootstrap
        } else if exitCode > 0 {
            // Exit 1+ = Continue with bootstrap
            Logger.info("Preflight script exited \(exitCode) - continuing with bootstrap")
            DialogManager.shared.updateListItem(name: displayName, status: .success, statusText: "Continue setup")
            StatusManager.shared.setPhaseStatus(phase: .preflight, stage: .completed, exitCode: Int(exitCode))
            return .continueBootstrap
        } else {
            // Negative exit code = error
            Logger.error("Preflight script failed with exit code \(exitCode)")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Exit code: \(exitCode)")
            StatusManager.shared.setPhaseStatus(phase: .preflight, stage: .failed, errorMessage: "Exit code: \(exitCode)", exitCode: Int(exitCode))
            return .failed
        }
    }
    
    // MARK: - Setup Assistant Stage
    
    private func runSetupAssistantStage(_ items: [ManifestItem]) -> Bool {
        Logger.writeSection("Setup Assistant Stage")
        StatusManager.shared.setPhaseStatus(phase: .setupAssistant, stage: .running)
        DialogManager.shared.notifyPhaseStarted(phase: "Setup Assistant")
        
        // Add all items to dialog
        for item in items {
            let displayName = item.name ?? item.file
            DialogManager.shared.addListItem(name: displayName, status: .pending)
        }
        
        var allSuccess = true
        
        for item in items {
            let displayName = item.name ?? item.file
            
            // Check architecture skip condition
            if let skipIf = item.skipIf, shouldSkipForArchitecture(skipIf) {
                Logger.writeSkipped("\(displayName) (architecture: \(skipIf))")
                DialogManager.shared.notifyPackageSkipped(packageName: displayName, reason: "Not for this architecture")
                continue
            }
            
            let success = processItem(item, phase: .setupAssistant)
            if !success {
                allSuccess = false
                // Continue processing remaining items even on failure
            }
        }
        
        let stage: InstallationStage = allSuccess ? .completed : .failed
        StatusManager.shared.setPhaseStatus(phase: .setupAssistant, stage: stage)
        
        return allSuccess
    }
    
    // MARK: - Userland Stage
    
    private func runUserlandStage(_ items: [ManifestItem]) -> Bool {
        Logger.writeSection("Userland Stage")
        StatusManager.shared.setPhaseStatus(phase: .userland, stage: .starting)
        DialogManager.shared.notifyPhaseStarted(phase: "Userland")
        
        // Wait for user session
        waitForUserSession()
        
        StatusManager.shared.setPhaseStatus(phase: .userland, stage: .running)
        
        // Add all items to dialog
        for item in items {
            let displayName = item.name ?? item.file
            DialogManager.shared.addListItem(name: displayName, status: .pending)
        }
        
        var allSuccess = true
        
        for item in items {
            let displayName = item.name ?? item.file
            
            // Check architecture skip condition
            if let skipIf = item.skipIf, shouldSkipForArchitecture(skipIf) {
                Logger.writeSkipped("\(displayName) (architecture: \(skipIf))")
                DialogManager.shared.notifyPackageSkipped(packageName: displayName, reason: "Not for this architecture")
                continue
            }
            
            let success = processItem(item, phase: .userland)
            if !success {
                allSuccess = false
            }
        }
        
        let stage: InstallationStage = allSuccess ? .completed : .failed
        StatusManager.shared.setPhaseStatus(phase: .userland, stage: stage)
        
        return allSuccess
    }
    
    // MARK: - Item Processing
    
    private func processItem(_ item: ManifestItem, phase: InstallationPhase) -> Bool {
        let displayName = item.name ?? item.file
        
        Logger.writeProgress("Processing", displayName)
        
        switch item.type {
        case "package":
            return processPackage(item, displayName: displayName)
            
        case "rootscript":
            return processRootScript(item, displayName: displayName)
            
        case "userscript":
            return processUserScript(item, displayName: displayName)
            
        default:
            Logger.warning("Unknown item type: \(item.type)")
            DialogManager.shared.updateListItem(name: displayName, status: .fail, statusText: "Unknown type")
            return false
        }
    }
    
    private func processPackage(_ item: ManifestItem, displayName: String) -> Bool {
        // Check if already installed
        if let pkgID = item.packageid, let ver = item.version,
           PackageManager.shared.isPackageInstalled(packageID: pkgID, minVersion: ver) {
            Logger.writeSkipped("\(displayName) - already installed (>= \(ver))")
            DialogManager.shared.notifyPackageSkipped(packageName: displayName)
            return true
        }
        
        // Download
        DialogManager.shared.notifyDownloadStarted(packageName: displayName)
        
        guard ManifestManager.shared.downloadIfNeeded(item) else {
            Logger.writeError("Failed to download \(displayName)")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Download failed")
            return false
        }
        
        // Install
        DialogManager.shared.notifyInstallStarted(packageName: displayName)
        
        let installSuccess = PackageManager.shared.installPackage(atPath: item.file)
        
        if installSuccess {
            Logger.writeSuccess("\(displayName) installed successfully")
            DialogManager.shared.notifyPackageSuccess(packageName: displayName)
        } else {
            Logger.writeError("Failed to install \(displayName)")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Installation failed")
        }
        
        return installSuccess
    }
    
    private func processRootScript(_ item: ManifestItem, displayName: String) -> Bool {
        DialogManager.shared.updateListItem(name: displayName, status: .wait, statusText: "Running...")
        
        // Download if needed
        guard ManifestManager.shared.downloadIfNeeded(item) else {
            Logger.writeError("Failed to download script \(displayName)")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Download failed")
            return false
        }
        
        let success = ScriptManager.shared.runScript(item)
        
        if success {
            Logger.writeSuccess("\(displayName) completed")
            DialogManager.shared.notifyPackageSuccess(packageName: displayName)
        } else {
            Logger.writeError("\(displayName) failed")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Script failed")
        }
        
        return success
    }
    
    private func processUserScript(_ item: ManifestItem, displayName: String) -> Bool {
        DialogManager.shared.updateListItem(name: displayName, status: .wait, statusText: "Running...")
        
        // Download if needed
        guard ManifestManager.shared.downloadIfNeeded(item) else {
            Logger.writeError("Failed to download user script \(displayName)")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Download failed")
            return false
        }
        
        let success = ScriptManager.shared.runScript(item)
        
        if success {
            Logger.writeSuccess("\(displayName) completed")
            DialogManager.shared.notifyPackageSuccess(packageName: displayName)
        } else {
            Logger.writeError("\(displayName) failed")
            DialogManager.shared.notifyPackageFailure(packageName: displayName, error: "Script failed")
        }
        
        return success
    }
    
    // MARK: - Helper Methods
    
    private func countTotalPackages(_ manifest: BootstrapManifest) -> Int {
        var count = 0
        if let preflight = manifest.preflight { count += preflight.count }
        if let setup = manifest.setupassistant { count += setup.count }
        if let userland = manifest.userland { count += userland.count }
        return count
    }
    
    private func shouldSkipForArchitecture(_ skipIf: String) -> Bool {
        let currentArch = getCurrentArchitecture()
        let skipLower = skipIf.lowercased()
        
        // ARM-based skip conditions
        if (skipLower.contains("arm") || skipLower.contains("apple_silicon")) && currentArch == "arm64" {
            return true
        }
        
        // Intel-based skip conditions
        if (skipLower.contains("x86_64") || skipLower.contains("intel")) && currentArch == "x86_64" {
            return true
        }
        
        return false
    }
    
    private func getCurrentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let chars = machineMirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8($0))) }
        let identifier = String(chars)
        return identifier.contains("arm64") ? "arm64" : "x86_64"
    }
    
    private func waitForUserSession() {
        Logger.info("Waiting for user session...")
        DialogManager.shared.updateProgressText(text: "Waiting for user to log in...")
        
        while true {
            let (username, uid) = SessionManager.shared.getConsoleUser()
            
            // Skip system users
            if let user = username,
               user != "loginwindow",
               user != "_mbsetupuser",
               user != "root",
               !user.hasPrefix("_") {
                Logger.success("User session detected: \(user) (uid: \(uid ?? 0))")
                DialogManager.shared.updateProgressText(text: "User \(user) logged in, continuing...")
                Thread.sleep(forTimeInterval: 2) // Brief delay for UI stability
                return
            }
            
            Logger.debug("No valid user session yet, waiting...")
            Thread.sleep(forTimeInterval: 2)
        }
    }
    
    private func cleanupAndExit(success: Bool) {
        DialogManager.shared.complete(message: success ? "Device already configured" : "Setup failed")
        Thread.sleep(forTimeInterval: 2)
        DialogManager.shared.close()
        registerCleanupTasks()
        Logger.writeSessionSummary()
    }
}

// MARK: - Cleanup Registration

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
        Logger.error("Failed to register cleanup tasks: \(error.localizedDescription)")
    }
}

