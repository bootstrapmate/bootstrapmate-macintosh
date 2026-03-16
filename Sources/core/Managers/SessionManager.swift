import Foundation
import SystemConfiguration

public final class SessionManager {
    nonisolated(unsafe) public static let shared = SessionManager()

    private init() {}

    public func getConsoleUser() -> (String?, uid_t?) {
        var uid: uid_t = 0
        var gid: gid_t = 0
        let user = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?
        return (user, uid)
    }
}
