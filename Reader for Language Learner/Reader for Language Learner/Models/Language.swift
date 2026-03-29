//
//  Language.swift
//  Reader for Language Learner
//
//  Supported native/target languages for the language-pair system.
//

import Foundation

enum Language: String, CaseIterable, Identifiable, Codable {
    case english    = "English"
    case turkish    = "Turkish"
    case german     = "German"
    case french     = "French"
    case spanish    = "Spanish"
    case japanese   = "Japanese"
    case korean     = "Korean"
    case chinese    = "Chinese"
    case arabic     = "Arabic"
    case portuguese = "Portuguese"
    case russian    = "Russian"
    case italian    = "Italian"

    var id: String { rawValue }

    // MARK: - UserDefaults Keys

    static let nativeLanguageKey  = "nativeLanguage"
    static let targetLanguageKey  = "targetLanguage"

    // MARK: - Defaults

    static let defaultNative: Language = .turkish
    static let defaultTarget: Language = .english

    // MARK: - Display

    var flag: String {
        switch self {
        case .english:    return "🇺🇸"
        case .turkish:    return "🇹🇷"
        case .german:     return "🇩🇪"
        case .french:     return "🇫🇷"
        case .spanish:    return "🇪🇸"
        case .japanese:   return "🇯🇵"
        case .korean:     return "🇰🇷"
        case .chinese:    return "🇨🇳"
        case .arabic:     return "🇸🇦"
        case .portuguese: return "🇧🇷"
        case .russian:    return "🇷🇺"
        case .italian:    return "🇮🇹"
        }
    }

    var nativeName: String {
        switch self {
        case .english:    return "English"
        case .turkish:    return "Türkçe"
        case .german:     return "Deutsch"
        case .french:     return "Français"
        case .spanish:    return "Español"
        case .japanese:   return "日本語"
        case .korean:     return "한국어"
        case .chinese:    return "中文"
        case .arabic:     return "العربية"
        case .portuguese: return "Português"
        case .russian:    return "Русский"
        case .italian:    return "Italiano"
        }
    }

    // MARK: - Native word for "Meaning" (used in module title)

    /// "Meaning" translated into the language itself — for module titles.
    var meaningTitle: String {
        switch self {
        case .english:    return "Meaning"
        case .turkish:    return "Anlam"
        case .german:     return "Bedeutung"
        case .french:     return "Signification"
        case .spanish:    return "Significado"
        case .japanese:   return "意味"
        case .korean:     return "의미"
        case .chinese:    return "含义"
        case .arabic:     return "المعنى"
        case .portuguese: return "Significado"
        case .russian:    return "Значение"
        case .italian:    return "Significato"
        }
    }

    // MARK: - Prompt Instruction

    /// Instruction string for LLM prompts: "Write in Turkish only."
    var promptInstruction: String {
        switch self {
        case .english:    return "Write in English only."
        case .turkish:    return "Yalnızca Türkçe yaz."
        case .german:     return "Schreibe nur auf Deutsch."
        case .french:     return "Écris uniquement en français."
        case .spanish:    return "Escribe solo en español."
        case .japanese:   return "日本語のみで書いてください。"
        case .korean:     return "한국어로만 작성하세요."
        case .chinese:    return "只用中文写。"
        case .arabic:     return "اكتب باللغة العربية فقط."
        case .portuguese: return "Escreva apenas em português."
        case .russian:    return "Пишите только на русском."
        case .italian:    return "Scrivi solo in italiano."
        }
    }

    // MARK: - Helper

    /// Reads from UserDefaults; falls back to `defaultNative`.
    static var storedNative: Language {
        guard let raw = UserDefaults.standard.string(forKey: nativeLanguageKey),
              let lang = Language(rawValue: raw) else { return defaultNative }
        return lang
    }

    static var storedTarget: Language {
        guard let raw = UserDefaults.standard.string(forKey: targetLanguageKey),
              let lang = Language(rawValue: raw) else { return defaultTarget }
        return lang
    }
}
