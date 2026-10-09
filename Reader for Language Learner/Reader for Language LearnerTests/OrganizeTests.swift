//
//  OrganizeTests.swift
//  Reader for Language LearnerTests
//
//  v16 Sprint 3 — a deck per book for Anki, the same word saved twice and
//  merged, the backup before a merge, the Kindle notice's count, and a
//  library card opening the notebook on its book.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class OrganizeTests: XCTestCase {

    // MARK: Anki

    func testEachBookCanBeItsOwnAnkiDeck() async {
        var withDeck = AnkiNoteDraft(front: "slumber", back: "uyuklama", tags: "rell", source: "Why We Sleep")
        withDeck.deck = AnkiExporter.bookDeck("Why We Sleep: Unlocking the Power")
        let document = AnkiExporter.tsvDocument(from: [withDeck])
        XCTAssertTrue(document.contains("#columns:Front\tBack\tTags\tSource\tDeck\n#deck column:5"))
        XCTAssertTrue(document.contains("\tRELL::Why We Sleep - Unlocking the Power\n"),
                      "a title's colon would make a deeper subdeck")
        XCTAssertEqual(AnkiExporter.bookDeck(nil), "RELL")

        let plain = AnkiExporter.tsvDocument(from: [AnkiNoteDraft(front: "a", back: "b", tags: "", source: "")])
        XCTAssertFalse(plain.contains("Deck"), "no deck column unless asked")
    }

    // MARK: Saved twice

    private let lemmas = ["gleaming": "gleam", "gleam": "gleam", "lolled": "loll", "loll": "loll"]

    func testTheSameWordUnderTwoFormsIsFound() async {
        var reviewed = SavedWord(term: "gleam", language: Language.english.rawValue); reviewed.reviewCount = 3
        let words = [
            SavedWord(term: "gleaming", language: Language.english.rawValue),
            reviewed,
            SavedWord(term: "Lolled", language: Language.english.rawValue),
            SavedWord(term: "loll", language: Language.german.rawValue),   // another language
            SavedWord(term: "lawn", language: Language.english.rawValue),
        ]
        let groups = WordMerge.duplicates(in: words) { term, _ in self.lemmas[term] }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].words.map(\.term), ["gleam", "gleaming"], "the reviewed one first, to keep")
    }

    func testMergingKeepsEverythingBothHad() async {
        let old = Date(timeIntervalSince1970: 1_700_000_000), recent = Date(timeIntervalSince1970: 1_790_000_000)
        var keep = SavedWord(term: "gleam", sentence: "A gleam of light.", tags: ["Okul"],
                             llmOutputs: [ModuleType.meaningTR.rawValue: "parıltı"], savedAt: recent)
        keep.reviewCount = 2; keep.stability = 3; keep.nextReviewAt = recent
        keep.reviewEvents = [ReviewEvent(date: recent, rating: .good)]
        var other = SavedWord(term: "gleaming", sentence: "The gleaming car.", tags: ["okul", "Kindle"],
                              llmOutputs: [ModuleType.meaningTR.rawValue: "parlayan", ModuleType.definitionEN.rawValue: "Shining."],
                              savedAt: old, fieldSources: ["definition": FillSource.onDevice.stored])
        other.reviewCount = 5; other.incorrectCount = 2; other.stability = 12; other.nextReviewAt = recent.addingTimeInterval(86_400 * 10)
        other.reviewEvents = [ReviewEvent(date: old, rating: .again)]

        let merged = WordMerge.merged(keep: keep, others: [other])
        XCTAssertEqual(merged.id, keep.id)
        XCTAssertEqual(merged.llmOutputs[ModuleType.meaningTR.rawValue], "parıltı", "the kept word's own stays")
        XCTAssertEqual(merged.llmOutputs[ModuleType.definitionEN.rawValue], "Shining.")
        XCTAssertEqual(merged.source(of: .definition), .onDevice)
        XCTAssertEqual(merged.tags, ["Okul", "Kindle"])
        XCTAssertEqual(merged.sentence, "A gleam of light.")
        XCTAssertTrue(merged.notes.contains("The gleaming car."), "the other sentence isn't lost")
        XCTAssertEqual(merged.reviewCount, 7)
        XCTAssertEqual(merged.incorrectCount, 2)
        XCTAssertEqual(merged.reviewEvents.map(\.rating), [.again, .good])
        XCTAssertEqual(merged.stability, 12, "the memory of the better-known one")
        XCTAssertEqual(merged.nextReviewAt, other.nextReviewAt)
        XCTAssertEqual(merged.savedAt, old)
    }

    func testTheStoreMergesAndTheEncountersFollow() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedWordsStore(fileURL: folder.appendingPathComponent("w.json"))
        let keep = SavedWord(term: "gleam"), other = SavedWord(term: "gleaming")
        store.add(keep); store.add(other)
        let encounters = WordEncounterStore(fileURL: folder.appendingPathComponent("e.json"))
        encounters.append([WordEncounter(wordID: other.id, documentPath: "/b.epub", documentTitle: "B", location: 0,
                                         isEPUB: true, sentence: "The gleaming car.", occurrences: 1, date: Date())])

        store.merge(keep: keep.id, others: [other.id])
        encounters.reassign(from: [other.id], to: keep.id)

        XCTAssertEqual(store.words.map(\.term), ["gleam"])
        XCTAssertEqual(encounters.encounters(for: keep.id).count, 1)
        XCTAssertTrue(encounters.encounters(for: other.id).isEmpty)
    }

    func testABackupComesBeforeAMergeAndOnlyFiveAreKept() async throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: data.appendingPathComponent("saved_words.json"))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OrganizeTests-\(UUID().uuidString)"))
        var last: URL?
        for minute in 0..<7 {
            last = PersistenceBackup.snapshotBeforeChange("merge", dataDirectory: data, defaults: defaults,
                                                          now: Date(timeIntervalSince1970: 1_790_000_000 + Double(minute) * 60))
        }
        let folder = try XCTUnwrap(last)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("saved_words.json").path))
        let kept = try FileManager.default.contentsOfDirectory(atPath: data.appendingPathComponent("Backups").path)
            .filter { $0.hasPrefix("before-") }
        XCTAssertEqual(kept.count, 5)
        XCTAssertTrue(kept.contains(folder.lastPathComponent), "the newest is kept")
    }

    // MARK: Kindle notice and library cards

    func testTheKindleNoticeCountsWhatAnImportWouldBring() async throws {
        let database = try KindleImportTests.fixture()
        XCTAssertEqual(KindleNoticeBanner.newWordCount(database: database, existing: [], target: .english), 3,
                       "Exactly, loaves, tesserae — not the Kindle-mastered word or the Turkish one")
        XCTAssertEqual(KindleNoticeBanner.newWordCount(database: database, existing: [SavedWord(term: "loaves")], target: .english), 2)
        XCTAssertEqual(KindleNoticeBanner.newWordCount(database: nil, existing: [], target: .english), 0)
    }

    func testALibraryCardFindsItsBookInTheNotebook() async {
        let words = [SavedWord(term: "a", pdfFilename: "Why We Sleep"),
                     SavedWord(term: "b", pdfFilename: "Why We Sleep_ Unlocking the Power of Sleep and Dreams -- Walker, Matthew -- 22 -- Anna’s Archive")]
        let books = WordNotebook.books(from: words)
        let pdf = "Matthew Walker PhD - Why We Sleep_ Unlocking the Power of Sleep and Dreams-Scribner (2017)"
        XCTAssertEqual(WordNotebook.book(named: pdf, in: books)?.count, 2, "a file with no words of its own finds its book by title")
        XCTAssertNil(WordNotebook.book(named: "Crime and Punishment", in: books))
    }
}
