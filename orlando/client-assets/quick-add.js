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

(function () {
    var pendingForm = null;

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
            var url = null;
            try {
                var doc = iframe.contentDocument;
                var link = doc && doc.querySelector('a[href*="github.com"]');
                if (link) url = link.href;
            } catch (_) {
                // shouldn't happen — same-origin
            }
            if (url) {
                if (s) {
                    s.className = "quick-add-status success";
                    s.innerHTML = 'Issue submitted: <a href="' + url
                        + '" target="_blank" rel="noopener">' + url + '</a>';
                    s.hidden = false;
                }
                form.reset();
                var toggle = toggleFor(form);
                if (toggle && toggle.classList.contains("quick-add-toggle")) {
                    toggle.checked = false;
                }
            } else if (s) {
                s.className = "quick-add-status failure";
                s.textContent = "Submission failed. Check server logs.";
                s.hidden = false;
            }
        });
    });
})();
