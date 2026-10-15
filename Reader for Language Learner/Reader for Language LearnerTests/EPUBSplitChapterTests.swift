//
//  EPUBSplitChapterTests.swift
//  Reader for Language LearnerTests
//
//  Books split by a tool like Calibre put a chapter's heading in one spine
//  item and its prose in the next. Treating those as two chapters made every
//  table-of-contents entry open a page containing only "CHAPTER 1" — the book
//  looked empty. These pin the folding behaviour that fixes it.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EPUBSplitChapterTests: XCTestCase {

    // MARK: - HTML surgery

    func testBodyInnerHTMLExtractsBetweenBodyTags() async {
        let html = "<html><head><title>x</title></head><body class=\"c\"><h2>CHAPTER 1</h2></body></html>"
        XCTAssertEqual(EPUBDocument.bodyInnerHTML(of: html), "<h2>CHAPTER 1</h2>")
    }

    func testBodyInnerHTMLReturnsNilForEmptyOrMissingBody() async {
        XCTAssertNil(EPUBDocument.bodyInnerHTML(of: "<html><head></head></html>"))
        XCTAssertNil(EPUBDocument.bodyInnerHTML(of: "<html><body>   </body></html>"))
    }

    func testInjectHeadingPlacesItInsideTheBody() async throws {
        let chapter = "<html><body class=\"c\"><p>To Sleep …</p></body></html>"
        let data = Data(chapter.utf8)

        let merged = try XCTUnwrap(EPUBDocument.injectHeading("<h2>CHAPTER 1</h2>", into: data))
        let text = String(decoding: merged, as: UTF8.self)

        XCTAssertTrue(text.contains("<h2>CHAPTER 1</h2>"), "the heading survives the merge")
        XCTAssertTrue(text.contains("<p>To Sleep …</p>"), "the prose survives the merge")
        let headingAt = try XCTUnwrap(text.range(of: "CHAPTER 1"))
        let proseAt = try XCTUnwrap(text.range(of: "To Sleep"))
        XCTAssertLessThan(headingAt.lowerBound, proseAt.lowerBound, "heading comes first")
        XCTAssertFalse(text.contains("</body></body>"), "the document stays well-formed")
    }

    func testInjectHeadingLeavesBodylessMarkupAlone() async {
        XCTAssertNil(EPUBDocument.injectHeading("<h2>X</h2>", into: Data("no body here".utf8)))
    }

    // MARK: - Against a real split book

    // MARK: - Books made for the test (v18 S0)
    //
    // These ran on real books in the developer's Downloads folder — skipped
    // on every other machine, 70–150 s on that one, and a personal file name
    // in the repository. Now small books built with `MiniEPUB`: a split one
    // (each chapter's heading on its own page, the way some converters
    // produce them) and an ordinary one.

    private static let prose = (0..<12).map { _ in
        ExtractedArticle.Block(text: String(repeating: "The old harbour lay quiet under a pewter sky. ", count: 5),
                               isHeading: false)
    }

    /// Headings split off onto their own pages, the prose on the next.
    private func splitBook() throws -> EPUBDocument {
        try book(named: "split", chapters: [
            .init(title: "One: The Harbour", blocks: []),
            .init(title: "", blocks: Self.prose),
            .init(title: "Two: The Market", blocks: []),
            .init(title: "", blocks: Self.prose),
        ])
    }

    private func ordinaryBook() throws -> EPUBDocument {
        try book(named: "ordinary", chapters: (1...4).map { .init(title: "Chapter \($0)", blocks: Self.prose) })
    }

    private func book(named name: String, chapters: [MiniEPUB.Chapter]) throws -> EPUBDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBSplitChapterTests-\(name)-\(UUID().uuidString).epub")
        try MiniEPUB.build(title: "Test Book", author: nil, language: "en", chapters: chapters).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try EPUBDocument(url: url)
    }

    /// Every table-of-contents entry must land on prose, not on a heading stub.
    func testSplitBookResolvesTOCEntriesToProse() async throws {
        let document = try splitBook()

        var stubsFound = 0
        for entry in document.tocEntries {
            guard let chapterPath = entry.chapterPath,
                  let index = document.chapterIndex(forPath: chapterPath)
            else { continue }

            if document.isHeadingStub(at: index) { stubsFound += 1 }

            // The reader must never *land* on a stub.
            let readable = document.readableChapterIndex(for: index)
            XCTAssertFalse(
                document.isHeadingStub(at: readable),
                "TOC entry '\(entry.title)' should open prose, not a heading stub"
            )
        }
        XCTAssertGreaterThan(stubsFound, 0, "precondition: this book is a split book")
    }

    /// Reading the folded chapter must show the heading that was split off,
    /// so nothing the author wrote disappears.
    func testSplitBookServesTheHeadingWithTheProse() async throws {
        let document = try splitBook()

        guard let stubIndex = (0..<document.chapterCount).first(where: { document.isHeadingStub(at: $0) }) else {
            return XCTFail("precondition: expected a heading stub")
        }
        let stubHTML = String(decoding: try document.chapterData(at: stubIndex), as: UTF8.self)
        let stubBody = try XCTUnwrap(EPUBDocument.bodyInnerHTML(of: stubHTML))
        let headingText = EPUBDocument.visibleText(in: stubBody)
        XCTAssertEqual(headingText, "One: The Harbour")

        let proseIndex = stubIndex + 1
        let served = try document.resource(at: document.chapterPath(at: proseIndex))
        let servedText = EPUBDocument.visibleText(in: String(decoding: served.data, as: UTF8.self))

        XCTAssertTrue(
            servedText.contains(headingText),
            "the folded chapter should carry its heading (\(headingText))"
        )
    }

    /// A book that isn't split must be served untouched.
    func testOrdinaryBookIsNotReshuffled() async throws {
        let document = try ordinaryBook()
        XCTAssertGreaterThanOrEqual(document.chapterCount, 4)

        for index in 0..<document.chapterCount {
            XCTAssertFalse(document.isHeadingStub(at: index))
            XCTAssertEqual(
                document.readableChapterIndex(for: index), index,
                "chapter \(index) of an unsplit book should resolve to itself"
            )
        }
    }
}
