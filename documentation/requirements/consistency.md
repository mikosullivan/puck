# Consistency report — requirements/
<!--index: 01-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_consistency_report",
	"role": "dynamic dashboard of consistency problems within the authoritative requirements/ tree. Every tracked problem is a GitHub issue against the file it pertains to; this page renders an executive summary and the full text of each issue at request time.",
	"status": "dynamic — content reflects the live open-issue list at page-load time; no static problem list on this page",
	"audience": "humans and AI tooling tracking what's actively broken or unresolved in the new requirements tree",
	"audit_protocol": {
		"note": "the page itself is a fixed shell — title, vibecode, summary directive, listing directive. Auditing does NOT edit this file. It audits requirements/, files/closes GitHub issues, and Orlando re-renders the page from the live issue list at next page-load.",
		"trigger": "the AI runs an audit when Miko says 'audit consistency', 'update consistency', 'rewrite consistency.md', or equivalent",
		"steps": ["cleanup: query open issues whose title references a documentation/requirements/ path and close any that no longer apply (file deleted, file moved, fix already landed)",
			"discovery: walk every *.md under documentation/requirements/ and look for problems (see checks below)",
			"verification: probe suspect links via the running Orlando at http://127.0.0.1:8181/... to confirm 404 status before filing",
			"trivial broken links: if the audit finds a broken link AND the correct target is unambiguous (file moved to a known sibling, renamed concept with one new home, missing trailing slash, etc.), just fix the link inline — do NOT file an issue for the obvious one-step rewrite. This DOES NOT apply to outbound links — see the outbound-references rule below",
			"filing: one verbose GitHub issue per problem that survives the trivial-fix filter (see filing rules below)"],
		"checks": ["broken cross-references (links to files or anchors that 404)",
			"stale vibecode role fields (mentions of paths that have moved or been renamed)",
			"contradictions between docs claiming authority for the same concept",
			"stale wording (old file names, renamed concepts, removed sections)",
			"single-source-of-truth violations (two docs both defining the same concept rather than one defining and the other linking)",
			"outbound references — see the outbound_links rule below for the full policy"],
		"outbound_links": {
			"rule": "with rare, deliberately-marked exceptions, nothing in requirements/ should link to anything outside requirements/. Authoritative spec is self-contained.",
			"on_finding": "file an issue against the file that contains the outbound link. DO NOT auto-fix and DO NOT auto-mark as allowed — Miko decides per link whether to remove it, restructure, or mark it as an exception",
			"exception_marker": "<!-- outbound-link-allowed -->",
			"marker_placement": "on the SAME LINE as the link, immediately after it. The audit detects outbound links via a relative path that resolves outside documentation/requirements/, then skips any line whose plain text contains the marker substring",
			"example_marked_link": "see [the cli launcher](../../../lib/lua/caspian/cli.lua) <!-- outbound-link-allowed -->",
			"why_per_link_not_per_doc": "blanket-allowing a whole doc lets new outbound links creep in unnoticed. Per-link opt-in makes every exception visible and auditable",
			"issue_body_should_offer": ["restructure to keep the link inside requirements/",
				"drop the link, keep the textual mention as plain code or prose",
				"mark the line with <!-- outbound-link-allowed --> if the link is genuinely needed"]
		},
		"filing_rules": {
			"one_issue_per_problem": true,
			"title_format": "File: documentation/<full-path>.md § <Section Name>",
			"title_constraint": "MUST start with 'File: documentation/' so the github-issues-against directive picks it up; the path after must exist on disk or the directive filters the issue out",
			"body_tone": "verbose — the body is the full description rendered to readers on consistency.md, not a summary",
			"body_should_include": ["what's broken (the specific failure)",
				"where (line numbers, link text, exact path)",
				"correct fix (concrete replacement, not 'figure it out')",
				"why it matters (the impact, who's misled)",
				"how to confirm (curl command, file path check, or other observable)"]
		},
		"page_shape": {
			"do_not_edit_during_audit": "no audit step writes to this file; the page IS the dashboard, not a snapshot",
			"only_reasons_to_edit": ["the audit protocol itself changes (this vibecode)",
				"a directive name changes",
				"the page shell adds/removes a section"],
			"current_sections": ["H1 title + index directive", "this vibecode block",
				"github-issues-summary directive (top, before any prose)",
				"H2 'Open consistency issues'", "github-issues-against directive"],
			"do_not_add": ["static problem list", "snapshot_date field",
				"'what changed since last snapshot' section",
				"prose How-to-refresh section — the protocol lives in this vibecode"]
		},
		"directives": {
			"github-issues-summary: PATH/": "emits 'All clear' when zero matching issues, 'Attention — N open issues' otherwise; place above any prose so readers see status before content",
			"github-issues-against: PATH/": "renders each matching issue as H3 linked to GitHub + full body markdown + horizontal rule",
			"match_criteria": "issue title starts with 'File: documentation/<prefix>/' AND the referenced file currently exists on disk",
			"implementation": "orlando/lua/orlando/page.lua — process_github_issues_directives"
		}
	}
}}
~~~

<!-- github-issues-summary: requirements/ -->

## Open consistency issues

<!-- github-issues-against: requirements/ -->
