//
//  EPUBHighlightStoreTests.swift
//  Reader for Language LearnerTests
//
//  Covers the store layer only — the JS text-quote anchor/render algorithm
//  (EPUBReaderView's highlightScript) needs a live WKWebView and isn't
//  exercised here, matching how EPUBSearchManagerTests stays Swift-side.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EPUBHighlightStoreTests: XCTestCase {
    private static var retainedStores: [EPUBHighlightStore] = []

    private func makeHighlight(
        book: String = "book",
        chapter: Int = 2,
        chapterPath: String = "OEBPS/text/ch3.xhtml",
        quote: String = "a lighthouse in the fog",
        color: HighlightColor = .yellow
    ) -> EPUBHighlight {
        EPUBHighlight(
            epubFilename: book,
            chapterIndex: chapter,
            chapterPath: chapterPath,
            quote: quote,
            prefix: "there stood ",
            suffix: " that winter",
            startOffset: 120,
            colorRaw: color.rawValue
        )
    }

    private func makeStore() -> EPUBHighlightStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub_highlights_\(UUID().uuidString).json")
        let store = EPUBHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }

    // MARK: - Queries

    func testHighlightsForFilenameFiltersAndOrdersByChapterThenNewest() {
        let store = makeStore()
        let older = makeHighlight(book: "book", chapter: 1, quote: "first")
        let newer = makeHighlight(book: "book", chapter: 1, quote: "second")
        let otherBook = makeHighlight(book: "other", chapter: 0, quote: "elsewhere")
        let laterChapter = makeHighlight(book: "book", chapter: 3, quote: "later")

        store.add(older)
        store.add(newer)
        store.add(otherBook)
        store.add(laterChapter)

        let result = store.highlights(for: "book")
        XCTAssertEqual(result.map(\.quote), ["second", "first", "later"],
                       "same chapter sorts newest-first; different chapters sort ascending")
    }

    func testHighlightsForFilenameAndChapterPathFiltersToOneChapter() {
        let store = makeStore()
        store.add(makeHighlight(chapterPath: "OEBPS/text/ch1.xhtml", quote: "one"))
        store.add(makeHighlight(chapterPath: "OEBPS/text/ch2.xhtml", quote: "two"))
        store.add(makeHighlight(chapterPath: "OEBPS/text/ch1.xhtml", quote: "three"))

        let result = store.highlights(for: "book", chapterPath: "OEBPS/text/ch1.xhtml")
        XCTAssertEqual(Set(result.map(\.quote)), ["one", "three"])
    }

    func testCountForFilename() {
        let store = makeStore()
        store.add(makeHighlight(book: "book", quote: "a"))
        store.add(makeHighlight(book: "book", quote: "b"))
        store.add(makeHighlight(book: "other", quote: "c"))

        XCTAssertEqual(store.count(for: "book"), 2)
        XCTAssertEqual(store.count(for: "missing"), 0)
        XCTAssertEqual(store.count(for: nil), 0)
    }

    // MARK: - Mutations

    func testUpdateColorPersistsAcrossInstances() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub_highlights_color_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = EPUBHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(first)
        let highlight = makeHighlight(color: .yellow)
        first.add(highlight)
        first.updateColor(id: highlight.id, color: .purple)

        let second = EPUBHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(second)
        XCTAssertEqual(second.highlights.first?.color, .purple)
    }

    func testUpdateNoteTrimsAndPersists() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub_highlights_note_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = EPUBHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(first)
        let highlight = makeHighlight()
        first.add(highlight)
        first.updateNote(id: highlight.id, note: "  irony of the fog  ")

        let second = EPUBHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(second)
        XCTAssertEqual(second.highlights.first?.note, "irony of the fog")
    }

    func testRemoveDeletesOnlyThatHighlight() {
        let store = makeStore()
        let keep = makeHighlight(quote: "keep")
        let remove = makeHighlight(quote: "remove")
        store.add(keep)
        store.add(remove)

        store.remove(id: remove.id)

        XCTAssertEqual(store.highlights.count, 1)
        XCTAssertEqual(store.highlights.first?.quote, "keep")
    }

    func testColorRawFallsBackToYellow() {
        let highlight = EPUBHighlight(
            epubFilename: "book", chapterIndex: 0, chapterPath: "OEBPS/text/ch1.xhtml",
            quote: "x", prefix: "", suffix: "", startOffset: 0, colorRaw: "chartreuse"
        )
        XCTAssertEqual(highlight.color, .yellow)
    }

    func testPersistsFullAnchorAcrossInstances() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub_highlights_anchor_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = EPUBHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(first)
        first.add(makeHighlight())

        let second = EPUBHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(second)
        let restored = try XCTUnwrap(second.highlights.first)
        XCTAssertEqual(restored.quote, "a lighthouse in the fog")
        XCTAssertEqual(restored.prefix, "there stood ")
        XCTAssertEqual(restored.suffix, " that winter")
        XCTAssertEqual(restored.startOffset, 120)
        XCTAssertEqual(restored.chapterPath, "OEBPS/text/ch3.xhtml")
        XCTAssertEqual(restored.chapterIndex, 2)
    }
}
