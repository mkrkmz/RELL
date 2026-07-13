//
//  LLMProvider.swift
//  Reader for Language Learner
//
//  Protocol abstraction for LLM backends.
//  Conforming types: LLMClient (LM Studio).
//  Future: OllamaProvider, OpenAIProvider, ClaudeProvider, etc.
//

import Foundation

// MARK: - Finish Reason

/// Why a streamed response ended, as reported by the server.
/// `nil` from `stream` means the server did not report one.
enum LLMFinishReason: Equatable, Sendable {
    /// Model finished naturally (`stop` / `end_turn`).
    case stop
    /// Response was cut off by the max_tokens limit (`length` / `max_tokens`).
    case length
    /// Any other server-reported reason.
    case other(String)

    init(openAIRawValue: String) {
        switch openAIRawValue {
        case "stop":   self = .stop
        case "length": self = .length
        default:       self = .other(openAIRawValue)
        }
    }

    init(anthropicRawValue: String) {
        switch anthropicRawValue {
        case "end_turn", "stop_sequence": self = .stop
        case "max_tokens":                self = .length
        default:                          self = .other(anthropicRawValue)
        }
    }
}

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
    /// Returns the server-reported finish reason, or `nil` when unavailable.
    @discardableResult
    func stream(
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> LLMFinishReason?
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

    /// Display name. Product names stay as-is; only "Compatible" translates.
    var localizedTitle: String {
        switch self {
        case .lmStudio, .ollama, .anthropic: return rawValue
        case .openAI: return String(localized: "OpenAI Compatible")
        }
    }

    var description: String {
        switch self {
        case .lmStudio:  return String(localized: "Local server via LM Studio")
        case .ollama:    return String(localized: "Local server via Ollama")
        case .openAI:    return String(localized: "OpenAI, OpenRouter, Together, or any compatible API")
        case .anthropic: return String(localized: "Anthropic Claude API")
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
