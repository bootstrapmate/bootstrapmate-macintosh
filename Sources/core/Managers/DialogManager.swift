//
//  DialogManager.swift
//  BootstrapMate
//
//  SwiftDialog integration for user-facing progress UI during enrollment.
//  Gracefully degrades to headless mode if SwiftDialog is not available.
//

import Foundation

public final class DialogManager {
    nonisolated(unsafe) public static let shared = DialogManager()
    
    // SwiftDialog paths
    private let dialogPath = "/usr/local/bin/dialog"
    private let defaultCommandFile = "/var/tmp/dialog.log"
    
    // State
    private var dialogProcess: Process?
    private var commandFilePath: String
    private var isAvailable: Bool = false
    private var isRunning: Bool = false
    private var totalItems: Int = 0
    private var completedItems: Int = 0
    
    private init() {
        self.commandFilePath = defaultCommandFile
        self.isAvailable = FileManager.default.fileExists(atPath: dialogPath)
        
        if !isAvailable {
            Logger.debug("SwiftDialog not found at \(dialogPath) - running in headless mode")
        }
    }
    
    // MARK: - Public API
    
    /// Check if SwiftDialog is available
    public func isDialogAvailable() -> Bool {
        return isAvailable
    }
    
    /// Initialize and launch the dialog window
    public func initialize(
        title: String,
        message: String,
        totalPackages: Int,
        icon: String? = nil,
        blurScreen: Bool = false
    ) {
        guard isAvailable else {
            Logger.debug("Dialog not available, skipping initialization")
            return
        }
        
        // Reset state
        self.totalItems = totalPackages
        self.completedItems = 0
        
        // Clear command file
        clearCommandFile()
        
        // Build dialog arguments
        var arguments: [String] = [
            "--title", title,
            "--message", message,
            "--progress", String(totalPackages),
            "--progresstext", "Preparing...",
            "--commandfile", commandFilePath,
            "--button1text", "Please Wait",
            "--button1disabled"
        ]
        
        if let iconPath = icon {
            arguments.append(contentsOf: ["--icon", iconPath])
        } else {
            // Use SF Symbol for default icon
            arguments.append(contentsOf: ["--icon", "SF=gearshape.2.fill"])
        }
        
        if blurScreen {
            arguments.append("--blurscreen")
        }
        
        // Launch dialog process
        launchDialog(arguments: arguments)
    }
    
    /// Add a new list item with initial status
    public func addListItem(
        name: String,
        status: DialogStatus = .pending,
        statusText: String = ""
    ) {
        let command = buildListItemCommand(
            action: "add",
            title: name,
            status: status,
            statusText: statusText
        )
        writeCommand(command)
        Logger.debug("Dialog: Added list item '\(name)' with status \(status.rawValue)")
    }
    
    /// Update an existing list item's status
    public func updateListItem(
        name: String,
        status: DialogStatus,
        statusText: String = ""
    ) {
        // SwiftDialog uses simplified syntax for updates
        let statusStr = statusText.isEmpty ? status.rawValue : "\(status.rawValue), statustext: \(statusText)"
        let command = "listitem: title: \(name), status: \(statusStr)"
        writeCommand(command)
        
        // Track completion for progress
        if status == .success || status == .fail {
            completedItems += 1
            let progressPercent = totalItems > 0 ? (completedItems * 100) / totalItems : 0
            updateProgress(percent: progressPercent)
        }
    }
    
    /// Update the progress bar value (0-100)
    public func updateProgress(percent: Int) {
        writeCommand("progress: \(min(100, max(0, percent)))")
    }
    
    /// Update the progress bar text
    public func updateProgressText(text: String) {
        writeCommand("progresstext: \(text)")
    }
    
    /// Update the dialog title
    public func updateTitle(title: String) {
        writeCommand("title: \(title)")
    }
    
    /// Update the dialog message
    public func updateMessage(message: String) {
        writeCommand("message: \(message)")
    }
    
