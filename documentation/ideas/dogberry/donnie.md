# Donnie

~~~json
{"vibecode": {
	"doc": "donnie",
	"status": "brainstorm — code name only; Donnie names the specific Dogberry service that pairs a remote source with Markie expansion",
	"role": "productized 'register a domain, point at your Markie-DSL source, get a live website' offering built on top of Dogberry",
	"ties": "Dogberry provides the hosting infrastructure (domain registration, TLS, request routing, cache); Markie does the DSL→HTML transform; Donnie is the named bundle of the two",
	"example_universe": "shakespeare"
}}
~~~

**Donnie is the code name for the Dogberry service that uses Markie.** Dogberry is the broader hosting framework — domain registration, TLS, request routing, cache layer. Markie is the transformer. Donnie is what we call the specific productized bundle: register a domain, point at a remote source (a GitHub repo, a static-file host, anywhere that returns HTML/Markie-DSL on GET), get a live website with the DSL expanded on each request.

The split exists so Dogberry can eventually host other services (raw HTML pass-through, Caspian-rendered pages, future things) without "Dogberry" coming to mean "the Markie one." Donnie is the Markie one.

## What Donnie includes

~~~json
{"vibecode": {
	"section": "what_donnie_includes",
	"role": "the specific feature bundle that gets the Donnie name; everything else stays under plain Dogberry"
}}
~~~

### Source-bound domain

Every Donnie domain is bound to a remote source URL. Source is the canonical authoring location; Dogberry treats it as read-only and never owns the bytes.

### Markie expansion on fetch

Every fetched response runs through the Markie engine before caching. The cached entry is the post-Markie HTML, not the raw source. Skipping Markie is a configuration choice that moves the domain off Donnie and onto plain Dogberry.

Donnie consumes the Markie engine directly as an internal library, not via the `markie.uno` HTTP API — that service is the standalone single-document offering for clients who aren't going through Dogberry at all. Both surfaces share the same engine; see [Markie service vs Markie engine](https://puck.uno/documentation/ideas/markie/markie#markie-service-vs-markie-engine).

### Site-aware features

Donnie knows the customer's full source tree, so it can offer features that only make sense in a whole-site context. See [Site-aware features](#site-aware-features) below for the full list — navigation tags, site-wide template inheritance, shared partials.

### GitHub-friendly defaults

The expected V1 customer authors in a GitHub repo. Donnie's defaults (push-triggered cache purge, branch-as-environment routing, PAT-based private-repo access) optimize for that flow. Other source hosts work; GitHub is the design center.

### Identity shared with Markie and Dogberry

Same account system across all three. A customer signs up once and gets access to whichever combination they want.

## Site-aware features

~~~json
{"vibecode": {
	"section": "site_aware_features",
	"role": "the class of Markie-ish features that only make sense when the whole site is in view; Donnie has them because it sees the full source tree, standalone Markie does not"
}}
~~~

Pure Markie processes one document at a time and has no idea what else is in the customer's site. Donnie sees the source's full file tree (and optionally a customer-authored sitemap), which unlocks a class of features Markie alone can't offer.

### Navigation tags

Tags the customer drops into any page; Donnie expands them against the site structure before Markie hands off the final HTML.

#### `<breadcrumbs>`

Renders the trail from the site root to the current page. Each segment links to the corresponding section index. Generated from the current URL path.

#### `<prev-next>`

Renders prev / next links to sibling pages, in source order or sitemap order. Useful for sequenced content (tutorials, chapter-style docs).

#### `<section-nav>`

Renders a list of pages under the current page's parent. The standard sidebar-of-this-section pattern.

#### `<sitemap>`

Renders the full or scoped site tree. Useful for a sitemap page or a footer overview. Scope-limiting attributes (`under="/products"`, `depth="2"`) let the tag appear anywhere.

#### `<you-are-here>`

Inside any embedded nav, marks the current page so CSS can highlight it. Lets a customer hand-author a nav and still get the current-page indicator for free.

### Site-wide template inheritance

Register one base layout per domain; every page in the source is treated as a derived fragment of that base. Markie has a [per-call template inheritance](https://puck.uno/documentation/ideas/markie/markie#template-inheritance) API (submit base + derived together) — Donnie applies the site-wide form: base lives in the source repo once (e.g. `_layouts/base.html`), every page automatically inherits.

### Shared partials

A header, footer, sidebar, or any other reusable fragment lives once in the source (e.g. `_partials/header.md`) and any page can reference it. Markie's [local file includes](https://puck.uno/documentation/ideas/markie/markie#local-file-includes) handle the per-call form; Donnie's site-wide form lets partials be referenced from any page without bundling them into the request.

### Structure source

Two options for where Donnie learns the site's structure.

#### Implicit file tree

Donnie reads the source's file/directory layout and uses that as the navigation order. Zero-config; assumes the file tree maps cleanly to navigation.

#### Explicit sitemap

The customer authors a `sitemap.json` (or similar) at the source root. Gives full control over order, grouping, hidden pages, and external links. Adds a config file to author.

Both probably supported, with one as the default. Default unsettled — see [Open questions](#open-questions).

## What stays under Dogberry

~~~json
{"vibecode": {
	"section": "stays_under_dogberry",
	"role": "the infrastructure layer Donnie depends on but doesn't own; lives in dogberry.md, not here"
}}
~~~

Domain registration mechanics, DNS pointing, TLS issuance and renewal, the cache layer itself, the per-domain dashboard, source fetch policy, the failure-mode behaviors. See [dogberry.md](https://puck.uno/documentation/ideas/dogberry/dogberry) for those — Donnie inherits them all.

## Naming and branding

~~~json
{"vibecode": {
	"section": "naming",
	"role": "Donnie is a code name; the customer-facing product name is TBD"
}}
~~~

Donnie is internal shorthand, not necessarily the customer-facing name. The combined service might launch as "Markie Hosting," "Markie Sites," "Dogberry for Markie," or under its own product name. Donnie keeps the conversation precise while the marketing question is open.

## Open questions

### Customer-facing name

Is Donnie also the public name, or do we ship under a different label? The code name is fine for internal docs but the customer story may want something more descriptive.

### Boundary between Donnie and plain Dogberry

A customer could plausibly want Markie expansion on some paths and raw pass-through on others within the same domain. Is that still Donnie? Or does the moment a domain mixes modes push it into "plain Dogberry with Markie configured per-path"?

### Default structure source

Both [implicit file tree and explicit sitemap](#structure-source) probably ship — but which is the default when a customer registers a domain and authors nothing extra? Implicit is zero-config; explicit gives the customer full control. Decide which we lead with.

### Default cache TTL

Markie expansion is more expensive than raw proxying, so the cache matters more for Donnie than for plain Dogberry. Default TTL should probably be higher for Donnie than the Dogberry default. Exact number TBD.

### Markie config location

Per-domain Dogberry-side config? A `.markie.json` in the source repo? Both? The repo-side option keeps authoring and config in one place; the Dogberry-side option keeps secrets and infra-y settings out of the public repo.
