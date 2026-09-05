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

    /// The console user that per-user work may be dispatched to, or nil when
    /// the console is held by a system account (loginwindow, _mbsetupuser,
    /// root, any underscore-prefixed service account) or by nobody at all.
    public func getValidConsoleUser() -> (username: String, uid: uid_t)? {
        let (username, uid) = getConsoleUser()
        guard let user = username,
              let userUid = uid,
              userUid != 0,
              user != "loginwindow",
              user != "_mbsetupuser",
              user != "root",
              !user.hasPrefix("_") else {
            return nil
        }
        return (user, userUid)
    }
}
