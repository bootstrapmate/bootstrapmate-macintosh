import Foundation
import ArgumentParser
import BootstrapMateCore

@main
struct BootstrapMate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bootstrapmate",
        abstract: "BootstrapMate - Swift deployment utility for ADE-driven macOS setup"
    )

    @Option(name: .long, help: "JSON manifest URL to load before executing stages.")
    var jsonurl: String?

    @Option(name: .long, help: "Optional authorization header value.")
    var headers: String?

    @Flag(name: .long, help: "When set, no installer actions are performed.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Follow HTTP redirects while downloading manifests and artifacts.")
    var followRedirects: Bool = false

    @Flag(name: .long, help: "Only run userland scripts and exit.")
    var userscript: Bool = false

    @Flag(name: .long, help: "Trigger a reboot after all stages complete.")
    var reboot: Bool = false

    func run() throws {
        Logger.log("BootstrapMate CLI invoked with arguments: \(CommandLine.arguments.joined(separator: " "))")

        if let headers {
            NetworkManager.shared.authorizationHeader = headers
        }

        if let jsonurl {
            let loaded = ManifestManager.shared.loadManifest(
                from: jsonurl,
                followRedirects: followRedirects,
                authHeader: headers,
                skipValidation: false
            )

            guard loaded else {
                Logger.log("Failed to load manifest from \(jsonurl). Exiting with error.")
                Foundation.exit(1)
            }
        } else {
            ManifestManager.shared.loadFromMDMOrLocal()
        }

        ManifestManager.shared.setDryRun(dryRun)

        if userscript {
            ScriptManager.shared.runUserScriptOnly()
            Foundation.exit(0)
        }

        let success = IAOrchestrator.shared.runAllStages(reboot: reboot)
        Foundation.exit(success ? 0 : 1)
    }
}
