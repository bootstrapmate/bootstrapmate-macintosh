//
//  RunLock.swift
//  BootstrapMate
//
//  One bootstrap run at a time. A second instance (a reload while a run is
//  going, the settings app's Run button) exits instead of running alongside,
//  and never mistakes the live run's "running" record for an orphan.
//

import Foundation

public final class RunLock {
    public static let defaultPath = "/Library/Managed Bootstrap/.run.lock"

    private let fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }

    /// Takes the lock, or returns nil when another process holds it. The
    /// descriptor is close-on-exec, so a child left running after this
    /// process exits (a fire-and-forget script) never holds the lock.
    public static func acquire(at path: String = defaultPath) -> RunLock? {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        return RunLock(fd: fd)
    }
}
