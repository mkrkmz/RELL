//
//  InterlinearGlossTests.swift
//  Reader for Language LearnerTests
//
//  Meanings above words in books (v13 Sprint 3): the model's answer, how a
//  gloss is fitted above a word, and — in the reader's real web view
//  configuration — that the meaning is drawn without changing the text.
//

import WebKit
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class InterlinearGlossTests: XCTestCase {
    private static var retained: [AnyObject] = []

    // MARK: - Parsing

    /// The on-device model's real answer to the gloss prompt (v13 spike).
    func testParseReadsTheModelsAnswer() async {
        let raw = """
        circadian | günlük ritim
        melatonin | uyku hormonu
        sleep | uyku
        """
        let glosses = InterlinearGloss.parse(raw, requested: ["circadian", "melatonin", "sleep"])
        XCTAssertEqual(glosses["melatonin"], "uyku hormonu")
        XCTAssertEqual(glosses.count, 3)
    }

    func testParseIgnoresUnaskedWordsAndChatter() async {
        let raw = """
        Here are the glosses:
        **sleep** | rest time.
        dream | not asked for
        """
        XCTAssertEqual(InterlinearGloss.parse(raw, requested: ["sleep"]), ["sleep": "rest time"])
    }

    func testLongGlossIsCutAtAWordOrDropped() async {
        let long = InterlinearGloss.fit("a hormone that tells the body it is time to sleep")
        XCTAssertNotNil(long)
        XCTAssertLessThanOrEqual(long?.count ?? .max, InterlinearGloss.maxLength)
        XCTAssertFalse(long?.hasSuffix(" ") ?? true)
        XCTAssertNil(InterlinearGloss.fit(String(repeating: "x", count: 40)), "one word too long to fit")
    }

    func testInflectedFormsShareTheirWordsGloss() async {
        let glosses = EPUBViewManager.glossesIncludingInflections(
            ["run": "koşmak"], inflected: ["ran", "running"], language: .english
        )
        XCTAssertEqual(glosses["ran"], "koşmak")
        XCTAssertEqual(glosses["running"], "koşmak")
    }

    // MARK: - Rendering (real reader configuration)

    func testGlossIsDrawnAboveTheWordWithoutChangingTheText() async throws {
        let webView = try await makeReader(html: "<p>Melatonin rises at dusk, and we sleep. A lark sings.</p>")
        let before = try await evaluate("document.body.textContent", in: webView) as? String

        _ = try await evaluate(EPUBViewManager.markSavedWordsScript(
            for: ["sleep"],
            color: "blue",
            glosses: ["sleep": "uyku", "melatonin": "uyku hormonu"],
            glossOnly: ["melatonin"],
            glossColor: "red"
        ), in: webView)

        // The whole point of drawing with CSS: highlights, search and
        // karaoke all count characters in textContent.
        let after = try await evaluate("document.body.textContent", in: webView) as? String
        XCTAssertEqual(after, before)

        let saved = try await evaluate("""
        (function() {
            var s = document.querySelector('span[data-rell-saved-word="1"]');
            return [s.textContent, s.getAttribute('data-rell-gloss'),
                    getComputedStyle(s, '::after').content, s.style.textDecorationLine].join('|');
        })()
        """, in: webView) as? String
        XCTAssertEqual(saved, "sleep|uyku|\"uyku\"|underline")

        // A warm-up word gets its meaning but not the saved-word underline.
        let warmUp = try await evaluate("""
        (function() {
            var s = document.querySelector('span[data-rell-saved-word="gloss"]');
            return [s.textContent, s.getAttribute('data-rell-gloss'), s.style.textDecorationLine].join('|');
        })()
        """, in: webView) as? String
        XCTAssertEqual(warmUp, "Melatonin|uyku hormonu|")

        let glossing = try await evaluate("document.documentElement.classList.contains('rell-glossing')", in: webView) as? Bool
        XCTAssertEqual(glossing, true)
    }

    func testTurningGlossesOffRemovesThem() async throws {
        let webView = try await makeReader(html: "<p>We sleep.</p>")
        _ = try await evaluate(EPUBViewManager.markSavedWordsScript(
            for: ["sleep"], color: "blue", glosses: ["sleep": "uyku"], glossColor: "red"
        ), in: webView)
        _ = try await evaluate(EPUBViewManager.markSavedWordsScript(for: ["sleep"], color: "blue"), in: webView)

        let state = try await evaluate("""
        [document.querySelectorAll('[data-rell-gloss]').length,
         document.getElementById('rell-gloss-style') === null,
         document.documentElement.classList.contains('rell-glossing')].join('|')
        """, in: webView) as? String
        XCTAssertEqual(state, "0|true|false")
    }

    /// A gloss comes from a model; quotes in it must not break the script.
    func testGlossWithQuotesIsSafe() async throws {
        let webView = try await makeReader(html: "<p>We sleep.</p>")
        _ = try await evaluate(EPUBViewManager.markSavedWordsScript(
            for: ["sleep"], color: "blue", glosses: ["sleep": "it's \"rest\""], glossColor: "red"
        ), in: webView)
        let gloss = try await evaluate(
            "document.querySelector('[data-rell-gloss]').getAttribute('data-rell-gloss')", in: webView
        ) as? String
        XCTAssertEqual(gloss, "it's \"rest\"")
    }

    // MARK: - Pipeline (needs Apple's on-device model)

    func testGlossesAreFetchedForLearningWordsInTheChapter() async throws {
        try XCTSkipUnless(
            AppleOnDevice.currentRoute(for: nil) == .appleOnDevice,
            "needs Apple's on-device model — absent on CI runners"
        )
        let document = try EPUBDocument(archive: ZIPArchive(data: Self.epub(chapter: """
        <p>At dusk the pineal gland releases melatonin, and the body prepares to sleep.</p>
        """)))
        let model = ReadingLoopModel()
        Self.retained.append(model)
        let learning = SavedWord(term: "melatonin", language: Language.storedTarget.rawValue)
        let mastered = SavedWord(term: "body", masteryLevel: .mastered, language: Language.storedTarget.rawValue)

        model.refreshGlosses(enabled: true, chapter: 0, document: document, savedWords: [learning, mastered])
        await model.waitForGlosses()

        XCTAssertNotNil(model.glosses["melatonin"], "\(model.glosses)")
        XCTAssertNil(model.glosses["body"], "mastered words get no gloss")
    }

    // MARK: - Helpers

    private func makeReader(html: String) async throws -> WKWebView {
        let manager = EPUBViewManager()
        Self.retained.append(manager)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                                configuration: EPUBReaderView.makeConfiguration(for: manager))
        Self.retained.append(webView)
        webView.loadHTMLString("<html><body>\(html)</body></html>", baseURL: nil)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            if !webView.isLoading,
               (try? await webView.evaluateJavaScript("document.readyState")) as? String == "complete" {
                return webView
            }
        }
        XCTFail("page never finished loading")
        return webView
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    private static func epub(chapter body: String) -> Data {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">urn:uuid:gloss</dc:identifier><dc:title>G</dc:title><dc:language>en</dc:language>
          </metadata>
          <manifest><item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """
        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body>\(body)</body></html>
        """
        return ZIPFixture.build([
            .init(path: "mimetype", data: Data("application/epub+zip".utf8), deflate: false),
            .init(path: "META-INF/container.xml", data: Data(container.utf8), deflate: true),
            .init(path: "OEBPS/content.opf", data: Data(opf.utf8), deflate: true),
            .init(path: "OEBPS/ch1.xhtml", data: Data(chapter.utf8), deflate: true),
        ])
    }
}
