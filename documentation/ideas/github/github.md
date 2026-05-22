# GitHub integration

~~~json
{"vibecode": {
	"doc": "github-integration",
	"status": "brainstorm — landing page for ideas about Puck/GitHub integration",
	"purpose": "Sketch the realistic shapes for adding Charlie-aware features to the GitHub browsing experience, given GitHub's deliberate limits on UI extension",
	"sibling_docs": ["differ.md is the first concrete proposal in this space"]
}}
~~~

Brainstorm landing page for Puck/GitHub integration ideas. Companion to the broader [ideas/](../ideas.md) brainstorm queue.

## The constraint

GitHub deliberately does not allow repo owners to push UI extensions, JavaScript, or styling into the github.com pages of their own repo. Their integration surface is designed to keep github.com under GitHub's control.

What GitHub *does* offer:

- **GitHub Apps** — installed by org/repo owners, run on your infrastructure, interact via webhooks + API. Can post comments, set commit statuses, file checks. No UI injection.
- **GitHub Actions** — server-side automation in GitHub's CI. PR annotations, status checks. No page-level UI.
- **Checks API** — custom check runs with summary text and inline diff annotations. Small, fixed UI surface.
- **GitHub Pages** — host a static site at `<user>.github.io/<repo>`. Separate URL, not embedded in github.com.

What can actually rewrite the github.com UI: **browser extensions** installed by the *viewer*, not the repo owner.

## Realistic shapes for Puck on GitHub

Three places Charlie-aware features can live:

### 1. External web service

A separate domain (e.g. `puck.uno/github/...` or `differ.puck.uno/...`) that takes a github.com URL as input and renders a Puck-flavored view of it. Viewer reaches it via a bookmarklet, browser extension redirect, or just bookmarking it manually.

Examples: [Differ](../differ.md), a hypothetical Charlie-aware blame viewer, a vibecode-aware README renderer.

### 2. Browser extension

An opt-in extension the viewer installs that rewrites github.com pages directly: syntax-highlighting `.charlie` files, rendering `%vibecode` blocks specially, resolving UNS references to live links, replacing diff views with normalized diffs.

Each viewer chooses to install. The repo owner can't push it.

### 3. GitHub App (server-side only)

For things that fit GitHub's native surface: PR-side checks (Charlie syntax errors, Bryton failures), comment bots, status checks. No UI injection but still useful for ecosystem-side validation.

## Charlie-aware things worth doing

- **Syntax highlighting** for `.charlie` files in source view and diffs (browser extension only — GitHub's own highlighter is Linguist-controlled, and Linguist won't know Charlie for a while).
- **Vibecode block rendering** — pretty-print the JSON inside `%vibecode <<EOF ... EOF`, possibly collapsible.
- **Normalized diffs** — see [Differ](../differ.md).
- **UNS link resolution** — turn `puck.uno/color` references in source into clickable links pointing at the canonical doc.
- **`.charlie` file preview** in the file tree popover, formatted to viewer's `style.json`.
- **Bryton test result badges** in PR view, fed by a GitHub Action.

## Open questions

- One umbrella "Puck for GitHub" browser extension that does everything, or several focused extensions the viewer composes?
- Bookmarklet vs full browser extension for redirecting to external web services? (Bookmarklet has no install friction; extension can intercept transparently.)
- Should there be a GitHub App for repo-side validation (syntax checks, Bryton runs) even though it can't inject UI? Probably yes once Charlie is real.
- Hosting model for the external web service — `puck.uno/...` subpaths? Separate subdomain per tool (`differ.puck.uno`, `blame.puck.uno`)? Single SPA?
- For browser-extension features that pull data from a server (e.g. UNS lookups), where does the server live and how does it handle rate limits?

## Out of scope (for now)

- Anything that requires repo-owner-controlled UI injection on github.com. Doesn't exist; don't design for it.
- Replacing GitHub for repo hosting. Puck integrates with GitHub; it doesn't compete with it.
