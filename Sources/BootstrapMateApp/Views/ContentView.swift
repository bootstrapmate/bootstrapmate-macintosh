//
//  ContentView.swift
//  BootstrapMate
//
//  Main window with three tabs: Prefs, Run, and Logs.
//  Uses standard TabView which renders as Liquid Glass on macOS 26+.
//

import SwiftUI
import BootstrapMateCore

struct ContentView: View {
    @Environment(XPCClient.self) private var xpcClient
    @State private var viewModel = SettingsViewModel()
    @State private var selectedTab: ContentTab = .prefs

    enum ContentTab: Hashable {
        case prefs, run, logs
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SettingsView(viewModel: viewModel)
                .environment(xpcClient)
                .tabItem { Text("Prefs") }
                .tag(ContentTab.prefs)

            RunView(viewModel: viewModel)
                .environment(xpcClient)
                .tabItem { Text("Run") }
                .tag(ContentTab.run)

            LogView()
                .tabItem { Text("Logs") }
                .tag(ContentTab.logs)
        }
        .onAppear {
            xpcClient.checkHelperStatus()
            xpcClient.connect()
        }
    }
}
