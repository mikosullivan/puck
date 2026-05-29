/* copy-code.js — turn `<a class="copy">` markers that sit before a
   `<pre>` block into a working copy-to-clipboard button positioned in
   the upper-right corner of that `<pre>`.

   Wires itself up on DOMContentLoaded. No dependencies. */
(function () {
    'use strict';

    /* Standard clipboard icon: two overlapping rounded rectangles. */
    var ICON = '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor" aria-hidden="true">'
        + '<path d="M16 1H4C2.9 1 2 1.9 2 3v14h2V3h12V1zm3 4H8C6.9 5 6 5.9 6 7v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/>'
        + '</svg>';

    /* From a `.copy` marker, find the nearest following `<pre>` element.
       Handles both the case where the marker is inline in body content
       and where the markdown renderer wrapped it in a stray `<p>`. */
    function findTargetPre(link) {
        var walker = link.parentElement && link.parentElement.tagName === 'P'
            ? link.parentElement
            : link;
        while ((walker = walker.nextElementSibling)) {
            if (!walker) return null;
            if (walker.tagName === 'PRE') return walker;
            /* Safety guard: if we walk past a heading or another paragraph
               of body text, there's no adjacent <pre>. */
            if (/^H\d$/.test(walker.tagName)) return null;
            if (walker.tagName === 'P' && walker.textContent.trim() !== '') return null;
        }
        return null;
    }

    /* Best-effort text-to-clipboard. Prefers the async clipboard API; falls
       back to the deprecated execCommand path for older browsers. */
    function copyText(text) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            return navigator.clipboard.writeText(text);
        }
        return new Promise(function (resolve, reject) {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.style.position = 'fixed';
            ta.style.top = '-1000px';
            document.body.appendChild(ta);
            ta.select();
            try {
                document.execCommand('copy');
                resolve();
            } catch (err) {
                reject(err);
            } finally {
                document.body.removeChild(ta);
            }
        });
    }

    function init() {
        var links = document.querySelectorAll('a.copy');
        Array.prototype.forEach.call(links, function (link) {
            var pre = findTargetPre(link);
            if (!pre) return;

            /* Wrap the <pre> in a positioning container, move the link in.
               Link is appended first so DOM order matches the source order
               (the markdown writes the link before the code fence). CSS
               positions the link absolutely in the upper-right, so visual
               placement is independent of DOM order. */
            var wrap = document.createElement('div');
            wrap.className = 'code-with-copy';
            pre.parentNode.insertBefore(wrap, pre);
            wrap.appendChild(link);
            wrap.appendChild(pre);

            /* Replace link contents with the icon; strip href so it stops
               navigating; mark up as a button for accessibility. */
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
                copyText(text).then(function () {
                    link.classList.add('copied');
                    setTimeout(function () { link.classList.remove('copied'); }, 1200);
                }).catch(function () {
                    /* Quiet failure: nothing for the user to act on. */
                });
            });
        });

        /* Clean up empty `<p>` elements left behind when we moved the link
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
