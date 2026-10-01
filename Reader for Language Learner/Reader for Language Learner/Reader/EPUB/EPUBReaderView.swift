//
//  EPUBReaderView.swift
//  Reader for Language Learner
//
//  WKWebView-backed EPUB reading surface. Content is served through the
//  rell-epub:// scheme directly from the archive; appearance (theme, font
//  size) is injected as CSS. A JS bridge reports text selections (with the
//  surrounding sentence) into SelectionState so the Inspector, word saving,
//  and the translation strip work exactly as they do for PDFs.
//

import SwiftUI
import os
import WebKit

// MARK: - Context-menu WebView

/// Adds the reader's right-click actions to WebKit's own menu when text is
/// selected — the EPUB counterpart of RELLPDFView's menu.
final class RELLEPUBWebView: WKWebView {

    var selectionProvider: (() -> String)?
    /// Current reading font size, mirrored from the appearance settings so a
    /// pinch has something to move (U-X3).
    var fontSize: Double = EPUBTypography.defaultFontSize
    /// Reports a pinch-driven font size back to the appearance settings.
    var onFontSizeChange: ((Double) -> Void)?
    /// Two-finger horizontal swipe, +1 for the next chapter, -1 for the
    /// previous one (U-X4).
    var onSwipeChapter: ((Int) -> Void)?
    var onContextSaveWord: (() -> Void)?
    var onContextLookUp:   (() -> Void)?
    var onContextAnalyze:  ((ModuleType) -> Void)?
    var onContextHighlight: ((HighlightColor) -> Void)?
    var onContextSpeak:    (() -> Void)?

    // MARK: - Gestures

    /// Pinch changes the reading font size rather than scaling the page
    /// (U-X3). v1.30 gave EPUBs WKWebView's native magnification; scaling a
    /// reflowable document blurs it and leaves the column at the wrong
    /// measure, while the same gesture on the font size is what the reader
    /// actually meant. `allowsMagnification` is off, so nothing else handles
    /// this and `super` is deliberately not called.
    private var pinchSizer = PinchFontSizer()

    override func magnify(with event: NSEvent) {
        switch event.phase {
        case .changed:
            guard let next = pinchSizer.size(after: event.magnification, from: fontSize) else { return }
            fontSize = next
            onFontSizeChange?(next)
        default:
            pinchSizer.reset()
        }
    }

    /// Two-finger horizontal swipe turns the chapter (U-X4).
    ///
    /// Reading `scrollFraction` instead would mean waiting on a 250ms
    /// throttle — far too coarse to feel like a gesture. The reading column
    /// never overflows horizontally, so a dominantly horizontal scroll has no
    /// other meaning here and is safe to consume.
    private var swipeDetector = SwipeChapterDetector()

    override func scrollWheel(with event: NSEvent) {
        // A gesture that already turned a chapter must not turn another one
        // as its momentum decays.
        if swipeDetector.hasFired, event.momentumPhase != [] { return }

        switch event.phase {
        case .began:
            swipeDetector.reset()
        case .changed:
            if let direction = swipeDetector.direction(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            ) {
                onSwipeChapter?(direction)
                return
            }
        default:
            break
        }
        super.scrollWheel(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // Reader surface, not a browser.
        menu.items.removeAll {
            $0.identifier?.rawValue == "WKMenuItemIdentifierReload"
        }

        let selection = (selectionProvider?() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return }

        // Same lines, same order as the PDF reader and the selection bar;
        // WebKit's own items (Copy, Look Up, Share) stay below.
        let actions = SelectionMenu.Actions(
            save: { [weak self] in self?.onContextSaveWord?() },
            analyze: { [weak self] in self?.onContextLookUp?() },
            analyzeWith: { [weak self] module in self?.onContextAnalyze?(module) },
            highlight: { [weak self] color in self?.onContextHighlight?(color) },
            speak: { [weak self] in self?.onContextSpeak?() }
        )
        var items = SelectionMenu.items(for: selection, actions: actions)
        items.append(.separator())
        menu.items.insert(contentsOf: items, at: 0)
    }
}

// MARK: - Reader View

struct EPUBReaderView: NSViewRepresentable {

