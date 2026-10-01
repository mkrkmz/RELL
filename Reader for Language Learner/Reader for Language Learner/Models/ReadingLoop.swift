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

// MARK: - Retell

/// "Retell it in your own words" (Roadmap v13 Sprint 4): the learner writes,
/// the model corrects, and the difference is shown word by word.
nonisolated enum Retell {

    struct Feedback: Equatable {
        let corrected: String
        let note: String
    }

    static let maxTokens = 1_600
    /// Parser-bound labels — English and fixed, whatever the languages.
    static let correctedLabel = "CORRECTED:"
    static let noteLabel = "NOTE:"

    static func systemPrompt(target: Language, native: Language, level: CEFRLevel) -> String {
        """
        You are a kind \(target.rawValue) teacher. A CEFR \(level.rawValue) learner \
        read the ORIGINAL passage and retold it in their own words. First correct \
        their text: fix grammar, spelling and word choice, but keep their own words \
        and ideas wherever they work. Then, in one or two short sentences in \
        \(native.rawValue), say whether the retelling got the passage's meaning and \
        name the most useful fix. Reply in exactly this format:
        \(correctedLabel)
        <the corrected text>
        \(noteLabel)
        <your note>
        """
    }

    static func userPrompt(original: String, retelling: String) -> String {
        "ORIGINAL:\n\(original)\n\nLEARNER'S RETELLING:\n\(retelling)"
    }

    /// Reads the two labelled parts; nil when the corrected text is missing.
    static func parse(_ raw: String) -> Feedback? {
        let text = raw.replacingOccurrences(of: "**", with: "")
        guard let correctedRange = text.range(of: correctedLabel, options: .caseInsensitive) else { return nil }
        let afterCorrected = text[correctedRange.upperBound...]
        let noteRange = afterCorrected.range(of: noteLabel, options: .caseInsensitive)
        let corrected = String(noteRange.map { afterCorrected[..<$0.lowerBound] } ?? afterCorrected)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let note = noteRange.map { String(afterCorrected[$0.upperBound...]) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !corrected.isEmpty else { return nil }
        return Feedback(corrected: corrected, note: note)
    }
}

/// Word-level difference between the learner's text and the correction.
nonisolated enum WordDiff {

    enum Kind: Equatable { case same, removed, added }

    struct Segment: Equatable {
        let kind: Kind
        let text: String
    }

    /// Longest-common-subsequence over whitespace-separated words; runs of
    /// the same kind are merged. Compared exactly — a fixed comma or capital
    /// is a fix worth showing.
    static func diff(_ old: String, _ new: String) -> [Segment] {
        let a = old.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = new.split(whereSeparator: \.isWhitespace).map(String.init)
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var words: [(Kind, String)] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                words.append((.same, a[i])); i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] > lcs[i + 1][j] {
                // Strictly greater: on a tie the old word goes first, so a
                // substitution reads "struck-out old, then new".
                words.append((.added, b[j])); j += 1
            } else {
                words.append((.removed, a[i])); i += 1
            }
        }
        var segments: [Segment] = []
        for (kind, word) in words {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = Segment(kind: kind, text: last.text + " " + word)
            } else {
                segments.append(Segment(kind: kind, text: word))
            }
        }
        return segments
    }

    /// Words the correction brought in — candidates to save. Letters only,
    /// at least three, first occurrence, in order.
    static func addedWords(_ segments: [Segment]) -> [String] {
        var seen: Set<String> = []
        return segments.filter { $0.kind == .added }
            .flatMap { $0.text.split(separator: " ") }
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 3 && $0.allSatisfy(\.isLetter) && seen.insert($0.lowercased()).inserted }
    }
}

// MARK: - Story from your words

