//
//  WordFill.swift
//  Reader for Language Learner
//
//  The parts of a saved word's card that can be filled in for you (Roadmap
//  v15 Sprint 1), where each filled value came from, and the pure rules for
//  turning a macOS dictionary entry or a model's answer into a card field.
//  The service that runs the fill is `WordEnricher`.
//
//  S0 measured the sources on the user's 59 words: the system dictionary
//  found all of them (instant, offline) and answers in whichever language
//  its first matching dictionary is written in; Apple's on-device model gave
//  a usable definition for 8 of 8 in ~0.4 s; a local server model returned
//  one empty answer in 8. Hence the order: dictionary, on-device model, then
//  the configured provider, and nothing that fails validation is written.
//

import Foundation
import NaturalLanguage

// MARK: - Fields

/// A card field that can be filled. Raw values key `SavedWord.fieldSources`
/// and must not change.
enum FillField: String, CaseIterable, Identifiable, Codable {
    case meaning
    case definition
    case pronunciation
    case level
    case examples

    var id: String { rawValue }

    /// The `llmOutputs` key the field is stored under; nil for the level,
    /// which lives in `cefrLevel`.
    var module: ModuleType? {
        switch self {
        case .meaning:       return .meaningTR
        case .definition:    return .definitionEN
        case .pronunciation: return .pronunciationEN
        case .examples:      return .examplesEN
        case .level:         return nil
        }
    }

    /// Fields the fill sheet ticks by default and the save-time fill runs.
    /// Examples are off: most words already carry the sentence they were
    /// saved from, and the card shows it.
    static let defaultSelection: Set<FillField> = [.meaning, .definition, .pronunciation, .level]

