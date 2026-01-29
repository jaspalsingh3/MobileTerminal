//
//  ConnectionService.swift
//  Mobile Terminal
//
//  Handles URL building and connection testing for servers
//

import Foundation
import Network

final class ConnectionService: ObservableObject {
    static let shared = ConnectionService()

    @Published var isTestingConnection = false
    @Published var lastTestResult: TestResult?

    enum TestResult {
        case success(latency: TimeInterval)
        case failure(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    private init() {}

    // MARK: - URL Building

    /// Build the full URL for a server connection (HTTP/HTTPS only)
    func buildURL(for server: ServerConnection) -> URL? {
        // SSH doesn't use URLs
        guard server.connectionType.isWebBased else { return nil }

        var components = URLComponents()
        components.scheme = server.connectionType.rawValue
        components.host = server.host
        components.port = server.port

        switch server.authMethod {
        case .none:
            components.path = "/"
        case .token(let token):
            components.path = "/\(token)"
        case .basicAuth:
            components.path = "/"
        case .sshKey:
            components.path = "/"
        }

        return components.url
    }

    /// Build URLRequest with appropriate headers
    func buildRequest(for server: ServerConnection) -> URLRequest? {
        guard let url = buildURL(for: server) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Add basic auth header if needed
        if case .basicAuth(let username) = server.authMethod {
            if let password = CredentialManager.shared.getPassword(for: server.id) {
                let credentials = "\(username):\(password)"
                if let credentialData = credentials.data(using: .utf8) {
                    let base64Credentials = credentialData.base64EncodedString()
                    request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
                }
            }
        }

        return request
    }

    // MARK: - Connection Testing

    /// Test connection to a server
    func testConnection(to server: ServerConnection) async -> TestResult {
        isTestingConnection = true
        defer { isTestingConnection = false }

        // SSH uses TCP test instead of HTTP
        if server.connectionType == .ssh {
            return await testTCPConnection(host: server.host, port: server.port)
        }

        guard let url = buildURL(for: server) else {
            let result = TestResult.failure("Invalid URL")
            lastTestResult = result
            return result
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        // Add basic auth if needed
        if case .basicAuth(let username) = server.authMethod {
            if let password = CredentialManager.shared.getPassword(for: server.id) {
                let credentials = "\(username):\(password)"
                if let credentialData = credentials.data(using: .utf8) {
                    let base64Credentials = credentialData.base64EncodedString()
                    request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
                }
            }
        }

        let startTime = Date()

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let result = TestResult.failure("Invalid response")
                lastTestResult = result
                return result
            }

            let latency = Date().timeIntervalSince(startTime)

            if httpResponse.statusCode == 200 || httpResponse.statusCode == 101 {
                let result = TestResult.success(latency: latency)
                lastTestResult = result
                return result
            } else if httpResponse.statusCode == 401 {
                let result = TestResult.failure("Authentication required")
                lastTestResult = result
                return result
            } else if httpResponse.statusCode == 403 {
                let result = TestResult.failure("Access denied")
                lastTestResult = result
                return result
            } else {
                let result = TestResult.failure("HTTP \(httpResponse.statusCode)")
                lastTestResult = result
                return result
            }
        } catch {
            let result = TestResult.failure(error.localizedDescription)
            lastTestResult = result
            return result
        }
    }

    /// Test TCP connection for SSH servers
    private func testTCPConnection(host: String, port: Int) async -> TestResult {
        let startTime = Date()

        return await withCheckedContinuation { continuation in
            let hasResumed = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            hasResumed.initialize(to: false)

            let resumeOnce: (TestResult) -> Void = { result in
                guard !hasResumed.pointee else { return }
                hasResumed.pointee = true
                Task { @MainActor in
                    self.lastTestResult = result
                }
                continuation.resume(returning: result)
            }

            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port))
            )

            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "com.mobileterminal.tcptest")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let latency = Date().timeIntervalSince(startTime)
                    connection.cancel()
                    resumeOnce(.success(latency: latency))

                case .failed(let error):
                    connection.cancel()
                    resumeOnce(.failure(error.localizedDescription))

                case .waiting(let error):
                    connection.cancel()
                    resumeOnce(.failure(error.localizedDescription))

                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout after 10 seconds
            queue.asyncAfter(deadline: .now() + 10) {
                connection.cancel()
                resumeOnce(.failure("Connection timed out"))
                hasResumed.deallocate()
            }
        }
    }

    /// Format latency for display
    func formatLatency(_ latency: TimeInterval) -> String {
        let ms = Int(latency * 1000)
        return "\(ms)ms"
    }
}
