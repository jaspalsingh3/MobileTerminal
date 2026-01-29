//
//  SwiftTermView.swift
//  Mobile Terminal
//
//  UIViewRepresentable wrapper for SwiftTerm to render rich terminal output
//  with full ANSI escape code support for colors, cursor positioning, etc.
//

import SwiftUI
import SwiftTerm

struct SwiftTermView: UIViewRepresentable {
    @ObservedObject var sshClient: SSHClient
    let fontSize: Int

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)

        // Configure terminal appearance
        terminalView.backgroundColor = .black

        // Set font
        let font = UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        terminalView.font = font

        // Enable auto-resizing to fill container
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Set the delegate for handling user input
        terminalView.terminalDelegate = context.coordinator

        // Store reference in coordinator
        context.coordinator.terminalView = terminalView

        // Wire up SSH client data callback
        context.coordinator.setupSSHClient()

        return terminalView
    }

    func updateUIView(_ terminalView: SwiftTerm.TerminalView, context: Context) {
        // Update font size if changed
        let newFont = UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        if terminalView.font != newFont {
            terminalView.font = newFont
        }

        // Ensure terminal fills its container
        DispatchQueue.main.async {
            if let superview = terminalView.superview {
                terminalView.frame = superview.bounds
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sshClient: sshClient)
    }

    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        // Hold direct reference to SSHClient (it's a class/ObservableObject)
        private let sshClient: SSHClient
        // Strong reference to prevent premature deallocation
        var terminalView: SwiftTerm.TerminalView?
        // Track if this coordinator is still valid
        private var isValid = true

        init(sshClient: SSHClient) {
            self.sshClient = sshClient
            super.init()
        }

        deinit {
            invalidate()
        }

        /// Invalidate this coordinator - called on deinit or when view is removed
        func invalidate() {
            isValid = false
            sshClient.onDataReceived = nil
            terminalView = nil
        }

        // MARK: - SSH Client Integration

        func setupSSHClient() {
            // Always set up fresh callback (previous coordinator's deinit will clear old one)
            guard isValid else { return }

            // Wire SSH output to terminal.feed()
            // Use unique identifier to verify callback is still valid
            let coordinatorId = ObjectIdentifier(self)

            sshClient.onDataReceived = { [weak self] bytes in
                DispatchQueue.main.async {
                    // Verify this is still the active coordinator
                    guard let self = self,
                          self.isValid,
                          ObjectIdentifier(self) == coordinatorId,
                          let terminal = self.terminalView else {
                        return
                    }
                    terminal.feed(byteArray: ArraySlice(bytes))
                }
            }
        }

        // MARK: - TerminalViewDelegate

        /// Called when user types in the terminal - sends data to SSH
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            // Verify coordinator is still valid
            guard isValid else { return }
            // Safety check - ensure we have a valid connection
            guard case .connected = sshClient.connectionState else { return }
            guard !data.isEmpty else { return }

            // Copy data before sending to avoid issues with ArraySlice lifecycle
            let dataToSend = Array(data)
            sshClient.sendRawData(dataToSend)
        }

        /// Called when terminal is scrolled
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            guard isValid else { return }
        }

        /// Called when terminal title changes (via OSC escape sequence)
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            guard isValid else { return }
        }

        /// Called when terminal size changes
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard isValid else { return }
            guard newCols > 0, newRows > 0 else { return }
            sshClient.resizeTerminal(cols: newCols, rows: newRows)
        }

        /// Called when clipboard should be set
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            guard isValid else { return }
            if let string = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = string
            }
        }

        /// Called when host current directory changes
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            guard isValid else { return }
        }

        /// Request to open a URL
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            guard isValid else { return }
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        /// Called when a range of text was modified
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            guard isValid else { return }
        }
    }
}

// MARK: - Preview

#Preview {
    SwiftTermView(sshClient: SSHClient(), fontSize: 14)
        .background(SwiftUI.Color.black)
}
