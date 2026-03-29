//
//  LLMProvider.swift
//  Reader for Language Learner
//
//  Protocol abstraction for LLM backends.
//  Conforming types: LLMClient (LM Studio).
//  Future: OllamaProvider, OpenAIProvider, ClaudeProvider, etc.
//

import Foundation

// MARK: - Protocol

/// Defines the minimum contract for an LLM backend used by RELL.
protocol LLMProvider {
    /// Non-streaming single-turn chat.
    func chat(
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double
    ) async throws -> String

    /// Streaming chat — `onToken` is called on @MainActor for each delta chunk.
    func stream(
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws
}

// MARK: - LLMClient conformance

extension LLMClient: LLMProvider {}

// MARK: - Provider Type (for Settings picker)

enum LLMProviderType: String, CaseIterable, Identifiable {
    case lmStudio  = "LM Studio"
    case ollama    = "Ollama"
    case openAI    = "OpenAI Compatible"
    case anthropic = "Anthropic Claude"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .lmStudio:  return "server.rack"
        case .ollama:    return "desktopcomputer"
        case .openAI:    return "cloud"
        case .anthropic: return "brain"
        }
    }

    var description: String {
        switch self {
        case .lmStudio:  return "Local server via LM Studio"
        case .ollama:    return "Local server via Ollama"
        case .openAI:    return "OpenAI, OpenRouter, Together, or any compatible API"
        case .anthropic: return "Anthropic Claude API"
        }
    }

    var defaultServerURL: String {
        switch self {
        case .lmStudio:  return "http://127.0.0.1:1234"
        case .ollama:    return "http://127.0.0.1:11434"
        case .openAI:    return "https://api.openai.com"
        case .anthropic: return "https://api.anthropic.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .lmStudio:  return "google/gemma-3-4b"
        case .ollama:    return "llama3.2"
        case .openAI:    return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .lmStudio, .ollama: return false
        case .openAI, .anthropic: return true
        }
    }
}