    func isMissing(in word: SavedWord) -> Bool {
        switch self {
        case .level:
            return word.cefrLevel == nil
        default:
            guard let module else { return false }
            return (word.llmOutputs[module.rawValue] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func value(in word: SavedWord) -> String? {
        switch self {
        case .level:
            return word.cefrLevel
        default:
            guard let module, let text = word.llmOutputs[module.rawValue] else { return nil }
            let cleaned = MarkdownUtils.sanitizeLLMOutput(text).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    var localizedTitle: String {
        switch self {
        case .meaning:
            return String(localized: "\(Self.languageName(Language.storedNative)) meaning")
        case .definition:
            return String(localized: "\(Self.languageName(Language.storedTarget)) definition")
        case .pronunciation: return String(localized: "Pronunciation")
        case .level:         return String(localized: "Level")
        case .examples:      return String(localized: "Examples")
        }
    }

    /// Where the field can come from, for the fill sheet.
    var sourceHint: String {
        switch self {
        case .meaning, .definition: return String(localized: "From the dictionary, else the model")
        case .pronunciation:        return String(localized: "Dictionary only")
        case .level:                return String(localized: "Model")
        case .examples:             return String(localized: "The model writes them")
        }
    }

    /// The language's name in the interface language ("İngilizce" in a
    /// Turkish interface), capitalised.
    static func languageName(_ language: Language) -> String {
        let code = language.shortCode.lowercased()
        let name = Locale.current.localizedString(forLanguageCode: code) ?? language.nativeName
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

// MARK: - Sources

/// Where a filled value came from. Stored as a string in
/// `SavedWord.fieldSources`; a field without an entry was saved from the
/// inspector or typed by you.
enum FillSource: Equatable, Hashable {
    case dictionary
    case onDevice
    case provider(String)

    init?(stored: String) {
        switch stored {
        case "dictionary": self = .dictionary
        case "onDevice":   self = .onDevice
        default:
            guard stored.hasPrefix("provider:") else { return nil }
            self = .provider(String(stored.dropFirst("provider:".count)))
        }
    }

    var stored: String {
        switch self {
        case .dictionary:         return "dictionary"
        case .onDevice:           return "onDevice"
        case .provider(let name): return "provider:\(name)"
        }
    }

    /// The three columns of the fill summary.
    enum Kind: CaseIterable { case dictionary, model, provider }

    var kind: Kind {
        switch self {
        case .dictionary: return .dictionary
        case .onDevice:   return .model
        case .provider:   return .provider
        }
    }

    var label: String {
        switch self {
        case .dictionary:         return String(localized: "Dictionary")
        case .onDevice:           return String(localized: "Model")
        case .provider(let name): return name
        }
    }
}

// MARK: - Dictionary entries

/// A macOS dictionary entry, split into what a card can use.
///
/// Entries come back as one line: `headword | IPA | body`. A bilingual
/// (English–Turkish) body reads `n hayvan gübresi ▸ phrase …`; a
/// monolingual one `noun a person who …: example. • second sense
/// DERIVATIVES …`. The headword is the dictionary's lemma, which can differ
/// from the saved form ("lolled" → "loll").
struct DictionaryEntry: Equatable {
    let headword: String
    let ipa: String?
    let body: String

    init?(raw: String) {
        let parts = raw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 3 {
            headword = parts[0]
            ipa = parts[1].isEmpty ? nil : parts[1]
            body = parts[2]
        } else {
            headword = ""
            ipa = nil
            body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !body.isEmpty else { return nil }
    }

    /// The pronunciation as a card shows it, only when the entry is for
    /// the saved form itself — the lemma's IPA is wrong for "lolled".
    func pronunciation(for term: String) -> String? {
        guard let ipa, Self.sameWord(headword, term) else { return nil }
        return "/\(ipa)/"
    }

    /// The first two senses, without parts of speech, examples, phrases or
    /// derivatives. Approved v15 S1 decision 4: the whole entry stays one
    /// click away in Dictionary.
    var briefSenses: String? {
        var text = body
        for marker in ["▸", " DERIVATIVES", " ORIGIN", " PHRASES", " PHRASAL VERBS", " USAGE"] {
            if let range = text.range(of: marker) { text = String(text[..<range.lowerBound]) }
        }
        text = Self.droppingLeadingPartOfSpeech(text)
        // The first part-of-speech group only: a second one ("intransitive
        // verb past participle, past slept…") is mostly grammar.
        if let range = Self.nextPartOfSpeech(in: text) { text = String(text[..<range.lowerBound]) }

        let senses: [String]
        if text.contains("•") || text.range(of: #"(^|\s)\d\s"#, options: .regularExpression) != nil {
            senses = text
                .replacingOccurrences(of: #"(^|\s)\d\s"#, with: "•", options: .regularExpression)
                .components(separatedBy: "•")
        } else {
            senses = text.components(separatedBy: ";")
        }
        let cleaned = senses
            .map(Self.droppingExample)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "()")))) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.prefix(2).joined(separator: "; ")
    }

    // MARK: Parsing helpers

    private static let partsOfSpeech = [
        "intransitive verb", "transitive verb", "phrasal verb", "auxiliary verb", "modal verb",
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction",
        "exclamation", "interjection", "determiner", "abbreviation", "plural noun",
        "n", "adj", "adv", "pron", "prep", "conj", "interj", "abbr", "pl",
    ]

    private static func droppingLeadingPartOfSpeech(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        // Longest first, so "transitive verb" isn't read as "verb".
        for pos in partsOfSpeech.sorted(by: { $0.count > $1.count }) where result.hasPrefix(pos + " ") {
            result = String(result.dropFirst(pos.count + 1))
            break
        }
        // "[with object]" style labels after the part of speech.
        while result.hasPrefix("["), let close = result.firstIndex(of: "]") {
            result = String(result[result.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func nextPartOfSpeech(in text: String) -> Range<String.Index>? {
        partsOfSpeech
            .compactMap { text.range(of: " \($0) ") }
            .min { $0.lowerBound < $1.lowerBound }
    }

    /// "a person who …: the twins were arch-enemies." → "a person who …"
    private static func droppingExample(_ sense: String) -> String {
        guard let colon = sense.range(of: ": ") else { return sense }
        return String(sense[..<colon.lowerBound])
    }

    /// Case, hyphens and spaces don't make a different word
    /// ("arch-enemy" is "archenemy").
    static func sameWord(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter }
        }
        let left = key(a)
        return !left.isEmpty && left == key(b)
    }
}

// MARK: - Validation

enum FillValidator {
    /// A model's answer as it may be stored, or nil when it shouldn't be:
    /// empty, the word repeated back, a refusal or preamble, or confidently
    /// written in another language than asked for.
    static func accept(_ raw: String, term: String, language: Language, field: FillField) -> String? {
        let text = MarkdownUtils.sanitizeLLMOutput(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 1_200 else { return nil }
        guard !DictionaryEntry.sameWord(text, term) else { return nil }
        let lowered = text.lowercased()
        for opener in ["i am ", "i'm ", "as an ai", "i cannot", "i can't", "sorry"] where lowered.hasPrefix(opener) {
            return nil
        }
        // A short answer ("gübre") is too little for a language guess; the
        // examples mix both languages by design.
        if field != .examples, text.count >= 24,
           let detected = SystemDictionary.detectedLanguage(of: text),
           detected != language {
            return nil
        }
        return text
    }
}
