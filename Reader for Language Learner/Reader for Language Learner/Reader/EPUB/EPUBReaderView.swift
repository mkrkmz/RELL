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
import WebKit

// MARK: - Context-menu WebView

/// Adds the reader's right-click actions to WebKit's own menu when text is
/// selected — the EPUB counterpart of RELLPDFView's menu.
final class RELLEPUBWebView: WKWebView {

    var selectionProvider: (() -> String)?
    var onContextSaveWord: (() -> Void)?
    var onContextLookUp:   (() -> Void)?
    var onContextAnalyze:  ((ModuleType) -> Void)?
    var onContextSpeak:    (() -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // Reader surface, not a browser.
        menu.items.removeAll {
            $0.identifier?.rawValue == "WKMenuItemIdentifierReload"
        }

        let selection = (selectionProvider?() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return }

        let preview = selection.count > 40 ? String(selection.prefix(40)) + "…" : selection
        var items: [NSMenuItem] = []

        let saveItem = NSMenuItem(
            title: String(localized: "Save \(preview)"),
            action: #selector(fireSaveWord),
            keyEquivalent: ""
        )
        saveItem.target = self
        items.append(saveItem)

        let lookUpItem = NSMenuItem(
            title: String(localized: "Look Up in Inspector"),
            action: #selector(fireLookUp),
            keyEquivalent: ""
        )
        lookUpItem.target = self
        items.append(lookUpItem)

        let analyzeItem = NSMenuItem(title: String(localized: "Analyze With"), action: nil, keyEquivalent: "")
        let analyzeSubmenu = NSMenu()
        analyzeSubmenu.autoenablesItems = false
        for module in ModuleType.menuOrder {
            let item = NSMenuItem(
                title: module.title,
                action: #selector(fireAnalyze(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = true
            item.representedObject = module.rawValue
            item.image = NSImage(systemSymbolName: module.iconName, accessibilityDescription: module.title)
            analyzeSubmenu.addItem(item)
        }
        analyzeItem.submenu = analyzeSubmenu
        items.append(analyzeItem)

        let speakItem = NSMenuItem(
            title: String(localized: "Speak"),
            action: #selector(fireSpeak),
            keyEquivalent: ""
        )
        speakItem.target = self
        items.append(speakItem)

        items.append(.separator())
        menu.items.insert(contentsOf: items, at: 0)
    }

    @objc private func fireSaveWord() { onContextSaveWord?() }
    @objc private func fireLookUp()   { onContextLookUp?()   }
    @objc private func fireSpeak()    { onContextSpeak?()    }

    @objc private func fireAnalyze(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let module = ModuleType(rawValue: raw) else { return }
        onContextAnalyze?(module)
    }
}

// MARK: - Reader View

struct EPUBReaderView: NSViewRepresentable {

    let documentURL: URL?
    var manager: EPUBViewManager
    var pageTheme: PageTheme
    var fontSize: Double
    @Binding var selectedText: String
    @Binding var contextSentence: String?
    var savedWordsStore: SavedWordsStore
    var quickLookup: QuickLookupService
    var hoverEnabled: Bool

    func makeNSView(context: Context) -> RELLEPUBWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(manager.schemeHandler, forURLScheme: EPUBScheme.scheme)

        let controller = configuration.userContentController
        controller.addUserScript(Self.scrollScript)
        controller.addUserScript(Self.selectionScript)
        controller.addUserScript(Self.hoverScript)
        controller.add(manager, name: EPUBViewManager.scrollMessageName)
        controller.add(manager, name: EPUBViewManager.selectionMessageName)
        controller.add(manager, name: EPUBViewManager.hoverMessageName)

        let webView = RELLEPUBWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = manager
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")   // theme CSS paints it

