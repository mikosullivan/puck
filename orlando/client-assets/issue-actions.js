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
            // Remove every card for this issue across all the places it could
            // appear: per-doc-page panels (.issue-item) and the /issues list
            // (.issue-panel). Same close button class everywhere; the parent
            // wrapper differs by page.
            var selector = '.issue-close[data-issue-number="' + number + '"]';
            var anyRemoved = false;
            document.querySelectorAll(selector).forEach(function (b) {
                var wrapper = b.closest(".issue-item") || b.closest(".issue-panel");
                if (wrapper) { wrapper.remove(); anyRemoved = true; }
            });
            // No wrapper to remove (e.g. consistency.md renders close buttons
            // inline among markdown — there's no enclosing card). Reload so
            // the now-closed issue stops appearing in the dynamic listing.
            if (!anyRemoved) { window.location.reload(); return; }
            // For each per-doc panel that's now empty, drop the panel too and
            // update counts on panels that still have items.
            document.querySelectorAll(".issues-panel").forEach(function (panel) {
                var items = panel.querySelectorAll(".issue-item");
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
                var remaining = document.querySelectorAll(".issue-panel").length;
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

    /* ===== Comment form (on /issues) ===== */

    document.addEventListener("submit", function (e) {
        var form = e.target;
        if (!form.classList || !form.classList.contains("issue-comment-form")) return;
        e.preventDefault();

        var number = form.getAttribute("data-issue-number");
        if (!number) return;

        var ta     = form.querySelector("textarea[name=body]");
        var btn    = form.querySelector("button[type=submit]");
        var status = form.querySelector(".issue-comment-status");
        var body   = (ta && ta.value || "").trim();
        if (!body) {
            if (status) status.textContent = "Comment can't be empty.";
            return;
        }

        if (btn) { btn.disabled = true; btn.textContent = "Posting…"; }
        if (status) { status.textContent = ""; }

        postComment(number, body).then(function () {
            if (ta) ta.value = "";
            if (btn) { btn.disabled = false; btn.textContent = "Post comment"; }
            if (status) {
                status.textContent = "Posted ✓";
                status.classList.add("ok");
                setTimeout(function () {
                    status.textContent = "";
                    status.classList.remove("ok");
                }, 2500);
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
})();
