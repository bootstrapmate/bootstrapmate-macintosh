//
//  DryRun.swift
//  BootstrapMate
//
//  The one switch every action site reads to tell a rehearsal from a real run.
//

import Foundation

/// A dry run rehearses a manifest against a real Mac. It downloads every item
/// and checks its hash, and checks package signatures, so a broken URL, a
/// stale hash or an untrusted package shows up just as it would for real. It
/// never changes the Mac: no package is installed, no script runs, nothing is
/// added to the install ledger, and the run does not reboot, report, mark
/// itself complete or remove its LaunchDaemon.
public enum DryRun {
    nonisolated(unsafe) public static var isEnabled = false

    /// Session run type recorded for a dry run, so `--last-run` never reports
    /// a rehearsal as a provisioning run.
    public static let runType = "dry-run"
}
