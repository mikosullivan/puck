// ghi button: on click, open a popup window pointing at the ghi-form
// page (served by Orlando) with the row's data as query params. The
// popup page has its own CSS and JS to render and fill the form.
//
// Each .ghi-btn carries some subset of:
//   data-doc     — source file the issue is against (generic mode)
//   data-line    — 1-indexed source line of the marker (generic mode)
//   data-context — trimmed text of the marker's comment line (generic mode)
//   data-url     — url the issue is about (legacy stdlib-review use)
//   data-ships   — legacy stdlib-review
//   data-day1    — legacy stdlib-review
//   data-desc    — description text, prefilled into the body

(function () {
	document.addEventListener("click", function (e) {
		var btn = e.target.closest && e.target.closest(".ghi-btn");
		if (!btn) return;

		var params = new URLSearchParams({
			doc:     btn.dataset.doc     || "",
			line:    btn.dataset.line    || "",
			context: btn.dataset.context || "",
			url:     btn.dataset.url     || "",
			ships:   btn.dataset.ships   || "",
			day1:    btn.dataset.day1    || "",
			desc:    btn.dataset.desc    || "",
		});
		var popupUrl = "/client-assets/ghi-form.html?" + params.toString();

		window.open(
			popupUrl,
			"ghi-popup",
			"width=900,height=720,resizable=yes,scrollbars=yes"
		);
	});
})();
