//
//  SSHTerminalView.swift
//  Mobile Terminal
//
//  Native terminal view for SSH connections with SwiftTerm for rich TUI support
//

import SwiftUI
import SwiftTerm
import UIKit

struct SSHTerminalView: View {
    let server: ServerConnection

    @StateObject private var sessionManager = TerminalSessionManager.shared
    @StateObject private var voiceService = VoiceCommandService()
    @StateObject private var historyManager = CommandHistoryManager.shared

    @State private var showingSettings = false
    @State private var showingPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var keepScreenAwake = true

    @Environment(\.dismiss) private var dismiss
    
    private var sshClient: SSHClient {
        sessionManager.prepareSession(for: server)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal display - SwiftTerm (renders full ANSI escape codes)
            GeometryReader { geometry in
                SwiftTermView(
                    sshClient: sshClient,
                    fontSize: sessionManager.fontSize
                )
                .id("terminal-\(server.id)") // Ensure fresh view identity for new servers
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(SwiftUI.Color.black)
            .clipped()

            // Quick action toolbar (still needed for mobile-friendly controls)
            SSHToolbar(
                onSendCommand: sendCommand,
                onSendControlKey: sendControlKey,
                sessionManager: sessionManager,
                voiceService: voiceService
            )
        }
        .background(SwiftUI.Color.black)
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Keep screen awake toggle
                    Button {
                        keepScreenAwake.toggle()
                        HapticManager.shared.lightTap()
                    } label: {
                        Image(systemName: keepScreenAwake ? "sun.max.fill" : "sun.max")
                            .foregroundStyle(keepScreenAwake ? .yellow : .secondary)
                    }

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }

