// rell-highlight.js — injected into every EPUB chapter by EPUBReaderView.makeConfiguration (RELL's own content world; the book's scripts are off).
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

        var escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        var regex;
        try {
            regex = new RegExp('(?<![\\p{L}\\p{N}])' + escaped + '(?![\\p{L}\\p{N}])', 'giu');
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

    function rellMarkRangesInNode(node, ranges, color, gloss, underline) {
        var text = node.textContent;
        var frag = document.createDocumentFragment();
        var last = 0;
        ranges.forEach(function(r) {
            if (r.start > last) {
                frag.appendChild(document.createTextNode(text.substring(last, r.start)));
            }
            var span = document.createElement('span');
            span.setAttribute('data-rell-saved-word', underline ? '1' : 'gloss');
            // The meaning is drawn by CSS (::after, attr()) — a
            // pseudo-element adds nothing to textContent, so text
            // offsets for highlights, search and karaoke stay valid.
            if (gloss) { span.setAttribute('data-rell-gloss', gloss); }
            if (underline) {
                span.style.textDecorationLine = 'underline';
                span.style.textDecorationStyle = 'dotted';
                span.style.textDecorationColor = color;
                span.style.textUnderlineOffset = '2px';
            }
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
    function rellSetGlossStyle(on, glossColor) {
        var root = document.documentElement;
        var was = root.classList.contains('rell-glossing');
        // Turning glosses on or off changes the line height, which
        // moves every line; keep the reader at the same place in
        // the chapter rather than the same pixel offset.
        var fraction = was === on ? null
            : window.scrollY / Math.max(1, root.scrollHeight - window.innerHeight);
        rellApplyGlossStyle(on, glossColor);
        if (fraction !== null && fraction > 0) {
            window.scrollTo(0, fraction * Math.max(0, root.scrollHeight - window.innerHeight));
        }
    }

    function rellApplyGlossStyle(on, glossColor) {
        var style = document.getElementById('rell-gloss-style');
        if (!on) {
            if (style) { style.remove(); }
            document.documentElement.classList.remove('rell-glossing');
            return;
        }
        if (!style) {
            style = document.createElement('style');
            style.id = 'rell-gloss-style';
            document.documentElement.appendChild(style);
        }
        // Room above each line for the meaning; more specific than
        // the appearance rules, so it wins while glosses are on.
        style.textContent =
            'html.rell-glossing body, html.rell-glossing body p, html.rell-glossing body li, ' +
            'html.rell-glossing body blockquote { line-height: 2.35 !important; }' +
            'span[data-rell-gloss] { position: relative; }' +
            'span[data-rell-gloss]::after { content: attr(data-rell-gloss); position: absolute; ' +
            'left: 50%; bottom: 88%; transform: translateX(-50%); font-size: 0.56em; ' +
            'line-height: 1; white-space: nowrap; font-style: normal; font-weight: 500; ' +
            'letter-spacing: 0; text-indent: 0; text-transform: none; pointer-events: none; ' +
            '-webkit-user-select: none; user-select: none; color: ' + glossColor + '; }';
        document.documentElement.classList.add('rell-glossing');
    }

    /// `glosses`: lowercased term → short meaning shown above it.
    /// `glossOnly`: terms that get a meaning but aren't saved words
    /// (the chapter warm-up), so no saved-word underline.
    window.rellMarkSavedWords = function(terms, color, glosses, glossOnly, glossColor) {
        rellUnmarkSavedWords();
        glosses = glosses || {};
        glossOnly = glossOnly || [];
        var glossing = Object.keys(glosses).length > 0;
        rellSetGlossStyle(glossing, glossColor);
        var onlySet = {};
        glossOnly.forEach(function(t) { onlySet[t.toLowerCase()] = true; });
        // Warm-up words first: there are only a handful, and the
        // 500-term cap below shouldn't be able to crowd them out.
        terms = glossOnly.filter(function(t) {
            return glosses[t.toLowerCase()];
        }).concat(terms || []);
        if (!terms.length) { return; }
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
                    var key = term.toLowerCase();
                    rellMarkRangesInNode(node, ranges, color, glosses[key], !onlySet[key]);
                    matched += ranges.length;
                }
            }
        });
    };
})();