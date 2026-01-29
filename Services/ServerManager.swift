//
//  ServerManager.swift
//  Mobile Terminal
//
//  Manages server connections with CRUD operations and persistence
//

import Foundation
import SwiftUI

final class ServerManager: ObservableObject {
    static let shared = ServerManager()

    @Published var servers: [ServerConnection] = []
    @Published var activeServer: ServerConnection?
    @Published var isLoading = false

    private let storageKey = "com.mobileterminal.servers"
    private let fileManager = FileManager.default

    private var storageURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("servers.json")
    }

    private init() {
        loadServers()
    }

    // MARK: - CRUD Operations

    /// Add a new server
    func addServer(_ server: ServerConnection) {
        servers.append(server)
        saveServers()
    }

    /// Update an existing server
    func updateServer(_ server: ServerConnection) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }

    /// Delete a server
    func deleteServer(_ server: ServerConnection) {
        servers.removeAll { $0.id == server.id }
        if activeServer?.id == server.id {
            activeServer = nil
        }
        // Also delete credentials
        CredentialManager.shared.deleteCredentials(for: server.id)
        saveServers()
    }

    /// Delete servers at specific indices
    func deleteServers(at offsets: IndexSet) {
        let serversToDelete = offsets.map { servers[$0] }
        for server in serversToDelete {
            CredentialManager.shared.deleteCredentials(for: server.id)
        }
        servers.remove(atOffsets: offsets)
        saveServers()
    }

    /// Toggle favorite status
    func toggleFavorite(_ server: ServerConnection) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].isFavorite.toggle()
            saveServers()
        }
    }

    /// Mark server as recently connected
    func markAsConnected(_ server: ServerConnection) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].lastConnected = Date()
            saveServers()
        }
    }

    // MARK: - Filtered Lists

    /// Get favorite servers
    var favoriteServers: [ServerConnection] {
        servers.filter { $0.isFavorite }
    }

    /// Get recently connected servers (last 7 days)
    var recentServers: [ServerConnection] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return servers
            .filter { $0.lastConnected != nil && $0.lastConnected! > weekAgo }
            .sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
    }

    /// Get all servers sorted by name
    var allServersSorted: [ServerConnection] {
        servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Search servers by name or host
    func searchServers(_ query: String) -> [ServerConnection] {
        guard !query.isEmpty else { return allServersSorted }
        let lowercasedQuery = query.lowercased()
        return servers.filter {
            $0.name.lowercased().contains(lowercasedQuery) ||
            $0.host.lowercased().contains(lowercasedQuery)
        }
    }

    // MARK: - Persistence

    private func saveServers() {
        do {
            let data = try JSONEncoder().encode(servers)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save servers: \(error)")
        }
    }

    private func loadServers() {
        do {
            let data = try Data(contentsOf: storageURL)
            servers = try JSONDecoder().decode([ServerConnection].self, from: data)
        } catch {
            // File doesn't exist or is invalid, start with empty list
            servers = []
        }
    }

    // MARK: - Import/Export

    /// Export servers to JSON data (for sharing)
    func exportServers() -> Data? {
        // Export without sensitive data
        let sanitizedServers = servers.map { server -> ServerConnection in
            var copy = server
            // Clear tokens for export
            if case .token = copy.authMethod {
                copy.authMethod = .token("REDACTED")
            }
            return copy
        }
        return try? JSONEncoder().encode(sanitizedServers)
    }

    /// Import servers from JSON data
    func importServers(from data: Data) throws {
        let imported = try JSONDecoder().decode([ServerConnection].self, from: data)
        for var server in imported {
            // Generate new IDs to avoid conflicts
            server = ServerConnection(
                id: UUID(),
                name: server.name,
                host: server.host,
                port: server.port,
                connectionType: server.connectionType,
                authMethod: server.authMethod,
                useBiometrics: false, // Reset biometrics for security
                isFavorite: false,
                fontSize: server.fontSize
            )
            servers.append(server)
        }
        saveServers()
    }
}
