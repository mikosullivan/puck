// Sidebar collapse toggle.
//
// The IIFE runs during head parsing (this script is loaded non-defer) so
// the sidebar-hidden class is on <html> before the body renders — no flash
// of visible sidebar when a user has previously hidden it.
//
// Click handlers bind at DOMContentLoaded after the buttons exist.

(function () {
	if (localStorage.getItem('sidebar-hidden') === 'true') {
		document.documentElement.classList.add('sidebar-hidden');
	}
})();

document.addEventListener('DOMContentLoaded', function () {
	var hideBtn = document.querySelector('.sidebar-hide-btn');
	var showBtn = document.querySelector('.sidebar-show-btn');

	if (hideBtn) {
		hideBtn.addEventListener('click', function () {
			document.documentElement.classList.add('sidebar-hidden');
			localStorage.setItem('sidebar-hidden', 'true');
		});
	}

	if (showBtn) {
		showBtn.addEventListener('click', function () {
			document.documentElement.classList.remove('sidebar-hidden');
			localStorage.setItem('sidebar-hidden', 'false');
		});
	}
});
