# Orlando — lessons learned

*Thoughts and experiences from building Orlando, with an eye to what might transfer to Lucy or Charlie*

~~~json
{"vibecode": {
	"doc": "orlando-lessons",
	"role": "running log of design and implementation insights from Orlando (the Lua sandbox); each lesson notes what we learned and whether it might apply to Lucy (the Lua reference implementation of Charlie) or to Charlie itself",
	"status": "ongoing; add lessons as they arise",
	"key_concepts": ["sandbox_learnings", "lua_experience",
		"transferable_patterns", "lucy_candidates", "charlie_candidates"]
}}
~~~

<a id="overview"></a>
## Overview

Orlando is the Lua sandbox (see
[orlando.md](../orlando.md)). Things we figure out here are not
automatically requirements for the wider project — but some of them
will turn out to be useful primitives for **Lucy** (the Lua
reference implementation of Charlie) or for **Charlie** itself.

This doc captures those lessons as we run into them, so the
information doesn't evaporate. Each entry follows a small shape:

- **What we did** — the concrete piece of Orlando work.
- **What we noticed** — the lesson or pattern that emerged.
- **Possible application elsewhere** — where else in the project this
  might be worth lifting.

---

<a id="a-tiny-tree-builder-is-useful"></a>
## A tiny tree-builder is useful

**What we did.** While planning Orlando's HTML rendering pipeline,
we needed a way to assemble structured HTML output (page templates,
sidebar nav, content shell). We considered three approaches: raw
string concatenation, an external templating library (etlua,
lustache, etc.), and an in-tree builder. We picked the in-tree
builder and implemented
[`orlando.quick_builder`](../../../code/orlando/lua/orlando/quick_builder.lua) —
one `Tag` class where every node is the same type, with a recursive
`render()` that emits the tag plus its children.

**What we noticed.** The whole thing fit in about 60 lines of code
with no dependencies. The "every node is the same type" design kept
the surface very small — no node-type hierarchy, no visitor
pattern, no template-object/data-object split. Ergonomics are good
via callback nesting: `parent:tag('child', function(c) ... end)`.
The same shape generalises trivially to any tree-structured data —
not just HTML.

**Possible application elsewhere.**

- **Lucy** may want a similarly lightweight builder for
  CharlieJSON output, AST nodes, or query result construction.
  Wherever a tree of similar-shaped nodes shows up, the
  one-class-recursive-render pattern is worth considering before
  reaching for something more elaborate.
- **Charlie** itself may want this at the language level —
  Charlie's class system already supports the pattern; what's
  novel is the deliberate refusal of node-type hierarchies. If
  Charlie picks up a tree-builder built-in, this is a good model
  to start from.
- The same pattern probably applies to **Mikobase** worldlet
  assembly (constructing a worldlet from scratch in code, rather
  than parsing one from JSON), if that ever becomes a use case.

The bar for adopting it elsewhere: a real use case where string
concatenation is causing actual bugs or unreadability. Not a
hypothetical "this might be useful." The Orlando version was built
because we had an immediate, concrete need; that's the trigger
worth waiting for in other components too.

---

<a id="markdown-parsing-is-going-to-come-up-everywhere"></a>
## Markdown parsing is going to come up everywhere

**What we did.** Orlando's whole purpose is rendering `.md` files
as HTML, so we had to pick a markdown parser. Evaluated cmark
(canonical CommonMark in C, AST-shaped), lcmark (cmark variant by
the same author), and lunamark (pure Lua, LPeg-based). Picked
lunamark to stay pure-Lua.

**What we noticed.** Markdown isn't an Orlando-specific need. As
soon as any other Charlie web app wants to serve human-readable
content (a docs page, a help system, a post body, an AI-generated
response, an admin notice, a release notes feed), it'll need
markdown rendering too. The wheel is going to get reinvented in
every Charlie app unless the framework provides it.

The library-evaluation work we did here — knowing that lunamark
parses Markdown.pl-flavoured by default and needs explicit options
for fenced code / tables / strikethrough, knowing the visitor-vs-AST
distinction matters for transforms, knowing the `~/.luarocks`
install path quirks — is the kind of trivia every adopter would
otherwise have to relearn.

**Possible application elsewhere.**