    let documentURL: URL?
    var manager: EPUBViewManager
    var pageTheme: PageTheme
    var typography: EPUBTypography
    @Binding var selectedText: String
    @Binding var contextSentence: String?
    var savedWordsStore: SavedWordsStore
    var quickLookup: QuickLookupService
    var epubHighlightStore: EPUBHighlightStore
    var toastCenter: ToastCenter
    var hoverEnabled: Bool
    /// Where a pinch-driven font size goes (U-X3). The preference belongs to
    /// the view that owns it — the same `@AppStorage` the appearance panel and
    /// the zoom menu items write, so all three stay in step and the size
    /// persists the same way however it was changed.
    var onFontSizeChange: (Double) -> Void

    /// The reader's web view configuration. The book's own JavaScript is
    /// switched off (`allowsContentJavaScript = false`): a book could
    /// otherwise navigate to any URL scheme without a click, or post fake
    /// `rellSelection` messages. RELL's user scripts and `evaluateJavaScript`
    /// calls are the app's, not the page's, and keep running.
    static func makeConfiguration(for manager: EPUBViewManager) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(manager.schemeHandler, forURLScheme: EPUBScheme.scheme)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let controller = configuration.userContentController
        // highlightScript must precede selectionScript: the latter calls
        // the anchor-computation function the former defines.
        controller.addUserScript(Self.highlightScript)
        controller.addUserScript(Self.scrollScript)
        controller.addUserScript(Self.selectionScript)
        controller.addUserScript(Self.hoverScript)
        controller.addUserScript(Self.karaokeScript)
        controller.add(manager, name: EPUBViewManager.scrollMessageName)
        controller.add(manager, name: EPUBViewManager.selectionMessageName)
        controller.add(manager, name: EPUBViewManager.hoverMessageName)
        return configuration
    }

    func makeNSView(context: Context) -> RELLEPUBWebView {
        let configuration = Self.makeConfiguration(for: manager)

        let webView = RELLEPUBWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = manager
        // Pinch is handled as a font-size gesture instead of native page
        // magnification — see `magnify(with:)` (U-X3, replacing v1.30's U4).
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")   // theme CSS paints it

        manager.webView = webView
        manager.currentTheme = pageTheme
        manager.currentTypography = typography

        wireCallbacks(webView)

        if let documentURL {
            manager.load(url: documentURL)
        }
        return webView
    }

    func updateNSView(_ webView: RELLEPUBWebView, context: Context) {
        wireCallbacks(webView)

        if let documentURL, manager.loadedURL != documentURL {
            manager.currentTheme = pageTheme
            manager.currentTypography = typography
            manager.load(url: documentURL)
        } else if manager.currentTheme != pageTheme || manager.currentTypography != typography {
            manager.applyAppearance(theme: pageTheme, typography: typography)
        }
    }

