//
//  RunView.swift
//  BootstrapMate
//
//  Dedicated tab for running the bootstrap process.
//  Shows run/stop controls and real-time console output.
//

import SwiftUI
import BootstrapMateCore

struct RunView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(XPCClient.self) private var xpcClient
    @State private var showDebug = true

    var body: some View {
        let lines = showDebug ? xpcClient.outputLines : xpcClient.outputLines.filter { $0.level != .debug }
        VStack(spacing: 0) {
            runControlBar
                .padding()

            Divider()

            ConsoleView(outputLines: lines)
                .padding()
        }
    }

    // MARK: - Run Control Bar

    @ViewBuilder
    private var runControlBar: some View {
        HStack(spacing: 12) {
            if xpcClient.isRunning {
                stopButton
            } else {
                runButton
            }

            if xpcClient.isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("Running...")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusIndicator

            Toggle("Debug", isOn: $showDebug)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Show or hide [DEBUG] log lines")

            if !xpcClient.outputLines.isEmpty {
                clearButton
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var runButton: some View {
        if #available(macOS 26, *) {
            Button {
                startRun()
            } label: {
                Label("Run BootstrapMate", systemImage: "play.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(xpcClient.helperStatus != .registered)
        } else {
            Button {
                startRun()
            } label: {
                Label("Run BootstrapMate", systemImage: "play.fill")
            }
            .controlSize(.large)
            .disabled(xpcClient.helperStatus != .registered)
        }
    }

    @ViewBuilder
    private var stopButton: some View {
        if #available(macOS 26, *) {
            Button(role: .destructive) {
                xpcClient.stopBootstrap()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
        } else {
            Button(role: .destructive) {
                xpcClient.stopBootstrap()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var clearButton: some View {
        if #available(macOS 26, *) {
            Button("Clear") {
                clearOutput()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        } else {
            Button("Clear") {
                clearOutput()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Actions

    private func startRun() {
        viewModel.save(using: xpcClient)
        let arguments = viewModel.buildRunArguments()
        xpcClient.runBootstrap(additionalArguments: arguments)
    }

    private func clearOutput() {
        xpcClient.outputLines.removeAll()
        xpcClient.lastExitCode = nil
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if let exitCode = xpcClient.lastExitCode {
            if exitCode == 0 {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Failed (exit \(exitCode))", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } else if xpcClient.isRunning {
            Label("Running", systemImage: "circle.dotted.circle")
                .foregroundStyle(.blue)
        }

        if xpcClient.helperStatus != .registered && !xpcClient.isRunning {
            Label("Helper not available", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }
}
