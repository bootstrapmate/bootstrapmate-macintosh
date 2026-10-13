//
//  XPCClient.swift
//  BootstrapMate
//
//  Manages the NSXPCConnection to the privileged helper daemon.
//  Streams CLI output back to the GUI and handles preference writes.
//

import Foundation
import ServiceManagement
import BootstrapMateCore

@Observable
@MainActor
final class XPCClient: NSObject {
    var outputLines: [OutputLine] = []
    var isRunning = false
    var lastExitCode: Int32?
    var helperStatus: HelperStatus = .unknown
    var connectionError: String?

    private var connection: NSXPCConnection?

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let level: LogLevel

        enum LogLevel {
            case info, debug, warning, error, success
        }
    }

    enum HelperStatus: String {
        case unknown = "Unknown"
        case registered = "Registered"
        case notRegistered = "Not Registered"
        case requiresApproval = "Requires Approval"
    }

    override init() {
        super.init()
    }

    // MARK: - Connection Management

    func connect() {
        guard connection == nil else { return }

        let conn = NSXPCConnection(machServiceName: kHelperMachServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: HelperXPCClientProtocol.self)
        conn.exportedObject = self

        conn.invalidationHandler = makeInvalidationHandler()
        conn.interruptionHandler = makeInterruptionHandler()

        conn.resume()
        connection = conn
        connectionError = nil

        // Ping helper to verify it's alive
        helperProxy { proxy in
            proxy.getHelperVersion { [weak self] version in
                Task { @MainActor [weak self] in
                    self?.helperStatus = .registered
                    self?.connectionError = nil
                }
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Helper Registration

    func registerHelper() {
        let service = SMAppService.daemon(plistName: BootstrapMateConstants.helperPlistName)
        do {
            try service.register()
            helperStatus = .registered
        } catch {
            helperStatus = .requiresApproval
            connectionError = "Helper registration failed: \(error.localizedDescription)"
        }
    }

    func checkHelperStatus() {
        let service = SMAppService.daemon(plistName: BootstrapMateConstants.helperPlistName)
        switch service.status {
        case .enabled:
            helperStatus = .registered
        case .requiresApproval:
            helperStatus = .requiresApproval
        case .notRegistered, .notFound:
            helperStatus = .notRegistered
        @unknown default:
            helperStatus = .unknown
        }
    }

    // MARK: - Running Bootstrap

    func runBootstrap(additionalArguments: [String] = []) {
        guard !isRunning else { return }

        isRunning = true
        lastExitCode = nil
        outputLines.removeAll()
        connectionError = nil

        // Always include --verbose
        var arguments = ["--verbose"]
        arguments.append(contentsOf: additionalArguments)

        connect()

        helperProxy { proxy in
            proxy.runBootstrap(arguments: arguments)
        }
    }

    // MARK: - Stop Bootstrap

    func stopBootstrap() {
        helperProxy { proxy in
            proxy.stopBootstrap()
        }
        isRunning = false
        lastExitCode = nil
        outputLines.append(OutputLine(text: "[WARNING] Bootstrap process stopped by user.", level: .warning))
    }

    // MARK: - Preference Management

    /// Performs one preference write with an administrator's authorization and
    /// returns whether the helper accepted it.
    func perform(_ write: BootstrapPreferenceWrite, authorization: Data) async -> Bool {
        let domain = BootstrapMateConstants.daemonIdentifier
        return await callHelper { proxy, reply in
            switch write {
            case .string(let key, let value):
                proxy.setPreference(key: key, stringValue: value, domain: domain, authorization: authorization, withReply: reply)
            case .bool(let key, let value):
                proxy.setBoolPreference(key: key, boolValue: value, domain: domain, authorization: authorization, withReply: reply)
            case .int(let key, let value):
                proxy.setIntPreference(key: key, intValue: value, domain: domain, authorization: authorization, withReply: reply)
            case .remove(let key):
                proxy.removePreference(key: key, domain: domain, authorization: authorization, withReply: reply)
            }
        }
    }

    /// Calls the helper and waits for its reply; a refused or broken connection
    /// counts as a failed write rather than leaving the caller waiting.
    private func callHelper(
        _ body: @escaping @Sendable (HelperXPCProtocol, @escaping @Sendable (Bool) -> Void) -> Void
    ) async -> Bool {
        connect()
        guard let conn = connection else { return false }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in once.resume(false) }) as? HelperXPCProtocol else {
                once.resume(false)
                return
            }
            body(proxy) { ok in once.resume(ok) }
        }
    }

    // MARK: - Private

    /// Creates XPC callbacks in a nonisolated context so they don't inherit
    /// @MainActor isolation and crash when called on the XPC dispatch queue.
    private nonisolated func makeInvalidationHandler() -> @Sendable () -> Void {
        { [weak self] in
            Task { @MainActor [weak self] in
                self?.connection = nil
                self?.reportConnectionFailure("Connection to helper was invalidated")
            }
        }
    }

    private nonisolated func makeInterruptionHandler() -> @Sendable () -> Void {
        { [weak self] in
            Task { @MainActor [weak self] in
                self?.reportConnectionFailure("Connection to helper was interrupted")
            }
        }
    }

    private nonisolated func makeErrorHandler() -> @Sendable (any Error) -> Void {
        { [weak self] error in
            Task { @MainActor [weak self] in
                self?.reportConnectionFailure(error.localizedDescription)
            }
        }
    }

    /// A failed connection during a run must show up in the run output; setting
    /// connectionError alone left the window blank with nothing explaining why.
    private func reportConnectionFailure(_ message: String) {
        connectionError = message
        if isRunning {
            outputLines.append(OutputLine(text: "ERROR: \(message). The helper refused the connection or is not running; see the system log for com.github.bootstrapmate.helper.", level: .error))
            isRunning = false
        }
    }

    private func helperProxy(block: @escaping (HelperXPCProtocol) -> Void) {
        guard let conn = connection else {
            connectionError = "No connection to helper"
            return
        }
        guard let proxy = conn.remoteObjectProxyWithErrorHandler(makeErrorHandler()) as? HelperXPCProtocol else {
            connectionError = "Failed to get helper proxy"
            return
        }
        block(proxy)
    }
}

/// Resumes a continuation exactly once, whichever of the reply or the
/// connection error arrives first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

// MARK: - HelperXPCClientProtocol

extension XPCClient: HelperXPCClientProtocol {

    nonisolated func didReceiveOutput(_ line: String) {
        let level = Self.parseLogLevel(line)
        Task { @MainActor in
            outputLines.append(OutputLine(text: line, level: level))
        }
    }

    nonisolated func runDidComplete(success: Bool, exitCode: Int32) {
        Task { @MainActor in
            isRunning = false
            lastExitCode = exitCode
        }
    }

    nonisolated func didEncounterError(_ message: String) {
        Task { @MainActor in
            connectionError = message
            outputLines.append(OutputLine(text: "ERROR: \(message)", level: .error))
        }
    }

    private static nonisolated func parseLogLevel(_ line: String) -> OutputLine.LogLevel {
        if line.contains("[x]") || line.contains("[ERROR]") { return .error }
        if line.contains("[!]") || line.contains("[WARNING]") { return .warning }
        if line.contains("[+]") || line.contains("[SUCCESS]") || line.contains("✓") { return .success }
        if line.contains("[~]") || line.contains("[DEBUG]") || line.contains("[DBG]") { return .debug }
        return .info
    }
}
