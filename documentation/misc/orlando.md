# Orlando

*A Lua web server for serving Markdown files*

~~~json
{"vibecode": {
	"doc": "orlando",
	"role": "design notes for a Lua HTTP server that serves the project's .md files as rendered HTML; ports the rendering logic from the Python build script; built as a Lua-practice project",
	"status": "design phase; no implementation yet",
	"key_concepts": ["lua_practice", "http_server", "routing",
		"markdown_to_html_rendering", "port_of_python_build_script",
		"not_puck", "not_touchstone", "not_sammy"],
	"reference_implementation": "/home/miko/tmp/puck/build.py"
}}
~~~

<a id="overview"></a>
## Overview

**Orlando** is an HTTP server, written in Lua, that serves the
Markdown files in this repository to a browser as **rendered HTML**.
On each request, Orlando reads the requested `.md` file, runs it
through a markdown-to-HTML pipeline, wraps it in the site template
(sidebar nav, hero logo, vibecode handling, all the same chrome the
static site has), and returns the HTML over HTTP.

Orlando also serves static files (CSS, SVG, images, raw JSON, etc.)
straight from the same document root, byte-for-byte with the right
`Content-Type`. The dispatch is by extension: `.md` files go through
the rendering pipeline; everything else is served verbatim.

**Every page is generated on the fly.** Orlando does not cache
rendered HTML. Each request re-reads the source `.md` and re-runs
the pipeline. This is a deliberate simplification — no cache layer,
no invalidation logic, no stale-content surprises while editing. The
performance hit is acceptable because Orlando is a development tool,
not a production server.

Orlando is built as a practice project for working with Lua and for
getting hands-on with the basics of HTTP serving: listening on a
port, parsing requests, routing paths to files, generating the
response body, setting the right content type, and handling the
obvious error cases.

Orlando's name fits the existing Shakespeare theme used elsewhere in
the project (Touchstone, Sammy), but it shares nothing else with
those projects.

---

<a id="why"></a>
## Why

The primary purpose is **practice**. Writing a small HTTP server in a
new language is a well-trodden way to learn the language and the
ecosystem at the same time:

- Practice with Lua syntax, idioms, modules, and standard library
- Practice setting up a TCP listener and accepting HTTP connections
- Practice request parsing and response formatting
- Practice routing — mapping a URL path to a file on disk
- Practice the error cases — 404, 405, range requests, etc.

A second-order benefit: once Orlando works, it's a useful local-dev
convenience. Edit a `.md` file, hit refresh in the browser, see the
change immediately — without running the full static-site build.

---

<a id="not-puck"></a>
## Not Puck

This is important enough to call out explicitly:

- Orlando is **not** Touchstone. Touchstone is per-request
  infrastructure for Charlie/Sammy applications (transactions,
  sessions, body buffering, CSP). Orlando shares none of that.
- Orlando is **not** Sammy. Sammy is a route-style serving framework
  built on Touchstone, intended for real applications. Orlando is a
  practice tool for serving static files.
- Orlando does **not** use the Puck ecoverse. No UNS lookup, no
  Mikobase, no Charlie engine, no Puck blockchain, no Puck client.
  Orlando is a plain Lua program that reads files from disk and
  writes bytes to a socket.

The reason for the separation: Orlando exists to teach Lua. Wiring it
into Puck infrastructure would defeat that purpose and would also
muddy what is and isn't part of the Puck stack.

---

<a id="scope"></a>
## Scope

What Orlando does:

