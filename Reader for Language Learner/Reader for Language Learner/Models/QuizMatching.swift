//
//  QuizMatching.swift
//  Reader for Language Learner
//
//  Pure helpers for the quiz modes: text normalization, typed-recall
//  matching, and multiple-choice distractor selection. Kept free of view
//  state so they can be unit-tested.
//

import Foundation

enum QuizMatching {

    /// Lowercased, diacritic-folded, punctuation-stripped, single-spaced.
    static func normalized(_ string: String) -> String {
        let folded = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let mapped = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped)
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Advisory check: does the typed answer overlap the definition?
    /// Substring match for short answers, or a shared significant token.
    static func looksCorrect(typed: String, definition: String) -> Bool {
        let answer = normalized(typed)
        guard answer.count >= 2 else { return false }
        let def = normalized(definition)
        if def.contains(answer) { return true }

        let answerTokens = Set(answer.split(separator: " ").map(String.init).filter { $0.count >= 3 })
        guard !answerTokens.isEmpty else { return false }
        let defTokens = Set(def.split(separator: " ").map(String.init))
        return !answerTokens.isDisjoint(with: defTokens)
    }

    /// Distinct distractor definitions for a multiple-choice question, in the
    /// order candidates are supplied (caller shuffles for display). Excludes
    /// empties, the placeholder, and anything matching the correct answer.
    static func distractors(correct: String, candidates: [String], limit: Int = 3) -> [String] {
        var seen: Set<String> = [normalized(correct)]
        var result: [String] = []
        for candidate in candidates {
            let key = normalized(candidate)
            guard !candidate.isEmpty,
                  candidate != "No definition saved.",
                  seen.insert(key).inserted else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }
}
