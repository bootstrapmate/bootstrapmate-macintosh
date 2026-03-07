//
//  SettingsViewModel.swift
//  BootstrapMate
//
//  Manages all configuration settings for the GUI.
//  Reads current values from ConfigManager and MDM status from MDMDetector.
//  Writes changes via XPC helper for system-level persistence.
//

import Foundation
import BootstrapMateCore

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Setting Values

    // Connection
    var jsonUrl: String = ""
    var authorizationHeader: String = ""
    var hasExistingAuth: Bool = false
    var followRedirects: Bool = false

    // Behavior
    var reboot: Bool = false
    var silentMode: Bool = false
    var verboseMode: Bool = false
    var dryRun: Bool = false
    var userscriptOnly: Bool = false

    // Dialog / UI
    var enableDialog: Bool = true
    var dialogTitle: String = "Setting up your Mac"
    var dialogMessage: String = "Please wait while we configure your device..."
    var dialogIcon: String = ""
    var blurScreen: Bool = false

    // Advanced
    var customInstallPath: String = ""
    var daemonIdentifier: String = BootstrapMateConstants.daemonIdentifier
    var agentIdentifier: String = BootstrapMateConstants.daemonIdentifier
    var networkTimeout: Int = 120

    // MARK: - Save Status

    private(set) var saveStatus: SaveStatus = .idle

    enum SaveStatus {
        case idle, saving, saved, failed(String)
    }

    // MARK: - MDM Status

    private(set) var managedKeys: Set<String> = []

    func isMDMManaged(_ key: String) -> Bool {
        managedKeys.contains(key)
    }

    // MARK: - Loading

    func load() {
        ConfigManager.shared.reloadPreferences()
        let config = ConfigManager.shared.config
        let detector = MDMDetector.shared

        managedKeys = detector.allManagedKeys()

        jsonUrl = config.jsonUrl ?? ""
        hasExistingAuth = !(config.authorizationHeader ?? "").isEmpty
        authorizationHeader = ""
        followRedirects = config.followRedirects
        reboot = config.reboot
        silentMode = config.silentMode
        verboseMode = config.verboseMode
        dryRun = config.dryRun
        userscriptOnly = config.userscriptOnly
        enableDialog = config.enableDialog
        dialogTitle = config.dialogTitle
        dialogMessage = config.dialogMessage
        dialogIcon = config.dialogIcon ?? ""
        blurScreen = config.blurScreen
        customInstallPath = config.customInstallPath ?? ""
        daemonIdentifier = config.daemonIdentifier
        agentIdentifier = config.agentIdentifier
        networkTimeout = config.networkTimeout
    }

    // MARK: - Saving

    /// Saves all non-MDM-managed settings via the XPC helper.
    func save(using client: XPCClient) {
        saveStatus = .saving

        func saveString(_ key: String, _ value: String) {
            guard !isMDMManaged(key) else { return }
            if value.isEmpty {
                client.removePreference(key: key)
            } else {
                client.setStringPreference(key: key, value: value)
            }
        }

        func saveBool(_ key: String, _ value: Bool) {
            guard !isMDMManaged(key) else { return }
            client.setBoolPreference(key: key, value: value)
        }

        func saveInt(_ key: String, _ value: Int) {
            guard !isMDMManaged(key) else { return }
            client.setIntPreference(key: key, value: value)
        }

        // Connection
        saveString("url", jsonUrl)
        if !authorizationHeader.isEmpty {
            saveString("headers", authorizationHeader)
        }
        saveBool("followRedirects", followRedirects)

        // Behavior
        saveBool("reboot", reboot)
        saveBool("silentMode", silentMode)
        saveBool("verboseMode", verboseMode)
        saveBool("dryRun", dryRun)
        saveBool("userscriptOnly", userscriptOnly)

        // Dialog
        saveBool("enableDialog", enableDialog)
        saveString("dialogTitle", dialogTitle)
        saveString("dialogMessage", dialogMessage)
        saveString("dialogIcon", dialogIcon)
        saveBool("blurScreen", blurScreen)

        // Advanced
        saveString("installPath", customInstallPath)
        saveString("daemonIdentifier", daemonIdentifier)
        saveString("agentIdentifier", agentIdentifier)
        saveInt("networkTimeout", networkTimeout)

        saveStatus = .saved
        Task {
            try? await Task.sleep(for: .seconds(2))
            if case .saved = saveStatus { saveStatus = .idle }
        }
    }

    /// Builds CLI arguments matching current settings for a GUI-triggered run.
    func buildRunArguments() -> [String] {
        var args: [String] = []
        if !jsonUrl.isEmpty { args.append(contentsOf: ["--jsonurl", jsonUrl]) }
        if !authorizationHeader.isEmpty { args.append(contentsOf: ["--headers", authorizationHeader]) }
        if followRedirects { args.append("--follow-redirects") }
        if dryRun { args.append("--dry-run") }
        if reboot { args.append("--reboot") }
        if silentMode { args.append("--silent") }
        if !enableDialog { args.append("--no-dialog") }
        if !dialogTitle.isEmpty && dialogTitle != "Setting up your Mac" {
            args.append(contentsOf: ["--dialog-title", dialogTitle])
        }
        if !dialogMessage.isEmpty && dialogMessage != "Please wait while we configure your device..." {
            args.append(contentsOf: ["--dialog-message", dialogMessage])
        }
        if networkTimeout != 120 {
            args.append(contentsOf: ["--network-timeout", String(networkTimeout)])
        }
        return args
    }
}
