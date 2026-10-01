//
//  OutputAndImportTests.swift
//  Reader for Language LearnerTests
//
//  v13 Sprint 4: reading from the web (article extraction, the EPUB RELL
//  writes for it) and writing back (retell corrections, word stories).
//  No network — pages are local fixtures.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class OutputAndImportTests: XCTestCase {

    private static let prose = "The committee met on Tuesday to discuss the new rules for river fishing in the valley."

    // MARK: - Article extraction

    /// BBC wraps every paragraph in its own pair of divs; the spike's first
    /// version picked a single paragraph's wrapper and found no article.
    func testFindsBodyWhoseParagraphsAreEachWrapped() async throws {
        let body = (0..<8).map { "<div><div><p>\(Self.prose) Paragraph \($0).</p></div></div>" }.joined()
        let html = """
        <html><head><title>River rules change | Daily News</title></head><body>
        <nav><p>Home News Sport Weather Culture Travel Business Earth Science</p></nav>
        <div class="story">\(body)</div>
        <footer><p>Copyright © 2026 Daily News. All rights reserved everywhere.</p></footer>
        </body></html>
        """
        let article = try ArticleExtractor.extract(html: Data(html.utf8))
        XCTAssertEqual(article.title, "River rules change")
        XCTAssertEqual(article.blocks.count, 8)
        XCTAssertFalse(article.blocks.contains { $0.text.contains("Weather") }, "navigation is stripped")
        XCTAssertFalse(article.blocks.contains { $0.text.contains("Copyright") })
    }

    /// Le Monde: a visually hidden label next to its twin, read as one run.
    func testDropsLinkParagraphsAndDoubledLabels() async throws {
        let body = (0..<8).map { "<p>\(Self.prose) Item \($0).</p>" }.joined()
        let html = """
        <html><body><article>
        <p>Back to the home page of the paperBack to the home page of the paper</p>
        <p><a href="/a">Read also: the other story about fishing rules in the valley</a></p>
        \(body)
        </article></body></html>
        """
        let article = try ArticleExtractor.extract(html: Data(html.utf8))
        XCTAssertFalse(article.blocks.contains { $0.text.hasPrefix("Back to the home") })
        XCTAssertFalse(article.blocks.contains { $0.text.hasPrefix("Read also") })
        XCTAssertEqual(article.blocks.count, 8)
    }

    /// Seen in the spike: pages declaring UTF-8 only in a <meta> came out
    /// as "â€™" when the parser was handed bytes.
    func testDecodesCurlyQuotesFromMetaCharset() async throws {
        let body = (0..<6).map { "<p>The driver’s glasses — \(Self.prose) \($0)</p>" }.joined()
        let html = "<html><head><meta charset=\"utf-8\"></head><body><article>\(body)</article></body></html>"
        let article = try ArticleExtractor.extract(html: Data(html.utf8))
        XCTAssertTrue(article.blocks[0].text.contains("driver’s"), article.blocks[0].text)
        XCTAssertFalse(article.blocks[0].text.contains("â€"))
    }

    /// Seen live: paulgraham.com essays have no <p> at all, only text
    /// between <br><br> — the import failed until this fallback.
    func testSplitsLineBreakSeparatedEssays() async throws {
        let paragraphs = (0..<8).map { "\(Self.prose) Part <i>\($0)</i> of the essay." }
        let html = """
        <html><head><title>How to Fish</title></head><body><table><tr><td>
        <font size="2">\(paragraphs.joined(separator: "<br><br>"))</font>
        </td></tr></table></body></html>
        """
        let article = try ArticleExtractor.extract(html: Data(html.utf8))
        XCTAssertEqual(article.blocks.count, 8)
        XCTAssertTrue(article.blocks[3].text.hasSuffix("Part 3 of the essay."), article.blocks[3].text)
    }

    func testAShortPageIsNotAnArticle() async {
        let html = "<html><body><p>\(Self.prose)</p></body></html>"
        XCTAssertThrowsError(try ArticleExtractor.extract(html: Data(html.utf8))) { error in
            XCTAssertEqual(error as? ArticleExtractor.Failure, .noArticleText)
        }
    }

    func testWebAddressParsing() async {
        XCTAssertEqual(ArticleImporter.webURL(from: " example.com/story ")?.absoluteString, "https://example.com/story")
        XCTAssertEqual(ArticleImporter.webURL(from: "http://news.site/a")?.scheme, "http")
        XCTAssertNil(ArticleImporter.webURL(from: "file:///etc/passwd"))
        XCTAssertNil(ArticleImporter.webURL(from: "not a link"))
        XCTAssertNil(ArticleImporter.webURL(from: "localhost"))
    }

    // MARK: - Writing EPUBs

    func testCRC32MatchesTheStandardCheckValue() async {
        XCTAssertEqual(ZIPWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testZIPWriterRoundTripsThroughTheReader() async throws {
        let zip = ZIPWriter.archive([
            .init(path: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(path: "dir/ü.txt", data: Data("hello".utf8)),
        ])
        let archive = try ZIPArchive(data: zip)
        XCTAssertEqual(try archive.data(at: "dir/ü.txt"), Data("hello".utf8))
        XCTAssertEqual(archive.entryPaths.first, "mimetype", "mimetype comes first")
    }

    func testMiniEPUBOpensAsABookWithEscapedText() async throws {
        let data = MiniEPUB.build(
            title: "Fish & <Chips>",
            author: "Daily News",
            language: "en",
            chapters: [.init(title: "Fish & <Chips>", blocks: [
                .init(text: "A heading", isHeading: true),
                .init(text: "Rules for \"fishing\" & more.", isHeading: false),
            ])],
            note: "From https://example.com/a?b=1&c=2."
        )
        let book = try EPUBDocument(archive: ZIPArchive(data: data))
        XCTAssertEqual(book.title, "Fish & <Chips>")
        XCTAssertEqual(book.chapterCount, 1)
        let text = book.plainText(at: 0)
        XCTAssertTrue(text.contains("Rules for \"fishing\" & more."), text)
        XCTAssertTrue(text.contains("b=1&c=2"), text)
    }

    func testFileNameIsASlug() async {
        XCTAssertEqual(MiniEPUB.fileName(for: "Çok Güzel: Bir Hikâye!"), "cok-guzel-bir-hikaye.epub")
        XCTAssertEqual(MiniEPUB.fileName(for: "???"), "untitled.epub")
    }

    // MARK: - Retell

    func testRetellParsesCorrectionAndNote() async {
        let raw = """
        **CORRECTED:**
        Anne went to the market and bought apples.
        NOTE:
        Anlamı yakalamışsın; "buyed" yerine "bought".
        """
        let feedback = Retell.parse(raw)
        XCTAssertEqual(feedback?.corrected, "Anne went to the market and bought apples.")
        XCTAssertEqual(feedback?.note, "Anlamı yakalamışsın; \"buyed\" yerine \"bought\".")
        XCTAssertNil(Retell.parse("Great job!"))
    }

    func testWordDiffMarksRemovedAndAdded() async {
        let segments = WordDiff.diff("Anne go to market and buyed apples.", "Anne went to the market and bought apples.")
        XCTAssertEqual(segments, [
            .init(kind: .same, text: "Anne"),
            .init(kind: .removed, text: "go"),
            .init(kind: .added, text: "went"),
            .init(kind: .same, text: "to"),
            .init(kind: .added, text: "the"),
            .init(kind: .same, text: "market and"),
            .init(kind: .removed, text: "buyed"),
            .init(kind: .added, text: "bought"),
            .init(kind: .same, text: "apples."),
        ])
        XCTAssertEqual(WordDiff.addedWords(segments), ["went", "the", "bought"])
    }

    func testIdenticalTextHasNoChanges() async {
        XCTAssertEqual(WordDiff.diff("All good here.", "All good here."), [.init(kind: .same, text: "All good here.")])
    }

    // MARK: - Word story

    func testStoryParsesTitleAndParagraphs() async {
        let raw = """
        TITLE: "The Quiet Harbour"
        STORY:
        Mira walked to the harbour.

        She felt drowsy in the sun.
        """
        let story = WordStory.parse(raw)
        XCTAssertEqual(story?.title, "The Quiet Harbour")
        XCTAssertEqual(story?.paragraphs, ["Mira walked to the harbour.", "She felt drowsy in the sun."])
        XCTAssertNil(WordStory.parse("Once upon a time"))
    }

    /// The answer behind the live bug: the placeholder copied, the story run
    /// on after the title, then written again under STORY:. The book showed
    /// it twice — once as a giant heading.
    func testStoryTitleIsOnlyTheTitle() async {
        let raw = """
        TITLE: <a strange night> The landlady found the flats in a strange state. The story was not over.
        STORY:
        The landlady found the flats in a strange state.
        The story was not over.
        """
        let story = WordStory.parse(raw)
        XCTAssertEqual(story?.title, "A strange night")
        XCTAssertEqual(story?.paragraphs.count, 2)
    }

    func testOverlongTitleLineFallsBackToTheDefault() async {
        let line = String(repeating: "The landlady found the flats in a strange state. ", count: 3)
        let story = WordStory.parse("TITLE: \(line)\nSTORY:\nOne paragraph.")
        XCTAssertEqual(story?.title, String(localized: "A Story From Your Words"))
        XCTAssertEqual(story?.paragraphs, ["One paragraph."])
    }

    func testStoryReportsWhichWordsItUsed() async {
        let story = WordStory.Story(title: "T", paragraphs: ["She ran to the harbour and felt drowsy."])
        let used = WordStory.usedWords(["run", "drowsy", "beverage"], in: story, language: .english)
        XCTAssertEqual(used, ["run", "drowsy"])
    }
}
