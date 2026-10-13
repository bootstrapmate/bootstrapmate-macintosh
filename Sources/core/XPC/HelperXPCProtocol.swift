//
//  HelperXPCProtocol.swift
//  BootstrapMate
//
//  Shared XPC protocol definitions for communication between the GUI app
//  and the privileged helper daemon.
//

import Foundation

/// Mach service name for the privileged helper
public let kHelperMachServiceName = "com.github.bootstrapmate.helper"

/// The authorization right an administrator must hold before the helper
/// writes a machine setting. The app asks for it when the user clicks Save;
/// the helper only confirms the credential it is handed and never prompts.
public let kHelperAdminRight = "system.privilege.admin"

/// Protocol exposed by the privileged helper daemon.
/// All methods run with root privileges.
/// XPC proxies are thread-safe by design; Sendable conformance is safe.
@objc public protocol HelperXPCProtocol: Sendable {
    /// Launch the CLI binary with the given arguments.
    /// Output is streamed back via the client protocol.
    func runBootstrap(arguments: [String])

    /// Stop the currently running bootstrap process.
    func stopBootstrap()

    /// Every preference write and removal carries `authorization`, an
    /// AuthorizationExternalForm that already holds `kHelperAdminRight`.
    /// Without it the helper refuses the write.

    /// Write a preference value at system level (kCFPreferencesAnyUser).
    func setPreference(key: String, stringValue: String, domain: String, authorization: Data, withReply reply: @escaping (Bool) -> Void)

    /// Write a boolean preference value at system level.
    func setBoolPreference(key: String, boolValue: Bool, domain: String, authorization: Data, withReply reply: @escaping (Bool) -> Void)

    /// Write an integer preference value at system level.
    func setIntPreference(key: String, intValue: Int, domain: String, authorization: Data, withReply reply: @escaping (Bool) -> Void)

    /// Remove a preference key at system level.
    func removePreference(key: String, domain: String, authorization: Data, withReply reply: @escaping (Bool) -> Void)

    /// Return the helper's version string for version-mismatch detection.
    func getHelperVersion(withReply reply: @escaping (String) -> Void)
}

/// Callback protocol from the helper back to the GUI client.
/// XPC proxies are thread-safe by design; Sendable conformance is safe.
@objc public protocol HelperXPCClientProtocol: Sendable {
    /// A single line of output from the running CLI process.
    func didReceiveOutput(_ line: String)

    /// The CLI process finished.
    func runDidComplete(success: Bool, exitCode: Int32)

    /// The helper encountered an error outside of a normal run.
    func didEncounterError(_ message: String)
}
