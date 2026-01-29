//
//  TerminalSettingsView.swift
//  Mobile Terminal
//
//  Settings view for terminal configuration
//

import SwiftUI

struct TerminalSettingsView: View {
    @StateObject private var sessionManager = TerminalSessionManager.shared
    @StateObject private var notificationService = NotificationService.shared

    @State private var showingShortcuts = false

    var body: some View {
        List {
            // MARK: - Display Settings
            Section("Display") {
                HStack {
                    Text("Font Size")
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
                    Text("You'll be notified when long-running commands complete while the app is in the background.")
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

                Text("Use Siri to open the terminal or run commands hands-free.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            // MARK: - Gestures Reference
            Section("Gestures") {
                GestureRow(gesture: "Swipe Up", action: "Previous command (↑)")
                GestureRow(gesture: "Swipe Down", action: "Next command (↓)")
                GestureRow(gesture: "2-Finger Swipe Left", action: "Cancel (Ctrl+C)")
                GestureRow(gesture: "Pinch", action: "Zoom font size")
                GestureRow(gesture: "Long Press", action: "Copy selected text")
            }

            // MARK: - Keyboard Shortcuts
            Section("Toolbar Quick Actions") {
                ToolbarRow(icon: "trash", name: "Clear", action: "clear")
                ToolbarRow(icon: "arrow.right.to.line", name: "Tab", action: "Tab key")
                ToolbarRow(icon: "xmark.circle", name: "^C", action: "Cancel/Interrupt")
                ToolbarRow(icon: "pause.circle", name: "^Z", action: "Suspend process")
                ToolbarRow(icon: "chevron.up", name: "Up", action: "Previous command")
                ToolbarRow(icon: "chevron.down", name: "Down", action: "Next command")
                ToolbarRow(icon: "sparkles", name: "Claude", action: "Start Claude Code")
                ToolbarRow(icon: "mic", name: "Voice", action: "Voice input")
                ToolbarRow(icon: "clock.arrow.circlepath", name: "History", action: "Command history")
                ToolbarRow(icon: "square.and.arrow.up", name: "Share", action: "Screenshot & share")
            }

            // MARK: - About
            Section("About") {
                HStack {
                    Text("Session Persistence")
                    Spacer()
                    Text("tmux")
                        .foregroundStyle(.secondary)
                }

                Text("Your terminal session persists across app restarts. Disconnect and reconnect without losing your work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Terminal Settings")
    }
}

struct GestureRow: View {
    let gesture: String
    let action: String

    var body: some View {
        HStack {
            Text(gesture)
                .fontWeight(.medium)
            Spacer()
            Text(action)
                .foregroundStyle(.secondary)
        }
    }
}

struct ToolbarRow: View {
    let icon: String
    let name: String
    let action: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            Text(name)
                .fontWeight(.medium)
            Spacer()
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        TerminalSettingsView()
    }
}
