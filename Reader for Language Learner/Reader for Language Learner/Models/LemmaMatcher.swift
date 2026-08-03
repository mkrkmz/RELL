//
//  LemmaMatcher.swift
//  Reader for Language Learner
//
//  Inflection-aware matching for saved vocabulary (Roadmap v9 Sprint 3, L2).
//
//  Highlighting saved words by exact string match quietly fails in exactly the
//  languages this app is for: save "laufen" and the text's "lief" never lights
//  up; save "run" and "ran" is missed. Apple's NaturalLanguage tagger reduces a
//  surface form to its dictionary form (lemma), so a word saved once matches
//  the shapes it actually takes in the book.
//
//  Everything is best-effort: when the tagger has no lemma for a token (many
//  languages have partial coverage) the caller falls back to the exact match it
//  did before, so this can only ever add matches, never remove them.
//

import Foundation
import NaturalLanguage

enum LemmaMatcher {

    /// NaturalLanguage's identifier for a study language, or nil when the
    /// framework has no lemmatizer worth asking.
    static func nlLanguage(for language: Language?) -> NLLanguage? {
        guard let language else { return nil }
        switch language {
        case .english:    return .english
        case .turkish:    return .turkish
        case .german:     return .german
        case .french:     return .french
        case .spanish:    return .spanish
        case .japanese:   return .japanese
        case .korean:     return .korean
        case .chinese:    return .simplifiedChinese
        case .arabic:     return .arabic
        case .portuguese: return .portuguese
        case .russian:    return .russian
        case .italian:    return .italian
        }
    }

    /// The dictionary form of a single word, lowercased. Returns nil when the
    /// tagger offers no lemma — the caller should fall back to exact matching.
    static func lemma(of term: String, language: Language?) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = trimmed
        if let nl = nlLanguage(for: language) {
            tagger.setLanguage(nl, range: trimmed.startIndex..<trimmed.endIndex)
        }
        let (tag, _) = tagger.tag(
            at: trimmed.startIndex,
            unit: .word,
            scheme: .lemma
        )
        guard let lemma = tag?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !lemma.isEmpty
        else { return nil }
        return lemma.lowercased()
    }

    /// Match key for a term: its lemma when available, else the term itself.
    /// Comparing two terms' keys is the inflection-aware equality test.
    static func matchKey(for term: String, language: Language?) -> String {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lemma(of: term, language: language) ?? normalized
    }

    /// True when two surface forms reduce to the same dictionary word —
    /// "ran"/"run", "Häuser"/"Haus", "koştu"/"koşmak".
    static func matches(_ lhs: String, _ rhs: String, language: Language?) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if left == right { return true }
        guard !left.isEmpty, !right.isEmpty else { return false }
        return matchKey(for: lhs, language: language) == matchKey(for: rhs, language: language)
    }

    /// Lemmatizes every word in a body of text, returning the distinct match
    /// keys it contains. Used to profile a document against saved vocabulary
    /// (`LexicalProfileService`) without re-tagging per lookup.
    ///
    /// `nonisolated` and pure so callers can run it off the main actor.
    static func matchKeys(in text: String, language: Language?) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        if let nl = nlLanguage(for: language) {
            tagger.setLanguage(nl, range: text.startIndex..<text.endIndex)
        }

        var keys: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            let surface = String(text[range]).lowercased()
            guard !surface.isEmpty else { return true }
            let lemma = tag?.rawValue.lowercased()
            keys.append(lemma?.isEmpty == false ? lemma! : surface)
            return true
        }
        return keys
    }
}
