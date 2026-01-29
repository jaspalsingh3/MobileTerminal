//
//  SSHKeyManager.swift
//  Mobile Terminal
//
//  Manages SSH keys for server authentication
//

import Foundation
import Security

// MARK: - SSH Key Model

struct SSHKey: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var publicKey: String
    var keyType: SSHKeyType
    var createdAt: Date
    var lastUsed: Date?
    var comment: String?

    // Private key is stored separately in Keychain
    var hasPrivateKey: Bool

    init(
        id: UUID = UUID(),
        name: String,
        publicKey: String,
        keyType: SSHKeyType = .ed25519,
        comment: String? = nil,
        hasPrivateKey: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.keyType = keyType
        self.comment = comment
        self.hasPrivateKey = hasPrivateKey
        self.createdAt = createdAt
        self.lastUsed = nil
    }
}

enum SSHKeyType: String, Codable, CaseIterable {
    case rsa = "RSA"
    case ed25519 = "Ed25519"
    case ecdsa = "ECDSA"

    var algorithmName: String {
        switch self {
        case .rsa: return "ssh-rsa"
        case .ed25519: return "ssh-ed25519"
        case .ecdsa: return "ecdsa-sha2-nistp256"
        }
    }

    var defaultBits: Int {
        switch self {
        case .rsa: return 4096
        case .ed25519: return 256
        case .ecdsa: return 256
        }
    }
}

// MARK: - SSH Key Manager

final class SSHKeyManager: ObservableObject {
    static let shared = SSHKeyManager()

    @Published var keys: [SSHKey] = []
    @Published var isLoading = false

    private let keychainService = "com.mobileterminal.sshkeys"
    private let storageKey = "com.mobileterminal.sshkeys.metadata"

