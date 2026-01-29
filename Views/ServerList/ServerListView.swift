//
//  ServerListView.swift
//  Mobile Terminal
//
//  Main view showing all saved servers with favorites, recents, and search
//

import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var serverManager: ServerManager
    @StateObject private var biometricService = BiometricService.shared

    @State private var searchText = ""
    @State private var showingAddServer = false
    @State private var serverToEdit: ServerConnection?
    @State private var serverToConnect: ServerConnection?
    @State private var serverAwaitingPassword: ServerConnection?
    @State private var showingPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var connectionError: String?
    @State private var showingConnectionError = false

    private var filteredServers: [ServerConnection] {
        serverManager.searchServers(searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if serverManager.servers.isEmpty {
                    emptyStateView
                } else {
                    serverListContent
                }
            }
            .navigationTitle("Servers")
            .searchable(text: $searchText, prompt: "Search servers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddServer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddServer) {
                ServerEditView(mode: .add)
            }
            .sheet(item: $serverToEdit) { server in
                ServerEditView(mode: .edit(server))
            }
            .navigationDestination(item: $serverToConnect) { server in
                if server.connectionType == .ssh {
                    SSHTerminalView(server: server)
                } else {
                    TerminalView(server: server)
                }
            }
            .alert("Connection Error", isPresented: $showingConnectionError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(connectionError ?? "Unknown error")
            }
            .alert("Enter Password", isPresented: $showingPasswordPrompt) {
                SecureField("Password", text: $passwordInput)
                Button("Connect") {
                    if let server = serverAwaitingPassword {
                        CredentialManager.shared.savePassword(passwordInput, for: server.id)
                        passwordInput = ""
                        serverAwaitingPassword = nil
                        // Now navigate
                        serverManager.markAsConnected(server)
                        serverToConnect = server
                    }
                }
                Button("Cancel", role: .cancel) {
                    passwordInput = ""
                    serverAwaitingPassword = nil
                }
            } message: {
                if let server = serverAwaitingPassword {
                    Text("Enter password for \(server.name)")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
        } description: {
            Text("Add your first server to get started")
        } actions: {
            Button {
                showingAddServer = true
            } label: {
                Text("Add Server")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Server List Content

    private var serverListContent: some View {
        List {
            // Favorites Section
            if !serverManager.favoriteServers.isEmpty && searchText.isEmpty {
                Section("Favorites") {
                    ForEach(serverManager.favoriteServers) { server in
                        ServerRowView(
                            server: server,
                            onConnect: { connectToServer(server) },
                            onEdit: { serverToEdit = server }
                        )
                    }
                }
            }

            // Recent Section
            if !serverManager.recentServers.isEmpty && searchText.isEmpty {
                Section("Recent") {
                    ForEach(serverManager.recentServers.prefix(5)) { server in
                        ServerRowView(
                            server: server,
                            onConnect: { connectToServer(server) },
                            onEdit: { serverToEdit = server }
                        )
                    }
                }
            }

            // All Servers Section
            Section(searchText.isEmpty ? "All Servers" : "Search Results") {
                ForEach(filteredServers) { server in
                    ServerRowView(
                        server: server,
                        onConnect: { connectToServer(server) },
                        onEdit: { serverToEdit = server }
                    )
                }
                .onDelete { offsets in
                    let serversToDelete = offsets.map { filteredServers[$0] }
                    for server in serversToDelete {
                        serverManager.deleteServer(server)
                    }
                }
            }
        }
    }

    // MARK: - Connection Logic

    private func connectToServer(_ server: ServerConnection) {
        Task {
            // Check if biometrics required
            if server.useBiometrics && biometricService.isAvailable {
                let result = await biometricService.authenticateForServer(server.name)
                switch result {
                case .success:
                    proceedWithConnection(server)
                case .failure(let error):
                    if case .userFallback = error {
                        // User wants to use password
                        proceedWithConnection(server)
                    } else if case .userCancelled = error {
                        // User cancelled, do nothing
                        return
                    } else {
                        connectionError = error.localizedDescription
                        showingConnectionError = true
                    }
                }
            } else {
                proceedWithConnection(server)
            }
        }
    }

    private func proceedWithConnection(_ server: ServerConnection) {
        // Check if password is needed for basic auth
        if case .basicAuth = server.authMethod {
            if CredentialManager.shared.getPassword(for: server.id) == nil {
                serverAwaitingPassword = server
                showingPasswordPrompt = true
                return
            }
        }

        // Check if SSH key exists for SSH key auth
        // If key not found, fall back to password prompt
        if case .sshKey(let keyId, _) = server.authMethod {
            if SSHKeyManager.shared.getPrivateKey(for: keyId) == nil {
                // No private key - prompt for password as fallback
                if CredentialManager.shared.getPassword(for: server.id) == nil {
                    serverAwaitingPassword = server
                    showingPasswordPrompt = true
                    return
                }
            }
        }

        // Mark as connected and navigate
        serverManager.markAsConnected(server)
        serverToConnect = server
    }
}

#Preview {
    ServerListView()
        .environmentObject(ServerManager.shared)
}
