//
//  AppSettingsView.swift
//  Mobile Terminal
//
//  Global app settings view
//

import SwiftUI

struct AppSettingsView: View {
    @StateObject private var sessionManager = TerminalSessionManager.shared
    @StateObject private var biometricService = BiometricService.shared
    @StateObject private var notificationService = NotificationService.shared

    @AppStorage("app_requireBiometricsForAll") private var requireBiometricsForAll = false
    @AppStorage("app_hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        List {
            // MARK: - Display Settings
            Section("Display") {
                HStack {
                    Text("Default Font Size")
                    Spacer()
                    HStack(spacing: 16) {
                        Button {
                            sessionManager.decreaseFontSize()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)

                        Text("\(sessionManager.fontSize)px")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50)

                        Button {
                            sessionManager.increaseFontSize()
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.blue)
                }

                Button("Reset to Default (22px)") {
                    sessionManager.resetFontSize()
                }
            }

            // MARK: - Interaction Settings
            Section("Interaction") {
                Toggle("Haptic Feedback", isOn: $sessionManager.hapticsEnabled)

                Toggle("Auto-Reconnect", isOn: $sessionManager.autoReconnect)
            }

            // MARK: - Security
            if biometricService.isAvailable {
                Section("Security") {
                    HStack {
                        Label(biometricService.biometricType.displayName, systemImage: biometricService.biometricType.iconName)
                        Spacer()
                        Text("Available")
                            .foregroundStyle(.green)
                    }

                    Toggle("Require for All Servers", isOn: $requireBiometricsForAll)

                    if requireBiometricsForAll {
                        Text("All server connections will require \(biometricService.biometricType.displayName) authentication")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Notifications
            Section("Notifications") {
                HStack {
                    Text("Status")
                    Spacer()
                    if notificationService.isAuthorized {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Enable") {
                            Task {
                                await notificationService.requestPermission()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if notificationService.isAuthorized {
                    Text("Get notified when long-running commands complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Siri Shortcuts
            #if os(iOS)
            Section("Siri Shortcuts") {
                NavigationLink {
                    SiriShortcutsSettingsView()
                } label: {
                    Label("Manage Shortcuts", systemImage: "mic.circle")
                }

                Text("Use Siri to connect to servers or run commands")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            // MARK: - SSH Keys
            Section("SSH Keys") {
                NavigationLink {
                    SSHKeyManagerView()
                } label: {
                    Label("Manage SSH Keys", systemImage: "key.fill")
                }

                Text("Import and manage SSH keys for server authentication")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Terminal Settings
            Section("Terminal") {
                NavigationLink {
                    TerminalSettingsView()
                } label: {
                    Label("Terminal Settings", systemImage: "terminal")
                }
            }

            // MARK: - Data
            Section("Data") {
                Button("Reset Onboarding") {
                    hasCompletedOnboarding = false
                }
                .foregroundStyle(.orange)

                Button(role: .destructive) {
                    // This would need confirmation
                } label: {
                    Text("Delete All Servers")
                }
            }

            // MARK: - About
            Section("About") {
                LabeledContent("App", value: "Mobile Terminal")
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Platform", value: "iOS 17+")

                Link(destination: URL(string: "https://github.com")!) {
                    HStack {
                        Text("Source Code")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        AppSettingsView()
    }
}
