//
//  SignatureVerifier.swift
//  BootstrapMate
//
//  Verifies the code-signing provenance of installer packages before they are
//  handed to `/usr/sbin/installer` and run as root.
//
//  The manifest SHA-256 only proves a downloaded file matches what the manifest
//  claims. If the manifest (or its host/CDN) is compromised, the hash check
//  happily validates attacker-supplied bytes. A signature + Team-ID gate proves
//  the package was actually produced by a trusted Apple Developer ID before we
//  execute it with root privileges.
//

import Foundation

public final class SignatureVerifier {
    nonisolated(unsafe) public static let shared = SignatureVerifier()

    private init() {}

    /// Outcome of inspecting a package's signature.
    public enum Result: Equatable {
        /// Signed with a certificate trusted by macOS. Associated value is the
        /// 10-character Apple Team ID when one could be parsed from the chain.
        case signed(teamID: String?)
        /// No signature, or a signature macOS does not trust.
        case untrusted(reason: String)
        /// Signed and trusted, but the Team ID does not match the expected value.
        case teamIDMismatch(found: String?, expected: String)
    }

    /// Decision after administrator policy is applied to a `Result`.
    public enum Decision: Equatable {
        case allow
        case deny(reason: String)
    }

    /// Inspect a flat installer package (`.pkg`) with `pkgutil --check-signature`.
    /// - Parameters:
    ///   - pkgPath: path to the package on disk.
    ///   - expectedTeamID: when non-nil/non-empty, the parsed Team ID must match.
    public func verifyPackage(atPath pkgPath: String, expectedTeamID: String?) -> Result {
        let (status, output) = runPkgutilCheckSignature(pkgPath)

        guard status == 0 else {
            // Non-zero exit means unsigned or a signature macOS will not trust.
            let firstMeaningful = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { !$0.isEmpty }) ?? "no signature"
            return .untrusted(reason: firstMeaningful)
        }

        let foundTeamID = Self.parseTeamID(from: output)

        if let expected = expectedTeamID, !expected.isEmpty {
            guard let found = foundTeamID, found == expected else {
                return .teamIDMismatch(found: foundTeamID, expected: expected)
            }
        }

        return .signed(teamID: foundTeamID)
    }

    /// Apply administrator policy to a verification result.
    /// - Parameter allowUnsigned: when true, an unsigned/untrusted package is
    ///   permitted (with a warning). A Team-ID *mismatch* is never permitted —
    ///   an explicit mismatch is a strong tampering signal, so `allowUnsigned`
    ///   does not bypass it.
    public func decide(_ result: Result, allowUnsigned: Bool) -> Decision {
        switch result {
        case .signed(let teamID):
            let suffix = teamID.map { " (Team ID \($0))" } ?? " (no Team ID in chain)"
            Logger.log("Package signature trusted\(suffix)")
            return .allow
        case .untrusted(let reason):
            if allowUnsigned {
                Logger.warning("Package signature not trusted (\(reason)) — proceeding because allowUnsigned is set")
                return .allow
            }
            return .deny(reason: "untrusted or missing signature (\(reason))")
        case .teamIDMismatch(let found, let expected):
            return .deny(reason: "Team ID mismatch — found \(found ?? "none"), expected \(expected)")
        }
    }

    // MARK: - Private

    private func runPkgutilCheckSignature(_ pkgPath: String) -> (Int32, String) {
        let task = Process()
        task.launchPath = "/usr/sbin/pkgutil"
        task.arguments = ["--check-signature", pkgPath]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return (-1, "failed to run pkgutil: \(error.localizedDescription)")
        }
        // Read to EOF before waiting so a large chain can't deadlock the pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, output)
    }

    /// Extract the 10-character Apple Team ID from the leaf certificate line of
    /// `pkgutil --check-signature` output, e.g.
    /// `1. Developer ID Installer: Example Corp (AB12CD34EF)`.
    /// Returns the first Team-ID-shaped token found (the leaf cert appears first).
    public static func parseTeamID(from output: String) -> String? {
        // Apple Team IDs are exactly 10 uppercase alphanumeric characters.
        guard let regex = try? NSRegularExpression(pattern: "\\(([A-Z0-9]{10})\\)") else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let teamRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[teamRange])
    }
}
