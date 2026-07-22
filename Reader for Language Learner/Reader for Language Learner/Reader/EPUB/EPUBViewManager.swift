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

// MARK: - Selection Anchor

/// Text-quote selector for a live selection — mirrors the W3C Web
/// Annotation model closely enough for our purposes: enough context to
/// re-find the same text after a chapter reload, independent of any fixed
/// geometry (EPUB has none).
struct EPUBSelectionAnchor: Equatable {
    let quote: String
    let prefix: String
    let suffix: String
    let startOffset: Int
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
    var currentTypography = EPUBTypography()

    /// Live selection state fed by the injected JS bridge — mirrors what
    /// PDFKit's selection notifications provide on the PDF side.
    private(set) var lastSelectionText: String = ""
    private(set) var lastSelectionSentence: String?
    /// Text-quote anchor for the live selection, computed in JS at the same
    /// time as the sentence — consumed when the user picks a highlight color.
    private(set) var lastSelectionAnchor: EPUBSelectionAnchor?
    /// Pushes selection changes into the window's SelectionState.
    @ObservationIgnored var onSelectionChange: ((_ text: String, _ sentence: String?) -> Void)?

    /// Supplies the highlights to render for a given chapter archive path —
    /// set by the reader view, which owns the store reference.
    @ObservationIgnored var highlightsProvider: ((_ chapterPath: String) -> [EPUBHighlight])?

    /// Supplies the current book's saved-word terms — set by the reader
    /// view, which owns the store reference. Mirrors `highlightsProvider`.
    @ObservationIgnored var savedWordTermsProvider: (() -> [String])?

    @ObservationIgnored private var pendingScrollFraction: Double?
    @ObservationIgnored private var pendingFragment: String?
    @ObservationIgnored private var lastPositionSave = Date.distantPast
    /// Term to highlight once the next chapter finishes loading (search jump).
    @ObservationIgnored private var pendingFindTerm: String?
    /// Highlight to scroll to once the next chapter finishes loading and its
    /// marks have been rendered.
    @ObservationIgnored private var pendingHighlightScrollID: UUID?

    // Hover dictionary — reuses the PDF side's popover UI and lookup flow.
    var hoverEnabled = true
    @ObservationIgnored var hoverCachedLookup: ((String) -> String?)?
    @ObservationIgnored var hoverLookup: ((String) async throws -> String)?
    @ObservationIgnored private var hoverPopover: NSPopover?
    @ObservationIgnored private let hoverModel = HoverLookupModel()
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var currentHoverTerm = ""

    @ObservationIgnored private var highlightsChangedObserver: NSObjectProtocol?
    @ObservationIgnored private var savedWordAddedObserver: NSObjectProtocol?

    // MARK: Init

