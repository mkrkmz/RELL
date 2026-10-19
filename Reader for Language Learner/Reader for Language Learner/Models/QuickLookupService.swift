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

/// Where a hover answer came from — the balloon names it (v18 S4).
nonisolated enum HoverSource: Equatable, Sendable {
    /// The meaning you saved with the word.
    case notebook
    /// macOS's own dictionaries.
    case dictionary
    /// A model, named as "Apple · this Mac" or "Ollama · gemma… · this Mac".
    case model(String)

    var label: String {
        switch self {
        case .notebook: return String(localized: "Your word notebook")
        case .dictionary: return String(localized: "Dictionary")
        case .model(let name): return name
        }
    }
}

/// A hover answer and its source.
nonisolated struct HoverAnswer: Equatable, Sendable {
    let text: String
    let source: HoverSource
}

extension HoverAnswer {
    /// The short meaning a glance needs (the word card, the hover balloon):
    /// from the dictionary, the meaning only — not the entry's grammar,
    /// inflections and phrases (1.48.1, v19 S0); otherwise the text as is.
    @MainActor
    func shortMeaning(for term: String) -> String {
        guard source == .dictionary else { return text }
        let parsed = WordFillEngine.dictionaryAnswer(for: term, raw: text,
                                                     native: Language.storedNative, target: Language.storedTarget)
        return parsed[.meaning] ?? parsed[.definition] ?? text
    }
}

