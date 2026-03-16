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

    // MARK: - Auto-Save

    private var xpcClient: XPCClient?
    private var autoSaveTask: Task<Void, Never>?
    private var isLoading = false

    func configure(client: XPCClient) {
        xpcClient = client
    }

    private func scheduleAutoSave() {
        guard !isLoading, let client = xpcClient, !client.isRunning else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.75))
            guard !Task.isCancelled, let self else { return }
            self.save(using: client)
        }
    }

    // MARK: - Setting Values

    // Connection
    var jsonUrl: String = "" { didSet { scheduleAutoSave() } }
    var authorizationHeader: String = "" { didSet { scheduleAutoSave() } }
    var hasExistingAuth: Bool = false
    var followRedirects: Bool = false { didSet { scheduleAutoSave() } }

    // Behavior
    var reboot: Bool = false { didSet { scheduleAutoSave() } }
    var silentMode: Bool = false { didSet { scheduleAutoSave() } }
    var verboseMode: Bool = false { didSet { scheduleAutoSave() } }
    var dryRun: Bool = false { didSet { scheduleAutoSave() } }
    var userscriptOnly: Bool = false { didSet { scheduleAutoSave() } }

    // Dialog / UI
    var enableDialog: Bool = true { didSet { scheduleAutoSave() } }
    var dialogTitle: String = "Setting up your Mac" { didSet { scheduleAutoSave() } }
    var dialogMessage: String = "Please wait while we configure your device..." { didSet { scheduleAutoSave() } }
    var dialogIcon: String = "" { didSet { scheduleAutoSave() } }
    var blurScreen: Bool = false { didSet { scheduleAutoSave() } }

    // Advanced
    var customInstallPath: String = "" { didSet { scheduleAutoSave() } }
    var daemonIdentifier: String = BootstrapMateConstants.daemonIdentifier { didSet { scheduleAutoSave() } }
    var agentIdentifier: String = BootstrapMateConstants.daemonIdentifier { didSet { scheduleAutoSave() } }
    var networkTimeout: Int = 120 { didSet { scheduleAutoSave() } }

    // MARK: - Save Status

    private(set) var saveStatus: SaveStatus = .idle

    enum SaveStatus {
        case idle, saving, saved, failed(String)
    }

    // MARK: - Manifest Preview

    enum PreviewState {
        case idle
        case loading
        case loaded(String)
        case failed(String)
    }

    private(set) var manifestPreviewState: PreviewState = .idle

    func fetchManifestPreview() {
        guard !jsonUrl.isEmpty, let url = URL(string: jsonUrl) else {
            manifestPreviewState = .failed("Invalid or empty URL")
            return
        }

        // Use newly entered header first; fall back to the stored one if present
        let authHeader: String?
        if !authorizationHeader.isEmpty {
            authHeader = authorizationHeader
        } else if hasExistingAuth {
            authHeader = ConfigManager.shared.config.authorizationHeader
        } else {
            authHeader = nil
        }

        manifestPreviewState = .loading

        NetworkManager.shared.downloadData(from: url, followRedirects: followRedirects, authHeader: authHeader) { [weak self] data, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.manifestPreviewState = .failed(error.localizedDescription)
                    return
                }
                guard let data else {
                    self.manifestPreviewState = .failed("No data received")
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    self.manifestPreviewState = .loaded(prettyString)
                } else if let rawString = String(data: data, encoding: .utf8) {
                    self.manifestPreviewState = .loaded(rawString)
                } else {
                    self.manifestPreviewState = .failed("Unable to decode response")
                }
            }
        }
    }

    func resetManifestPreview() {
        manifestPreviewState = .idle
    }

    // MARK: - MDM Status

    private(set) var managedKeys: Set<String> = []

    func isMDMManaged(_ key: String) -> Bool {
        managedKeys.contains(key)
    }

    // MARK: - Loading

    func load() {
        isLoading = true
        defer { isLoading = false }

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
