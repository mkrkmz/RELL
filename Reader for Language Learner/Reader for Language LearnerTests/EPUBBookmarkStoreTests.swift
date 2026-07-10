//
//  EPUBBookmarkStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EPUBBookmarkStoreTests: XCTestCase {
    // CI-only gotcha: @Observable objects created in a test body must outlive
    // the test (libmalloc double-free in the runner's post-scope checker).
    private static var retained: [EPUBBookmarkStore] = []

    private func makeStore() -> EPUBBookmarkStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = EPUBBookmarkStore(fileURL: fileURL)
        Self.retained.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }

    func testToggleAddsThenRemovesNearSamePosition() {
        let store = makeStore()

        let added = store.toggle(filename: "book", chapterIndex: 3, fraction: 0.42, snippet: "It was the best of times")
        XCTAssertTrue(added)
        XCTAssertEqual(store.count(for: "book"), 1)
        XCTAssertTrue(store.isBookmarked(filename: "book", chapterIndex: 3, near: 0.42))

        // Slightly different fraction within the tolerance still counts as
        // the same place — a second press removes rather than duplicating.
        let addedAgain = store.toggle(filename: "book", chapterIndex: 3, fraction: 0.43, snippet: "")
        XCTAssertFalse(addedAgain)
        XCTAssertEqual(store.count(for: "book"), 0)
    }

    func testPositionsBeyondToleranceAreDistinctBookmarks() {
        let store = makeStore()
        store.toggle(filename: "book", chapterIndex: 3, fraction: 0.10, snippet: "")
        store.toggle(filename: "book", chapterIndex: 3, fraction: 0.50, snippet: "")

        XCTAssertEqual(store.count(for: "book"), 2)
    }

    func testSameFractionDifferentChapterIsDistinct() {
        let store = makeStore()
        store.toggle(filename: "book", chapterIndex: 1, fraction: 0.5, snippet: "")
        store.toggle(filename: "book", chapterIndex: 2, fraction: 0.5, snippet: "")

        XCTAssertEqual(store.count(for: "book"), 2)
    }

    func testBookmarksAreScopedPerDocumentAndSortedByPosition() {
        let store = makeStore()
        store.add(EPUBBookmark(epubFilename: "book", chapterIndex: 5, scrollFraction: 0.2, snippet: ""))
        store.add(EPUBBookmark(epubFilename: "book", chapterIndex: 2, scrollFraction: 0.8, snippet: ""))
        store.add(EPUBBookmark(epubFilename: "book", chapterIndex: 2, scrollFraction: 0.1, snippet: ""))
        store.add(EPUBBookmark(epubFilename: "other", chapterIndex: 1, scrollFraction: 0, snippet: ""))

        let entries = store.bookmarks(for: "book")
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.chapterIndex), [2, 2, 5])
        XCTAssertLessThan(entries[0].scrollFraction, entries[1].scrollFraction)
        XCTAssertEqual(store.count(for: "other"), 1)
        XCTAssertEqual(store.count(for: nil), 0)
    }

    func testUpdateNoteTrimsAndPersists() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }

        let store = EPUBBookmarkStore(fileURL: fileURL)
        Self.retained.append(store)
        let bookmark = EPUBBookmark(epubFilename: "book", chapterIndex: 0, scrollFraction: 0, snippet: "s")
        store.add(bookmark)
        store.updateNote(id: bookmark.id, note: "  remember this  ")

        let reloaded = EPUBBookmarkStore(fileURL: fileURL)
        Self.retained.append(reloaded)
        XCTAssertEqual(reloaded.bookmarks(for: "book").first?.note, "remember this")
        XCTAssertEqual(reloaded.bookmarks(for: "book").first?.snippet, "s")
    }
}
