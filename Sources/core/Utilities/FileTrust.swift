//
//  FileTrust.swift
//  BootstrapMate
//
//  BootstrapMate runs as root and acts on files it finds on disk: state that
//  steers the next run, the force file, and cached payloads it installs or
//  runs. Each of those is acted on only when no other account could have
//  written it.
//

import Foundation

public enum FileTrust {

    /// The owners whose files a run accepts: root, and the account running
    /// the tool. On a managed Mac the tool runs as root, so that is root
    /// alone; under `swift test` it is the developer's own account.
    static func isTrustedOwner(_ uid: uid_t) -> Bool {
        uid == 0 || uid == geteuid()
    }

    private static func lstatInfo(_ path: String) -> stat? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info
    }

    private static func notWritableByOthers(_ mode: mode_t) -> Bool {
        mode & (S_IWGRP | S_IWOTH) == 0
    }

    /// True for a real directory, not a link, owned by a trusted account and
    /// writable by no one else.
    public static func isTrustedDirectory(_ path: String) -> Bool {
        guard let info = lstatInfo(path) else { return false }
        return info.st_mode & S_IFMT == S_IFDIR
            && isTrustedOwner(info.st_uid)
            && notWritableByOthers(info.st_mode)
    }

    /// True for a regular file, not a link, owned by a trusted account,
    /// writable by no one else, in a directory that is trusted the same way.
    /// Only such a file is read as state or installed or run.
    public static func isTrustedFile(_ path: String) -> Bool {
        guard let info = lstatInfo(path) else { return false }
        return info.st_mode & S_IFMT == S_IFREG
            && isTrustedOwner(info.st_uid)
            && notWritableByOthers(info.st_mode)
            && isTrustedDirectory((path as NSString).deletingLastPathComponent)
    }

    /// True for a marker file, such as the force file, that only a trusted
    /// account could have put there: owned by one, in a trusted directory.
    /// Its own permissions do not matter, because only its presence is read.
    public static func isTrustedMarker(_ path: String) -> Bool {
        guard let info = lstatInfo(path) else { return false }
        return info.st_mode & S_IFMT == S_IFREG
            && isTrustedOwner(info.st_uid)
            && isTrustedDirectory((path as NSString).deletingLastPathComponent)
    }

    /// Creates `path` as a directory if it is missing and, when running as
    /// root, makes it root:wheel and writable by no one else. A link or file
    /// in its place is left alone and reported. Returns whether the
    /// directory ends up trusted.
    @discardableResult
    public static func secureDirectory(_ path: String) -> Bool {
        let fm = FileManager.default
        if lstatInfo(path) == nil {
            try? fm.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        }
        guard let info = lstatInfo(path), info.st_mode & S_IFMT == S_IFDIR else { return false }
        if geteuid() == 0 {
            if info.st_uid != 0 || info.st_gid != 0 {
                _ = lchown(path, 0, 0)
            }
            if !notWritableByOthers(info.st_mode) {
                _ = chmod(path, (info.st_mode & 0o7777) & ~(S_IWGRP | S_IWOTH))
            }
        }
        return isTrustedDirectory(path)
    }

    /// Writes `data` to `path` as a new file: whatever was there, including a
    /// link, is removed first, and the file is created exclusively, so the
    /// write never follows a link to somewhere else.
    public static func writeNewFile(_ data: Data, to path: String) throws {
        let fm = FileManager.default
        if lstatInfo(path) != nil {
            try fm.removeItem(atPath: path)
        }
        try data.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
    }
}
