// Issue actions: per-card buttons and forms in the open-issues panels.
//
// Handlers:
//   - "Close" button (per-doc-page panels): confirms, POSTs to
//     /api/close-issue, removes the card.
//   - Comment form (the /issues page, allowed IPs only): POSTs body
//     to /api/comment-issue, shows brief feedback, clears textarea.
//
// Both endpoints are form-encoded; both return JSON {ok, error?}.

(function () {
    function postForm(url, body) {
        return fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: body,
        }).then(function (r) {
            return r.json().then(function (j) {
                if (!j.ok) throw new Error(j.error || ("HTTP " + r.status));
                return j;
            });
        });
    }

    function postClose(number) {
        return postForm("/api/close-issue", "number=" + encodeURIComponent(String(number)));
    }

    function postComment(number, body) {
        var qs = "number=" + encodeURIComponent(String(number))
               + "&body="  + encodeURIComponent(body);
        return postForm("/api/comment-issue", qs);
    }

    /* ===== Close ===== */

    document.addEventListener("click", function (e) {
        var btn = e.target;
        if (!btn.classList || !btn.classList.contains("issue-close")) return;
        e.preventDefault();
        var number = btn.getAttribute("data-issue-number");
        if (!number) return;
        if (!window.confirm("Close issue #" + number + "?")) return;

        btn.disabled = true;
        btn.textContent = "Closing…";

        postClose(number).then(function () {
            // Remove every card for this issue across all the places it
            // could appear. Every surface now wraps a card in
            // <div class="issue-card">; the older .issue-item /
            // .issue-panel wrappers are kept as fallbacks in case any
            // legacy markup remains.
            var selector = '.issue-close[data-issue-number="' + number + '"]';
            var anyRemoved = false;
            document.querySelectorAll(selector).forEach(function (b) {
                var wrapper = b.closest(".issue-card")
                           || b.closest(".issue-item")
                           || b.closest(".issue-panel");
                if (wrapper) { wrapper.remove(); anyRemoved = true; }
            });
            // No wrapper found — reload so the dashboard refreshes.
            if (!anyRemoved) { window.location.reload(); return; }
            // For each per-doc / per-section panel that's now empty,
            // drop the panel too and update counts on panels that
            // still have items.
            document.querySelectorAll(".issues-panel").forEach(function (panel) {
                var items = panel.querySelectorAll(".issue-card, .issue-item");
                if (items.length === 0) {
                    panel.remove();
                } else {
                    var summary = panel.querySelector("summary");
                    if (summary) {
                        summary.textContent = "Open issues (" + items.length + ")";
                    }
                }
            });
            // On /issues, update the summary count to reflect the close.
            var summary = document.querySelector(".issues-summary");
            if (summary) {
                var remaining = document.querySelectorAll(".issue-card, .issue-panel").length;
                summary.textContent = remaining + " open issue"
                    + (remaining === 1 ? "" : "s")
                    + " — sorted by issue number, newest first";
            }
        }).catch(function (err) {
            btn.disabled = false;
            btn.textContent = "Close";
            window.alert("Close failed: " + (err && err.message ? err.message : err));
        });
    });

    /* ===== Comment form (on /issues and on audit.md cards) =====

       Two surfaces share .issue-comment-form: the per-card form on /issues
       (always visible inside a <details>) and the per-card form on
       audit.md (hidden by default, toggled by the Comment chip in
       the heading's chip group). The Cancel and resolve-checkbox features
       only apply to the audit.md form but are harmless on /issues. */

    document.addEventListener("click", function (e) {
        var t = e.target;
        if (!t.classList) return;

        // Comment chip toggles the matching hidden form. The same issue
        // can appear in more than one panel on the same page (top-of-doc
        // panel + per-section panel), each with its own form keyed by the
        // same data-issue-number. Scope the lookup to THIS button's
        // .issue-card so we toggle the form right next to the click.
        if (t.classList.contains("issue-comment")) {
            var card = t.closest(".issue-card");
            var form = card && card.querySelector(".issue-card-comment-form");
            if (!form) return;
            if (form.hasAttribute("hidden")) {
                form.removeAttribute("hidden");
                var ta = form.querySelector("textarea[name=body]");
                if (ta) ta.focus();
            } else {
                form.setAttribute("hidden", "");
            }
            return;
        }

        // Cancel button hides the form and clears its contents.
        if (t.classList.contains("issue-comment-cancel")) {
            var f = t.closest("form.issue-card-comment-form");
            if (!f) return;
            var t1 = f.querySelector("textarea[name=body]"); if (t1) t1.value = "";
            var r1 = f.querySelector("input[name=resolve]"); if (r1) r1.checked = false;
            var s1 = f.querySelector(".issue-comment-status"); if (s1) s1.textContent = "";
            f.setAttribute("hidden", "");
        }
    });

    document.addEventListener("submit", function (e) {
        var form = e.target;
        if (!form.classList || !form.classList.contains("issue-comment-form")) return;
        e.preventDefault();

        var number = form.getAttribute("data-issue-number");
        if (!number) return;

        var ta     = form.querySelector("textarea[name=body]");
        var btn    = form.querySelector("button[type=submit]");
        var status = form.querySelector(".issue-comment-status");
        var resolveCb = form.querySelector("input[name=resolve]");
        var body   = (ta && ta.value || "").trim();
        if (!body) {
            if (status) status.textContent = "Comment can't be empty.";
            return;
        }
        // Resolution marker — when the checkbox is checked, prefix the
        // comment so a future audit (Claude reading the issue body /
        // comments) can spot it as "this is how to resolve, please fix".
        if (resolveCb && resolveCb.checked) {
            body = "**Resolve:** " + body;
        }

        if (btn) { btn.disabled = true; btn.textContent = "Posting…"; }
        if (status) { status.textContent = ""; }

        postComment(number, body).then(function () {
            if (ta) ta.value = "";
            if (resolveCb) resolveCb.checked = false;
            if (btn) { btn.disabled = false; btn.textContent = "Post comment"; }
            if (status) {
                status.textContent = "Posted ✓";
                status.classList.add("ok");
                setTimeout(function () {
                    status.textContent = "";
                    status.classList.remove("ok");
                }, 2500);
            }
            // Auto-hide audit.md inline form on success.
            if (form.classList.contains("issue-card-comment-form")) {
                setTimeout(function () { form.setAttribute("hidden", ""); }, 1200);
            }
            // Bump the comment count badge on this panel if present.
            var panel = form.closest(".issue-panel");
            if (panel) {
                var c = panel.querySelector(".issue-panel-comments");
                if (c) {
                    var m = (c.textContent || "").match(/^(\d+)/);
                    var n = m ? parseInt(m[1], 10) + 1 : 1;
                    c.textContent = n + " comment" + (n === 1 ? "" : "s");
                } else {
                    // No badge existed (0 comments before). Add one.
                    var foot = panel.querySelector(".issue-panel-foot");
                    if (foot) {
                        var span = document.createElement("span");
                        span.className = "issue-panel-comments";
                        span.textContent = "1 comment";
                        foot.insertBefore(span, foot.firstChild);
                    }
                }
            }
        }).catch(function (err) {
            if (btn) { btn.disabled = false; btn.textContent = "Post comment"; }
            if (status) {
                status.textContent = "Failed: " + (err && err.message ? err.message : err);
                status.classList.add("err");
                setTimeout(function () { status.classList.remove("err"); }, 4000);
            }
        });
    });

    /* ===== Refresh issues cache ===== */
    // Button on /issues — re-pulls the cache from gh, then reloads.

    document.addEventListener("click", function (e) {
        var btn = e.target;
        if (!btn.classList || !btn.classList.contains("issues-refresh")) return;
        e.preventDefault();
        btn.disabled = true;
        var original = btn.textContent;
        btn.textContent = "Refreshing…";
        postForm("/api/refresh-issues", "").then(function () {
            window.location.reload();
        }).catch(function (err) {
            btn.disabled = false;
            btn.textContent = original;
            window.alert("Refresh failed: " + (err && err.message ? err.message : err));
        });
    });
})();
