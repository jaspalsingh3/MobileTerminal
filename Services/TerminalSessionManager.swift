//
//  TerminalSessionManager.swift
//  Mobile Terminal
//
//  Manages terminal connection state and session persistence
//

import SwiftUI
import Combine
import UIKit

final class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    @Published var isConnected = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastConnectedTime: Date?
    @Published var reconnectAttempts = 0
    
    // Persistent SSH Client instance
    @Published var activeClient: SSHClient?
    
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var cancellables = Set<AnyCancellable>()
    private var keepAliveTimer: Timer?

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

    private init() {
        setupLifecycleObservers()
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        guard isConnected else { return }
        
        // Request extra time from iOS to keep the socket alive
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SSHKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
        
        // Start a more aggressive keep-alive timer if needed
        startKeepAliveTimer()
    }
    
    @objc private func appWillEnterForeground() {
        endBackgroundTask()
        stopKeepAliveTimer()
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            // Send a safe "no-op" control character to keep the SSH channel active
            // \u{00} is a null character that usually has no effect but keeps the socket busy
            self?.activeClient?.sendRawData([0])
        }
    }
    
    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    func prepareSession(for server: ServerConnection) -> SSHClient {
        // If we already have a client for this server, reuse it
        if let existing = activeClient {
            // Note: In a full app you might check if server IDs match
            return existing
        }
        
        let client = SSHClient()
        activeClient = client
        
        // Sync client state to manager
        client.$connectionState
            .sink { [weak self] state in
                self?.updateFromClientState(state)
            }
            .store(in: &cancellables)
            
        return client
    }
    
    private func updateFromClientState(_ state: SSHClient.SSHConnectionState) {
        switch state {
        case .connected:
            didConnect()
        case .error(let msg):
            didEncounterError(msg)
        case .connecting, .authenticating:
            didStartConnecting()
        case .disconnected:
            didDisconnect()
        }
    }

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

    func disconnect() {
        activeClient?.disconnect()
        activeClient = nil
        cancellables.removeAll()
        didDisconnect()
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
