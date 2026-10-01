//
//  PreflightDecision.swift
//  BootstrapMate
//
//  Maps a preflight script's exit code to what the rest of the run does.
//

import Foundation

public enum PreflightDecision: Equatable {
    /// Exit 0 — the machine needs nothing; skip every later stage.
    case skip
    /// Exit 2 — the machine is already provisioned; bring its tooling back to
    /// the manifest's baseline without provisioning it again.
    case baseline
    /// Any other positive exit — run the full bootstrap.
    case provision
    /// Negative exit — the script itself failed.
    case failed

    /// Exit code a preflight script returns to request baseline mode.
    public static let baselineExitCode: Int32 = 2

    public static func from(exitCode: Int32) -> PreflightDecision {
        if exitCode == 0 { return .skip }
        if exitCode == baselineExitCode { return .baseline }
        return exitCode > 0 ? .provision : .failed
    }
}

public extension ManifestItem {
    /// Whether this item runs in baseline mode. Items opt out with
    /// `"baseline": false`; everything else in setupassistant is included.
    var runsInBaseline: Bool {
        return baseline ?? true
    }
}
