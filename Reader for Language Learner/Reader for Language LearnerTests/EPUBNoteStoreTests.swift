//
//  EPUBNoteStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EPUBNoteStoreTests: XCTestCase {
    // CI-only gotcha: @Observable objects created in a test body must outlive
    // the test (libmalloc double-free in the runner's post-scope checker).
    private static var retained: [EPUBNoteStore] = []

    private func makeStore(fileURL: URL? = nil) -> EPUBNoteStore {
        let url = fileURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = EPUBNoteStore(fileURL: url)
        Self.retained.append(store)
        if fileURL == nil {
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        }
        return store
    }

    func testAddRemoveAndPerDocumentCounts() {
        let store = makeStore()
        let note = EPUBNote(epubFilename: "book", chapterIndex: 1, scrollFraction: 0.3, text: "thought")
        store.add(note)
        store.add(EPUBNote(epubFilename: "other", chapterIndex: 0, scrollFraction: 0, text: "x"))

        XCTAssertEqual(store.count(for: "book"), 1)
        XCTAssertEqual(store.count(for: "other"), 1)
        XCTAssertEqual(store.count(for: nil), 0)

        store.remove(id: note.id)
        XCTAssertEqual(store.count(for: "book"), 0)
    }

    func testNotesSortedByChapterThenNewestFirst() {
        let store = makeStore()
        let older = Date(timeIntervalSinceNow: -100)
        store.add(EPUBNote(epubFilename: "book", chapterIndex: 4, scrollFraction: 0, text: "later chapter"))
        store.add(EPUBNote(epubFilename: "book", chapterIndex: 1, scrollFraction: 0, text: "old", createdAt: older))
        store.add(EPUBNote(epubFilename: "book", chapterIndex: 1, scrollFraction: 0, text: "new"))

        let entries = store.notes(for: "book")
        XCTAssertEqual(entries.map(\.text), ["new", "old", "later chapter"])
    }

    func testUpdateTextTrimsAndPersistsRoundTrip() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }

        let store = makeStore(fileURL: fileURL)
        let note = EPUBNote(epubFilename: "book", chapterIndex: 2, scrollFraction: 0.7, text: "draft")
        store.add(note)
        store.updateText(id: note.id, text: "  final thought  ")

        let reloaded = makeStore(fileURL: fileURL)
        let entry = reloaded.notes(for: "book").first
        XCTAssertEqual(entry?.text, "final thought")
        XCTAssertEqual(entry?.chapterIndex, 2)
        XCTAssertEqual(entry?.scrollFraction ?? 0, 0.7, accuracy: 0.0001)
    }
}
