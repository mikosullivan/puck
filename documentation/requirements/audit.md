# Audit report
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_audit_report",
	"role": "dynamic dashboard of consistency problems within the authoritative requirements/ tree. Every tracked problem is a GitHub issue against the file it pertains to; this page renders an executive summary and the full text of each issue at request time. The audit *protocol* — what to do when Miko says 'run an audit' — lives in CLAUDE.md § Running an audit of requirements/, not here. This page is only the dashboard shell.",
	"status": "dynamic — content reflects the live open-issue list at page-load time; no static problem list on this page",
	"audience": "humans and AI tooling tracking what's actively broken or unresolved in the new requirements tree",
	"page_shape": {
		"do_not_edit_during_audit": "no audit step writes to this file; the page IS the dashboard, not a snapshot",
		"only_reasons_to_edit": ["a directive name changes",
			"the page shell adds/removes a section"],
		"current_sections": ["H1 title + index directive", "this vibecode block",
			"github-issues-summary directive (top, before any prose)",
			"H2 'Open consistency issues'", "github-issues-against directive"],
		"do_not_add": ["static problem list", "snapshot_date field",
			"'what changed since last snapshot' section",
			"prose How-to-refresh section — the protocol lives in CLAUDE.md"]
	},
	"directives": {
		"github-issues-summary: PATH/": "emits 'All clear' when zero matching issues, 'Attention — N open issues' otherwise; place above any prose so readers see status before content",
		"github-issues-against: PATH/": "renders each matching issue as H3 linked to GitHub + full body markdown + horizontal rule",
		"match_criteria": "issue title starts with 'File: documentation/<prefix>/' AND the referenced file currently exists on disk",
		"implementation": "orlando/lua/orlando/page.lua — process_github_issues_directives"
	}
}}
~~~

<!-- github-issues-summary: requirements/ -->

## Open consistency issues

<!-- github-issues-against: requirements/ -->
