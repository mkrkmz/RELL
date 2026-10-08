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
    ///
    /// `unfamiliar` are the other words you're still learning (lowercased).
    /// A sentence full of them tests several words at once; the rotation
    /// keeps to the sentences with the fewest — ideally none, so the blank
    /// is the only thing you don't know yet (i+1, v15 S3).
    static func choice(for word: SavedWord, encounters: [WordEncounter], unfamiliar: Set<String> = []) -> Choice? {
        var candidates: [Choice] = []
        var unfamiliarCounts: [Int] = []
        var seen: Set<String> = []

        func add(_ sentence: String, source: WordEncounter?) {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = EncounterScanner.normalize(trimmed).lowercased()
            guard !trimmed.isEmpty, !seen.contains(key) else { return }
            let masked = QuizMatching.maskTerm(word.term, in: trimmed)
            guard masked != trimmed else { return }
            seen.insert(key)
            candidates.append(Choice(masked: masked, source: source))
            unfamiliarCounts.append(unfamiliarCount(in: masked, unfamiliar: unfamiliar))
        }

        add(word.sentence, source: nil)
        // Oldest first, so the order is stable as new encounters arrive —
        // newer ones join the end of the rotation instead of shifting it.
        for encounter in encounters.sorted(by: { $0.date < $1.date }) {
            add(encounter.sentence, source: encounter)
        }
        guard let fewest = unfamiliarCounts.min() else { return nil }
        let best = candidates.indices.filter { unfamiliarCounts[$0] == fewest }.map { candidates[$0] }
        return best[word.reviewCount % best.count]
    }

    /// How many of `unfamiliar` the sentence holds, as whole words.
    static func unfamiliarCount(in sentence: String, unfamiliar: Set<String>) -> Int {
        guard !unfamiliar.isEmpty else { return 0 }
        let lowered = sentence.lowercased()
        let tokens = Set(lowered.split { !$0.isLetter && $0 != "-" && $0 != "'" }.map(String.init))
        return unfamiliar.count { term in
            term.contains(" ") ? lowered.contains(term) : tokens.contains(term)
        }
    }
}
