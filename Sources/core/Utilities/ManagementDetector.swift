//
//  ManagementDetector.swift
//  BootstrapMate
//
//  Detects which preferences are managed by configuration profiles
//  vs. set locally. Used by the GUI to show lock indicators.
//

import Foundation

public final class ManagementDetector: Sendable {

    public static let shared = ManagementDetector()

    /// Answers whether a key in a domain is forced by a configuration profile.
    public typealias ForcedCheck = @Sendable (_ key: String, _ domain: String) -> Bool

    /// Reads a key's effective value in a domain.
    public typealias ValueRead = @Sendable (_ key: String, _ domain: String) -> Any?

    /// Preference domains checked for management, in priority order.
    private let managedDomains = [
        "com.github.bootstrapmate"
    ]

    /// Known key aliases: maps each canonical key the GUI shows to every name
    /// ConfigManager accepts for it, so a profile using any alias locks the field.
    public static let keyAliases: [String: [String]] = [
        "jsonUrl":             ["url", "jsonurl", "JsonUrl", "ConfigURL", "ManifestURL"],
        "authorizationHeader": ["headers", "Headers", "AuthorizationHeader"],
        "followRedirects":     ["followRedirects", "FollowRedirects"],
        "silentMode":          ["silentMode", "SilentMode", "silent"],
        "verboseMode":         ["verboseMode", "VerboseMode", "verbose"],
        "reboot":              ["reboot", "Reboot"],
        "dryRun":              ["dryRun"],
        "userscriptOnly":      ["userscriptOnly"],
        "enableDialog":        ["enableDialog"],
        "dialogTitle":         ["dialogTitle", "DialogTitle"],
        "dialogMessage":       ["dialogMessage", "DialogMessage"],
        "dialogIcon":          ["dialogIcon"],
        "blurScreen":          ["blurScreen"],
        "retainCache":         ["retainCache", "RetainCache"],
        "networkTimeout":      ["networkTimeout"],
    ]

    private let isForced: ForcedCheck
    private let readValue: ValueRead

    private convenience init() {
        self.init(
            isForced: { key, domain in
                CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
            },
            readValue: { key, domain in
                CFPreferencesCopyAppValue(key as CFString, domain as CFString)
            }
        )
    }

    /// Test seam: supply the forced check and value read instead of CFPreferences.
    public init(isForced: @escaping ForcedCheck, readValue: @escaping ValueRead) {
        self.isForced = isForced
        self.readValue = readValue
    }

    // MARK: - Public API

    /// Returns the canonical key for any alias, or the key itself when it has none.
    public static func canonicalKey(for key: String) -> String {
        if keyAliases[key] != nil { return key }
        for (canonical, aliases) in keyAliases where aliases.contains(key) {
            return canonical
        }
        return key
    }

    /// Returns true when a configuration profile forces the key or any of its aliases.
    public func isManaged(key: String) -> Bool {
        forcedAlias(for: key) != nil
    }

    /// Returns the profile-forced value for a key, or nil when no profile sets it.
    public func managedValue(forKey key: String) -> Any? {
        guard let (alias, domain) = forcedAlias(for: key) else { return nil }
        return readValue(alias, domain)
    }

    /// Returns the set of canonical keys that a configuration profile forces.
    public func allManagedKeys() -> Set<String> {
        Set(Self.keyAliases.keys.filter { isManaged(key: $0) })
    }

    // MARK: - Private

    private func forcedAlias(for key: String) -> (String, String)? {
        let canonical = Self.canonicalKey(for: key)
        let keysToCheck = Self.keyAliases[canonical] ?? [canonical]
        for domain in managedDomains {
            for alias in keysToCheck where isForced(alias, domain) {
                return (alias, domain)
            }
        }
        return nil
    }
}
