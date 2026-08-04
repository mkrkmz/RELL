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

final class EPUBSplitChapterTests: XCTestCase {

    // MARK: - HTML surgery

    func testBodyInnerHTMLExtractsBetweenBodyTags() {
        let html = "<html><head><title>x</title></head><body class=\"c\"><h2>CHAPTER 1</h2></body></html>"
        XCTAssertEqual(EPUBDocument.bodyInnerHTML(of: html), "<h2>CHAPTER 1</h2>")
    }

    func testBodyInnerHTMLReturnsNilForEmptyOrMissingBody() {
        XCTAssertNil(EPUBDocument.bodyInnerHTML(of: "<html><head></head></html>"))
        XCTAssertNil(EPUBDocument.bodyInnerHTML(of: "<html><body>   </body></html>"))
    }

    func testInjectHeadingPlacesItInsideTheBody() throws {
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

    func testInjectHeadingLeavesBodylessMarkupAlone() {
        XCTAssertNil(EPUBDocument.injectHeading("<h2>X</h2>", into: Data("no body here".utf8)))
    }

    // MARK: - Against a real split book

    /// End-to-end on the book that surfaced this: every table-of-contents entry
    /// must land on prose, not on a heading stub.
    func testRealSplitBookResolvesTOCEntriesToProse() throws {
        let path = ("~/Downloads/Why We Sleep_ Unlocking the Power of Sleep and Dreams -- Walker, Matthew -- 2215bbe2fa1ffc1b477714adb7464da8 -- Anna’s Archive.epub" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("sample book not present on this machine")
        }
        let document = try EPUBDocument(url: URL(fileURLWithPath: path))

        var stubsFound = 0
        for entry in document.tocEntries {
            guard let chapterPath = entry.chapterPath,
                  let index = document.chapterIndex(forPath: chapterPath)
            else { continue }

            if document.isHeadingStub(at: index) { stubsFound += 1 }

            // The reader must never *land* on a stub. (Part dividers are
            // legitimately short and aren't stubs — nothing was split off them.)
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
    func testRealSplitBookServesTheHeadingWithTheProse() throws {
        let path = ("~/Downloads/Why We Sleep_ Unlocking the Power of Sleep and Dreams -- Walker, Matthew -- 2215bbe2fa1ffc1b477714adb7464da8 -- Anna’s Archive.epub" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("sample book not present on this machine")
        }
        let document = try EPUBDocument(url: URL(fileURLWithPath: path))

        guard let stubIndex = (0..<document.chapterCount).first(where: { document.isHeadingStub(at: $0) }) else {
            return XCTFail("precondition: expected a heading stub")
        }
        // The stub's *visible* heading — `plainText` would also pull in the
        // document head's <title>, which isn't what the page shows.
        let stubHTML = String(decoding: try document.chapterData(at: stubIndex), as: UTF8.self)
        let stubBody = try XCTUnwrap(EPUBDocument.bodyInnerHTML(of: stubHTML))
        let headingText = EPUBDocument.visibleText(in: stubBody)
        XCTAssertFalse(headingText.isEmpty, "precondition: the stub shows a heading")

        let proseIndex = stubIndex + 1
        let served = try document.resource(at: document.chapterPath(at: proseIndex))
        let servedText = EPUBDocument.visibleText(in: String(decoding: served.data, as: UTF8.self))

        XCTAssertTrue(
            servedText.contains(headingText),
            "the folded chapter should carry its heading (\(headingText))"
        )
    }

    /// A book that isn't split must be served untouched.
    func testOrdinaryBookIsNotReshuffled() throws {
        let path = ("~/Downloads/Crime and Punishment.epub" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("sample book not present on this machine")
        }
        let document = try EPUBDocument(url: URL(fileURLWithPath: path))

        for index in 0..<document.chapterCount {
            XCTAssertEqual(
                document.readableChapterIndex(for: index), index,
                "chapter \(index) of an unsplit book should resolve to itself"
            )
        }
    }
}
