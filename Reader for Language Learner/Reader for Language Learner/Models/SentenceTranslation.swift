//
//  SentenceTranslation.swift
//  Reader for Language Learner
//
//  A saved sentence's translation (Roadmap v19 Sprint 2): the one the
//  sentence strip already made (Apple Translation or the model, cached),
//  else asked for once after saving. Fill Missing leaves sentences alone;
//  the sentence's page has a Translate button when this found nothing.
//

import Foundation

@MainActor
enum SentenceTranslation {
    /// Stores the translation of the saved sentence `wordID` unless it has
    /// one. Quiet on failure: the sentence is saved either way.
    static func fill(wordID: UUID, store: SavedWordsStore, quickLookup: QuickLookupService) async {
        guard let word = store.word(withID: wordID), word.isSentence, word.translation == nil else { return }
        let text: String?
        if let cached = quickLookup.cachedTranslation(for: word.term) {
            text = cached
        } else {
            text = try? await quickLookup.translate(sentence: word.term)
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              var latest = store.word(withID: wordID), latest.translation == nil else { return }
        latest.llmOutputs[SavedWord.translationKey] = text
        store.update(latest)
    }
}
