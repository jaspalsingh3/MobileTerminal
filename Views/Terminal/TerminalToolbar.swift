//
//  TerminalToolbar.swift
//  Mobile Terminal
//
//  Quick action toolbar for terminal interactions
//

import SwiftUI

struct TerminalToolbar: View {
    let onSendCommand: (String) -> Void
    let onSendControlKey: (ControlKey) -> Void
    let onTakeScreenshot: () -> Void

    @ObservedObject var sessionManager: TerminalSessionManager
    @ObservedObject var voiceService: VoiceCommandService

    @State private var showingVoiceInput = false
    @State private var showingHistory = false

    enum ControlKey: String {
        case escape = "\u{1B}"  // ESC - Escape key
        case ctrlC = "\u{03}"  // ETX - Cancel/Interrupt (exit Claude, cancel commands)
        case ctrlZ = "\u{1A}"  // SUB - Suspend
        case ctrlD = "\u{04}"  // EOT - EOF (exit shells, end input)
        case ctrlL = "\u{0C}"  // FF - Clear screen
        case ctrlU = "\u{15}"  // NAK - Kill line (delete to start)
        case ctrlW = "\u{17}"  // ETB - Delete word
        case tab = "\t"
        case shiftTab = "\u{1B}[Z"  // Reverse tab / Shift+Tab
        case backspace = "\u{7F}"  // DEL - Backspace
        case upArrow = "\u{1B}[A"
        case downArrow = "\u{1B}[B"
        case leftArrow = "\u{1B}[D"
        case rightArrow = "\u{1B}[C"
        case enter = "\r"
    }

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

                    // Quick actions
                    quickActionGroup

                    Divider()
                        .frame(height: 30)

                    // Editing (backspace, delete word, delete line)
                    editingGroup

                    Divider()
                        .frame(height: 30)

                    // Navigation
                    navigationGroup

                    Divider()
                        .frame(height: 30)

                    // Utilities
                    utilityGroup
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(UIColor.systemBackground).opacity(0.95))
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
                onSendCommand("clear")
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

    // MARK: - Navigation (Arrow Keys)

    private var navigationGroup: some View {
        HStack(spacing: 8) {
            // Up arrow - for scrolling up in Claude plan mode
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

            // Left arrow
            ToolbarButton(
                icon: "chevron.left",
                label: "←",
                tint: .cyan
            ) {
                onSendControlKey(.leftArrow)
            }

            // Right arrow
            ToolbarButton(
                icon: "chevron.right",
                label: "→",
                tint: .cyan
            ) {
                onSendControlKey(.rightArrow)
            }
        }
    }

    // MARK: - Utilities

    private var utilityGroup: some View {
        HStack(spacing: 8) {
            ToolbarButton(
                icon: "sparkles",
                label: "Claude",
                tint: .purple
            ) {
                onSendCommand("claude")
            }

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

            ToolbarButton(
                icon: "square.and.arrow.up",
                label: "Share"
            ) {
                onTakeScreenshot()
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
                .background(Color(UIColor.secondarySystemBackground))
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
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    let icon: String
    let label: String
    var tint: Color = .primary

    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.lightTap()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(tint)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Repeatable Toolbar Button (for backspace, etc.)

struct RepeatableToolbarButton: View {
    let icon: String
    let label: String
    var tint: Color = .primary
    var repeatInterval: TimeInterval = 0.1  // How fast to repeat (seconds)
    var initialDelay: TimeInterval = 0.3    // Delay before repeating starts

    let action: () -> Void

    @State private var isPressed = false
    @State private var repeatTimer: Timer?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
            Text(label)
                .font(.system(size: 10))
        }
        .foregroundStyle(isPressed ? tint.opacity(0.6) : tint)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        // Fire immediately on press
                        HapticManager.shared.lightTap()
                        action()

                        // Start repeat timer after initial delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
                            guard isPressed else { return }
                            startRepeating()
                        }
                    }
                }
                .onEnded { _ in
                    stopRepeating()
                }
        )
    }

    private func startRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatInterval, repeats: true) { _ in
            action()
            // Light haptic on each repeat
            HapticManager.shared.lightTap()
        }
    }

    private func stopRepeating() {
        isPressed = false
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

// MARK: - Command History View

struct CommandHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var historyManager = CommandHistoryManager.shared
    @State private var searchText = ""

    let onSelect: (String) -> Void

    private var filteredCommands: [CommandHistoryManager.CommandEntry] {
        if searchText.isEmpty {
            return historyManager.commands
        }
        return historyManager.searchCommands(searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCommands) { entry in
                    Button {
                        onSelect(entry.command)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.command)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(2)
                            Text(entry.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            historyManager.deleteCommand(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search commands")
            .navigationTitle("Command History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All", role: .destructive) {
                        historyManager.clearHistory()
                    }
                    .disabled(historyManager.commands.isEmpty)
                }
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        TerminalToolbar(
            onSendCommand: { print("Command: \($0)") },
            onSendControlKey: { print("Control: \($0)") },
            onTakeScreenshot: { print("Screenshot") },
            sessionManager: TerminalSessionManager.shared,
            voiceService: VoiceCommandService()
        )
    }
}
