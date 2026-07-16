//
//  LLMConfiguration.swift
//  Reader for Language Learner
//

import Foundation

/// Central configuration for the LLM backend.
/// Values are persisted in UserDefaults and exposed as @AppStorage keys.
struct LLMConfiguration {

    // MARK: - UserDefaults Keys

    static let providerTypeKey = "llmProviderType"
    static let serverURLKey    = "llmServerURL"
    static let modelKey        = "llmModel"
    static let timeoutKey      = "llmRequestTimeout"
    /// Legacy UserDefaults key — the key now lives in the Keychain; this name
    /// survives only for the one-time migration and as the Keychain account.
    static let apiKeyKey       = "llmAPIKey"

    // MARK: - Keychain

    static var keychainService: String {
        Bundle.main.bundleIdentifier ?? "com.rell.app"
    }

    // MARK: - Defaults

    static let defaultProviderType: LLMProviderType = .lmStudio
    static let defaultServerURL = "http://127.0.0.1:1234"
    static let defaultModel     = "google/gemma-3-4b"
    static let defaultTimeout: Double = 30
    static let minTimeout: Double     = 10
    static let maxTimeout: Double     = 120

    // MARK: - Current values (read from UserDefaults)

    var providerType: LLMProviderType {
        guard let raw = UserDefaults.standard.string(forKey: Self.providerTypeKey),
              let type = LLMProviderType(rawValue: raw) else {
            return Self.defaultProviderType
        }
        return type
    }

    var serverURL: String {
        UserDefaults.standard.string(forKey: Self.serverURLKey) ?? Self.defaultServerURL
    }

    var model: String {
        UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
    }

    var timeout: Double {
        let stored = UserDefaults.standard.double(forKey: Self.timeoutKey)
        return stored > 0 ? stored : Self.defaultTimeout
    }

    var apiKey: String {
        Self.storedAPIKey
    }

    // MARK: - API key storage (Keychain)

    /// Reads the key from the Keychain, migrating a legacy plaintext
    /// UserDefaults value on first access.
    static var storedAPIKey: String {
        migrateLegacyAPIKeyIfNeeded()
        return KeychainHelper.read(service: keychainService, account: apiKeyKey) ?? ""
    }

    /// Persists (or, for an empty string, removes) the key. No-op when the
    /// value is unchanged, so callers can write on every UI change safely.
    static func setAPIKey(_ value: String) {
        guard value != storedAPIKey else { return }
        if value.isEmpty {
            KeychainHelper.delete(service: keychainService, account: apiKeyKey)
        } else {
            KeychainHelper.write(value, service: keychainService, account: apiKeyKey)
        }
    }

    /// One-time move of the pre-v1.23 plaintext UserDefaults key into the
    /// Keychain. An existing Keychain value wins; the plaintext copy is
    /// deleted either way.
    private static func migrateLegacyAPIKeyIfNeeded() {
        migrateLegacyAPIKey(defaults: .standard, service: keychainService)
    }

    /// Parameterized for tests — production always calls the private wrapper
    /// with the standard defaults + real service.
    static func migrateLegacyAPIKey(defaults: UserDefaults, service: String) {
        guard let legacy = defaults.string(forKey: apiKeyKey) else { return }
        if !legacy.isEmpty,
           KeychainHelper.read(service: service, account: apiKeyKey) == nil {
            KeychainHelper.write(legacy, service: service, account: apiKeyKey)
        }
        defaults.removeObject(forKey: apiKeyKey)
    }

    // MARK: - Factory

    /// Returns a fully configured LLMProvider using the current settings.
    func makeProvider() -> any LLMProvider {
        switch providerType {
        case .lmStudio, .ollama, .openAI:
            var client = LLMClient()
            client.baseURLString = serverURL
            client.model = model
            client.apiKey = providerType.requiresAPIKey ? apiKey : nil
            client.session = LLMClient.makeSession(timeout: timeout)
            return client
        case .anthropic:
            var client = AnthropicClient()
            client.baseURLString = serverURL
            client.model = model
            client.apiKey = apiKey
            client.session = AnthropicClient.makeSession(timeout: timeout)
            return client
        }
    }

    /// Legacy convenience — returns LLMClient for backward compatibility.
    func makeClient() -> LLMClient {
        var client = LLMClient()
        client.baseURLString = serverURL
        client.model = model
        client.apiKey = providerType.requiresAPIKey ? apiKey : nil
        client.session = LLMClient.makeSession(timeout: timeout)
        return client
    }
}
