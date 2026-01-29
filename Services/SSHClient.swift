//
//  SSHClient.swift
//  Mobile Terminal
//
//  Real SSH client implementation using Citadel (SwiftNIO SSH)
//  Supports password and SSH key authentication with persistent PTY shell
//

import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

// MARK: - SSH Client

final class SSHClient: ObservableObject {
    @Published var connectionState: SSHConnectionState = .disconnected
    @Published var outputBuffer: String = ""
    @Published var errorMessage: String?

    private var sshClient: Citadel.SSHClient?
    private var stdinWriter: TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?

    // Raw data callback for SwiftTerm integration
    var onDataReceived: (([UInt8]) -> Void)?

    // Terminal size (updated by SwiftTermView)
    private(set) var terminalCols: Int = 80
    private(set) var terminalRows: Int = 24

    // Connection parameters
    private var host: String = ""
    private var port: Int = 22
    private var username: String = ""
    private var authMethod: SSHAuthMethod = .password("")

    enum SSHAuthMethod {
        case password(String)
        case publicKey(privateKey: String, passphrase: String?)
    }

    enum SSHConnectionState: Equatable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case error(String)

        var statusText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .authenticating: return "Authenticating..."
            case .connected: return "Connected"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    deinit {
        sessionTask?.cancel()
    }

    // MARK: - Connection

    func connect(
        host: String,
        port: Int = 22,
        username: String,
        password: String
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = .password(password)

        Task {
            await establishConnection()
        }
    }

    func connect(
        host: String,
        port: Int = 22,
        username: String,
        privateKey: String,
        passphrase: String? = nil
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = .publicKey(privateKey: privateKey, passphrase: passphrase)

        Task {
            await establishConnection()
        }
    }

    func connectWithServer(_ server: ServerConnection) {
        self.host = server.host
        self.port = server.port
        self.username = extractUsername(from: server)

        switch server.authMethod {
        case .basicAuth(let user):
            let password = CredentialManager.shared.getPassword(for: server.id) ?? ""
            self.username = user
            self.authMethod = .password(password)

        case .sshKey(let keyId, let user):
            self.username = user
            if let privateKey = SSHKeyManager.shared.getPrivateKey(for: keyId) {
                let passphrase = SSHKeyManager.shared.getPassphrase(for: keyId)
                self.authMethod = .publicKey(privateKey: privateKey, passphrase: passphrase)
            } else {
                // Fall back to password if no private key
                let password = CredentialManager.shared.getPassword(for: server.id) ?? ""
                if password.isEmpty {
                    Task { @MainActor in
                        self.connectionState = .error("No private key found. Import your private key or use password auth.")
                    }
                    return
                }
                self.authMethod = .password(password)
            }

        case .none:
            // Try with empty password
            self.authMethod = .password("")

        case .token:
            Task { @MainActor in
                self.connectionState = .error("Token auth not supported for SSH")
            }
            return
        }

        Task {
            await establishConnection()
        }
    }

    private func extractUsername(from server: ServerConnection) -> String {
        switch server.authMethod {
        case .basicAuth(let username):
            return username
        case .sshKey(_, let username):
            return username
        default:
            return "root"
        }
    }

