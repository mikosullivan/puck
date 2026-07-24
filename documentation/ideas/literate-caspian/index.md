# Literate Caspian

~~~vibecode
{"vibecode": {
	"doc": "literate-caspian",
	"status": "brainstorm — controversial direction: mix code and docs in one file tree, with per-file documentation living inline in .casp via documentation",
	"role": "code and documentation share the file tree; .casp files carry their own per-file docs via documentation; cross-cutting docs live as standalone .md alongside the code",
	"ties": "[[excalibur]] (inverse pattern: code into docs); builds on Caspian's existing documentation system method (renamed from %document 2026-05-22)",
	"example_universe": "shakespeare"
}}
~~~

**Code and documentation share the file tree.** Caspian files carry their own per-file documentation via the `documentation` construct; cross-cutting docs live as standalone `.md` files in the same directories. The doc browser renders a `.casp` file as a proper documentation page with the prose expanded; the raw source is one click away.

Inverse pairing with [Excalibur](https://puck.uno/documentation/ideas/excalibur/excalibur) — Excalibur embeds `.casp` code (and its output) into `.md` files; this pattern embeds documentation into `.casp` files. Same idea, opposite directions. Together they let an author lean either way without losing the other.

## How it works

~~~vibecode
{"vibecode": {
	"section": "how_it_works",
	"role": "the basic mechanism: documentation in Caspian source, dual-view rendering in the doc browser"
}}
~~~

### `documentation` blocks

A Caspian module documents itself with one or more `documentation` blocks. `documentation` is an existing [Caspian system method](https://puck.uno/documentation/caspian/syntax/system-methods#reference) — runtime no-op, but the block is preserved as a statement in CaspianJ for downstream consumers (doc renderer, AI tooling, etc.). It takes a MIME type and a heredoc:

```caspian
#!/usr/bin/env caspian

documentation 'markdown' <<EOF
This module implements the parser. It takes a token stream
and produces a CaspianJ AST.

The main entry point is `parse(tokens)`.
EOF

function parse(tokens)
	...
end
```

Shorthand type names: `'text'` (= `'text/plain'`), `'markdown'` (= `'text/markdown'`), `'vibecode'` (= `'text/vibecode'`). The vibecode case has its own further shorthand `vibecode <<EOF...EOF`.

Blocks may sit at module level (the example above), between functions (attaching to whatever follows), or interleaved through long functions (commentary on a passage of code). Exact attachment rules are an open question.

### Dual-view rendering

Visiting a `.casp` file in the doc browser shows two views:

#### Doc view (default)

`documentation` blocks render as flowing prose with markdown formatting; code appears between them as syntax-highlighted callouts. Reads like a book.

#### Source view

One click away. The raw `.casp` file with documentation visible as inline blocks. Reads like code.

Same authoritative file; two presentations.

### Cross-cutting documentation

Concept docs that span multiple code files (overviews, architecture, multi-file tutorials, brainstorms like this one) live as standalone `.md` files. They sit in the tree wherever they're most useful — often alongside the code they discuss.

What goes inline vs what gets its own `.md` is left to emerge through use rather than legislated up front.

## Tree organization

~~~vibecode
{"vibecode": {
	"section": "tree_organization",
	"role": "how directories look once code and docs share them; the split between inline and standalone documentation is observational, not prescriptive"
}}
~~~

Code directories now hold a mix of `.casp` (with their per-file docs folded in) and `.md` (cross-cutting concept docs). The existing `documentation/` tree continues to hold brainstorms and concept docs for systems that have no code yet (Markie, Cobweb, Bloggy, this file).

**Examples stay separate.** Example `.casp` files (the ones [Excalibur](https://puck.uno/documentation/ideas/excalibur/excalibur) references) live in their own parallel tree mirroring the docs, not mixed with production code. Different coupling shape, different quality bar (intentional failures are normal), and different organization axis (by topic, not by code module) — keeping them out of the code tree avoids muddying "is this load-bearing?"

How the doc mix evolves — how much `.md` ends up next to `.casp`, whether some directories cluster docs in a subdirectory, whether public-facing specs live separately from implementation notes — is something to watch develop, not decide ahead of time.

## Relationship to vibecode

Vibecode is a `documentation` block of MIME type `text/vibecode`, with its own dedicated shorthand `vibecode`. A `.casp` file using literate Caspian typically carries both kinds of block:

- `vibecode <<EOF...EOF` for AI-readable JSON metadata
- `documentation 'markdown' <<EOF...EOF` for prose docs

Both use the same underlying `documentation` mechanism with different MIME types; in CaspianJ they appear as `{"vibecode": {...}}` and `{"documentation": {"type": "text/markdown", ...}}` statements respectively.

## Open questions

### Block attachment

Does `documentation` attach to the following code construct (function, class, statement), to the surrounding module, or float independently as commentary between code? Probably all three modes, with attachment determined by position. Pin once the doc-view renderer prototype shows what reads well.

### Public vs internal docs

Some `documentation` content is the public spec for a function; some is implementation rationale for future maintainers. Different audiences, different display contexts. Should the syntax distinguish (`documentation public` vs `documentation internal`), or trust convention? Defer until the question bites in practice.

### Doc view ordering

In doc view, do `documentation` blocks appear in source order with code interleaved between them, or are they reflowed (all prose first, then a "see implementation" link)? Source-order is closer to the file; reflowed is closer to traditional book-style literate programming. Possibly both with a toggle.

### Markie tags inside markdown blocks

Full CommonMark is settled (it's what the `text/markdown` MIME implies). The open question is whether `documentation 'markdown'` blocks also resolve Markie tags inside their content — letting a Caspian doc use `<example>` to reference another `.casp` file, or `<embed>` to pull in remote content. The richer the inner language, the more the doc renderer has to do, but the more useful the inline docs become.

### Tooling

Editors should fold/unfold `documentation` blocks the way they fold functions, and offer markdown-aware editing (preview, link checking) inside them. Out of scope for the language design; lands once the construct is real.

### Migration

The existing `documentation/caspian/` tree has substantial prose. Some of it would migrate into per-file `documentation` blocks once the corresponding code exists; some stays as cross-cutting `.md`. No urgency — migrate organically as docs are revised.