@MainActor
@Observable
final class QuickLookupService {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}


    @ObservationIgnored private var definitionCache = LRUCache<String, String>(capacity: 60)
    @ObservationIgnored private var nativeMeaningCache = LRUCache<String, String>(capacity: 60)
    @ObservationIgnored private var translationCache = LRUCache<String, String>(capacity: 40)
    /// Bumped whenever a translation is cached, so views that read the cache
    /// (the inspector's sentence card) update when the strip finishes.
    private(set) var translationRevision = 0
    /// System-dictionary hits and misses alike — a miss is worth remembering
    /// too, so a word the dictionaries don't cover isn't looked up on every
    /// hover of it.
    @ObservationIgnored private var systemDictionaryCache = LRUCache<String, String?>(capacity: 200)
    /// Which model wrote each cached definition or meaning, by the same key.
    @ObservationIgnored private var modelSources = LRUCache<String, String>(capacity: 120)
    /// Who translated each cached sentence (v18 S4: the strip says so).
    @ObservationIgnored private var translationSources = LRUCache<String, String>(capacity: 40)

    // MARK: - Hover dictionary (respects the user's language preference)

    /// Instant hover answer from a saved word or cache, in whichever language
    /// the reader chose. Returns nil when a fresh `hoverDefinition` is needed.
    func cachedHoverDefinition(for term: String, savedWordsStore: SavedWordsStore?) -> String? {
        cachedHoverAnswer(for: term, savedWordsStore: savedWordsStore)?.text
    }

    /// `cachedHoverDefinition`, with where the answer came from.
    func cachedHoverAnswer(for term: String, savedWordsStore: SavedWordsStore?) -> HoverAnswer? {
        let normalized = normalize(term)
        guard !normalized.isEmpty else { return nil }
        let saved = savedWordsStore?.words.first(where: { normalize($0.term) == normalized })
        switch HoverDictionaryLanguage.stored {
        case .target:
            if let saved {
                let definition = saved.reviewDefinition
                if !definition.isEmpty, definition != "No definition saved." {
                    return HoverAnswer(text: definition, source: .notebook)
                }
            }
            let key = cacheKey(term, language: Language.storedTarget)
            if let cached = definitionCache.get(key) {
                return HoverAnswer(text: cached, source: modelSource(key, module: .definitionEN))
            }
            return systemDictionaryDefinition(for: term, in: Language.storedTarget)
                .map { HoverAnswer(text: $0, source: .dictionary) }
        case .native:
            // Prefer a saved word's own native meaning before asking the model.
            if let meaning = saved?.llmOutputs[ModuleType.meaningTR.rawValue],
               !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return HoverAnswer(text: meaning, source: .notebook)
            }
            let key = cacheKey(term, language: Language.storedNative)
            if let cached = nativeMeaningCache.get(key) {
                return HoverAnswer(text: cached, source: modelSource(key, module: .meaningTR))
            }
            return systemDictionaryDefinition(for: term, in: Language.storedNative)
                .map { HoverAnswer(text: $0, source: .dictionary) }
        }
    }

    /// Fetches the hover answer in the reader's chosen language.
    func hoverDefinition(for term: String) async throws -> String {
        try await hoverAnswer(for: term).text
    }

    /// `hoverDefinition`, with the model that answered.
    func hoverAnswer(for term: String) async throws -> HoverAnswer {
        switch HoverDictionaryLanguage.stored {
        case .target:
            let text = try await definition(for: term)
            return HoverAnswer(text: text, source: modelSource(cacheKey(term, language: Language.storedTarget), module: .definitionEN))
        case .native:
            let text = try await nativeMeaning(for: term)
            return HoverAnswer(text: text, source: modelSource(cacheKey(term, language: Language.storedNative), module: .meaningTR))
        }
    }

    /// The model recorded for a cached answer, or the one that would answer now.
    private func modelSource(_ key: String, module: ModuleType) -> HoverSource {
        .model(modelSources.get(key) ?? Self.modelLabel(for: module))
    }

    /// "Apple · this Mac", or the provider, model and where it runs.
    static func modelLabel(for module: ModuleType?) -> String {
        if AppleOnDevice.currentRoute(for: module) == .appleOnDevice {
            return String(localized: "Apple · this Mac")
        }
        let configuration = LLMConfiguration()
        let place = configuration.runsOnThisMac ? String(localized: "this Mac") : String(localized: "cloud")
        return "\(configuration.providerType.localizedTitle) · \(configuration.model) · \(place)"
    }

    // MARK: - Definitions (hover)

    /// Instant definition from a saved word or the in-memory cache, if present.
    /// Returns nil when a fresh `definition(for:)` call is needed.
    func cachedDefinition(for term: String, savedWordsStore: SavedWordsStore?) -> String? {
        let normalized = normalize(term)
        guard !normalized.isEmpty else { return nil }

        if let saved = savedWordsStore?.words.first(where: { normalize($0.term) == normalized }) {
            let definition = saved.reviewDefinition
            if !definition.isEmpty, definition != "No definition saved." {
                return definition
            }
        }
        if let cached = definitionCache.get(cacheKey(term, language: Language.storedTarget)) {
            return cached
        }
        return systemDictionaryDefinition(for: term, in: Language.storedTarget)
    }

    /// macOS's own dictionaries, as an instant offline answer before the model
    /// is asked (L-E3). Only entries actually written in `language` are used —
    /// see `SystemDictionary` for why that filter has to be there.
    private func systemDictionaryDefinition(for term: String, in language: Language) -> String? {
        let key = cacheKey(term, language: language)
        if let cached = systemDictionaryCache.get(key) { return cached }
        let definition = SystemDictionary.definition(for: term, in: language)
        systemDictionaryCache.set(key, definition)
        return definition
    }

    func definition(for term: String) async throws -> String {
        let key = cacheKey(term, language: Language.storedTarget)
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
            temperature: module.recommendedTemperature,
            module: module
        )
        let cleaned = MarkdownUtils.sanitizeLLMOutput(text)
        definitionCache.set(key, cleaned)
        modelSources.set(key, Self.modelLabel(for: module))
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
        let key = cacheKey(term, language: Language.storedTarget)
        if let cached = definitionCache.get(key) {
            onToken(cached)
            return cached
        }

        let native = Language.storedNative
        let module = ModuleType.definitionEN
        let system = module.systemPrompt(customPreamble: "", nativeLanguage: native)
        let user = module.userPrompt(term: term, mode: .word, detail: .short, nativeLanguage: native)
        let maxTokens = module.recommendedMaxTokens(mode: .word, detail: .short, modelIdentifier: LLMConfiguration().model)

        // A model on this Mac waits its turn with everything else
        // (`LLMScheduler`); Apple's model and cloud servers don't queue.
        let provider = AppleOnDevice.recordedProvider(for: module, origin: .quickLookup)
        defer { provider.dropIfNotSent() }

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
        modelSources.set(key, Self.modelLabel(for: module))
        return cleaned
    }

    // MARK: - Native-language meaning (HUD subtitle)

    func cachedNativeMeaning(for term: String) -> String? {
        nativeMeaningCache.get(cacheKey(term, language: Language.storedNative))
    }

    func nativeMeaning(for term: String) async throws -> String {
        let key = cacheKey(term, language: Language.storedNative)
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
            temperature: module.recommendedTemperature,
            module: module
        )
        let cleaned = MarkdownUtils.sanitizeLLMOutput(text)
        nativeMeaningCache.set(key, cleaned)
        modelSources.set(key, Self.modelLabel(for: module))
        return cleaned
    }

    // MARK: - Translation (sentence strip)

    func cachedTranslation(for sentence: String) -> String? {
        guard !normalize(sentence).isEmpty else { return nil }
        return translationCache.get(cacheKey(sentence, language: Language.storedNative))
    }

    /// Who translated a cached sentence, for the strip's source line.
    func cachedTranslationSource(for sentence: String) -> String? {
        translationSources.get(cacheKey(sentence, language: Language.storedNative))
    }

    static var appleTranslationLabel: String { String(localized: "Apple Translation · this Mac") }

    /// Caches a translation made elsewhere (Apple Translation) so the strip
    /// finds it next time like any other.
    func storeTranslation(_ translation: String, for sentence: String) {
        guard !normalize(sentence).isEmpty else { return }
        let key = cacheKey(sentence, language: Language.storedNative)
        translationCache.set(key, translation)
        translationSources.set(key, Self.appleTranslationLabel)
        translationRevision += 1
    }

    func translate(sentence: String) async throws -> String {
        let key = cacheKey(sentence, language: Language.storedNative)
        if let cached = translationCache.get(key) { return cached }

        let native = Language.storedNative
        let system = """
        You are a translator for language learners.
        Output only the \(native.nativeName) translation of the sentence.
        No notes, no quotes, no preamble.
        """
        let user = "Translate to \(native.nativeName):\n\(sentence)"

        let text = try await run(system: system, user: user, maxTokens: 240, temperature: 0.1, module: nil)
        let cleaned = MarkdownUtils.sanitizeLLMOutput(text)
        translationCache.set(key, cleaned)
        translationSources.set(key, Self.modelLabel(for: nil))
        translationRevision += 1
        return cleaned
    }

    // MARK: - Shared

    private func run(
        system: String, user: String, maxTokens: Int, temperature: Double, module: ModuleType?
    ) async throws -> String {
        // A model on this Mac waits its turn with everything else
        // (`LLMScheduler`); Apple's model and cloud servers don't queue.
        let provider = AppleOnDevice.recordedProvider(for: module, origin: .quickLookup)
        defer { provider.dropIfNotSent() }

        return try await provider.chat(
            system: system,
            user: user,
            temperature: temperature,
            maxTokens: maxTokens,
            topP: 0.9
        )
    }

    private func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Caches are in-memory but survive language switches within a session —
    /// keying by the output language keeps a mid-session native/target change
    /// from serving stale-language entries.
    private func cacheKey(_ string: String, language: Language) -> String {
        "\(language.rawValue)|\(normalize(string))"
    }
}
