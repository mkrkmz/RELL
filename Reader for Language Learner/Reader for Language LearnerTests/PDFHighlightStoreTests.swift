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
}
