//
//  ModuleType.swift
//  Reader for Language Learner
//
//  Created by Codex on 11.02.2026.
//

import Foundation
import SwiftUI

enum ExplainMode: String, CaseIterable, Identifiable {
    case word = "Word"
    case sentence = "Sentence"

    var id: String { rawValue }
}

enum ExplainDetail: String, CaseIterable, Identifiable {
    case short = "Short"
    case detailed = "Detailed"

    var id: String { rawValue }
}

enum DomainPreference: String, CaseIterable, Identifiable {
    case general = "General"
    case academic = "Academic"
    case legal = "Legal"
    case business = "Business"
    case medical = "Medical"
    case technical = "Technical"

    var id: String { rawValue }

    /// Badge tint for domain pills in saved-word rows.
    var badgeColor: SwiftUI.Color {
        switch self {
        case .general:   return .blue
        case .academic:  return .purple
        case .legal:     return Color(hue: 0.08, saturation: 0.55, brightness: 0.52)
        case .business:  return .green
        case .medical:   return .red
        case .technical: return .orange
        }
    }
}

enum ModuleType: String, CaseIterable, Identifiable, Hashable {
    case definitionEN
    case meaningTR
    case collocations
    case examplesEN
    case pronunciationEN
    case etymologyEN
    case mnemonicEN
    case synonymsEN
    case wordFamilyEN
    case usageNotesEN

    var id: String { rawValue }

    /// Static title — used in result panel header.
    var title: String {
        title(nativeLanguage: Language.storedNative)
    }

    /// Dynamic title that adapts to the current native language.
    func title(nativeLanguage: Language) -> String {
        switch self {
        case .definitionEN:    return "Definition (EN)"
        case .meaningTR:       return "\(nativeLanguage.nativeName) \(nativeLanguage.meaningTitle)"
        case .collocations:    return "Collocations (EN+\(nativeLanguage.flag))"
        case .examplesEN:      return "Examples (EN)"
        case .etymologyEN:     return "Etymology (EN)"
        case .pronunciationEN: return "Pronunciation (EN)"
        case .mnemonicEN:      return "Mnemonic (EN)"
        case .synonymsEN:      return "Synonyms & Antonyms"
        case .wordFamilyEN:    return "Word Family"
        case .usageNotesEN:    return "Usage Notes"
        }
    }

    var iconName: String {
        switch self {
        case .definitionEN:    return "text.book.closed"
        case .meaningTR:       return "globe"
        case .collocations:    return "text.word.spacing"
        case .examplesEN:      return "list.bullet.rectangle"
        case .etymologyEN:     return "clock.arrow.circlepath"
        case .pronunciationEN: return "waveform"
        case .mnemonicEN:      return "lightbulb"
        case .synonymsEN:      return "arrow.left.arrow.right"
        case .wordFamilyEN:    return "list.number"
        case .usageNotesEN:    return "chart.bar.xaxis"
        }
    }

    /// Compact label used in the module grid buttons.
    var shortTitle: String {
        switch self {
        case .definitionEN:    return "Define"
        case .meaningTR:       return "Türkçe"
        case .collocations:    return "Colloc."
        case .examplesEN:      return "Examples"
        case .etymologyEN:     return "Etymology"
        case .pronunciationEN: return "Pronounce"
        case .mnemonicEN:      return "Mnemonic"
        case .synonymsEN:      return "Synonyms"
        case .wordFamilyEN:    return "Word Form"
        case .usageNotesEN:    return "Usage"
        }
    }

    /// Per-module accent color — used for icon and active-state tinting in the grid.
    var accentColor: SwiftUI.Color {
        switch self {
        case .definitionEN:    return .blue
        case .meaningTR:       return .purple
        case .collocations:    return .green
        case .examplesEN:      return .teal
        case .pronunciationEN: return .orange
        case .etymologyEN:     return Color(hue: 0.08, saturation: 0.55, brightness: 0.52)
        case .mnemonicEN:      return .pink
        case .synonymsEN:      return .indigo
        case .wordFamilyEN:    return .cyan
        case .usageNotesEN:    return Color(hue: 0.12, saturation: 0.80, brightness: 0.78)
        }
    }

