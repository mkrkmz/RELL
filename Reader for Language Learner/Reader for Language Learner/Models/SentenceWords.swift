//
//  SentenceWords.swift
//  Reader for Language Learner
//
//  The words inside a saved sentence (Roadmap v19 Sprint 2): the ones
//  already saved (in any form — "pulled" finds a saved "pull"), and the
//  rest worth saving. Shown on the study card, the sentence's page and its
//  Anki card.
//

import Foundation
import SwiftUI

@MainActor
enum SentenceWords {
    struct Token: Equatable {
        let text: String
        let range: Range<String.Index>
        /// The saved word it is, if any.
        let saved: SavedWord?
    }

    /// Every word of `sentence`, in order, with its saved word.
    static func tokens(in sentence: String, store: SavedWordsStore, language: Language? = nil) -> [Token] {
        var tokens: [Token] = []
        sentence.enumerateSubstrings(in: sentence.startIndex..<sentence.endIndex, options: .byWords) { word, range, _, _ in
            guard let word else { return }
            tokens.append(Token(text: word, range: range, saved: store.lemmaMatchedWord(for: word, language: language)))
        }
        return tokens
    }

    /// The saved words in `sentence`, once each, in order.
    static func saved(in sentence: String, store: SavedWordsStore, language: Language? = nil) -> [SavedWord] {
        var seen = Set<UUID>()
        return tokens(in: sentence, store: store, language: language).compactMap(\.saved).filter { seen.insert($0.id).inserted }
    }

    /// Words of `sentence` worth offering to save: not saved, four letters
    /// or more, not a common function word.
    static func candidates(in sentence: String, store: SavedWordsStore, language: Language? = nil) -> [String] {
        var seen = Set<String>()
        return tokens(in: sentence, store: store, language: language).compactMap { token in
            let lower = token.text.lowercased()
            guard token.saved == nil, lower.count >= 4, lower.allSatisfy(\.isLetter),
                  !commonWords.contains(lower), seen.insert(lower).inserted else { return nil }
            return token.text
        }
    }

    /// `sentence` with its saved words marked, for display.
    static func marked(_ sentence: String, store: SavedWordsStore, language: Language? = nil) -> AttributedString {
        var text = AttributedString(sentence)
        for token in tokens(in: sentence, store: store, language: language) where token.saved != nil {
            guard let lower = AttributedString.Index(token.range.lowerBound, within: text),
                  let upper = AttributedString.Index(token.range.upperBound, within: text) else { continue }
            text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            text[lower..<upper].backgroundColor = DS.Color.accent.opacity(0.14)
        }
        return text
    }

    private static let commonWords: Set<String> = [
        "about", "after", "again", "also", "because", "been", "before", "being", "could", "does", "down",
        "each", "even", "every", "from", "have", "having", "here", "into", "just", "like", "made", "make",
        "many", "more", "most", "much", "must", "never", "only", "other", "over", "said", "same", "should",
        "some", "such", "than", "that", "their", "them", "then", "there", "these", "they", "this", "those",
        "through", "very", "want", "were", "what", "when", "where", "which", "while", "will", "with", "would",
        "your", "yours",
    ]
}
