//
//  LexicalProfileService.swift
//  Reader for Language Learner
//
//  Computes and caches document coverage profiles (Roadmap v9 Sprint 3, L3).
//  Tokenizing and lemmatizing a chapter is far too slow for the main actor, so
//  the pass runs on a detached task and publishes its result back; a generation
//  counter drops results that arrive after the reader has moved on.
//

import Foundation

@MainActor
@Observable
final class LexicalProfileService {

    /// Profile of the passage currently on screen, or nil before the first
    /// pass completes.
    private(set) var current: LexicalProfile?
    private(set) var isComputing = false

    /// Cache keyed by document + passage so flipping back and forth is free.
    @ObservationIgnored private var cache = LRUCache<String, LexicalProfile>(capacity: 40)
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Profiles `text` against the reader's vocabulary. Cheap and cached when
    /// the same passage comes back around.
    func profile(
        text: String,
        cacheKey: String,
        language: Language,
        savedWordsStore: SavedWordsStore
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            current = nil
            return
        }

        if let cached = cache.get(cacheKey) {
            current = cached
            return
        }

        generation += 1
        let generationAtStart = generation
        let keys = savedWordsStore.lemmaKeySets(for: language)

        task?.cancel()
        isComputing = true
        task = Task { [weak self] in
            let profile = await Task.detached(priority: .utility) {
                LexicalProfileBuilder.profile(
                    text: trimmed,
                    language: language,
                    masteredKeys: keys.mastered,
                    learningKeys: keys.learning
                )
            }.value

            guard let self, !Task.isCancelled else { return }
            // Drop a result the reader has already navigated away from.
            guard generationAtStart == self.generation else { return }
            self.cache.set(cacheKey, profile)
            self.current = profile
            self.isComputing = false
        }
    }

    /// Clears cached profiles — call when the vocabulary changes enough that
    /// old coverage numbers would be stale (e.g. a bulk import or delete).
    func invalidate() {
        cache.removeAll()
        current = nil
    }
}
