//
//  WordEncounter.swift
//  Reader for Language Learner
//
//  A saved word met again while reading (Roadmap v13 Sprint 1). The encounter
//  log is display-only: meeting a word on a page is exposure, not recall, so
//  nothing here ever reaches the scheduler.
//

import Foundation
import NaturalLanguage

/// One passage in which a saved word turned up.
nonisolated struct WordEncounter: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let wordID: UUID
    /// Path of the document on disk — what reopening it needs.
    let documentPath: String
    /// Human-readable title at the time of reading.
    let documentTitle: String
    /// 0-based PDF page or EPUB chapter.
    let location: Int
    let isEPUB: Bool
    /// The first sentence on that page/chapter the word appeared in.
    let sentence: String
    /// How many times it appeared there.
    let occurrences: Int
    let date: Date

    init(
        id: UUID = UUID(),
        wordID: UUID,
        documentPath: String,
        documentTitle: String,
        location: Int,
        isEPUB: Bool,
        sentence: String,
        occurrences: Int,
        date: Date
    ) {
        self.id = id
        self.wordID = wordID
        self.documentPath = documentPath
        self.documentTitle = documentTitle
        self.location = location
        self.isEPUB = isEPUB
        self.sentence = sentence
        self.occurrences = occurrences
        self.date = date
    }
}

/// Finds saved vocabulary in a passage and the sentence each word first
/// appears in. Pure and `nonisolated` — a chapter-sized pass belongs off the
/// main actor.
nonisolated enum EncounterScanner {

    struct Entry: Sendable, Hashable {
        let id: UUID
        let term: String
    }

    struct Hit: Sendable, Equatable {
        let wordID: UUID
        let sentence: String
        let occurrences: Int
    }

    /// Longest sentence kept. PDF text can run a whole paragraph together when
    /// the page has no terminal punctuation; past this the sentence is cut to
    /// a window around the match.
    static let maxSentenceLength = 280

    static func scan(text: String, vocabulary: [Entry], language: Language?) -> [Hit] {
        guard !text.isEmpty, !vocabulary.isEmpty else { return [] }

        // Single words match through the lemma tagger (inflections count);
        // phrases can't be tagged as one token, so they match literally.
        var idsByKey: [String: [UUID]] = [:]
        var phrases: [Entry] = []
        for entry in vocabulary {
            let literal = entry.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !literal.isEmpty else { continue }
            if literal.contains(" ") {
                phrases.append(entry)
                continue
            }
            // Both keys, as `SavedWordsStore.lemmaKeys` does: a lone term is
            // sometimes lemmatized wrongly where the same word in a sentence
            // is not.
            var keys: Set<String> = [literal]
            keys.insert(LemmaMatcher.matchKey(for: literal, language: language))
            for key in keys where !key.isEmpty {
                idsByKey[key, default: []].append(entry.id)
            }
        }

        let nsText = text as NSString
        var matches: [UUID: [NSRange]] = [:]
        var order: [UUID] = []

        func record(_ id: UUID, _ range: NSRange) {
            if matches[id] == nil { order.append(id) }
            matches[id, default: []].append(range)
        }

        if !idsByKey.isEmpty {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = text
            if let nl = LemmaMatcher.nlLanguage(for: language) {
                tagger.setLanguage(nl, range: text.startIndex..<text.endIndex)
            }
            tagger.enumerateTags(
                in: text.startIndex..<text.endIndex,
                unit: .word,
                scheme: .lemma,
                options: [.omitPunctuation, .omitWhitespace, .omitOther]
            ) { tag, range in
                let surface = text[range].lowercased()
                guard !surface.isEmpty else { return true }
                var ids: Set<UUID> = []
                if let lemma = tag?.rawValue.lowercased(), !lemma.isEmpty {
                    ids.formUnion(idsByKey[lemma] ?? [])
                }
                ids.formUnion(idsByKey[surface] ?? [])
                guard !ids.isEmpty else { return true }
                let nsRange = NSRange(range, in: text)
                for id in ids { record(id, nsRange) }
                return true
            }
        }

        for phrase in phrases {
            for range in TermMatcher.ranges(of: phrase.term, in: nsText) {
                record(phrase.id, range)
            }
        }

        guard !order.isEmpty else { return [] }
        let sentences = sentenceRanges(in: text)
        return order.compactMap { id in
            guard let ranges = matches[id], let firstRange = ranges.first else { return nil }
            // The first occurrence on a PDF page is often its running head or
            // a section title ("REM-Sleep Dreaming"). Prefer the first one
            // that sits in actual prose; fall back to the first at all.
            let candidates = ranges.lazy.map {
                self.sentence(containing: $0, sentences: sentences, in: nsText)
            }
            let sentence = candidates.first(where: isProse)
                ?? self.sentence(containing: firstRange, sentences: sentences, in: nsText)
            guard !sentence.isEmpty else { return nil }
            return Hit(wordID: id, sentence: sentence, occurrences: ranges.count)
        }
    }

    /// Fewest words a sentence needs to read as prose rather than a heading.
    static let minimumProseWords = 6

    /// A sentence worth showing: enough words to be more than a title. Scripts
    /// without spaces between words count characters instead.
    static func isProse(_ sentence: String) -> Bool {
        if !TermMatcher.usesWholeWordMatching(sentence) {
            return sentence.count >= minimumProseWords * 2
        }
        return sentence.split(whereSeparator: \.isWhitespace).count >= minimumProseWords
    }

    // MARK: - Sentences

    private static func sentenceRanges(in text: String) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { NSRange($0, in: text) }
    }

    static func sentence(containing match: NSRange, sentences: [NSRange], in text: NSString) -> String {
        let enclosing = sentences.first { NSLocationInRange(match.location, $0) }
            ?? NSRange(location: 0, length: text.length)
        var range = enclosing
        if range.length > maxSentenceLength {
            // A window centred on the match, clamped to the sentence.
            let half = maxSentenceLength / 2
            let start = max(enclosing.location, match.location - half)
            let end = min(NSMaxRange(enclosing), start + maxSentenceLength)
            range = NSRange(location: start, length: end - start)
        }
        return normalize(text.substring(with: range))
    }

    /// PDF page text carries line breaks and end-of-line hyphenation; a
    /// sentence shown on its own should read as one line.
    static func normalize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
