// rell-scroll.js — injected into every EPUB chapter by EPUBReaderView.makeConfiguration (RELL's own content world; the book's scripts are off).
(function() {
    var pending = false;
    window.addEventListener('scroll', function() {
        if (pending) { return; }
        pending = true;
        setTimeout(function() {
            pending = false;
            var max = document.body.scrollHeight - window.innerHeight;
            var fraction = max > 0 ? window.scrollY / max : 0;
            window.webkit.messageHandlers.rellScroll
                .postMessage(fraction);
        }, 250);
    }, { passive: true });
})();