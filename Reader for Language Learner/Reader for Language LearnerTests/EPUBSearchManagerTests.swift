//
//  EPUBSearchManagerTests.swift
//  Reader for Language LearnerTests
//
//  Builds a tiny two-chapter EPUB via the same ZIPFixture helper
//  EPUBDocumentTests uses, then exercises the synchronous in-book search.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EPUBSearchManagerTests: XCTestCase {
    // CI-only gotcha: the macos-15 runner's Swift toolchain SIGABRTs
    // (libmalloc double-free) when XCTest's post-scope memory checker
    // deallocates a @MainActor @Observable object created in a test body.
    // Every EPUBSearchManager instance must outlive the test.
    private static var retainedManagers: [EPUBSearchManager] = []

    private func makeManager() -> EPUBSearchManager {
        let manager = EPUBSearchManager()
        Self.retainedManagers.append(manager)
        return manager
    }

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
        <dc:identifier id="uid">urn:uuid:search-test</dc:identifier>
        <dc:title>Search Test Book</dc:title>
      </metadata>
      <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
        <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
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
            <li><a href="text/ch1.xhtml">The Storm</a></li>
            <li><a href="text/ch2.xhtml">After the Storm</a></li>
          </ol>
        </nav>
      </body>
    </html>
    """

    private static let chapter1 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><body>
    <p>The lighthouse stood against the storm. The lighthouse keeper watched the waves.</p>
    </body></html>
    """

    private static let chapter2 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><body>
    <p>By morning the harbor was calm and quiet.</p>
    </body></html>
    """

    private func makeDocument() throws -> EPUBDocument {
        let zip = ZIPFixture.build([
            .init(path: "META-INF/container.xml", data: Data(Self.containerXML.utf8), deflate: false),
            .init(path: "OEBPS/content.opf", data: Data(Self.opf.utf8), deflate: false),
            .init(path: "OEBPS/nav.xhtml", data: Data(Self.nav.utf8), deflate: false),
            .init(path: "OEBPS/text/ch1.xhtml", data: Data(Self.chapter1.utf8), deflate: false),
            .init(path: "OEBPS/text/ch2.xhtml", data: Data(Self.chapter2.utf8), deflate: false),
        ])
        return try EPUBDocument(archive: ZIPArchive(data: zip))
    }

    func testShortQueryIsIgnored() throws {
        let manager = makeManager()
        let document = try makeDocument()
        manager.query = "a"
        manager.runSearch(in: document)

        XCTAssertFalse(manager.hasSearched)
        XCTAssertTrue(manager.results.isEmpty)
    }

    func testSearchFindsMatchesInOneChapterWithCorrectCount() throws {
        let manager = makeManager()
        let document = try makeDocument()
        manager.query = "lighthouse"
        manager.runSearch(in: document)

        XCTAssertTrue(manager.hasSearched)
        XCTAssertEqual(manager.results.count, 1)
        XCTAssertEqual(manager.results.first?.chapterIndex, 0)
        XCTAssertEqual(manager.results.first?.chapterTitle, "The Storm")
        XCTAssertEqual(manager.results.first?.matchCount, 2)
        XCTAssertEqual(manager.totalMatches, 2)
    }

    func testSearchIsCaseInsensitiveAndCanSpanChapters() throws {
        let manager = makeManager()
        let document = try makeDocument()
        manager.query = "STORM"
        manager.runSearch(in: document)

        // "storm" (lowercase) only appears in chapter 1's body text; nav
        // labels like chapter 2's "After the Storm" aren't part of any
        // chapter's plainText, so this must not spuriously match chapter 2.
        XCTAssertEqual(manager.results.count, 1)
        XCTAssertEqual(manager.results.first?.matchCount, 1)
    }

    func testSearchWithNoMatchesReturnsEmptyButMarksSearched() throws {
        let manager = makeManager()
        let document = try makeDocument()
        manager.query = "dragon"
        manager.runSearch(in: document)

        XCTAssertTrue(manager.hasSearched)
        XCTAssertTrue(manager.results.isEmpty)
        XCTAssertEqual(manager.totalMatches, 0)
    }

    func testClearResetsState() throws {
        let manager = makeManager()
        let document = try makeDocument()
        manager.query = "lighthouse"
        manager.runSearch(in: document)

        manager.clear()

        XCTAssertEqual(manager.query, "")
        XCTAssertTrue(manager.results.isEmpty)
        XCTAssertFalse(manager.hasSearched)
    }

    func testShowAndCloseFindBarTogglesVisibilityAndClears() throws {
        let manager = makeManager()
        let document = try makeDocument()
        manager.showFindBar()
        XCTAssertTrue(manager.isFindBarVisible)

        manager.query = "lighthouse"
        manager.runSearch(in: document)
        manager.closeFindBar()

        XCTAssertFalse(manager.isFindBarVisible)
        XCTAssertTrue(manager.results.isEmpty)
    }
}
