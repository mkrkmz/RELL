// rell-selection.js — injected into every EPUB chapter by EPUBReaderView.makeConfiguration (RELL's own content world; the book's scripts are off).
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

    // Selection bounds in viewport (CSS) coordinates for the native
    // floating action bar. WKWebView is flipped, so these map straight
    // to the web view's subview coordinate space. -1 width = no rect.
    function selRect(sel) {
        if (sel && sel.rangeCount > 0) {
            var r = sel.getRangeAt(0).getBoundingClientRect();
            if (r && (r.width > 0 || r.height > 0)) {
                return { x: r.left, y: r.top, w: r.width, h: r.height };
            }
        }
        return { x: -1, y: -1, w: 0, h: 0 };
    }

    document.addEventListener('selectionchange', function() {
        if (timer) { clearTimeout(timer); }
        timer = setTimeout(function() {
            var sel = window.getSelection();
            var text = sel ? sel.toString().trim() : '';
            var sentence = '';
            var anchor = null;
            var rect = { x: -1, y: -1, w: 0, h: 0 };
            if (text.length > 0 && sel.anchorNode) {
                var block = enclosingBlock(sel.anchorNode);
                sentence = sentenceAround(block ? block.innerText : '', text);
                if (sel.rangeCount > 0 && window.__rellComputeAnchor) {
                    anchor = window.__rellComputeAnchor(sel.getRangeAt(0));
                }
                rect = selRect(sel);
            }
            window.webkit.messageHandlers.rellSelection
                .postMessage({
                    text: text, sentence: sentence,
                    quote: anchor ? anchor.quote : '',
                    prefix: anchor ? anchor.prefix : '',
                    suffix: anchor ? anchor.suffix : '',
                    startOffset: anchor ? anchor.startOffset : -1,
                    rectX: rect.x, rectY: rect.y, rectW: rect.w, rectH: rect.h
                });
        }, 120);
    });

    // Keep the action bar pinned above its selection while the chapter
    // scrolls under it. One post per animation frame; reposition-only.
    var scrollPending = false;
    window.addEventListener('scroll', function() {
        if (scrollPending) { return; }
        scrollPending = true;
        requestAnimationFrame(function() {
            scrollPending = false;
            var sel = window.getSelection();
            var text = sel ? sel.toString().trim() : '';
            var rect = (text.length > 0)
                ? selRect(sel)
                : { x: -1, y: -1, w: 0, h: 0 };
            window.webkit.messageHandlers.rellSelection
                .postMessage({
                    reposition: true,
                    rectX: rect.x, rectY: rect.y, rectW: rect.w, rectH: rect.h
                });
        });
    }, true);
})();