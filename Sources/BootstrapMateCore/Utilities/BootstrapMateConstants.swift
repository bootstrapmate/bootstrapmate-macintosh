import Foundation

public enum BootstrapMateConstants {
    public static let daemonIdentifier = "com.github.bootstrapmate"
    public static let executablePath = "/Applications/Utilities/BootstrapMate.app/Contents/MacOS/installapplications"
    public static let helperBundleID = "com.github.bootstrapmate.helper"
    public static let helperPlistName = "com.github.bootstrapmate.helper.plist"
    public static let defaultRetryCount = 3
    public static let defaultRetryDelay = 5
    public static let cacheDirectory = "/Library/Managed Bootstrap/cache"
    
    // Version in YYYY.MM.DD.HHMM format - generated at compile time
    public static let version: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd.HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }()
}
