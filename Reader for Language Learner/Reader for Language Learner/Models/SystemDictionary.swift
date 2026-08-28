//
//  SystemDictionary.swift
//  Reader for Language Learner
//
//  macOS's own dictionaries as an instant, offline answer for hover and the
//  lookup HUD (Roadmap v10 Sprint 4, L-E3). No model, no network, no wait —
//  for a word the reader's dictionaries already cover.
//
//  The catch that shapes this file: which dictionaries are enabled is the
//  user's business, and they can be bilingual in either direction. On a Mac
//  with an English–Turkish dictionary, "sleep" comes back as Turkish. That
//  makes the raw lookup unusable for a reader who asked to be answered in the
//  language they're studying, because the instant layer suppresses the model
//  call entirely. So an entry is only offered when it's actually written in
//  the language that was asked for.
//

import CoreServices
import Foundation
import NaturalLanguage

enum SystemDictionary {

    /// The system's definition of `term`, or nil when no active dictionary
    /// covers it. Fast: about 60ms on the first call of a session while the
    /// indexes load, well under a millisecond afterwards.
    static func rawDefinition(for term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = CFRange(location: 0, length: trimmed.utf16.count)
        guard let result = DCSCopyTextDefinition(nil, trimmed as CFString, range) else { return nil }
        let definition = (result.takeRetainedValue() as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return definition.isEmpty ? nil : definition
    }

    /// The system's definition of `term`, but only when the entry is written
    /// in `language` — the language the reader asked to be answered in.
    /// Returns nil for a mismatch, which leaves the existing model-backed path
    /// to answer instead of quietly overriding the reader's choice.
    static func definition(for term: String, in language: Language) -> String? {
        guard let definition = rawDefinition(for: term) else { return nil }
        guard let detected = self.language(of: definition, headword: term),
              detected == language
        else { return nil }
        return definition
    }

    // MARK: - Language of an entry

    /// Best guess at the language an entry is written in.
    ///
    /// The headword and its pronunciation open the entry in the *looked-up*
    /// word's language ("sleep | sliːp | n uyku…"), which pulls detection the
    /// wrong way on a bilingual entry, so they're dropped first.
    private static func language(of definition: String, headword: String) -> Language? {
        let body = strippingHeadword(from: definition, headword: headword)
        guard body.count >= 8 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(body)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        // A weak guess is worse than no answer here: acting on it would show
        // the reader an entry in a language they didn't ask for. Real entries
        // score above 0.95; the floor only rejects the ambiguous ones.
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0
        guard confidence >= 0.65 else { return nil }
        return LemmaMatcher.language(for: dominant)
    }

    /// Drops the leading headword and pronunciation. Dictionary entries open
    /// with `headword | prəˌnʌnsiˈeɪʃn |`; when that shape isn't there, only
    /// a leading repeat of the headword is removed.
    private static func strippingHeadword(from definition: String, headword: String) -> String {
        let parts = definition.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count == 3 {
            return parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmedHead = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHead.isEmpty, definition.lowercased().hasPrefix(trimmedHead.lowercased()) {
            return String(definition.dropFirst(trimmedHead.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return definition
    }
}
