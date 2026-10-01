//
//  InstallLedger.swift
//  BootstrapMate
//
//  Remembers which package files this tool has installed, by content hash.
//

import Foundation

/// A baseline run repeats on a machine in use, so it must not reinstall a
/// package it already put there. The receipt check covers packages whose
/// manifest `packageid` matches a receipt; it cannot cover a payload-free
/// package, which leaves no receipt, or an entry whose `packageid` is wrong.
/// The ledger covers both: the same file, by hash, is installed once.
public struct InstallLedger {
    public static let defaultPath = "/Library/Managed Bootstrap/installed.json"

    public let path: String

    public init(path: String = InstallLedger.defaultPath) {
        self.path = path
    }

    public func contains(hash: String) -> Bool {
        guard !hash.isEmpty else { return false }
        return load()[hash.lowercased()] != nil
    }

    public func record(hash: String, name: String, date: Date = Date()) {
        guard !hash.isEmpty else { return }
        var entries = load()
        entries[hash.lowercased()] = [
            "name": name,
            "installed": ISO8601DateFormatter().string(from: date)
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: entries,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func load() -> [String: [String: String]] {
        guard let data = FileManager.default.contents(atPath: path),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            return [:]
        }
        return entries
    }
}