/// A short story built around the words due for review (Roadmap v13
/// Sprint 4) — review by reading. It never touches the schedule.
nonisolated enum WordStory {

    struct Story: Equatable {
        let title: String
        let paragraphs: [String]
    }

    static let minimumWords = 4
    static let maximumWords = 12
    static let maxTokens = 2_000
    static let titleLabel = "TITLE:"
    static let storyLabel = "STORY:"

    static func systemPrompt(target: Language, level: CEFRLevel) -> String {
        """
        You write short stories for language learners. Write a story of about \
        300 words in simple \(target.rawValue) for a CEFR \(level.rawValue) learner. \
        Use every word from the list at least once, naturally, in a form that fits \
        the sentence. Keep everything else simple.
        Reply in this layout: the first line is \(titleLabel) followed by a title \
        of at most six words and nothing else; the second line is \(storyLabel) \
        on its own; then the story, in paragraphs. Write the story only once.
        """
    }

    static func userPrompt(words: [String]) -> String {
        "Words: " + words.joined(separator: ", ")
    }

    /// Longest title kept; past it, the "title" is really the story.
    static let maxTitleLength = 70

    static func parse(_ raw: String) -> Story? {
        let text = raw.replacingOccurrences(of: "**", with: "")
        guard let storyRange = text.range(of: storyLabel, options: .caseInsensitive) else { return nil }
        var title = ""
        if let titleRange = text.range(of: titleLabel, options: .caseInsensitive),
           titleRange.upperBound <= storyRange.lowerBound {
            // Only the title line. Seen live: the model copied the old
            // "<a short title>" placeholder and ran the whole story on after
            // it, then wrote it again under STORY: — the book showed it twice.
            let firstLine = text[titleRange.upperBound..<storyRange.lowerBound]
                .components(separatedBy: .newlines)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            title = cleanTitle(firstLine)
        }
        let paragraphs = text[storyRange.upperBound...]
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return nil }
        return Story(title: title.isEmpty ? String(localized: "A Story From Your Words") : title, paragraphs: paragraphs)
    }

    /// A title from its line: "<a strange night> The landlady found…" →
    /// "A strange night". Bracketed text wins; otherwise the line, unless it
    /// is too long to be a title.
    static func cleanTitle(_ line: String) -> String {
        var title = line.trimmingCharacters(in: .whitespaces)
        if title.hasPrefix("<"), let close = title.firstIndex(of: ">") {
            title = String(title[title.index(after: title.startIndex)..<close])
        }
        title = title.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'#<>*")))
        guard !title.isEmpty, title.count <= maxTitleLength else { return "" }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// Which of the words the story actually used, inflections included.
    static func usedWords(_ words: [String], in story: Story, language: Language?) -> [String] {
        let entries = words.map { EncounterScanner.Entry(id: UUID(), term: $0) }
        let hits = Set(EncounterScanner.scan(
            text: story.paragraphs.joined(separator: "\n"), vocabulary: entries, language: language
        ).map(\.wordID))
        return zip(words, entries).filter { hits.contains($0.1.id) }.map(\.0)
    }
}

// MARK: - Grammar lens

/// Parts of speech in a sentence, from the system tagger — offline and
/// instant (Roadmap v13 Sprint 5). The explanation of the structure is a
/// separate, optional model call.
nonisolated enum GrammarLens {

    enum Kind: String, CaseIterable, Sendable {
        case noun, verb, adjective, adverb, pronoun, determiner, preposition, conjunction, particle, number, other
    }

    struct Token: Equatable, Sendable {
        let text: String
        let kind: Kind
    }

    static let minimumWords = 3
    static let maxWords = 60
    static let maxTokens = 900

    static func tokens(in sentence: String, language: Language?) -> [Token] {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        if let nl = LemmaMatcher.nlLanguage(for: language) {
            tagger.setLanguage(nl, range: text.startIndex..<text.endIndex)
        }
        var tokens: [Token] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .omitOther]
        ) { tag, range in
            tokens.append(Token(text: String(text[range]), kind: kind(for: tag)))
            return tokens.count < maxWords
        }
        return tokens
    }

    static func kind(for tag: NLTag?) -> Kind {
        switch tag {
        case .noun?: return .noun
        case .verb?: return .verb
        case .adjective?: return .adjective
        case .adverb?: return .adverb
        case .pronoun?: return .pronoun
        case .determiner?: return .determiner
        case .preposition?: return .preposition
        case .conjunction?: return .conjunction
        case .particle?: return .particle
        case .number?: return .number
        default: return .other
        }
    }

    static func isEligible(_ text: String) -> Bool {
        let count = text.split(whereSeparator: \.isWhitespace).count
        return count >= minimumWords && count <= maxWords
    }

    /// Grounded in the verb forms rather than in what the sentence means.
    /// The first prompt asked the model to "name the structure", and the
    /// user saw simple-present sentences explained as past or continuous;
    /// a v13 test on ten simple sentences found Apple's on-device model
    /// wrong on most of them either way, while the configured provider got
    /// all ten right with this prompt — so explanations go there
    /// (`GrammarLensView.explain`).
    static func systemPrompt(target: Language, native: Language, level: CEFRLevel) -> String {
        """
        You explain \(target.rawValue) grammar to a CEFR \(level.rawValue) learner, \
        in \(native.rawValue). Work only from the exact words of the sentence.
        1. Quote the main verb phrase exactly as written, in quotes.
        2. Name its tense from the verb's FORM — its ending and its helper verbs — \
        never from the time or meaning the sentence talks about. Give the usual \
        \(native.rawValue) name with the \(target.rawValue) name in brackets.
        3. Say in one sentence which part of the form shows it, and why the tense \
        fits here.
        4. Only if the sentence really has one, name another structure worth \
        knowing (a conditional, a passive, a relative clause) in one sentence.
        At most four short sentences. No preamble, no list markers. If you are \
        not sure, say so instead of guessing.
        """
    }

    /// The sentence and the verb words the system tagger found in it, which
    /// anchor step 1 of the prompt.
    static func userPrompt(sentence: String, tokens: [Token]) -> String {
        let verbs = tokens.filter { $0.kind == .verb }.map(\.text)
        return "Sentence: \(sentence)\nVerb words the tagger found: "
            + (verbs.isEmpty ? "none" : verbs.joined(separator: ", "))
    }
}
