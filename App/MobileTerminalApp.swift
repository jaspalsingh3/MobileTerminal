//
//  MobileTerminalApp.swift
//  Mobile Terminal
//
//  Professional iOS terminal app for connecting to remote servers
//  Tagline: "Use CLI on your Phone"
//

import SwiftUI

@main
struct MobileTerminalApp: App {
    @StateObject private var serverManager = ServerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
        }
    }
}
