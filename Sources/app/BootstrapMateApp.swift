//
//  BootstrapMateApp.swift
//  BootstrapMate
//
//  SwiftUI GUI for configuring BootstrapMate settings and running
//  the bootstrap process with real-time output.
//

import SwiftUI
import BootstrapMateCore

@main
struct BootstrapMateApp: App {
    @State private var xpcClient = XPCClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(xpcClient)
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 850, height: 748)
    }
}
