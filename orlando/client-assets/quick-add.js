// Quick-add form behavior.
//
// 1. Autofocus the textarea when a form is opened. HTML's `autofocus`
//    attribute only fires on initial page load and the form starts
//    hidden, so we wait for the toggle checkbox to flip on.
//
// 2. Clear any stale status from a previous submission when the form
//    re-opens.
//
// 3. Submit handling. The form POSTs to a shared hidden iframe
//    (name="qa-target"); we read the response from inside the iframe
//    (same-origin) to pull out the new issue's URL. On success we
//    reset the form, uncheck the toggle (collapsing the panel), and
//    leave the success status visible outside the panel.
//
// 4. Inject the newly-created issue as an issue-panel into the
//    top-of-page issues list, so the new issue shows up immediately
//    in the same format as /issues without requiring a page reload.
//    Creates the issues panel if the page doesn't yet have one.

(function () {
    var pendingForm = null;
    var BODY_PREVIEW_MAX = 280;

    // Each Quick-add panel is three sibling elements:
    //   <input.quick-add-toggle> + <div.quick-add-form> + <div.quick-add-status>
    // The status sits OUTSIDE the form panel so it stays visible after
    // the panel collapses on a successful submit.
    function formDivFor(form)   { return form.parentNode; }
    function toggleFor(form)    { return formDivFor(form).previousElementSibling; }
    function statusEl(form)     {
        var sib = formDivFor(form).nextElementSibling;
        return (sib && sib.classList && sib.classList.contains("quick-add-status"))
            ? sib : null;
    }
    function clearStatus(status) {
        if (!status) return;
        status.hidden = true;
        status.textContent = "";
        status.className = "quick-add-status";
    }

    function htmlEscape(s) {
        return String(s == null ? "" : s)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#39;");
    }
    function singleLine(s) {
        return String(s == null ? "" : s).replace(/\s+/g, " ").trim();
    }
    function truncate(s, max) {
        if (s.length <= max) return [s, false];
        return [s.slice(0, max), true];
    }
    function issueNumberFromUrl(url) {
        var m = /\/issues\/(\d+)\b/.exec(url || "");
        return m ? m[1] : null;
    }

    // Build an .issue-panel matching what orlando.issue_panel.render emits
    // on the server. Used to inject the just-created issue into the
    // top-of-page list.
    function renderPanelHtml(issue, opts) {
        opts = opts || {};
        var n     = issue.number || 0;
        var title = singleLine(issue.title || "(no title)");
        var body  = singleLine(issue.body || "");
        var t     = truncate(body, BODY_PREVIEW_MAX);
        var label = "Issue " + n;

        var html = ""
            + '<article class="issue-panel">'
            + '<header class="issue-panel-head">'
            + '<button type="button" class="issue-num-badge" data-copy="'
            +    htmlEscape(label) + '" title="Click to copy">'
            +    htmlEscape(label) + '</button>'
            + '<h2 class="issue-panel-title">' + htmlEscape(title) + '</h2>'
            + '</header>';

        // Section chip (this panel always lives in top-of-page list, so
        // show the section if the title has '§ Section ...' suffix).
        var sect = (title.match(/§\s*(.*?)\s*\(/) || title.match(/§\s*(.+)$/));
        if (sect && sect[1]) {
            html += '<div class="issue-panel-section">§ '
                  + htmlEscape(sect[1]) + '</div>';
        }

        if (t[0] !== "") {
            html += '<div class="issue-panel-body">' + htmlEscape(t[0])
                  + (t[1] ? "…" : "") + '</div>';
        }

        if (opts.canEdit) {
            html += '<details class="issue-comment-add">'
                  + '<summary>+ Comment</summary>'
                  + '<form class="issue-comment-form" data-issue-number="' + n + '">'
                  + '<textarea name="body" rows="3" required '
                  +   'placeholder="Comment to post to GitHub…"></textarea>'
                  + '<div class="issue-comment-actions">'
                  + '<button type="submit">Post comment</button>'
                  + '<span class="issue-comment-status"></span>'
                  + '</div></form></details>';
        }

        html += '<footer class="issue-panel-foot">';
        if (opts.canEdit) {
            html += '<button type="button" class="issue-close issue-panel-close" '
                  + 'data-issue-number="' + n + '">Close</button>';
        }
        html += '<a class="issue-panel-github" href="' + htmlEscape(issue.url || "#")
              + '" target="_blank" rel="noopener noreferrer">GitHub →</a>';
        html += '</footer></article>';
        return html;
    }

    // Find the page-level Open-issues <details> (the one Lua injects via
    // inject_issues_panel). Skip section-issues-panels — those are
    // anchor-scoped and would clutter the page-level list.
    function findTopPanel() {
        var all = document.querySelectorAll("details.issues-panel");
        for (var i = 0; i < all.length; i++) {
            if (!all[i].classList.contains("section-issues-panel")) {
                return all[i];
            }
        }
        return null;
    }

    // Create a fresh top-of-page Open-issues panel and inject it. Picks
    // the same insertion point as the server-side inject_issues_panel:
    // after the vibecode <details>, or after the first H1, else prepend.
    function createTopPanel() {
        var details = document.createElement("details");
        details.className = "issues-panel";
        details.open = true;
        details.innerHTML = '<summary>Open issues (0)</summary>'
                          + '<div class="issues-list"></div>';

        var vc = document.querySelector("details.vibecode");
        if (vc && vc.parentNode) {
            vc.parentNode.insertBefore(details, vc.nextSibling);
            return details;
        }
        var h1 = document.querySelector("h1");
        if (h1 && h1.parentNode) {
            h1.parentNode.insertBefore(details, h1.nextSibling);
            return details;
        }
        var body = document.body;
        body.insertBefore(details, body.firstChild);
        return details;
    }

    // Insert the new issue panel at the TOP of the list (most recent first).
    // Bump the summary count.
    function injectNewIssue(issue) {
        var panel = findTopPanel() || createTopPanel();
        var list  = panel.querySelector(".issues-list");
        if (!list) return;
        // Render assumes the submitter is allow-listed (they just submitted).
        var html = renderPanelHtml(issue, { canEdit: true });
        var tmp  = document.createElement("div");
        tmp.innerHTML = html;
        var article = tmp.firstChild;
        list.insertBefore(article, list.firstChild);

        // Bump count in the summary.
        var summary = panel.querySelector("summary");
        if (summary) {
            var count = list.querySelectorAll(".issue-panel").length;
            summary.textContent = "Open issues (" + count + ")";
        }
        // Open the panel so the new issue is visible.
        panel.open = true;
    }

    document.addEventListener("change", function (e) {
        var cb = e.target;
        if (!cb.classList || !cb.classList.contains("quick-add-toggle")) return;
        if (!cb.checked) return;
        var formDiv = cb.nextElementSibling;
        if (!formDiv) return;
        var status = formDiv.nextElementSibling;
        if (status && status.classList.contains("quick-add-status")) {
            clearStatus(status);
        }
        var ta = formDiv.querySelector("textarea");
        if (ta) ta.focus();
    });

    document.addEventListener("submit", function (e) {
        var form = e.target;
        if (form.getAttribute("target") !== "qa-target") return;
        pendingForm = form;
        var s = statusEl(form);
        if (s) {
            s.hidden = false;
            s.className = "quick-add-status pending";
            s.textContent = "Submitting…";
        }
    });

    window.addEventListener("DOMContentLoaded", function () {
        var iframe = document.querySelector('iframe[name="qa-target"]');
        if (!iframe) return;
        iframe.addEventListener("load", function () {
            if (!pendingForm) return;  // initial empty load — ignore
            var form = pendingForm;
            pendingForm = null;
            var s = statusEl(form);

            // Pull the new issue URL out of the iframe's response (the
            // server returns an HTML confirmation page with a single
            // github.com link to the new issue).
            var url = null;
            try {
                var doc = iframe.contentDocument;
                var link = doc && doc.querySelector('a[href*="github.com"]');
                if (link) url = link.href;
            } catch (_) {
                // shouldn't happen — same-origin
            }

            if (!url) {
                if (s) {
                    s.className = "quick-add-status failure";
                    s.textContent = "Submission failed. Check server logs.";
                    s.hidden = false;
                }
                return;
            }

            // Success: show the new-issue "Issue NNN" link in the
            // status area AND inject the issue panel into the page
            // list.
            var number = issueNumberFromUrl(url);

            // Read what user submitted before we reset the form.
            var titleInput = form.querySelector("input[name=title]");
            var bodyInput  = form.querySelector("textarea[name=body]");
            var issue = {
                number:   number ? parseInt(number, 10) : 0,
                title:    titleInput ? titleInput.value : "",
                body:     bodyInput  ? bodyInput.value  : "",
                url:      url,
                comments: [],
            };

            if (s) {
                var label = number ? ("Issue " + number) : "Issue submitted";
                s.className = "quick-add-status success";
                s.innerHTML = ""
                    + '<button type="button" class="issue-num-badge" '
                    +   'data-copy="' + htmlEscape(label) + '" '
                    +   'title="Click to copy">' + htmlEscape(label) + '</button>'
                    + ' <a href="' + htmlEscape(url) + '" '
                    +   'target="_blank" rel="noopener">' + htmlEscape(url) + '</a>';
                s.hidden = false;
            }

            if (number) {
                injectNewIssue(issue);
            }

            form.reset();
            var toggle = toggleFor(form);
            if (toggle && toggle.classList.contains("quick-add-toggle")) {
                toggle.checked = false;
            }
        });
    });
})();
