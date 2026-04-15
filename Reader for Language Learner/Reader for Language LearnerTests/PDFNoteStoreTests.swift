//
//  PDFNoteStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class PDFNoteStoreTests: XCTestCase {
    private static var retainedStores: [PDFNoteStore] = []

    func testAddAndFilterNotesByDocument() {
        let store = makeStore()
        store.add(PDFNote(pdfFilename: "a.pdf", pageIndex: 0, pageLabel: "Page 1", selectedText: "orbit", contextSentence: "", note: "test", category: .vocabulary, highlightRects: []))
        store.add(PDFNote(pdfFilename: "b.pdf", pageIndex: 1, pageLabel: "Page 2", selectedText: "gravity", contextSentence: "", note: "test", category: .review, highlightRects: []))

        XCTAssertEqual(store.notes(for: "a.pdf").count, 1)
        XCTAssertEqual(store.count(for: "b.pdf"), 1)
    }

    func testFilterByCategoryAndSearchText() {
        let store = makeStore()
        store.add(PDFNote(pdfFilename: "astro.pdf", pageIndex: 0, pageLabel: "Page 1", selectedText: "orbit", contextSentence: "Planet orbit", note: "Useful noun", category: .vocabulary, highlightRects: []))
        store.add(PDFNote(pdfFilename: "astro.pdf", pageIndex: 2, pageLabel: "Page 3", selectedText: "gravity", contextSentence: "Review this later", note: "", category: .review, highlightRects: []))

        XCTAssertEqual(store.filteredNotes(for: "astro.pdf", filter: .vocabulary).count, 1)
        XCTAssertEqual(store.filteredNotes(for: "astro.pdf", searchText: "later", filter: .all).count, 1)
        XCTAssertEqual(store.filteredNotes(for: "astro.pdf", searchText: "orbit", filter: .review).count, 0)
    }

    func testDraftCanBeStartedAndCancelled() {
        let store = makeStore()
        let draft = PDFNote(pdfFilename: "a.pdf", pageIndex: 0, pageLabel: "Page 1", selectedText: "orbit", contextSentence: "", note: "", category: .vocabulary, highlightRects: [])

        store.startDraft(draft)
        XCTAssertEqual(store.draftNote?.selectedText, "orbit")

        store.cancelDraft()
        XCTAssertNil(store.draftNote)
    }

    func testDecodeLegacyNoteDefaultsCategory() throws {
        let json = """
        [
          {
            "id": "D88A716D-6B96-4D84-AB95-1A1DB3CB8560",
            "pdfFilename": "legacy.pdf",
            "pageIndex": 0,
            "pageLabel": "Page 1",
            "selectedText": "orbit",
            "contextSentence": "orbit around the sun",
            "note": "legacy note",
            "highlightRects": [],
            "createdAt": 123456789,
            "updatedAt": 123456789
          }
        ]
        """
        let notes = try JSONDecoder().decode([PDFNote].self, from: Data(json.utf8))
        XCTAssertEqual(notes.first?.category, .vocabulary)
    }

    private func makeStore() -> PDFNoteStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = PDFNoteStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }
}
