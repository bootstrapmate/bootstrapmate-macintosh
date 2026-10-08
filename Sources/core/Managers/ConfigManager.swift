//
//  ConfigManager.swift
//  BootstrapMate
//
//  Configuration loader with fallback chain:
//  1. CLI arguments (highest priority)
//  2. managed preferences
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
    /// Keep downloaded payloads in the cache after a successful run. When
    /// false, the cache is emptied once the run succeeds.
    public var retainCache: Bool
    // Reporting: vendor-neutral run-summary POST
    public var reportingUrl: String?
    public var reportingHeader: String?
    // Security: package signature verification
    public var verifyPackageSignatures: Bool
    public var expectedTeamID: String?
    public var allowUnsigned: Bool
    // Dialog / UI settings
    public var enableDialog: Bool
    public var dialogTitle: String
    public var dialogMessage: String
    public var dialogIcon: String?
    public var blurScreen: Bool
    public var networkTimeout: Int
    // Userland: how long to wait for a console user before skipping the stage
    public var userlandLoginTimeout: Int
    /// Minimum hours between baseline runs; 0 or negative turns the throttle off.
    public var baselineMinIntervalHours: Int
    /// A file whose presence exempts the next run from the baseline throttle.
    public var forceRunFile: String
    
    public init(
        jsonUrl: String? = nil,
        authorizationHeader: String? = nil,
        followRedirects: Bool = true,
        dryRun: Bool = false,
        reboot: Bool = false,
        userscriptOnly: Bool = false,
        silentMode: Bool = false,
        verboseMode: Bool = false,
        retainCache: Bool = true,
        reportingUrl: String? = nil,
        reportingHeader: String? = nil,
        verifyPackageSignatures: Bool = true,
        expectedTeamID: String? = nil,
        allowUnsigned: Bool = false,
        enableDialog: Bool = true,
        dialogTitle: String = "Setting up your Mac",
        dialogMessage: String = "Please wait while we configure your device...",
        dialogIcon: String? = nil,
        blurScreen: Bool = false,
        networkTimeout: Int = 120,
        userlandLoginTimeout: Int = 3600,
        baselineMinIntervalHours: Int = BaselineThrottle.defaultMinIntervalHours,
        forceRunFile: String = BaselineThrottle.defaultForceFile
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
        self.reportingUrl = reportingUrl
        self.reportingHeader = reportingHeader
        self.verifyPackageSignatures = verifyPackageSignatures
        self.expectedTeamID = expectedTeamID
        self.allowUnsigned = allowUnsigned
        self.enableDialog = enableDialog
        self.dialogTitle = dialogTitle
        self.dialogMessage = dialogMessage
        self.dialogIcon = dialogIcon
        self.blurScreen = blurScreen
        self.networkTimeout = networkTimeout
        self.userlandLoginTimeout = userlandLoginTimeout
        self.baselineMinIntervalHours = baselineMinIntervalHours
        self.forceRunFile = forceRunFile
    }
}

/// Where the run's Authorization header came from.
public enum AuthorizationHeaderSource: String, Sendable {
    case none
    case commandLine = "command line"
    case preferences
    case secretsFile = "secrets file"
}

public final class ConfigManager {
    nonisolated(unsafe) public static let shared = ConfigManager()
    
    // management preference domains to check (in order of priority)
    private let managementPreferenceDomains = [
        "com.github.bootstrapmate"            // Primary BootstrapMate domain (management profile)
    ]
    
    /// Current active configuration
    public private(set) var config: BootstrapMateConfig

    /// Where `config.authorizationHeader` came from. Set by
    /// `applyCliArguments` and `applyAuthorizationHeaderFile`.
    public private(set) var authorizationHeaderSource: AuthorizationHeaderSource = .none

    /// The manifest URL the preferences gave, before any command-line
    /// override. Set by `applyCliArguments`.
    private var preferencesJsonUrl: String?
    
    /// Unsupported keys already named in the log, so the wait for the
    /// management profile, which rereads preferences every second, names each
    /// one once.
    private var warnedUnsupportedKeys = Set<String>()

    /// Legacy external config (for backward compatibility)
    public private(set) var externalConfig: BootstrapConfig?
    
    private init() {
        // Start with defaults
        self.config = BootstrapMateConfig()
        
        // Load managed preferences as baseline
        loadManagedPreferences()
    }
    