- **Sammy** (the HTTP framework on Touchstone) is the natural
  place to bake markdown rendering in. A `%sammy.render.markdown`
  or similar helper, with sensible defaults (GFM-ish: fenced
  code, tables, strikethrough), would mean Charlie web apps get
  markdown rendering as a one-liner instead of as a per-app
  research project.
- **Lucy** could expose the underlying parser as a primitive
  (`%utils.markdown` or similar) so non-web Charlie code — CLI
  tools, AI assistants, content pipelines — has it without
  pulling in HTTP machinery.
- **AI2AI** records often contain markdown in body fields
  (proposals, reports, evidence). A shared parser means consumers
  of AI2AI session data have a consistent rendering story.
- **Mikobase worldlet authoring** — the same applies if a worldlet
  carries human-readable notes that need rendering at display time.

The shape of the helper matters less than that one helper exists.
Right now, Charlie has no markdown story at all; the first thing
to do is decide which layer owns it (Lucy primitive vs. Sammy
helper vs. both), and what defaults that layer picks (which
extensions are on by default, whether the API is `string → string`
or `string → tree`).

---

<a id="multiple-search-routes-are-needed-almost-immediately"></a>
## Multiple search routes are needed almost immediately

**What we did.** Orlando started with a single document root
(`documentation/`) for everything — markdown sources rendered as
HTML, plus static files served verbatim. Within one feature step
(adding the README as the home page), we already needed a separate
mount for the project's logo, because the README's
`<img src="graphics/logo.svg">` resolves to `/graphics/logo.svg`
and the file lives outside `documentation/`. First attempt: a
`/graphics/` mount alongside the document root. Then we course-
corrected to a single proper static dir (`static/`) where
authorable assets (logos, CSS, JS) live, and removed the
`/graphics/` carve-out.

**What we noticed.** Even a deliberately-minimal static file
server needs a URL-prefix → filesystem-root mapping table from
day one. One root only works for the trivial case; the moment
you have a logo that lives outside the doc tree, or want a
`/static/` namespace for assets, or want to serve from two
different content trees with different rendering rules, you
need mount-table semantics. The Orlando implementation is about
a dozen lines: a list of `{url_prefix, fs_root}` pairs, tried in
order, first match wins. Cheap to write, cheap to extend.

The corollary: we also learned that "just use the documentation
root for everything" is a temporary illusion. The right model is
named mounts from the start, even if the table starts with a
single entry.

**Possible application elsewhere.**

- **Sammy** will need this from the start. Any web framework that
  serves static assets and routes dynamic content needs
  mount-table semantics. The pattern is generic enough that a
  framework-level helper (`%sammy.mount('/static/', 'static/')`)
  would carry its weight immediately, rather than waiting for
  the second use case.
- **Lucy** could expose a file-resolution primitive that takes a
  mount table — useful for any CLI tool that serves files from
  multiple roots, including non-HTTP cases like static-site
  generators or asset bundlers.
- **AI2AI** agents that serve worldlets over HTTP will likely
  hit the same need (worldlet files in one tree, supporting
  attachments in another).

The shape (`{url_prefix, fs_root}` list, first match wins) is
worth keeping as the default — it's simple, predictable, and
extends cleanly. The bar for adopting it elsewhere is just
"you have more than one place to serve from," which arrives
much faster than you'd expect.

---

<a id="syntax-highlighting-needs-a-framework-level-story"></a>
## Syntax highlighting needs a framework-level story

**What we did.** Orlando needed syntax highlighting for the JSON
inside vibecode blocks. Evaluated three options:

- **Shell out to pygmentize** (Python). Five lines of Lua, but
  adds Python as a runtime dep and forks a process per code
  block per request (≈80 forks per dev-plan render — performance
  hostile without caching).
- **highlight.js on the client.** Zero Lua code, but adds a JS
  dependency, conflicts with the current CSP (`script-src
  'self'`, no JS shipped today), and turns presentational chrome
  into something that breaks when JS is disabled.
- **Build a small Lua tokenizer.** ~60 lines of actual logic
  plus tests, no new deps. We picked this — JSON's grammar is
  tiny enough that rolling our own was competitive on every
  axis.

**What we noticed.** JSON happened to be small enough to build,
but the answer flips for anything with a real grammar (Charlie,
Python, Lua, SQL, Q0, etc.). Every Charlie web app that serves
authored content with code samples will hit this. We don't want
each adopter re-evaluating the same three options.

