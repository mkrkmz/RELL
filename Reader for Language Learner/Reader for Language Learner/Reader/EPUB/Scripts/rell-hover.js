// rell-hover.js — injected into every EPUB chapter by EPUBReaderView.makeConfiguration (RELL's own content world; the book's scripts are off).
(function() {
    var timer = null;
    var WORD = /[A-Za-zÀ-ÖØ-öø-ÿĀ-ſ'’-]/;

    function post(word, r) {
        window.webkit.messageHandlers.rellHover.postMessage({
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