    override init() {
        super.init()
        // The store mutates outside SwiftUI's view-update path (a WKWebView
        // can't observe @Observable directly), so re-render on its broadcast —
        // mirrors PDFKitView.Coordinator's .pdfHighlightsChanged handling.
        highlightsChangedObserver = NotificationCenter.default.addObserver(
            forName: .epubHighlightsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshHighlights() }
        }
        // A newly-saved word should pick up its underline mark without
        // waiting for the next chapter turn. Removal isn't observed the
        // same way — it settles at the next natural refresh (chapter
        // navigation, theme change, or another save), matching PDF's own
        // scroll-tick-driven word-count check rather than adding a
        // dedicated "removed" broadcast for a much rarer interaction.
        savedWordAddedObserver = NotificationCenter.default.addObserver(
            forName: .savedWordAdded, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshHighlights() }
        }
    }

    deinit {
        if let highlightsChangedObserver {
            NotificationCenter.default.removeObserver(highlightsChangedObserver)
        }
        if let savedWordAddedObserver {
            NotificationCenter.default.removeObserver(savedWordAddedObserver)
        }
    }

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

    func applyAppearance(theme: PageTheme, typography: EPUBTypography) {
        let themeChanged = currentTheme != theme
        currentTheme = theme
        currentTypography = typography
        webView?.evaluateJavaScript(Self.appearanceScript(theme: theme, typography: typography))
        // Highlight ink is baked into each <mark>'s inline style at render
        // time, so a theme switch has to re-wrap the marks with the new ink.
        if themeChanged { refreshHighlights() }
    }

    /// Ink color for highlighted text, per page theme. Light themes get
    /// dark "physical highlighter" ink; dark surfaces keep their own light
    /// text — dark ink over a translucent mark on a dark page is unreadable.
    static func highlightInk(for theme: PageTheme) -> String {
        theme.usesLightInk ? "#e8e8e8" : "#1d1d1f"
    }

    /// CSS pushed into every chapter. Layout basics are ours; for tinted
    /// themes we must *override* publisher styling — most EPUBs set their own
    /// `body { background:#fff; color:#000 }` (often on descendant elements
    /// too), so the theme only takes effect when we force it with
    /// `!important` on both the surface and the text-bearing descendants.
    /// `.original` stays hands-off so a book's own colors show through.
    static func appearanceCSS(theme: PageTheme, typography: EPUBTypography) -> String {
        // Font override cascades through the same text-bearing elements as
        // the theme colors — publisher CSS often sets font-family on <p>
        // directly, so body alone wouldn't win.
        let fontRule = typography.fontFamilyCSS.map {
            "body, \(Self.textSelector) { font-family: \($0) !important; }\n"
        } ?? ""
        let justifyRule = typography.justified
            ? "body p { text-align: justify; }\n"
            : ""
        // Line height needs the descendant cascade too, or publisher
        // paragraph rules keep their own tighter leading.
        let layout = """
        body {
            font-size: \(Int(typography.fontSize))px;
            line-height: \(String(format: "%.1f", typography.lineHeight));
            max-width: \(typography.widthEm)em;
            margin: 0 auto;
            padding: 2.5em 2em 4em;
            -webkit-hyphens: auto;
        }
        body p, body li, body blockquote {
            line-height: \(String(format: "%.1f", typography.lineHeight)) !important;
        }
        \(fontRule)\(justifyRule)img, svg { max-width: 100%; height: auto; }
        """

        guard let colors = theme.epubColors else {
            return layout + "\nhtml, body { background-color: #ffffff !important; }\n"
        }

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

    /// Explicit `body <el>` selectors (specificity 0,0,2) rather than
    /// `:where()` (0,0,0) so we also win against the rare publisher rule
    /// that marks a text color `!important`. Shared by the theme-color and
    /// font-family cascades.
    private static let textSelector: String = {
        let textElements = [
            "p", "div", "span", "li", "ul", "ol", "dl", "dt", "dd",
            "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "figure",
            "figcaption", "td", "th", "section", "article", "header",
            "footer", "em", "strong", "b", "i", "small", "sub", "sup",
            "code", "pre",
        ]
        return textElements.map { "body \($0)" }.joined(separator: ", ")
    }()

    private static func appearanceScript(theme: PageTheme, typography: EPUBTypography) -> String {
        let css = appearanceCSS(theme: theme, typography: typography)
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

    /// First visible line of text in the viewport — the display label for a
    /// bookmark created at the current position. Falls back to "" when the
    /// probe finds nothing (image-only view, JS failure).
    func visibleSnippet() async -> String {
        guard let webView else { return "" }
        let script = """
        (function() {
            var x = Math.floor(window.innerWidth / 2);
            for (var y = 8; y < window.innerHeight; y += 24) {
                var range = document.caretRangeFromPoint(x, y);
                if (!range || !range.startContainer) { continue; }
                var node = range.startContainer;
                if (node.nodeType !== Node.TEXT_NODE) { continue; }
                var text = node.textContent.substring(range.startOffset).trim();
                if (text.length < 3) { text = node.textContent.trim(); }
                // The caret usually lands mid-word — drop the partial word
                // so the label starts on a word boundary.
                if (range.startOffset > 0 && /\\S/.test(node.textContent.charAt(range.startOffset - 1))) {
                    text = text.replace(/^\\S+\\s+/, '');
                }
                if (text.length >= 3) { return text.substring(0, 120); }
            }
            return '';
        })();
        """
        let result = try? await webView.evaluateJavaScript(script)
        return (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Plain text of the current chapter, for "Read Chapter Aloud". Chapter
    /// scope (not full-book) matches how EPUB navigation already works here.
    func currentChapterPlainText() async -> String {
        guard let webView else { return "" }
        let result = try? await webView.evaluateJavaScript("document.body.innerText")
        return (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func handleSelectionMessage(text: String, sentence: String?, anchor: EPUBSelectionAnchor?) {
        lastSelectionText = text
        lastSelectionSentence = sentence?.isEmpty == true ? nil : sentence
        lastSelectionAnchor = anchor
        onSelectionChange?(text, lastSelectionSentence)
        // A deliberate selection supersedes a passive hover.
        if !text.isEmpty { closeHoverPopover() }
    }

    // MARK: Highlights

    /// Re-renders this chapter's highlight marks and saved-word underlines
    /// from current store contents. Safe to call repeatedly — the JS side
    /// clears old marks before re-wrapping. Saved-word marks are applied
    /// *after* highlights: highlight anchors must resolve against a
    /// pristine, unwrapped DOM (see `rellRenderHighlights`), and running
    /// them second here keeps that guarantee regardless of call order.
    func refreshHighlights() {
        guard let webView, let document,
              document.spinePaths.indices.contains(chapterIndex)
        else { return }

        if let highlightsProvider {
            let chapterPath = document.spinePaths[chapterIndex]
            let entries = highlightsProvider(chapterPath)
            webView.evaluateJavaScript(Self.renderHighlightsScript(for: entries, ink: Self.highlightInk(for: currentTheme)))
        }

        if let savedWordTermsProvider {
            let terms = savedWordTermsProvider()
            webView.evaluateJavaScript(Self.markSavedWordsScript(for: terms, color: Self.savedWordMarkColor(for: currentTheme)))
        }
    }

    /// Dotted-underline tint for saved-word marks — visually distinct from
    /// a user highlight's filled background, and readable against all six
    /// page themes without one fixed color's contrast breaking on the dark
    /// ones.
    static func savedWordMarkColor(for theme: PageTheme) -> String {
        theme.usesLightInk ? "rgba(150, 179, 255, 0.75)" : "rgba(51, 92, 209, 0.65)"
    }

    private static func markSavedWordsScript(for terms: [String], color: String) -> String {
        let capped = Array(terms.prefix(500))
        let json = (try? JSONEncoder().encode(capped)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "window.rellMarkSavedWords(\(json), '\(color)');"
    }

    private static func renderHighlightsScript(for highlights: [EPUBHighlight], ink: String) -> String {
        struct Entry: Encodable {
            let id: String
            let quote: String
            let prefix: String
            let suffix: String
            let startOffset: Int
            let color: String
        }
        let entries = highlights.map {
            Entry(
                id: $0.id.uuidString, quote: $0.quote, prefix: $0.prefix,
                suffix: $0.suffix, startOffset: $0.startOffset, color: $0.color.webBackground
            )
        }
        let json = (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "window.rellRenderHighlights(\(json), '\(ink)');"
    }

    /// Opens a chapter and scrolls to a highlight's mark once it renders.
    func openChapter(at index: Int, thenScrollToHighlight id: UUID) {
        pendingHighlightScrollID = id
        if index == chapterIndex {
            refreshHighlights()
            scrollToHighlight(id)
            pendingHighlightScrollID = nil
        } else {
            openChapter(at: index)
        }
    }

    private func scrollToHighlight(_ id: UUID) {
        webView?.evaluateJavaScript(
            "document.querySelector('mark[data-rell-highlight-id=\"\(id.uuidString)\"]')" +
            "?.scrollIntoView({block: 'center'});"
        )
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
            handleSelectionMessage(text: "", sentence: nil, anchor: nil)
        }
        // A link inside the book may have navigated to another chapter —
        // keep the index in sync with what is actually on screen.
        if let url, url.scheme == EPUBScheme.scheme,
           let index = document?.chapterIndex(forPath: EPUBScheme.archivePath(from: url)) {
            chapterIndex = index
        }

        applyAppearance(theme: currentTheme, typography: currentTypography)
        refreshHighlights()

        if let fragment = pendingFragment {
            pendingFragment = nil
            pendingScrollFraction = nil
            scroll(toFragment: fragment)
        } else if let term = pendingFindTerm {
            pendingFindTerm = nil
            pendingScrollFraction = nil
            findInPage(term)
        } else if let highlightID = pendingHighlightScrollID {
            pendingHighlightScrollID = nil
            pendingScrollFraction = nil
            scrollToHighlight(highlightID)
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
                    let text = (body["text"] as? String) ?? ""
                    var anchor: EPUBSelectionAnchor?
                    if !text.isEmpty,
                       let quote = body["quote"] as? String, !quote.isEmpty,
                       let startOffset = body["startOffset"] as? Int {
                        anchor = EPUBSelectionAnchor(
                            quote: quote,
                            prefix: (body["prefix"] as? String) ?? "",
                            suffix: (body["suffix"] as? String) ?? "",
                            startOffset: startOffset
                        )
                    }
                    handleSelectionMessage(
                        text: text,
                        sentence: body["sentence"] as? String,
                        anchor: anchor
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
