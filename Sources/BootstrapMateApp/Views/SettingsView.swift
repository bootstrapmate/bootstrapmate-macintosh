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
    @State private var showManifestPreview = false

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

                // Settings in 2x2 grid
                HStack(alignment: .top, spacing: 20) {
                    connectionSection
                    behaviorSection
                }

                HStack(alignment: .top, spacing: 20) {
                    dialogSection
                    advancedSection
                }

                // Auto-save status
                HStack {
                    Spacer()
                    saveStatusLabel
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear {
            viewModel.configure(client: xpcClient)
            viewModel.load()
        }
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

            Text("Enterprise management tools provisioning for automated device setup using manifests.")
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

    // MARK: - Auto-Save Status

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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("jsonUrl", label: "Manifest URL") {
                    HStack(spacing: 6) {
                        TextField("https://example.com/manifest.json", text: $viewModel.jsonUrl)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            viewModel.fetchManifestPreview()
                            showManifestPreview = true
                        } label: {
                            Image(systemName: "eye")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.jsonUrl.isEmpty)
                        .help("Preview manifest content")
                        .popover(isPresented: $showManifestPreview, arrowEdge: .trailing) {
                            ManifestPreviewPopover(viewModel: viewModel)
                                .onDisappear { viewModel.resetManifestPreview() }
                        }
                    }
                }

                settingRow("authorizationHeader", label: "Authorization Header") {
                    SecureField(
                        viewModel.hasExistingAuth ? "Token saved — enter new to replace" : "Bearer token or Basic auth",
                        text: $viewModel.authorizationHeader
                    )
                    .textFieldStyle(.roundedBorder)
                }

                settingRow("followRedirects") {
                    Toggle("Follow HTTP redirects", isOn: $viewModel.followRedirects)
                }
            }
            .padding(.vertical, 8)
        } label: {
            Label("Connection", systemImage: "network")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var behaviorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("reboot") {
                    Toggle("Reboot after completion", isOn: $viewModel.reboot)
                }

                settingRow("silentMode") {
                    Toggle("Suppress console output", isOn: $viewModel.silentMode)
                }

                settingRow("verboseMode") {
                    Toggle("Enable verbose logging", isOn: $viewModel.verboseMode)
                }

                settingRow("dryRun") {
                    Toggle("No installer actions performed", isOn: $viewModel.dryRun)
                }

                settingRow("userscriptOnly") {
                    Toggle("Only run userland scripts", isOn: $viewModel.userscriptOnly)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Behavior", systemImage: "gearshape")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var dialogSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("enableDialog") {
                    Toggle("Show SwiftDialog UI during run", isOn: $viewModel.enableDialog)
                }

                settingRow("dialogTitle", label: "Title") {
                    TextField("Setting up your Mac", text: $viewModel.dialogTitle)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("dialogMessage", label: "Message") {
                    TextField("Please wait while we configure your device...", text: $viewModel.dialogMessage)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("dialogIcon", label: "Icon") {
                    TextField("SF Symbol name (e.g. gearshape.2.fill)", text: $viewModel.dialogIcon)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("blurScreen") {
                    Toggle("Blur screen behind dialog", isOn: $viewModel.blurScreen)
                }
            }
            .padding(.vertical, 8)
        } label: {
            Label("Dialog", systemImage: "text.bubble")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("customInstallPath", label: "Install Path") {
                    TextField("/Library/Managed Bootstrap", text: $viewModel.customInstallPath)
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
                    HStack {
                        TextField("", value: $viewModel.networkTimeout, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Stepper("", value: $viewModel.networkTimeout, in: 10...600, step: 10)
                            .labelsHidden()
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        } label: {
            Label("Advanced", systemImage: "wrench.and.screwdriver")
                .font(.headline)
        }
    }

    // MARK: - Manifest Preview Popover

    private struct ManifestPreviewPopover: View {
        let viewModel: SettingsViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Manifest Preview", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Spacer()
                }
                .padding()

                Divider()

                Group {
                    switch viewModel.manifestPreviewState {
                    case .idle:
                        Text("Tap the button to load the manifest.")
                            .foregroundStyle(.secondary)
                            .padding(40)
                    case .loading:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fetching manifest\u{2026}")
                                .foregroundStyle(.secondary)
                        }
                        .padding(40)
                    case .loaded(let content):
                        TextEditor(text: .constant(content))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 720, height: 520)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(40)
                    }
                }
            }
            .frame(minWidth: 720)
        }
    }

    // MARK: - Managed Setting Row

    @ViewBuilder
    private func settingRow<Content: View>(
        _ key: String,
        label: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let managed = viewModel.isMDMManaged(key)
        VStack(alignment: .leading, spacing: 2) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
