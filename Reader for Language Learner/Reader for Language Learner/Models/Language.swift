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

    /// Two-letter display code for module title suffixes, e.g. "Definition (DE)".
    var shortCode: String {
        switch self {
        case .english:    return "EN"
        case .turkish:    return "TR"
        case .german:     return "DE"
        case .french:     return "FR"
        case .spanish:    return "ES"
        case .japanese:   return "JA"
        case .korean:     return "KO"
        case .chinese:    return "ZH"
        case .arabic:     return "AR"
        case .portuguese: return "PT"
        case .russian:    return "RU"
        case .italian:    return "IT"
        }
    }

    // MARK: - Speech

    /// BCP-47 code for `AVSpeechSynthesisVoice(language:)` lookups.
    var speechCode: String {
        switch self {
        case .english:    return "en-US"
        case .turkish:    return "tr-TR"
        case .german:     return "de-DE"
        case .french:     return "fr-FR"
        case .spanish:    return "es-ES"
        case .japanese:   return "ja-JP"
        case .korean:     return "ko-KR"
        case .chinese:    return "zh-CN"
        case .arabic:     return "ar-SA"
        case .portuguese: return "pt-BR"
        case .russian:    return "ru-RU"
        case .italian:    return "it-IT"
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

    /// "Unknown" in the language itself — the model's fallback answer when unsure.
    var unknownWord: String {
        switch self {
        case .english:    return "Unknown"
        case .turkish:    return "Bilinmiyor"
        case .german:     return "Unbekannt"
        case .french:     return "Inconnu"
        case .spanish:    return "Desconocido"
        case .japanese:   return "不明"
        case .korean:     return "알 수 없음"
        case .chinese:    return "未知"
        case .arabic:     return "غير معروف"
        case .portuguese: return "Desconhecido"
        case .russian:    return "Неизвестно"
        case .italian:    return "Sconosciuto"
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
