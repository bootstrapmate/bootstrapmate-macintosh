//
//  SettingsView.swift
//  BootstrapMate
//
//  Main tab with centered app info header and settings below.
//  MDM-managed settings display a lock icon and are disabled.
//

import SwiftUI
import BootstrapMateCore

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(XPCClient.self) private var xpcClient

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App info header
                appInfoHeader

                Divider()

                // Settings in 2 columns
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 12) {
                        connectionSection
                        dialogSection
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 12) {
                        behaviorSection
                        advancedSection
                    }
                    .frame(maxWidth: .infinity)
                }

                // Save row
                HStack {
                    Spacer()
                    saveStatusLabel
                    saveButton
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - App Info Header

    @ViewBuilder
    private var appInfoHeader: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)

            Text("BootstrapMate")
                .font(.largeTitle.bold())

            Text("macOS provisioning tool for automated device setup using JSON manifests.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Documentation", destination: URL(string: "https://github.com/bootstrapmate/bootstrapmate-macintosh/wiki")!)
                    .font(.caption)
                Link("Report Issue", destination: URL(string: "https://github.com/bootstrapmate/bootstrapmate-macintosh/issues")!)
                    .font(.caption)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        if #available(macOS 26, *) {
            Button("Save Settings") {
                viewModel.save(using: xpcClient)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .disabled(xpcClient.isRunning)
        } else {
            Button("Save Settings") {
                viewModel.save(using: xpcClient)
            }
            .buttonStyle(.borderedProminent)
            .disabled(xpcClient.isRunning)
        }
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        switch viewModel.saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
                .controlSize(.small)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
                .transition(.opacity)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var connectionSection: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("jsonUrl", label: "Manifest URL") {
                    TextField("https://example.com/manifest.json", text: $viewModel.jsonUrl)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("authorizationHeader", label: "Authorization Header") {
                    SecureField(
                        viewModel.hasExistingAuth ? "Token saved — enter new to replace" : "Bearer token or Basic auth",
                        text: $viewModel.authorizationHeader
                    )
                    .textFieldStyle(.roundedBorder)
                }

                settingRow("followRedirects", label: "Follow Redirects") {
                    Toggle("Follow HTTP redirects", isOn: $viewModel.followRedirects)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var behaviorSection: some View {
        GroupBox("Behavior") {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("reboot", label: "Reboot") {
                    Toggle("Reboot after completion", isOn: $viewModel.reboot)
                }

                settingRow("silentMode", label: "Silent Mode") {
                    Toggle("Suppress console output", isOn: $viewModel.silentMode)
                }

                settingRow("verboseMode", label: "Verbose Mode") {
                    Toggle("Enable verbose logging", isOn: $viewModel.verboseMode)
                }

                settingRow("dryRun", label: "Dry Run") {
                    Toggle("No installer actions performed", isOn: $viewModel.dryRun)
                }

                settingRow("userscriptOnly", label: "Userscript Only") {
                    Toggle("Only run userland scripts", isOn: $viewModel.userscriptOnly)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var dialogSection: some View {
        GroupBox("Dialog") {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("enableDialog", label: "Enable Dialog") {
                    Toggle("Show SwiftDialog UI during run", isOn: $viewModel.enableDialog)
                }

                settingRow("dialogTitle", label: "Dialog Title") {
                    TextField("Setting up your Mac", text: $viewModel.dialogTitle)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("dialogMessage", label: "Dialog Message") {
                    TextField("Please wait while we configure your device...", text: $viewModel.dialogMessage)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("dialogIcon", label: "Dialog Icon") {
                    TextField("SF Symbol name (e.g. gearshape.2.fill)", text: $viewModel.dialogIcon)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("blurScreen", label: "Blur Screen") {
                    Toggle("Blur screen behind dialog", isOn: $viewModel.blurScreen)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        GroupBox("Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("customInstallPath", label: "Install Path") {
                    TextField("/Library/Application Support/BootstrapMate", text: $viewModel.customInstallPath)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("daemonIdentifier", label: "Daemon Identifier") {
                    TextField("com.github.bootstrapmate", text: $viewModel.daemonIdentifier)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("agentIdentifier", label: "Agent Identifier") {
                    TextField("com.github.bootstrapmate", text: $viewModel.agentIdentifier)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("networkTimeout", label: "Network Timeout") {
                    Stepper(value: $viewModel.networkTimeout, in: 10...600, step: 10) {
                        Text("\(viewModel.networkTimeout) seconds")
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Managed Setting Row

    @ViewBuilder
    private func settingRow<Content: View>(
        _ key: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let managed = viewModel.isMDMManaged(key)
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .disabled(managed)
            if managed {
                Label("Managed by MDM", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
