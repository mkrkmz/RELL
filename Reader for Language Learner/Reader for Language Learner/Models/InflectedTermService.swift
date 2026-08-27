//
//  InflectedTermService.swift
//  Reader for Language Learner
//
//  Lemma-aware saved-word highlighting (Roadmap v10 Sprint 2, L-V1).
//
//  Both readers underline saved words by matching their literal text, so a
//  saved "run" never lights up the book's "ran". Asking the lemmatizer per
//  term per page is out of the question on the main actor, so the pass runs
//  the other way around: lemmatize the passage once, off-main, keep the
//  surface forms whose dictionary word the reader has saved, and hand those
//  to the existing string-matching highlighters.
//
//  Results are cached per passage. A pass that misses returns nothing at all
//  and calls back when it lands, so highlighting never blocks on the tagger —
//  the literal matches are already on screen by then.
//

import Foundation

@MainActor
final class InflectedTermService {

    private var cache = LRUCache<String, [String]>(capacity: 60)
    /// Passages whose pass is running, so a re-entrant refresh (the callback
    /// re-runs highlighting, which asks again) doesn't start a second one.
    private var inFlight: Set<String> = []

    /// The inflected forms of saved vocabulary that occur in this passage, or
    /// an empty array while the first pass for it is still running.
    ///
    /// - Parameters:
    ///   - passageKey: stable identity of the page/chapter within its document.
    ///   - keys: lemma match keys of the saved vocabulary
    ///     (`SavedWordsStore.lemmaKeys(for:)`).
    ///   - text: the passage, evaluated only on a cache miss.
    ///   - onReady: called on the main actor when a pass finds something the
    ///     caller didn't already have — re-run the highlight refresh there.
    func surfaceForms(
        passageKey: String,
        keys: Set<String>,
        language: Language,
        text: @autoclosure () -> String?,
        onReady: @escaping @MainActor () -> Void
    ) -> [String] {
        guard !keys.isEmpty else { return [] }

        // The vocabulary is part of the identity: saving a word has to produce
        // a new pass rather than a stale hit, and an entry for the previous
        // vocabulary simply ages out of the LRU.
        let cacheKey = "\(passageKey)|\(language.rawValue)|\(keys.hashValue)"
        if let cached = cache.get(cacheKey) { return cached }
        guard !inFlight.contains(cacheKey),
              let passage = text(),
              !passage.isEmpty
        else { return [] }

        inFlight.insert(cacheKey)
        Task { [weak self] in
            let forms = await Task.detached(priority: .utility) {
                LemmaMatcher.surfaceForms(in: passage, matchingKeys: keys, language: language)
            }.value

            guard let self else { return }
            self.cache.set(cacheKey, forms)
            self.inFlight.remove(cacheKey)
            // Nothing found means nothing to redraw — the literal matches on
            // screen are already the whole answer for this passage.
            guard !forms.isEmpty else { return }
            onReady()
        }
        return []
    }

    /// Drops every cached pass. For vocabulary-wide upheaval (bulk import or
    /// delete); ordinary edits fall out of the key.
    func invalidate() {
        cache.removeAll()
    }
}
