//
//  ReadingLoop.swift
//  Reader for Language Learner
//
//  Before and after the page (Roadmap v13 Sprint 2): a recap when you come
//  back to a book after a break, and the hard words of a chapter before you
//  start it. The pure parts — when, what text, which words, how to read the
//  model's answer — live here; `ReadingLoopModel` runs them.
//

import Foundation
import NaturalLanguage

// MARK: - Learner level

extension CEFRLevel {
    /// The reader's own level, set in Settings ▸ General. Recaps, warm-ups
    /// and simplified text are pitched at it. B1 until they say otherwise.
    static let defaultLearnerLevel: CEFRLevel = .b1

    static var storedLearnerLevel: CEFRLevel {
        UserDefaults.standard.string(forKey: StorageKey.learnerLevel)
            .flatMap(CEFRLevel.init(rawValue:)) ?? defaultLearnerLevel
    }
}

// MARK: - Recap

nonisolated enum ReadingRecap {

    /// A break this long earns a recap on return.
    static let minimumGap: TimeInterval = 3 * 86_400

    /// Characters of reading sent to the model. The on-device model's window
    /// is 4096 tokens and a chapter runs ~7k; the pages just before the
    /// bookmark are the part that says where the reader is.
    static let passageLimit = 6_000

    /// Thinking models spend a few hundred tokens before answering; the v13
    /// spike got an empty reply from a local Gemma at 300.
    static let maxTokens = 1_200

    static func isDue(lastOpenedAt: Date?, now: Date = Date(), hasProgress: Bool) -> Bool {
        guard hasProgress, let lastOpenedAt else { return false }
        return now.timeIntervalSince(lastOpenedAt) >= minimumGap
    }

    /// Whole days since the book was last open, when that's long enough for
    /// a recap — for the dashboard to say one is coming.
    static func daysAway(lastOpenedAt: Date, now: Date = Date(), hasProgress: Bool) -> Int? {
        guard isDue(lastOpenedAt: lastOpenedAt, now: now, hasProgress: hasProgress) else { return nil }
        return Int(now.timeIntervalSince(lastOpenedAt) / 86_400)
    }

    /// The reading just before the bookmark: `earlier` (the previous chapter
    /// or pages) followed by `current` up to `fraction`, trimmed to the
    /// last `limit` characters, starting on a word.
    static func passage(current: String, upTo fraction: Double = 1, earlier: String = "", limit: Int = passageLimit) -> String {
        let clamped = min(1, max(0, fraction))
        let readCount = Int((Double(current.count) * clamped).rounded())
        let read = earlier + (earlier.isEmpty ? "" : "\n\n") + String(current.prefix(readCount))
        guard read.count > limit else { return read.trimmingCharacters(in: .whitespacesAndNewlines) }
        var tail = String(read.suffix(limit))
        if let space = tail.firstIndex(where: \.isWhitespace) {
            tail = String(tail[space...])
        }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func systemPrompt(language: Language, level: CEFRLevel) -> String {
        """
        You help a language learner pick a book back up after a break. Summarize \
        what happened in the passage they last read, in 3 short sentences, in \
        simple \(language.rawValue) at CEFR \(level.rawValue) level. Only use what \
        is in the passage — never guess what happens next. No title, no list, \
        no preamble.
        """
    }

    static func userPrompt(passage: String) -> String {
        "Passage:\n\(passage)"
    }

    /// The model's answer as shown: preamble lines ("Here is a summary:") and
    /// list markers dropped, whitespace collapsed. nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !isPreamble($0) }
            .map { line in
                var line = line
                while let first = line.first, "-*•#".contains(first) {
                    line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return line
            }
        let text = lines.joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// A line that introduces the answer instead of being it — ends in a
    /// colon, or is the model introducing itself.
    static func isPreamble(_ line: String) -> Bool {
        let lower = line.lowercased()
        return line.hasSuffix(":")
            || lower.hasPrefix("i am a ")
            || lower.hasPrefix("here is")
            || lower.hasPrefix("here's")
    }
}

// MARK: - Chapter warm-up

nonisolated enum ChapterWarmUp {

    struct Word: Equatable, Sendable, Identifiable {
        let term: String
        let definition: String
        /// The first sentence in the chapter it appears in.
        var sentence: String
        var id: String { term.lowercased() }
    }

    static let maxWords = 6
    /// Candidates offered to the model. ~250 short lemmas fit the on-device
    /// window with room to spare.
    static let maxCandidates = 250
    /// Shorter words are almost always everyday ones; the spike's
    /// frequency-ranked list was all "understand", "moment", "clear".
    static let minimumLength = 6
    static let maxTokens = 1_200

    /// Content-word lemmas in the chapter that could be hard: nouns, verbs,
    /// adjectives and adverbs, at least `minimumLength` letters, not names
    /// (tagged or capitalised mid-text), not already saved. Alphabetical, so
    /// the list the model sees carries no hint of frequency — frequency is
    /// what made the first candidate list easy.
    static func candidates(in text: String, language: Language?, excludingKeys saved: Set<String>) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = text
        if let nl = LemmaMatcher.nlLanguage(for: language) {
            tagger.setLanguage(nl, range: text.startIndex..<text.endIndex)
        }
        let content: Set<NLTag> = [.noun, .verb, .adjective, .adverb]
        let names: Set<NLTag> = [.personalName, .placeName, .organizationName]
        var lemmas: Set<String> = []

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .omitOther, .joinNames]
        ) { tag, range in
            guard let tag, content.contains(tag) else { return true }
            let (name, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
            if let name, names.contains(name) { return true }
            let surface = String(text[range])
            guard surface.count >= minimumLength,
                  surface.allSatisfy(\.isLetter),
                  surface.first?.isLowercase == true
            else { return true }
            let (lemma, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
            let key = (lemma?.rawValue.isEmpty == false ? lemma!.rawValue : surface).lowercased()
            guard !saved.contains(key), !saved.contains(surface.lowercased()) else { return true }
            lemmas.insert(key)
            return true
        }
        return Array(lemmas.sorted().prefix(maxCandidates))
    }

    /// `answerIn` is the hover dictionary's language — the warm-up is a
    /// preview of the same lookups.
    static func systemPrompt(target: Language, answerIn: Language, level: CEFRLevel) -> String {
        """
        You help a language learner prepare for a chapter of a \(target.rawValue) \
        book. From the word list, pick the \(maxWords) words a CEFR \(level.rawValue) \
        learner is least likely to know that matter for understanding the chapter. \
        Skip easy everyday words. For each, give a short definition in simple \
        \(answerIn.rawValue) (at most 10 words). One per line, exactly:
        word | definition
        """
    }

    static func userPrompt(candidates: [String]) -> String {
        "Words: " + candidates.joined(separator: ", ")
    }

    /// Strict parse: only `word | definition` lines whose word was actually
    /// offered, first `maxWords`, no repeats. Preambles and chatter fall out
    /// because they don't have that shape.
    static func parse(_ raw: String, offered: [String]) -> [Word] {
        let allowed = Set(offered.map { $0.lowercased() })
        var seen: Set<String> = []
        var words: [Word] = []
        for line in raw.components(separatedBy: .newlines) {
            let parts = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "*-•`")))
            }
            guard parts.count == 2 else { continue }
            let term = parts[0].lowercased()
            let definition = parts[1]
            guard allowed.contains(term), !definition.isEmpty, !seen.contains(term) else { continue }
            seen.insert(term)
            words.append(Word(term: term, definition: definition, sentence: ""))
            if words.count == maxWords { break }
        }
        return words
    }

    /// Fills each word's sentence from the chapter; words the scanner can't
    /// place (the model's lemma differs from any form in the text) keep none.
    static func attachSentences(_ words: [Word], chapter: String, language: Language?) -> [Word] {
        let entries = words.map { EncounterScanner.Entry(id: UUID(), term: $0.term) }
        let hits = EncounterScanner.scan(text: chapter, vocabulary: entries, language: language)
        let sentenceByID = Dictionary(uniqueKeysWithValues: hits.map { ($0.wordID, $0.sentence) })
        return zip(words, entries).map { word, entry in
            var word = word
            word.sentence = sentenceByID[entry.id] ?? ""
            return word
        }
    }
}

