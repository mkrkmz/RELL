//
//  RecentDocumentStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class RecentDocumentStoreTests: XCTestCase {

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

    private func makeStore() -> RecentDocumentStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return RecentDocumentStore(fileURL: fileURL)
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
