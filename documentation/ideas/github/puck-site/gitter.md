# Gitter

~~~json
{"vibecode": {
	"doc": "github-gitter",
	"status": "V1.0 feature — initial scope is internal use only (renders puck.uno's docs from the mikosullivan/puck repo). Public multi-repo product is post-V1.",
	"v1_url": "puck.uno/documentation/ (same as today)",
	"future_url": "gitter.puck.uno (multi-repo, post-V1)",
	"shape": "Caspian class at V1; public web service post-V1",
	"parent": "../github.md"
}}
~~~

Gitter is a Caspian class for rendering GitHub-hosted documentation. **V1 scope is narrow**: an internal class that powers puck.uno's documentation surface, fetching content from `mikosullivan/puck` and rendering it through a single Orlando-look default skin. The visible URL stays at `puck.uno/documentation/` exactly as it is today.

The broader public-service ambition — `gitter.puck.uno` rendering any public GitHub repo with viewer-selectable skins, normalized diffs, in-place code formatting — is **post-V1**. We want to live with Gitter on our own site first before opening it to arbitrary repos.

## Why

GitHub's own browser is fine but generic. Docs that follow conventions — heavy markdown, nested directory trees, vibecode-style metadata, Caspian source — deserve a viewer tuned for those conventions. [Orlando](../../../misc/orlando.md) already does this for puck.uno; Gitter is the production Caspian-native replacement for Orlando's role on the site, plus the seed of a public service later.

It's also the delivery vehicle for Puck tooling that can't live inside github.com (see [github.md](../index.md)): vibecode-aware rendering, UNS link resolution, Caspian syntax highlighting, and — post-V1 — normalized diffs and in-place code formatting.

## Relationship to Orlando

Orlando is the experimental Lua HTTP server that currently serves puck.uno's docs from local files. **Orlando stays its own thing** — it does not get folded into Gitter, replaced by Gitter, or merged with it. Its purpose remains an experimental sandbox where Miko sees docs his way and surfaces feature ideas.

Gitter is built fresh in Caspian. Code from Orlando is fair game to borrow (markdown rendering, nav generation, vibecode rendering, etc.), but the implementations stay separate.

Once V1 Gitter is ready, it takes over the production serving of `puck.uno/documentation/`.

## Relationship to Donnie

