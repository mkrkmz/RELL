//
//  AppleTranslation.swift
//  Reader for Language Learner
//
//  Sentence translation through Apple's Translation framework (macOS 15+):
//  offline once the language pack is installed, free, and no AI provider
//  involved. The sentence strip uses it by default and falls back to the AI
//  provider when the pair isn't supported or a translation fails.
//

import Foundation
import Translation

enum SentenceTranslationEngine: String, CaseIterable, Identifiable {
    case apple
    case aiProvider

    static let storageKey = "sentenceTranslationEngine"
    static let `default`: SentenceTranslationEngine = .apple

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .apple:      return String(localized: "Apple Translation (offline)")
        case .aiProvider: return String(localized: "AI provider")
        }
    }

    static var stored: SentenceTranslationEngine {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .default
    }
}

enum AppleTranslation {
    /// The Translation framework's identifier for a RELL language. Chinese
    /// and Portuguese need a script/region to resolve to a model.
    static func localeLanguage(for language: Language) -> Locale.Language {
        switch language {
        case .chinese:    return Locale.Language(identifier: "zh-Hans")
        case .portuguese: return Locale.Language(identifier: "pt-BR")
        default:          return Locale.Language(identifier: language.shortCode.lowercased())
        }
    }

    /// True when Apple can translate `source` → `target`, installed or after
    /// a one-time download the system offers itself.
    static func canTranslate(from source: Language, to target: Language) async -> Bool {
        guard source != target else { return false }
        let status = await LanguageAvailability().status(
            from: localeLanguage(for: source),
            to: localeLanguage(for: target)
        )
        return status != .unsupported
    }
}