// MARK: - Interlinear gloss

/// A few words of meaning drawn above a word in the book (Roadmap v13
/// Sprint 3) — for the words the app knows are hard for this reader: saved
/// words still being learned, and the chapter's warm-up words.
nonisolated enum InterlinearGloss {

    /// Longest gloss drawn. Above a word there's room for two or three short
    /// words; a sentence would run into its neighbours.
    static let maxLength = 28
    /// Words asked for in one request.
    static let maxBatch = 60
    static let maxTokens = 1_200

    static func systemPrompt(target: Language, answerIn: Language, level: CEFRLevel) -> String {
        """
        You write tiny glosses for a CEFR \(level.rawValue) learner reading a \
        \(target.rawValue) book. For each word, give its most common meaning in \
        \(answerIn.rawValue) in 1 to 3 words — like a note written above the word. \
        One per line, exactly:
        word | gloss
        """
    }

    static func userPrompt(words: [String]) -> String {
        "Words: " + words.joined(separator: ", ")
    }

    /// Strict parse: `word | gloss` lines for words that were asked for;
    /// a gloss too long to sit above a word is cut at a word boundary or,
    /// failing that, dropped.
    static func parse(_ raw: String, requested: [String]) -> [String: String] {
        let allowed = Set(requested.map { $0.lowercased() })
        var result: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let parts = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "*-•`\"")))
            }
            guard parts.count == 2 else { continue }
            let term = parts[0].lowercased()
            guard allowed.contains(term), result[term] == nil,
                  let gloss = fit(parts[1])
            else { continue }
            result[term] = gloss
        }
        return result
    }

    /// Trailing punctuation dropped; over `maxLength`, cut back to the last
    /// whole word that fits, or nil when even the first word doesn't.
    static func fit(_ raw: String) -> String? {
        var gloss = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !gloss.isEmpty else { return nil }
        if gloss.count > maxLength {
            let words = gloss.split(separator: " ")
            var kept = ""
            for word in words {
                let next = kept.isEmpty ? String(word) : kept + " " + word
                guard next.count <= maxLength else { break }
                kept = next
            }
            gloss = kept.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        }
        return gloss.isEmpty ? nil : gloss
    }
}

