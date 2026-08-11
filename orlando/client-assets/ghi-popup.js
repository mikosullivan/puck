// Fill the popup form from the URL query params written by the opener,
// then intercept the submit so the popup itself doesn't navigate away —
// POST via fetch, parse the API's HTML confirmation page for the issue
// URL, and show an "Issue NNN" copy-badge + link in the status area
// (same shape as quick-add.js on doc pages, so issue-copy.js picks it
// up).

(function () {
	// Esc closes the popup — matches typical dialog affordance.
	document.addEventListener("keydown", function (e) {
		if (e.key === "Escape") {
			window.close();
		}
	});

	function htmlEscape(s) {
		return String(s == null ? "" : s)
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;")
			.replace(/'/g, "&#39;");
	}

	function issueNumberFromUrl(url) {
		var m = /\/issues\/(\d+)\b/.exec(url || "");
		return m ? m[1] : null;
	}

	// Prefill from query params.
	var params  = new URLSearchParams(window.location.search);
	var doc     = params.get("doc")     || "";
	var line    = params.get("line")    || "";
	var context = params.get("context") || "";
	var url     = params.get("url")     || "";
	var ships   = params.get("ships")   || "";
	var day1    = params.get("day1")    || "";
	var desc    = params.get("desc")    || "";

	// Generic mode: `doc` is present (source file the issue is against).
	// Legacy stdlib-review mode: no `doc`, hard-code the review doc + use
	// the ships / day1 body template.
	var titlePrefix, bodyText;

	if (doc) {
		// Title format: `File: <path>[:<line>][ — <context>]`
		titlePrefix = "File: " + doc;
		if (line) titlePrefix += ":" + line;
		if (context) titlePrefix += " — " + context;
		else if (url) titlePrefix += " — " + url;
		bodyText = desc;
	} else {
		titlePrefix = "File: ideas/caspian/stdlib-suggestions-review.md — " + url;
		bodyText =
			"URL: " + url + "\n" +
			"Ships: " + ships + "\n" +
			"Day 1: " + day1 + "\n\n" +
			desc;
	}

	var heading = document.getElementById("ghi-heading");
	if (heading) {
		var headingText;
		if (doc) {
			headingText = "File issue: " + doc + (line ? (":" + line) : "");
		} else {
			headingText = "File issue: " + url;
		}
		heading.textContent = headingText;
		document.title = headingText;
	}

	var titleInput = document.getElementById("ghi-title");
	if (titleInput) titleInput.value = titlePrefix;

	var bodyInput = document.getElementById("ghi-body");
	if (bodyInput) {
		bodyInput.value = bodyText;
		bodyInput.focus();
		var end = bodyInput.value.length;
		bodyInput.setSelectionRange(end, end);
	}

	// Intercept submit → fetch → render status.
	var form   = document.getElementById("ghi-form");
	var status = document.getElementById("ghi-status");
	if (!form || !status) return;

	form.addEventListener("submit", function (e) {
		e.preventDefault();

		status.hidden = false;
		status.className = "ghi-status pending";
		status.textContent = "Submitting…";

		var body = new URLSearchParams(new FormData(form));

		fetch(form.action, {
			method:  "POST",
			body:    body,
			headers: {"Accept": "text/html"},
			credentials: "same-origin",
		})
		.then(function (r) {
			if (!r.ok) throw new Error("HTTP " + r.status);
			return r.text();
		})
		.then(function (html) {
			// The API returns an HTML confirmation page with a single
			// github.com link to the new issue. Parse it out.
			var doc = new DOMParser().parseFromString(html, "text/html");
			var link = doc.querySelector('a[href*="github.com"]');
			var issueUrl = link ? link.href : null;
			var number   = issueNumberFromUrl(issueUrl);

			if (!issueUrl) {
				throw new Error("no issue URL in response");
			}

			var label = number ? ("Issue " + number) : "Issue submitted";
			status.className = "ghi-status success";
			status.innerHTML = ""
				+ '<button type="button" class="issue-num-badge" '
				+   'data-copy="' + htmlEscape(label) + '" '
				+   'title="Click to copy">' + htmlEscape(label) + '</button>'
				+ ' <a href="' + htmlEscape(issueUrl) + '" '
				+   'target="_blank" rel="noopener">'
				+   htmlEscape(issueUrl) + '</a>';

			form.reset();
		})
		.catch(function (err) {
			status.className = "ghi-status failure";
			status.textContent = "Submission failed: " + err.message;
		});
	});
})();
