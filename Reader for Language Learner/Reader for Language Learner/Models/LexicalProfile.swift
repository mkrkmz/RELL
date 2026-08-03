//
//  LexicalProfile.swift
//  Reader for Language Learner
//
//  "Is this book at my level?" (Roadmap v9 Sprint 3, L3).
//
//  Comprehensible-input research says reading works best when you already know
//  most of the words on the page. This profiles a document against the user's
//  own vocabulary: what share of its running words are ones they've mastered,
//  are still learning, or have never saved. Matching is lemma-based (L2), so
//  an inflected form in the text counts against the dictionary word they saved.
//
//  The math is a pure value type so it can be computed off the main actor and
//  unit-tested without a document or a store.
//

import Foundation

/// Coverage of one document by the reader's saved vocabulary.
struct LexicalProfile: Equatable, Codable {
    /// Running words counted (tokens, not distinct words).
    var totalTokens: Int
    /// Tokens whose dictionary form the reader has mastered.
    var masteredTokens: Int
    /// Tokens the reader has saved but is still learning.
    var learningTokens: Int

    /// Tokens the reader has never saved.
    var unknownTokens: Int { max(0, totalTokens - masteredTokens - learningTokens) }

    /// Share (0…1) of the text the reader already knows well.
    var masteredShare: Double {
        totalTokens > 0 ? Double(masteredTokens) / Double(totalTokens) : 0
    }

    /// Share (0…1) covered by any saved word, mastered or still learning —
    /// the "how much of this can I follow" number.
    var knownShare: Double {
        totalTokens > 0 ? Double(masteredTokens + learningTokens) / Double(totalTokens) : 0
    }

    var unknownShare: Double {
        totalTokens > 0 ? Double(unknownTokens) / Double(totalTokens) : 0
    }

    /// Rough readability verdict, on the comprehensible-input rule of thumb
    /// that ~95%+ known words reads comfortably and below ~80% is a slog.
    enum Difficulty: String, Codable {
        case comfortable    // ≥ 95% known
        case challenging    // 80–95%
        case demanding      // < 80%
    }

    var difficulty: Difficulty {
        switch knownShare {
        case 0.95...: return .comfortable
        case 0.80..<0.95: return .challenging
        default: return .demanding
        }
    }

    static let empty = LexicalProfile(totalTokens: 0, masteredTokens: 0, learningTokens: 0)
}

enum LexicalProfileBuilder {

    /// Profiles `text` against the reader's vocabulary.
    ///
    /// - Parameters:
    ///   - masteredKeys: lemma match keys of words the reader has mastered.
    ///   - learningKeys: lemma match keys of words still being learned.
    ///
    /// Pure and `nonisolated`-safe: callers pass pre-computed key sets so the
    /// whole pass can run on a background task.
    static func profile(
        text: String,
        language: Language?,
        masteredKeys: Set<String>,
        learningKeys: Set<String>
    ) -> LexicalProfile {
        let keys = LemmaMatcher.matchKeys(in: text, language: language)
        guard !keys.isEmpty else { return .empty }

        var mastered = 0
        var learning = 0
        for key in keys {
            if masteredKeys.contains(key) {
                mastered += 1
            } else if learningKeys.contains(key) {
                learning += 1
            }
        }
        return LexicalProfile(
            totalTokens: keys.count,
            masteredTokens: mastered,
            learningTokens: learning
        )
    }
}