The Sammy/Lucy framework needs a syntax-highlighting story —
specifically: a built-in primitive that takes (language, source)
and returns HTML with pygments-compatible classes, so the
existing pygments-themed CSS ecosystem applies directly.

**Possible application elsewhere.**

- **Sammy** is the natural owner of a `%sammy.highlight(lang,
  source)` helper. **Charlie itself is the most important
  language to support** — every doc page about Charlie will
  contain Charlie source. JSON, Lua, SQL, and the Q0 query
  language are the next-priority targets. The mechanism likely
  needs to delegate to pygmentize (or an equivalent) under the
  hood for non-trivial languages; the framework provides the
  caching layer and the language registry.
- **Lucy** should expose the primitive too (`%utils.highlight`
  or similar) so non-web Charlie code — CLI tools, AI
  assistants, content pipelines — gets it without HTTP.
- **Charlie's own toolchain** (Bryton, Trivet) will want this
  for rendering source snippets in test failures or trace
  output.

The Orlando JSON tokenizer ([orlando.json_highlight](../../../orlando/lua/orlando/json_highlight.lua))
is worth keeping as a reference for how the output should be
shaped (pygments-class spans, key-vs-value distinction via
look-ahead). It's not worth generalizing into the framework —
the framework version will need to handle real grammars and
should delegate to a real lexer.

---

<a id="we-built-a-nice-markdown-tree-renderer"></a>
## We built a nice markdown-tree renderer

**What we did.** Orlando started as a server skeleton, picked up a
markdown renderer, then a static-mount table, then site chrome,
then collapsible TOCs auto-generated from headings, then dark
syntax-highlighted vibecode blocks, then a sidebar that tracks the
current page, then a directory-index rule with 301 redirects.
None of it was planned up front — each piece was the next
obvious step. The cumulative shape, looking back, is a small
self-contained system that turns a directory tree of `.md` files
into a navigable, chrome-wrapped website.

**What we noticed.** The whole system is about a dozen small,
single-purpose modules totalling ~700 lines of Lua (excluding
the third-party deps and the pygments CSS). The pieces are
genuinely independent:

- **route** — URL → fs path (with the dir-index rule and 301s)
- **server** — accept loop, response framing
- **page** — markdown render + chrome transforms (hero logo,
  link rewriting, external-link marking, auto-TOC, vibecode
  wrapping)
- **nav** — sidebar tree (current-page highlight, ancestor
  expansion, directory-as-link when an index file exists)
- **quick_builder** — HTML/XML tree → string with HTML5 void-
  element awareness and a `:raw()` escape hatch for mixing in
  pre-rendered HTML
- **json_highlight** — tiny pygments-compatible JSON tokenizer
- **content_type** — extension → MIME

Each is small enough that the next contributor can hold it in
their head. The composition pattern (post-render transforms as
functions over HTML strings, with `:raw()` at the boundary) is
the load-bearing idea — it lets us bolt new chrome on without
touching the existing pieces.

The thing it does — *render a tree of markdown files as a
website* — is one of the most common shapes in software. Docs
sites, personal wikis, knowledge bases, public-facing project
pages, internal handbooks. Anywhere authors want to write
content without writing code, this is the natural pattern.

**Possible application elsewhere.**

- **Robinson** wants a markdown-tree handler peer to its
  Charlie-page handler, lifting Orlando's design directly. See
  [robinson-wishlist.md "Robinson Handler (Markdown-Tree
  Pages)"](../../ideas/robinson-wishlist.md#robinson-handler-markdown-tree).
  The translation to Charlie should be roughly mechanical;
  the design decisions are the valuable part.
- **Charlie's own toolchain** could use the same shape for
  rendered documentation, runnable examples with embedded
  output, AI2AI session viewers, etc. Anywhere there's a tree
  of source content that should be browsable.
- **Mikobase** worldlet documentation, if worldlets carry
  prose, fits the same pattern.

The most important transfer isn't the code — it's the *order
in which the pieces were added*, captured across the other
lessons here. Each lesson is the answer to a question that
arose naturally. A Robinson markdown handler that re-derives
those answers from scratch will spend time on problems Orlando
already solved.
