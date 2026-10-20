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

    var localizedTitle: String {
        switch self {
        case .word:     return String(localized: "Word")
        case .sentence: return String(localized: "Sentence")
        }
    }

    /// "word" → "Word". Four save paths wrote the raw value in lower case
    /// (v15 S0: 21 of 59 saved words); comparisons and `init(rawValue:)`
    /// are case-sensitive, so stored modes are normalised when read.
    static func normalizedRawValue(_ raw: String) -> String {
        allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }?.rawValue ?? raw
    }

    /// The mode a selection is explained in unless the reader overrides it
    /// (v14 S2): one word is a word, anything longer a sentence — the same
    /// test the inspector uses to show the word card.
    static func automatic(for selection: String) -> ExplainMode {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        let isWord = !trimmed.isEmpty && trimmed.count <= 40 && !trimmed.contains(where: \.isWhitespace)
        return isWord ? .word : .sentence
    }
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

    var localizedTitle: String {
        switch self {
        case .general:   return String(localized: "General")
        case .academic:  return String(localized: "Academic")
        case .legal:     return String(localized: "Legal")
        case .business:  return String(localized: "Business")
        case .medical:   return String(localized: "Medical")
        case .technical: return String(localized: "Technical")
        }
    }

    /// Badge tint for domain pills in saved-word rows.
    var badgeColor: SwiftUI.Color {
        switch self {
        case .general:   return .blue
        case .academic:  return .purple
        case .legal:     return DS.Color.brown
        case .business:  return .green
        case .medical:   return .red
        case .technical: return .orange
        }
    }
}

enum ModuleType: String, CaseIterable, Identifiable, Hashable, Codable {
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

    /// The five always-visible modules, in grid and menu order.
    static let primary: [ModuleType] = [.definitionEN, .meaningTR, .collocations, .examplesEN, .pronunciationEN]

    /// The overflow set shown behind "more modules".
    static let overflow: [ModuleType] = [.etymologyEN, .mnemonicEN, .synonymsEN, .wordFamilyEN, .usageNotesEN]

    /// The inspector's chips (v14 S2): the primary set less Pronunciation,
    /// which the word card's speaker button covers.
    static let inspectorFront: [ModuleType] = [.definitionEN, .meaningTR, .collocations, .examplesEN]

    /// Behind the inspector's "More" menu, in menu (⌘5–⌘9) order.
    static var inspectorMore: [ModuleType] { menuOrder.filter { !inspectorFront.contains($0) } }

    /// Canonical ordering for menus: primary first, then overflow.
    static var menuOrder: [ModuleType] { primary + overflow }

    /// Static title — used in result panel header.
    var title: String {
        title(nativeLanguage: Language.storedNative, targetLanguage: Language.storedTarget)
    }

    /// Dynamic title that adapts to the current native and target languages.
    /// Raw values / CodingKeys keep their `…EN` names — they key persisted
    /// `SavedWord.llmOutputs` dictionaries and must never change.
    func title(nativeLanguage: Language, targetLanguage: Language = Language.storedTarget) -> String {
        // Localized (v18 S2): shown with `Text(String)`, which skips the
        // catalog, so these were English in every language until now.
        let code = targetLanguage.shortCode
        switch self {
        case .definitionEN:    return String(localized: "Definition (\(code))")
        case .meaningTR:       return "\(nativeLanguage.nativeName) \(nativeLanguage.meaningTitle)"
        case .collocations:    return String(localized: "Collocations (\(code)+\(nativeLanguage.flag))")
        case .examplesEN:      return String(localized: "Examples (\(code))")
        case .etymologyEN:     return String(localized: "Etymology (\(code))")
        case .pronunciationEN: return String(localized: "Pronunciation (\(code))")
        case .mnemonicEN:      return String(localized: "Mnemonic (\(code))")
        case .synonymsEN:      return String(localized: "Synonyms & Antonyms")
        case .wordFamilyEN:    return String(localized: "Word Family")
        case .usageNotesEN:    return String(localized: "Usage Notes")
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
        case .definitionEN:    return String(localized: "Definition")
        case .meaningTR:       return Language.storedNative.nativeName
        case .collocations:    return String(localized: "Collocations")
        case .examplesEN:      return String(localized: "Examples")
        case .etymologyEN:     return String(localized: "Etymology")
        case .pronunciationEN: return String(localized: "Pronunciation")
        case .mnemonicEN:      return String(localized: "Mnemonic")
        case .synonymsEN:      return String(localized: "Synonyms")
        case .wordFamilyEN:    return String(localized: "Word Family")
        case .usageNotesEN:    return String(localized: "Usage")
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
        case .etymologyEN:     return DS.Color.brown
        case .mnemonicEN:      return .pink
        case .synonymsEN:      return .indigo
        case .wordFamilyEN:    return .cyan
        case .usageNotesEN:    return DS.Color.amber
        }
    }