    // MARK: - Public API
    
    /// Apply CLI arguments (highest priority - overrides management settings)
    public func applyCliArguments(
        jsonUrl: String? = nil,
        headers: String? = nil,
        followRedirects: Bool? = nil,
        dryRun: Bool? = nil,
        reboot: Bool? = nil,
        userscriptOnly: Bool? = nil,
        silentMode: Bool? = nil,
        verboseMode: Bool? = nil,
        reportingUrl: String? = nil,
        verifyPackageSignatures: Bool? = nil,
        expectedTeamID: String? = nil,
        allowUnsigned: Bool? = nil
    ) {
        preferencesJsonUrl = config.jsonUrl
        if let url = jsonUrl, !url.isEmpty {
            config.jsonUrl = url
            Logger.debug("CLI override: jsonUrl = \(url)")
        }
        
        if let auth = headers, !auth.isEmpty {
            config.authorizationHeader = auth
            authorizationHeaderSource = .commandLine
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

        if let reporting = reportingUrl, !reporting.isEmpty {
            config.reportingUrl = reporting
            Logger.debug("CLI override: reportingUrl set")
        }

        if let verify = verifyPackageSignatures {
            config.verifyPackageSignatures = verify
            Logger.debug("CLI override: verifyPackageSignatures = \(verify)")
        }

        if let team = expectedTeamID, !team.isEmpty {
            config.expectedTeamID = team
            Logger.debug("CLI override: expectedTeamID = \(team)")
        }

        if let allow = allowUnsigned {
            config.allowUnsigned = allow
            Logger.debug("CLI override: allowUnsigned = \(allow)")
        }
    }
    
    /// The header to use, by precedence: the command line, then the
    /// preferences (a non-empty value), then the root-only file. The file is
    /// read only when neither of the others gives a header.
    ///
    /// The privileged helper runs this tool as root with whatever arguments
    /// the Settings window passes, and a standard user can type any manifest
    /// URL there. So a header the user did not supply is used only when the
    /// manifest URL is https on the host the administrator configured:
    ///
    /// - The root-only file: the host of `managedURL`, the manifest URL a
    ///   configuration profile forces. Without one the file is not used.
    /// - The preferences: the host of `managedURL`, else of `preferencesURL`
    ///   (the preferences' own URL, before any command-line override), so a
    ///   URL given on the command line never inherits the header to another
    ///   host.
    /// - The command line: the caller supplied the header, so it is not
    ///   gated here; it still goes only to the manifest's https host.
    ///
    /// A header that fails its check is dropped, with a warning that names
    /// the hosts and never the value, and no lower source is tried.
    static func resolveAuthorizationHeader(
        commandLine: String?,
        preferences: String?,
        file: () -> String?,
        manifestURL: String?,
        preferencesURL: String?,
        managedURL: String?
    ) -> (header: String?, source: AuthorizationHeaderSource) {
        if let header = NetworkManager.usableHeader(commandLine) { return (header, .commandLine) }

        let candidate: (header: String, source: AuthorizationHeaderSource, configuredURL: String?)
        if let header = NetworkManager.usableHeader(preferences) {
            candidate = (header, .preferences, managedURL ?? preferencesURL)
        } else if let header = NetworkManager.usableHeader(file()) {
            candidate = (header, .secretsFile, managedURL)
        } else {
            return (nil, .none)
        }

        guard isConfiguredHost(manifestURL, configuredURL: candidate.configuredURL) else {
            let configured = candidate.configuredURL.flatMap { URL(string: $0)?.host } ?? "none"
            Logger.warning("Not using the Authorization header from the \(candidate.source.rawValue): the manifest URL \(manifestURL ?? "none") is not https on the administrator-configured manifest host (\(configured))")
            return (nil, .none)
        }
        return (candidate.header, candidate.source)
    }

    /// True when `manifestURL` is https on the same host as `configuredURL`,
    /// which must be https too.
    static func isConfiguredHost(_ manifestURL: String?, configuredURL: String?) -> Bool {
        guard let manifestURL, let configuredURL,
              let manifest = URL(string: manifestURL),
              let configured = URL(string: configuredURL)
        else { return false }
        return NetworkManager.isAuthorizedHost(manifest, scope: configured)
    }

    /// The manifest URL a configuration profile forces, if any. A value in
    /// /Library/Preferences does not count: the helper writes the `url`
    /// preference on behalf of a standard user.
    static func managedManifestURL() -> String? {
        let domain = BootstrapMateConstants.daemonIdentifier
        for key in ["url", "jsonurl", "JsonUrl", "ConfigURL", "ManifestURL"] {
            if CFPreferencesAppValueIsForced(key as CFString, domain as CFString),
               let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String,
               !value.isEmpty {
                return value
            }
        }
        let path = HelperPreferencePolicy.managedPreferencesPath
        guard FileTrust.isTrustedFile(path),
              let plist = NSDictionary(contentsOfFile: path) as? [String: Any]
        else { return nil }
        for key in ["url", "jsonurl", "JsonUrl", "ConfigURL", "ManifestURL"] {
            if let value = plist[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// Settles the run's Authorization header once the command line has been
    /// applied, falling back to the root-only file at `path` when neither the
    /// command line nor the preferences give one, and dropping a header the
    /// manifest URL may not have (see `resolveAuthorizationHeader`). With no
    /// header anywhere the configuration is left exactly as it was.
    public func applyAuthorizationHeaderFile(at path: String = AuthorizationHeaderFile.defaultPath) {
        let fromCommandLine = authorizationHeaderSource == .commandLine
        guard fromCommandLine
            || NetworkManager.usableHeader(config.authorizationHeader) != nil
            || FileManager.default.fileExists(atPath: path)
        else {
            authorizationHeaderSource = .none
            return
        }
        let resolved = Self.resolveAuthorizationHeader(
            commandLine: fromCommandLine ? config.authorizationHeader : nil,
            preferences: fromCommandLine ? nil : config.authorizationHeader,
            file: { AuthorizationHeaderFile.read(at: path) },
            manifestURL: config.jsonUrl,
            preferencesURL: preferencesJsonUrl,
            managedURL: Self.managedManifestURL()
        )
        authorizationHeaderSource = resolved.source
        if resolved.source == .none {
            config.authorizationHeader = nil
        } else if resolved.source == .secretsFile {
            config.authorizationHeader = resolved.header
            Logger.debug("authorizationHeader read from \(path)")
        }
    }

    /// Get the effective JSON URL (from config or fallback)
    public func getEffectiveJsonUrl() -> String? {
        return config.jsonUrl
    }
    
    /// Check if configuration is valid (has minimum required settings)
    public func isValid() -> Bool {
        // Must have a JSON URL to proceed
        return config.jsonUrl != nil && !config.jsonUrl!.isEmpty
    }
    
    /// Reload managed preferences (call when waiting for management profile to be applied)
    /// Returns true if a valid JSON URL was found
    public func reloadManagedPreferences() -> Bool {
        // Clear existing URL to force re-read
        config.jsonUrl = nil
        
        // Try each domain in priority order
        for domain in managementPreferenceDomains {
            if loadPreferencesFromDomain(domain) {
                if config.jsonUrl != nil && !config.jsonUrl!.isEmpty {
                    Logger.info("Loaded managed preferences from: \(domain)")
                    return true
                }
            }
        }
        
        // Also check for managed preferences via management profile
        loadFromManagedAppConfig()
        
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
                let decoded = try ManifestDecoder.decode(
                    BootstrapConfig.self,
                    from: data,
                    urlHint: urlString
                )
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
        
        // Try each domain in priority order
        for domain in managementPreferenceDomains {
            if loadPreferencesFromDomain(domain) {
                Logger.info("Loaded managed preferences from: \(domain)")
                return
            }
        }
        
        // Also check for managed preferences via management profile
        loadFromManagedAppConfig()
        
        Logger.debug("No managed preferences found, using defaults")
    }
    
    private func loadPreferencesFromDomain(_ domain: String) -> Bool {
        // First try CFPreferences (works better for management-pushed preferences)
        let cfDomain = domain as CFString
        
        // Check for URL key (various names)
        let urlKeys = ["url", "jsonurl", "JsonUrl", "ConfigURL", "ManifestURL"]
        for key in urlKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? String {
                config.jsonUrl = value
                Logger.debug("Found \(key) in \(domain): \(value)")
                break
            }
        }
        
        // Check for headers
        let headerKeys = ["headers", "Headers", "AuthorizationHeader"]
        for key in headerKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? String {
                // An empty value manages the field without sending a header.
                config.authorizationHeader = value.isEmpty ? nil : value
                break
            }
        }
        
        // Check for followRedirects
        if let value = CFPreferencesCopyAppValue("followRedirects" as CFString, cfDomain) as? Bool {
            config.followRedirects = value
        } else if let value = CFPreferencesCopyAppValue("FollowRedirects" as CFString, cfDomain) as? Bool {
            config.followRedirects = value
        }
        
        // Check for silentMode
        let silentKeys = ["silentMode", "SilentMode", "silent"]
        for key in silentKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? Bool {
                config.silentMode = value
                break
            }
        }
        
        // Check for verboseMode
        let verboseKeys = ["verboseMode", "VerboseMode", "verbose"]
        for key in verboseKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? Bool {
                config.verboseMode = value
                break
            }
        }
        
        // Check for reboot
        if let value = CFPreferencesCopyAppValue("reboot" as CFString, cfDomain) as? Bool {
            config.reboot = value
        } else if let value = CFPreferencesCopyAppValue("Reboot" as CFString, cfDomain) as? Bool {
            config.reboot = value
        }
        
        // Check for dryRun
        if let value = CFPreferencesCopyAppValue("dryRun" as CFString, cfDomain) as? Bool {
            config.dryRun = value
        }
        
        // Check for userscriptOnly
        if let value = CFPreferencesCopyAppValue("userscriptOnly" as CFString, cfDomain) as? Bool {
            config.userscriptOnly = value
        }
        
        // Cache retention after a successful run
        let retainCacheKeys = ["retainCache", "RetainCache"]
        for key in retainCacheKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? Bool {
                config.retainCache = value
                break
            }
        }

