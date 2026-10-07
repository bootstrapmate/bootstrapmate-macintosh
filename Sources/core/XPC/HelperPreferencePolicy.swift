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

    /// True when a configuration profile forces the key.
    public static func isForcedByProfile(_ key: String) -> Bool {
        CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
    }
}
