# Markdown

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_v1_downloads_markdown",
	"role": "spec for the Markdown class at `caspian.uno/markdown.casp` — Ships: no, Day 1: leaning yes. Port of Orlando's existing markdown parser to a standalone class. Parse Markdown source to a tree; render tree to HTML.",
	"status": "stub — needs class-surface design; port strategy from Orlando's parser TBD",
	"audience": "developers rendering Markdown in Caspian apps (docs sites, chat, blog posts); anyone writing the Markdown class spec"
}}
~~~

Stub. First-party download at `caspian.uno/markdown.casp` — Markdown parse and render. Port of the existing Markdown parser that lives in Orlando.

## What Markdown is

TBD. CommonMark-plus-extensions text-to-HTML markup. In practice the class needs to decide which dialect it targets — CommonMark strict, GitHub Flavored Markdown (tables / task lists / autolinks / strikethrough), or Orlando's current mix (fenced code, admonitions, vibecode blocks, tag markers).

## Scope call to make

TBD. Two positioning questions:
- **Which dialect.** Whatever Orlando currently does, or a cleaner CommonMark + GFM baseline with Orlando extensions gated behind a flag.
- **Whether to expose the tree.** Some callers want raw HTML, some want the intermediate node tree (for custom rendering, TOC generation, link rewriting). Both should be reachable.

## Method surface

TBD. Likely `.parse` (source → tree), `.render` (source → HTML), `.render_tree` (tree → HTML) — same shape as the JSON class's `.parse` / `.emit` split.

## Testing

TBD.
