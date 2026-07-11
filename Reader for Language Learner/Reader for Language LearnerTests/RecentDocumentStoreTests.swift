//
//  RecentDocumentStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class RecentDocumentStoreTests: XCTestCase {
    private static var retainedStores: [RecentDocumentStore] = []

    func testRegisterOpenTracksMostRecentDocument() throws {
        let store = makeStore()
        let firstURL = try makeTempPDF(named: "astro-one")
        let secondURL = try makeTempPDF(named: "astro-two")

        store.registerOpen(url: firstURL)
        store.registerOpen(url: secondURL)

        XCTAssertEqual(store.recentDocuments.first?.filename, "astro-two")
        XCTAssertEqual(store.recentDocuments.count, 2)
    }

    func testUpdateLastPagePersistsPageIndex() throws {
        let store = makeStore()
        let url = try makeTempPDF(named: "astro-page")

        store.registerOpen(url: url)
        store.updateLastPage(for: url, pageIndex: 7)

        XCTAssertEqual(store.recentDocuments.first?.lastPageIndex, 7)
        // pageLabel is localized — compare against the same API so this
        // assertion holds regardless of the host machine's system language.
        XCTAssertEqual(store.recentDocuments.first?.pageLabel, String(localized: "Page \(8)"))
    }

    func testUpdateLastPageWithPageCountBuildsProgress() throws {
        let store = makeStore()
        let url = try makeTempPDF(named: "astro-progress")

        store.registerOpen(url: url)
        store.updateLastPage(for: url, pageIndex: 4, pageCount: 10)

        let document = try XCTUnwrap(store.recentDocuments.first)
        XCTAssertEqual(document.pageLabel, String(localized: "Page \(5) of \(10)"))
        XCTAssertEqual(document.readingProgress, 0.5)
    }

    func testReadingProgressNilWithoutPageCount() {
        let document = RecentDocument(path: "/tmp/a.pdf", filename: "a", lastPageIndex: 3)
        XCTAssertNil(document.readingProgress)
        XCTAssertEqual(document.pageLabel, String(localized: "Page \(4)"))
    }

    func testPageLabelUsesChapterWordingForEPUB() {
        let withCount = RecentDocument(
            path: "/tmp/book.epub", filename: "book",
            lastPageIndex: 10, pageCount: 28
        )
        XCTAssertTrue(withCount.isEPUB)
        XCTAssertEqual(withCount.pageLabel, String(localized: "Chapter \(11) of \(28)"))

        let withoutCount = RecentDocument(path: "/tmp/book.epub", filename: "book", lastPageIndex: 2)
        XCTAssertEqual(withoutCount.pageLabel, String(localized: "Chapter \(3)"))
    }

    func testIsEPUBIsCaseInsensitiveAndFalseForPDF() {
        XCTAssertTrue(RecentDocument(path: "/tmp/a.EPUB", filename: "a").isEPUB)
        XCTAssertFalse(RecentDocument(path: "/tmp/a.pdf", filename: "a").isEPUB)
    }

    func testDisplayTitleStripsLegacyExtensionsAndUnderscores() {
        // Legacy entries persisted the filename with its extension.
        XCTAssertEqual(
            RecentDocument(path: "/tmp/a.pdf", filename: "My_Book.pdf").displayTitle,
            "My Book"
        )
        XCTAssertEqual(
            RecentDocument(path: "/tmp/b.epub", filename: "Crime_and_Punishment.EPUB").displayTitle,
            "Crime and Punishment"
        )
        // Current entries are stored extension-less already — unchanged.
        XCTAssertEqual(
            RecentDocument(path: "/tmp/c.epub", filename: "Persuasion").displayTitle,
            "Persuasion"
        )
    }

    func testDecodeLegacyDocumentWithoutPageCount() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","path":"/tmp/a.pdf","filename":"a","lastOpenedAt":700000000,"lastPageIndex":2}
        """
        let decoded = try JSONDecoder().decode(RecentDocument.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.pageCount)
        XCTAssertEqual(decoded.lastPageIndex, 2)
    }

    func testRemoveByIDDeletesOnlyThatDocument() throws {
        let store = makeStore()
        let keepURL = try makeTempPDF(named: "astro-keep")
        let removeURL = try makeTempPDF(named: "astro-remove")

        store.registerOpen(url: keepURL)
        store.registerOpen(url: removeURL)
        let target = try XCTUnwrap(store.recentDocuments.first { $0.filename == "astro-remove" })

        store.remove(id: target.id)

        XCTAssertEqual(store.recentDocuments.count, 1)
        XCTAssertEqual(store.recentDocuments.first?.filename, "astro-keep")
    }

    func testClearEmptiesTheWholeList() throws {
        let store = makeStore()
        store.registerOpen(url: try makeTempPDF(named: "astro-a"))
        store.registerOpen(url: try makeTempPDF(named: "astro-b"))
        XCTAssertEqual(store.recentDocuments.count, 2)

        store.clear()

        XCTAssertTrue(store.recentDocuments.isEmpty)
    }

    private func makeStore() -> RecentDocumentStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = RecentDocumentStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }

    private func makeTempPDF(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("pdf")
        try Data().write(to: url, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
