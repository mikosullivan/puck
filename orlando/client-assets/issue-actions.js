// Issue actions: per-card buttons in the open-issues panels.
//
// Today: one button — "Close" — that confirms with the viewer, POSTs
// to /api/close-issue, and removes the card on success. The fetch is
// form-encoded to match the other Orlando endpoints.

(function () {
    function postClose(number) {
        var body = "number=" + encodeURIComponent(String(number));
        return fetch("/api/close-issue", {
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
            // Remove every card for this issue across page-top and per-section
            // panels so the user doesn't see stale entries elsewhere on the page.
            var selector = '.issue-close[data-issue-number="' + number + '"]';
            document.querySelectorAll(selector).forEach(function (b) {
                var li = b.closest(".issue-item");
                if (li) li.remove();
            });
            // For each panel that's now empty, drop the panel too and update
            // counts on panels that still have items.
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
        }).catch(function (err) {
            btn.disabled = false;
            btn.textContent = "Close";
            window.alert("Close failed: " + (err && err.message ? err.message : err));
        });
    });
})();
