//
//  KindleVocabulary.swift
//  Reader for Language Learner
//
//  Kindle's Vocabulary Builder as a way in for words (Roadmap v15 Sprint 4).
//  Every word looked up on a Kindle is kept in `system/vocabulary/vocab.db`
//  on the device, with the sentence it was met in and the book:
//
//      WORDS     (id "en:loaves", word, stem, lang, category, timestamp)
//      LOOKUPS   (word_key → WORDS.id, book_key → BOOK_INFO.id, usage, timestamp)
//      BOOK_INFO (id, lang, title, authors)
//
//  The device is never written to: the file is copied to a temporary
//  folder first and the copy is opened read-only and immutable, so SQLite
//  doesn't even create a journal or lock file.
//

import Foundation
import NaturalLanguage
import SQLite3

/// One word from a Kindle, with its latest lookup.
struct KindleWord: Equatable, Identifiable {
    let id: String
    let word: String
    let stem: String
    /// ISO code as Kindle stores it ("en", "tr").
    let languageCode: String
    /// Kindle's "mastered" flag (category 100).
    let isMastered: Bool
    let sentence: String
    let bookID: String?
    let bookTitle: String?
    let lookedUpAt: Date

    /// The term to save: as read, except a capital that only starts the
    /// sentence ("Exactly" → "exactly", "It" → "it"; "Levantine" and "I"
    /// stay).
    var term: String {
        guard let first = word.first, first.isUppercase, word != "I", !word.hasPrefix("I'") else { return word }
        let stemIsLower = stem.first?.isLowercase == true
        let opensSentence = sentence
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“‘(«— ").union(.whitespaces))
            .hasPrefix(word)
        guard stemIsLower || opensSentence else { return word }
        return first.lowercased() + word.dropFirst()
    }

    var language: Language? {
        Language.allCases.first { $0.shortCode.lowercased() == languageCode.lowercased() }
    }
}

struct KindleBook: Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let wordCount: Int
}

enum KindleVocabulary {

