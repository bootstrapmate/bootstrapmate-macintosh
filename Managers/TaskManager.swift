import Foundation

public func executeInstallation() {
    guard let config = ConfigManager.shared.config else {
        Logger.log("No config loaded. Exiting.")
        return
    }

    if let options = config.options, let enabled = options.enabled, !enabled {
        Logger.log("BootstrapMate is disabled in config. Exiting.")
        return
    }

    if let header = config.options?.authorizationHeader {
        NetworkManager.shared.authorizationHeader = header
    }

    for item in config.preflight {
        perform(item)
    }

    for item in config.setupassistant {
        perform(item)
    }

    for item in config.userland {
        perform(item)
    }
}

private func perform(_ item: BootstrapItem) {
    Logger.log("Performing item: \(item.name ?? item.file)")

    switch item.type {
    case "package":
        installPackage(item)
    case "rootscript", "userscript":
        runScript(item)
    default:
        Logger.log("Unknown item type: \(item.type)")
    }
}

private func installPackage(_ item: BootstrapItem) {
    Logger.log("Installing package: \(item.file)")
}

private func runScript(_ item: BootstrapItem) {
    Logger.log("Running script: \(item.file)")
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = [item.file]
    process.launch()
    process.waitUntilExit()
}
