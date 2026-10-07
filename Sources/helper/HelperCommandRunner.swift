//
//  HelperCommandRunner.swift
//  BootstrapMateHelper
//
//  Implements the XPC protocol: runs the CLI binary with output streaming
//  and manages system-level preferences.
//

import Foundation
import BootstrapMateCore

final class HelperCommandRunner: NSObject, HelperXPCProtocol, @unchecked Sendable {
    // Safety invariant: `process` is only mutated on the XPC dispatch queue
    // which serializes all incoming calls. The connection holds a strong
    // reference to this object; invalidationHandler calls cancelRunningProcess
    // on the same queue.
    private let connection: NSXPCConnection
    private var process: Process?

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    /// The CLI that ships next to this helper in the same app bundle, so a run
    /// works wherever the app is installed; the fixed install path is the fallback.
    static let cliURL: URL = {
        let ownPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let sibling = ownPath.deletingLastPathComponent().appendingPathComponent("managedbootstrapinstall")
        if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        return URL(fileURLWithPath: BootstrapMateConstants.executablePath)
    }()

    // MARK: - HelperXPCProtocol

    func runBootstrap(arguments: [String]) {
        let clientProxy = connection.remoteObjectProxy as? HelperXPCClientProtocol

        let task = Process()
        task.executableURL = Self.cliURL
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        process = task

        // Stream output line by line on a background queue
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                // EOF
                fileHandle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                let lines = text.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    clientProxy?.didReceiveOutput(line)
                }
            }
        }

        task.terminationHandler = { [weak self] proc in
            handle.readabilityHandler = nil
            // Drain any remaining data
            let remaining = handle.readDataToEndOfFile()
            if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    clientProxy?.didReceiveOutput(line)
                }
            }
            let exitCode = proc.terminationStatus
            clientProxy?.runDidComplete(success: exitCode == 0, exitCode: exitCode)
            self?.process = nil
        }

        do {
            try task.run()
        } catch {
            clientProxy?.didEncounterError("Failed to launch CLI: \(error.localizedDescription)")
            clientProxy?.runDidComplete(success: false, exitCode: -1)
            process = nil
        }
    }

    func setPreference(key: String, stringValue: String, domain: String, withReply reply: @escaping (Bool) -> Void) {
        reply(writePreference(key: key, value: stringValue as CFString, kind: .string, domain: domain))
    }

    func setBoolPreference(key: String, boolValue: Bool, domain: String, withReply reply: @escaping (Bool) -> Void) {
        reply(writePreference(key: key, value: boolValue as CFPropertyList, kind: .bool, domain: domain))
    }

    func setIntPreference(key: String, intValue: Int, domain: String, withReply reply: @escaping (Bool) -> Void) {
        reply(writePreference(key: key, value: intValue as CFNumber as CFPropertyList, kind: .int, domain: domain))
    }

    func removePreference(key: String, domain: String, withReply reply: @escaping (Bool) -> Void) {
        reply(writePreference(key: key, value: nil, kind: nil, domain: domain))
    }

    /// Writes one machine-level preference after the policy accepts it. Values go to
    /// /Library/Preferences (any user, any host), which is where the runner reads them.
    private func writePreference(key: String, value: CFPropertyList?, kind: HelperPreferencePolicy.ValueKind?, domain: String) -> Bool {
        let decision = HelperPreferencePolicy.evaluate(
            domain: domain,
            key: key,
            kind: kind,
            isForced: HelperPreferencePolicy.isForcedByProfile
        )
        guard decision == .allow else {
            NSLog("BootstrapMate helper refused preference write for %@ in %@: %@", key, domain, String(describing: decision))
            return false
        }
        let cfDomain = HelperPreferencePolicy.domain as CFString
        CFPreferencesSetValue(key as CFString, value, cfDomain, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(cfDomain, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
    }

    func getHelperVersion(withReply reply: @escaping (String) -> Void) {
        reply(BootstrapMateConstants.version)
    }

    // MARK: - Cancellation

    func stopBootstrap() {
        cancelRunningProcess()
    }

    func cancelRunningProcess() {
        process?.terminate()
        process = nil
    }
}
