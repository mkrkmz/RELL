//
//  EPUBSecurityTests.swift
//  Reader for Language LearnerTests
//
//  v1.39: a book's own JavaScript doesn't run, a link leaves the app only
//  when clicked and only for web/mail, and a ZIP entry can't claim gigabytes.
//

import WebKit
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EPUBSecurityTests: XCTestCase {
    private static var retained: [AnyObject] = []

    // MARK: Link policy

    func testBookInternalLinksLoadInPlace() async throws {
        let chapterLink = try XCTUnwrap(URL(string: "rell-epub://book/OEBPS/ch2.xhtml#note3"))
        XCTAssertEqual(EPUBLinkPolicy.decision(for: chapterLink, userClicked: false), .allow)
        XCTAssertEqual(EPUBLinkPolicy.decision(for: URL(string: "about:blank"), userClicked: false), .allow)
    }

    func testClickedWebAndMailLinksOpenExternally() async throws {
        for string in ["https://example.com", "http://example.com/a", "mailto:author@example.com"] {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertEqual(EPUBLinkPolicy.decision(for: url, userClicked: true), .openExternally(url), string)
        }
    }

    /// Before v1.39 every one of these was handed to `NSWorkspace.open`,
    /// click or no click — a book could launch an app from a script or a
    /// meta refresh.
    func testEverythingElseIsBlocked() async throws {
        XCTAssertEqual(EPUBLinkPolicy.decision(for: URL(string: "https://example.com"), userClicked: false), .block)
        for string in [
            "file:///System/Applications/Calculator.app",
            "x-apple.systempreferences:com.apple.preference.security",
            "someapp://do-something",
            "javascript:alert(1)",
        ] {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertEqual(EPUBLinkPolicy.decision(for: url, userClicked: true), .block, string)
        }
        XCTAssertEqual(EPUBLinkPolicy.decision(for: nil, userClicked: true), .block)
    }

    // MARK: ZIP

    func testEntryClaimingAHugeSizeIsRejected() async throws {
        var data = ZIPFixture.build([.init(path: "OEBPS/ch1.xhtml", data: Data("hi".utf8), deflate: false)])
        // Patch the central directory's "uncompressed size" to 300 MB.
        let signature = Data([0x50, 0x4B, 0x01, 0x02])
        let record = try XCTUnwrap(data.range(of: signature)).lowerBound
        let size = UInt32(300 * 1_048_576)
        for byte in 0..<4 {
            data[record + 24 + byte] = UInt8((size >> (8 * UInt32(byte))) & 0xFF)
        }

        XCTAssertThrowsError(try ZIPArchive(data: data))
    }

    // MARK: JavaScript

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    private func load(_ html: String, in webView: WKWebView) async throws {
        webView.loadHTMLString(html, baseURL: nil)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            if !webView.isLoading,
               (try? await evaluate("document.readyState", in: webView)) as? String == "complete" {
                return
            }
        }
        XCTFail("page never finished loading")
    }

    func testBookScriptsDoNotRunButReaderScriptsDo() async throws {
        let manager = EPUBViewManager()
        Self.retained.append(manager)
        let webView = WKWebView(frame: .zero, configuration: EPUBReaderView.makeConfiguration(for: manager))
        Self.retained.append(webView)

        try await load("""
        <html><head><title>untouched</title></head>
        <body onload="document.title = 'onload ran'">
        <p>Text</p>
        <script>document.title = 'book script ran';</script>
        </body></html>
        """, in: webView)

        let title = try await evaluate("document.title", in: webView) as? String
        XCTAssertEqual(title, "untouched", "the book's script and inline handler must not run")
        let readerFunction = try await evaluate("typeof window.rellMarkSavedWords", in: webView) as? String
        XCTAssertEqual(readerFunction, "function", "RELL's own user scripts keep working")

        // Listeners RELL registers (scroll, selection, hover) still fire, and
        // the message bridge they post through is still there.
        let listenerFired = try await evaluate("""
        (function() {
            var hit = false;
            document.addEventListener('rell-probe', function() { hit = true; });
            document.dispatchEvent(new Event('rell-probe'));
            return hit && typeof window.webkit.messageHandlers.rellSelection.postMessage === 'function';
        })()
        """, in: webView) as? Bool
        XCTAssertEqual(listenerFired, true)
    }
}
