// Edit-suggestion form behavior.
//
// 1. When an Edit panel is first opened, fetch the section's current
//    markdown from /api/section-markdown and put it in the textarea.
//    Subsequent re-opens reuse the populated content (so a user can
//    flip the panel closed and back open without losing their edits).
//
// 2. Submission is iframe-targeted (target="edit-target"). When the
//    iframe loads after submit, read the response page to pull the new
//    GitHub issue URL and show a success status outside the panel.

(function () {
    var pendingForm = null;

    function formDivFor(form)   { return form.parentNode; }
    function toggleFor(form)    { return formDivFor(form).previousElementSibling; }

    function statusEl(form) {
        var sib = formDivFor(form).nextElementSibling;
        return (sib && sib.classList && sib.classList.contains("edit-status"))
            ? sib : null;
    }

    function clearStatus(status) {
        if (!status) return;
        status.hidden = true;
        status.textContent = "";
        status.className = "edit-status";
    }

    function populateTextarea(form) {
        var ta = form.querySelector('textarea[name="markdown"]');
        if (!ta) return;
        if (ta.value && ta.value.length > 0) return;  // already populated or user-edited
        var path   = form.getAttribute("data-md-path") || "";
        var anchor = form.getAttribute("data-anchor")  || "";
        if (!path) return;

        var qs = "path=" + encodeURIComponent(path);
        if (anchor) qs += "&anchor=" + encodeURIComponent(anchor);
        ta.placeholder = "Loading section…";

        var xhr = new XMLHttpRequest();
        xhr.open("GET", "/api/section-markdown?" + qs, true);
        xhr.onload = function () {
            if (xhr.status === 200) {
                ta.value = xhr.responseText;
                ta.placeholder = "";
                // Move caret to start so the user sees the top.
                ta.setSelectionRange(0, 0);
                ta.scrollTop = 0;
                ta.focus();
            } else {
                ta.placeholder = "Failed to load section (HTTP " + xhr.status + ").";
            }
        };
        xhr.onerror = function () {
            ta.placeholder = "Failed to load section (network error).";
        };
        xhr.send();
    }

    document.addEventListener("change", function (e) {
        var cb = e.target;
        if (!cb.classList || !cb.classList.contains("edit-toggle")) return;
        if (!cb.checked) return;

        var formDiv = cb.nextElementSibling;
        if (!formDiv) return;

        var status = formDiv.nextElementSibling;
        if (status && status.classList && status.classList.contains("edit-status")) {
            clearStatus(status);
        }

        var form = formDiv.querySelector("form");
        if (!form) return;

        populateTextarea(form);
    });

    document.addEventListener("submit", function (e) {
        var form = e.target;
        if (form.getAttribute("target") !== "edit-target") return;
        pendingForm = form;

        var s = statusEl(form);
        if (s) {
            s.hidden = false;
            s.className = "edit-status pending";
            s.textContent = "Submitting…";
        }
    });

    window.addEventListener("DOMContentLoaded", function () {
        var iframe = document.querySelector('iframe[name="edit-target"]');
        if (!iframe) return;

        iframe.addEventListener("load", function () {
            if (!pendingForm) return;  // initial empty load — ignore

            var form = pendingForm;
            pendingForm = null;
            var s = statusEl(form);
            var doc = null;
            var savedMarker = null;
            var errorText = null;

            try {
                doc = iframe.contentDocument;
                if (doc) {
                    savedMarker = doc.querySelector(
                        'meta[name="orlando-edit-saved"]');
                    if (!savedMarker) {
                        var pre = doc.querySelector("pre");
                        if (pre) errorText = pre.textContent;
                    }
                }
            } catch (_) {
                // same-origin, shouldn't happen
            }

            if (savedMarker && doc) {
                // Swap the freshly server-rendered <main class="content">
                // into the live page. The old main (which contained the
                // form the user just submitted from) is replaced by the
                // new render, so the toggle naturally becomes unchecked
                // and the rendered edit becomes visible immediately —
                // no manual reload.
                var newMain = doc.querySelector("main.content");
                var oldMain = document.querySelector("main.content");
                if (newMain && oldMain) {
                    var savedScroll = window.scrollY;
                    oldMain.innerHTML = newMain.innerHTML;
                    window.scrollTo(0, savedScroll);
                }
                // No status update — the visible content change IS the
                // confirmation. The status element is also inside the
                // replaced DOM, so updating it would be invisible.
            } else if (s) {
                s.className = "edit-status failure";
                s.textContent = errorText
                    ? ("Edit failed: " + errorText)
                    : "Edit failed. Check server logs.";
                s.hidden = false;
            }
        });
    });
})();
