//
//  ConfigManager.swift
//  BootstrapMate
//
//  Configuration loader with fallback chain:
//  1. CLI arguments (highest priority)
//  2. MDM managed preferences (com.bootstrapmate.config)
//  3. Embedded/default values (lowest priority)
//

import Foundation

/// Configuration options for BootstrapMate
public struct BootstrapMateConfig {
    public var jsonUrl: String?
    public var authorizationHeader: String?
    public var followRedirects: Bool
    public var dryRun: Bool
    public var reboot: Bool
    public var userscriptOnly: Bool
    public var silentMode: Bool
    public var verboseMode: Bool
    public var retainCache: Bool        // If false, cache is cleaned after successful run
    public var customInstallPath: String?
    public var daemonIdentifier: String
    public var agentIdentifier: String
    
    public init(
        jsonUrl: String? = nil,
        authorizationHeader: String? = nil,
        followRedirects: Bool = false,
        dryRun: Bool = false,
        reboot: Bool = false,
        userscriptOnly: Bool = false,
        silentMode: Bool = false,
        verboseMode: Bool = false,
        retainCache: Bool = false,
        customInstallPath: String? = nil,
        daemonIdentifier: String = BootstrapMateConstants.daemonIdentifier,
        agentIdentifier: String = BootstrapMateConstants.daemonIdentifier
    ) {
        self.jsonUrl = jsonUrl
        self.authorizationHeader = authorizationHeader
        self.followRedirects = followRedirects
        self.dryRun = dryRun
        self.reboot = reboot
        self.userscriptOnly = userscriptOnly
        self.silentMode = silentMode
        self.verboseMode = verboseMode
        self.retainCache = retainCache
        self.customInstallPath = customInstallPath
        self.daemonIdentifier = daemonIdentifier
        self.agentIdentifier = agentIdentifier
    }
}

public final class ConfigManager {
    nonisolated(unsafe) public static let shared = ConfigManager()
    
    // MDM preference domains to check (in order of priority)
    private let mdmPreferenceDomains = [
        BootstrapMateConstants.preferenceDomain,  // Primary domain: com.github.bootstrapmate
        "com.bootstrapmate.config",               // Alternative domain
        "io.macadmins.installapplications"        // Legacy InstallApplications compatibility
    ]
    
    // Default installation path
    private let defaultInstallPath = "/Library/Managed Bootstrap"
    
    /// Current active configuration
    public private(set) var config: BootstrapMateConfig
    
    /// Legacy external config (for backward compatibility)
    public private(set) var externalConfig: BootstrapConfig?
    
    private init() {
        // Start with defaults
        self.config = BootstrapMateConfig()
        
        // Load MDM managed preferences as baseline
        loadManagedPreferences()
    }
    
    // MARK: - Public API
    
    /// Apply CLI arguments (highest priority - overrides MDM settings)
    public func applyCliArguments(
        jsonUrl: String? = nil,
        headers: String? = nil,
        followRedirects: Bool? = nil,
        dryRun: Bool? = nil,
        reboot: Bool? = nil,
        userscriptOnly: Bool? = nil,
        silentMode: Bool? = nil,
        verboseMode: Bool? = nil,
        retainCache: Bool? = nil
    ) {
        if let url = jsonUrl, !url.isEmpty {
            config.jsonUrl = url
            Logger.debug("CLI override: jsonUrl = \(url)")
        }
        
        if let auth = headers, !auth.isEmpty {
            config.authorizationHeader = auth
            Logger.debug("CLI override: authorizationHeader set")
        }
        
        if let redirects = followRedirects {
            config.followRedirects = redirects
            Logger.debug("CLI override: followRedirects = \(redirects)")
        }
        
        if let dry = dryRun {
            config.dryRun = dry
            Logger.debug("CLI override: dryRun = \(dry)")
        }
        
        if let rebootFlag = reboot {
            config.reboot = rebootFlag
            Logger.debug("CLI override: reboot = \(rebootFlag)")
        }
        
        if let userscript = userscriptOnly {
            config.userscriptOnly = userscript
            Logger.debug("CLI override: userscriptOnly = \(userscript)")
        }
        
        if let silent = silentMode {
            config.silentMode = silent
            Logger.debug("CLI override: silentMode = \(silent)")
        }
        
        if let verbose = verboseMode {
            config.verboseMode = verbose
            Logger.debug("CLI override: verboseMode = \(verbose)")
        }
        
        if let retain = retainCache {
            config.retainCache = retain
            Logger.debug("CLI override: retainCache = \(retain)")
        }
    }
    