                    Button {
                        reconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusShortText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                TerminalSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .alert("Enter Password", isPresented: $showingPasswordPrompt) {
            SecureField("Password", text: $passwordInput)
            Button("Connect") {
                connectWithPassword()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Enter password for \(server.name)")
        }
        .onAppear {
            if !sessionManager.isConnected {
                connectToServer()
            }
            // Keep screen awake to maintain SSH session
            if keepScreenAwake {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        .onDisappear {
            // Remove hard disconnect to allow background persistence
            // sessionTask stays alive in the background
            
            // Re-enable screen sleep
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: keepScreenAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }

    // MARK: - Status

    private var statusColor: SwiftUI.Color {
        switch sshClient.connectionState {
        case .disconnected: return .gray
        case .connecting, .authenticating: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private var statusShortText: String {
        switch sshClient.connectionState {
        case .disconnected: return "Offline"
        case .connecting: return "..."
        case .authenticating: return "Auth"
        case .connected: return "Live"
        case .error: return "Error"
        }
    }

    // MARK: - Actions

    private func connectToServer() {
        // Check if we need a password
        if case .basicAuth = server.authMethod {
            if CredentialManager.shared.getPassword(for: server.id) == nil {
                showingPasswordPrompt = true
                return
            }
        }

        sshClient.connectWithServer(server)
    }

    private func connectWithPassword() {
        CredentialManager.shared.savePassword(passwordInput, for: server.id)
        passwordInput = ""
        sshClient.connectWithServer(server)
    }

    private func reconnect() {
        sshClient.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            connectToServer()
        }
    }

    private func sendCommand(_ command: String) {
        guard !command.isEmpty else { return }
        historyManager.addCommand(command)
        sshClient.send(command)
        HapticManager.shared.mediumImpact()
    }

    private func sendControlKey(_ key: TerminalToolbar.ControlKey) {
        let sequence: String
        switch key {
        case .ctrlC:
            sequence = "\u{03}"
        case .ctrlD:
            sequence = "\u{04}"
        case .ctrlZ:
            sequence = "\u{1A}"
        case .ctrlL:
            sshClient.clearOutput()
            return
        case .ctrlU:
            sequence = "\u{15}"
        case .ctrlW:
            sequence = "\u{17}"
        case .escape:
            sequence = "\u{1B}"
        case .tab:
            sequence = "\t"
        case .shiftTab:
            sequence = "\u{1B}[Z"
        case .backspace:
            sequence = "\u{7F}"
        case .upArrow:
            sequence = "\u{1B}[A"
        case .downArrow:
            sequence = "\u{1B}[B"
        case .leftArrow:
            sequence = "\u{1B}[D"
        case .rightArrow:
            sequence = "\u{1B}[C"
        case .enter:
            sequence = "\r"
        }
        sshClient.sendControlSequence(sequence)
    }
}

// MARK: - SSH Toolbar

struct SSHToolbar: View {
    let onSendCommand: (String) -> Void
    let onSendControlKey: (TerminalToolbar.ControlKey) -> Void

    @ObservedObject var sessionManager: TerminalSessionManager
    @ObservedObject var voiceService: VoiceCommandService

    @State private var showingVoiceInput = false
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // Voice input overlay
            if showingVoiceInput {
                voiceInputOverlay
            }

            // Main toolbar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Font controls
                    fontControlGroup

                    Divider()
                        .frame(height: 30)

                    // Quick actions (Esc, ^C, ^D, Clear, Tab, ^Z)
                    quickActionGroup

                    Divider()
                        .frame(height: 30)

                    // Navigation (Arrow keys - critical for Claude menu)
                    navigationGroup

                    Divider()
                        .frame(height: 30)

                    // Editing (backspace, delete word, delete line)
                    editingGroup

                    Divider()
                        .frame(height: 30)

                    // Utilities (Voice, History, Enter)
                    utilityGroup
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(SwiftUI.Color(UIColor.systemBackground).opacity(0.95))
        }
    }

    // MARK: - Font Controls

    private var fontControlGroup: some View {
        HStack(spacing: 8) {
            ToolbarButton(
                icon: "textformat.size.smaller",
                label: "A-"
            ) {
                sessionManager.decreaseFontSize()
            }

            Text("\(sessionManager.fontSize)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            ToolbarButton(
                icon: "textformat.size.larger",
                label: "A+"
            ) {
                sessionManager.increaseFontSize()
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionGroup: some View {
        HStack(spacing: 8) {
            // Escape key - essential for vim, nano, exiting prompts
            ToolbarButton(
                icon: "escape",
                label: "Esc",
                tint: .blue
            ) {
                onSendControlKey(.escape)
                HapticManager.shared.lightTap()
            }

            // Ctrl+C - Cancel/Interrupt (exit Claude sessions, cancel commands)
            ToolbarButton(
                icon: "xmark.circle.fill",
                label: "^C",
                tint: .red
            ) {
                onSendControlKey(.ctrlC)
                HapticManager.shared.mediumImpact()
            }

            // Ctrl+D - EOF (exit shells, end input)
            ToolbarButton(
                icon: "rectangle.portrait.and.arrow.right",
                label: "^D",
                tint: .orange
            ) {
                onSendControlKey(.ctrlD)
                HapticManager.shared.lightTap()
            }

            ToolbarButton(
                icon: "trash",
                label: "Clear"
            ) {
                onSendControlKey(.ctrlL)
            }

            ToolbarButton(
                icon: "arrow.right.to.line",
                label: "Tab"
            ) {
                onSendControlKey(.tab)
            }

            ToolbarButton(
                icon: "arrow.left.to.line",
                label: "S-Tab"
            ) {
                onSendControlKey(.shiftTab)
            }

            ToolbarButton(
                icon: "pause.circle",
                label: "^Z",
                tint: .orange
            ) {
                onSendControlKey(.ctrlZ)
            }
        }
    }

    // MARK: - Navigation (Arrow Keys)

    private var navigationGroup: some View {
        HStack(spacing: 8) {
            // Up arrow - for scrolling up in Claude plan mode, command history
            RepeatableToolbarButton(
                icon: "chevron.up",
                label: "↑",
                tint: .cyan,
                repeatInterval: 0.15,
                initialDelay: 0.4
            ) {
                onSendControlKey(.upArrow)
            }

            // Down arrow - for scrolling down in Claude plan mode
            RepeatableToolbarButton(
                icon: "chevron.down",
                label: "↓",
                tint: .cyan,
                repeatInterval: 0.15,
                initialDelay: 0.4
            ) {
                onSendControlKey(.downArrow)
            }

            // Left arrow - move cursor left
            ToolbarButton(
                icon: "chevron.left",
                label: "←",
                tint: .cyan
            ) {
                onSendControlKey(.leftArrow)
            }

            // Right arrow - move cursor right
            ToolbarButton(
                icon: "chevron.right",
                label: "→",
                tint: .cyan
            ) {
                onSendControlKey(.rightArrow)
            }
        }
    }

    // MARK: - Editing Actions

    private var editingGroup: some View {
        HStack(spacing: 8) {
            // Repeatable backspace - holds to keep deleting
            RepeatableToolbarButton(
                icon: "delete.left",
                label: "Del",
                repeatInterval: 0.05  // Fast repeat
            ) {
                onSendControlKey(.backspace)
            }

            // Delete word (Ctrl+W)
            ToolbarButton(
                icon: "text.badge.minus",
                label: "DelW"
            ) {
                onSendControlKey(.ctrlW)
            }

            // Delete entire line (Ctrl+U)
            ToolbarButton(
                icon: "trash.slash",
                label: "DelLn",
                tint: .orange
            ) {
                onSendControlKey(.ctrlU)
            }
        }
    }

    // MARK: - Utilities

    private var utilityGroup: some View {
        HStack(spacing: 8) {
            ToolbarButton(
                icon: voiceService.isListening ? "mic.fill" : "mic",
                label: "Voice",
                tint: voiceService.isListening ? .red : .blue
            ) {
                withAnimation {
                    showingVoiceInput.toggle()
                    if showingVoiceInput {
                        voiceService.startListening()
                    } else {
                        voiceService.stopListening()
                    }
                }
            }

            ToolbarButton(
                icon: "clock.arrow.circlepath",
                label: "History"
            ) {
                showingHistory = true
            }

            // Enter button - critical for confirming selections in Claude
            ToolbarButton(
                icon: "return",
                label: "Enter",
                tint: .green
            ) {
                onSendControlKey(.enter)
                HapticManager.shared.mediumImpact()
            }
        }
        .sheet(isPresented: $showingHistory) {
            CommandHistoryView { command in
                onSendCommand(command)
                showingHistory = false
            }
        }
    }

    // MARK: - Voice Input Overlay

    private var voiceInputOverlay: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Voice Input")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    voiceService.stopListening()
                    voiceService.clearTranscription()
                    showingVoiceInput = false
                }
                .foregroundStyle(.red)
            }

            Text(voiceService.transcribedText.isEmpty ? "Listening..." : voiceService.transcribedText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(voiceService.transcribedText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(SwiftUI.Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)

            HStack(spacing: 16) {
                Button {
                    voiceService.clearTranscription()
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(.bordered)

                Button {
                    if voiceService.isListening {
                        voiceService.stopListening()
                    } else {
                        voiceService.startListening()
                    }
                } label: {
                    Label(
                        voiceService.isListening ? "Stop" : "Listen",
                        systemImage: voiceService.isListening ? "stop.fill" : "mic.fill"
                    )
                }
                .buttonStyle(.bordered)
                .tint(voiceService.isListening ? .red : .blue)

                Button {
                    let text = voiceService.transcribedText
                    voiceService.stopListening()
                    voiceService.clearTranscription()
                    showingVoiceInput = false
                    if !text.isEmpty {
                        onSendCommand(text)
                        HapticManager.shared.mediumImpact()
                    }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(voiceService.transcribedText.isEmpty)
            }

            if let error = voiceService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(SwiftUI.Color(UIColor.systemBackground))
    }
}

#Preview {
    NavigationStack {
        SSHTerminalView(server: .sampleSSH)
    }
}
