//
//  main.swift
//  BootstrapMateHelper
//
//  Privileged XPC helper daemon. Runs as root via SMAppService,
//  executes the CLI binary and writes system-level preferences.
//

import Foundation
import BootstrapMateCore

final class HelperService: NSObject, NSXPCListenerDelegate, Sendable {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // Validate the connecting client is our signed GUI app
        guard validateClient(connection) else { return false }

        let exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedInterface = exportedInterface

        let remoteInterface = NSXPCInterface(with: HelperXPCClientProtocol.self)
        connection.remoteObjectInterface = remoteInterface

        let runner = HelperCommandRunner(connection: connection)
        connection.exportedObject = runner

        connection.invalidationHandler = { [weak runner] in
            runner?.cancelRunningProcess()
        }

        connection.resume()
        return true
    }

    private func validateClient(_ connection: NSXPCConnection) -> Bool {
        // In production, verify the code signing identity of the connecting process.
        // SMAppService handles registration trust; we additionally confirm the
        // connecting PID belongs to a process signed with our team ID.
        let pid = connection.processIdentifier
        guard pid > 0 else { return false }

        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let secCode = code else {
            return false
        }

        // Require the process be signed by our team
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"7TF6CSP83S\""
        var reqRef: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &reqRef) == errSecSuccess,
              let req = reqRef else {
            return false
        }

        return SecCodeCheckValidity(secCode, [], req) == errSecSuccess
    }
}

let delegate = HelperService()
let listener = NSXPCListener(machServiceName: kHelperMachServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
