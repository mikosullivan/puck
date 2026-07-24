# Robinson

~~~vibecode
{"vibecode": {
	"doc": "robinson",
	"role": "spec for puck.uno/robinson, a filesystem-tree HTTP server where page files live in directory trees and URL paths map to file paths; library-resolved through Puck, built on Touchstone",
	"key_concepts": ["filesystem_tree_server", "url_to_file_mapping", "library_resolved",
		"touchstone_descendant", "multi_site_dispatch", "directory_handler_trees"]
}}
~~~

`puck.uno/robinson` — a filesystem-tree HTTP server. Page files
live in directory trees; URL paths map to file paths. Designed
for content-shaped sites where each URL corresponds to a file.

**Robinson is not bundled with Puck.** It's a **library available
through Puck** — when Caspian code references
`%['puck.uno/robinson']`, Puck's resolver fetches it from its URL
source on first use and caches it locally; subsequent references
hit the cache. Programs that don't use Robinson never pull it in.
See [puck.md](../../requirements/puck/index.md) for the resolution + caching
model that governs all library resolution.

Built on [Touchstone](../../requirements/network/http/server/touchstone/index.md) (which **does** ship with
Puck), Robinson inherits the transaction model, request/response
objects, sessions, body buffering, the handler chain, CSRF guard,
CSP, and the response constructor. Robinson adds multi-site
dispatch, directory-handler trees (pages, factory, admin), and
content-as-files semantics on top.

Named after a Ruby library still running unotate.com, itself
named after the author's old high school.

---

## Status

