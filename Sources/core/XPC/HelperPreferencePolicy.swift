import Foundation

/// Decides which preference writes the privileged helper accepts.
///
/// The helper runs as root, so it only writes the keys the Prefs window edits,
/// only in BootstrapMate's own domain, and never a key a configuration profile
/// manages.
public enum HelperPreferencePolicy {
    public enum ValueKind: Equatable, Sendable {
        case string
        case bool
        case int
    }

    public static let domain = BootstrapMateConstants.daemonIdentifier

    /// The keys the Prefs window saves, and the type each one takes.
    public static let allowedKeys: [String: ValueKind] = [
        "url": .string,
        "headers": .string,
        "followRedirects": .bool,
        "reboot": .bool,
        "silentMode": .bool,
        "verboseMode": .bool,
        "dryRun": .bool,
        "userscriptOnly": .bool,
        "enableDialog": .bool,
        "dialogTitle": .string,
        "dialogMessage": .string,
        "dialogIcon": .string,
        "blurScreen": .bool,
        "retainCache": .bool,
        "networkTimeout": .int,
    ]

    public enum Decision: Equatable, Sendable {
        case allow
        case wrongDomain
        case unknownKey
        case wrongType
        case managed
    }

    /// Checks a write. `kind` is nil for a removal, which any allowed key accepts.
    public static func evaluate(
        domain requestedDomain: String,
        key: String,
        kind: ValueKind?,
        isForced: (String) -> Bool
    ) -> Decision {
        guard requestedDomain == domain else { return .wrongDomain }
        guard let expected = allowedKeys[key] else { return .unknownKey }
        if let kind, kind != expected { return .wrongType }
        if isForced(key) { return .managed }
        return .allow
    }

    /// Where the system keeps machine-wide values a configuration profile sets.
    public static let managedPreferencesPath = "/Library/Managed Preferences/\(domain).plist"

    /// True when a configuration profile forces the key. The helper is long-lived and
    /// CFPreferences keeps the managed layer it loaded at start-up, so a profile that
    /// arrives later is also checked for in the managed preferences file itself.
    public static func isForcedByProfile(_ key: String) -> Bool {
        if CFPreferencesAppValueIsForced(key as CFString, domain as CFString) { return true }
        return managedFileSetsKey(key, path: managedPreferencesPath)
    }

    /// True when the plist at `path` has a value for `key`.
    public static func managedFileSetsKey(_ key: String, path: String) -> Bool {
        guard let dict = NSDictionary(contentsOfFile: path) else { return false }
        return dict[key] != nil
    }
}

/// Decides whether a run the helper starts needs an administrator.
///
/// The runner reads the machine's saved settings itself, so a run with no
/// arguments, or only the flags below, does what the machine is already set
/// to do and any user may start it. Every other argument changes where
/// BootstrapMate fetches from, how it authenticates or what it does, so the
/// helper accepts it only with an administrator's authorization. The helper
/// makes this decision from the arguments it receives, never from the client.
public enum HelperRunPolicy {
    /// Flags that only add logging or keep the Mac unchanged.
    public static let harmlessArguments: Set<String> = ["--verbose", "--dry-run"]

    public static func requiresAdmin(_ arguments: [String]) -> Bool {
        arguments.contains { !harmlessArguments.contains($0) }
    }
}
