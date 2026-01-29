//
//  TerminalSessionManager.swift
//  Mobile Terminal
//
//  Manages terminal connection state and session persistence
//

import SwiftUI
import Combine

final class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    @Published var isConnected = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastConnectedTime: Date?
    @Published var reconnectAttempts = 0

    @AppStorage("terminal_fontSize") var fontSize: Int = 22
    @AppStorage("terminal_haptics_enabled") var hapticsEnabled: Bool = true
    @AppStorage("terminal_autoReconnect") var autoReconnect: Bool = true

    private let maxReconnectAttempts = 3

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var statusText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var statusColor: Color {
            switch self {
            case .disconnected: return .gray
            case .connecting: return .orange
            case .connected: return .green
            case .error: return .red
            }
        }
    }

    private init() {}

    func didStartConnecting() {
        connectionState = .connecting
        isConnected = false
    }

    func didConnect() {
        connectionState = .connected
        isConnected = true
        lastConnectedTime = Date()
        reconnectAttempts = 0

        if hapticsEnabled {
            HapticManager.shared.success()
        }
    }

    func didDisconnect() {
        connectionState = .disconnected
        isConnected = false
    }

    func didEncounterError(_ message: String) {
        connectionState = .error(message)
        isConnected = false

        if hapticsEnabled {
            HapticManager.shared.error()
        }
    }

    func shouldAttemptReconnect() -> Bool {
        guard autoReconnect else { return false }
        guard reconnectAttempts < maxReconnectAttempts else { return false }
        reconnectAttempts += 1
        return true
    }

    func resetReconnectAttempts() {
        reconnectAttempts = 0
    }

    // Font size controls
    func increaseFontSize() {
        if fontSize < 36 {
            fontSize += 2
            if hapticsEnabled {
                HapticManager.shared.lightTap()
            }
        }
    }

    func decreaseFontSize() {
        if fontSize > 12 {
            fontSize -= 2
            if hapticsEnabled {
                HapticManager.shared.lightTap()
            }
        }
    }

    func resetFontSize() {
        fontSize = 22
        if hapticsEnabled {
            HapticManager.shared.lightTap()
        }
    }
}
