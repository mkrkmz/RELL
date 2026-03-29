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
    static let apiKeyKey       = "llmAPIKey"

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
        UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
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