    var outputLanguage: PromptTemplates.OutputLanguage {
        switch self {
        case .meaningTR:
            return .turkishOnly
        case .collocations:
            return .mixed
        case .definitionEN, .examplesEN, .etymologyEN, .pronunciationEN, .mnemonicEN,
             .synonymsEN, .wordFamilyEN, .usageNotesEN:
            return .englishOnly
        }
    }

    /// Modules that produce structured markdown output.
    var outputFormat: PromptTemplates.OutputFormat {
        switch self {
        case .collocations: return .markdown
        default:            return .plain
        }
    }

    var systemPrompt: String {
        PromptTemplates.system(lang: outputLanguage, format: outputFormat)
    }

    func isEnabled(mode: ExplainMode) -> Bool {
        switch (self, mode) {
        case (.etymologyEN, .sentence), (.mnemonicEN, .sentence), (.wordFamilyEN, .sentence):
            return false
        default:
            return true
        }
    }

    /// Recommended max_tokens cap per module/mode/detail to keep Gemma fast.
    func recommendedMaxTokens(mode: ExplainMode, detail: ExplainDetail) -> Int {
        switch (self, mode, detail) {
        // Definition
        case (.definitionEN, .word, .short):        return 160
        case (.definitionEN, .word, .detailed):     return 280
        case (.definitionEN, .sentence, .short):    return 160
        case (.definitionEN, .sentence, .detailed): return 280
        // TR Meaning — Turkish prose needs more room than English
        case (.meaningTR, .word, .short):           return 220
        case (.meaningTR, .word, .detailed):        return 380
        case (.meaningTR, .sentence, .short):       return 220
        case (.meaningTR, .sentence, .detailed):    return 380
        // Collocations — markdown numbered list format needs more room
        case (.collocations, .word, .short):        return 550
        case (.collocations, .word, .detailed):     return 900
        case (.collocations, .sentence, .short):    return 400
        case (.collocations, .sentence, .detailed): return 700
        // Examples
        case (.examplesEN, .word, .short):          return 120
        case (.examplesEN, .word, .detailed):       return 180
        case (.examplesEN, .sentence, .short):      return 120
        case (.examplesEN, .sentence, .detailed):   return 150
        // Etymology (word only)
        case (.etymologyEN, _, .short):             return 100
        case (.etymologyEN, _, .detailed):          return 160
        // Pronunciation
        case (.pronunciationEN, .word, .short):     return 40
        case (.pronunciationEN, .word, .detailed):  return 40
        case (.pronunciationEN, .sentence, .short): return 80
        case (.pronunciationEN, .sentence, .detailed): return 120
        // Mnemonic (word only)
        case (.mnemonicEN, _, .short):              return 60
        case (.mnemonicEN, _, .detailed):           return 100
        // Synonyms & Antonyms
        case (.synonymsEN, .word, .short):          return 160
        case (.synonymsEN, .word, .detailed):       return 280
        case (.synonymsEN, .sentence, .short):      return 120
        case (.synonymsEN, .sentence, .detailed):   return 180
        // Word Family (word only; sentence disabled but keep exhaustive)
        case (.wordFamilyEN, _, .short):            return 160
        case (.wordFamilyEN, _, .detailed):         return 260
        // Usage Notes
        case (.usageNotesEN, .word, .short):        return 180
        case (.usageNotesEN, .word, .detailed):     return 320
        case (.usageNotesEN, .sentence, .short):    return 150
        case (.usageNotesEN, .sentence, .detailed): return 240
        }
    }