    private var storageURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("ssh_keys.json")
    }

    private init() {
        loadKeys()
    }

    private func loadKeys() {
        do {
            let data = try Data(contentsOf: storageURL)
            keys = try JSONDecoder().decode([SSHKey].self, from: data)
        } catch {
            keys = []
        }
    }

    // MARK: - Key Management

    /// Import an existing SSH key pair
    func importKey(
        name: String,
        publicKey: String,
        privateKey: String,
        passphrase: String? = nil,
        comment: String? = nil
    ) throws -> SSHKey {
        // Validate the key format
        guard isValidPublicKey(publicKey) else {
            throw SSHKeyError.invalidPublicKey
        }

        // Detect key type from public key
        let keyType = detectKeyType(from: publicKey)

        // Create the key model
        let key = SSHKey(
            name: name,
            publicKey: publicKey.trimmingCharacters(in: .whitespacesAndNewlines),
            keyType: keyType,
            comment: comment,
            hasPrivateKey: !privateKey.isEmpty
        )

        // Store private key in Keychain
        if !privateKey.isEmpty {
            savePrivateKey(privateKey, for: key.id)
        }

        // Store passphrase if provided
        if let passphrase = passphrase, !passphrase.isEmpty {
            savePassphrase(passphrase, for: key.id)
        }

        // Add to list and persist
        keys.append(key)
        saveKeys()

        return key
    }

    /// Import from a file URL (e.g., from Files app)
    func importKeyFromFile(publicKeyURL: URL, privateKeyURL: URL?, name: String) throws -> SSHKey {
        // Read public key
        let publicKey = try String(contentsOf: publicKeyURL, encoding: .utf8)

        // Read private key if provided
        var privateKey = ""
        if let privateURL = privateKeyURL {
            privateKey = try String(contentsOf: privateURL, encoding: .utf8)
        }

        return try importKey(name: name, publicKey: publicKey, privateKey: privateKey)
    }

    /// Delete an SSH key
    func deleteKey(_ key: SSHKey) {
        // Remove from Keychain
        deletePrivateKey(for: key.id)
        deletePassphrase(for: key.id)

        // Remove from list
        keys.removeAll { $0.id == key.id }
        saveKeys()
    }

    /// Get a key by ID
    func getKey(byId id: UUID) -> SSHKey? {
        return keys.first { $0.id == id }
    }

    /// Update key metadata
    func updateKey(_ key: SSHKey) {
        if let index = keys.firstIndex(where: { $0.id == key.id }) {
            keys[index] = key
            saveKeys()
        }
    }

    /// Mark key as recently used
    func markKeyAsUsed(_ key: SSHKey) {
        if let index = keys.firstIndex(where: { $0.id == key.id }) {
            keys[index].lastUsed = Date()
            saveKeys()
        }
    }

    // MARK: - Private Key Access

    /// Get the private key for a key ID (requires authentication)
    func getPrivateKey(for keyId: UUID) -> String? {
        let key = "private.\(keyId.uuidString)"
        return getFromKeychain(key: key)
    }

    /// Get passphrase for a key
    func getPassphrase(for keyId: UUID) -> String? {
        let key = "passphrase.\(keyId.uuidString)"
        return getFromKeychain(key: key)
    }

    /// Check if a key has a passphrase
    func hasPassphrase(for keyId: UUID) -> Bool {
        return getPassphrase(for: keyId) != nil
    }

    // MARK: - Key Generation (placeholder - actual generation requires OpenSSL or similar)

    /// Generate a new SSH key pair
    /// Note: Full key generation would require linking against a crypto library
    /// For now, this creates a placeholder that users should replace with a real key
    func generateKeyPlaceholder(name: String, type: SSHKeyType) -> SSHKey {
        let placeholder = SSHKey(
            name: name,
            publicKey: "# Key generation requires external tools. Please import your keys.",
            keyType: type,
            hasPrivateKey: false
        )

        keys.append(placeholder)
        saveKeys()

        return placeholder
    }

    // MARK: - Validation

    private func isValidPublicKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("ssh-rsa") ||
               trimmed.hasPrefix("ssh-ed25519") ||
               trimmed.hasPrefix("ecdsa-sha2")
    }

    private func detectKeyType(from publicKey: String) -> SSHKeyType {
        let trimmed = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ssh-ed25519") {
            return .ed25519
        } else if trimmed.hasPrefix("ecdsa-sha2") {
            return .ecdsa
        } else {
            return .rsa
        }
    }

    // MARK: - Keychain Operations

    private func savePrivateKey(_ privateKey: String, for keyId: UUID) {
        let key = "private.\(keyId.uuidString)"
        saveToKeychain(key: key, value: privateKey)
    }

    private func deletePrivateKey(for keyId: UUID) {
        let key = "private.\(keyId.uuidString)"
        deleteFromKeychain(key: key)
    }

    private func savePassphrase(_ passphrase: String, for keyId: UUID) {
        let key = "passphrase.\(keyId.uuidString)"
        saveToKeychain(key: key, value: passphrase)
    }

    private func deletePassphrase(for keyId: UUID) {
        let key = "passphrase.\(keyId.uuidString)"
        deleteFromKeychain(key: key)
    }

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Persistence

    private func saveKeys() {
        do {
            let data = try JSONEncoder().encode(keys)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save SSH keys: \(error)")
        }
    }

    // MARK: - Export

    /// Export public key to clipboard or share
    func exportPublicKey(_ key: SSHKey) -> String {
        return key.publicKey
    }

    /// Get the fingerprint of a public key
    func getFingerprint(for key: SSHKey) -> String {
        // Simple placeholder - real implementation would compute SHA256 fingerprint
        let data = Data(key.publicKey.utf8)
        let hash = data.hashValue
        return String(format: "SHA256:%08X", abs(hash))
    }
}

// MARK: - Errors

enum SSHKeyError: Error, LocalizedError {
    case invalidPublicKey
    case invalidPrivateKey
    case keyNotFound
    case importFailed(String)
    case keychainError

    var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "Invalid public key format. Key should start with ssh-rsa, ssh-ed25519, or ecdsa-sha2."
        case .invalidPrivateKey:
            return "Invalid private key format."
        case .keyNotFound:
            return "SSH key not found."
        case .importFailed(let reason):
            return "Failed to import key: \(reason)"
        case .keychainError:
            return "Failed to access secure storage."
        }
    }
}

// MARK: - Sample Data

extension SSHKey {
    static let sample = SSHKey(
        name: "My MacBook",
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@macbook",
        keyType: .ed25519,
        comment: "Personal laptop key"
    )

    static let sampleRSA = SSHKey(
        name: "Work Laptop",
        publicKey: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB... work@company",
        keyType: .rsa,
        comment: "Work computer"
    )
}