    /// Get the effective JSON URL (from config or fallback)
    public func getEffectiveJsonUrl() -> String? {
        return config.jsonUrl
    }
    
    /// Get the installation path
    public func getInstallPath() -> String {
        return config.customInstallPath ?? defaultInstallPath
    }
    
    /// Check if configuration is valid (has minimum required settings)
    public func isValid() -> Bool {
        // Must have a JSON URL to proceed
        return config.jsonUrl != nil && !config.jsonUrl!.isEmpty
    }
    
    /// Validate and fetch external bootstrap config if URL is set
    public func fetchExternalConfig() -> Bool {
        guard let urlString = config.jsonUrl,
              let url = URL(string: urlString) else {
            Logger.warning("No valid JSON URL configured")
            return false
        }
        
        Logger.info("Fetching external config from: \(urlString)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        // Use a class wrapper to safely capture data across thread boundary
        final class DataHolder: @unchecked Sendable {
            var data: Data?
            var errorMessage: String?
        }
        let holder = DataHolder()
        
        NetworkManager.shared.downloadData(
            from: url,
            followRedirects: config.followRedirects,
            authHeader: config.authorizationHeader
        ) { data, error in
            holder.data = data
            holder.errorMessage = error?.localizedDescription
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
        
        // Process downloaded data outside the closure
        if let errorMessage = holder.errorMessage {
            Logger.error("Failed to fetch external config: \(errorMessage)")
        }
        
        if let data = holder.data {
            do {
                let decoded = try JSONDecoder().decode(BootstrapConfig.self, from: data)
                self.externalConfig = decoded
                Logger.success("External config loaded successfully")
                return true
            } catch {
                Logger.error("Failed to decode external config: \(error.localizedDescription)")
            }
        }
        
        return false
    }
    
    // MARK: - Private Methods
    
    private func loadManagedPreferences() {
        Logger.debug("Loading managed preferences...")
        
        // First: Try CFPreferences (correct way to read MDM-managed preferences)
        if loadFromCFPreferences() {
            return
        }
        
        // Second: Try UserDefaults persistentDomain (for local preferences)
        for domain in mdmPreferenceDomains {
            if loadPreferencesFromDomain(domain) {
                Logger.info("Loaded preferences from UserDefaults domain: \(domain)")
                return
            }
        }
        
        // Third: Try managed preference plist files directly
        loadFromManagedAppConfig()
        
        if config.jsonUrl == nil {
            Logger.debug("No MDM managed preferences found, using defaults")
        }
    }
    
    /// Load preferences via CFPreferences (correct API for MDM-managed settings)
    private func loadFromCFPreferences() -> Bool {
        let domain = BootstrapMateConstants.preferenceDomain as CFString
        
        // CRITICAL: Force synchronization with managed preferences database
        // This is essential during enrollment when profiles are just being installed
        // Without this, preferences may not be visible immediately
        CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        
        Logger.debug("Forcing CFPreferences synchronization for domain: \(domain)")
        
        // CFPreferencesCopyAppValue reads from all preference sources including managed
        if let url = CFPreferencesCopyAppValue("url" as CFString, domain) as? String {
            config.jsonUrl = url
            Logger.info("Loaded 'url' from CFPreferences: \(url)")
        }
        
        if let auth = CFPreferencesCopyAppValue("headers" as CFString, domain) as? String {
            config.authorizationHeader = auth
            Logger.debug("Loaded 'headers' from CFPreferences")
        }
        
        if let redirects = CFPreferencesCopyAppValue("followRedirects" as CFString, domain) as? Bool {
            config.followRedirects = redirects
        }
        
        if let retain = CFPreferencesCopyAppValue("retainCache" as CFString, domain) as? Bool {
            config.retainCache = retain
            Logger.debug("Loaded 'retainCache' from CFPreferences: \(retain)")
        }
        
        if let silent = CFPreferencesCopyAppValue("silentMode" as CFString, domain) as? Bool {
            config.silentMode = silent
        }
        
        if let verbose = CFPreferencesCopyAppValue("verboseMode" as CFString, domain) as? Bool {
            config.verboseMode = verbose
        }
        
        if let reboot = CFPreferencesCopyAppValue("reboot" as CFString, domain) as? Bool {
            config.reboot = reboot
        }
        
        if config.jsonUrl != nil {
            Logger.info("Loaded managed preferences from CFPreferences domain: \(domain)")
            return true
        }
        
        Logger.debug("No managed preferences found in CFPreferences domain: \(domain)")
        return false
    }
    
    private func loadPreferencesFromDomain(_ domain: String) -> Bool {
        guard let prefs = UserDefaults.standard.persistentDomain(forName: domain),
              !prefs.isEmpty else {
            return false
        }
        
        // Map various possible key names ("url" is preferred, matching Windows version)
        if let url = prefs["url"] as? String ??          // Preferred key (matches Windows)
                     prefs["Url"] as? String ??
                     prefs["jsonurl"] as? String ??       // Legacy key
                     prefs["JsonUrl"] as? String ?? 
                     prefs["ConfigURL"] as? String ?? 
                     prefs["ManifestURL"] as? String {
            config.jsonUrl = url
        }
        
        if let auth = prefs["headers"] as? String ?? 
                      prefs["Headers"] as? String ?? 
                      prefs["AuthorizationHeader"] as? String {
            config.authorizationHeader = auth
        }
        
        if let redirects = prefs["followRedirects"] as? Bool ?? 
                          prefs["FollowRedirects"] as? Bool {
            config.followRedirects = redirects
        }
        
        if let silent = prefs["silentMode"] as? Bool ?? 
                       prefs["SilentMode"] as? Bool ?? 
                       prefs["silent"] as? Bool {
            config.silentMode = silent
        }
        
        if let verbose = prefs["verboseMode"] as? Bool ?? 
                        prefs["VerboseMode"] as? Bool ?? 
                        prefs["verbose"] as? Bool {
            config.verboseMode = verbose
        }
        
        if let retain = prefs["retainCache"] as? Bool ?? 
                       prefs["RetainCache"] as? Bool {
            config.retainCache = retain
        }
        
        if let reboot = prefs["reboot"] as? Bool ?? 
                       prefs["Reboot"] as? Bool {
            config.reboot = reboot
        }
        
        if let path = prefs["installPath"] as? String ?? 
                     prefs["InstallPath"] as? String ?? 
                     prefs["iapath"] as? String {
            config.customInstallPath = path
        }
        
        if let daemonId = prefs["daemonIdentifier"] as? String ?? 
                         prefs["ldidentifier"] as? String {
            config.daemonIdentifier = daemonId
        }
        
        if let agentId = prefs["agentIdentifier"] as? String ?? 
                        prefs["laidentifier"] as? String {
            config.agentIdentifier = agentId
        }
        
        return config.jsonUrl != nil
    }
    
    private func loadFromManagedAppConfig() {
        // Check for MDM-deployed configuration profile plist files
        // System-scoped MDM profiles write directly to /Library/Managed Preferences/
        let primaryDomain = BootstrapMateConstants.preferenceDomain
        let paths = [
            "/Library/Managed Preferences/\(primaryDomain).plist",
            "/Library/Managed Preferences/com.bootstrapmate.config.plist",
            "/Library/Managed Preferences/io.macadmins.installapplications.plist"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                Logger.debug("Found managed preferences plist at: \(path)")
                
                if let plist = NSDictionary(contentsOfFile: path) as? [String: Any] {
                    if let url = plist["url"] as? String ??
                                 plist["Url"] as? String ??
                                 plist["jsonurl"] as? String ??
                                 plist["JsonUrl"] as? String {
                        config.jsonUrl = url
                        Logger.info("Loaded 'url' from plist: \(url)")
                    }
                    
                    if let auth = plist["headers"] as? String ?? plist["Headers"] as? String {
                        config.authorizationHeader = auth
                    }
                    
                    if let redirects = plist["followRedirects"] as? Bool {
                        config.followRedirects = redirects
                    }
                    
                    if let retain = plist["retainCache"] as? Bool {
                        config.retainCache = retain
                    }
                    
                    if config.jsonUrl != nil {
                        Logger.info("Loaded config from managed preferences plist: \(path)")
                        return
                    }
                }
            }
        }
    }
    
    /// Debug: Print current configuration
    public func printCurrentConfig() {
        Logger.debug("Current Configuration:")
        Logger.debug("  jsonUrl: \(config.jsonUrl ?? "not set")")
        Logger.debug("  authorizationHeader: \(config.authorizationHeader != nil ? "[set]" : "not set")")
        Logger.debug("  followRedirects: \(config.followRedirects)")
        Logger.debug("  dryRun: \(config.dryRun)")
        Logger.debug("  reboot: \(config.reboot)")
        Logger.debug("  silentMode: \(config.silentMode)")
        Logger.debug("  verboseMode: \(config.verboseMode)")
        Logger.debug("  installPath: \(getInstallPath())")
        Logger.debug("  daemonIdentifier: \(config.daemonIdentifier)")
    }
}