Spec in development. **Robinson is not in core and not required
for launch day.** This document captures the design well enough
to see how it fits with Sammy and Touchstone; details that
need filling in are flagged. The
[Robinson wishlist § Robinson Handler (Filesystem-Tree Pages)](robinson-wishlist.md#robinson-handler-filesystem-tree-pages)
holds earlier-thinking material that this spec consolidates and
in places supersedes.

---

## Architecture

A Robinson server lives in a directory. That directory contains
a `server.json` listing the sites it serves; each site lives in
its own subdirectory and contains its own `site.json` plus one
or more **directory trees** of content.

```
robinson_server/                  ← server root
├─ server.json                   ← lists sites
└─ sites/
   └─ borg/                     ← one site (nickname "borg")
      ├─ site.json             ← per-site config
      ├─ pages/                ← main content tree
      ├─ factory/              ← built-in fallback content
      └─ admin/                ← optional admin pages (opt-in)
```

The runtime structure: Robinson is a Touchstone subclass that
inherits the full handler chain. Each site is implemented as a
sub-chain of Handlers; at request time, Robinson dispatches by
`Host` header to the matching site, then walks the site's chain.

```
$server.handlers (Robinson default stack):
  1. Reserved-prefix blocker    (404s any /robinson.* request)
  2. Domain-canonicalizer       (301-redirects non-canonical domains)
  3. Site dispatcher            (routes by Host to a site's sub-chain)

Per-site sub-chain (the "directory handlers"):
  1. pages/      handler         (developer's main tree)
  2. admin/      handler         (if admin is enabled in site.json)
  3. factory/    handler         (built-in fallback content)
```

Each entry is a regular Touchstone Handler — same
`before` / `process` / `after` interface every other Handler
uses. Developers can insert their own Handlers anywhere (auth,
CORS, metrics, etc.). **Robinson and Sammy Handlers are
interchangeable**; in principle you can install Sammy
path-selector Handlers alongside Robinson directory Handlers in
the same server. Whether that's a feature or a footgun is TBD.

### Directory handlers

A directory handler is a Touchstone Handler bound to one
directory. On a request, it searches its directory for a file
matching the request and either returns a response or declines
(returns null). The next directory handler tries.

Each site has **at least one** directory handler (its `pages/`
tree); the factory handler is implicitly added; the admin
handler is opt-in. Site authors can add more directory handlers
via `site.json` (mechanism TBD).

**Zero directory handlers is a configuration error.** A site
with no directory handlers can't serve content; Robinson refuses
to start such a site with a clear error message.

### Match patterns

A directory handler resolves the request path to a file using
**one glob pass** that expands the path against two rules:

1. **Exact match beats placeholder** at each segment.
   Brace-expansion-style: `{literal, robinson.placeholder}` at
   every step. The first existing file in iteration order wins,
   so literal candidates always come before placeholder
   candidates.
2. **Extension elision** for `.casp` files. The terminal
   segment of the glob includes both with-`.casp` and
   without-`.casp` variants. A request for `/foo` matches
   both `pages/foo.casp` and `pages/foo`, with the former
   tried first.

Concrete example. Request `/plays/hamlet/act-3/scene-1` against
the `pages/` handler expands to:

```
pages/{plays,robinson.placeholder}/{hamlet,robinson.placeholder}/{act-3,robinson.placeholder}/{scene-1.casp,robinson.placeholder.casp,scene-1,robinson.placeholder}
```

That's 2 × 2 × 2 × 4 = 32 candidates. Robinson iterates them in
the order brace expansion produces (literal-first per segment;
`.casp`-with-elision before bare-static within the terminal),
testing each against the filesystem. First hit wins. If nothing
matches, the handler declines and the next directory handler in
the chain gets a turn.

**Candidate count grows as 2^depth × terminal-options.** A
6-segment URL is ~256 candidates. Filesystem `stat` is cheap;
this is fine in practice. If real-world load hits a pain point,
a future optimization can short-circuit on an exact-literal match
before doing the full expansion. For now, one glob pass keeps the
implementation simple — no need to optimize ahead of measurement.

**Directory-index resolution is a separate rule.** If the glob
above produces nothing and the request is for a directory (or
the literal path is a directory), the handler then looks for an
index file inside that directory by priority (`index.casp`,
`index.html`, ...). Priority list TBD.

### The three built-in trees

- **`pages/`** — the developer's main content. URL `/foo` looks
  here first. This is the tree most developers think of as "the
  site."
- **`factory/`** — built-in fallback content shipped with
  Robinson. Holds the [welcome page](#empty-site-welcome-page) for
  empty sites, the [factory message templates](#factory-messages),
  and any other defaults. Site authors override by putting their
  version in `pages/` (or another higher-priority tree).
- **`admin/`** — Robinson's built-in admin pages (login, logout,
  future log viewers). Opt-in via `site.json`; URL-prefixed (see
  [Admin tree](#admin-tree)).

Three trees, one rule: search them in chain order, first match
wins. The "site override" / "factory fallback" / "admin pages"
mechanisms aren't special cases — they're just chain order.

---

## Quick example

```
$server = %['puck.uno/robinson'].new(dir: $jail)
$server.run()
```

`$dir` is a [jail](../../requirements/built-in-classes/filesystem.md) over the Robinson
server's root directory, with `read + execute` permission.
Robinson reads `server.json` from there, loads each listed site,
and starts dispatching.

---

## What's in scope

Content-as-files HTTP serving with filesystem-tree-is-routing:

- **Multi-site dispatch** via `server.json`.
- **Canonical domain redirects** declared by domain order in
  `server.json`.
- **Reserved filename prefix** (`robinson.*`) blocked from HTTP.
- **Page files** (`.casp`) invoked per request to produce
  responses.
- **Three built-in trees** per site: `pages/`, `factory/`,
  optional `admin/`.
- **Factory message pages** for 4xx/5xx, overridable by
  higher-priority trees.
- **Empty-site welcome page** from the factory tree.
- **Admin authentication** (opt-in) with login/logout.
- **Admin-visible error reporting** — full Jasmine log inline on
  the error page when `$transaction.admin` is truthy.

---

## `server.json`

Lives at the Robinson server's root directory. Lists every site
the server hosts.

```json
{
    "sites": {
        "borg": {
            "dir": "sites/borg",
            "domains": ["www.borg.com", "borg.com"]
        }
    }
}
```

- **`sites`** — hash of site configurations. Each key is a
  **nickname** (free-form, used internally; not exposed via
  HTTP).
- For each site:
  - **`dir`** — path to the site's directory (relative to the
    server root, or absolute).
  - **`domains`** — ordered array of domains the site claims.
    **First entry is canonical.** Requests on any other listed
    domain get a 301 permanent redirect to the canonical (same
    path, same query).

**No wildcards or regex** in domains. Every domain is listed
explicitly.

Open:
- Overlapping domains across sites: probably startup error.
- Unknown-domain requests: probably decline (404).
- Other server-level keys: logging config, default per-site
  options, etc. — TBD as needs surface.

---

## `site.json`

Lives in each site's directory. Per-site configuration.

```json
{
    "admin": {
        "url_prefix": "/r-admin/",
        "users": {
            "stuart": "<encrypted password>",
            "miko": "<encrypted password>"
        }
    }
}
```

Currently the only documented section is `admin`. More will
surface as needed (per-site CSP defaults, custom directory
handlers, etc.).

Both `server.json` and `site.json` are deliberately small — the
expectation is that most sites need almost no config.

---

## Pages tree

The `pages/` directory under a site is the primary content
tree. URL paths map to files within it.

### Page file contract

A `.casp` file in the tree is a page file. Its last
expression must be a class inheriting from
`puck.uno/robinson/page` with a `process` method:

```
class
    inherits 'puck.uno/robinson/page'

    function process($request) do
        response.html(200, '<h1>Hello from ' + $request.path + '</h1>')
    end
end
```

Robinson invokes the file (via Caspian's
[file-invocation model](../../requirements/modules.md)), takes the
returned class, instantiates it, calls `process($request)`, and
uses the returned response. The class has no URL — its identity
is its location in the tree.

**No caching in v1.** Every request re-invokes the file from
disk. The class is rebuilt; a fresh instance is constructed
each request. Slower in absolute terms, but the implementation
stays simple and file changes are picked up immediately
(useful in dev mode without a separate reload trigger). OS-level
filesystem caching mitigates the disk-read cost in practice.
Class-level caching is planned for later; the design space is
deferred.

Non-`.casp` files (HTML, CSS, JS, images, etc.) are served
as-is, with content type inferred from extension (via
[Touchstone's factory map](../../requirements/network/http/server/touchstone/index.md#content-type-factory-defaults)).

### Path resolution

URL → file via the directory handler's jail. The site root is a
jail; path resolution goes through `$jail.use_path`, which both
validates and normalizes. Robinson stays out of normalization.

Trailing slashes are significant. File-request on a directory
triggers a **302 redirect** to the slash form. Detailed
resolution table belongs in the (deferred) match-patterns
section.

Directory traversal is not Robinson's concern — the jail refuses
anything outside root.

### Reserved filename prefix: `robinson.*`

Any request whose path contains a segment starting with
`robinson.` returns 404, regardless of whether the file exists.
Internal artifacts (config files, state, scratch content) live
under that prefix and are blocked from HTTP. Files at those
paths may exist on disk and be used by Robinson internally; the
prohibition is on **request boundary** access only.

This rule runs in a dedicated Handler at the front of the chain.
Not overridable.

---

## Factory tree

Built-in content shipped with Robinson, sitting at the lowest
priority in each site's chain. Provides:

- **Empty-site welcome page** for the bounded "site has no
  servable files" case.
- **Factory message templates** (`message.html`, `message.svg`,
  `message.json`, `message.txt`) for 4xx/5xx responses.

Both are just files in the factory tree; the higher-priority
trees (developer's `pages/`, optional `admin/`) override by
holding files at the same paths.

### Empty-site welcome page

When a site's `pages/` tree is genuinely empty, requests fall
through to the factory and hit the welcome page. First-run
convenience: confirms Robinson is alive on the right host.

**Bounding rule.** The welcome page appears only when `pages/`
is empty. The moment any file lands there, this stops being the
fallback for any path the developer added content for — missing
URLs hit factory message pages (404) normally.

**Content is deliberately minimal:** just the requested host.
No site root path, no version, no request path. Anything more
is potential info leakage on a misconfigured production
deployment.

### Factory messages

Robinson ships one parameterized template per content type for
non-200 responses (HTML, SVG, JSON, text). Each template has
placeholders for the status code and message string.

**Per-site overrides** happen by virtue of the chain: drop your
version in `pages/messages/message.html` (or wherever) and it
matches before the factory version. No special override
mechanism — just dir handler priority.

**Feature lock**: this subsystem is closed to new features. The
previous Dogberry iteration over-customized messages; this spec
is deliberately constrained.

**Content negotiation** for non-200 responses:

1. Image-only Accept → SVG
2. JSON-accepting → JSON
3. Plain-text-accepting → text
4. Anything else → HTML

If nothing matches, HTML anyway.

**JSON shape: no coddling.** `{"status": <code>, "message": "<text>"}`
and that's it. HTTP status is the canonical error signal;
clients that don't check it made that choice.

**Admin exception placeholder.** `message.html` includes a
placeholder filled in for authenticated admins only — the full
Jasmine log for the request. Stack traces visible to operators
debugging, never to public clients. See
[Error handling](#error-handling) for details.

---

## Concurrency

**Robinson is single-threaded. One request at a time.** Same
model as Sammy — inherits the simplicity and the constraints.
Caspian is single-threaded by design; Robinson doesn't depart
from that.

Scaling beyond one request at a time is process-level:

- **Externally supervised.** Run N Robinson processes behind a
  load balancer or per-Unix-socket, supervised by the host's
  process manager (systemd, k8s, etc.).
- **Forking add-on.** Install the forking pool add-on (the
  same one Sammy offers) — manages a prefork worker pool
  from a single `$server.run`. Each worker is itself a
  single-threaded Robinson process. Opt-in download, not core.

What this rules out: long-polling, WebSockets, streaming
responses, in-process background work. Same trade-offs as
Sammy. The framework is designed for sites that need
ordinary HTTP request/response, where a multi-process scaling
strategy is sufficient.

---

## Target/content cascade

**Status: hazy. Design captured below, but the rules need
more work before implementation.** Goes in as a sketch for
later refinement.

Robinson assembles each response from a **cascade of HTML
fragments** — a factory default, optional per-directory
`robinson.html` files at each level above the page, and the
page file's own response. Each layer fits into the previous
one via two custom tags: `<target>` (placeholder for incoming
content) and `<content>` (content destined for a target).

This is HTML-as-templating without inventing a separate
template syntax — just two extra tags on top of HTML5.

### Why

The classic shared-layout problem: every page on a site shares
a header, footer, navigation, maybe a sidebar. Without a
mechanism, the developer copy-pastes that into every page (a
nightmare) or invents a template engine (more inventory). The
target/content cascade gives shared layout for free, using HTML
shapes the developer already knows.

### The cascade

For a request to `/blog/posts/my-post`, layers are assembled
in this order:

1. **Factory default** (ships with Robinson).
2. **`/robinson.html`** (site root, if present).
3. **`/blog/robinson.html`** (if present).
4. **`/blog/posts/robinson.html`** (if present).
5. **The page file's response** (the leaf).

Each layer fits into the layer above. `robinson.html` files
are real on disk but blocked from HTTP requests by the
[reserved-prefix rule](#reserved-filename-prefix-robinson).

### Factory default

```
<html>
<head></head>
<body>
<target>
</body>
</html>
```

One unnamed `<target>` in the body. Every site starts with this
as the outermost layer.

### `<target>` and `<content>`

Two custom tags (additions to the HTML5 schema for sites that
opt into them):

- **`<target>`** — placeholder for content from below. May
  have an `id` attribute to name it.
- **`<content>`** — content destined for a target. May have a
  `target` attribute giving the id to fill.

```
<!-- robinson.html, contributes a header/footer wrap -->
<header>Site nav</header>
<target>
<footer>Site footer</footer>
```

The next-level layer's `<content>` (with no target attribute)
fills the unnamed target above.

### Default targets and contents (unnamed)

A `<target>` with no `id` is the **default target** of its
layer. An `<content>` with no `target` attribute fills the
default target.

```
<!-- this layer -->
<header>Logo</header>
<target>
<footer>©</footer>

<!-- next layer's content -->
<content>
   <h1>Page content</h1>
</content>
```

### Named targets and contents

For multi-slot layouts, name the targets and pair contents by id:

```
<!-- this layer -->
<main><target id="main"></main>
<aside><target id="sidebar"></aside>

<!-- next layer -->
<content target="main">
   <h1>Article</h1>
</content>
<content target="sidebar">
   <p>Related posts</p>
</content>
```

### Page file response: auto-content

The page file's response is plain HTML — no `<content>` wrapping
required. Robinson treats the whole response as an unnamed
content targeting the deepest layer's default target:

```
# in a page file's process method:
response.html(200, '<h1>Hello</h1><p>...</p>')

# Robinson treats this as if it were:
# <content><h1>Hello</h1><p>...</p></content>
```

If the page wants to fill **named** targets, it returns
explicit `<content>` tags. The implicit auto-content only fires
when the response has no `<content>` tags of its own.

### `<replace>` for overrides

Sometimes a layer needs to **remove** an inherited block, not
just fill it. The `<replace>` tag empties the named target
entirely (target and its surrounding context get stripped):

```
<replace target="sidebar"></replace>
```

After the cascade, the `<aside><target id="sidebar"></aside>`
block from the upstream layer is gone — not just empty, but
removed from the document. Useful for "this page has no
sidebar."

### `$request.uma`

When a handler accesses `$request.uma`, it gets the assembled
Uma document for the current request — factory + cascade +
page response, target/content resolved into one document. The
handler can manipulate it further (set page title, modify
elements, add metadata) before serialization.

> **Uma spec status (2026-05-17)**: Uma is currently brainstormed in
> [`documentation/ideas/uma/index.md`](uma/index.md), not yet
> promoted to canonical. Robinson's target/content cascade and the
> `$request.uma` interface depend on Uma being canonical before
> Robinson can be implemented. Listed as a Robinson prerequisite.

### Validation: warnings on assembly issues

Cascade assembly catches a few common slipups:

| Situation | Warning class | Effect |
|---|---|---|
| `<content>` with target attribute that has no matching `<target>` | `puck.uno/robinson/warning/orphan_content` | Content element dropped |
| `<content>` with no target attribute, but no default `<target>` upstream | `puck.uno/robinson/warning/orphan_content` | Content element dropped |
| `<target>` that no `<content>` filled | `puck.uno/robinson/warning/unfilled_target` | Target element stripped from response |
| Multiple unnamed `<target>`s at the same layer | `puck.uno/robinson/warning/multiple_default_targets` | Only the first acts as default; later ones unfilled |

All warnings flow through Jasmine via the entry-heed mechanism.

### Final sweep

Before serialization, Robinson scans the assembled document
for any **leftover `<content>` or `<target>` tags**:

- Leftover `<content>` — the orphan-content warning fires (above);
  the element is stripped.
- Leftover `<target>` — the unfilled-target warning fires;
  the element is stripped.

No `<content>` or `<target>` tags ever leak to the rendered HTML.

### Caching

Each `robinson.html` is parsed to an Uma document at first use
and cached. File-watcher invalidates the cache when the file
changes (dev mode). Production: parsed at server start,
retained for process lifetime unless a reload signal fires.

Per-request work is just the target/content composition — walk
the cached layer documents, run the content resolution, emit
the final HTML. Fast in practice for typical cascade depths.

### What still needs work

This design is captured for refinement. Specific gaps:

- **Multiple unnamed targets in one layer.** Spec'd as a
  warning, but the right answer might be different — maybe
  multiple unnamed targets are fine and contents resolve to
  them in order. Or maybe it should be a hard error. TBD.
- **What if a `robinson.html` has only contents, no targets?**
  It contributes content but nothing below it can extend the
  layout. Probably fine, but worth pinning.
- **Cross-level content targeting.** Could a deeply
  nested `<content>` target a faraway upstream target by name?
  Probably yes (named targets aren't lexically scoped), but
  the rules need formalizing.
- **The interaction with the Uma builder API.** A page file
  using `$uma.body.tag(...)` rather than returning raw HTML
  — does the resulting Uma tree go through the same cascade?
  Probably yes; the page response is the page response
  regardless of how it was constructed.
- **Performance bounds.** What's a reasonable cascade-depth
  limit? Probably uncapped in practice but worth measuring.

---

## CSS handler

~~~vibecode
{"vibecode": {
	"section": "css_handler",
	"role": "Robinson's handler for .css files; supports query-param scoping that rewrites selectors so one source can serve multiple namespaces",
	"key_feature": "?base=X transforms every selector to .X <selector> for descendant scoping"
}}
~~~

Robinson's `.css` handler serves stylesheets verbatim by default. When a request includes the `base` query parameter, the handler rewrites every selector to be a descendant of the named class.

### `?base=X`

Request `https://puck.uno/jqmin.css?base=foo` and the handler reads jqmin.css, prepends `.foo ` (with a space) to every selector, and serves the result.

Original:

```css
.custom-checkbox > input { display: none }
```

Scoped:

```css
.foo .custom-checkbox > input { display: none }
```

Use case: drop the same stylesheet into a page that already has its own `.custom-checkbox` (or any other collision-prone class) by scoping each include under a distinct ancestor class. Two copies of the same stylesheet under different bases coexist on one page without interfering.

### Transformation rules

#### Comma-separated selector lists

Each piece in a comma list gets prefixed independently.

```css
.foo, .bar { ... }
```

becomes

```css
.X .foo, .X .bar { ... }
```

#### Media queries and conditional groups

The `@media` (and `@supports`, `@container`) wrapper passes through unchanged; selectors inside get prefixed:

```css
@media print {
	.foo { display: none }
}
```

becomes

```css
@media print {
	.X .foo { display: none }
}
```

#### Non-selector at-rules

`@keyframes`, `@font-face`, `@import`, `@charset`, `@page` pass through unmodified. They don't contain selectors in the conventional sense.

#### Body-rooted selectors

Selectors starting with `body`, `html`, or `:root` become inert after prefixing — `.X body.stickies` can never match because `body` isn't a descendant of anything within itself. The handler emits the rewritten rule silently; the rule simply never applies. CSS authors using body-rooted rules can choose to serve those files unscoped.

### Caching

Each `(file, base)` pair is a distinct URL, so browser and CDN caches handle the per-base variants automatically. No internal cache needed; the handler does its rewrite per request and lets the URL key the result.

### Generalization

The `?base=X` feature is a property of Robinson's CSS handler, not of any specific stylesheet. Any `.css` file served through Robinson takes the query parameter — jqmin.css, peaseblossom.css, future custom stylesheets, all get the same treatment without per-file configuration.

---

## Admin tree

**Opt-in.** A site has no admin tree unless `site.json` declares
one:

```json
{
    "admin": {
        "url_prefix": "/r-admin/",
        "users": {
            "stuart": "<encrypted password>",
            "miko": "<encrypted password>"
        }
    }
}
```

When enabled, Robinson adds the admin tree to the site's chain
between `pages/` and `factory/`. URLs under `url_prefix` are
routed to it; anything else falls through to the next handler.

### URL prefix

Default `/r-admin/` (configurable). The `r-` prefix is a hint
that this is a Robinson-shipped path, not the site author's.
Site authors who genuinely want their own `/admin/` URLs can do
so without colliding by choosing a different prefix here, or by
not enabling the admin tree at all.

### Login / logout

Minimum admin pages shipped with Robinson:

- **`/r-admin/login.casp`** — login form, checks credentials
  against `site.json`'s `admin.users`, sets the admin cookie on
  success.
- **`/r-admin/logout.casp`** — clears the admin cookie,
  redirects to login.

Future pages (log viewers, configuration inspection, etc.) ship
later. Site authors who want to extend the admin tree do so by
placing files at `pages/r-admin/...` (which override Robinson's
defaults because `pages/` has higher priority than `admin/`).

### Admin cookie

Admin authentication uses a separate cookie, distinct from the
general session cookie. **Cookie name**: `robinson-admin` (or
similar). The admin cookie's lifecycle (created at login,
cleared at logout) is independent of `$transaction.session`,
which a site may use for its own per-user state.

### `$transaction.admin`

Page code checks for admin presence via `$transaction.admin`:

- `null` if no admin authenticated for this request.
- A truthy hash if one is. The hash is currently always empty —
  the existence of the value is the signal. Specific keys (e.g.,
  username) can be added later if a real use case surfaces.

```
if $transaction.admin
    # admin-only behavior here
end
```

Surface is narrow: *admins only*, not end-user accounts, not
OAuth, not general user authentication. End-user auth is a
separate concern outside the framework.

### Per-site admin data

The admin tree needs somewhere to store its data (active admin
sessions, login attempts, etc.). The storage mechanism is **TBD**
and will be configured per-site once the broader "per-site data
storage" question is settled.

### Open

- Password hash algorithm — must not be a fast hash (bcrypt,
  argon2, or scrypt).
- Helper utility for generating hashes to paste into `site.json`.
- Session/cookie mechanism details (TTL, signing).
- Whether admin auth eventually moves to Touchstone (so Sammy
  can use it) — for now stays Robinson-specific.

---

## Error handling

Server-side error visibility is one of the worst recurring pain
points in web development. Robinson addresses it on multiple
fronts.

### Page-file syntax errors (admin-visible)

When a `.casp` page file has a syntax error, the developer
needs to find it fast. The standard 500 page is useless — it
doesn't say which file or where.

Robinson's response when invocation of a page file fails to
parse:

- **For admins**: a detailed admin page showing the file path,
  line number, column, the parser's complaint, and a snippet of
  the offending source. Bundled into the standard admin-exception
  placeholder; same affordance as runtime exceptions.
- **For non-admins**: a generic factory 500 page. No file paths,
  no source — anything specific would be information leakage.

Robinson knows where it tried to invoke from; the Caspian
runtime knows where parsing failed. Joining the two is
straightforward.

### "Why didn't my route match?" (admin-visible 404)

Filesystem-routed servers have a unique frustration: developer
creates `pages/blog/post-1.casp`, requests `/blog/post-1`,
gets a 404. Was the file in the wrong place? Wrong extension?
Permission issue? Wrong site? Without diagnostic information,
the developer is blind.

Robinson's admin 404 page shows:

- Which dir handlers were consulted, in order.
- For each handler, which file paths were considered.
- Why each was rejected (file missing, wrong extension, jail
  refused the path, robinson.*-prefix-blocked, etc.).

This is the single most "I'm flying blind" experience in
filesystem-routed servers, and Robinson is the only layer that
can answer it cleanly. Same admin gating as the other admin-only
disclosures — never visible to public clients.

### Startup config errors (fail loud)

`server.json` or `site.json` problems should fail at server
start with specific, actionable error messages — not "server
didn't start" with no detail. Checks include:

- `server.json` is parseable JSON.
- Each site's `dir` exists and is readable.
- No two sites declare the same canonical domain.
- Each admin's password hash is parseable (we can't verify the
  hash itself, but we can verify it's not garbage).
- Each opt-in admin section has a valid `url_prefix`.

The startup error message includes the file path, line/column
where possible, and a clear "what's wrong" message. The server
refuses to start; the operator fixes the config and retries.

### Handler attribution on runtime exceptions

When an exception fires during request handling, the admin
exception display says **which handler was running** when it
fired — by name (e.g., "CSRF guard," "page-tree handler for
borg.com," developer's custom CORS handler). Without this,
debugging a chain of handlers means guessing which one threw.

This is a Touchstone feature, not Robinson-specific — see
[touchstone.md § Handler attribution](../../requirements/network/http/server/touchstone/index.md#handler-attribution-on-exceptions).

### Cleanup errors don't mask the original

If an `ensure` block raises during cleanup, the cleanup error
doesn't replace the original exception in the admin display.
Both are preserved: the original gets the primary slot; the
cleanup error appears as a secondary "and during cleanup, also
this happened" annotation.

Also a Touchstone feature.

### Logger failure cascade

If Jasmine itself fails to log (downstream service down, disk
full, etc.), the original event isn't silently swallowed — it
falls through to stderr with a `[JASMINE FAILED]` marker.

A Jasmine feature; see [jasmine.md](../../requirements/packages/jasmine/index.md).

---

## What Robinson inherits from Touchstone

Everything in [Touchstone](../../requirements/network/http/server/touchstone/index.md). Notably:

- [The transaction object](../../requirements/network/http/server/touchstone/index.md#the-transaction-object)
- [The request object](../../requirements/network/http/server/touchstone/index.md#the-request-object) (steps, params, body)
- [Sessions](../../requirements/network/http/server/touchstone/index.md#sessions)
- [Body buffering](../../requirements/network/http/server/touchstone/index.md#body-buffering)
- [The handler chain](../../requirements/network/http/server/touchstone/index.md#the-handler-chain)
- [The response object](../../requirements/network/http/server/touchstone/index.md#the-response-object) (constructor, helpers, headers, redirects)
- [CSRF Protection](../../requirements/network/http/server/touchstone/index.md#csrf-protection)
- [Content Security Policy (CSP)](../../requirements/network/http/server/touchstone/index.md#content-security-policy)

A page's `process` method is just a Handler `process` that
happens to be loaded from a file at request time. No new
machinery.

---

## Convergence with Sammy

The architectures converge cleanly because **everything is a
Handler**. Sammy and Robinson are both Touchstone subclasses
that pre-install a different set of Handlers; they differ in
the *configuration affordance* (method-selector calls vs.
filesystem trees) but not in the underlying dispatch model.

| Concept | Sammy | Robinson | Shared? |
|---|---|---|---|
| Dispatch primitive | Path selector Handler | Directory handler | Touchstone Handler interface |
| Pattern matching | `{name}` placeholders | URL → file path | Both populate `$request.steps` |
| Trailing slash | Significant (no redirect) | Significant (302 redirect) | Same semantic, different handling |
| 404 behavior | Catch-all on `$server.run` or built-in 404 | Factory messages tree | Both end at the factory |
| 5xx behavior | Built-in pages, status mapping | Factory messages with admin placeholder | Both use Touchstone's mapping |
| Sessions, CSRF, CSP, body buffering | From Touchstone | From Touchstone | Identical |
| Authentication | Developer rolls own | Built-in admin tree (opt-in) | Robinson-specific (for now) |
| Multi-host | Not in core | First-class via `server.json` | Robinson-specific |

**Sammy and Robinson differ in *registration model*, not in
*runtime model*.** A directory Handler and a path-selector
Handler look identical to the dispatcher. Once dispatch starts,
Touchstone is in charge.

---

## What's out of scope

If your app is mostly ad-hoc routes rather than content-as-files,
use [Sammy](../../requirements/network/http/server/sammy/index.md). If you need both styles in one
server, that's possible in principle (both expose Handlers); the
ergonomics of that combination are deferred until a real use
case surfaces.

---

## Candidates for v1

Features worth considering if they prove light, otherwise
deferred.

- **Per-page `csrf: false` opt-out.** Page files declare a
  `csrf` property on the page class.
- **Per-page content-type / cache headers**, declared on the
  page class.
- **Background page reload.** Reload `.casp` page files when
  they change on disk during development (not production).

---

## Open issues

Match patterns (large):
- **Directory-index priority** (`index.casp` → `index.html` → ...).
- **Directory listings by default** — almost certainly no, but pin it.
- **Dotfile handling** — case-by-case (`/.well-known/` yes, `/.git/` no).
- **Directory-request on file** — probably 302 to no-slash form.
- **Extension elision** — `/about` matching `about.casp` or `about.html`?

Sites and dispatch:
- **Overlapping domains across sites** — startup error vs. silent first-match-wins.
- **Unknown-domain requests** — decline vs. 404 vs. installation-level fallback.
- **Custom directory handlers** in `site.json` — how to add a tree beyond
  pages/factory/admin (e.g., a separate docs/ tree at higher priority).

Admin:
- **Hash algorithm** for `admin.users` passwords.
- **Hashing helper** (CLI or runtime utility).
- **Admin session mechanism details** — TTL, signing, storage.
- **Per-site data storage** mechanism (broader than admin).

Cross-cutting:
- **Mixing Sammy and Robinson Handlers** in one server — supported by
  the Handler interface; ergonomics TBD.
