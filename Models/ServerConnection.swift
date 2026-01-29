//
//  ServerConnection.swift
//  Mobile Terminal
//
//  Data model for server connections
//

import Foundation

// MARK: - Server Connection Model

struct ServerConnection: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var connectionType: ConnectionType
    var authMethod: AuthMethod
    var useBiometrics: Bool
    var isFavorite: Bool
    var fontSize: Int
    var lastConnected: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 7681,
        connectionType: ConnectionType = .http,
        authMethod: AuthMethod = .none,
        useBiometrics: Bool = false,
        isFavorite: Bool = false,
        fontSize: Int = 22,
        lastConnected: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.connectionType = connectionType
        self.authMethod = authMethod
        self.useBiometrics = useBiometrics
        self.isFavorite = isFavorite
        self.fontSize = fontSize
        self.lastConnected = lastConnected
        self.createdAt = createdAt
    }

    /// Build the full URL for this server connection
    var url: URL? {
        var components = URLComponents()
        components.scheme = connectionType.rawValue
        components.host = host
        components.port = port

        switch authMethod {
        case .none:
            break
        case .token(let token):
            components.path = "/\(token)"
        case .basicAuth:
            // Basic auth is handled via headers, not URL
            break
        case .sshKey:
            // SSH key auth is handled via headers/handshake, not URL
            break
        }

        return components.url
    }

    /// Display string for the server address
    var displayAddress: String {
        "\(host):\(port)"
    }
}

// MARK: - Connection Type

enum ConnectionType: String, Codable, CaseIterable {
    case http
    case https
    case ssh

    var displayName: String {
        switch self {
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .ssh: return "SSH"
        }
    }

    var defaultPort: Int {
        switch self {
        case .http: return 7681
        case .https: return 443
        case .ssh: return 22
        }
    }

    var isWebBased: Bool {
        self == .http || self == .https
    }
}

// MARK: - Authentication Method

enum AuthMethod: Codable, Equatable, Hashable {
    case none
    case token(String)
    case basicAuth(username: String)
    case sshKey(keyId: UUID, username: String)

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .token:
            return "Token URL"
        case .basicAuth(let username):
            return "Basic Auth (\(username))"
        case .sshKey(_, let username):
            return "SSH Key (\(username))"
        }
    }

    var requiresPassword: Bool {
        switch self {
        case .basicAuth:
            return true
        default:
            return false
        }
    }

    var requiresSSHKey: Bool {
        switch self {
        case .sshKey:
            return true
        default:
            return false
        }
    }

    // Custom coding for enum with associated values
    private enum CodingKeys: String, CodingKey {
        case type
        case token
        case username
        case keyId
    }

    private enum AuthType: String, Codable {
        case none
        case token
        case basicAuth
        case sshKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AuthType.self, forKey: .type)

        switch type {
        case .none:
            self = .none
        case .token:
            let token = try container.decode(String.self, forKey: .token)
            self = .token(token)
        case .basicAuth:
            let username = try container.decode(String.self, forKey: .username)
            self = .basicAuth(username: username)
        case .sshKey:
            let keyId = try container.decode(UUID.self, forKey: .keyId)
            let username = try container.decode(String.self, forKey: .username)
            self = .sshKey(keyId: keyId, username: username)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .none:
            try container.encode(AuthType.none, forKey: .type)
        case .token(let token):
            try container.encode(AuthType.token, forKey: .type)
            try container.encode(token, forKey: .token)
        case .basicAuth(let username):
            try container.encode(AuthType.basicAuth, forKey: .type)
            try container.encode(username, forKey: .username)
        case .sshKey(let keyId, let username):
            try container.encode(AuthType.sshKey, forKey: .type)
            try container.encode(keyId, forKey: .keyId)
            try container.encode(username, forKey: .username)
        }
    }
}

// MARK: - Sample Data for Previews

extension ServerConnection {
    static let sample = ServerConnection(
        name: "Home Server",
        host: "192.168.1.100",
        port: 7681,
        connectionType: .http,
        authMethod: .none,
        isFavorite: true
    )

    static let sampleWithToken = ServerConnection(
        name: "Work Server",
        host: "work.example.com",
        port: 7682,
        connectionType: .https,
        authMethod: .token("abc123token"),
        useBiometrics: true,
        isFavorite: true
    )

    static let sampleWithBasicAuth = ServerConnection(
        name: "Production",
        host: "prod.example.com",
        port: 443,
        connectionType: .https,
        authMethod: .basicAuth(username: "admin"),
        useBiometrics: true
    )

    static let sampleSSH = ServerConnection(
        name: "Mac Mini",
        host: "192.168.1.50",
        port: 22,
        connectionType: .ssh,
        authMethod: .basicAuth(username: "admin"),
        useBiometrics: false,
        isFavorite: true
    )

    static let sampleSSHWithKey = ServerConnection(
        name: "Dev Server",
        host: "dev.example.com",
        port: 22,
        connectionType: .ssh,
        authMethod: .sshKey(keyId: UUID(), username: "developer"),
        useBiometrics: true
    )

    static let samples: [ServerConnection] = [
        .sample,
        .sampleWithToken,
        .sampleWithBasicAuth,
        .sampleSSH,
        .sampleSSHWithKey
    ]
}
