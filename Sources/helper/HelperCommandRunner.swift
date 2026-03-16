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

    // MARK: - HelperXPCProtocol

    func runBootstrap(arguments: [String]) {
        let clientProxy = connection.remoteObjectProxy as? HelperXPCClientProtocol

        let task = Process()
        task.executableURL = URL(fileURLWithPath: BootstrapMateConstants.executablePath)
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
        CFPreferencesSetValue(
            key as CFString,
            stringValue as CFString,
            domain as CFString,
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        )
        let synced = CFPreferencesSynchronize(domain as CFString, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        reply(synced)
    }

    func setBoolPreference(key: String, boolValue: Bool, domain: String, withReply reply: @escaping (Bool) -> Void) {
        CFPreferencesSetValue(
            key as CFString,
            boolValue as CFPropertyList,
            domain as CFString,
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        )
        let synced = CFPreferencesSynchronize(domain as CFString, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        reply(synced)
    }

    func setIntPreference(key: String, intValue: Int, domain: String, withReply reply: @escaping (Bool) -> Void) {
        CFPreferencesSetValue(
            key as CFString,
            intValue as CFNumber as CFPropertyList,
            domain as CFString,
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        )
        let synced = CFPreferencesSynchronize(domain as CFString, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        reply(synced)
    }

    func removePreference(key: String, domain: String, withReply reply: @escaping (Bool) -> Void) {
        CFPreferencesSetValue(
            key as CFString,
            nil,
            domain as CFString,
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        )
        let synced = CFPreferencesSynchronize(domain as CFString, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        reply(synced)
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
