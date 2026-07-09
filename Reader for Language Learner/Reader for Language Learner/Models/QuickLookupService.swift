//
//  QuickLookupService.swift
//  Reader for Language Learner
//
//  Lightweight, cache-first LLM calls for the reading-surface aids:
//  hover dictionary definitions and the sentence translation strip.
//  Reuses the configured provider, ModuleType prompts, and an AsyncLimiter
//  so it never floods a local server.
//

import Foundation
import os

@MainActor
@Observable
final class QuickLookupService {

    @ObservationIgnored private var definitionCache = LRUCache<String, String>(capacity: 60)
    @ObservationIgnored private var nativeMeaningCache = LRUCache<String, String>(capacity: 60)
    @ObservationIgnored private var translationCache = LRUCache<String, String>(capacity: 40)
    @ObservationIgnored private let gate = AsyncLimiter(limit: 1)

    // MARK: - Definitions (hover)

    /// Instant definition from a saved word or the in-memory cache, if present.
    /// Returns nil when a fresh `definition(for:)` call is needed.
    func cachedDefinition(for term: String, savedWordsStore: SavedWordsStore?) -> String? {
        let key = normalize(term)
        guard !key.isEmpty else { return nil }

        if let saved = savedWordsStore?.words.first(where: { normalize($0.term) == key }) {
            let definition = saved.reviewDefinition
            if !definition.isEmpty, definition != "No definition saved." {
                return definition
            }
        }
        return definitionCache.get(key)
    }

    func definition(for term: String) async throws -> String {
        let key = normalize(term)
        if let cached = definitionCache.get(key) { return cached }

        let native = Language.storedNative
        let module = ModuleType.definitionEN
        let system = module.systemPrompt(customPreamble: "", nativeLanguage: native)
        let user = module.userPrompt(term: term, mode: .word, detail: .short, nativeLanguage: native)
        let maxTokens = module.recommendedMaxTokens(mode: .word, detail: .short, modelIdentifier: LLMConfiguration().model)

        let text = try await run(
            system: system,
            user: user,
            maxTokens: maxTokens,
            temperature: module.recommendedTemperature
        )
        let cleaned = MarkdownUtils.sanitizeLLMOutput(text)
        definitionCache.set(key, cleaned)
        return cleaned
    }

    /// Streams the definition token-by-token — `onToken` receives the full
    /// accumulated text so far (matching InspectorView's append pattern) on
    /// @MainActor. Cache hits still call `onToken` once with the full text
    /// so callers don't need a separate cache-first branch.
    @discardableResult
    func streamDefinition(
        for term: String,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        let key = normalize(term)
        if let cached = definitionCache.get(key) {
            onToken(cached)
            return cached
        }

        let native = Language.storedNative
        let module = ModuleType.definitionEN
        let system = module.systemPrompt(customPreamble: "", nativeLanguage: native)
        let user = module.userPrompt(term: term, mode: .word, detail: .short, nativeLanguage: native)
        let maxTokens = module.recommendedMaxTokens(mode: .word, detail: .short, modelIdentifier: LLMConfiguration().model)

        let local = isLocalProvider
        if local { await gate.acquire() }
        defer { if local { gate.release() } }

        let provider = LLMConfiguration().makeProvider()
        var accumulated = ""
        _ = try await provider.stream(
            system: system,
            user: user,
            temperature: module.recommendedTemperature,
            maxTokens: maxTokens,
            topP: 0.9
        ) { token in
            accumulated += token
            onToken(accumulated)
        }
        let cleaned = MarkdownUtils.sanitizeLLMOutput(accumulated)
        definitionCache.set(key, cleaned)
        return cleaned
    }

    // MARK: - Native-language meaning (HUD subtitle)

    func cachedNativeMeaning(for term: String) -> String? {
        nativeMeaningCache.get(normalize(term))
    }

    func nativeMeaning(for term: String) async throws -> String {
        let key = normalize(term)
        if let cached = nativeMeaningCache.get(key) { return cached }

        let native = Language.storedNative
        let module = ModuleType.meaningTR
        let system = module.systemPrompt(customPreamble: "", nativeLanguage: native)
        let user = module.userPrompt(term: term, mode: .word, detail: .short, nativeLanguage: native)
        let maxTokens = module.recommendedMaxTokens(mode: .word, detail: .short, modelIdentifier: LLMConfiguration().model)

        let text = try await run(
            system: system,
            user: user,
            maxTokens: maxTokens,
            temperature: module.recommendedTemperature
        )
        let cleaned = MarkdownUtils.sanitizeLLMOutput(text)
        nativeMeaningCache.set(key, cleaned)
        return cleaned
    }

    // MARK: - Translation (sentence strip)

    func cachedTranslation(for sentence: String) -> String? {
        let key = normalize(sentence)
        guard !key.isEmpty else { return nil }
        return translationCache.get(key)
    }

    func translate(sentence: String) async throws -> String {
        let key = normalize(sentence)
        if let cached = translationCache.get(key) { return cached }

        let native = Language.storedNative
        let system = """
        You are a translator for language learners.
        Output only the \(native.nativeName) translation of the sentence.
        No notes, no quotes, no preamble.
        """
        let user = "Translate to \(native.nativeName):\n\(sentence)"

        let text = try await run(system: system, user: user, maxTokens: 240, temperature: 0.1)
        let cleaned = MarkdownUtils.sanitizeLLMOutput(text)
        translationCache.set(key, cleaned)
        return cleaned
    }

    // MARK: - Shared

    private func run(system: String, user: String, maxTokens: Int, temperature: Double) async throws -> String {
        let local = isLocalProvider
        if local { await gate.acquire() }
        defer { if local { gate.release() } }

        let provider = LLMConfiguration().makeProvider()
        return try await provider.chat(
            system: system,
            user: user,
            temperature: temperature,
            maxTokens: maxTokens,
            topP: 0.9
        )
    }

    private var isLocalProvider: Bool {
        let type = LLMConfiguration().providerType
        return type == .lmStudio || type == .ollama
    }

    private func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
