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
import Network

@main
struct BootstrapMate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bootstrapmate",
        abstract: "BootstrapMate - Swift deployment utility for ADE-driven macOS setup",
        version: BootstrapMateConstants.version
    )

    @Option(name: .long, help: "JSON manifest URL to load before executing stages.")
    var jsonurl: String?

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
    
    @Flag(name: .long, help: "Disable SwiftDialog UI (headless mode).")
    var noDialog: Bool = false
    
    @Option(name: .long, help: "Custom dialog title.")
    var dialogTitle: String?
    
    @Option(name: .long, help: "Custom dialog message.")
    var dialogMessage: String?
    
    @Option(name: .long, help: "Maximum seconds to wait for network (default: 120).")
    var networkTimeout: Int = 120

    /// Thread-safe wrapper for network status
    private final class NetworkStatus: @unchecked Sendable {
        var isReady = false
    }

    /// Wait for network connectivity before proceeding
    private func waitForNetwork(timeout: Int) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let status = NetworkStatus()
        
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.github.bootstrapmate.networkmonitor")
        
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                status.isReady = true
                semaphore.signal()
            }
        }
        
        monitor.start(queue: queue)
        
        // Wait for network or timeout
        let result = semaphore.wait(timeout: .now() + .seconds(timeout))
        monitor.cancel()
        
        if result == .timedOut {
            // Final check - try a simple DNS lookup
            let host = CFHostCreateWithName(nil, "apple.com" as CFString).takeRetainedValue()
            var resolved = DarwinBoolean(false)
            CFHostStartInfoResolution(host, .addresses, nil)
            _ = CFHostGetAddressing(host, &resolved)
            return resolved.boolValue
        }
        
        return status.isReady
    }

    func run() throws {
        // Early fallback logging to /tmp in case main log dir doesn't exist yet
        let fallbackLog = "/tmp/bootstrapmate-startup.log"
        func earlyLog(_ msg: String) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestamp = df.string(from: Date())
            let entry = "[\(timestamp)] \(msg)\n"
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fallbackLog) {
                    if let handle = FileHandle(forWritingAtPath: fallbackLog) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    FileManager.default.createFile(atPath: fallbackLog, contents: data)
                }
            }
        }
        
        earlyLog("BootstrapMate v\(BootstrapMateConstants.version) starting...")
        earlyLog("  Arguments: \(CommandLine.arguments.joined(separator: " "))")
        earlyLog("  User: \(NSUserName())")
        earlyLog("  UID: \(getuid())")
        
        // Ensure log directory exists before initializing Logger
        let logDir = "/Library/Managed Bootstrap/logs"
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDir) {
            earlyLog("Creating log directory: \(logDir)")
            do {
                try fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true)
                earlyLog("Log directory created successfully")
            } catch {
                earlyLog("ERROR: Failed to create log directory: \(error.localizedDescription)")
            }
        } else {
            earlyLog("Log directory already exists")
        }
        
        // Initialize logger
        let version = BootstrapMateConstants.version
        Logger.initialize(
            logDirectory: logDir,
            version: version,
            verboseConsole: verbose,
            silentMode: silent
        )
        
        earlyLog("Logger initialized, log file: \(Logger.getLogFilePath() ?? "unknown")")
        
        Logger.info("BootstrapMate v\(version) started")
        Logger.debug("CLI arguments: \(CommandLine.arguments.joined(separator: " "))")
        earlyLog("Main logger active, continuing startup...")
        
        // Wait for network connectivity before proceeding
        Logger.info("Waiting for network connectivity (timeout: \(networkTimeout)s)...")
        if waitForNetwork(timeout: networkTimeout) {
            Logger.success("Network is available")
        } else {
            Logger.warning("Network check timed out - proceeding anyway")
        }
        
        // Brief delay to ensure filesystem is fully mounted during Setup Assistant
        if !FileManager.default.isWritableFile(atPath: "/Library/Managed Bootstrap") {
            Logger.info("Waiting for Data volume to be writable...")
            for i in 1...30 {
                Thread.sleep(forTimeInterval: 1)
                if FileManager.default.isWritableFile(atPath: "/Library") {
                    Logger.success("Data volume is now writable after \(i)s")
                    break
                }
                if i == 30 {
                    Logger.warning("Data volume still not writable after 30s - proceeding anyway")
                }
            }
        }
        
        // Wait for MDM configuration profile to be applied (during Setup Assistant)
        // The MDM profile with url preference may not be applied immediately at boot
        let mdmTimeout = 300 // 5 minutes
        if jsonurl == nil || jsonurl!.isEmpty {
            // No CLI URL provided, we need MDM config
            if !ConfigManager.shared.isValid() {
                Logger.info("Waiting for MDM configuration profile (timeout: \(mdmTimeout)s)...")
                earlyLog("Waiting for MDM config...")
                
                for i in 1...mdmTimeout {
                    // Reload preferences from MDM domains
                    if ConfigManager.shared.reloadManagedPreferences() {
                        Logger.success("MDM configuration received after \(i)s")
                        earlyLog("MDM config received after \(i)s")
                        break
                    }
                    
                    // Log progress every 30 seconds
                    if i % 30 == 0 {
                        Logger.debug("Still waiting for MDM config... (\(i)s elapsed)")
                    }
                    
                    Thread.sleep(forTimeInterval: 1)
                    
                    if i == mdmTimeout {
                        Logger.warning("MDM configuration not received within \(mdmTimeout)s")
                        earlyLog("MDM config timeout after \(mdmTimeout)s")
                    }
                }
            }
        }
        
        // Apply CLI arguments to ConfigManager (overrides MDM settings)
        ConfigManager.shared.applyCliArguments(
            jsonUrl: jsonurl,
            headers: headers,
            followRedirects: followRedirects,
            dryRun: dryRun,
            reboot: reboot,
            userscriptOnly: userscript,
            silentMode: silent,
            verboseMode: verbose
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
