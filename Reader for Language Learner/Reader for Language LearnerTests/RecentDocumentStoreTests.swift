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
        XCTAssertEqual(store.recentDocuments.first?.pageLabel, "Page 8")
    }

    func testUpdateLastPageWithPageCountBuildsProgress() throws {
        let store = makeStore()
        let url = try makeTempPDF(named: "astro-progress")

        store.registerOpen(url: url)
        store.updateLastPage(for: url, pageIndex: 4, pageCount: 10)

        let document = try XCTUnwrap(store.recentDocuments.first)
        XCTAssertEqual(document.pageLabel, "Page 5 of 10")
        XCTAssertEqual(document.readingProgress, 0.5)
    }

    func testReadingProgressNilWithoutPageCount() {
        let document = RecentDocument(path: "/tmp/a.pdf", filename: "a", lastPageIndex: 3)
        XCTAssertNil(document.readingProgress)
        XCTAssertEqual(document.pageLabel, "Page 4")
    }

    func testDecodeLegacyDocumentWithoutPageCount() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","path":"/tmp/a.pdf","filename":"a","lastOpenedAt":700000000,"lastPageIndex":2}
        """
        let decoded = try JSONDecoder().decode(RecentDocument.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.pageCount)
        XCTAssertEqual(decoded.lastPageIndex, 2)
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