    private func establishConnection() async {
        await MainActor.run {
            connectionState = .connecting
            outputBuffer = ""
            errorMessage = nil
        }

        await appendOutput("Connecting to \(host):\(port)...\n")

        do {
            // Create SSH client based on auth method
            await MainActor.run {
                connectionState = .authenticating
            }
            await appendOutput("Authenticating as \(username)...\n")

            switch authMethod {
            case .password(let password):
                sshClient = try await Citadel.SSHClient.connect(
                    host: host,
                    port: port,
                    authenticationMethod: .passwordBased(username: username, password: password),
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never
                )

            case .publicKey(let privateKeyPEM, _):
                // Normalize the key format
                let keyString = normalizeOpenSSHKey(privateKeyPEM)

                // Try Ed25519 first (most common modern key type)
                do {
                    let ed25519Key = try Curve25519.Signing.PrivateKey(sshEd25519: keyString)
                    await appendOutput("Using Ed25519 key authentication\n")
                    sshClient = try await Citadel.SSHClient.connect(
                        host: host,
                        port: port,
                        authenticationMethod: .ed25519(username: username, privateKey: ed25519Key),
                        hostKeyValidator: .acceptAnything(),
                        reconnect: .never
                    )
                } catch {
                    // Try RSA
                    do {
                        let rsaKey = try Insecure.RSA.PrivateKey(sshRsa: keyString)
                        await appendOutput("Using RSA key authentication\n")
                        sshClient = try await Citadel.SSHClient.connect(
                            host: host,
                            port: port,
                            authenticationMethod: .rsa(username: username, privateKey: rsaKey),
                            hostKeyValidator: .acceptAnything(),
                            reconnect: .never
                        )
                    } catch {
                        throw SSHClientLocalError.invalidKeyFormat
                    }
                }
            }

            await appendOutput("SSH connection established!\n")
            await appendOutput("Opening interactive shell...\n")

            // Start persistent PTY shell session
            try await startShellSession()

        } catch let error as NIOSSHError {
            await handleError("SSH Error: \(error)")
        } catch let error as SSHClientLocalError {
            await handleError(error.localizedDescription)
        } catch let error as CitadelError {
            await handleError("Citadel Error: \(error)")
        } catch {
            await handleError("Connection failed: \(error.localizedDescription)")
        }
    }

