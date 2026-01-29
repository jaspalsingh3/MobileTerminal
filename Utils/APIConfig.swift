//
//  APIConfig.swift
//  Mobile Terminal
//
//  Secure API key storage using iOS Keychain (legacy - kept for migration)
//

import Foundation
import Security

class APIConfig {
    static let shared = APIConfig()

    private let service = "com.sanatanstories.api"
    private let accountFalAPI = "fal-api-key"
    private let accountClaudeAPI = "claude-api-key"
    private let accountOpenAIAPI = "openai-api-key"

    private init() {}

    // MARK: - FAL API Key

    /// Save the FAL API key to Keychain
    func saveAPIKey(_ apiKey: String) {
        save(key: accountFalAPI, value: apiKey)
    }

    /// Retrieve the FAL API key from Keychain
    func getAPIKey() -> String? {
        return get(key: accountFalAPI)
    }

    /// Delete the FAL API key from Keychain
    func deleteAPIKey() {
        delete(key: accountFalAPI)
    }

    /// Check if FAL API key is configured
    var isConfigured: Bool {
        guard let key = getAPIKey() else { return false }
        return !key.isEmpty
    }

    // MARK: - Claude API Key

    /// Save the Claude API key to Keychain
    func saveClaudeAPIKey(_ apiKey: String) {
        save(key: accountClaudeAPI, value: apiKey)
    }

    /// Retrieve the Claude API key from Keychain
    func getClaudeAPIKey() -> String? {
        return get(key: accountClaudeAPI)
    }

    /// Delete the Claude API key from Keychain
    func deleteClaudeAPIKey() {
        delete(key: accountClaudeAPI)
    }

    /// Check if Claude API key is configured
    var isClaudeConfigured: Bool {
        guard let key = getClaudeAPIKey() else { return false }
        return !key.isEmpty
    }

    // MARK: - OpenAI API Key (Image Generation)

    /// Save the OpenAI API key to Keychain
    func saveOpenAIAPIKey(_ apiKey: String) {
        save(key: accountOpenAIAPI, value: apiKey)
    }

    /// Retrieve the OpenAI API key from Keychain
    func getOpenAIAPIKey() -> String? {
        return get(key: accountOpenAIAPI)
    }

    /// Delete the OpenAI API key from Keychain
    func deleteOpenAIAPIKey() {
        delete(key: accountOpenAIAPI)
    }

    /// Check if OpenAI API key is configured
    var isOpenAIConfigured: Bool {
        guard let key = getOpenAIAPIKey() else { return false }
        return !key.isEmpty
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
