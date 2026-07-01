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

    /// Objective check for typed recall: the typed answer must equal the term
    /// after normalization (case, diacritics, punctuation, and spacing folded).
    static func matchesTerm(typed: String, term: String) -> Bool {
        let answer = normalized(typed)
        guard !answer.isEmpty else { return false }
        return answer == normalized(term)
    }

    // MARK: - Term masking

    /// Placeholder shown where the term has been masked out of a question.
    static let maskPlaceholder = "•••"

    /// Replaces occurrences of `term` in `text` with `maskPlaceholder`, so
    /// definitions and context sentences can be shown as questions without
    /// giving the answer away. Matching is case- and diacritic-insensitive,
    /// respects word boundaries ("cat" never masks "category"), spans
    /// multi-word terms, and also catches simple inflections: a trailing
    /// suffix of up to three letters ("coma" → "comas", "circumstance" →
    /// "circumstances") and the y→ie family ("fatality" → "fatalities").
    static func maskTerm(_ term: String, in text: String) -> String {
        let termTokens = normalized(term)
            .split(separator: " ")
            .map(String.init)
        guard !termTokens.isEmpty, !text.isEmpty else { return text }

        // Tokenize the original text into word ranges so replacements can be
        // made in place without disturbing punctuation or quoting.
        var words: [(range: Range<String.Index>, normalized: String)] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber {
                var end = text.index(after: index)
                while end < text.endIndex,
                      text[end].isLetter || text[end].isNumber {
                    end = text.index(after: end)
                }
                words.append((index..<end, normalized(String(text[index..<end]))))
                index = end
            } else {
                index = text.index(after: index)
            }
        }

        // Collect matching word sequences (non-overlapping, left to right).
        var maskRanges: [Range<String.Index>] = []
        var wordIndex = 0
        while wordIndex + termTokens.count <= words.count {
            if sequenceMatches(at: wordIndex, words: words, termTokens: termTokens) {
                let start = words[wordIndex].range.lowerBound
                let end = words[wordIndex + termTokens.count - 1].range.upperBound
                maskRanges.append(start..<end)
                wordIndex += termTokens.count
            } else {
                wordIndex += 1
            }
        }

        guard !maskRanges.isEmpty else { return text }
        var result = text
        for range in maskRanges.reversed() {
            result.replaceSubrange(range, with: maskPlaceholder)
        }
        return result
    }

    private static func sequenceMatches(
        at start: Int,
        words: [(range: Range<String.Index>, normalized: String)],
        termTokens: [String]
    ) -> Bool {
        for (offset, token) in termTokens.enumerated() {
            let word = words[start + offset].normalized
            let isLastToken = offset == termTokens.count - 1
            // Only the final token tolerates inflection; earlier tokens of a
            // multi-word term must match exactly ("give up" ≠ "given up").
            if isLastToken {
                if !wordMatchesToken(word, token) { return false }
            } else if word != token {
                return false
            }
        }
        return true
    }

    /// Exact match, a short trailing suffix (≤3 letters), or y→ie inflection.
    private static func wordMatchesToken(_ word: String, _ token: String) -> Bool {
        if word == token { return true }
        if word.hasPrefix(token), word.count - token.count <= 3 { return true }
        if token.hasSuffix("y") {
            let stem = String(token.dropLast())
            if word.hasPrefix(stem) {
                let suffix = String(word.dropFirst(stem.count))
                if ["ies", "ied", "ier", "iest"].contains(suffix) { return true }
            }
        }
        return false
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
