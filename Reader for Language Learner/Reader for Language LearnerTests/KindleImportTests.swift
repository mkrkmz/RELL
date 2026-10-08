//
//  KindleImportTests.swift
//  Reader for Language LearnerTests
//
//  v15 Sprint 4 — Kindle's vocabulary as a way in: reading vocab.db
//  (a fixture built here with Kindle's schema) without touching it, what's
//  new against the saved words, and what an import saves.
//

import SQLite3
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class KindleImportTests: XCTestCase {

    // MARK: Reading

    func testReadsWordsWithTheirLatestSentenceAndBook() async throws {
        let words = try KindleVocabulary.read(try fixture())
        XCTAssertEqual(words.count, 5)
        let tesserae = try XCTUnwrap(words.first { $0.word == "tesserae" })
        XCTAssertEqual(tesserae.sentence, "Prim is not to take any tesserae.", "the newest lookup")
        XCTAssertEqual(tesserae.bookTitle, "The Hunger Games")
        XCTAssertEqual(tesserae.lookedUpAt, Date(timeIntervalSince1970: 1_681_834_200))
        XCTAssertEqual(tesserae.language, .english)
        XCTAssertEqual(words.first { $0.word == "Exactly" }?.term, "exactly", "a sentence-start capital goes")
        XCTAssertEqual(words.first { $0.word == "Levantine" }?.term, "Levantine", "a proper adjective keeps it")
    }

    func testTheKindleFileIsNeverWritten() async throws {
        let database = try fixture()
        let before = try Data(contentsOf: database)
        let modified = try database.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        _ = try KindleVocabulary.read(database)
        XCTAssertEqual(try Data(contentsOf: database), before)
        XCTAssertEqual(try database.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
        let folder = try FileManager.default.contentsOfDirectory(atPath: database.deletingLastPathComponent().path)
        XCTAssertEqual(folder, ["vocab.db"], "no journal or lock file beside it")
    }

    func testFindsAConnectedKindle() async throws {
        let volumes = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vocabulary = volumes.appendingPathComponent("Kindle/system/vocabulary")
        try FileManager.default.createDirectory(at: vocabulary, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: volumes.appendingPathComponent("Macintosh HD"), withIntermediateDirectories: true)
        XCTAssertNil(KindleVocabulary.connectedDatabase(volumes: volumes))
        FileManager.default.createFile(atPath: vocabulary.appendingPathComponent("vocab.db").path, contents: Data())
        XCTAssertEqual(KindleVocabulary.connectedDatabase(volumes: volumes)?.lastPathComponent, "vocab.db")
    }

    func testAFileThatIsNotKindlesSaysSo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).db")
        try Data("not a database".utf8).write(to: url)
        XCTAssertThrowsError(try KindleVocabulary.read(url))
    }

    // MARK: Plan and import

    func testThePlanLeavesOutWhatsSavedAndOtherLanguages() async throws {
        let words = try KindleVocabulary.read(try fixture())
        let existing = [SavedWord(term: "Exactly"), SavedWord(term: "tessera")]   // by term, and by stem
        let plan = KindleVocabulary.Plan(words: words, existing: existing, target: .english)
        XCTAssertEqual(Set(plan.candidates.map(\.word)), ["loaves", "Levantine"])
        XCTAssertEqual(plan.alreadySaved, 2)
        XCTAssertEqual(plan.otherLanguage, 1)
        XCTAssertEqual(Set(plan.books.map(\.title)), ["The Hunger Games", "BBC News"])

        let all = Set(plan.books.map(\.id))
        XCTAssertEqual(plan.savedWords(books: all, includeMastered: false).map(\.term), ["loaves"],
                       "Kindle's mastered words wait for the checkbox")
        let saved = plan.savedWords(books: all, includeMastered: true)
        XCTAssertEqual(saved.count, 2)
        let loaves = try XCTUnwrap(saved.first { $0.term == "loaves" })
        XCTAssertEqual(loaves.sentence, "His are as solid and warm as those loaves of bread.")
        XCTAssertEqual(loaves.pdfFilename, "The Hunger Games")
        XCTAssertEqual(loaves.tags, [KindleVocabulary.deckName])
        XCTAssertEqual(loaves.language, Language.english.rawValue)
        XCTAssertEqual(loaves.savedAt, Date(timeIntervalSince1970: 1_681_833_951))
    }

    func testImportSavesOnceWithoutAnnouncingEachWord() async throws {
        let store = SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
        store.add(SavedWord(term: "lawn"))
        var announced = 0
        let observer = NotificationCenter.default.addObserver(forName: .savedWordAdded, object: nil, queue: nil) { _ in announced += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let ids = store.addImported([SavedWord(term: "loaves"), SavedWord(term: "Lawn"), SavedWord(term: "tessera")])
        XCTAssertEqual(ids.count, 2, "lawn is already saved")
        XCTAssertEqual(store.words.count, 3)
        XCTAssertEqual(announced, 0, "one bulk fill instead of a fill and an estimate per word")
    }

    // MARK: Fixture

    /// A vocab.db with Kindle's schema: two lookups of "tesserae" (the newer
    /// one wins), a Kindle-mastered word, and a Turkish book's word.
    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("vocab.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
            PRAGMA journal_mode=DELETE;
            CREATE TABLE WORDS (id TEXT PRIMARY KEY NOT NULL, word TEXT, stem TEXT, lang TEXT, category INTEGER DEFAULT 0, timestamp INTEGER DEFAULT 0, profileid TEXT);
            CREATE TABLE LOOKUPS (id TEXT PRIMARY KEY NOT NULL, word_key TEXT, book_key TEXT, dict_key TEXT, pos TEXT, usage TEXT, timestamp INTEGER DEFAULT 0);
            CREATE TABLE BOOK_INFO (id TEXT PRIMARY KEY NOT NULL, asin TEXT, guid TEXT, lang TEXT, title TEXT, authors TEXT);
            INSERT INTO BOOK_INFO VALUES ('hg', '', '', 'en', 'The Hunger Games', 'Suzanne Collins');
            INSERT INTO BOOK_INFO VALUES ('bbc', '', '', 'en', 'BBC News', 'calibre');
            INSERT INTO BOOK_INFO VALUES ('dg', '', '', 'tr', 'Dorian Gray''in Portresi', 'Oscar Wilde');
            INSERT INTO WORDS VALUES ('en:Exactly', 'Exactly', 'exactly', 'en', 0, 1681833992524, '');
            INSERT INTO WORDS VALUES ('en:loaves', 'loaves', 'loaves', 'en', 0, 1681833951623, '');
            INSERT INTO WORDS VALUES ('en:tesserae', 'tesserae', 'tessera', 'en', 0, 1681834148234, '');
            INSERT INTO WORDS VALUES ('en:Levantine', 'Levantine', 'Levantine', 'en', 100, 1681841180973, '');
            INSERT INTO WORDS VALUES ('tr:portre', 'portre', 'portre', 'tr', 0, 1681841180000, '');
            INSERT INTO LOOKUPS VALUES ('1', 'en:Exactly', 'hg', '', '', 'Exactly how am I supposed to work in a thank-you in there? ', 1681833992541);
            INSERT INTO LOOKUPS VALUES ('2', 'en:loaves', 'hg', '', '', 'His are as solid and warm as those loaves of bread. ', 1681833951000);
            INSERT INTO LOOKUPS VALUES ('3', 'en:tesserae', 'hg', '', '', 'An older sentence with tesserae.', 1681834100000);
            INSERT INTO LOOKUPS VALUES ('4', 'en:tesserae', 'hg', '', '', 'Prim is not to take any tesserae. ', 1681834200000);
            INSERT INTO LOOKUPS VALUES ('5', 'en:Levantine', 'bbc', '', '', 'A Levantine dessert.', 1681841181000);
            INSERT INTO LOOKUPS VALUES ('6', 'tr:portre', 'dg', '', '', 'Bir portre.', 1681841180500);
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
        return url
    }
}
