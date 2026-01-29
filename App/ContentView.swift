//
//  ContentView.swift
//  Mobile Terminal
//
//  Main content view with server list as the primary screen
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverManager: ServerManager

    @AppStorage("app_hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding || !serverManager.servers.isEmpty {
                mainContent
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
    }

    private var mainContent: some View {
        TabView {
            // Servers Tab (Main)
            ServerListView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }

            // Settings Tab
            NavigationStack {
                AppSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerManager.shared)
}