    private func startShellSession() async throws {
        guard let client = sshClient else { return }

        // Use stored terminal size or mobile-friendly defaults
        // iPhone screens typically fit 45-50 columns at readable font sizes
        let cols = terminalCols > 0 ? terminalCols : 50
        let rows = terminalRows > 0 ? terminalRows : 30

        // Create PTY request with dynamic size
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        // Start PTY session in a long-running task
        sessionTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                try await client.withPTY(ptyRequest) { [weak self] inbound, outbound in
                    guard let self = self else { return }

                    // Store the writer and mark as connected
                    await MainActor.run {
                        self.stdinWriter = outbound
                        self.connectionState = .connected
                    }

                    // Read output continuously
                    for try await output in inbound {
                        if Task.isCancelled { break }

                        switch output {
                        case .stdout(let buffer):
                            // Get raw bytes for SwiftTerm
                            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
                                await MainActor.run {
                                    self.onDataReceived?(bytes)
                                }
                            }
                            // Also append to outputBuffer for backwards compatibility
                            if let text = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
                                await self.appendOutput(text)
                            }
                        case .stderr(let buffer):
                            // Get raw bytes for SwiftTerm
                            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
                                await MainActor.run {
                                    self.onDataReceived?(bytes)
                                }
                            }
                            // Also append to outputBuffer for backwards compatibility
                            if let text = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
                                await self.appendOutput(text)
                            }
                        }
                    }
                }

                // Session ended normally
                if !Task.isCancelled {
                    await self.handleError("Shell session ended")
                }
            } catch {
                if !Task.isCancelled {
                    await self.handleError("Shell error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleError(_ message: String) async {
        await MainActor.run {
            connectionState = .error(message)
            errorMessage = message
        }
        await appendOutput("\n\(message)\n")
    }

    // MARK: - Data Transmission

    func send(_ command: String) {
        guard connectionState == .connected, let writer = stdinWriter else { return }

        let data = command + "\n"

        Task {
            do {
                var buffer = ByteBufferAllocator().buffer(capacity: data.utf8.count)
                buffer.writeString(data)
                try await writer.write(buffer)
            } catch {
                await handleError("Failed to send: \(error.localizedDescription)")
            }
        }
    }

    func sendControlSequence(_ sequence: String) {
        // Capture writer reference before async work
        guard connectionState == .connected, let writer = stdinWriter else { return }

        // Explicitly capture writer to ensure it's retained
        let capturedWriter = writer
        Task {
            do {
                var buffer = ByteBufferAllocator().buffer(capacity: sequence.utf8.count)
                buffer.writeString(sequence)
                try await capturedWriter.write(buffer)
            } catch {
                print("Failed to send control sequence: \(error)")
            }
        }
    }

    /// Send raw bytes to SSH (used by SwiftTerm for keyboard input)
    func sendRawData(_ data: [UInt8]) {
        // Capture writer reference before async work
        guard connectionState == .connected, let writer = stdinWriter else { return }

        // Explicitly capture writer to ensure it's retained
        let capturedWriter = writer
        Task {
            do {
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                try await capturedWriter.write(buffer)
            } catch {
                print("Failed to send raw data: \(error)")
            }
        }
    }

    /// Update terminal size (called when SwiftTermView resizes)
    func resizeTerminal(cols: Int, rows: Int) {
        terminalCols = cols
        terminalRows = rows
        // Note: Citadel doesn't support window-change requests after session start
        // The terminal will use the initial size from PTY request
        // For a full implementation, you'd need to send SSH_MSG_CHANNEL_REQUEST
        // with "window-change" type, but Citadel's API doesn't expose this
    }

    // MARK: - Disconnect

    func disconnect() {
        sessionTask?.cancel()
        sessionTask = nil
        stdinWriter = nil

        Task {
            try? await sshClient?.close()
            sshClient = nil
        }

        Task { @MainActor in
            connectionState = .disconnected
        }

        Task {
            await appendOutput("\nConnection closed.\n")
        }
    }

    // MARK: - Output

    private func appendOutput(_ text: String) async {
        let cleanText = stripANSIEscapeCodes(text)
        await MainActor.run {
            outputBuffer += cleanText
        }
    }

    /// Strip ANSI escape codes from terminal output
    private func stripANSIEscapeCodes(_ text: String) -> String {
        // Match various ANSI/terminal escape sequences:
        // - CSI sequences: ESC [ ... (letter)
        // - OSC sequences: ESC ] ... BEL
        // - Character set: ESC ( B, ESC ) B, etc.
        // - Other escapes: ESC followed by various characters
        let patterns = [
            "\u{1B}\\[[0-9;?]*[A-Za-z]",      // CSI sequences (colors, cursor, etc.)
            "\u{1B}\\][^\u{07}]*\u{07}",      // OSC sequences (title, etc.)
            "\u{1B}\\][^\u{1B}]*\u{1B}\\\\",  // OSC with ST terminator
            "\u{1B}[()][AB0-2]",               // Character set selection
            "\u{1B}[=>]",                      // Keypad modes
            "\u{1B}[78]",                      // Save/restore cursor
            "\u{1B}[DMEH]",                    // Line operations
            "\\(B",                            // Stray character set markers
        ]

        var result = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        return result
    }

    func clearOutput() {
        Task { @MainActor in
            outputBuffer = ""
        }
    }

    // MARK: - Key Normalization

    /// Normalize OpenSSH private key format (fix line breaks mangled by iOS TextEditor)
    private func normalizeOpenSSHKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        let beginMarker = "-----BEGIN OPENSSH PRIVATE KEY-----"
        let endMarker = "-----END OPENSSH PRIVATE KEY-----"

        var base64Content: String

        // Check if key has proper markers
        if trimmed.contains(beginMarker) && trimmed.contains(endMarker) {
            // Extract the base64 content between markers
            guard let beginRange = trimmed.range(of: beginMarker),
                  let endRange = trimmed.range(of: endMarker) else {
                return trimmed
            }

            let base64Start = beginRange.upperBound
            let base64End = endRange.lowerBound
            base64Content = String(trimmed[base64Start..<base64End])
        } else {
            // Key is raw base64 without markers - use as-is
            base64Content = trimmed
        }

        // Remove all whitespace from base64 content
        let cleanBase64 = base64Content
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Rebuild key with proper 70-character line breaks
        var formattedBase64 = ""
        var index = cleanBase64.startIndex
        while index < cleanBase64.endIndex {
            let endIndex = cleanBase64.index(index, offsetBy: 70, limitedBy: cleanBase64.endIndex) ?? cleanBase64.endIndex
            formattedBase64 += String(cleanBase64[index..<endIndex])
            if endIndex < cleanBase64.endIndex {
                formattedBase64 += "\n"
            }
            index = endIndex
        }

        // Always wrap with proper markers
        return "\(beginMarker)\n\(formattedBase64)\n\(endMarker)"
    }
}

// MARK: - SSH Client Errors

enum SSHClientLocalError: Error, LocalizedError {
    case invalidKeyFormat

    var errorDescription: String? {
        switch self {
        case .invalidKeyFormat:
            return "Invalid SSH key format. Supported formats: Ed25519, RSA"
        }
    }
}
