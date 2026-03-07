//
//  MDMDetector.swift
//  BootstrapMate
//
//  Detects which preferences are managed by MDM configuration profiles
//  vs. set locally. Used by the GUI to show lock indicators.
//

import Foundation

public final class MDMDetector: Sendable {

    public static let shared = MDMDetector()

    /// Preference domains checked for MDM management, in priority order.
    private let managedDomains = [
        "com.github.bootstrapmate",
        "io.macadmins.installapplications"
    ]

    /// Known key aliases — maps canonical key to all variant names.
    private static let keyAliases: [String: [String]] = [
        "jsonUrl":           ["url", "jsonurl", "JsonUrl", "ConfigURL", "ManifestURL"],
        "authorizationHeader": ["headers", "Headers", "AuthorizationHeader"],
        "followRedirects":   ["followRedirects", "FollowRedirects"],
        "silentMode":        ["silentMode", "SilentMode", "silent"],
        "verboseMode":       ["verboseMode", "VerboseMode", "verbose"],
        "reboot":            ["reboot", "Reboot"],
        "customInstallPath": ["installPath", "InstallPath", "iapath"],
        "daemonIdentifier":  ["daemonIdentifier", "ldidentifier"],
        "agentIdentifier":   ["agentIdentifier", "laidentifier"],
    ]

    private init() {}

    // MARK: - Public API

    /// Returns true if the canonical key is present in any managed preferences plist.
    public func isManagedByMDM(key: String) -> Bool {
        let keysToCheck = Self.keyAliases[key] ?? [key]
        for domain in managedDomains {
            for plistPath in managedPlistPaths(for: domain) {
                guard let plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else { continue }
                for alias in keysToCheck {
                    if plist[alias] != nil { return true }
                }
            }
        }
        return false
    }

    /// Returns the MDM-managed value for a canonical key, or nil.
    public func managedValue(forKey key: String) -> Any? {
        let keysToCheck = Self.keyAliases[key] ?? [key]
        for domain in managedDomains {
            for plistPath in managedPlistPaths(for: domain) {
                guard let plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else { continue }
                for alias in keysToCheck {
                    if let value = plist[alias] { return value }
                }
            }
        }
        return nil
    }

    /// Returns the set of canonical keys that are MDM-managed.
    public func allManagedKeys() -> Set<String> {
        var result = Set<String>()
        for (canonical, aliases) in Self.keyAliases {
            for domain in managedDomains {
                for plistPath in managedPlistPaths(for: domain) {
                    guard let plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else { continue }
                    for alias in aliases {
                        if plist[alias] != nil {
                            result.insert(canonical)
                        }
                    }
                }
            }
        }
        return result
    }

    // MARK: - Private

    private func managedPlistPaths(for domain: String) -> [String] {
        [
            "/Library/Managed Preferences/\(domain).plist",
            "/Library/Managed Preferences/\(NSUserName())/\(domain).plist"
        ]
    }
}