        // Keys earlier builds accepted but never acted on. Name any that are
        // set, so a profile carrying one shows in the log instead of looking
        // as if it took effect.
        for key in Self.unsupportedKeys
        where !warnedUnsupportedKeys.contains(key)
            && CFPreferencesCopyAppValue(key as CFString, cfDomain) != nil {
            warnedUnsupportedKeys.insert(key)
            Logger.warning("Ignoring managed preference \(key) in \(domain): BootstrapMate does not support it")
        }

        // Reporting: vendor-neutral run-summary POST endpoint
        let reportingUrlKeys = ["reportingUrl", "ReportingUrl", "ReportURL", "reportingURL"]
        for key in reportingUrlKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? String, !value.isEmpty {
                config.reportingUrl = value
                break
            }
        }
        let reportingHeaderKeys = ["reportingHeader", "ReportingHeader", "ReportingAuthorizationHeader"]
        for key in reportingHeaderKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? String, !value.isEmpty {
                config.reportingHeader = value
                break
            }
        }
        
        // Security: package signature verification
        let verifyKeys = ["verifyPackageSignatures", "VerifyPackageSignatures", "verifySignatures"]
        for key in verifyKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? Bool {
                config.verifyPackageSignatures = value
                break
            }
        }
        let teamIDKeys = ["expectedTeamID", "ExpectedTeamID", "teamID", "TeamID"]
        for key in teamIDKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? String, !value.isEmpty {
                config.expectedTeamID = value
                break
            }
        }
        let allowUnsignedKeys = ["allowUnsigned", "AllowUnsigned"]
        for key in allowUnsignedKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? Bool {
                config.allowUnsigned = value
                break
            }
        }

        // Dialog / UI settings
        if let value = CFPreferencesCopyAppValue("enableDialog" as CFString, cfDomain) as? Bool {
            config.enableDialog = value
        }
        let titleKeys = ["dialogTitle", "DialogTitle"]
        for key in titleKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? String {
                config.dialogTitle = value
                break
            }
        }
        let messageKeys = ["dialogMessage", "DialogMessage"]
        for key in messageKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? String {
                config.dialogMessage = value
                break
            }
        }
        if let value = CFPreferencesCopyAppValue("dialogIcon" as CFString, cfDomain) as? String {
            config.dialogIcon = value.isEmpty ? nil : value
        }
        if let value = CFPreferencesCopyAppValue("blurScreen" as CFString, cfDomain) as? Bool {
            config.blurScreen = value
        }
        if let value = CFPreferencesCopyAppValue("networkTimeout" as CFString, cfDomain) as? Int {
            config.networkTimeout = value
        }

        // Userland: seconds to wait for a console user before skipping the
        // stage. 0 or negative means wait indefinitely.
        // Baseline throttle
        if let value = CFPreferencesCopyAppValue("baselineMinIntervalHours" as CFString, cfDomain) as? Int {
            config.baselineMinIntervalHours = value
        }
        if let value = CFPreferencesCopyAppValue("forceRunFile" as CFString, cfDomain) as? String, !value.isEmpty {
            config.forceRunFile = value
        }

        let loginTimeoutKeys = ["userlandLoginTimeout", "UserlandLoginTimeout"]
        for key in loginTimeoutKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, cfDomain) as? Int {
                config.userlandLoginTimeout = value
                break
            }
        }

        return config.jsonUrl != nil
    }
    
    /// Preference keys that are read nowhere. The install path, daemon and
    /// agent identifiers are fixed by the package (the app bundle, the
    /// LaunchDaemon label), so a preference cannot move them.
    public static let unsupportedKeys = [
        "installPath", "InstallPath", "iapath",
        "daemonIdentifier", "ldidentifier",
        "agentIdentifier", "laidentifier"
    ]

    private func loadFromManagedAppConfig() {
        // Check for management-deployed configuration profile
        // This handles the case where config is delivered via custom configuration profile
        let configDomains = [
            "com.github.bootstrapmate"
        ]
        
        for domain in configDomains {
            let managedConfigPath = "/Library/Managed Preferences/\(NSUserName())/\(domain).plist"
            let systemManagedPath = "/Library/Managed Preferences/\(domain).plist"
            
            for path in [managedConfigPath, systemManagedPath] {
                if FileManager.default.fileExists(atPath: path),
                   let plist = NSDictionary(contentsOfFile: path) as? [String: Any] {
                    
                    if let url = plist["url"] as? String ?? plist["jsonurl"] as? String ?? plist["JsonUrl"] as? String {
                        config.jsonUrl = url
                    }
                    
                    if let auth = plist["headers"] as? String ?? plist["Headers"] as? String {
                        config.authorizationHeader = auth
                    }
                    
                    if let redirects = plist["followRedirects"] as? Bool {
                        config.followRedirects = redirects
                    }
                    
                    Logger.info("Loaded config from managed preferences plist: \(path)")
                    return
                }
            }
        }
    }
    
    /// Reload all preferences from CFPreferences (call after GUI saves via XPC).
    public func reloadPreferences() {
        config = BootstrapMateConfig()
        authorizationHeaderSource = .none
        loadManagedPreferences()
    }

    /// Debug: Print current configuration
    public func printCurrentConfig() {
        Logger.debug("Current Configuration:")
        Logger.debug("  jsonUrl: \(config.jsonUrl ?? "not set")")
        Logger.debug("  authorizationHeader: \(NetworkManager.usableHeader(config.authorizationHeader) != nil ? "[set] from \(authorizationHeaderSource.rawValue)" : "not set")")
        Logger.debug("  followRedirects: \(config.followRedirects)")
        Logger.debug("  dryRun: \(config.dryRun)")
        Logger.debug("  reboot: \(config.reboot)")
        Logger.debug("  silentMode: \(config.silentMode)")
        Logger.debug("  verboseMode: \(config.verboseMode)")
        Logger.debug("  reportingUrl: \(config.reportingUrl != nil ? "set" : "not set")")
        Logger.debug("  verifyPackageSignatures: \(config.verifyPackageSignatures)")
        Logger.debug("  expectedTeamID: \(config.expectedTeamID ?? "any trusted")")
        Logger.debug("  allowUnsigned: \(config.allowUnsigned)")
        Logger.debug("  retainCache: \(config.retainCache)")
        Logger.debug("  enableDialog: \(config.enableDialog)")
        Logger.debug("  dialogTitle: \(config.dialogTitle)")
        Logger.debug("  dialogMessage: \(config.dialogMessage)")
        Logger.debug("  dialogIcon: \(config.dialogIcon ?? "default")")
        Logger.debug("  blurScreen: \(config.blurScreen)")
        Logger.debug("  networkTimeout: \(config.networkTimeout)")
        Logger.debug("  userlandLoginTimeout: \(config.userlandLoginTimeout)")
        Logger.debug("  baselineMinIntervalHours: \(config.baselineMinIntervalHours)")
        Logger.debug("  forceRunFile: \(config.forceRunFile)")
    }
}

