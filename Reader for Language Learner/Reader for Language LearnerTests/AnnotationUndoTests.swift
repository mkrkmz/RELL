//
//  AnnotationUndoTests.swift
//  Reader for Language LearnerTests
//
//  Verifies the shared UndoableStore round-trip (Roadmap v9 Sprint 2, U5):
//  a mutation registers its inverse, so undo reverses it and redo re-applies.
//  PDFHighlightStore stands in for all six annotation stores — they share the
//  same `registerUndo` plumbing.
//
//  Methods are `async` to match the CI-safe convention (synchronous @MainActor
//  XCTest methods that drive the debounced writer deadlocked the runner).
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class AnnotationUndoTests: XCTestCase {
    private static var retainedStores: [PDFHighlightStore] = []

    func testAddThenUndoRemovesAndRedoRestores() async throws {
        let store = makeStore()
        let undo = makeUndoManager()
        store.undoManager = undo
        let highlight = sampleHighlight()

        undo.beginUndoGrouping(); store.add(highlight); undo.endUndoGrouping()
        await Task.yield()
        XCTAssertEqual(store.highlights.count, 1)

        undo.undo()
        XCTAssertTrue(store.highlights.isEmpty, "undo removes the added highlight")

        undo.redo()
        XCTAssertEqual(store.highlights.map(\.id), [highlight.id], "redo re-adds it")
    }

    func testRemoveThenUndoRestoresAtOriginalIndex() async throws {
        let store = makeStore()
        let undo = makeUndoManager()
        let first = sampleHighlight()
        let second = sampleHighlight()
        store.add(first)   // no undo manager yet — set-up, not under test
        store.add(second)  // second is now at index 0, first at index 1
        store.undoManager = undo

        undo.beginUndoGrouping(); store.remove(id: first.id); undo.endUndoGrouping()
        await Task.yield()
        XCTAssertEqual(store.highlights.map(\.id), [second.id])

        undo.undo()
        XCTAssertEqual(store.highlights.map(\.id), [second.id, first.id], "undo restores at the prior index")
    }

    func testColorChangeIsUndoable() async throws {
        let store = makeStore()
        let undo = makeUndoManager()
        let highlight = sampleHighlight(color: "yellow")
        store.add(highlight)
        store.undoManager = undo

        undo.beginUndoGrouping(); store.updateColor(id: highlight.id, color: .green); undo.endUndoGrouping()
        await Task.yield()
        XCTAssertEqual(store.highlights.first?.colorRaw, "green")

        undo.undo()
        XCTAssertEqual(store.highlights.first?.colorRaw, "yellow", "undo restores the prior color")
    }

    func testNoUndoManagerIsHarmless() async throws {
        let store = makeStore()   // undoManager stays nil
        store.add(sampleHighlight())
        await Task.yield()
        XCTAssertEqual(store.highlights.count, 1, "mutations still work without an undo manager")
    }

    // MARK: - Helpers

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false   // no run loop in tests; group explicitly
        return undo
    }

    private func sampleHighlight(color: String = "yellow") -> PDFHighlight {
        PDFHighlight(
            pdfFilename: "doc",
            pageIndex: 0,
            pageLabel: "1",
            selectedText: "word",
            colorRaw: color,
            highlightRects: []
        )
    }

    private func makeStore() -> PDFHighlightStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = PDFHighlightStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return store
    }
}
