//
//  BuildInfo.swift
//  BootstrapMate
//
//  The version of the build that is running, read from the app bundle that
//  contains the executable. It never depends on the clock.
//

import Foundation

public enum BuildInfo {

    /// The running build's version, e.g. 2026.10.05.0926.
    ///
    /// Read from the Info.plist of the app bundle holding the executable,
    /// following symlinks so the /usr/local/bin link resolves to the bundle.
    /// Falls back to the version stamped in at build time.
    public static func version(executablePath: String? = nil) -> String {
        let path = executablePath ?? Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        return bundleVersion(forExecutable: path) ?? BuildVersion.value
    }

    /// `CFBundleShortVersionString` joined to `CFBundleVersion` for an
    /// executable at `<App>.app/Contents/MacOS/<name>`, or nil when the
    /// executable is not inside an app bundle. The package splits a version
    /// like 2026.10.05.0926 into a short version (2026.10.05) and a build
    /// number (0926); this puts it back together.
    static func bundleVersion(forExecutable path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let macOS = resolved.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents" else { return nil }
        let plistURL = contents.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let short = plist["CFBundleShortVersionString"] as? String, !short.isEmpty else {
            return nil
        }
        guard let build = plist["CFBundleVersion"] as? String, !build.isEmpty, build != short,
              !short.hasSuffix("." + build) else {
            return short
        }
        return "\(short).\(build)"
    }
}
