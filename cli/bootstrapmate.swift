//
//  bootstrapmate.swift
//  BootstrapMate
//
//  CLI entry point for BootstrapMate - Swift deployment utility for ADE-driven macOS setup.
//  Supports MDM managed preferences, CLI arguments, and graceful fallbacks.
//

import Foundation
import ArgumentParser
import BootstrapMateCore

@main
struct BootstrapMate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "installapplications",
        abstract: "BootstrapMate - Swift deployment utility for ADE-driven macOS setup",
        version: BootstrapMateConstants.version
    )

    @Option(name: .long, help: "JSON manifest URL to load before executing stages.")
    var url: String?

    @Option(name: .long, help: "Optional authorization header value (e.g., 'Basic xxx').")
    var headers: String?

    @Flag(name: .long, help: "When set, no installer actions are performed.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Follow HTTP redirects while downloading manifests and artifacts.")
    var followRedirects: Bool = false

    @Flag(name: .long, help: "Only run userland scripts and exit.")
    var userscript: Bool = false

    @Flag(name: .long, help: "Trigger a reboot after all stages complete.")
    var reboot: Bool = false
    
    @Flag(name: .long, help: "Run in silent mode (no console output).")
    var silent: Bool = false
    
    @Flag(name: .long, help: "Enable verbose logging output.")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Retain cache files after successful run (useful for debugging).")
    var retainCache: Bool = false
    
    @Flag(name: .long, help: "Force bootstrap run on production devices (creates trigger file and exits).")
    var forceRun: Bool = false
    
    @Flag(name: .long, help: "Disable SwiftDialog UI (headless mode).")
    var noDialog: Bool = false
    
    @Option(name: .long, help: "Custom dialog title.")
    var dialogTitle: String?
    
    @Option(name: .long, help: "Custom dialog message.")
    var dialogMessage: String?

    func run() throws {
        // Handle --force-run flag (creates trigger file and exits)
        if forceRun {
            let forceRunPath = BootstrapMateConstants.forceRunFlagPath
            let forceRunDir = BootstrapMateConstants.managedBootstrapDir
            
            // Ensure directory exists
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: forceRunDir) {
                try? fileManager.createDirectory(atPath: forceRunDir, withIntermediateDirectories: true)
            }
            
            // Create/touch the trigger file
            if fileManager.createFile(atPath: forceRunPath, contents: nil) {
                print("[+] Force-run trigger created at \(forceRunPath)")
                print("[i] LaunchDaemon will start BootstrapMate momentarily...")
                Foundation.exit(0)
            } else {
                print("[X] Failed to create force-run trigger at \(forceRunPath)")
                print("[i] Try: sudo touch \"\(forceRunPath)\"")
                Foundation.exit(1)
            }
        }
        
        // Initialize logger first
        let version = BootstrapMateConstants.version
        Logger.initialize(
            logDirectory: BootstrapMateConstants.logDirectory,
            version: version,
            verboseConsole: verbose,
            silentMode: silent
        )
        
        Logger.info("BootstrapMate v\(version) started")
        Logger.debug("CLI arguments: \(CommandLine.arguments.joined(separator: " "))")
        
        // Apply CLI arguments to ConfigManager (overrides MDM settings)
        ConfigManager.shared.applyCliArguments(
            jsonUrl: url,
            headers: headers,
            followRedirects: followRedirects,
            dryRun: dryRun,
            reboot: reboot,
            userscriptOnly: userscript,
            silentMode: silent,
            verboseMode: verbose,
            retainCache: retainCache
        )
        
        // Debug: Show effective configuration
        if verbose {
            ConfigManager.shared.printCurrentConfig()
        }
        
        // Set up network manager with auth header if provided
        let effectiveConfig = ConfigManager.shared.config
        if let authHeader = effectiveConfig.authorizationHeader {
            NetworkManager.shared.authorizationHeader = authHeader
        }
        
        // Load manifest
        var manifestLoaded = false
        
        if let url = effectiveConfig.jsonUrl, !url.isEmpty {
            Logger.info("Loading manifest from: \(url)")
            manifestLoaded = ManifestManager.shared.loadManifest(
                from: url,
                followRedirects: effectiveConfig.followRedirects,
                authHeader: effectiveConfig.authorizationHeader,
                skipValidation: false
            )
            
            if !manifestLoaded {
                Logger.error("Failed to load manifest from \(url)")
                Foundation.exit(1)
            }
        } else {
            // No URL provided - check if we have embedded config or should fail
            Logger.warning("No JSON URL provided via CLI or MDM")
            
            // Try to fetch from ConfigManager's external config
            if ConfigManager.shared.fetchExternalConfig() {
                Logger.info("Loaded external config from MDM preferences")
                // Convert BootstrapConfig to manifest loading
                // For now, we require jsonUrl
            } else {
                Logger.error("No manifest URL configured. Use --jsonurl or configure via MDM profile.")
                Foundation.exit(1)
            }
        }
        
        // Set dry run mode
        ManifestManager.shared.setDryRun(effectiveConfig.dryRun)
        
        // Configure orchestrator
        var orchestratorConfig = IAOrchestrator.OrchestratorConfig()
        orchestratorConfig.enableDialog = !noDialog && !silent
        
        if let title = dialogTitle {
            orchestratorConfig.dialogTitle = title
        }
        if let message = dialogMessage {
            orchestratorConfig.dialogMessage = message
        }
        
        IAOrchestrator.shared.config = orchestratorConfig
        
        // Handle userscript-only mode
        if effectiveConfig.userscriptOnly {
            Logger.info("Running in userscript-only mode")
            ScriptManager.shared.runUserScriptOnly()
            Logger.writeSessionSummary()
            Foundation.exit(0)
        }
        
        // Run all stages
        let success = IAOrchestrator.shared.runAllStages(reboot: effectiveConfig.reboot)
        
        Logger.writeSessionSummary()
        Foundation.exit(success ? 0 : 1)
    }
}