    static func dismantleNSView(_ webView: RELLEPUBWebView, coordinator: ()) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: EPUBViewManager.scrollMessageName)
        controller.removeScriptMessageHandler(forName: EPUBViewManager.selectionMessageName)
        controller.removeScriptMessageHandler(forName: EPUBViewManager.hoverMessageName)
    }

    // MARK: Wiring

    private func wireCallbacks(_ webView: RELLEPUBWebView) {
        let selectedText = $selectedText

        // Gestures (U-X3, U-X4). The size is pushed in rather than read out,
        // so a change from the appearance panel moves the pinch's starting
        // point too.
        webView.fontSize = typography.fontSize
        webView.onFontSizeChange = onFontSizeChange
        webView.onSwipeChapter = { [weak manager] direction in
            if direction > 0 { manager?.nextChapter() } else { manager?.previousChapter() }
        }
        let contextSentence = $contextSentence

        manager.hoverEnabled = hoverEnabled
        let quickLookup = self.quickLookup
        let savedWords = self.savedWordsStore
        manager.hoverCachedLookup = { term in
            quickLookup.cachedHoverDefinition(for: term, savedWordsStore: savedWords)
        }
        manager.hoverLookup = { term in
            try await quickLookup.hoverDefinition(for: term)
        }

        manager.onSelectionChange = { text, sentence in
            if selectedText.wrappedValue != text {
                selectedText.wrappedValue = text
            }
            if contextSentence.wrappedValue != sentence {
                contextSentence.wrappedValue = sentence
            }
        }

        let manager = self.manager
        let store = self.savedWordsStore
        let highlightStore = self.epubHighlightStore
        let toastCenter = self.toastCenter

        manager.highlightsProvider = { [weak manager] chapterPath in
            guard let bookFilename = manager?.loadedURL?.deletingPathExtension().lastPathComponent
            else { return [] }
            return highlightStore.highlights(for: bookFilename, chapterPath: chapterPath)
        }

        // Scoped to the study language — an English book shouldn't underline
        // the German words in the same library, and the 500-term chapter cap
        // now spends its budget on terms that can actually appear.
        manager.savedWordTermsProvider = {
            store.terms(for: Language.storedTarget)
        }
        manager.savedWordKeysProvider = {
            store.lemmaKeys(for: Language.storedTarget)
        }

        webView.selectionProvider = { [weak manager] in
            manager?.lastSelectionText ?? ""
        }
        webView.onContextSaveWord = { [weak manager] in
            guard let manager else { return }
            let term = manager.lastSelectionText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return }
            store.add(SavedWord(
                term: term,
                sentence: manager.lastSelectionSentence ?? "",
                pdfFilename: manager.loadedURL?.deletingPathExtension().lastPathComponent,
                pageNumber: manager.chapterIndex + 1,
                mode: "word",
                domain: "general",
                llmOutputs: [:],
                language: Language.storedTarget.rawValue
            ))
            toastCenter.show(String(localized: "Word saved!"))
        }
        webView.onContextLookUp = {
            NotificationCenter.default.post(name: .inspectorRunLastModule, object: nil)
        }
        webView.onContextHighlight = { [weak manager] color in
            guard let manager, let anchor = manager.lastSelectionAnchor,
                  let document = manager.document,
                  let bookFilename = manager.loadedURL?.deletingPathExtension().lastPathComponent,
                  let chapterPath = try? document.chapterPath(at: manager.chapterIndex)
            else { return }
            highlightStore.add(EPUBHighlight(
                epubFilename: bookFilename,
                chapterIndex: manager.chapterIndex,
                chapterPath: chapterPath,
                quote: anchor.quote,
                prefix: anchor.prefix,
                suffix: anchor.suffix,
                startOffset: anchor.startOffset,
                colorRaw: color.rawValue
            ))
        }
        webView.onContextAnalyze = { module in
            NotificationCenter.default.post(name: .inspectorRunModule, object: module.rawValue)
        }
        webView.onContextSpeak = { [weak manager] in
            guard let manager else { return }
            let text = manager.lastSelectionText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            SpeechManager.shared.speakResolved(text)
        }
    }

    // MARK: Injected scripts

    /// Reads one of the reader's scripts from the app bundle
    /// (`Reader/EPUB/Scripts/*.js`, moved out of this file in v14 Sprint 0 —
    /// byte for byte what the Swift literals produced at runtime).
    static func bundledScript(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            AppLogger.ui.error("Reader script \(name, privacy: .public).js is missing from the app bundle")
            assertionFailure("missing \(name).js")
            return ""
        }
        return source
    }

    /// Defines the shared text-offset walk plus anchor/render/unwrap
    /// functions used both to capture a new highlight's anchor (in
    /// selectionScript) and to re-render marks from the store (called by
    /// Swift via `evaluateJavaScript`). Wrapping/unwrapping a `<mark>`
    /// never changes character counts — only node boundaries — so absolute
    /// text offsets stay valid across repeated re-renders and reflow
    /// (font-size change, window resize).
    private static let highlightScript = WKUserScript(
        source: bundledScript("rell-highlight"),
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    /// Throttled scroll reporting for reading-position persistence.
    private static let scrollScript = WKUserScript(
        source: bundledScript("rell-scroll"),
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    /// Hover dictionary bridge: after the pointer rests for 500 ms over a
    /// word (and nothing is selected), report the word + its viewport rect.
    /// An empty word means "hover ended" and closes the popover.
    private static let hoverScript = WKUserScript(
        source: bundledScript("rell-hover"),
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    /// Selection bridge: debounced selectionchange → { text, sentence }.
    /// The sentence is cut from the enclosing block's text at sentence
    /// punctuation — the web counterpart of the PDF side's NLTokenizer pass.
    private static let selectionScript = WKUserScript(
        source: bundledScript("rell-selection"),
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    /// Karaoke: highlights the sentence currently being spoken and keeps it in
    /// view. Uses the CSS Custom Highlight API rather than wrapping the text in
    /// a `<mark>`, so the DOM is never mutated — user highlights, saved-word
    /// marks, and the offset anchors they resolve against all stay intact.
    /// Returns false (and highlights nothing) when the sentence isn't found,
    /// which is the agreed "silently skip" behaviour.
    static let karaokeScript = WKUserScript(
        source: bundledScript("rell-karaoke"),
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )
}
