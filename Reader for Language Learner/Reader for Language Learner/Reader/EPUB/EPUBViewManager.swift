//
//  EPUBViewManager.swift
//  Reader for Language Learner
//
//  Drives the EPUB reader: serves book resources through a custom URL
//  scheme (no temp-file extraction), tracks the current chapter and scroll
//  position, persists reading positions, and injects appearance CSS.
//  Counterpart of PDFViewManager for the EPUB world.
//

import Foundation
import Observation
import os
import SwiftUI
import WebKit

// MARK: - URL Scheme

enum EPUBScheme {
    static let scheme = "rell-epub"

    static func url(forArchivePath path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "book"
        components.path = "/" + path
        return components.url
    }

    static func archivePath(from url: URL) -> String {
        String(url.path.dropFirst())   // strip leading "/" — already percent-decoded
    }
}

// MARK: - Scheme Handler

/// Serves chapter XHTML and its resources (images, CSS, fonts) straight from
/// the ZIP archive. WebKit calls these on the main thread; the nonisolated
/// annotations satisfy the protocol, `assumeIsolated` recovers main-actor state.
final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {

    var document: EPUBDocument?

    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        MainActor.assumeIsolated {
            guard let url = urlSchemeTask.request.url,
                  let document
            else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }

            let path = EPUBScheme.archivePath(from: url)
            do {
                let resource = try document.resource(at: path)
                let response = URLResponse(
                    url: url,
                    mimeType: resource.mimeType,
                    expectedContentLength: resource.data.count,
                    textEncodingName: resource.mimeType.contains("xml") || resource.mimeType.hasPrefix("text")
                        ? "utf-8" : nil
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(resource.data)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Loads are synchronous slices from memory — nothing to cancel.
    }
}

// MARK: - Manager

@MainActor
@Observable
final class EPUBViewManager: NSObject {

    private(set) var document: EPUBDocument?
    private(set) var loadedURL: URL?
    private(set) var chapterIndex: Int = 0
    /// 0…1 scroll progress within the current chapter.
    private(set) var scrollFraction: Double = 0

    var chapterCount: Int { document?.chapterCount ?? 0 }
    var bookTitle: String? { document?.title }
    var tocEntries: [EPUBTOCEntry] { document?.tocEntries ?? [] }

    var canGoToPreviousChapter: Bool { document != nil && chapterIndex > 0 }
    var canGoToNextChapter: Bool { document != nil && chapterIndex < chapterCount - 1 }

    let schemeHandler = EPUBSchemeHandler()
    weak var webView: WKWebView?

    /// Appearance the next loaded chapter should adopt (set by the view).
    var currentTheme: PageTheme = .original
    var currentFontSize: Double = 18

    /// Live selection state fed by the injected JS bridge — mirrors what
    /// PDFKit's selection notifications provide on the PDF side.
    private(set) var lastSelectionText: String = ""
    private(set) var lastSelectionSentence: String?
    /// Pushes selection changes into the window's SelectionState.
    @ObservationIgnored var onSelectionChange: ((_ text: String, _ sentence: String?) -> Void)?

    @ObservationIgnored private var pendingScrollFraction: Double?
    @ObservationIgnored private var pendingFragment: String?
    @ObservationIgnored private var lastPositionSave = Date.distantPast
    /// Term to highlight once the next chapter finishes loading (search jump).
    @ObservationIgnored private var pendingFindTerm: String?

    // Hover dictionary — reuses the PDF side's popover UI and lookup flow.
    var hoverEnabled = true
    @ObservationIgnored var hoverCachedLookup: ((String) -> String?)?
    @ObservationIgnored var hoverLookup: ((String) async throws -> String)?
    @ObservationIgnored private var hoverPopover: NSPopover?
    @ObservationIgnored private let hoverModel = HoverLookupModel()
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var currentHoverTerm = ""

    // MARK: Lifecycle

    func load(url: URL) {
        guard loadedURL != url else { return }
        do {
            let parsed = try EPUBDocument(url: url)
            document = parsed
            schemeHandler.document = parsed
            loadedURL = url

            let saved = Self.savedPosition(for: positionKey(url))
            openChapter(at: min(saved.chapter, parsed.chapterCount - 1), scrollTo: saved.fraction)
        } catch {
            AppLogger.ui.error("EPUB open failed: \(error.localizedDescription, privacy: .public)")
            document = nil
            schemeHandler.document = nil
            loadedURL = nil
        }
    }

    func close() {
        savePositionNow()
        document = nil
        schemeHandler.document = nil
        loadedURL = nil
        chapterIndex = 0
        scrollFraction = 0
    }

    // MARK: Navigation

    func openChapter(at index: Int, scrollTo fraction: Double = 0, fragment: String? = nil) {
        guard let document,
              document.spinePaths.indices.contains(index),
              let url = EPUBScheme.url(forArchivePath: document.spinePaths[index])
        else { return }
        chapterIndex = index
        scrollFraction = fraction
        pendingScrollFraction = fraction
        pendingFragment = fragment
        webView?.load(URLRequest(url: url))
    }

    func nextChapter() {
        guard canGoToNextChapter else { return }
        openChapter(at: chapterIndex + 1)
    }

    func previousChapter() {
        guard canGoToPreviousChapter else { return }
        openChapter(at: chapterIndex - 1)
    }

    func open(tocEntry: EPUBTOCEntry) {
        guard let path = tocEntry.chapterPath,
              let index = document?.chapterIndex(forPath: path)
        else { return }
        if index == chapterIndex, let fragment = tocEntry.fragment {
            scroll(toFragment: fragment)
        } else {
            openChapter(at: index, fragment: tocEntry.fragment)
        }
    }

    // MARK: Appearance

    func applyAppearance(theme: PageTheme, fontSize: Double) {
        currentTheme = theme
        currentFontSize = fontSize
        webView?.evaluateJavaScript(Self.appearanceScript(theme: theme, fontSize: fontSize))
    }

    /// CSS pushed into every chapter. Layout basics are ours; for sepia and
    /// dark we must *override* publisher styling — most EPUBs set their own
    /// `body { background:#fff; color:#000 }` (often on descendant elements
    /// too), so the theme only takes effect when we force it with
    /// `!important` on both the surface and the text-bearing descendants.
    /// `.original` stays hands-off so a book's own colors show through.
    static func appearanceCSS(theme: PageTheme, fontSize: Double) -> String {
        let layout = """
        body {
            font-size: \(Int(fontSize))px;
            line-height: 1.6;
            max-width: 42em;
            margin: 0 auto;
            padding: 2.5em 2em 4em;
            -webkit-hyphens: auto;
        }
        img, svg { max-width: 100%; height: auto; }
        """

        guard theme != .original else {
            return layout + "\nhtml, body { background-color: #ffffff !important; }\n"
        }

        let colors: (background: String, text: String, link: String)
        switch theme {
        case .sepia: colors = ("#f4ecd8", "#5b4636", "#8a5a2b")
        case .dark:  colors = ("#1e1e1e", "#d8d8d8", "#7db4e6")
        case .original: colors = ("#ffffff", "#1d1d1f", "#0066cc")   // unreachable
        }

        // Force the surface, then cascade the text color down through every
        // text-bearing element (publisher CSS often colors <p>/<span> directly)
        // and strip element-level backgrounds (white callout boxes, etc.).
        // Uses explicit `body <el>` selectors (specificity 0,0,2) rather than
        // `:where()` (0,0,0) so we also win against the rare publisher rule
        // that marks a text color `!important`.
        let textElements = [
            "p", "div", "span", "li", "ul", "ol", "dl", "dt", "dd",
            "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "figure",
            "figcaption", "td", "th", "section", "article", "header",
            "footer", "em", "strong", "b", "i", "small", "sub", "sup",
            "code", "pre",
        ]
        let textSelector = textElements.map { "body \($0)" }.joined(separator: ", ")

        return layout + """

        html, body { background-color: \(colors.background) !important; }
        body { color: \(colors.text) !important; }
        \(textSelector) {
            color: inherit !important;
            background-color: transparent !important;
            border-color: currentColor !important;
        }
        body a, body a * {
            color: \(colors.link) !important;
            background-color: transparent !important;
        }
        """
    }

    private static func appearanceScript(theme: PageTheme, fontSize: Double) -> String {
        let css = appearanceCSS(theme: theme, fontSize: fontSize)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        (function() {
            var style = document.getElementById('rell-appearance');
            if (!style) {
                style = document.createElement('style');
                style.id = 'rell-appearance';
                document.documentElement.appendChild(style);
            }
            style.textContent = `\(css)`;
            // Large single-chapter books: defer offscreen image decoding.
            document.querySelectorAll('img').forEach(function(img) {
                img.loading = 'lazy';
            });
        })();
        """
    }

    // MARK: Scroll & Position

    func handleScrollMessage(fraction: Double) {
        scrollFraction = max(0, min(1, fraction))
        // Persist at most twice per second — scroll events are chatty.
        if Date().timeIntervalSince(lastPositionSave) > 0.5 {
            savePositionNow()
        }
    }

    func savePositionNow() {
        guard let loadedURL else { return }
        lastPositionSave = Date()
        Self.savePosition(
            chapter: chapterIndex,
            fraction: scrollFraction,
            for: positionKey(loadedURL)
        )
    }

    private func scroll(toFraction fraction: Double) {
        webView?.evaluateJavaScript(
            "window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * \(fraction));"
        )
    }

    private func scroll(toFragment fragment: String) {
        let escaped = fragment.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript(
            "document.getElementById('\(escaped)')?.scrollIntoView();"
        )
    }

    func handleSelectionMessage(text: String, sentence: String?) {
        lastSelectionText = text
        lastSelectionSentence = sentence?.isEmpty == true ? nil : sentence
        onSelectionChange?(text, lastSelectionSentence)
        // A deliberate selection supersedes a passive hover.
        if !text.isEmpty { closeHoverPopover() }
    }

    // MARK: Find in page

    /// Highlights the next/previous occurrence in the loaded chapter using
    /// WebKit's native find (Safari-style selection + scroll).
    func findInPage(_ term: String, forward: Bool = true) {
        guard let webView, !term.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(term, configuration: configuration) { _ in }
    }

    /// Opens a chapter and highlights `term` once it has loaded.
    func openChapter(at index: Int, thenFind term: String) {
        pendingFindTerm = term
        if index == chapterIndex {
            findInPage(term)
            pendingFindTerm = nil
        } else {
            openChapter(at: index)
        }
    }

    // MARK: Hover dictionary

    func handleHoverMessage(word: String, rect: CGRect) {
        guard hoverEnabled, let webView, document != nil else { return }
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (1...40).contains(term.count),
              term.contains(where: \.isLetter),
              !term.contains(where: \.isWhitespace)
        else {
            closeHoverPopover()
            return
        }
        if term.lowercased() == currentHoverTerm.lowercased(), hoverPopover?.isShown == true {
            return
        }
        currentHoverTerm = term

        hoverModel.term = term
        if let cached = hoverCachedLookup?(term) {
            hoverModel.phase = .loaded(cached)
        } else {
            hoverModel.phase = .loading
            startHoverLookup(term: term)
        }

        let popover: NSPopover
        if let existing = hoverPopover {
            popover = existing
            if popover.isShown { popover.close() }   // reposition to the new word
        } else {
            popover = NSPopover()
            popover.behavior = .semitransient
            popover.animates = false
            popover.contentViewController = NSHostingController(
                rootView: HoverDefinitionPopover(model: hoverModel)
            )
            hoverPopover = popover
        }
        // WKWebView is flipped, so JS viewport coordinates map straight
        // onto the view's coordinate space.
        let positioning = rect.width > 0 ? rect : CGRect(x: rect.minX, y: rect.minY, width: 1, height: 1)
        popover.show(relativeTo: positioning, of: webView, preferredEdge: .maxY)
    }

    private func startHoverLookup(term: String) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor [weak self] in
            guard let self, let lookup = self.hoverLookup else { return }
            do {
                let definition = try await lookup(term)
                guard !Task.isCancelled,
                      self.currentHoverTerm.lowercased() == term.lowercased() else { return }
                self.hoverModel.phase = .loaded(definition)
            } catch {
                guard !Task.isCancelled,
                      self.currentHoverTerm.lowercased() == term.lowercased() else { return }
                self.hoverModel.phase = .failed
            }
        }
    }

    func closeHoverPopover() {
        hoverTask?.cancel()
        currentHoverTerm = ""
        hoverPopover?.performClose(nil)
    }

    /// Called by the reader view when a chapter finishes loading.
    func chapterDidFinishLoading(url: URL?) {
        // Navigation clears any DOM selection — mirror that in app state.
        if !lastSelectionText.isEmpty {
            handleSelectionMessage(text: "", sentence: nil)
        }
        // A link inside the book may have navigated to another chapter —
        // keep the index in sync with what is actually on screen.
        if let url, url.scheme == EPUBScheme.scheme,
           let index = document?.chapterIndex(forPath: EPUBScheme.archivePath(from: url)) {
            chapterIndex = index
        }

        applyAppearance(theme: currentTheme, fontSize: currentFontSize)

        if let fragment = pendingFragment {
            pendingFragment = nil
            pendingScrollFraction = nil
            scroll(toFragment: fragment)
        } else if let term = pendingFindTerm {
            pendingFindTerm = nil
            pendingScrollFraction = nil
            findInPage(term)
        } else if let fraction = pendingScrollFraction, fraction > 0 {
            pendingScrollFraction = nil
            scroll(toFraction: fraction)
        } else {
            pendingScrollFraction = nil
        }
        savePositionNow()
    }

    // MARK: Reading-position persistence

    private static let positionsKey = "epubReadingPositions"

    private func positionKey(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func savedPosition(for key: String) -> (chapter: Int, fraction: Double) {
        guard let dict = UserDefaults.standard.dictionary(forKey: positionsKey),
              let entry = dict[key] as? [String: Double]
        else { return (0, 0) }
        return (Int(entry["chapter"] ?? 0), entry["fraction"] ?? 0)
    }

    private static func savePosition(chapter: Int, fraction: Double, for key: String) {
        var dict = UserDefaults.standard.dictionary(forKey: positionsKey) ?? [:]
        dict[key] = ["chapter": Double(chapter), "fraction": fraction]
        UserDefaults.standard.set(dict, forKey: positionsKey)
    }
}

// MARK: - WKNavigationDelegate

extension EPUBViewManager: WKNavigationDelegate {

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        MainActor.assumeIsolated {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Book-internal navigation stays in the web view; external links
            // open in the default browser.
            if url.scheme == EPUBScheme.scheme || url.scheme == "about" {
                decisionHandler(.allow)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            chapterDidFinishLoading(url: webView.url)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension EPUBViewManager: WKScriptMessageHandler {

    static let scrollMessageName = "rellScroll"
    static let selectionMessageName = "rellSelection"
    static let hoverMessageName = "rellHover"

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            switch message.name {
            case Self.scrollMessageName:
                if let fraction = message.body as? Double {
                    handleScrollMessage(fraction: fraction)
                }
            case Self.selectionMessageName:
                if let body = message.body as? [String: Any] {
                    handleSelectionMessage(
                        text: (body["text"] as? String) ?? "",
                        sentence: body["sentence"] as? String
                    )
                }
            case Self.hoverMessageName:
                if let body = message.body as? [String: Any] {
                    handleHoverMessage(
                        word: (body["word"] as? String) ?? "",
                        rect: CGRect(
                            x: (body["x"] as? Double) ?? 0,
                            y: (body["y"] as? Double) ?? 0,
                            width: (body["w"] as? Double) ?? 0,
                            height: (body["h"] as? Double) ?? 0
                        )
                    )
                }
            default:
                break
            }
        }
    }
}
