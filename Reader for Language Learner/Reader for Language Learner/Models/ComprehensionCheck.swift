//
//  ComprehensionCheck.swift
//  Reader for Language Learner
//
//  "What did you understand?" (Roadmap v19 Sprint 3): three short questions
//  on the part of a chapter (EPUB) or the pages (PDF) the reader has read —
//  the main idea, a detail, a why — answered in the language being learned.
//  Each answer gets a verdict on its content and, separately, a correction
//  of its language, with the sentence of the book it rests on. A quote the
//  book doesn't contain is never shown. Practice only.
//

import Foundation
import PDFKit

nonisolated enum ComprehensionCheck {

    enum Kind: String, CaseIterable, Equatable, Sendable {
        case mainIdea = "MAIN"
        case detail = "DETAIL"
        case why = "WHY"

        var localizedTitle: String {
            switch self {
            case .mainIdea: return String(localized: "Main idea")
            case .detail:   return String(localized: "Detail")
            case .why:      return String(localized: "Why")
            }
        }
    }

    struct Question: Equatable, Identifiable, Sendable {
        let id: Int
        let kind: Kind
        let text: String
    }

    enum Verdict: Equatable, Sendable {
        case understood, partly, missed, skipped
    }

    struct Grade: Equatable, Sendable {
        let verdict: Verdict
        /// The answer with its language fixed; nil when nothing changed or
        /// the answer was in the reader's own language.
        let corrected: String?
        let note: String
        /// The book's sentence the answer rests on — only when the passage
        /// really contains it.
        let quote: String?
    }

    /// A chapter shorter than this isn't offered a check at its end.
    static let minimumWords = 400
    /// The furthest a PDF check reaches back.
    static let maxPDFPages = 12
    /// The same budget as a recap: the on-device model's window is small.
    static let passageLimit = ReadingRecap.passageLimit
    static let questionTokens = 700
    static let gradeTokens = 1_400

    // Parser-bound labels — English and fixed, whatever the languages.
    static let answerLabel = "ANSWER"
    static let verdictLabel = "VERDICT:"
    static let correctedLabel = "CORRECTED:"
    static let noteLabel = "NOTE:"
    static let quoteLabel = "QUOTE:"

    static func isLongEnough(_ chapterText: String) -> Bool {
        var words = 0
        chapterText.enumerateSubstrings(in: chapterText.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, stop in
            words += 1
            if words >= minimumWords { stop = true }
        }
        return words >= minimumWords
    }

    /// The pages a PDF check covers: from where this session started to the
    /// page on screen, at most `maxPDFPages`, never past the page on screen.
    /// 0-based.
    static func pdfRange(sessionStart: Int?, current: Int) -> ClosedRange<Int> {
        let start = min(sessionStart ?? current, current)
        return max(start, current - maxPDFPages + 1)...current
    }

    // MARK: Questions

    static func questionsSystemPrompt(target: Language, level: CEFRLevel) -> String {
        """
        You write reading-comprehension questions for a CEFR \(level.rawValue) learner of \
        \(target.rawValue). Ask exactly three short questions in \(target.rawValue) about the \
        PASSAGE, at the learner's level, answerable from the passage alone and in one or two \
        sentences: one on the main idea, one on a detail, one asking why something happened \
        or why someone acted as they did. Don't ask about anything the passage doesn't say. \
        Reply with exactly three lines and nothing else:
        Q1 [MAIN]: <question>
        Q2 [DETAIL]: <question>
        Q3 [WHY]: <question>
        """
    }

    static func questionsUserPrompt(passage: String) -> String {
        "PASSAGE:\n\(passage)"
    }

    /// The questions in the reply, in order; empty unless at least two read.
    static func parseQuestions(_ raw: String) -> [Question] {
        var questions: [Question] = []
        for line in raw.replacingOccurrences(of: "**", with: "").components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.firstMatch(of: /^Q\s*([1-3])\s*[\[(]?\s*([A-Za-z]+)?\s*[\])]?\s*[:.)\-–]\s*(.+)$/) else { continue }
            let text = String(match.3).trimmingCharacters(in: .whitespaces)
            guard text.count > 3 else { continue }
            let kind = match.2.flatMap { Kind(rawValue: String($0).uppercased()) }
                ?? Kind.allCases[min(questions.count, Kind.allCases.count - 1)]
            questions.append(Question(id: questions.count + 1, kind: kind, text: text))
        }
        return questions.count >= 2 ? Array(questions.prefix(3)) : []
    }

    // MARK: Grading

    static func gradeSystemPrompt(target: Language, native: Language, level: CEFRLevel, answersInNative: Bool) -> String {
        let language = answersInNative
            ? "The learner answered in \(native.rawValue); judge only the content and write \(correctedLabel) NONE."
            : "Also correct the language of each answer: fix grammar, spelling and word choice, keep the learner's words where they work; write \(correctedLabel) NONE when nothing needs fixing."
        return """
        You check a CEFR \(level.rawValue) learner's answers to questions about a PASSAGE in \
        \(target.rawValue). Judge each answer only by what the passage says: UNDERSTOOD when \
        it gets the point, PARTLY when it is right but misses part of it, MISSED when it is \
        wrong. \(language) For each answer write a NOTE of one or two short sentences in \
        \(native.rawValue): what was right or what was missed. Then copy, word for word, the \
        one sentence of the passage the answer rests on as the QUOTE. Reply in exactly this \
        format for every answer:
        \(answerLabel) <number>
        \(verdictLabel) UNDERSTOOD, PARTLY or MISSED
        \(correctedLabel) <the corrected answer, or NONE>
        \(noteLabel) <your note>
        \(quoteLabel) <the sentence from the passage>
        """
    }

    static func gradeUserPrompt(passage: String, questions: [Question], answers: [Int: String]) -> String {
        var text = "PASSAGE:\n\(passage)\n"
        for question in questions {
            guard let answer = answers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !answer.isEmpty else { continue }
            text += "\nQUESTION \(question.id): \(question.text)\nANSWER \(question.id): \(answer)\n"
        }
        return text
    }

    /// The grades in the reply, by question id. Unanswered questions are
    /// skipped here, not sent; a quote the passage doesn't contain is dropped.
    static func parseGrades(_ raw: String, answers: [Int: String], passage: String) -> [Int: Grade] {
        var blocks: [Int: String] = [:]
        var current: Int?
        for line in raw.replacingOccurrences(of: "**", with: "").components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.firstMatch(of: /^#*\s*ANSWER\s*([1-3])\s*:?\s*$/.ignoresCase()) {
                current = Int(match.1)
                continue
            }
            if let current { blocks[current, default: ""] += line + "\n" }
        }

        var grades: [Int: Grade] = [:]
        for (id, answer) in answers {
            let written = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !written.isEmpty else {
                grades[id] = Grade(verdict: .skipped, corrected: nil, note: "", quote: nil)
                continue
            }
            guard let block = blocks[id] else { continue }
            let parts = LabelledReply.sections(block, labels: [verdictLabel, correctedLabel, noteLabel, quoteLabel])
            let said = (parts[verdictLabel] ?? "").uppercased()
            let verdict: Verdict = said.contains("PART") ? .partly
                : said.contains("MISS") ? .missed
                : said.contains("UNDERST") ? .understood : .partly
            let corrected = parts[correctedLabel].map(unquoted).flatMap { text -> String? in
                guard !text.isEmpty, text.uppercased() != "NONE" else { return nil }
                return WordDiff.diff(written, text).contains { $0.kind != .same } ? text : nil
            }
            grades[id] = Grade(verdict: verdict, corrected: corrected, note: parts[noteLabel] ?? "",
                               quote: parts[quoteLabel].flatMap { verifiedQuote($0, in: passage) })
        }
        return grades
    }

    /// `quote` when the passage contains it — ignoring case, spacing and
    /// the style of quotation marks — at four words or more; otherwise nil,
    /// so a sentence the model made up never shows as the book's.
    static func verifiedQuote(_ quote: String, in passage: String) -> String? {
        let cleaned = unquoted(quote).trimmingCharacters(in: CharacterSet(charactersIn: ".…").union(.whitespaces))
        guard cleaned.split(whereSeparator: \.isWhitespace).count >= 4 else { return nil }
        return normalized(passage).contains(normalized(cleaned)) ? unquoted(quote) : nil
    }

    /// How many answers got the point, of those given.
    static func score(_ grades: [Int: Grade]) -> (understood: Int, total: Int) {
        (grades.values.filter { $0.verdict == .understood }.count, grades.count)
    }

    // MARK: Passages

    /// The part of an EPUB chapter read so far, within the budget.
    static func chapterPassage(_ chapterText: String, readUpTo fraction: Double) -> String {
        ReadingRecap.passage(current: chapterText, upTo: fraction, limit: passageLimit)
    }

    /// The text of PDF pages `range` (0-based), within the budget.
    static func pdfPassage(url: URL, pages range: ClosedRange<Int>) -> String {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return "" }
        let last = min(range.upperBound, document.pageCount - 1)
        let first = min(max(0, range.lowerBound), last)
        let text = (first...last).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        return ReadingRecap.passage(current: text, limit: passageLimit)
    }

    // MARK: Helpers

    private static func normalized(_ text: String) -> String {
        let quotes: [Character: Character] = ["“": "\"", "”": "\"", "„": "\"", "«": "\"", "»": "\"", "‘": "'", "’": "'"]
        let mapped = String(text.map { quotes[$0] ?? $0 }).lowercased()
        return mapped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func unquoted(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»„'‘’"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The last check of each chapter (EPUB) or book (PDF), and the chapters
/// whose end already offered one — small, in UserDefaults, newest 200 kept.
@MainActor
enum ComprehensionHistory {

    struct Entry: Codable, Equatable {
        let understood: Int
        let total: Int
        let date: Date
        /// True for the "offered at the chapter's end" marker without a check.
        var offeredOnly = false
    }

    static let capacity = 200

    static func key(book: String, chapter: Int?) -> String {
        chapter.map { "\(book)#c\($0)" } ?? "\(book)#pdf"
    }

    static func entry(for key: String, defaults: UserDefaults = .standard) -> Entry? {
        load(defaults)[key]
    }

    static func lastCheck(for key: String, defaults: UserDefaults = .standard) -> Entry? {
        entry(for: key, defaults: defaults).flatMap { $0.offeredOnly ? nil : $0 }
    }

    static func record(_ understood: Int, of total: Int, for key: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        store(Entry(understood: understood, total: total, date: now), for: key, defaults: defaults)
    }

    /// The chapter's end offered a check; it won't ask again.
    static func markOffered(_ key: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        guard entry(for: key, defaults: defaults) == nil else { return }
        store(Entry(understood: 0, total: 0, date: now, offeredOnly: true), for: key, defaults: defaults)
    }

    private static func store(_ entry: Entry, for key: String, defaults: UserDefaults) {
        var all = load(defaults)
        all[key] = entry
        if all.count > capacity {
            for old in all.sorted(by: { $0.value.date < $1.value.date }).prefix(all.count - capacity) {
                all[old.key] = nil
            }
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: StorageKey.comprehensionHistory)
        }
    }

    private static func load(_ defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: StorageKey.comprehensionHistory) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }
}