[Donnie](https://puck.uno/documentation/ideas/dogberry/donnie) — the Dogberry service that serves a remote source as a website via Markie — does most of what Gitter needs at the machinery level: fetch from a remote source (often a GitHub repo), transform the content, cache by URL, serve on a domain. **V1 Gitter could plausibly be expressed as a Donnie configuration** rather than a separate service: a single Donnie site at `puck.uno/documentation/` backed by `mikosullivan/puck`, with a Markie vocabulary that renders markdown the Orlando way (vibecode panels, JSON highlighting, sidebar nav, open-issue panels).

The post-V1 "any public GitHub repo at `gitter.puck.uno/<owner>/<repo>/path`" vision is the only piece that doesn't fit Donnie's existing nickname-to-source binding — Gitter wants the source to be derived from the URL path, not registered ahead of time. Two ways to reconcile:

### Donnie gains URL-path source routing

Donnie acquires a routing mode where the source URL is derived from the request path according to a pattern (`gitter.puck.uno/<owner>/<repo>/<rest>` → `https://github.com/<owner>/<repo>/blob/main/<rest>`). Gitter stays a subset of Donnie; the new feature is a Donnie capability.

### Separate router in front of Donnie's machinery

A thin Gitter front-end synthesizes a per-request Donnie source binding, then delegates fetch/transform/cache/serve to Donnie's existing pipeline. Donnie doesn't need a new routing mode; Gitter owns the URL-to-source mapping.

Either way the machinery stays shared. The pieces genuinely unique to Gitter are the **docs-flavored Markie vocabulary** (markdown-to-HTML renderer with the docs panels and highlighting) and the **skin catalog** — both of which probably belong to Markie/Donnie as generic features, not Gitter-specific.

The Caspian-class facade (`%['gitter.puck.uno/<owner>/<repo>/path']`) still makes sense as a friendly entry point regardless of which routing approach wins.

## V1 scope

V1 Gitter must do:

- **Render `mikosullivan/puck` docs at `puck.uno/documentation/`.** Same URL as today; visible change for readers is minimal.
- **Fetch from GitHub** rather than reading local files. Aggressive per-commit-SHA caching is required for the site to feel responsive.
- **Match Orlando's current feature set.** Auto-generated sidebar nav with subdirs and files interleaved alphabetically, same-name index convention (`foo/foo.md` is `foo/`'s landing page), sentence-case titles, pretty markdown rendering with vibecode / JSON / Caspian syntax highlighting, extensionless URLs, server-rendered HTML per request, pages-double-as-plain-APIs, lightweight side panels.
- **Skin architecture from the start.** Renderer is built with data and presentation separated, so additional skins are cheap to add later. V1 ships one skin: the **Orlando-look default**.
- **"View on github.com" link** on every page, pointing at the corresponding `github.com/mikosullivan/puck/blob/main/...` URL.
- **"Open issue" links** per page and per section (Orlando's existing quick-add panel, ported).
- **Open-issues panel** at the top of each page (just below the vibecode block) listing every currently-open GitHub issue whose title starts with `File: <md_path>` — collapsible `<details>` element, collapsed by default; expand to see each issue's title, section, and full body. Lifted from Orlando.

V1 Gitter is a **Caspian class**, not a separate service. No public URL beyond `puck.uno/documentation/`. No public API.

## Implementation

Gitter is implemented in Caspian, running on the V1 Caspian web stack (Sammy / Touchstone — themselves Caspian-based). Because those tools are on their own V1 schedule, Gitter cannot land before they do. Orlando bridges the gap on the production site until then.

Code from Orlando — markdown rendering, nav generation, vibecode formatting — can be borrowed when building Gitter, but the two implementations stay separate.

## Post-V1 features

Sketched here so we don't lose the ideas. None of these are in V1.

### Public multi-repo product

`gitter.puck.uno` (subdomain) or `puck.uno/gitter` (subpath) lets any viewer browse any public GitHub repo through Gitter. Paste a URL like `gitter.puck.uno/<owner>/<repo>/path/to/page` or follow a link and get the Puck-flavored view. No install, no repo-owner buy-in required.

### Skin catalog

Additional skins beyond the V1 default. **"Git classic"** mimics github.com's look — useful for viewers who want Gitter's features but the visual familiarity of github.com. Other skins can follow. The skin authorship model (open submission, curated catalog, or both) is a separate question.

### Diff with normalization

Surfaced on any file view: pick two versions of the file — commit refs, tag names, branch tips, or arbitrary pasted content — and get a clean diff between them. Optional normalization layer: before diffing, both sides are run through a formatter so style differences don't pollute the result.

For Caspian files this uses the canonical Caspian→CJS transpiler followed by re-rendering with a default style — same architecture spelled out in [issue #56](https://github.com/mikosullivan/puck/issues/56). The standalone Differ proposal in [../../differ.md](../../differ.md) is the deeper design; Gitter is its hosting context. For other languages, Gitter could plug in third-party formatters (Prettier, gofmt, Black) where they exist, or fall back to raw diff with normalization disabled.

The viewer can toggle normalization off per view to see the raw diff as a sanity check.

### Per-block code formatting

When rendering markdown that contains fenced code blocks, each block in a language Gitter has a formatter for gets an inline "format" toggle. Clicking it reformats that block per the viewer's [style.json](../../../requirements/ecoverse/formatting/index.md).

- **Off by default.** Author-faithful display is the baseline.
- **Per-language sticky.** The preference is scoped per language: turning on the toggle on a JSON block flips formatting on for every JSON block on every page (and stays on across sessions until flipped off). Caspian and Python and the rest each have their own independent toggle state.
- **Reversible.** Once formatted, the toggle flips to "view source".

Caspian-specific extras (view-as-CJS, etc.) live in their own doc: [puck-site/caspian.md](caspian.md).

### Language coverage

Gitter offers per-block formatting for nearly every major language. The implementation strategy differs by language:

- **Native (parse-and-rebuild)** — languages we own the formatter for. Caspian uses the canonical Caspian→CJS transpiler followed by re-rendering (see [issue #56](https://github.com/mikosullivan/puck/issues/56)). JSON uses direct parse-and-emit. We write and maintain these implementations.
- **Off-the-shelf wrapping** — everything else. Gitter wraps mature community formatters (Prettier for JS / TS / HTML / CSS / Markdown, Black for Python, gofmt for Go, rustfmt for Rust, etc.) and feeds them the relevant settings from the viewer's `style.json` as far as each formatter supports them. We don't write our own parsers for these languages — we just integrate.

The format button appears for any language Gitter knows how to format, native or wrapped. The rare languages with no community formatter (obscure DSLs, ad-hoc scripts) fall back to syntax-highlight-only; languages Gitter can't even highlight render as plain text per the [parse-fail rule](../../../requirements/ecoverse/formatting/index.md#parse-fail-behavior).

### `gitpage` as a Puck object class

The natural extension of Gitter as a class: expose `gitpage` as a Puck-native object that can be instantiated in Caspian or fetched from the website. Remote methods on the object cover diff, render with a chosen skin, format blocks, etc.:

```caspian
$page = %['gitter.puck.uno/owner/repo/path']
$diff = $page.diff_against('v1.0')
$page.render(skin: 'git-classic')
```

Maps cleanly onto Puck's remote-objects-with-methods model. Deferred — V1 establishes the rendering surface; V1.x or later wraps it as a Puck object class.

## Open questions

All post-V1, surfacing when the public multi-repo product gets built:

- Subdomain (`gitter.puck.uno`) or subpath (`puck.uno/gitter`)? Subdomain reads cleaner and isolates resource use; subpath shares cookies and auth with the main site.
- Skin authorship model — open submission, curated catalog, or both?
- Per-viewer preference storage — cookie / localStorage (no account) or behind an optional Puck account for cross-device sync?
- Copy-paste behavior with formatting on — clipboard gets reformatted version, original, or both via a "copy source" alternative?
- Which formatters ship in the diff normalization layer at the public launch? Just Caspian (eats own dog food), or also Prettier / gofmt / Black?
- Discoverability — someone arriving via a github.com link doesn't know Gitter exists. Bookmarklet? Browser extension hint? Search ranking?
- Open-in-editor integrations (Codespaces, VS Code web)?

## Out of scope (for now)

- Write access. Gitter is read-only; editing happens on github.com.
- Private repos in the public product.
- Replacing github.com for native flows (issues, PRs, CI status). Gitter is a viewing lens.
- Non-GitHub forges (GitLab, Bitbucket, Codeberg). Could extend later, but the focus is GitHub.
