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
    @Published var errorMessage: String?

    private var sshClient: Citadel.SSHClient?
    private var stdinWriter: TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?

    // Raw data callback for SwiftTerm integration
    var onDataReceived: (([UInt8]) -> Void)?
    var onResetRequested: (() -> Void)?

    // Terminal size (updated by SwiftTermView)
    // Default to standard 80x24 which is safer for TUI initial layout
    private(set) var terminalCols: Int = 80
    private(set) var terminalRows: Int = 24

    // Connection parameters
    private var host: String = ""
    private var port: Int = 22
    private var username: String = ""
    private var authMethod: SSHAuthMethod = .password("")
    
    // Sequential task for sending data to ensure order and avoid concurrent writes
    private var lastWriteTask: Task<Void, Never>?

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
        lastWriteTask?.cancel()
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
            errorMessage = nil
        }

        await logToTerminal("Connecting to \(host):\(port)...\r\n")

        do {
            // Create SSH client based on auth method
            await MainActor.run {
                connectionState = .authenticating
            }
            await logToTerminal("Authenticating as \(username)...\r\n")

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
                    await logToTerminal("Using Ed25519 key authentication\r\n")
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
                        await logToTerminal("Using RSA key authentication\r\n")
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

            await logToTerminal("SSH connection established!\r\n")
            await logToTerminal("Opening interactive shell...\r\n")

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

        // Use stored terminal size or standard defaults
        // Using standard 80x24 as a safer fallback than 50
        let cols = terminalCols > 0 ? terminalCols : 80
        let rows = terminalRows > 0 ? terminalRows : 24

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
                        case .stderr(let buffer):
                            // Get raw bytes for SwiftTerm
                            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
                                await MainActor.run {
                                    self.onDataReceived?(bytes)
                                }
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
        await logToTerminal("\r\n\(message)\r\n")
    }

    private func logToTerminal(_ message: String) async {
        let bytes = Array(message.utf8)
        await MainActor.run {
            self.onDataReceived?(bytes)
        }
    }

    // MARK: - Data Transmission

    func send(_ command: String) {
        guard connectionState == .connected, stdinWriter != nil else { return }
        let data = command + "\n"
        enqueueWrite(data: Array(data.utf8))
    }

    func sendControlSequence(_ sequence: String) {
        guard connectionState == .connected, stdinWriter != nil else { return }
        enqueueWrite(data: Array(sequence.utf8))
    }

    /// Send raw bytes to SSH (used by SwiftTerm for keyboard input)
    func sendRawData(_ data: [UInt8]) {
        guard connectionState == .connected, let _ = stdinWriter else { return }
        guard !data.isEmpty else { return }
        enqueueWrite(data: data)
    }

    /// Helper to enqueue writes sequentially to ensure order and avoid race conditions
    private func enqueueWrite(data: [UInt8]) {
        guard let writer = stdinWriter else { return }
        
        // Chain the new write task to the previous one
        let previousTask = lastWriteTask
        lastWriteTask = Task { [weak self] in
            // Wait for previous write to complete
            _ = await previousTask?.result
            
            guard self != nil else { return }
            
            do {
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                try await writer.write(buffer)
            } catch {
                print("Failed to write to SSH: \(error)")
            }
        }
    }

    /// Update terminal size (called when SwiftTermView resizes)
    func resizeTerminal(cols: Int, rows: Int) {
        let changed = terminalCols != cols || terminalRows != rows
        terminalCols = cols
        terminalRows = rows
        
        if changed, connectionState == .connected {
            Task {
                try? await stdinWriter?.changeSize(
                    cols: cols,
                    rows: rows,
                    pixelWidth: 0,
                    pixelHeight: 0
                )
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        sessionTask?.cancel()
        sessionTask = nil
        lastWriteTask?.cancel()
        lastWriteTask = nil
        stdinWriter = nil

        Task {
            try? await sshClient?.close()
            sshClient = nil
        }

        Task { @MainActor in
            connectionState = .disconnected
        }
    }

    func clearOutput() {
        onResetRequested?()
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
