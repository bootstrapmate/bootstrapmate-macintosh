//
//  SettingsViewModel.swift
//  BootstrapMate
//
//  Manages all configuration settings for the GUI.
//  Reads current values from ConfigManager and management status from ManagementDetector.
//  Edits stay in the window until the user clicks Save, which asks for an
//  administrator and then writes the changed, unmanaged keys through the
//  privileged helper. Keys a profile manages are never written.
//

import Foundation
import BootstrapMateCore

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Helper

    private var xpcClient: XPCClient?

    func configure(client: XPCClient) {
        xpcClient = client
    }

    // MARK: - Setting Values

    // Connection
    var jsonUrl: String = ""
    var authorizationHeader: String = ""
    var hasExistingAuth: Bool = false
    var followRedirects: Bool = true

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
    var retainCache: Bool = true
    var networkTimeout: Int = 120

    // MARK: - Save Status

    private(set) var saveStatus: SaveStatus = .idle

    enum SaveStatus: Equatable {
        case idle, saving, saved, failed(String)
    }

    /// The settings as last read from, or written to, the machine.
    private var saved = BootstrapPreferenceSnapshot()

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

    // MARK: - Management

    private(set) var managedKeys: Set<String> = []

    /// True when a profile forces at least one of the app's keys.
    var hasManagedSettings: Bool { !managedKeys.isEmpty }

    func isManaged(_ key: String) -> Bool {
        managedKeys.contains(ManagementDetector.canonicalKey(for: key))
    }

    // MARK: - Loading

    func load() {
        ConfigManager.shared.reloadPreferences()
        let config = ConfigManager.shared.config
        let detector = ManagementDetector.shared

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
        retainCache = config.retainCache
        networkTimeout = config.networkTimeout
        saved = current
        saved.headers = ""
    }

    // MARK: - Saving

    /// The settings as the window currently holds them.
    var current: BootstrapPreferenceSnapshot {
        var snapshot = BootstrapPreferenceSnapshot()
        snapshot.url = jsonUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.headers = authorizationHeader
        snapshot.followRedirects = followRedirects
        snapshot.reboot = reboot
        snapshot.silentMode = silentMode
        snapshot.verboseMode = verboseMode
        snapshot.dryRun = dryRun
        snapshot.userscriptOnly = userscriptOnly
        snapshot.enableDialog = enableDialog
        snapshot.dialogTitle = dialogTitle
        snapshot.dialogMessage = dialogMessage
        snapshot.dialogIcon = dialogIcon
        snapshot.blurScreen = blurScreen
        snapshot.retainCache = retainCache
        snapshot.networkTimeout = networkTimeout
        return snapshot
    }

    private var pendingWrites: [BootstrapPreferenceWrite] {
        BootstrapPreferenceEdits.writes(from: saved, to: current, isManaged: isManaged)
    }

    /// True when an unmanaged setting differs from what the machine holds.
    var hasUnsavedChanges: Bool { !pendingWrites.isEmpty }

    /// True when a profile manages every setting the window edits, so the
    /// window is read-only and offers no Save.
    var allSettingsManaged: Bool {
        HelperPreferencePolicy.allowedKeys.keys.allSatisfy(isManaged)
    }

    /// Puts every field back to the values the machine holds.
    func revert() {
        apply(saved)
        authorizationHeader = ""
        if case .failed = saveStatus { saveStatus = .idle }
    }

    /// Asks an administrator to authenticate, then writes every changed,
    /// unmanaged setting through the helper. Cancelling the prompt leaves the
    /// edits in the window, unsaved.
    func save() async {
        guard let client = xpcClient else { return }
        let pending = pendingWrites
        guard !pending.isEmpty else { return }
        guard let admin = AdminAuthorization.authorize() else { return }
        defer { admin.free() }

        saveStatus = .saving
        var applied = saved
        var failed: [String] = []
        for write in pending {
            if await client.perform(write, authorization: admin.externalForm) {
                if write.key == "headers" {
                    authorizationHeader = ""
                    hasExistingAuth = true
                } else {
                    BootstrapPreferenceEdits.record(write, into: &applied)
                }
            } else {
                failed.append(write.key)
            }
        }
        saved = applied

        if failed.isEmpty {
            saveStatus = .saved
            try? await Task.sleep(for: .seconds(2))
            if saveStatus == .saved { saveStatus = .idle }
        } else {
            saveStatus = .failed("Could not save \(failed.joined(separator: ", ")): the helper refused or is not available")
        }
    }

    private func apply(_ snapshot: BootstrapPreferenceSnapshot) {
        jsonUrl = snapshot.url
        followRedirects = snapshot.followRedirects
        reboot = snapshot.reboot
        silentMode = snapshot.silentMode
        verboseMode = snapshot.verboseMode
        dryRun = snapshot.dryRun
        userscriptOnly = snapshot.userscriptOnly
        enableDialog = snapshot.enableDialog
        dialogTitle = snapshot.dialogTitle
        dialogMessage = snapshot.dialogMessage
        dialogIcon = snapshot.dialogIcon
        blurScreen = snapshot.blurScreen
        retainCache = snapshot.retainCache
        networkTimeout = snapshot.networkTimeout
    }

    /// Builds CLI arguments matching current settings for a GUI-triggered run.
    func buildRunArguments() -> [String] {
        var args: [String] = []
        if !jsonUrl.isEmpty { args.append(contentsOf: ["--jsonurl", jsonUrl]) }
        if !authorizationHeader.isEmpty { args.append(contentsOf: ["--headers", authorizationHeader]) }
        if !followRedirects { args.append("--no-follow-redirects") }
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
