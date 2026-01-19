//
//  TaskManager.swift
//  BootstrapMate
//
//  Legacy compatibility layer - delegates to IAOrchestrator for actual execution.
//  Maintained for backwards compatibility with existing integrations.
//

import Foundation

/// Legacy entry point - delegates to IAOrchestrator
/// @deprecated Use IAOrchestrator.shared.runAllStages() directly
public func executeInstallation() {
    Logger.warning("TaskManager.executeInstallation() is deprecated - use IAOrchestrator directly")
    
    // Simply delegate to the orchestrator with default settings
    _ = IAOrchestrator.shared.runAllStages(reboot: false)
}