- Listen on a configurable TCP port (default TBD)
- Accept HTTP/1.1 connections
- For `GET /path/to/file` or `/path/to/file.html`, find the
  corresponding `.md` file in the document root, render it to HTML
  through the full pipeline (see [Rendering pipeline](#rendering-pipeline)),
  and return it as `text/html; charset=utf-8`. **Generated fresh on
  every request — no caching.**
- For any other path, serve the file at that path from the document
  root verbatim, with a `Content-Type` chosen by extension (`.css`,
  `.svg`, `.json`, `.png`, etc.)
- Return `404 Not Found` for missing files
- Return `405 Method Not Allowed` for non-GET requests
- Log each request to stdout in a simple, readable format

What Orlando does **not** do (at least not in any first version):

- **Any caching.** Every `.md` request triggers a fresh parse and
  render. Static files are read off disk on every request too. The
  OS page cache helps; Orlando does nothing on top.
- HTTPS (run behind a reverse proxy if needed)
- Authentication or authorization
- POST, PUT, DELETE, or any state-changing operation
- WebSockets

---

<a id="rendering-pipeline"></a>
## Rendering pipeline

Orlando's rendering pipeline is a Lua port of the Python static-site
build script at `/home/miko/tmp/puck/build.py`. The output should
match that script's output byte-for-byte for the same input
(modulo timestamps or any clearly noted differences). That script is
the reference implementation.

The pipeline applies these transforms in order to each `.md` request:

1. **Markdown → HTML.** Parse the Markdown source. Needs:
   GFM-style tables, strikethrough, fenced code blocks (both
   `~~~lang` and ` ```lang `), inline HTML pass-through (so the
   doc-convention `<a id="anchor"></a>` lines survive).
2. **Fence handling for vibecode.** A `~~~json` fence whose first
   non-whitespace content is `{"vibecode":` becomes a
   `<details class="vibecode"><summary>vibecode</summary><pre><code>…</code></pre></details>`
   block — collapsed by default, Monokai-style syntax-highlighted.
3. **Fence handling for other code.** Render through a syntax
   highlighter. The Python version uses Pygments; the Lua port will
   need an equivalent (see [Open questions](#open-questions)).
4. **Internal link rewriting.** `[text](foo.md)` and
   `[text](foo.md#anchor)` are rewritten so `.md` becomes `.html`.
5. **Hero logo injection.** Insert
   `<img class="hero-logo" src="…/graphics/logo.svg">` at the start
   of the first `<h1>` element, unless one is already present
   (the README hardcodes its own). The logo's `src` path is
   adjusted to the current page's depth.
6. **Hero logo link wrap.** The hero logo is wrapped in an
   `<a href="…/index.html">` so it acts as a home link.
7. **Issue links on each H2.** Each `<h2>` heading gets a
   `<a class="issue-link section-issue" href="…">GitHub issue</a>`
   appended, with the URL pre-filled to open a new GitHub issue
   titled `[docs] <path> § <section>`.
8. **TOC transformation.** The Contents section's `<ul>` becomes a
   collapsible tree: each leaf `<li>` gets a `<label class="toc">•</label>`,
   each branch `<li>` gets a `<label class="toc" for="…">⊕</label>`
   plus a hidden `<input type="checkbox" class="show-nested">` that
   CSS uses to toggle the nested `<ul>` open/closed. No JavaScript.
9. **External link `target` marking.** Any `<a href="http(s)://…">`
   not already containing a `target` attribute gets
   `target="_blank" rel="noopener"`.
10. **Sidebar nav.** A tree of all `.md` files in the document
    root, rendered as nested `<details>`/`<ul>` so dirs are
    collapsible. The current page's `<li>` is rendered as a bold
    `<span>` (not a link). Ancestors of the current page have
    `open` on their `<details>` so the path to the current page is
    visible by default.
11. **Page template.** Wrap everything in the standard
    `<!DOCTYPE html>`/`<head>`/sidebar/main-content shell. The
    body class is `"home"` only for the index page.
12. **Pretty-print HTML.** Reindent the HTML by block-level
    structure for readability. Whitespace inside `<pre>`,
    `<script>`, `<style>`, and `<textarea>` is preserved verbatim
    (critical for the vibecode `<pre><code>` blocks).

The CSS and the logo are served as static files from the document
root, not regenerated per request.

For the **index page**, the source is `README.md` (one level up
from the document root). README links use `documentation/foo.md`
paths; those need a `documentation/` prefix stripped before the
`.md → .html` rewrite, since the document root IS `documentation/`.

---

<a id="staging-plan"></a>
## Staging plan

End-state goal: Orlando serves the same site the Python build script
currently publishes to puck.uno, looking the same in a browser. The
work gets there in four stages, each shippable on its own. Pick up
the next stage when the previous one is solid.

<a id="stage-1-server-skeleton"></a>
### Stage 1 — Server skeleton

Get the HTTP plumbing right end-to-end, before any rendering.

- Bind to a configurable TCP port (proposed default: `8181`).
- Accept HTTP/1.1 connections one at a time (synchronous accept
  loop — concurrency is a later concern).
- Parse the request line and headers far enough to extract method
  and path.
- Reject non-GET with `405 Method Not Allowed`.
- For any path: read the file at that path under the document root
  and return its bytes verbatim, with a `Content-Type` chosen from
  the file extension (`.md` → `text/markdown` for now, `.css` →
  `text/css`, `.svg` → `image/svg+xml`, etc.).
- `404 Not Found` for missing files. Path traversal protection
  (no `..` escaping the root).
- Log each request to stdout.

At the end of this stage, Orlando is a perfectly serviceable static
file server. Markdown rendering comes next.

<a id="stage-2-markdown-to-html"></a>
### Stage 2 — Markdown to HTML

Plug in the rendering pipeline's core.

- For `GET /foo` or `GET /foo.html`: resolve to `foo.md` in the
  document root, run it through a Markdown library, wrap the
  result in a minimal page shell (`<!DOCTYPE html>` + `<head>` with
  a title + `<body>` containing the rendered HTML), return as
  `text/html; charset=utf-8`.
- Non-`.md` paths continue to serve verbatim from Stage 1.
- Internal link rewriting: `.md` → `.html` (and `.md#anchor` →
  `.html#anchor`) inside rendered hrefs.

At the end of this stage, browsing to `/overview` shows the
overview document as basic HTML with no chrome.

<a id="stage-3-site-chrome"></a>
### Stage 3 — Site chrome

Make it look like puck.uno.

- Serve the existing `_assets/style.css` as a static file (CSS is
  generated once and shipped as a file, not generated per request).
- Sidebar nav: walk the document root for `.md` files, build the
  nested `<details>` tree, mark the current page's `<li>` with a
  bold `<span>` (no link), open the `<details>` ancestors of the
  current page so the path is visible.
- Hero logo: inject `<img class="hero-logo" src="…/graphics/logo.svg">`
  into the first `<h1>`. Wrap it in `<a href="…/index.html">`.
- Issue links: append a `GitHub issue` link to every `<h2>`, with
  the URL pre-filled.
- External link target marking: add `target="_blank" rel="noopener"`
  to every `<a href="http(s)://…">`.
- Index page: source is `README.md` one level above the document
  root; rewrite README's `documentation/` link prefixes.

At the end of this stage, Orlando is visually indistinguishable
from the Python-built site for the common case.

<a id="stage-4-pixel-parity"></a>
### Stage 4 — Pixel parity

The remaining details that the static build does.

- TOC transformation: convert the Contents `<ul>` into the
  collapsible labels + hidden-checkbox tree.
- Vibecode handling: detect `~~~json` fences starting with
  `{"vibecode":` and wrap as `<details class="vibecode">`.
  Optional in this stage: JSON syntax highlighting (Pygments has
  no Lua equivalent; either find a small Lua-native JSON
  highlighter, port enough of Pygments-lite to handle JSON, or
  ship without highlighting and revisit).
- Pretty-print HTML output (purely cosmetic for view-source).
- Side-by-side visual diff against the Python output; fix
  discrepancies.

At the end of this stage, Orlando's output should match the Python
build's output closely enough that you have to look hard to spot
differences.

---

<a id="open-questions"></a>
## Open questions

These need to be settled before any code is written.

- **HTTP implementation.** Pure Lua from scratch (using `luasocket`
  or similar), an existing Lua HTTP library, or a thin wrapper
  around a C library? The practice goal probably argues for a Lua-
  level implementation rather than wrapping `libmicrohttpd`.
- **Markdown parser.** A pure-Lua markdown library (e.g.
  `lua-discount`, `markdown.lua`), a wrapper around a C parser
  (`cmark`), or a hand-rolled parser? Output must match the Python
  `markdown-it-py` reference closely enough that the pipeline
  steps downstream of it still work.
- **Syntax highlighter.** Pygments isn't a Lua library; the closest
  equivalents are Lua bindings to a C highlighter or a smaller
  Lua-native one. JSON is the only language that really matters for
  vibecode rendering; other code blocks could ship without
  highlighting in v1.
- **Document root.** Hard-coded to `documentation/`? Configurable?
  Multiple roots?
- **URL-to-file mapping.** Does `/foo` map to `foo.md`,
  `foo/index.md`, both, or only one? Trailing-slash handling?
  Index-page behavior when the URL is `/`?
- **Port.** What's the default? Something memorable but unlikely to
  collide — 8080 is overused; 8088 or 8181 or a Shakespeare-themed
  number?
- **Concurrency model.** Synchronous accept-one-at-a-time (simplest),
  Lua coroutines (idiomatic), or one-process-per-request? The
  practice angle probably argues for starting synchronous and
  evolving from there.
- **Repository placement.** Where in this repo does the Lua source
  live? `code/orlando/lua/orlando/` would match the convention
  Charlie uses. `code/orlando/` standalone might be cleaner since
  Orlando isn't multi-language.
- **Tests.** Same Lua test harness as Charlie (`tests/charlie/run.lua`
  style), or something separate? Plus: how do we test that
  Orlando's HTML output matches the Python reference? Golden-file
  comparison against the build script's output is the obvious
  approach.
- **Phasing.** Twelve-step pipeline is a lot. Reasonable v1: serve
  one `.md` file as HTML with steps 1, 4, and 11 only (markdown →
  HTML, link rewriting, page template). Add the rest in slices.
