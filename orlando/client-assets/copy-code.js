/* copy-code.js — give every `<pre>` block a copy-to-clipboard button in
   its upper-right corner. If the source markdown placed an explicit
   `<a class="copy">` marker right before the `<pre>`, that marker is
   reused; otherwise a new one is created. Either way every `<pre>` ends
   up with a working copy button.

   Wires itself up on DOMContentLoaded. No dependencies. */
(function () {
    'use strict';

    /* Standard clipboard icon: two overlapping rounded rectangles. */
    var ICON = '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor" aria-hidden="true">'
        + '<path d="M16 1H4C2.9 1 2 1.9 2 3v14h2V3h12V1zm3 4H8C6.9 5 6 5.9 6 7v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/>'
        + '</svg>';

    /* If a `<pre>` is preceded by an `<a class="copy">` marker — either
       bare or wrapped in a `<p>` by the markdown renderer — return that
       link. The link is then reused as the copy button.

       When the `<pre>` is itself inside a `.code-block` language-label
       wrapper, the marker lives before the wrapper (the wrapper is the
       pre's parent), so the search starts from the wrapper instead of
       the pre. */
    function findExistingMarker(pre) {
        var anchor = pre;
        if (pre.parentNode
            && pre.parentNode.classList
            && pre.parentNode.classList.contains('code-block')) {
            anchor = pre.parentNode;
        }
        var prev = anchor.previousElementSibling;
        if (!prev) return null;
        if (prev.tagName === 'A' && prev.classList.contains('copy')) {
            return prev;
        }
        if (prev.tagName === 'P' && prev.children.length === 1) {
            var only = prev.children[0];
            if (only.tagName === 'A' && only.classList.contains('copy')) {
                return only;
            }
        }
        return null;
    }

    /* Best-effort text-to-clipboard. Tries the async clipboard API
       first; falls back to the deprecated execCommand path both when
       the API is missing AND when it rejects (Firefox over HTTP,
       documents without focus, sandboxed iframes, etc. all trigger
       rejection even though the API itself exists). Returns a Promise
       that resolves to true/false; never rejects. */
    function copyText(text) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            return navigator.clipboard.writeText(text)
                .then(function () { return true; })
                .catch(function () { return execCommandCopy(text); });
        }
        return Promise.resolve(execCommandCopy(text));
    }

    function execCommandCopy(text) {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.setAttribute('readonly', '');
        ta.style.position = 'fixed';
        ta.style.top = '0';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        var ok = false;
        try { ok = document.execCommand('copy'); } catch (e) { /* ignore */ }
        document.body.removeChild(ta);
        return ok;
    }

    /* Wrap `<pre>` in a `.code-with-copy` div with the given link as the
       copy button. Wires up the click handler. */
    function attachCopy(pre, link) {
        var wrap = document.createElement('div');
        wrap.className = 'code-with-copy';
        pre.parentNode.insertBefore(wrap, pre);
        wrap.appendChild(link);
        wrap.appendChild(pre);

        link.innerHTML = ICON;
        link.removeAttribute('href');
        link.setAttribute('role', 'button');
        link.setAttribute('tabindex', '0');
        link.setAttribute('aria-label', 'Copy code');
        link.setAttribute('title', 'Copy code');

        link.addEventListener('click', function (e) {
            e.preventDefault();
            /* `<pre>` content is the code's text — use innerText so the
               browser strips highlight spans. */
            var text = pre.innerText;
            copyText(text).then(function (ok) {
                var klass = ok ? 'copied' : 'copy-failed';
                link.classList.add(klass);
                setTimeout(function () { link.classList.remove(klass); }, 1200);
            });
        });
    }

    function init() {
        var pres = document.querySelectorAll('pre');
        Array.prototype.forEach.call(pres, function (pre) {
            /* Skip if already wrapped (defensive — shouldn't happen on a
               single pass, but cheap to check). */
            if (pre.parentNode
                && pre.parentNode.classList
                && pre.parentNode.classList.contains('code-with-copy')) {
                return;
            }

            /* Reuse an explicit `<a class="copy">` marker if the markdown
               placed one before this `<pre>`. Otherwise create one. */
            var link = findExistingMarker(pre);
            if (!link) {
                link = document.createElement('a');
                link.className = 'copy';
            }

            attachCopy(pre, link);
        });

        /* Clean up empty `<p>` elements left behind when we moved a link
           out of its original paragraph wrapper. */
        var emptyParas = document.querySelectorAll('p:empty');
        Array.prototype.forEach.call(emptyParas, function (p) {
            p.parentNode.removeChild(p);
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
