//
//  PDFHighlightStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class PDFHighlightStoreTests: XCTestCase {
    private static var retainedStores: [PDFHighlightStore] = []

    private func makeStore() -> PDFHighlightStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("highlights_test_\(UUID().uuidString).json")
        let store = PDFHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return store
    }

    private func makeHighlight(
        file: String = "doc",
        page: Int = 0,
        text: String = "passage",
        color: HighlightColor = .yellow
    ) -> PDFHighlight {
        PDFHighlight(
            pdfFilename: file,
            pageIndex: page,
            pageLabel: "Page \(page + 1)",
            selectedText: text,
            colorRaw: color.rawValue,
            highlightRects: [PDFHighlightRect(x: 0, y: 0, width: 10, height: 4)]
        )
    }

    func testAddAndFilterByDocument() {
        let store = makeStore()
        store.add(makeHighlight(file: "alpha", text: "a"))
        store.add(makeHighlight(file: "beta", text: "b"))
        store.add(makeHighlight(file: "alpha", text: "c"))

        XCTAssertEqual(store.highlights(for: "alpha").count, 2)
        XCTAssertEqual(store.highlights(for: "beta").count, 1)
        XCTAssertEqual(store.count(for: "alpha"), 2)
        XCTAssertEqual(store.count(for: nil), 0)
    }

    func testHighlightsSortedByPageThenRecency() {
        let store = makeStore()
        store.add(makeHighlight(file: "doc", page: 5, text: "late page"))
        store.add(makeHighlight(file: "doc", page: 1, text: "early page"))

        let ordered = store.highlights(for: "doc")
        XCTAssertEqual(ordered.first?.selectedText, "early page")
        XCTAssertEqual(ordered.last?.selectedText, "late page")
    }

    func testUpdateColor() {
        let store = makeStore()
        let highlight = makeHighlight(color: .yellow)
        store.add(highlight)

        store.updateColor(id: highlight.id, color: .green)

        XCTAssertEqual(store.highlights(for: "doc").first?.color, .green)
    }

    func testRemove() {
        let store = makeStore()
        let highlight = makeHighlight()
        store.add(highlight)
        store.remove(id: highlight.id)

        XCTAssertTrue(store.highlights(for: "doc").isEmpty)
    }

    func testPersistsAcrossInstances() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("highlights_persist_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = PDFHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(first)
        first.add(makeHighlight(text: "remembered", color: .pink))

        let second = PDFHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(second)
        let restored = second.highlights(for: "doc")
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.selectedText, "remembered")
        XCTAssertEqual(restored.first?.color, .pink)
    }

    func testColorRawFallsBackToYellow() {
        let highlight = PDFHighlight(
            pdfFilename: "doc", pageIndex: 0, pageLabel: "Page 1",
            selectedText: "x", colorRaw: "chartreuse", highlightRects: []
        )
        XCTAssertEqual(highlight.color, .yellow)
    }

    // MARK: - Notes

    func testUpdateNotePersistsAcrossInstances() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("highlights_note_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = PDFHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(first)
        let highlight = makeHighlight(text: "annotated", color: .blue)
        first.add(highlight)
        first.updateNote(id: highlight.id, note: "  grammar point here  ")

        let second = PDFHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(second)
        XCTAssertEqual(second.highlights.first?.note, "grammar point here", "note is trimmed and persisted")

        // Clearing the note also persists.
        second.updateNote(id: highlight.id, note: "")
        let third = PDFHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(third)
        XCTAssertEqual(third.highlights.first?.note, "")
    }

    func testDecodesLegacyHighlightWithoutNoteField() throws {
        // Pre-1.10 persistence files have no "note" key — decoding must not throw.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","pdfFilename":"doc","pageIndex":2,"pageLabel":"Page 3",
         "selectedText":"old","colorRaw":"green","highlightRects":[],"createdAt":700000000}
        """
        let decoded = try JSONDecoder().decode(PDFHighlight.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.note, "")
        XCTAssertEqual(decoded.selectedText, "old")
        XCTAssertEqual(decoded.color, .green)
    }
}
