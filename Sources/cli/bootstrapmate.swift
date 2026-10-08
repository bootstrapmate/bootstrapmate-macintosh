//
//  bootstrapmate.swift
//  BootstrapMate
//
//  CLI entry point for BootstrapMate - Swift deployment utility for ADE-driven macOS setup.
//  Supports managed preferences, CLI arguments, and graceful fallbacks.
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

    @Flag(name: .long, help: "Download and verify every item, but install nothing, run no scripts and leave the Mac unchanged.")
    var dryRun: Bool = false

    @Flag(
        inversion: .prefixedNo,
        help: "Follow HTTP redirects when downloading the manifest and its items (default: on, or the followRedirects preference). --no-follow-redirects refuses them."
    )
    var followRedirects: Bool?

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
    
    @Option(name: .long, help: "Maximum seconds to wait for network (default: the networkTimeout preference, else 120).")
    var networkTimeout: Int?

    @Option(name: .long, help: "URL to POST a run summary to on completion (vendor-neutral JSON).")
    var reportingUrl: String?
    @Flag(name: .long, help: "Skip installer-package signature verification (NOT recommended).")
    var noVerifySignature: Bool = false

    @Option(name: .long, help: "Require installer packages to be signed by this Apple Team ID.")
    var expectedTeamId: String?

    @Flag(name: .long, help: "Allow unsigned/untrusted installer packages to install.")
    var allowUnsigned: Bool = false

    @Flag(name: .long, help: "Print the last run's summary from last-run.json as one line and exit.")
    var lastRun: Bool = false

    /// Keeps the run lock alive for the life of the process.
    nonisolated(unsafe) private static var heldLock: RunLock?

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
        // A read-only query: answer before the logger starts, because starting
        // it opens a new session and would overwrite the record being read.
        if lastRun {
            print(LastRun.summaryLine())
            return
        }

        // Ensure the real log directory exists before initializing Logger, and
        // that the directories root reads state and payloads from are
        // root:wheel and writable by no one else. There is no fallback log
        // elsewhere; a failure here is reported on stderr.
        let logDir = BootstrapMateConstants.logsDirectory
        for dir in [BootstrapMateConstants.managedDirectory, logDir, BootstrapMateConstants.cacheDirectory]
        where !FileTrust.secureDirectory(dir) {
            FileHandle.standardError.write(
                Data("bootstrapmate: \(dir) is missing, not a directory, or writable by an account other than root\n".utf8)
            )
        }

        // One run at a time. A second instance leaves before it touches the
        // live run's records. The lock is held until this process exits.
        guard let runLock = RunLock.acquire() else {
            FileHandle.standardError.write(Data("bootstrapmate: another run is in progress; exiting\n".utf8))
            Foundation.exit(0)
        }
        Self.heldLock = runLock

        // A run left as "running" by a process that was killed, crashed or
        // lost its Mac to a restart is recorded as interrupted before this
        // run replaces last-run.json.
        let orphan = LastRun.recoverInterrupted(
            lastRunPath: BootstrapMateConstants.lastRunPath,
            logsDirectory: logDir
        )
        BaselineThrottle.markInterrupted(at: IAOrchestrator.shared.baselineStatePath)

        // Initialize logger
        let version = BootstrapMateConstants.version
        Logger.initialize(
            logDirectory: logDir,
            version: version,
            verboseConsole: verbose,
            silentMode: silent
        )

        // Handle SIGTERM (sent by the helper when the user clicks Stop) by
        // terminating SwiftDialog before exiting, so the dialog doesn't linger.
        signal(SIGTERM, SIG_IGN)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        sigtermSource.setEventHandler {
            // Close the session as interrupted, so a shutdown or bootout
            // mid-run never leaves last-run.json saying "running". After a
            // normal finish the session is already closed and this is a no-op.
            Logger.warning("Received SIGTERM — terminating dialog and exiting")
            DialogManager.shared.terminateDialog()
            Logger.writeSessionSummary(status: LastRun.interruptedStatus)
            BaselineThrottle.markInterrupted(at: IAOrchestrator.shared.baselineStatePath)
            Foundation.exit(1)
        }
        sigtermSource.resume()
        
        Logger.info("BootstrapMate v\(version) started")
        if let orphan {
            Logger.warning("Previous run \(orphan.sessionId) (started \(orphan.startTime), v\(orphan.toolVersion)) never finished; recorded as interrupted")
        }
        Logger.debug("CLI arguments: \(CommandLine.arguments.joined(separator: " "))")
        
        // Wait for network connectivity before proceeding. The CLI value wins;
        // otherwise the networkTimeout managed preference applies.
        let networkWait = networkTimeout ?? ConfigManager.shared.config.networkTimeout
        Logger.info("Waiting for network connectivity (timeout: \(networkWait)s)...")
        if waitForNetwork(timeout: networkWait) {
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
        
        // Wait for management configuration profile to be applied (during Setup Assistant)
        // The management profile with url preference may not be applied immediately at boot
        let managementTimeout = 300 // 5 minutes
        if jsonurl == nil || jsonurl!.isEmpty {
            // No CLI URL provided, we need management config
            if !ConfigManager.shared.isValid() {
                Logger.info("Waiting for management configuration profile (timeout: \(managementTimeout)s)...")
                
                for i in 1...managementTimeout {
                    // Reload preferences from management domains
                    if ConfigManager.shared.reloadManagedPreferences() {
                        Logger.success("Management configuration received after \(i)s")
                        break
                    }
                    
                    // Log progress every 30 seconds
                    if i % 30 == 0 {
                        Logger.debug("Still waiting for management config... (\(i)s elapsed)")
                    }
                    
                    Thread.sleep(forTimeInterval: 1)
                    
                    if i == managementTimeout {
                        Logger.warning("Management configuration not received within \(managementTimeout)s")
                    }
                }
            }
        }
        
        // Apply CLI arguments to ConfigManager (overrides management settings)
        ConfigManager.shared.applyCliArguments(
            jsonUrl: jsonurl,
            headers: headers,
            followRedirects: followRedirects,
            dryRun: dryRun,
            reboot: reboot,
            userscriptOnly: userscript,
            silentMode: silent,
            verboseMode: verbose,
            reportingUrl: reportingUrl,
            verifyPackageSignatures: noVerifySignature ? false : nil,
            expectedTeamID: expectedTeamId,
            allowUnsigned: allowUnsigned ? true : nil
        )
        // With no header on the command line or in the preferences, use the
        // one kept in the root-only secrets file, if there is one.
        ConfigManager.shared.applyAuthorizationHeaderFile()
        
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
                Logger.writeSessionSummary(status: "failed")
                // One-shot: never leave the daemon behind to run again at boot.
                if !effectiveConfig.dryRun { registerCleanupTasks() }
                Foundation.exit(1)
            }
        } else {
            // No URL provided - check if we have embedded config or should fail
            Logger.warning("No JSON URL provided via CLI or managed preferences")
            
            // Try to fetch from ConfigManager's external config
            if ConfigManager.shared.fetchExternalConfig() {
                Logger.info("Loaded external config from management preferences")
                // Convert BootstrapConfig to manifest loading
                // For now, we require jsonUrl
            } else {
                Logger.error("No manifest URL configured. Use --jsonurl or configure via management profile.")
                Logger.writeSessionSummary(status: "failed")
                if !effectiveConfig.dryRun { registerCleanupTasks() }
                Foundation.exit(1)
            }
        }
        
        // Set dry run mode
        ManifestManager.shared.setDryRun(effectiveConfig.dryRun)
        
        // Configure orchestrator
        let orchestratorConfig = IAOrchestrator.OrchestratorConfig(
            preferences: effectiveConfig,
            noDialog: noDialog,
            silent: silent,
            title: dialogTitle,
            message: dialogMessage
        )
        
        IAOrchestrator.shared.config = orchestratorConfig
        
        // Handle userscript-only mode
        if effectiveConfig.userscriptOnly {
            Logger.info("Running in userscript-only mode")
            let userscriptSuccess = ScriptManager.shared.runUserScriptOnly()
            Logger.writeSessionSummary()
            Foundation.exit(userscriptSuccess ? 0 : 1)
        }
        
        // Run all stages
        let success = IAOrchestrator.shared.runAllStages(reboot: effectiveConfig.reboot)
        
        Logger.writeSessionSummary()
        Foundation.exit(success ? 0 : 1)
    }
}
