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

    /// Per-chapter content weights (character counts), computed once per book
    /// and memoized — the basis for content-weighted book progress (U3).
    @ObservationIgnored private var chapterWeightCache: [Int]?

    private func chapterWeights() -> [Int] {
        if let chapterWeightCache { return chapterWeightCache }
        guard let document else { return [] }
        let weights = (0..<document.chapterCount).map { max(1, document.plainText(at: $0).count) }
        chapterWeightCache = weights
        return weights
    }

    /// Fraction (0…1) through the entire book, weighted by chapter length —
    /// far more honest than "chapter N of M" for uneven chapters.
    var bookProgress: Double {
        ReadingProgressMath.bookProgress(
            weights: chapterWeights(),
            chapterIndex: chapterIndex,
            scrollFraction: scrollFraction
        )
    }

    /// Estimated minutes of reading left in the book.
    var minutesRemaining: Int {
        ReadingProgressMath.minutesRemaining(
            weights: chapterWeights(),
            chapterIndex: chapterIndex,
            scrollFraction: scrollFraction
        )
    }

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

    /// Supplies the lemma match keys of the same vocabulary, for the
    /// inflection-aware pass over the chapter (L-V1).
    @ObservationIgnored var savedWordKeysProvider: (() -> Set<String>)?

    /// Interlinear glosses (v13 S3): lowercased term → a short meaning drawn
    /// above the word. Empty while the feature is off.
    @ObservationIgnored private(set) var glosses: [String: String] = [:]
    /// Glossed terms that aren't saved words — the chapter warm-up — marked
    /// without the saved-word underline.
    @ObservationIgnored private(set) var glossOnlyTerms: [String] = []

    /// Replaces the glosses and re-marks the chapter when they changed.
    func setGlosses(_ glosses: [String: String], glossOnly: [String]) {
        guard glosses != self.glosses || glossOnly != glossOnlyTerms else { return }
        self.glosses = glosses
        self.glossOnlyTerms = glossOnly
        refreshHighlights()
    }

    /// Inflected shapes of saved words, per chapter — computed off-main, so
    /// the first render shows literal matches and the callback re-marks.
    @ObservationIgnored let inflectedTerms = InflectedTermService()

    @ObservationIgnored private var pendingScrollFraction: Double?
    @ObservationIgnored private var pendingFragment: String?
    @ObservationIgnored private var lastPositionSave = Date.distantPast
    /// Term to highlight once the next chapter finishes loading (search jump).
    @ObservationIgnored var pendingFindTerm: String?
    /// Highlight to scroll to once the next chapter finishes loading and its
    /// marks have been rendered.
    @ObservationIgnored var pendingHighlightScrollID: UUID?

    // Hover dictionary — reuses the PDF side's popover UI and lookup flow.
    var hoverEnabled = true
    @ObservationIgnored var hoverCachedLookup: ((String) -> HoverAnswer?)?
    @ObservationIgnored var hoverLookup: ((String) async throws -> HoverAnswer)?
    /// Whether a hovered word is in the notebook (any form of it).
    @ObservationIgnored var hoverIsSaved: ((String) -> Bool)?
    @ObservationIgnored lazy var hoverBalloon = HoverBalloon(model: hoverModel)
    /// Floating selection action bar hosted over the web view (U1).
    @ObservationIgnored private var selectionBarHost: NSHostingView<SelectionActionBar>?
    @ObservationIgnored let hoverModel = HoverLookupModel()
    @ObservationIgnored var hoverTask: Task<Void, Never>?
    @ObservationIgnored var currentHoverTerm = ""

    // `nonisolated(unsafe)`: written once in init, read only by deinit.
    @ObservationIgnored nonisolated(unsafe) private var highlightsChangedObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var savedWordAddedObserver: NSObjectProtocol?

    // MARK: Init

    override init() {
        super.init()
        // The store mutates outside SwiftUI's view-update path (a WKWebView
        // can't observe @Observable directly), so re-render on its broadcast —
        // mirrors PDFKitView.Coordinator's .pdfHighlightsChanged handling.
        highlightsChangedObserver = NotificationCenter.default.addObserver(
            forName: .epubHighlightsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshHighlights() }
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
            Task { @MainActor [weak self] in self?.refreshHighlights() }
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
            chapterWeightCache = nil   // recompute weights for the new book

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
        guard let document, document.spinePaths.indices.contains(index) else { return }
        // A split book's heading-only spine item is folded into the chapter
        // that follows it (the prose), so land there instead of on a page
        // showing nothing but "CHAPTER 1". Every entry point — the table of
        // contents, next/previous, restore — goes through here.
        let index = document.readableChapterIndex(for: index)
        guard let url = EPUBScheme.url(forArchivePath: document.spinePaths[index]) else { return }
        chapterIndex = index
        scrollFraction = fraction
        pendingScrollFraction = fraction
        pendingFragment = fragment
        // The selection (and its bar) doesn't survive a chapter swap.
        hideSelectionBar()
        webView?.load(URLRequest(url: url))
    }

    func nextChapter() {
        guard canGoToNextChapter else { return }
        openChapter(at: chapterIndex + 1)
    }

    func previousChapter() {
        guard canGoToPreviousChapter, let document else { return }
        // Step over the heading stub that belongs to the current chapter —
        // `openChapter` would otherwise fold it straight back to where we are.
        var target = chapterIndex - 1
        if target > 0, document.isHeadingStub(at: target) { target -= 1 }
        guard target >= 0 else { return }
        openChapter(at: target)
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
        // The reading column has to win outright. Calibre-produced books put a
        // class on <body> (`.calibre1 { margin: 0 5pt; padding-left: 0;
        // font-size: 1em }`), and a class selector beats our bare `body` rule —
        // which left those books pinned to the left edge at the wrong size, an
        // ugly surprise in zen mode especially. `!important` on the column
        // geometry is the same defence the theme colors below already use.
        let layout = """
        body {
            font-size: \(Int(typography.fontSize))px !important;
            line-height: \(String(format: "%.1f", typography.lineHeight)) !important;
            max-width: \(typography.widthEm)em !important;
            margin: 0 auto !important;
            padding: 2.5em 2em 4em !important;
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
        // The fragment comes from the book; JSON-encoding makes it a string
        // literal whatever it contains (quotes, backslashes, `</script>`).
        guard let literal = (try? JSONEncoder().encode(fragment)).flatMap({ String(data: $0, encoding: .utf8) })
        else { return }
        webView?.evaluateJavaScript(
            "document.getElementById(\(literal))?.scrollIntoView();"
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

    func handleSelectionMessage(text: String, sentence: String?, anchor: EPUBSelectionAnchor?, rect: CGRect = CGRect(x: -1, y: -1, width: 0, height: 0)) {
        lastSelectionText = text
        lastSelectionSentence = sentence?.isEmpty == true ? nil : sentence
        lastSelectionAnchor = anchor
        onSelectionChange?(text, lastSelectionSentence)
        // A deliberate selection supersedes a passive hover.
        if !text.isEmpty { closeHoverPopover() }
        updateSelectionBar(text: text, rect: rect)
    }

    // MARK: - Selection Action Bar (U1)

    /// Shows the floating action bar above the current selection, or hides it
    /// when the selection is empty / has no measurable rect.
    private func updateSelectionBar(text: String, rect: CGRect) {
        guard SelectionActionBar.isEnabled,
              let webView,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              rect.width > 0, rect.height > 0
        else {
            hideSelectionBar()
            return
        }

        let host: NSHostingView<SelectionActionBar>
        if let existing = selectionBarHost {
            host = existing
        } else {
            host = NSHostingView(rootView: makeSelectionBar())
            host.translatesAutoresizingMaskIntoConstraints = true
            webView.addSubview(host)
            selectionBarHost = host
        }
        host.rootView = makeSelectionBar()
        positionSelectionBar(host, over: rect, in: webView)
    }

    /// Scroll-driven update: keep the existing bar pinned, or hide it once the
    /// selection is gone / off-screen.
    func repositionSelectionBar(rect: CGRect) {
        guard let webView, let host = selectionBarHost else { return }
        guard rect.width > 0, rect.height > 0 else { hideSelectionBar(); return }
        positionSelectionBar(host, over: rect, in: webView)
    }

    private func positionSelectionBar(_ host: NSHostingView<SelectionActionBar>, over rect: CGRect, in webView: WKWebView) {
        let barSize = host.fittingSize
        let bounds = webView.bounds
        // WKWebView is flipped (top-left origin, y grows down), as the
        // placement rule expects.
        let originX = SelectionBarPlacement.originX(selectionMidX: rect.midX, barWidth: barSize.width,
                                                    visibleLeft: 0, visibleRight: bounds.width)
        let originY = SelectionBarPlacement.originY(selectionTop: rect.minY, selectionBottom: rect.maxY,
                                                    barHeight: barSize.height,
                                                    visibleTop: 0, visibleBottom: bounds.height)

        host.frame = CGRect(x: originX, y: originY, width: barSize.width, height: barSize.height)
    }

    private func hideSelectionBar() {
        selectionBarHost?.removeFromSuperview()
        selectionBarHost = nil
    }

    private func refreshSelectionBar() {
        selectionBarHost?.rootView = makeSelectionBar()
    }

    private func makeSelectionBar() -> SelectionActionBar {
        let term = lastSelectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Terms are scoped to the study language, so the bookmark reads
        // "have I saved this *as a word I'm studying*" — a homograph saved
        // under another language still offers Save.
        let isSaved = savedWordTermsProvider?()
            .contains { $0.caseInsensitiveCompare(term) == .orderedSame } ?? false
        return SelectionActionBar(
            onSave: { [weak self] in
                (self?.webView as? RELLEPUBWebView)?.onContextSaveWord?()
                self?.refreshSelectionBar()
            },
            onAnalyze: {
                NotificationCenter.default.post(name: .inspectorRunLastModule, object: nil)
            },
            onHighlight: { [weak self] color in
                (self?.webView as? RELLEPUBWebView)?.onContextHighlight?(color)
            },
            onSpeak: { [weak self] in
                (self?.webView as? RELLEPUBWebView)?.onContextSpeak?()
            },
            onCopy: { [weak self] in
                guard let self else { return }
                let text = self.lastSelectionText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            onSimplify: {
                NotificationCenter.default.post(name: .simplifySelectionCommand, object: term)
            },
            onRetell: {
                NotificationCenter.default.post(name: .retellSelectionCommand, object: term)
            },
            isPassage: GradedRewrite.isEligible(term),
            isSaved: isSaved,
            savesSentence: SavedWord.savesAsSentence(term),
            canRepeat: SpokenRepetition.isEligible(term)
                && SpokenRepetitionRecognizer.isOffered(for: Language.storedTarget),
            onRepeat: { NotificationCenter.default.post(name: .repeatAloudCommand, object: term) }
        )
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

    /// Where the reader left the book at `url` — the recap reads up to here.
    static func startPosition(for url: URL) -> (chapter: Int, fraction: Double) {
        savedPosition(for: url.deletingPathExtension().lastPathComponent)
    }

    /// Where the book at `url` opens next — the word page's jump to a
    /// chapter a word was met in, before the book's window exists.
    static func setStartPosition(chapter: Int, for url: URL) {
        savePosition(chapter: chapter, fraction: 0, for: url.deletingPathExtension().lastPathComponent)
    }

    private static func savePosition(chapter: Int, fraction: Double, for key: String) {
        var dict = UserDefaults.standard.dictionary(forKey: positionsKey) ?? [:]
        dict[key] = ["chapter": Double(chapter), "fraction": fraction]
        UserDefaults.standard.set(dict, forKey: positionsKey)
    }
}

