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
        systemPrompt(customPreamble: "")
    }

    func systemPrompt(customPreamble: String) -> String {
        PromptTemplates.system(lang: outputLanguage, format: outputFormat, customPreamble: customPreamble)
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
    func recommendedMaxTokens(
        mode: ExplainMode,
        detail: ExplainDetail,
        modelIdentifier: String? = nil
    ) -> Int {
        let base: Int
        switch (self, mode, detail) {
        // Definition
        case (.definitionEN, .word, .short):        base = 160
        case (.definitionEN, .word, .detailed):     base = 280
        case (.definitionEN, .sentence, .short):    base = 160
        case (.definitionEN, .sentence, .detailed): base = 280
        // TR Meaning — Turkish prose needs more room than English
        case (.meaningTR, .word, .short):           base = 220
        case (.meaningTR, .word, .detailed):        base = 380
        case (.meaningTR, .sentence, .short):       base = 220
        case (.meaningTR, .sentence, .detailed):    base = 380
        // Collocations — markdown numbered list format needs more room
        case (.collocations, .word, .short):        base = 550
        case (.collocations, .word, .detailed):     base = 900
        case (.collocations, .sentence, .short):    base = 400
        case (.collocations, .sentence, .detailed): base = 700
        // Examples
        case (.examplesEN, .word, .short):          base = 120
        case (.examplesEN, .word, .detailed):       base = 180
        case (.examplesEN, .sentence, .short):      base = 120
        case (.examplesEN, .sentence, .detailed):   base = 150
        // Etymology (word only)
        case (.etymologyEN, _, .short):             base = 100
        case (.etymologyEN, _, .detailed):          base = 160
        // Pronunciation
        case (.pronunciationEN, .word, .short):     base = 40
        case (.pronunciationEN, .word, .detailed):  base = 40
        case (.pronunciationEN, .sentence, .short): base = 80
        case (.pronunciationEN, .sentence, .detailed): base = 120
        // Mnemonic (word only)
        case (.mnemonicEN, _, .short):              base = 60
        case (.mnemonicEN, _, .detailed):           base = 100
        // Synonyms & Antonyms
        case (.synonymsEN, .word, .short):          base = 160
        case (.synonymsEN, .word, .detailed):       base = 280
        case (.synonymsEN, .sentence, .short):      base = 120
        case (.synonymsEN, .sentence, .detailed):   base = 180
        // Word Family (word only; sentence disabled but keep exhaustive)
        case (.wordFamilyEN, _, .short):            base = 160
        case (.wordFamilyEN, _, .detailed):         base = 260
        // Usage Notes
        case (.usageNotesEN, .word, .short):        base = 180
        case (.usageNotesEN, .word, .detailed):     base = 320
        case (.usageNotesEN, .sentence, .short):    base = 150
        case (.usageNotesEN, .sentence, .detailed): base = 240
        }

        guard let modelIdentifier else { return base }
        guard modelIdentifier.localizedCaseInsensitiveContains("gemma-4") else { return base }

        switch (self, mode, detail) {
        case (.definitionEN, .word, .short),
             (.definitionEN, .sentence, .short):
            return min(base, 96)
        case (.definitionEN, _, .detailed):
            return min(base, 160)
        case (.meaningTR, .word, .short),
             (.meaningTR, .sentence, .short):
            return min(base, 120)
        case (.meaningTR, _, .detailed):
            return min(base, 180)
        case (.collocations, .word, .short):
            return min(base, 220)
        case (.collocations, .sentence, .short):
            return min(base, 180)
        case (.collocations, _, .detailed):
            return min(base, 320)
        case (.examplesEN, _, .short):
            return min(base, 80)
        case (.examplesEN, _, .detailed):
            return min(base, 120)
        case (.usageNotesEN, .word, .short),
             (.usageNotesEN, .sentence, .short):
            return min(base, 110)
        case (.usageNotesEN, _, .detailed):
            return min(base, 180)
        case (.synonymsEN, .word, .short),
             (.synonymsEN, .sentence, .short),
             (.wordFamilyEN, _, .short):
            return min(base, 100)
        case (.synonymsEN, _, .detailed),
             (.wordFamilyEN, _, .detailed):
            return min(base, 150)
        case (.etymologyEN, _, .short),
             (.mnemonicEN, _, .short):
            return min(base, 70)
        case (.etymologyEN, _, .detailed),
             (.mnemonicEN, _, .detailed):
            return min(base, 100)
        case (.pronunciationEN, _, _):
            return base
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
            ? "\nDomain: \(domain.rawValue). Adapt the explanation."
            : ""
        
        let ctxBlock = context.map {
            """
            \nContext sentence: "\($0)"
            """
        } ?? ""

        switch (self, mode) {

        // ──────────────────────────────────────
        // MARK: Definition (EN)
        // ──────────────────────────────────────

        case (.definitionEN, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Define it in English.
            \(context != nil
                ? "Write exactly 2 short paragraphs: first this context, then general meaning."
                : (detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs."))
            """

        case (.definitionEN, .sentence):
            return """
            Sentence: \(term)\(domainLine)

            Explain this sentence in plain English.
            \(detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Turkish Meaning (TR)
        // ──────────────────────────────────────

        case (.meaningTR, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Explain it in \(nativeLanguage.rawValue).
            \(nativeLanguage.promptInstruction)
            \(context != nil
                ? "Write exactly 2 short paragraphs: first this context, then general meaning."
                : (detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs."))
            """

        case (.meaningTR, .sentence):
            return """
            Sentence: \(term)\(domainLine)

            Explain this sentence in \(nativeLanguage.rawValue).
            \(nativeLanguage.promptInstruction)
            \(detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Collocations (EN+TR)
        // ──────────────────────────────────────

        case (.collocations, .word):
            let count = detail == .short ? 3 : 5
            let native = nativeLanguage.rawValue
            return """
            Word: \(term)\(domainLine)

            List \(count) common collocations. Use exactly this format:

            N. **[collocation]:** [meaning in \(native), \(native) only]
               - *Örnek Cümle:* "[one English example sentence]"
               - *Türkçe Çeviri:* "[Turkish translation of the example]"

            Blank line between items. Start numbering at 1.
            """

        case (.collocations, .sentence):
            let count = detail == .short ? 2 : 4
            let native = nativeLanguage.rawValue
            return """
            Sentence: \(term)\(domainLine)

            Extract \(count) key collocations or phrases from this sentence. Use exactly this format:

            N. **[collocation/phrase]:** [meaning in \(native), \(native) only]
               - *Örnek Cümle:* "[one short English example sentence using this collocation]"
               - *Türkçe Çeviri:* "[Turkish translation of the example]"

            Blank line between items. Start numbering at 1.
            """

        // ──────────────────────────────────────
        // MARK: Examples (EN)
        // ──────────────────────────────────────

        case (.examplesEN, .word):
            let count = detail == .short ? 3 : 5
            return """
            \(term)\(domainLine)

            Write exactly \(count) example sentences using this word/phrase.
            One sentence per line.
            """

        case (.examplesEN, .sentence):
            let count = detail == .short ? 3 : 5
            return """
            \(term)\(domainLine)

            Paraphrase this sentence \(count) different ways.
            One paraphrase per line.
            """

        // ──────────────────────────────────────
        // MARK: Etymology (EN) — word only
        // ──────────────────────────────────────

        case (.etymologyEN, .word):
            return """
            \(term)

            Give the etymology of this word.
            \(detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Pronunciation (EN)
        // ──────────────────────────────────────

        case (.pronunciationEN, .word):
            return """
            \(term)

            Output only: /IPA/ (RESPelling)
            """

        case (.pronunciationEN, .sentence):
            let count = detail == .short ? 2 : 3
            return """
            \(term)

            Pick \(count) tricky words from this sentence.
            Format each line: word — /IPA/ (RESPelling)
            """

        // ──────────────────────────────────────
        // MARK: Mnemonic (EN) — word only
        // ──────────────────────────────────────

        case (.mnemonicEN, .word):
            return """
            \(term)

            Write a short mnemonic using sound similarity or a mini-story.
            \(detail == .short ? "Use 1-2 sentences." : "Use at most 3 sentences.")
            """

        // ──────────────────────────────────────
        // MARK: Synonyms & Antonyms (EN)
        // ──────────────────────────────────────

        case (.synonymsEN, .word):
            let synCount = detail == .short ? 3 : 5
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            List \(synCount) synonyms with a short nuance note for each.
            Format: word — note
            Then add a blank line and list 1-2 antonyms, each prefixed with "≠".
            Skip antonyms if none exist.
            """

        case (.synonymsEN, .sentence):
            return """
            Sentence: \(term)

            Pick 3 key words from this sentence and provide one synonym for each.
            Format: original → synonym — brief nuance note
            """

        // ──────────────────────────────────────
        // MARK: Word Family (EN) — word only
        // ──────────────────────────────────────

        case (.wordFamilyEN, .word):
            return """
            Word/Phrase: \(term)

            List common derived forms of this word.
            Format: (part of speech) form — one short example sentence
            \(detail == .short ? "Include the 3–4 most useful forms." : "Include all common forms: noun, verb, adjective, adverb, and any notable compounds.")
            """

        // ──────────────────────────────────────
        // MARK: Usage Notes (EN)
        // ──────────────────────────────────────

        case (.usageNotesEN, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Provide usage notes using exactly these labels, one per line:
            FREQ: [very common / common / uncommon / rare] — brief reason
            REG: [formal / neutral / informal / slang] — typical context\(detail == .detailed ?
            """

            CONFUSE: word most often confused with this one and why (write CONFUSE: none if not applicable)
            CAUTION: common learner mistake, regional note, or usage restriction (write CAUTION: none if not applicable)
            """ : "")

            Use only these labels.
            """

        case (.usageNotesEN, .sentence):
            return """
            Sentence: \(term)

            Analyze the register and style of this sentence.
            Cover register, notable vocabulary or structure, and where it fits.
            \(detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // Disabled combinations
        // ──────────────────────────────────────

        case (.etymologyEN, .sentence), (.mnemonicEN, .sentence), (.wordFamilyEN, .sentence):
            return "N/A"
        }
    }
}
