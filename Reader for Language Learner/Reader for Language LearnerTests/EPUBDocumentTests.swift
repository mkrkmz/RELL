//
//  EPUBDocumentTests.swift
//  Reader for Language LearnerTests
//
//  Builds a minimal-but-valid EPUB3 in memory via ZIPFixture and exercises
//  the full parse: container → OPF → spine → nav TOC → cover → resources.
//

import XCTest
@testable import Reader_for_Language_Learner

final class EPUBDocumentTests: XCTestCase {

    // MARK: - Fixture

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private static let opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="uid">urn:uuid:test-book</dc:identifier>
        <dc:title>Test Kitabı</dc:title>
        <dc:creator>Ada Yazar</dc:creator>
        <dc:language>en</dc:language>
      </metadata>
      <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
        <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
        <item id="cover" href="images/cover.png" media-type="image/png" properties="cover-image"/>
        <item id="css" href="style/book.css" media-type="text/css"/>
      </manifest>
      <spine>
        <itemref idref="ch1"/>
        <itemref idref="ch2"/>
      </spine>
    </package>
    """

    private static let nav = """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
      <body>
        <nav epub:type="toc">
          <ol>
            <li><a href="text/ch1.xhtml">Birinci Bölüm</a></li>
            <li><a href="text/ch2.xhtml#part2">İkinci Bölüm</a></li>
          </ol>
        </nav>
      </body>
    </html>
    """

    private static func chapter(_ n: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <h1>Chapter \(n)</h1><p>Content of chapter \(n).</p>
        </body></html>
        """
    }

    private static func makeEPUBData() -> Data {
        ZIPFixture.build([
            .init(path: "mimetype", data: Data("application/epub+zip".utf8), deflate: false),
            .init(path: "META-INF/container.xml", data: Data(containerXML.utf8), deflate: true),
            .init(path: "OEBPS/content.opf", data: Data(opf.utf8), deflate: true),
            .init(path: "OEBPS/nav.xhtml", data: Data(nav.utf8), deflate: true),
            .init(path: "OEBPS/text/ch1.xhtml", data: Data(chapter(1).utf8), deflate: true),
            .init(path: "OEBPS/text/ch2.xhtml", data: Data(chapter(2).utf8), deflate: true),
            .init(path: "OEBPS/images/cover.png", data: Data([0x89, 0x50, 0x4E, 0x47]), deflate: false),
            .init(path: "OEBPS/style/book.css", data: Data("body { margin: 1em; }".utf8), deflate: true),
        ])
    }

    private func makeDocument() throws -> EPUBDocument {
        try EPUBDocument(archive: ZIPArchive(data: Self.makeEPUBData()))
    }

    // MARK: - Tests

    func testMetadata() throws {
        let doc = try makeDocument()
        XCTAssertEqual(doc.title, "Test Kitabı")
        XCTAssertEqual(doc.author, "Ada Yazar")
        XCTAssertEqual(doc.language, "en")
    }

    func testSpineOrderAndChapterAccess() throws {
        let doc = try makeDocument()
        XCTAssertEqual(doc.chapterCount, 2)
        XCTAssertEqual(doc.spinePaths, ["OEBPS/text/ch1.xhtml", "OEBPS/text/ch2.xhtml"])

        let ch2 = try doc.chapterData(at: 1)
        XCTAssertTrue(String(decoding: ch2, as: UTF8.self).contains("Chapter 2"))

        XCTAssertEqual(doc.chapterIndex(forPath: "OEBPS/text/ch2.xhtml"), 1)
        XCTAssertThrowsError(try doc.chapterData(at: 5))
    }

    func testNavTOC() throws {
        let doc = try makeDocument()
        XCTAssertEqual(doc.tocEntries.count, 2)
        XCTAssertEqual(doc.tocEntries[0].title, "Birinci Bölüm")
        XCTAssertEqual(doc.tocEntries[0].chapterPath, "OEBPS/text/ch1.xhtml")
        XCTAssertNil(doc.tocEntries[0].fragment)
        XCTAssertEqual(doc.tocEntries[1].fragment, "part2")
        XCTAssertEqual(doc.tocEntries[1].chapterPath, "OEBPS/text/ch2.xhtml")
    }

    func testCoverDetection() throws {
        let doc = try makeDocument()
        XCTAssertEqual(doc.coverImagePath, "OEBPS/images/cover.png")
    }

    func testResourceLookupUsesManifestMime() throws {
        let doc = try makeDocument()
        let css = try doc.resource(at: "OEBPS/style/book.css")
        XCTAssertEqual(css.mimeType, "text/css")
        XCTAssertTrue(doc.containsResource(at: "OEBPS/images/cover.png"))
        XCTAssertFalse(doc.containsResource(at: "OEBPS/missing.png"))
    }

    func testNotAnEPUBThrows() {
        let zip = ZIPFixture.build([
            .init(path: "readme.txt", data: Data("not an epub".utf8), deflate: false)
        ])
        XCTAssertThrowsError(try EPUBDocument(archive: ZIPArchive(data: zip))) { error in
            guard case EPUBDocumentError.missingContainer = error else {
                return XCTFail("expected missingContainer, got \(error)")
            }
        }
    }

    func testPlainTextExtraction() throws {
        let doc = try makeDocument()
        let text = doc.plainText(at: 0)
        XCTAssertTrue(text.contains("Chapter 1"))
        XCTAssertTrue(text.contains("Content of chapter 1."))
        XCTAssertFalse(text.contains("<"), "markup must be stripped")
    }

    /// The cache backing `plainText(at:)` must return identical text on
    /// repeat reads and never crash or corrupt under concurrent access from
    /// multiple threads — this is exactly the access pattern the EPUB
    /// search manager's detached scan produces.
    func testPlainTextIsStableAndThreadSafeUnderConcurrentAccess() throws {
        let doc = try makeDocument()
        let first = doc.plainText(at: 0)
        XCTAssertEqual(doc.plainText(at: 0), first)
        XCTAssertEqual(doc.plainText(at: 1), doc.plainText(at: 1))

        let expectation = XCTestExpectation(description: "concurrent plainText reads")
        expectation.expectedFulfillmentCount = 100
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            let text = doc.plainText(at: i % 2)
            XCTAssertFalse(text.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testChapterTitleFallsBackWhenNotInTOC() throws {
        let doc = try makeDocument()
        XCTAssertEqual(doc.chapterTitle(at: 0), "Birinci Bölüm")   // from nav TOC
        XCTAssertEqual(doc.chapterTitle(at: 1), "İkinci Bölüm")
    }

    func testHrefResolution() {
        XCTAssertEqual(
            EPUBDocument.resolve(href: "text/ch1.xhtml", relativeTo: "OEBPS/content.opf").path,
            "OEBPS/text/ch1.xhtml"
        )
        XCTAssertEqual(
            EPUBDocument.resolve(href: "../images/pic.png", relativeTo: "OEBPS/text/ch1.xhtml").path,
            "OEBPS/images/pic.png"
        )
        let fragmentOnly = EPUBDocument.resolve(href: "#note1", relativeTo: "OEBPS/text/ch1.xhtml")
        XCTAssertEqual(fragmentOnly.path, "OEBPS/text/ch1.xhtml")
        XCTAssertEqual(fragmentOnly.fragment, "note1")
        XCTAssertEqual(
            EPUBDocument.resolve(href: "my%20file.xhtml", relativeTo: "OEBPS/content.opf").path,
            "OEBPS/my file.xhtml"
        )
    }
}
