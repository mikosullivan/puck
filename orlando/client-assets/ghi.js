// ghi button: on click, open a popup window pointing at the ghi-form
// page (served by Orlando) with the row's data as query params. The
// popup page has its own CSS and JS to render and fill the form.
//
// Each .ghi-btn carries data-url / data-ships / data-day1 / data-desc.

(function () {
	document.addEventListener("click", function (e) {
		var btn = e.target.closest && e.target.closest(".ghi-btn");
		if (!btn) return;

		var params = new URLSearchParams({
			url:   btn.dataset.url   || "",
			ships: btn.dataset.ships || "",
			day1:  btn.dataset.day1  || "",
			desc:  btn.dataset.desc  || "",
		});
		var popupUrl = "/client-assets/ghi-form.html?" + params.toString();

		window.open(
			popupUrl,
			"ghi-popup",
			"width=900,height=720,resizable=yes,scrollbars=yes"
		);
	});
})();
