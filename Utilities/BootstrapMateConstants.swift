import Foundation

public enum BootstrapMateConstants {
    /// LaunchDaemon/LaunchAgent identifier
    public static let daemonIdentifier = "com.github.bootstrapmate"
    
    /// MDM preference domain for configuration
    public static let preferenceDomain = "com.github.bootstrapmate"
    
    /// Path to the main app bundle
    public static let appPath = "/Applications/Utilities/BootstrapMate.app"
    
    /// Path to the executable inside the app bundle
    public static let executablePath = "/Applications/Utilities/BootstrapMate.app/Contents/MacOS/installapplications"
    
    /// Symlink path for PATH access
    public static let symlinkDir = "/usr/local/bootstrapmate"
    public static let symlinkPath = "/usr/local/bootstrapmate/installapplications"
    
    /// LaunchDaemon plist path
    public static let launchDaemonPath = "/Library/LaunchDaemons/com.github.bootstrapmate.plist"
    
    /// Managed Bootstrap directory for all logs, cache, and support files
    public static let managedBootstrapDir = "/Library/Managed Bootstrap"
    public static let logDirectory = "/Library/Managed Bootstrap/logs"
    public static let cacheDirectory = "/Library/Managed Bootstrap/cache"
    
    /// Force-run trigger file (watched by LaunchDaemon)
    public static let forceRunFlagPath = "/Library/Managed Bootstrap/.bootstrapmate-force-run"
    
    /// Default retry settings
    public static let defaultRetryCount = 3
    public static let defaultRetryDelay = 5
    
    // Version in YYYY.MM.DD.HHMM format - generated at compile time
    public static let version: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd.HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }()
}