        manager.webView = webView
        manager.currentTheme = pageTheme
        manager.currentFontSize = fontSize

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
            manager.currentFontSize = fontSize
            manager.load(url: documentURL)
        } else if manager.currentTheme != pageTheme || manager.currentFontSize != fontSize {
            manager.applyAppearance(theme: pageTheme, fontSize: fontSize)
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
        let contextSentence = $contextSentence

        manager.hoverEnabled = hoverEnabled
        let quickLookup = self.quickLookup
        let savedWords = self.savedWordsStore
        manager.hoverCachedLookup = { term in
            quickLookup.cachedDefinition(for: term, savedWordsStore: savedWords)
        }
        manager.hoverLookup = { term in
            try await quickLookup.definition(for: term)
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
                llmOutputs: [:]
            ))
        }
        webView.onContextLookUp = {
            NotificationCenter.default.post(name: .inspectorRunLastModule, object: nil)
        }
        webView.onContextAnalyze = { module in
            NotificationCenter.default.post(name: .inspectorRunModule, object: module.rawValue)
        }
        webView.onContextSpeak = { [weak manager] in
            guard let manager else { return }
            let text = manager.lastSelectionText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            SpeechManager.shared.speak(text, voice: .englishUS, rate: 0.5)
        }
    }

    // MARK: Injected scripts

    /// Throttled scroll reporting for reading-position persistence.
    private static let scrollScript = WKUserScript(
        source: """
        (function() {
            var pending = false;
            window.addEventListener('scroll', function() {
                if (pending) { return; }
                pending = true;
                setTimeout(function() {
                    pending = false;
                    var max = document.body.scrollHeight - window.innerHeight;
                    var fraction = max > 0 ? window.scrollY / max : 0;
                    window.webkit.messageHandlers.\(EPUBViewManager.scrollMessageName)
                        .postMessage(fraction);
                }, 250);
            }, { passive: true });
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    /// Hover dictionary bridge: after the pointer rests for 500 ms over a
    /// word (and nothing is selected), report the word + its viewport rect.
    /// An empty word means "hover ended" and closes the popover.
    private static let hoverScript = WKUserScript(
        source: """
        (function() {
            var timer = null;
            var WORD = /[A-Za-zÀ-ÖØ-öø-ÿĀ-ſ'’-]/;

            function post(word, r) {
                window.webkit.messageHandlers.\(EPUBViewManager.hoverMessageName).postMessage({
                    word: word,
                    x: r ? r.left : 0, y: r ? r.top : 0,
                    w: r ? r.width : 0, h: r ? r.height : 0
                });
            }

            document.addEventListener('mousemove', function(event) {
                if (timer) { clearTimeout(timer); }
                timer = setTimeout(function() {
                    var sel = window.getSelection();
                    if (sel && sel.toString().trim().length > 0) { return; }
                    var range = document.caretRangeFromPoint(event.clientX, event.clientY);
                    if (!range || !range.startContainer || range.startContainer.nodeType !== 3) {
                        post('', null); return;
                    }
                    var node = range.startContainer;
                    var text = node.textContent;
                    var offset = range.startOffset;
                    if (offset >= text.length || !WORD.test(text[offset])) { post('', null); return; }
                    var start = offset; while (start > 0 && WORD.test(text[start - 1])) { start--; }
                    var end = offset; while (end < text.length && WORD.test(text[end])) { end++; }
                    var wordRange = document.createRange();
                    wordRange.setStart(node, start);
                    wordRange.setEnd(node, end);
                    post(text.substring(start, end), wordRange.getBoundingClientRect());
                }, 500);
            }, { passive: true });

            document.addEventListener('mouseleave', function() {
                if (timer) { clearTimeout(timer); }
                post('', null);
            });
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    /// Selection bridge: debounced selectionchange → { text, sentence }.
    /// The sentence is cut from the enclosing block's text at sentence
    /// punctuation — the web counterpart of the PDF side's NLTokenizer pass.
    private static let selectionScript = WKUserScript(
        source: """
        (function() {
            var timer = null;
            var BOUNDARIES = /[.!?…]/;

            function enclosingBlock(node) {
                var el = node && node.nodeType === 3 ? node.parentElement : node;
                while (el && el.tagName &&
                       !/^(P|DIV|LI|BLOCKQUOTE|TD|DD|DT|FIGCAPTION|H[1-6]|BODY)$/i.test(el.tagName)) {
                    el = el.parentElement;
                }
                return el;
            }

            function sentenceAround(blockText, selected) {
                if (!blockText || !selected) { return ''; }
                var index = blockText.indexOf(selected);
                if (index < 0) { return ''; }
                var start = 0;
                for (var i = index - 1; i >= 0; i--) {
                    if (BOUNDARIES.test(blockText[i])) { start = i + 1; break; }
                }
                var end = blockText.length;
                for (var j = index + selected.length; j < blockText.length; j++) {
                    if (BOUNDARIES.test(blockText[j])) { end = j + 1; break; }
                }
                return blockText.substring(start, end).trim();
            }

            document.addEventListener('selectionchange', function() {
                if (timer) { clearTimeout(timer); }
                timer = setTimeout(function() {
                    var sel = window.getSelection();
                    var text = sel ? sel.toString().trim() : '';
                    var sentence = '';
                    if (text.length > 0 && sel.anchorNode) {
                        var block = enclosingBlock(sel.anchorNode);
                        sentence = sentenceAround(block ? block.innerText : '', text);
                    }
                    window.webkit.messageHandlers.\(EPUBViewManager.selectionMessageName)
                        .postMessage({ text: text, sentence: sentence });
                }, 120);
            });
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )
}
