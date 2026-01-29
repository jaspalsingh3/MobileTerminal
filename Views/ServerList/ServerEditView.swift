//
//  ServerEditView.swift
//  Mobile Terminal
//
//  Form for adding or editing a server connection
//

import SwiftUI

struct ServerEditView: View {
    enum Mode: Identifiable {
        case add
        case edit(ServerConnection)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let server): return server.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var serverManager: ServerManager
    @StateObject private var connectionService = ConnectionService.shared
    @StateObject private var biometricService = BiometricService.shared

    @State private var sshKeys: [SSHKey] = []

    // Form fields
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "7681"
    @State private var connectionType: ConnectionType = .http
    @State private var authType: AuthType = .none
    @State private var token: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var selectedSSHKeyId: UUID?
    @State private var useBiometrics: Bool = false
    @State private var isFavorite: Bool = false
    @State private var fontSize: Int = 22

    // UI State
    @State private var showPassword = false
    @State private var isTestingConnection = false
    @State private var testResult: ConnectionService.TestResult?
    @State private var showingValidationError = false
    @State private var validationError = ""
    @State private var showingSSHKeyManager = false

    enum AuthType: String, CaseIterable {
        case none = "None"
        case token = "Token URL"
        case basicAuth = "Basic Auth"
        case sshKey = "SSH Key"
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingServer: ServerConnection? {
        if case .edit(let server) = mode { return server }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Basic Info
                Section("Server Info") {
                    TextField("Name", text: $name)
                        .textContentType(.organizationName)

                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("Protocol", selection: $connectionType) {
                        ForEach(ConnectionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                // MARK: - Authentication
                Section("Authentication") {
                    Picker("Method", selection: $authType) {
                        ForEach(AuthType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    switch authType {
                    case .none:
                        Text("No authentication required")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                    case .token:
                        TextField("Token", text: $token)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))

                        Text("Token will be appended to URL path")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                    case .basicAuth:
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        HStack {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .textContentType(.password)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                            }

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Password is stored securely in Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                    case .sshKey:
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        // SSH Key Picker
                        if sshKeys.isEmpty {
                            Button {
                                showingSSHKeyManager = true
                            } label: {
                                Label("Import SSH Key", systemImage: "key.fill")
                            }

                            Text("No SSH keys found. Import a key to continue.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("SSH Key", selection: $selectedSSHKeyId) {
                                Text("Select a key").tag(nil as UUID?)
                                ForEach(sshKeys) { key in
                                    HStack {
                                        Text(key.name)
                                        Text("(\(key.keyType.rawValue))")
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(key.id as UUID?)
                                }
                            }

                            Button {
                                showingSSHKeyManager = true
                            } label: {
                                Label("Manage SSH Keys", systemImage: "key.fill")
                            }
                        }

                        Text("SSH key authentication for ttyd servers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Security
                if biometricService.isAvailable {
                    Section("Security") {
                        Toggle(isOn: $useBiometrics) {
                            Label(
                                "Require \(biometricService.biometricType.displayName)",
                                systemImage: biometricService.biometricType.iconName
                            )
                        }

                        if useBiometrics {
                            Text("\(biometricService.biometricType.displayName) will be required before connecting")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Preferences
                Section("Preferences") {
                    Toggle("Favorite", isOn: $isFavorite)

                    HStack {
                        Text("Font Size")
                        Spacer()
                        HStack(spacing: 16) {
                            Button {
                                if fontSize > 12 { fontSize -= 2 }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)

                            Text("\(fontSize)px")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50)

                            Button {
                                if fontSize < 36 { fontSize += 2 }
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(.blue)
                    }
                }

                // MARK: - Test Connection
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "network")
                            Spacer()
                            if isTestingConnection {
                                ProgressView()
                            } else if let result = testResult {
                                testResultView(result)
                            }
                        }
                    }
                    .disabled(host.isEmpty)
                }
            }
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveServer()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Validation Error", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationError)
            }
            .onAppear {
                sshKeys = SSHKeyManager.shared.keys
                loadExistingServer()
            }
            .sheet(isPresented: $showingSSHKeyManager, onDismiss: {
                sshKeys = SSHKeyManager.shared.keys
            }) {
                NavigationStack {
                    SSHKeyManagerView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingSSHKeyManager = false
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Test Result View

    @ViewBuilder
    private func testResultView(_ result: ConnectionService.TestResult) -> some View {
        switch result {
        case .success(let latency):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(connectionService.formatLatency(latency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failure(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(port) != nil
    }

    // MARK: - Actions

    private func loadExistingServer() {
        guard let server = existingServer else { return }

        name = server.name
        host = server.host
        port = String(server.port)
        connectionType = server.connectionType
        useBiometrics = server.useBiometrics
        isFavorite = server.isFavorite
        fontSize = server.fontSize

        switch server.authMethod {
        case .none:
            authType = .none
        case .token(let t):
            authType = .token
            token = t
        case .basicAuth(let u):
            authType = .basicAuth
            username = u
            // Load password from keychain
            password = CredentialManager.shared.getPassword(for: server.id) ?? ""
        case .sshKey(let keyId, let u):
            authType = .sshKey
            selectedSSHKeyId = keyId
            username = u
        }
    }

    private func saveServer() {
        guard isValid else {
            validationError = "Please fill in all required fields"
            showingValidationError = true
            return
        }

        let authMethod: AuthMethod
        switch authType {
        case .none:
            authMethod = .none
        case .token:
            authMethod = .token(token)
        case .basicAuth:
            authMethod = .basicAuth(username: username)
        case .sshKey:
            guard let keyId = selectedSSHKeyId else {
                validationError = "Please select an SSH key"
                showingValidationError = true
                return
            }
            authMethod = .sshKey(keyId: keyId, username: username)
        }

        if let existingServer = existingServer {
            // Update existing server
            var updated = existingServer
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.host = host.trimmingCharacters(in: .whitespaces)
            updated.port = Int(port) ?? 7681
            updated.connectionType = connectionType
            updated.authMethod = authMethod
            updated.useBiometrics = useBiometrics
            updated.isFavorite = isFavorite
            updated.fontSize = fontSize

            serverManager.updateServer(updated)

            // Save password if basic auth
            if authType == .basicAuth && !password.isEmpty {
                CredentialManager.shared.savePassword(password, for: existingServer.id)
            }
        } else {
            // Create new server
            let newServer = ServerConnection(
                name: name.trimmingCharacters(in: .whitespaces),
                host: host.trimmingCharacters(in: .whitespaces),
                port: Int(port) ?? 7681,
                connectionType: connectionType,
                authMethod: authMethod,
                useBiometrics: useBiometrics,
                isFavorite: isFavorite,
                fontSize: fontSize
            )

            serverManager.addServer(newServer)

            // Save password if basic auth
            if authType == .basicAuth && !password.isEmpty {
                CredentialManager.shared.savePassword(password, for: newServer.id)
            }
        }

        dismiss()
    }

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        // Build a temporary server for testing
        let authMethod: AuthMethod
        switch authType {
        case .none:
            authMethod = .none
        case .token:
            authMethod = .token(token)
        case .basicAuth:
            authMethod = .basicAuth(username: username)
        case .sshKey:
            guard let keyId = selectedSSHKeyId else {
                testResult = .failure("No SSH key selected")
                isTestingConnection = false
                return
            }
            authMethod = .sshKey(keyId: keyId, username: username)
        }

        let testServer = ServerConnection(
            name: name,
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 7681,
            connectionType: connectionType,
            authMethod: authMethod
        )

        // Temporarily save password for test if needed
        if authType == .basicAuth && !password.isEmpty {
            CredentialManager.shared.savePassword(password, for: testServer.id)
        }

        Task {
            let result = await connectionService.testConnection(to: testServer)
            isTestingConnection = false
            testResult = result

            // Clean up temp password
            if authType == .basicAuth {
                CredentialManager.shared.deletePassword(for: testServer.id)
            }
        }
    }
}

#Preview("Add Server") {
    ServerEditView(mode: .add)
        .environmentObject(ServerManager.shared)
}

#Preview("Edit Server") {
    ServerEditView(mode: .edit(.sample))
        .environmentObject(ServerManager.shared)
}
