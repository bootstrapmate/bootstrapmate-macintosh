import Foundation

/// The settings the Prefs window edits, as it holds them.
///
/// `headers` is the newly typed authorization header only. The stored header is
/// never read back into the window, so an empty value means "leave it as it is".
public struct BootstrapPreferenceSnapshot: Equatable, Sendable {
    public var url = ""
    public var headers = ""
    public var followRedirects = true
    public var reboot = false
    public var silentMode = false
    public var verboseMode = false
    public var dryRun = false
    public var userscriptOnly = false
    public var enableDialog = true
    public var dialogTitle = "Setting up your Mac"
    public var dialogMessage = "Please wait while we configure your device..."
    public var dialogIcon = ""
    public var blurScreen = false
    public var retainCache = true
    public var networkTimeout = 120

    public init() {}
}

/// One preference write the helper performs, keyed by the stored preference name.
public enum BootstrapPreferenceWrite: Equatable, Sendable {
    case string(String, String)
    case bool(String, Bool)
    case int(String, Int)
    case remove(String)

    public var key: String {
        switch self {
        case .string(let key, _), .bool(let key, _), .int(let key, _), .remove(let key):
            return key
        }
    }
}

public enum BootstrapPreferenceEdits {
    /// The writes that take the stored settings from `saved` to `current`,
    /// skipping every key a profile manages. An empty string removes the key,
    /// so BootstrapMate falls back to its default.
    public static func writes(
        from saved: BootstrapPreferenceSnapshot,
        to current: BootstrapPreferenceSnapshot,
        isManaged: (String) -> Bool
    ) -> [BootstrapPreferenceWrite] {
        var writes: [BootstrapPreferenceWrite] = []

        func string(_ key: String, _ old: String, _ new: String) {
            guard old != new, !isManaged(key) else { return }
            writes.append(new.isEmpty ? .remove(key) : .string(key, new))
        }
        func bool(_ key: String, _ old: Bool, _ new: Bool) {
            guard old != new, !isManaged(key) else { return }
            writes.append(.bool(key, new))
        }
        func int(_ key: String, _ old: Int, _ new: Int) {
            guard old != new, !isManaged(key) else { return }
            writes.append(.int(key, new))
        }

        string("url", saved.url, current.url)
        if !current.headers.isEmpty, !isManaged("headers") {
            writes.append(.string("headers", current.headers))
        }
        bool("followRedirects", saved.followRedirects, current.followRedirects)
        bool("reboot", saved.reboot, current.reboot)
        bool("silentMode", saved.silentMode, current.silentMode)
        bool("verboseMode", saved.verboseMode, current.verboseMode)
        bool("dryRun", saved.dryRun, current.dryRun)
        bool("userscriptOnly", saved.userscriptOnly, current.userscriptOnly)
        bool("enableDialog", saved.enableDialog, current.enableDialog)
        string("dialogTitle", saved.dialogTitle, current.dialogTitle)
        string("dialogMessage", saved.dialogMessage, current.dialogMessage)
        string("dialogIcon", saved.dialogIcon, current.dialogIcon)
        bool("blurScreen", saved.blurScreen, current.blurScreen)
        bool("retainCache", saved.retainCache, current.retainCache)
        int("networkTimeout", saved.networkTimeout, current.networkTimeout)
        return writes
    }

    /// Updates `snapshot` for one write that succeeded, so a write that failed
    /// still shows as unsaved and is retried by the next Save.
    public static func record(_ write: BootstrapPreferenceWrite, into snapshot: inout BootstrapPreferenceSnapshot) {
        let defaults = BootstrapPreferenceSnapshot()
        switch write {
        case .string(let key, let value):
            switch key {
            case "url": snapshot.url = value
            case "dialogTitle": snapshot.dialogTitle = value
            case "dialogMessage": snapshot.dialogMessage = value
            case "dialogIcon": snapshot.dialogIcon = value
            default: break
            }
        case .remove(let key):
            switch key {
            case "url": snapshot.url = ""
            case "dialogTitle": snapshot.dialogTitle = ""
            case "dialogMessage": snapshot.dialogMessage = ""
            case "dialogIcon": snapshot.dialogIcon = defaults.dialogIcon
            default: break
            }
        case .bool(let key, let value):
            switch key {
            case "followRedirects": snapshot.followRedirects = value
            case "reboot": snapshot.reboot = value
            case "silentMode": snapshot.silentMode = value
            case "verboseMode": snapshot.verboseMode = value
            case "dryRun": snapshot.dryRun = value
            case "userscriptOnly": snapshot.userscriptOnly = value
            case "enableDialog": snapshot.enableDialog = value
            case "blurScreen": snapshot.blurScreen = value
            case "retainCache": snapshot.retainCache = value
            default: break
            }
        case .int(let key, let value):
            if key == "networkTimeout" { snapshot.networkTimeout = value }
        }
    }
}
