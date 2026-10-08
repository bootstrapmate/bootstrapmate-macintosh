//
//  AuthorizationHeaderFile.swift
//  BootstrapMate
//
//  A configuration profile delivers its preferences to a file every user can
//  read, so a credential set there is visible to anyone logged in. This file
//  is the alternative: the full Authorization header value, kept where only
//  root can read it.
//

import Foundation

public enum AuthorizationHeaderFile {

    /// Where a root-only Authorization header is kept.
    public static let defaultPath = BootstrapMateConstants.secretsDirectory + "/AuthorizationHeader"

    /// Anything larger is not a header.
    static let maxSize = 64 * 1024

    private static let groupOrWorldBits: mode_t = S_IRWXG | S_IRWXO

    /// The header in `path`, trimmed, or nil when there is none to trust.
    ///
    /// The file counts only when it is a regular file, not a link, owned by
    /// root (or, under `swift test`, the account running the tests), with no
    /// group or world permission bits (0600 or 0400), and its directory is
    /// owned the same way with no group or world bits (0700). A file that
    /// exists but fails those checks is ignored with a warning. A missing or
    /// unreadable file, which is what a run as a standard user finds, is
    /// simply nothing.
    public static func read(at path: String = defaultPath) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        var dirInfo = stat()
        guard lstat(parent, &dirInfo) == 0 else { return nil }

        var fileInfo = stat()
        guard lstat(path, &fileInfo) == 0 else { return nil }

        guard dirInfo.st_mode & S_IFMT == S_IFDIR,
              FileTrust.isTrustedOwner(dirInfo.st_uid),
              dirInfo.st_mode & groupOrWorldBits == 0
        else {
            Logger.warning("Ignoring \(path): \(parent) must be a directory owned by root with mode 0700")
            return nil
        }

        guard fileInfo.st_mode & S_IFMT == S_IFREG,
              FileTrust.isTrustedOwner(fileInfo.st_uid),
              fileInfo.st_mode & groupOrWorldBits == 0
        else {
            Logger.warning("Ignoring \(path): it must be a regular file owned by root with mode 0600")
            return nil
        }

        // Opened without following a link, and checked again on the open
        // descriptor, so what is read is the file that passed the checks.
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var openInfo = stat()
        guard fstat(fd, &openInfo) == 0,
              openInfo.st_dev == fileInfo.st_dev,
              openInfo.st_ino == fileInfo.st_ino,
              openInfo.st_mode & groupOrWorldBits == 0,
              openInfo.st_size <= maxSize
        else {
            Logger.warning("Ignoring \(path): it changed while being read or is too large")
            return nil
        }

        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return NetworkManager.usableHeader(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
