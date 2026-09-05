//
//  ArchitectureSkip.swift
//  BootstrapMate
//
//  Single interpretation of a manifest item's `skipIf` value.
//
//  The InstallApplications sense is authoritative: `skipIf` names the
//  architecture the item must NOT run on, so the item is skipped when the
//  named architecture is the one we are running on. Two copies of this rule
//  used to exist — one in the stage loops and one gating the download — and
//  they disagreed, so an item carrying `skipIf` was never downloaded on the
//  architecture it was written for.
//

import Foundation

public enum ArchitectureSkip {

    /// The architecture of the machine this run is on: "arm64" or "x86_64".
    public static func currentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let chars = machineMirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8($0))) }
        let identifier = String(chars)
        return identifier.contains("arm64") ? "arm64" : "x86_64"
    }

    /// Returns true when `skipIf` names the architecture we are running on,
    /// i.e. when the item should be skipped on this machine.
    ///
    /// - Parameters:
    ///   - skipIf: the manifest item's raw `skipIf` value.
    ///   - currentArch: the running architecture; defaults to this machine's.
    public static func shouldSkip(_ skipIf: String, currentArch: String = currentArchitecture()) -> Bool {
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
}