    func outputLanguage(
        nativeLanguage: Language,
        targetLanguage: Language = Language.storedTarget
    ) -> PromptTemplates.OutputLanguage {
        switch self {
        case .meaningTR:
            return .native(nativeLanguage)
        // v19 S1: the hook is a sound-alike in your own language (the
        // keyword method), so it's written in it.
        case .mnemonicEN:
            return .native(nativeLanguage)
        case .collocations:
            return .mixed(native: nativeLanguage, target: targetLanguage)
        case .definitionEN, .examplesEN, .etymologyEN, .pronunciationEN,
             .synonymsEN, .wordFamilyEN, .usageNotesEN:
            return .target(targetLanguage)
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

    func systemPrompt(
        customPreamble: String,
        nativeLanguage: Language = Language.storedNative,
        targetLanguage: Language = Language.storedTarget
    ) -> String {
        PromptTemplates.system(
            lang: outputLanguage(nativeLanguage: nativeLanguage, targetLanguage: targetLanguage),
            format: outputFormat,
            customPreamble: customPreamble
        )
    }

    /// Whether this module's prompt reads the sentence around the word —
    /// its answer then depends on that sentence (v19 S0: the cache keys it
    /// by the sentence too).
    /// v19 S1: in word mode every module answers for the sense the word has
    /// in its sentence ("bank" of a river has other collocations, another
    /// word family and another origin than the money "bank").
    func usesContext(mode: ExplainMode) -> Bool {
        mode == .word
    }

    func isEnabled(mode: ExplainMode) -> Bool {
        switch (self, mode) {
        case (.etymologyEN, .sentence), (.mnemonicEN, .sentence), (.wordFamilyEN, .sentence):
            return false
        default:
            return true
        }
    }

    /// Recommended max_tokens cap per module/mode/detail.
    /// Base values are sized for mid/large local models (7B+); known small
    /// models (e.g. gemma-4) get tighter caps below to stay fast.
    func recommendedMaxTokens(
        mode: ExplainMode,
        detail: ExplainDetail,
        modelIdentifier: String? = nil
    ) -> Int {
        let base: Int
        switch (self, mode, detail) {
        // Definition
        case (.definitionEN, .word, .short):        base = 256
        case (.definitionEN, .word, .detailed):     base = 512
        case (.definitionEN, .sentence, .short):    base = 256
        case (.definitionEN, .sentence, .detailed): base = 512
        // TR Meaning — Turkish prose needs more room than English
        case (.meaningTR, .word, .short):           base = 320
        case (.meaningTR, .word, .detailed):        base = 640
        case (.meaningTR, .sentence, .short):       base = 320
        case (.meaningTR, .sentence, .detailed):    base = 640
        // Collocations — markdown numbered list format needs more room
        case (.collocations, .word, .short):        base = 800
        case (.collocations, .word, .detailed):     base = 1400
        case (.collocations, .sentence, .short):    base = 600
        case (.collocations, .sentence, .detailed): base = 1100
        // Examples
        case (.examplesEN, .word, .short):          base = 240
        case (.examplesEN, .word, .detailed):       base = 400
        case (.examplesEN, .sentence, .short):      base = 240
        case (.examplesEN, .sentence, .detailed):   base = 320
        // Etymology (word only)
        case (.etymologyEN, _, .short):             base = 200
        case (.etymologyEN, _, .detailed):          base = 320
        // Pronunciation
        case (.pronunciationEN, .word, .short):     base = 64
        case (.pronunciationEN, .word, .detailed):  base = 64
        case (.pronunciationEN, .sentence, .short): base = 120
        case (.pronunciationEN, .sentence, .detailed): base = 180
        // Mnemonic (word only)
        case (.mnemonicEN, _, .short):              base = 120
        case (.mnemonicEN, _, .detailed):           base = 200
        // Synonyms & Antonyms
        case (.synonymsEN, .word, .short):          base = 280
        case (.synonymsEN, .word, .detailed):       base = 480
        case (.synonymsEN, .sentence, .short):      base = 200
        case (.synonymsEN, .sentence, .detailed):   base = 300
        // Word Family (word only; sentence disabled but keep exhaustive)
        case (.wordFamilyEN, _, .short):            base = 280
        case (.wordFamilyEN, _, .detailed):         base = 440
        // Usage Notes
        case (.usageNotesEN, .word, .short):        base = 320
        case (.usageNotesEN, .word, .detailed):     base = 600
        case (.usageNotesEN, .sentence, .short):    base = 260
        case (.usageNotesEN, .sentence, .detailed): base = 420
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
        nativeLanguage: Language = Language.storedNative,
        targetLanguage: Language = Language.storedTarget,
        level: CEFRLevel = CEFRLevel.storedLearnerLevel
    ) -> String {
        let domainLine = domain != .general
            ? "\nDomain: \(domain.rawValue). Adapt the explanation."
            : ""
        let target = targetLanguage.rawValue
        let native = nativeLanguage.rawValue
        let context = context.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }

        let ctxBlock = context.map {
            """
            \nContext sentence: "\($0)"
            """
        } ?? ""
        // v19 S1 (measured): modules that didn't read the sentence answered
        // for another sense of the word — the money "bank" for a river bank.
        let senseLine = context != nil ? "\nUse the sense the word has in the context sentence." : ""
        // v19 S1: the reader's level; answers were written for advanced readers.
        let levelLine = "\nThe reader is a \(level.rawValue) learner of \(target): use words a \(level.rawValue) learner knows."

        switch (self, mode) {

        // ──────────────────────────────────────
        // MARK: Definition
        // ──────────────────────────────────────

        // Two paragraphs with a context sentence: `ContextAwareResultView`
        // shows the first as "In This Context", the rest as "General Meaning".
        case (.definitionEN, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Define it in \(target), like a learner's dictionary: start with the part of speech in brackets, e.g. (verb), then plain words.\(levelLine)
            \(context != nil
                ? "Write exactly 2 short paragraphs. First: its meaning in this sentence, in one sentence. Second: its other common meanings, in one or two sentences."
                : (detail == .short ? "Write one sentence for the main meaning." : "Write one sentence for the main meaning, then one or two for its other common meanings."))
            """

        case (.definitionEN, .sentence):
            return """
            Sentence: \(term)\(domainLine)

            Explain what this sentence means in plain \(target).\(levelLine)
            Name any phrase or structure that makes it hard to read.
            \(detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Meaning in your language
        // ──────────────────────────────────────

        case (.meaningTR, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Give its meaning in \(native).
            \(nativeLanguage.promptInstruction)
            \(context != nil
                ? "Write exactly 2 short paragraphs. First: the \(native) equivalent for this sentence in quotes, then one sentence on why it fits — do not translate the whole sentence. Second: its other common meanings in \(native)."
                : (detail == .short ? "Start with the \(native) equivalents in quotes, then one sentence." : "Start with the \(native) equivalents in quotes, then at most 2 short paragraphs."))
            """

        case (.meaningTR, .sentence):
            return """
            Sentence: \(term)\(domainLine)

            Explain this sentence in \(native).
            \(nativeLanguage.promptInstruction)
            \(detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Collocations
        // ──────────────────────────────────────

        // The literal `*Example:*` / `*Translation:*` labels are parser
        // targets (`ResultParser.parseCollocationEntries`) — always English,
        // never localized; only the bracketed content follows the languages.
        case (.collocations, .word):
            let count = detail == .short ? 3 : 5
            return """
            Word: \(term)\(domainLine)\(ctxBlock)

            List \(count) common collocations.\(senseLine) Use exactly this format:

            N. **[collocation]:** [meaning in \(native), \(native) only]
               - *Example:* "[one simple \(target) example sentence]"
               - *Translation:* "[\(native) translation of the example]"

            Fill in each [bracketed part] and leave the brackets out. Blank line between items. Start numbering at 1.
            """

        case (.collocations, .sentence):
            let count = detail == .short ? 2 : 4
            return """
            Sentence: \(term)\(domainLine)

            Extract \(count) key collocations or phrases from this sentence. Use exactly this format:

            N. **[collocation/phrase]:** [meaning in \(native), \(native) only]
               - *Example:* "[one short \(target) example sentence using this collocation]"
               - *Translation:* "[\(native) translation of the example]"

            Fill in each [bracketed part] and leave the brackets out. Blank line between items. Start numbering at 1.
            """

        // ──────────────────────────────────────
        // MARK: Examples
        // ──────────────────────────────────────

        case (.examplesEN, .word):
            let count = detail == .short ? 3 : 5
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Write exactly \(count) new example sentences using it.\(senseLine)\(levelLine)
            Keep them short and everyday.\(context != nil ? " Do not repeat the context sentence." : "")
            One sentence per line.
            """

        case (.examplesEN, .sentence):
            let count = detail == .short ? 3 : 5
            return """
            \(term)\(domainLine)

            Paraphrase this sentence \(count) different ways.\(levelLine)
            One paraphrase per line.
            """

        // ──────────────────────────────────────
        // MARK: Etymology — word only
        // ──────────────────────────────────────

        case (.etymologyEN, .word):
            return """
            Word: \(term)\(ctxBlock)

            Give the etymology of this word.\(context != nil ? " If its senses come from different words, give the origin of the sense in the context sentence." : "")
            Give only well-attested history. If the origin is uncertain, say so in one sentence instead of guessing.
            \(detail == .short ? "Write 1 short paragraph." : "Write at most 2 short paragraphs.")
            """

        // ──────────────────────────────────────
        // MARK: Pronunciation
        // ──────────────────────────────────────

        case (.pronunciationEN, .word):
            return """
            \(term)\(ctxBlock)
            \(context != nil ? "\nIf its pronunciation depends on the sense, use the sense in the context sentence.\n" : "")
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
        // MARK: Memory hook — word only
        // ──────────────────────────────────────

        // v19 S1: the keyword method — a sound-alike in your language tied
        // to the meaning by a picture. English sound-alikes in English
        // ("actual sounds like act") helped a reader little.
        case (.mnemonicEN, .word):
            return """
            Word: \(term)\(ctxBlock)

            Write a memory hook in \(native) for this \(target) word.\(senseLine)
            \(nativeLanguage.promptInstruction)
            Find a \(native) word or phrase that sounds like "\(term)", put it in quotes, and link it to the meaning with one vivid picture.
            Never use a \(native) look-alike whose meaning differs (a false friend) as if it meant the same; if the obvious sound-alike is one, warn about it in the hook.
            \(detail == .short ? "Use 1-2 sentences." : "Use at most 3 sentences.")
            """

        // ──────────────────────────────────────
        // MARK: Synonyms & Antonyms
        // ──────────────────────────────────────

        case (.synonymsEN, .word):
            let synCount = detail == .short ? 3 : 5
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            List \(synCount) synonyms with a short nuance note for each, in simple words.\(senseLine)
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
        // MARK: Word Family — word only
        // ──────────────────────────────────────

        case (.wordFamilyEN, .word):
            return """
            Word/Phrase: \(term)\(ctxBlock)

            List common words formed from the same root.\(senseLine) Only real, common words, each with its correct part of speech.
            If it is a phrasal verb or an idiom, list instead 2–3 related expressions that share its key word and meaning area, marked (phrase).
            Format: (part of speech) form — one short example sentence
            \(detail == .short ? "Include the 3–4 most useful forms." : "Include all common forms: noun, verb, adjective, adverb, and any notable compounds.")
            """

        // ──────────────────────────────────────
        // MARK: Usage Notes
        // ──────────────────────────────────────

        case (.usageNotesEN, .word):
            return """
            Word/Phrase: \(term)\(domainLine)\(ctxBlock)

            Provide usage notes using exactly these labels, one per line.\(senseLine)
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