    enum ReadError: LocalizedError {
        case notAVocabularyFile
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notAVocabularyFile:
                return String(localized: "This isn't a Kindle vocabulary file (vocab.db).")
            case .unreadable(let reason):
                return String(localized: "The Kindle vocabulary file couldn't be read: \(reason)")
            }
        }
    }

    /// `vocab.db` on a connected Kindle, if one is mounted.
    static func connectedDatabase(volumes: URL = URL(fileURLWithPath: "/Volumes")) -> URL? {
        let mounted = (try? FileManager.default.contentsOfDirectory(at: volumes, includingPropertiesForKeys: nil)) ?? []
        return mounted
            .map { $0.appendingPathComponent("system/vocabulary/vocab.db") }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// Every word in `database`, newest lookup first. Reads a copy.
    static func read(_ database: URL) throws -> [KindleWord] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rell-kindle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("vocab.db")
        try FileManager.default.copyItem(at: database, to: copy)

        var handle: OpaquePointer?
        let uri = "file:\(copy.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? copy.path)?immutable=1"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw ReadError.unreadable(String(localized: "it didn't open"))
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT w.id, w.word, w.stem, w.lang, w.category, l.usage, l.book_key, b.title,
                   COALESCE(l.timestamp, w.timestamp)
            FROM WORDS w
            LEFT JOIN LOOKUPS l ON l.word_key = w.id
                AND l.timestamp = (SELECT MAX(timestamp) FROM LOOKUPS WHERE word_key = w.id)
            LEFT JOIN BOOK_INFO b ON b.id = l.book_key
            ORDER BY COALESCE(l.timestamp, w.timestamp) DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw ReadError.notAVocabularyFile
        }
        defer { sqlite3_finalize(statement) }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var words: [KindleWord] = []
        var seen = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(0), seen.insert(id).inserted,
                  let word = text(1)?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else { continue }
            words.append(KindleWord(
                id: id,
                word: word,
                stem: text(2) ?? word,
                languageCode: text(3) ?? "",
                isMastered: sqlite3_column_int(statement, 4) == 100,
                sentence: (text(5) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                bookID: text(6),
                bookTitle: text(7)?.trimmingCharacters(in: .whitespacesAndNewlines),
                lookedUpAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 8)) / 1000)
            ))
        }
        return words
    }

    // MARK: Import plan

    /// What an import of `words` would add to `existing`.
    struct Plan: Equatable {
        /// New words in the language you study, by book.
        let candidates: [KindleWord]
        let books: [KindleBook]
        /// Already saved (same term or stem).
        let alreadySaved: Int
        /// In another language than the one you study.
        let otherLanguage: Int
        /// Words no one studies — "it", "an", "have" — looked up by a slip
        /// of the finger.
        let tooCommon: Int

        init(words: [KindleWord], existing: [SavedWord], target: Language) {
            let saved = Set(existing.map { $0.term.lowercased() })
            var alreadySaved = 0, otherLanguage = 0, tooCommon = 0
            var candidates: [KindleWord] = []
            var seenTerms = Set<String>()
            for word in words {
                guard word.language == target else { otherLanguage += 1; continue }
                if KindleVocabulary.isFunctionWord(word.term, language: target, sentence: word.sentence) { tooCommon += 1; continue }
                let term = word.term.lowercased()
                if saved.contains(term) || saved.contains(word.stem.lowercased()) || !seenTerms.insert(term).inserted {
                    alreadySaved += 1
                    continue
                }
                candidates.append(word)
            }
            self.candidates = candidates
            self.alreadySaved = alreadySaved
            self.otherLanguage = otherLanguage
            self.tooCommon = tooCommon

            var counts: [String: (title: String, count: Int)] = [:]
            for word in candidates {
                let key = word.bookID ?? ""
                let title = word.bookTitle ?? String(localized: "Unknown book")
                counts[key] = (title, (counts[key]?.count ?? 0) + 1)
            }
            self.books = counts
                .map { KindleBook(id: $0.key, title: $0.value.title, wordCount: $0.value.count) }
                .sorted { ($0.wordCount, $1.title) > ($1.wordCount, $0.title) }
        }

        /// The words to save: from `books`, and Kindle-mastered ones only
        /// when asked.
        func savedWords(books: Set<String>, includeMastered: Bool, deck: String = KindleVocabulary.deckName) -> [SavedWord] {
            candidates
                .filter { books.contains($0.bookID ?? "") && (includeMastered || !$0.isMastered) }
                .map { word in
                    SavedWord(
                        term: word.term,
                        sentence: word.sentence,
                        pdfFilename: word.bookTitle,
                        tags: [deck],
                        savedAt: word.lookedUpAt,
                        language: word.language?.rawValue
                    )
                }
        }
    }

    /// Pronouns, articles, prepositions, conjunctions and particles, and
    /// the forms of be / have / do — by the language's own tagger.
    static func isFunctionWord(_ term: String, language: Language, sentence: String = "") -> Bool {
        let lowered = term.lowercased()
        if language == .english, auxiliaries.contains(lowered) { return true }
        // Short ones only: "albeit" and "whereas" are closed-class too, and
        // worth learning.
        guard !lowered.contains(" "), lowered.count <= 5 else { return false }
        // In its sentence when it's there: alone, the tagger calls
        // "thalamus" and "anthem" function words (v15 S4, the user's Kindle).
        let text = sentence.isEmpty ? lowered : sentence
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        if let nl = LemmaMatcher.nlLanguage(for: language) {
            tagger.setLanguage(nl, range: text.startIndex..<text.endIndex)
        }
        let whole = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
        guard let range = text.range(of: whole, options: [.regularExpression, .caseInsensitive])
            ?? text.range(of: term, options: [.caseInsensitive]) else { return false }
        let (tag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass)
        let closed: Set<NLTag> = [.pronoun, .determiner, .preposition, .conjunction, .particle, .classifier]
        return tag.map(closed.contains) ?? false
    }

    private static let auxiliaries: Set<String> = [
        "be", "am", "is", "are", "was", "were", "been", "being",
        "have", "has", "had", "having", "do", "does", "did", "i'm", "it's",
    ]

    /// The deck imported words go into, so they can be studied together.
    static let deckName = "Kindle"
}
