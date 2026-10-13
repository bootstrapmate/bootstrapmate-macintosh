//
//  SettingsView.swift
//  BootstrapMate
//
//  Main tab with centered app info header and settings below. Settings a
//  profile manages are disabled (gray); one banner under the header explains
//  why, instead of a caption on every field. Only MDM changes those, so the
//  window offers nothing for them. Every other setting is editable, and Save
//  asks for an administrator before the helper writes it. When a profile
//  manages every setting the window is simply read-only, with no Save.
//

import SwiftUI
import BootstrapMateCore

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(XPCClient.self) private var xpcClient
    @State private var showManifestPreview = false

    /// Bound to the first text field so the window opens with nothing
    /// focused instead of AppKit picking the first control and drawing a ring.
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case jsonUrl
    }

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                appInfoHeader

                if viewModel.hasManagedSettings {
                    ProfileManagedBanner()
                }

                Divider()

                // Two even columns, the same split on every row.
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 16) {
                    GridRow {
                        connectionSection
                            .frame(maxWidth: .infinity, alignment: .top)
                        behaviorSection
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                    GridRow {
                        dialogSection
                            .frame(maxWidth: .infinity, alignment: .top)
                        advancedSection
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }

                ServicesSection(
                    prefixes: ["com.github.bootstrapmate"],
                    extraDaemonDirectories: [
                        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons").path
                    ]
                )

                saveBar
                    .padding(.top, 4)
            }
            .padding()
        }
        .defaultFocus($focusedField, nil)
        .onAppear {
            viewModel.configure(client: xpcClient)
            viewModel.load()
            DispatchQueue.main.async { focusedField = nil }
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

            Text("Managed Bootstrap Install")
                .font(.largeTitle.bold())

            Text("Enterprise management tools provisioning for automated device setup using manifests.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

        }
        .padding(.top, 8)
    }

    // MARK: - Save

    @ViewBuilder
    private var saveBar: some View {
        HStack(spacing: 12) {
            Text("v\(marketingVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Link("Documentation", destination: URL(string: "https://github.com/bootstrapmate/bootstrapmate-macintosh/wiki")!)
                .font(.caption)
            Link("Report Issue", destination: URL(string: "https://github.com/bootstrapmate/bootstrapmate-macintosh/issues")!)
                .font(.caption)

            Spacer()
            saveStatusLabel
            if !viewModel.allSettingsManaged {
                Button("Revert") {
                    viewModel.revert()
                }
                .disabled(!viewModel.hasUnsavedChanges || viewModel.saveStatus == .saving)
                .help("Discard your changes and show the saved settings")

                Button("Save") {
                    Task { await viewModel.save() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasUnsavedChanges || viewModel.saveStatus == .saving)
                .help("An administrator name and password is needed to save")
            }
        }
    }

    // MARK: - Save Status

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
                            .focused($focusedField, equals: .jsonUrl)
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
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            switch viewModel.authorizationHeaderState {
                            case .managed:
                                Text("Set by profile")
                                Label("Managed", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .set:
                                Text("Set")
                            case .notSet:
                                Text("Not set")
                            }
                        }
                        Text("Set with the headers key in a configuration profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                settingRow("followRedirects") {
                    Toggle("Follow HTTP redirects", isOn: $viewModel.followRedirects)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Toggle("Download and verify only; install and run nothing", isOn: $viewModel.dryRun)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Dialog", systemImage: "text.bubble")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("retainCache") {
                    Toggle("Keep downloaded payloads after a successful run", isOn: $viewModel.retainCache)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        let managed = viewModel.isManaged(key)
        VStack(alignment: .leading, spacing: 2) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
                .disabled(managed)
        }
    }
}