    /// Recommended temperature per module.
    var recommendedTemperature: Double {
        switch self {
        case .mnemonicEN:
            return 0.3
        case .examplesEN:
            return 0.2
        case .collocations:
            return 0.15
        default:
            return 0.1
        }
    }

    // MARK: - User Prompts

    func userPrompt(
        term: String,
        mode: ExplainMode,
        detail: ExplainDetail,
        domain: DomainPreference = .general,
        context: String? = nil,
        nativeLanguage: Language = Language.storedNative
    ) -> String {
        let domainLine = domain != .general
            ? "\nContext: \(domain.rawValue) domain. Tailor vocabulary and examples accordingly. Do not mention domain in output."
            : ""
        
        // If context is provided, we ask the model to consider it.
        let ctxBlock = context.map {
            """
            \nContext Sentence: "\($0)"
            (Explain the meaning/usage of the term specifically as it appears in this sentence.)
            """
        } ?? ""

        switch (self, mode) {

        // ──────────────────────────────────────
        // MARK: Definition (EN)
        // ──────────────────────────────────────

        case (.definitionEN, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Give a plain-text definition in English. No headings, labels, or bullet points.
            \(context != nil ? "Start by briefly explaining how it is used in the context sentence, then give the general definition." : "")
            \(detail == .short ? "Exactly 1 paragraph." : "Max 2 paragraphs.")
            """

        case (.definitionEN, .sentence):
            return """
            Sentence: \(term)\(domainLine)

            Explain the meaning of this sentence in plain English. No headings, labels, or bullet points.
            \(detail == .short ? "Exactly 1 paragraph." : "Max 2 paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Turkish Meaning (TR)
        // ──────────────────────────────────────

        case (.meaningTR, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Explain the meaning in \(nativeLanguage.rawValue). Plain text only, no headings, no labels, no bullet points.
            \(nativeLanguage.promptInstruction)
            \(context != nil ? "First explain the contextual usage, then the general meaning." : "")
            \(detail == .short ? "Exactly 1 paragraph." : "Max 2 paragraphs.")
            """

        case (.meaningTR, .sentence):
            return """
            Sentence: \(term)\(domainLine)

            Explain the meaning of this sentence in \(nativeLanguage.rawValue). Plain text only, no headings, no labels.
            \(nativeLanguage.promptInstruction)
            \(detail == .short ? "Exactly 1 paragraph." : "Max 2 paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Collocations (EN+TR)
        // ──────────────────────────────────────

        case (.collocations, .word):
            let count = detail == .short ? 3 : 5
            let native = nativeLanguage.rawValue
            return """
            Word: \(term)\(domainLine)

            List \(count) common collocations using exactly this markdown format for each item:

            N. **[collocation]:** [meaning in \(native), \(native) only]
               - *Örnek Cümle:* "[one English example sentence]"
               - *Türkçe Çeviri:* "[Turkish translation of the example]"

            Put a blank line between items. Number each item starting from 1. No introduction, no commentary, nothing else.
            """

        case (.collocations, .sentence):
            let count = detail == .short ? 2 : 4
            let native = nativeLanguage.rawValue
            return """
            Sentence: \(term)\(domainLine)

            Extract \(count) key collocations or phrases from this sentence. Use exactly this markdown format for each item:

            N. **[collocation/phrase]:** [meaning in \(native), \(native) only]
               - *Örnek Cümle:* "[one short English example sentence using this collocation]"
               - *Türkçe Çeviri:* "[Turkish translation of the example]"

            Put a blank line between items. Number each item starting from 1. No introduction, no commentary, nothing else.
            """

        // ──────────────────────────────────────
        // MARK: Examples (EN)
        // ──────────────────────────────────────

        case (.examplesEN, .word):
            let count = detail == .short ? 3 : 5
            return """
            \(term)\(domainLine)

            Write exactly \(count) example sentences using this word/phrase. Each sentence on its own line. No numbering, no labels, no extra text.
            """

        case (.examplesEN, .sentence):
            let count = detail == .short ? 3 : 5
            return """
            \(term)\(domainLine)

            Paraphrase this sentence \(count) different ways. Each paraphrase on its own line. No numbering, no labels, no extra text.
            """

        // ──────────────────────────────────────
        // MARK: Etymology (EN) — word only
        // ──────────────────────────────────────

        case (.etymologyEN, .word):
            return """
            \(term)

            Give the etymology of this word in plain text. No headings, no labels, no bullet points.
            \(detail == .short ? "Exactly 1 paragraph." : "Max 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Pronunciation (EN)
        // ──────────────────────────────────────

        case (.pronunciationEN, .word):
            return """
            \(term)

            Output only the IPA transcription followed by a simple respelling in parentheses on the same line. Example format: /ˈwɜːrd/ (WURD). Nothing else.
            """

        case (.pronunciationEN, .sentence):
            let count = detail == .short ? 2 : 3
            return """
            \(term)

            Pick \(count) tricky-to-pronounce words from this sentence. For each word, output IPA + respelling on one line. Example format: word — /ˈwɜːrd/ (WURD). Each on its own line. Nothing else.
            """

        // ──────────────────────────────────────
        // MARK: Mnemonic (EN) — word only
        // ──────────────────────────────────────

        case (.mnemonicEN, .word):
            return """
            \(term)

            Write a short mnemonic to remember this word. Use sound similarity or a mini-story. No labels, no headings.
            \(detail == .short ? "1-2 sentences only." : "Max 3 sentences.")
            """

        // ──────────────────────────────────────
        // MARK: Synonyms & Antonyms (EN)
        // ──────────────────────────────────────

        case (.synonymsEN, .word):
            let synCount = detail == .short ? 3 : 5
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            List \(synCount) synonyms with a one-line nuance note for each (format: word — note).
            Then, after a blank line, list 1–2 antonyms with a brief note, each prefixed with "≠".
            Skip antonyms if none exist. No headings, no bullet points, no extra labels.
            """

        case (.synonymsEN, .sentence):
            return """
            Sentence: \(term)

            Pick 3 key words from this sentence and provide one synonym for each.
            Format: original → synonym — brief nuance note. One per line. No extra text.
            """

        // ──────────────────────────────────────
        // MARK: Word Family (EN) — word only
        // ──────────────────────────────────────

        case (.wordFamilyEN, .word):
            return """
            Word/Phrase: \(term)

            List all common derived forms of this word that exist in English.
            Format: (part of speech) form — one short example sentence.
            One per line. No headings, no extra labels.
            \(detail == .short ? "Include the 3–4 most useful forms." : "Include all common forms: noun, verb, adjective, adverb, and any notable compounds.")
            """

        // ──────────────────────────────────────
        // MARK: Usage Notes (EN)
        // ──────────────────────────────────────

        case (.usageNotesEN, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Provide usage notes in this exact format, one per line, using these labels:
            FREQ: [very common / common / uncommon / rare] — brief reason
            REG: [formal / neutral / informal / slang] — typical context\(detail == .detailed ?
            """

            CONFUSE: word most often confused with this one and why (write CONFUSE: none if not applicable)
            CAUTION: common learner mistake, regional note, or usage restriction (write CAUTION: none if not applicable)
            """ : "")

            No headings, no bullet points. Use only the labels above.
            """

        case (.usageNotesEN, .sentence):
            return """
            Sentence: \(term)

            Analyze the register and style of this sentence. Cover: register (formal/informal/neutral), any notable vocabulary or structures, and the contexts where it would be appropriate.
            Plain text only. \(detail == .short ? "Exactly 1 paragraph." : "Max 2 paragraphs.")
            """

        // ──────────────────────────────────────
        // Disabled combinations
        // ──────────────────────────────────────

        case (.etymologyEN, .sentence), (.mnemonicEN, .sentence), (.wordFamilyEN, .sentence):
            return "N/A"
        }
    }
}
