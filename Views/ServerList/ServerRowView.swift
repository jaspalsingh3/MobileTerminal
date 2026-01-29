//
//  ServerRowView.swift
//  Mobile Terminal
//
//  Individual server row component for the server list
//

import SwiftUI

struct ServerRowView: View {
    let server: ServerConnection
    let onConnect: () -> Void
    let onEdit: () -> Void

    @EnvironmentObject var serverManager: ServerManager
    @StateObject private var connectionService = ConnectionService.shared

    @State private var isTestingConnection = false
    @State private var testResult: ConnectionService.TestResult?

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                // Server icon with status
                serverIcon

                // Server info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(server.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if server.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }

                    Text(server.displayAddress)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        // Connection type badge
                        Text(server.connectionType.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(server.connectionType == .https ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                            .foregroundStyle(server.connectionType == .https ? .green : .orange)
                            .cornerRadius(4)

                        // Auth method badge
                        if case .basicAuth = server.authMethod {
                            Label("Auth", systemImage: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if case .token = server.authMethod {
                            Label("Token", systemImage: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // Biometrics indicator
                        if server.useBiometrics {
                            Image(systemName: "faceid")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()

                // Test connection indicator or chevron
                if isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let result = testResult {
                    testResultIndicator(result)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                serverManager.toggleFavorite(server)
            } label: {
                Label(server.isFavorite ? "Unfavorite" : "Favorite", systemImage: server.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                serverManager.deleteServer(server)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button {
                testConnection()
            } label: {
                Label("Test", systemImage: "network")
            }
            .tint(.green)
        }
        .contextMenu {
            Button {
                onConnect()
            } label: {
                Label("Connect", systemImage: "play.fill")
            }

            Button {
                testConnection()
            } label: {
                Label("Test Connection", systemImage: "network")
            }

            Button {
                serverManager.toggleFavorite(server)
            } label: {
                Label(server.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: server.isFavorite ? "star.slash" : "star")
            }

            Divider()

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                serverManager.deleteServer(server)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Server Icon

    private var serverIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
                .frame(width: 44, height: 44)

            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Test Result Indicator

    @ViewBuilder
    private func testResultIndicator(_ result: ConnectionService.TestResult) -> some View {
        switch result {
        case .success(let latency):
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(connectionService.formatLatency(latency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        Task {
            let result = await connectionService.testConnection(to: server)
            isTestingConnection = false
            testResult = result

            // Clear result after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            testResult = nil
        }
    }
}

#Preview {
    List {
        ServerRowView(
            server: .sample,
            onConnect: {},
            onEdit: {}
        )
        ServerRowView(
            server: .sampleWithToken,
            onConnect: {},
            onEdit: {}
        )
        ServerRowView(
            server: .sampleWithBasicAuth,
            onConnect: {},
            onEdit: {}
        )
    }
    .environmentObject(ServerManager.shared)
}
