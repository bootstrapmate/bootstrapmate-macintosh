//
//  CommandLineRedaction.swift
//  BootstrapMate
//
//  The command line is written to the log and to session.json, and a run
//  started from the Settings window can carry an Authorization header on it.
//  Every credential is hidden before a command line is recorded.
//

import Foundation

public enum CommandLineRedaction {

    public static let mask = "<redacted>"

    /// Options whose value is a credential.
    public static let secretOptions = ["--headers", "--reporting-header"]

    /// HTTP authentication schemes. An argument that starts with one of these
    /// and a space is an Authorization value, wherever it appears.
    static let authSchemes = ["basic", "bearer", "digest", "negotiate", "ntlm", "aws4-hmac-sha256"]

    /// `arguments` with the value of every secret option, in either the
    /// `--headers value` or the `--headers=value` form, and every argument
    /// that is itself an Authorization value, replaced by `mask`.
    public static func redact(_ arguments: [String]) -> [String] {
        var hideNext = false
        return arguments.map { arg in
            if hideNext {
                hideNext = false
                return mask
            }
            let lowered = arg.lowercased()
            if let option = secretOptions.first(where: { lowered.hasPrefix($0 + "=") }) {
                return String(arg.prefix(option.count + 1)) + mask
            }
            if secretOptions.contains(lowered) {
                hideNext = true
                return arg
            }
            if looksLikeAuthorizationValue(arg) {
                return mask
            }
            return arg
        }
    }

    /// The command line as it is recorded: redacted, space-joined.
    public static func redactedCommandLine(_ arguments: [String] = CommandLine.arguments) -> String {
        redact(arguments).joined(separator: " ")
    }

    static func looksLikeAuthorizationValue(_ arg: String) -> Bool {
        let trimmed = arg.trimmingCharacters(in: .whitespaces).lowercased()
        let withoutName = trimmed.hasPrefix("authorization:")
            ? String(trimmed.dropFirst("authorization:".count)).trimmingCharacters(in: .whitespaces)
            : trimmed
        if withoutName != trimmed { return true }
        return authSchemes.contains { withoutName.hasPrefix($0 + " ") }
    }
}
