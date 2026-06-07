/* issue-copy.js — click a .issue-num-badge to copy its data-copy value to
   the clipboard. Shows "Copied!" feedback in the badge, then restores the
   original label after a short delay.

   Used on /issues AND on every doc page (the per-doc issue panels render
   with the same badge format). Event-delegated from the document so
   dynamically-added badges (e.g., quick-add.js inserting a new issue
   panel after submission) work without rebinding. */
(function () {
    'use strict';

    /* Try the async Clipboard API first; fall back to a hidden-textarea +
       execCommand path if the async API is missing OR rejects (Firefox
       sometimes rejects in non-secure contexts; some browsers gate it
       behind permissions even on localhost). Returns a Promise that
       resolves with true on success, false on failure. */
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

    /* Briefly replace the badge text with feedback, then restore. */
    function flashBadge(btn, text, klass) {
        if (btn.dataset.copyRestoreTimer) {
            clearTimeout(parseInt(btn.dataset.copyRestoreTimer, 10));
        }
        var original = btn.dataset.copyOriginal || btn.textContent;
        btn.dataset.copyOriginal = original;
        btn.textContent = text;
        btn.classList.add(klass);
        var t = setTimeout(function () {
            btn.textContent = original;
            btn.classList.remove(klass);
            delete btn.dataset.copyRestoreTimer;
        }, 1200);
        btn.dataset.copyRestoreTimer = String(t);
    }

    /* Event-delegated click handler — works for badges present at page
       load AND for badges inserted later (quick-add.js renders new
       issue panels client-side, and event delegation catches them
       without rebinding). */
    document.addEventListener('click', function (ev) {
        var btn = ev.target.closest && ev.target.closest('.issue-num-badge[data-copy]');
        if (!btn) return;
        ev.preventDefault();
        var text = btn.getAttribute('data-copy') || '';
        if (!text) return;
        copyText(text).then(function (ok) {
            flashBadge(btn, ok ? 'Copied!' : 'Copy failed', ok ? 'copied' : 'copy-failed');
        });
    });
})();
