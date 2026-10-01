// rell-karaoke.js — injected into every EPUB chapter by EPUBReaderView.makeConfiguration (RELL's own content world; the book's scripts are off).
(function() {
    var STYLE_ID = 'rell-karaoke-style';
    // ONE Highlight object, registered once and mutated in place.
    // Re-registering (delete + set) leaves the previous run's painted
    // ranges on screen in WebKit, so every spoken sentence would pile
    // up another stripe. A Highlight is Set-like: clear() then add().
    var highlight = null;

    function ensureStyle() {
        if (document.getElementById(STYLE_ID)) { return; }
        var style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent =
            '::highlight(rell-karaoke) {' +
            '  background-color: var(--rell-karaoke-bg, rgba(255, 205, 90, 0.55));' +
            '}';
        document.head.appendChild(style);
    }

    function registry() {
        if (!window.CSS || !CSS.highlights || typeof Highlight === 'undefined') { return null; }
        if (!highlight) {
            highlight = new Highlight();
            CSS.highlights.set('rell-karaoke', highlight);
        }
        return highlight;
    }

    function clear() {
        if (highlight) { highlight.clear(); }
    }

    window.rellKaraoke = function(sentence, background) {
        try {
            var hl = registry();
            if (!hl) { return false; }
            hl.clear();
            if (!sentence) { return false; }
            ensureStyle();
            if (background) {
                document.documentElement.style.setProperty('--rell-karaoke-bg', background);
            }

            var target = sentence.replace(/\s+/g, ' ').trim().toLowerCase();
            if (target.length < 2) { return false; }

            // Flatten the chapter's text nodes into one whitespace-
            // collapsed string, remembering where each character came
            // from so a match can be turned back into a DOM Range.
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            var flat = '';
            var origin = [];
            var node;
            while ((node = walker.nextNode())) {
                var raw = node.nodeValue;
                if (!raw) { continue; }
                for (var i = 0; i < raw.length; i++) {
                    var ch = raw[i];
                    if (/\s/.test(ch)) {
                        if (flat.length && flat[flat.length - 1] !== ' ') {
                            flat += ' ';
                            origin.push([node, i]);
                        }
                    } else {
                        flat += ch.toLowerCase();
                        origin.push([node, i]);
                    }
                }
            }

            var index = flat.indexOf(target);
            if (index < 0) { return false; }
            var start = origin[index];
            var end = origin[Math.min(index + target.length - 1, origin.length - 1)];
            if (!start || !end) { return false; }

            var range = document.createRange();
            range.setStart(start[0], start[1]);
            range.setEnd(end[0], end[1] + 1);
            hl.add(range);

            var host = start[0].parentElement;
            if (host && host.getBoundingClientRect) {
                var box = host.getBoundingClientRect();
                // Only scroll when it has drifted out of comfortable view.
                if (box.top < 0 || box.bottom > window.innerHeight) {
                    host.scrollIntoView({ block: 'center', behavior: 'smooth' });
                }
            }
            return true;
        } catch (e) {
            clear();
            return false;
        }
    };
})();