// MARK: - Graded rewrite

/// A passage rewritten at the reader's level, shown next to the original
/// (Roadmap v13 Sprint 3) — for the paragraph that lost them.
nonisolated enum GradedRewrite {

    /// Below this there's nothing to simplify — the hover dictionary and the
    /// inspector already cover a word or a short phrase.
    static let minimumWords = 6
    /// Characters sent. A long selection is cut at a sentence boundary.
    static let maxInput = 2_500
    static let maxTokens = 1_600

    static func isEligible(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count >= minimumWords
    }

    /// The selection trimmed to `maxInput`, ending on a full sentence when
    /// one ends inside the limit.
    static func input(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxInput else { return trimmed }
        let head = String(trimmed.prefix(maxInput))
        if let end = head.lastIndex(where: { ".!?…".contains($0) }) {
            return String(head[...end])
        }
        return head
    }

    static func systemPrompt(language: Language, level: CEFRLevel) -> String {
        """
        Rewrite the passage in simple \(language.rawValue) for a CEFR \(level.rawValue) \
        learner. Keep the meaning, the names and the order of events. Split long \
        sentences and use common words instead of rare ones. Add nothing that isn't \
        in the passage. Output only the rewritten passage, no title or preamble.
        """
    }

    static func userPrompt(passage: String) -> String {
        "Passage:\n\(passage)"
    }

    /// The model's answer with preamble lines dropped and markdown bold
    /// removed; paragraph breaks are kept.
    static func clean(_ raw: String) -> String? {
        let lines = raw.components(separatedBy: .newlines)
        let kept = lines.drop { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || ReadingRecap.isPreamble(trimmed)
        }
        let text = kept.joined(separator: "\n")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
