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
    var onContextHighlight: ((HighlightColor) -> Void)?
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

        let highlightItem = NSMenuItem(title: String(localized: "Highlight"), action: nil, keyEquivalent: "")
        let highlightSubmenu = NSMenu()
        highlightSubmenu.autoenablesItems = false
        for color in HighlightColor.allCases {
            let item = NSMenuItem(
                title: color.label,
                action: #selector(fireHighlight(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = true
            item.representedObject = color.rawValue
            item.image = Self.swatchImage(for: color.nsColor)
            highlightSubmenu.addItem(item)
        }
        highlightItem.submenu = highlightSubmenu
        items.append(highlightItem)

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

    @objc private func fireHighlight(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let color = HighlightColor(rawValue: raw) else { return }
        onContextHighlight?(color)
    }

    /// Small filled-circle swatch for the color submenu items.
    private static func swatchImage(for color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
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

    func makeNSView(context: Context) -> RELLEPUBWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(manager.schemeHandler, forURLScheme: EPUBScheme.scheme)

        let controller = configuration.userContentController
        // highlightScript must precede selectionScript: the latter calls
        // the anchor-computation function the former defines.
        controller.addUserScript(Self.highlightScript)
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
        let highlightStore = self.epubHighlightStore
        let toastCenter = self.toastCenter

        manager.highlightsProvider = { [weak manager] chapterPath in
            guard let bookFilename = manager?.loadedURL?.deletingPathExtension().lastPathComponent
            else { return [] }
            return highlightStore.highlights(for: bookFilename, chapterPath: chapterPath)
        }

        manager.savedWordTermsProvider = {
            store.words
                .map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
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

    /// Defines the shared text-offset walk plus anchor/render/unwrap
    /// functions used both to capture a new highlight's anchor (in
    /// selectionScript) and to re-render marks from the store (called by
    /// Swift via `evaluateJavaScript`). Wrapping/unwrapping a `<mark>`
    /// never changes character counts — only node boundaries — so absolute
    /// text offsets stay valid across repeated re-renders and reflow
    /// (font-size change, window resize).
    private static let highlightScript = WKUserScript(
        source: """
        (function() {
            function rellWalkTextNodes(root) {
                var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                    acceptNode: function(node) {
                        var p = node.parentElement;
                        if (!p) { return NodeFilter.FILTER_REJECT; }
                        var tag = p.tagName;
                        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') {
                            return NodeFilter.FILTER_REJECT;
                        }
                        return NodeFilter.FILTER_ACCEPT;
                    }
                });
                var nodes = [];
                var n;
                while ((n = walker.nextNode())) { nodes.push(n); }
                return nodes;
            }

            function rellFullText(nodes) {
                var text = '';
                var spans = [];
                for (var i = 0; i < nodes.length; i++) {
                    var t = nodes[i].textContent;
                    spans.push({ start: text.length, end: text.length + t.length, node: nodes[i] });
                    text += t;
                }
                return { text: text, spans: spans };
            }

            function rellUnwrapHighlights() {
                var marks = document.querySelectorAll('mark[data-rell-highlight-id]');
                marks.forEach(function(mark) {
                    var parent = mark.parentNode;
                    if (!parent) { return; }
                    while (mark.firstChild) { parent.insertBefore(mark.firstChild, mark); }
                    parent.removeChild(mark);
                    parent.normalize();
                });
            }

            /// Computes a text-quote anchor for a live Range — the DOM is
            /// read as-is (existing marks don't skew offsets; see above).
            function rellComputeAnchor(range) {
                var walked = rellFullText(rellWalkTextNodes(document.body));

                function offsetOf(container, localOffset) {
                    for (var i = 0; i < walked.spans.length; i++) {
                        if (walked.spans[i].node === container) {
                            return walked.spans[i].start + localOffset;
                        }
                    }
                    return -1;
                }

                var start = offsetOf(range.startContainer, range.startOffset);
                var end = offsetOf(range.endContainer, range.endOffset);
                if (start < 0 || end < 0 || end <= start) { return null; }

                var CTX = 24;
                return {
                    quote: walked.text.substring(start, end),
                    prefix: walked.text.substring(Math.max(0, start - CTX), start),
                    suffix: walked.text.substring(end, Math.min(walked.text.length, end + CTX)),
                    startOffset: start
                };
            }

            /// Resolves a stored anchor to a live [start, end) offset pair:
            /// try the saved offset first (fast path, valid unless the
            /// chapter content itself changed), then prefix+quote+suffix,
            /// then the bare quote as a last resort.
            function rellResolvePosition(fullText, entry) {
                if (entry.startOffset >= 0) {
                    var atOffset = fullText.substr(entry.startOffset, entry.quote.length);
                    if (atOffset === entry.quote) {
                        return { start: entry.startOffset, end: entry.startOffset + entry.quote.length };
                    }
                }
                if (entry.prefix || entry.suffix) {
                    var needle = entry.prefix + entry.quote + entry.suffix;
                    var idx = fullText.indexOf(needle);
                    if (idx >= 0) {
                        var start = idx + entry.prefix.length;
                        return { start: start, end: start + entry.quote.length };
                    }
                }
                var bare = fullText.indexOf(entry.quote);
                if (bare >= 0) { return { start: bare, end: bare + entry.quote.length }; }
                return null;
            }

            function rellNodeOffsetFor(spans, globalOffset) {
                for (var i = 0; i < spans.length; i++) {
                    if (globalOffset >= spans[i].start && globalOffset <= spans[i].end) {
                        return { node: spans[i].node, offset: globalOffset - spans[i].start };
                    }
                }
                return null;
            }

            function rellWrapRange(spans, start, end, id, color, ink) {
                var startPos = rellNodeOffsetFor(spans, start);
                var endPos = rellNodeOffsetFor(spans, end);
                if (!startPos || !endPos) { return; }
                var range = document.createRange();
                range.setStart(startPos.node, startPos.offset);
                range.setEnd(endPos.node, endPos.offset);

                var mark = document.createElement('mark');
                mark.setAttribute('data-rell-highlight-id', id);
                mark.style.backgroundColor = color;
                mark.style.color = ink || '#1d1d1f';
                mark.style.borderRadius = '2px';
                mark.style.padding = '0 1px';
                // extractContents+insertNode (rather than surroundContents)
                // handles ranges that span multiple elements or partial
                // inline tags (e.g. a quote crossing into a <b>) uniformly.
                var frag = range.extractContents();
                mark.appendChild(frag);
                range.insertNode(mark);
            }

            window.rellRenderHighlights = function(entries, ink) {
                rellUnwrapHighlights();
                if (!entries || !entries.length) { return; }

                // Resolve every entry against one pristine pre-wrap walk —
                // resolution must happen before any wrapping mutates the DOM.
                var walked0 = rellFullText(rellWalkTextNodes(document.body));
                var resolved = [];
                entries.forEach(function(e) {
                    var pos = rellResolvePosition(walked0.text, e);
                    if (pos) { resolved.push({ id: e.id, color: e.color, start: pos.start, end: pos.end }); }
                });
                resolved.sort(function(a, b) { return a.start - b.start; });

                // Wrap one at a time, re-walking the (now-mutated) DOM
                // before each wrap so node references are always fresh —
                // chapters are small, so this is cheap and sidesteps any
                // node-identity invalidation from the previous wrap.
                var lastEnd = -1;
                resolved.forEach(function(r) {
                    if (r.start < lastEnd) { return; } // overlapping highlight — skip
                    var walked = rellFullText(rellWalkTextNodes(document.body));
                    rellWrapRange(walked.spans, r.start, r.end, r.id, r.color, ink);
                    lastEnd = r.end;
                });
            };

            window.__rellComputeAnchor = rellComputeAnchor;

            // ── Saved-word marks ────────────────────────────────────────
            // Dotted underline, no background — stays visually distinct
            // from a user highlight's colored fill. Click selects the
            // word's text so the existing selectionchange listener below
            // (selectionScript) picks it up exactly like a manual
            // selection, feeding the same lookup path with no separate
            // message channel.

            var rellSavedWordClickBound = false;
            function rellBindSavedWordClicks() {
                if (rellSavedWordClickBound) { return; }
                rellSavedWordClickBound = true;
                document.body.addEventListener('click', function(event) {
                    var target = event.target;
                    var span = target && target.closest
                        ? target.closest('span[data-rell-saved-word]') : null;
                    if (!span) { return; }
                    var range = document.createRange();
                    range.selectNodeContents(span);
                    var sel = window.getSelection();
                    sel.removeAllRanges();
                    sel.addRange(range);
                });
            }

            function rellUnmarkSavedWords() {
                var marks = document.querySelectorAll('span[data-rell-saved-word]');
                marks.forEach(function(span) {
                    var parent = span.parentNode;
                    if (!parent) { return; }
                    while (span.firstChild) { parent.insertBefore(span.firstChild, span); }
                    parent.removeChild(span);
                    parent.normalize();
                });
            }

            // CJK scripts have no whitespace word segmentation, so a
            // letter-boundary check would reject every real match (the
            // character before/after is itself a letter). Terms in these
            // scripts use a plain substring scan instead — everything else
            // gets Unicode-aware whole-word matching.
            var rellCJK = /[぀-ヿ㐀-鿿가-힯]/;

            function rellSubstringRanges(term, text, cap) {
                var lower = text.toLowerCase();
                var needle = term.toLowerCase();
                var ranges = [];
                var idx = 0;
                while (ranges.length < cap && (idx = lower.indexOf(needle, idx)) >= 0) {
                    ranges.push({ start: idx, end: idx + needle.length });
                    idx += needle.length;
                }
                return ranges;
            }

            function rellFindTermRanges(term, text, cap) {
                if (rellCJK.test(term)) { return rellSubstringRanges(term, text, cap); }

                var escaped = term.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                var regex;
                try {
                    regex = new RegExp('(?<![\\\\p{L}\\\\p{N}])' + escaped + '(?![\\\\p{L}\\\\p{N}])', 'giu');
                } catch (e) {
                    // Defensive fallback for a term whose regex failed to compile.
                    return rellSubstringRanges(term, text, cap);
                }
                var ranges = [];
                var m;
                while (ranges.length < cap && (m = regex.exec(text))) {
                    ranges.push({ start: m.index, end: m.index + m[0].length });
                    if (m[0].length === 0) { regex.lastIndex++; }
                }
                return ranges;
            }

            function rellAcceptableSavedWordNode(node) {
                var p = node.parentElement;
                while (p) {
                    if (p.tagName === 'MARK' || (p.dataset && p.dataset.rellSavedWord)) {
                        return false;
                    }
                    p = p.parentElement;
                }
                return true;
            }

            function rellMarkRangesInNode(node, ranges, color) {
                var text = node.textContent;
                var frag = document.createDocumentFragment();
                var last = 0;
                ranges.forEach(function(r) {
                    if (r.start > last) {
                        frag.appendChild(document.createTextNode(text.substring(last, r.start)));
                    }
                    var span = document.createElement('span');
                    span.setAttribute('data-rell-saved-word', '1');
                    span.style.textDecorationLine = 'underline';
                    span.style.textDecorationStyle = 'dotted';
                    span.style.textDecorationColor = color;
                    span.style.textUnderlineOffset = '2px';
                    span.style.cursor = 'pointer';
                    span.textContent = text.substring(r.start, r.end);
                    frag.appendChild(span);
                    last = r.end;
                });
                if (last < text.length) {
                    frag.appendChild(document.createTextNode(text.substring(last)));
                }
                node.parentNode.replaceChild(frag, node);
            }

            /// Underlines every occurrence of a saved word. Case-insensitive;
            /// Unicode-aware letter/number boundaries give correct whole-word
            /// matching for accented Latin, Cyrillic, and Arabic scripts,
            /// while CJK terms use plain substring matching (no boundary
            /// concept applies there — see `rellFindTermRanges`).
            window.rellMarkSavedWords = function(terms, color) {
                rellUnmarkSavedWords();
                if (!terms || !terms.length) { return; }
                rellBindSavedWordClicks();

                // Bounds: at most 500 terms and 50 matches per term per
                // chapter — a saved vocabulary can grow into the thousands,
                // and a single common word could otherwise match hundreds
                // of times in one chapter.
                terms.slice(0, 500).forEach(function(term) {
                    if (!term) { return; }
                    var matched = 0;
                    // Re-walk fresh for each term — the previous term's
                    // wraps mutated the DOM, invalidating old node refs.
                    var nodes = rellWalkTextNodes(document.body).filter(rellAcceptableSavedWordNode);
                    for (var i = 0; i < nodes.length && matched < 50; i++) {
                        var node = nodes[i];
                        var ranges = rellFindTermRanges(term, node.textContent, 50 - matched);
                        if (ranges.length) {
                            rellMarkRangesInNode(node, ranges, color);
                            matched += ranges.length;
                        }
                    }
                });
            };
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

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
                    var anchor = null;
                    if (text.length > 0 && sel.anchorNode) {
                        var block = enclosingBlock(sel.anchorNode);
                        sentence = sentenceAround(block ? block.innerText : '', text);
                        if (sel.rangeCount > 0 && window.__rellComputeAnchor) {
                            anchor = window.__rellComputeAnchor(sel.getRangeAt(0));
                        }
                    }
                    window.webkit.messageHandlers.\(EPUBViewManager.selectionMessageName)
                        .postMessage({
                            text: text, sentence: sentence,
                            quote: anchor ? anchor.quote : '',
                            prefix: anchor ? anchor.prefix : '',
                            suffix: anchor ? anchor.suffix : '',
                            startOffset: anchor ? anchor.startOffset : -1
                        });
                }, 120);
            });
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )
}