    /// Mark progress as complete
    public func complete(message: String = "Setup Complete") {
        updateProgressText(text: message)
        writeCommand("progress: complete")
        writeCommand("button1text: Done")
        writeCommand("button1: enable")
        Logger.info("Dialog: Marked as complete")
    }
    
    /// Close the dialog window
    public func close() {
        guard isRunning else { return }
        
        writeCommand("quit:")
        
        // Give dialog time to close gracefully using Thread.sleep instead of async
        Thread.sleep(forTimeInterval: 0.5)
        terminateDialog()
    }
    
    /// Force terminate the dialog (for error scenarios)
    public func terminateDialog() {
        guard isRunning, let process = dialogProcess else { return }
        
        if process.isRunning {
            process.terminate()
        }
        
        dialogProcess = nil
        isRunning = false
        Logger.debug("Dialog process terminated")
    }
    
    // MARK: - Private Methods
    
    private func launchDialog(arguments: [String]) {
        guard !isRunning else {
            Logger.warning("Dialog already running, skipping launch")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: dialogPath)
        process.arguments = arguments
        
        // Don't capture output - let it run independently
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            dialogProcess = process
            isRunning = true
            Logger.info("SwiftDialog launched successfully")
        } catch {
            Logger.error("Failed to launch SwiftDialog: \(error.localizedDescription)")
            isRunning = false
        }
    }
    
    private func writeCommand(_ command: String) {
        guard isAvailable && isRunning else { return }
        
        let commandWithNewline = command + "\n"
        
        do {
            let fileURL = URL(fileURLWithPath: commandFilePath)
            
            if FileManager.default.fileExists(atPath: commandFilePath) {
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                fileHandle.seekToEndOfFile()
                if let data = commandWithNewline.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try commandWithNewline.write(toFile: commandFilePath, atomically: true, encoding: .utf8)
            }
        } catch {
            Logger.debug("Failed to write dialog command: \(error.localizedDescription)")
        }
    }
    
    private func clearCommandFile() {
        do {
            try "".write(toFile: commandFilePath, atomically: true, encoding: .utf8)
        } catch {
            Logger.debug("Failed to clear command file: \(error.localizedDescription)")
        }
    }
    
    private func buildListItemCommand(
        action: String,
        title: String,
        status: DialogStatus,
        statusText: String
    ) -> String {
        var command = "listitem: \(action), title: \(title), status: \(status.rawValue)"
        if !statusText.isEmpty {
            command += ", statustext: \(statusText)"
        }
        return command
    }
}

// MARK: - Dialog Status Enum

public enum DialogStatus: String {
    case none = "none"
    case pending = "pending"
    case wait = "wait"
    case success = "success"
    case fail = "fail"
    case error = "error"
    case progress = "progress"
}

// MARK: - Convenience Extension for Package Processing

public extension DialogManager {
    
    /// Helper for package download phase
    func notifyDownloadStarted(packageName: String) {
        updateListItem(name: packageName, status: .wait, statusText: "Downloading...")
        updateProgressText(text: "Downloading \(packageName)...")
    }
    
    /// Helper for package installation phase
    func notifyInstallStarted(packageName: String) {
        updateListItem(name: packageName, status: .wait, statusText: "Installing...")
        updateProgressText(text: "Installing \(packageName)...")
    }
    
    /// Helper for package success
    func notifyPackageSuccess(packageName: String) {
        updateListItem(name: packageName, status: .success, statusText: "Installed")
    }
    
    /// Helper for package failure
    func notifyPackageFailure(packageName: String, error: String) {
        updateListItem(name: packageName, status: .fail, statusText: error)
    }
    
    /// Helper for package skipped
    func notifyPackageSkipped(packageName: String, reason: String = "Already installed") {
        updateListItem(name: packageName, status: .success, statusText: reason)
    }
    
    /// Helper for phase transition
    func notifyPhaseStarted(phase: String) {
        updateProgressText(text: "Phase: \(phase)")
        Logger.writeSection("Processing \(phase) packages")
    }
}
