//
//  BookWordsTests.swift
//  Reader for Language LearnerTests
//
//  v16 Sprint 1 — a book's sidebar: its saved words from this file, other
//  copies and Kindle; the ones met again in it; the per-book switch.
//

import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class BookWordsTests: XCTestCase {

    private let path = "/Books/Matthew Walker PhD - Why We Sleep_ Unlocking the Power of Sleep and Dreams-Scribner (2017).pdf"
    private var document: BookIdentity.Document {
        BookIdentity.Document(path: path, names: ["Matthew Walker PhD - Why We Sleep_ Unlocking the Power of Sleep and Dreams-Scribner (2017)"])
    }

    private func words() -> [SavedWord] {
        [
            SavedWord(term: "drowsy", pdfFilename: "renamed", documentPath: path),
            SavedWord(term: "brainwave", pdfFilename: "Matthew Walker PhD - Why We Sleep_ Unlocking the Power of Sleep and Dreams-Scribner (2017)"),
            SavedWord(term: "slumber", pdfFilename: "Why We Sleep", tags: [KindleVocabulary.deckName]),
            SavedWord(term: "nap", pdfFilename: "Why We Sleep_ Unlocking the Power of Sleep and Dreams -- Walker, Matthew -- 2215bb -- Anna’s Archive"),
            SavedWord(term: "peculiar", pdfFilename: "Harry Potter and the Chamber of Secrets"),
            SavedWord(term: "manure", pdfFilename: "Harry Potter and the Chamber of Secrets"),
        ]
    }

    private func met(_ word: SavedWord, title: String, path: String) -> WordEncounter {
        WordEncounter(wordID: word.id, documentPath: path, documentTitle: title, location: 0, isEPUB: false,
                      sentence: "", occurrences: 1, date: Date())
    }

    func testTheBookGathersItsCopiesAndKindle() async {
        let all = words()
        let book = BookWords(document: document, words: all, encounters: [
            met(all[4], title: "Why We Sleep: Unlocking the Power of Sleep and Dreams", path: "/Books/other.epub"),
            met(all[1], title: "x", path: path),   // saved here: not "met again"
        ], matchingTitles: true)

        XCTAssertEqual(Set(book.saved.map(\.term)), ["drowsy", "brainwave", "slumber", "nap"])
        XCTAssertEqual(book.met.map(\.term), ["peculiar"], "saved elsewhere, met in another copy of this book")
        let kinds = Dictionary(uniqueKeysWithValues: book.sources.map { ($0.kind == .thisFile ? "this" : $0.name, $0.kind) })
        XCTAssertEqual(kinds["this"], .thisFile)
        XCTAssertEqual(kinds["Why We Sleep"], .kindle)
        XCTAssertEqual(book.sources.first { $0.kind == .thisFile }?.count, 2, "by path and by this file's name")
    }

    func testTheSwitchKeepsToThisFile() async throws {
        let all = words()
        let book = BookWords(document: document, words: all, encounters: [
            met(all[4], title: "Why We Sleep", path: "/Books/other.epub"),
            met(all[5], title: "anything", path: path),
        ], matchingTitles: false)
        XCTAssertEqual(Set(book.saved.map(\.term)), ["drowsy", "brainwave"])
        XCTAssertEqual(book.met.map(\.term), ["manure"], "met in this very file still counts")

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BookWordsTests-\(UUID().uuidString)"))
        XCTAssertTrue(BookWords.matchesTitles(forDocumentAt: path, defaults: defaults), "on by default")
        BookWords.setMatchesTitles(false, forDocumentAt: path, defaults: defaults)
        XCTAssertFalse(BookWords.matchesTitles(forDocumentAt: path, defaults: defaults))
        XCTAssertTrue(BookWords.matchesTitles(forDocumentAt: "/Books/other.epub", defaults: defaults), "per book")
        BookWords.setMatchesTitles(true, forDocumentAt: path, defaults: defaults)
        XCTAssertTrue(BookWords.matchesTitles(forDocumentAt: path, defaults: defaults))
    }

    func testTitlesReadLikeTitles() async {
        XCTAssertEqual(BookIdentity.displayTitle("Why We Sleep_ Unlocking the Power of Sleep and Dreams -- Walker, Matthew -- 2215bb -- Anna’s Archive"),
                       "Why We Sleep: Unlocking the Power of Sleep and Dreams")
        XCTAssertEqual(BookIdentity.displayTitle("Harry Potter and the Chamber of Secrets (1)"), "Harry Potter and the Chamber of Secrets")
    }

    /// The book's list in the narrowest sidebar: header, filters and two
    /// groups stay inside the column.
    func testTheBookListFitsTheNarrowestSidebar() async throws {
        let store = SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
        for word in words() { store.add(word) }
        let list = SavedWordsListView(
            store: store, currentDocumentName: nil,
            book: .init(document: document, title: "Why We Sleep: Unlocking the Power of Sleep and Dreams"),
            onStudyBook: {}
        )
        .environment(CEFREstimator(savedWordsStore: store))
        .environment(WordEncounterStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("e.json")))
        let height = try await LayoutGuard.settledHeight(of: list, width: 200, height: 420)
        XCTAssertLessThanOrEqual(height, 420 + 1, "the book's list forced the window to \(height) pt")
    }
}
