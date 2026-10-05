import Foundation

public enum BootstrapMateConstants {
    public static let daemonIdentifier = "com.github.bootstrapmate"
    public static let executablePath = "/Applications/Utilities/Managed Bootstrap Install.app/Contents/MacOS/managedbootstrapinstall"
    public static let helperBundleID = "com.github.bootstrapmate.helper"
    public static let helperPlistName = "com.github.bootstrapmate.helper.plist"
    public static let defaultRetryCount = 3
    public static let defaultRetryDelay = 5
    /// The most download attempts any item gets in one run, whatever its
    /// manifest `retries` says.
    public static let maxDownloadAttempts = 5
    /// The longest wait between attempts, in seconds.
    public static let maxRetryDelay = 60

    /// Attempts for one item: the manifest's `retries`, kept within 1...max.
    public static func downloadAttempts(requested: Int?) -> Int {
        min(max(requested ?? defaultRetryCount, 1), maxDownloadAttempts)
    }

    /// Seconds between attempts: the manifest's `retrywait`, kept within 0...max.
    public static func retryDelay(requested: Int?) -> Int {
        min(max(requested ?? defaultRetryDelay, 0), maxRetryDelay)
    }
    public static let cacheDirectory = "/Library/Managed Bootstrap/cache"
    public static let logsDirectory = "/Library/Managed Bootstrap/logs"
    /// The most recent run's summary, beside the logs directory.
    public static let lastRunPath = "/Library/Managed Bootstrap/last-run.json"
    
    /// The running build's version (YYYY.MM.DD.HHMM), from the app bundle's
    /// Info.plist, else the value stamped in at build time. Never the clock.
    public static let version: String = BuildInfo.version()
}
