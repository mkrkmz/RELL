//
//  ClozeContext.swift
//  Reader for Language Learner
//
//  Which sentence a typed-recall card blanks the word out of (Roadmap v13
//  Sprint 1). Always the same saved sentence teaches the sentence, not the
//  word; rotating through the ones the reader has met it in since — from
//  their own books — asks for the word in a new context each time.
//

import Foundation

enum ClozeContext {

    struct Choice: Equatable {
        /// The sentence with the word blanked.
        let masked: String
        /// Where the sentence came from; nil for the one the word was saved from.
        let source: WordEncounter?
    }

    /// The card's sentence for this review. Rotates by review count, so the
    /// same card shows a different context each time it comes back, in a
    /// fixed order rather than at random — no two reviews in a row repeat
    /// while there's more than one.
    ///
    /// Only sentences where the word appears as saved are used: the answer is
    /// graded against the saved term, and a blank that stood for "ran" would
    /// mark a correct "ran" wrong and ask for "run" where it doesn't fit.
    static func choice(for word: SavedWord, encounters: [WordEncounter]) -> Choice? {
        var candidates: [Choice] = []
        var seen: Set<String> = []

        func add(_ sentence: String, source: WordEncounter?) {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = EncounterScanner.normalize(trimmed).lowercased()
            guard !trimmed.isEmpty, !seen.contains(key) else { return }
            let masked = QuizMatching.maskTerm(word.term, in: trimmed)
            guard masked != trimmed else { return }
            seen.insert(key)
            candidates.append(Choice(masked: masked, source: source))
        }

        add(word.sentence, source: nil)
        // Oldest first, so the order is stable as new encounters arrive —
        // newer ones join the end of the rotation instead of shifting it.
        for encounter in encounters.sorted(by: { $0.date < $1.date }) {
            add(encounter.sentence, source: encounter)
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[word.reviewCount % candidates.count]
    }
}
