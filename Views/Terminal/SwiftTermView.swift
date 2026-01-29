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
        
        // Configure terminal behavior
        let term = terminalView.getTerminal()
        // Disable mouse reporting if it's causing issues, or keep standard
        // Some TUI apps get confused by too much reporting on mobile
        
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
    }

    static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        // Clean up when view is removed from hierarchy
        coordinator.cleanup()
        uiView.terminalDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sshClient: sshClient)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        private let sshClient: SSHClient
        var terminalView: SwiftTerm.TerminalView?
        private var hasBeenCleaned = false
        
        // Serial queue for terminal operations to ensure order and thread safety
        private let terminalQueue = DispatchQueue(label: "com.mobileterminal.terminalQueue")

        init(sshClient: SSHClient) {
            self.sshClient = sshClient
            super.init()
        }

        deinit {
            terminalView = nil
        }

        /// Clean up - called when view is dismantled
        func cleanup() {
            hasBeenCleaned = true
            sshClient.onDataReceived = nil
            terminalView = nil
        }
        
        func resetTerminal() {
            terminalQueue.async { [weak self] in
                DispatchQueue.main.async {
                    self?.terminalView?.getTerminal().resetToInitialState()
                }
            }
        }

        // MARK: - SSH Client Integration

        func setupSSHClient() {
            guard !hasBeenCleaned else { return }

            sshClient.onDataReceived = { [weak self] bytes in
                guard let self = self else { return }
                self.terminalQueue.async {
                    self.feedTerminal(bytes: bytes)
                }
            }
            
            sshClient.onResetRequested = { [weak self] in
                self?.resetTerminal()
            }
        }

        private func feedTerminal(bytes: [UInt8]) {
            // Note: Must be called from terminalQueue or a thread-safe manner
            guard !hasBeenCleaned,
                  let terminal = terminalView else {
                return
            }
            
            // Still dispatch to main for the actual UIKit-backed terminal view update
            // but the processing is now serialized through terminalQueue
            DispatchQueue.main.async {
                guard terminal.window != nil else { return }
                terminal.feed(byteArray: ArraySlice(bytes))
            }
        }

        // MARK: - TerminalViewDelegate

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            // Copy data immediately to avoid ArraySlice lifecycle issues
            guard !data.isEmpty else { return }
            let dataToSend = Array(data)

            // Dispatch to main thread to ensure thread safety
            // SwiftTerm may call this from any thread
            if Thread.isMainThread {
                guard !hasBeenCleaned else { return }
                sshClient.sendRawData(dataToSend)
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.hasBeenCleaned else { return }
                    self.sshClient.sendRawData(dataToSend)
                }
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            // No action needed
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // No action needed
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard !hasBeenCleaned else { return }
            guard newCols > 0, newRows > 0 else { return }
            
            terminalQueue.async { [weak self] in
                self?.sshClient.resizeTerminal(cols: newCols, rows: newRows)
            }
        }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = string
            }
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // No action needed
        }

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // No action needed
        }
    }
}

// MARK: - Preview

#Preview {
    SwiftTermView(sshClient: SSHClient(), fontSize: 14)
        .background(SwiftUI.Color.black)
}
