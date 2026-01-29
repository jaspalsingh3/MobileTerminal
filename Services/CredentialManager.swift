//
//  CredentialManager.swift
//  Mobile Terminal
//
//  Secure credential storage using iOS Keychain
//

import Foundation
import Security

final class CredentialManager {
    static let shared = CredentialManager()

    private let service = "com.mobileterminal.credentials"

    private init() {}

    // MARK: - Password Management

    /// Save password for a server
    func savePassword(_ password: String, for serverId: UUID) {
        let key = "server.\(serverId.uuidString).password"
        save(key: key, value: password)
    }

    /// Get password for a server
    func getPassword(for serverId: UUID) -> String? {
        let key = "server.\(serverId.uuidString).password"
        return get(key: key)
    }

    /// Delete password for a server
    func deletePassword(for serverId: UUID) {
        let key = "server.\(serverId.uuidString).password"
        delete(key: key)
    }

    // MARK: - Token Management

    /// Save token for a server
    func saveToken(_ token: String, for serverId: UUID) {
        let key = "server.\(serverId.uuidString).token"
        save(key: key, value: token)
    }

    /// Get token for a server
    func getToken(for serverId: UUID) -> String? {
        let key = "server.\(serverId.uuidString).token"
        return get(key: key)
    }

    /// Delete token for a server
    func deleteToken(for serverId: UUID) {
        let key = "server.\(serverId.uuidString).token"
        delete(key: key)
    }

    // MARK: - Bulk Operations

    /// Delete all credentials for a server
    func deleteCredentials(for serverId: UUID) {
        deletePassword(for: serverId)
        deleteToken(for: serverId)
    }

    // MARK: - Generic Keychain Operations

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            print("Keychain save failed with status: \(status)")
        }
    }

    private func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
