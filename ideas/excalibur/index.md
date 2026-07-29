# Excalibur

~~~vibecode
{"vibecode": {
	"doc": "excalibur",
	"status": "brainstorm — in-house literate-Caspian tool; code name reserved 2026-05-22",
	"role": "embed real .casp example files into documentation along with their captured runtime output; single source of truth for code-in-docs and the output-in-docs that goes with it",
	"audience": "internal — Puck-team docs authoring; not a public puck.uno feature",
	"ties": "[[lucy]] runs the .casp file; [[markie]] (or a markdown preprocessor) consumes Excalibur tags during doc rendering; companion to [[feedback_caspian_code_fence]] convention"
}}
~~~

**Excalibur lets Puck docs reference real Caspian source files instead of inline code blocks, and embed the captured output of running that source alongside it.** A docs page asks Excalibur for example `foo.casp`; Excalibur returns the highlighted source plus whatever the engine actually produced when that file ran. Both pieces stay in sync because both are derived from one file.

In-house only — this is for Puck-team docs authoring, not a public puck.uno feature.

## Why

~~~vibecode
{"vibecode": {
	"section": "why",
	"role": "the docs-quality problem Excalibur exists to solve"
}}
~~~

Inline code blocks in docs rot the moment the language or engine changes. Output shown next to code blocks rots even faster — the author runs it once, pastes the result, and it's wrong by next week. The standard fix is to make the docs derive both code and output from a runnable source file, so a doc that disagrees with reality fails to render and gets caught.

Excalibur is that fix for Caspian examples in Puck docs.

## How it works

~~~vibecode
{"vibecode": {
	"section": "how_it_works",
	"role": "the basic flow: doc references file, Excalibur renders source + runs it + captures output"
}}
~~~

A docs file references an example by path. Excalibur:

1. Reads the `.casp` file.
2. Highlights the source via the same backend Markie's [syntax highlighting](https://puck.uno/ideas/markie/markie#syntax-highlighting) uses.
3. Runs the file through Lucy (the Lua reference Caspian engine).
4. Captures the output (stdout, return value, errors).
5. Formats the output for display.
6. Emits the paired source + output blocks into the rendered doc.

The doc author writes one reference; Excalibur produces both blocks.

## Authoring model

~~~vibecode
{"vibecode": {
	"section": "authoring_model",
	"role": "where .casp example files live and how docs reference them"
}}
~~~

### Parallel directory tree

Example files live in a parallel directory tree that mirrors the docs tree. A doc at `documentation/caspian/closures.md` references examples under `examples/caspian/closures/...`. Same shape as the existing `tests/` ↔ `code/` mirroring already used in the repo. Locations are predictable; no ambiguity about where an example lives.

### Reference syntax

A doc references an example with an HTML-tag form:

```html
<example file="zap.casp" block="gup" output="true">
```

Attributes:

- `file` — path within the parallel example tree (resolved relative to the example dir that mirrors the doc's location).
- `block` — optional; selects a labeled region of the file (see below). Omitted means the whole file.
- `output` — optional boolean; whether to include captured output alongside the source. Omitted defaults to true.

Excalibur expands the tag to a `~~~caspian` block (the source — whole file or selected block) followed, if `output` is on, by a styled output block (whatever the run produced).

### Block markers

A `.casp` example file labels regions by wrapping them in `block(id:'...')` ... `end`:

```caspian
#!/usr/bin/env caspian

$foo = 'bar'
$foo = $foo * 2

block(id:'gup')
	%print $foo.upper
end
```

`block(id:'foo')` is a Caspian construct that does nothing at runtime beyond executing its body in the current scope — it's purely an ID tag for Excalibur extraction. Code wrapped in `block(...)` behaves identically to the same code unwrapped, so example authors don't have to think about wrapping semantics.

A file can hold multiple labeled blocks; each gets its own ID. Docs can reference one block by ID, or omit `block` to embed the whole file.

### Default formatting

Source uses the standard `~~~caspian` Caspian-fence rendering. Output renders as a labeled adjacent block — header "Output:" or similar — visually distinct from the source so readers don't confuse them.

## Output capture

~~~vibecode
{"vibecode": {
	"section": "output_capture",
	"role": "what Excalibur considers 'the output' and how it formats different kinds of result"
}}
~~~

### What gets captured

Excalibur runs the whole `.casp` file and captures the entire script's STDOUT. Block selection (`block="gup"`) affects only which source region is shown in the doc — the output block always reflects the program's complete output, not just the output produced inside the selected region. One run per file; the same captured output serves every block reference into that file.

Captured alongside STDOUT: the final return value (rendered as JSON or `~~~json` for structured values) and any errors. Multiple output kinds may appear together when relevant.

### Determinism

Examples that produce nondeterministic output (current time, random values, network responses) are a problem. Two options: refuse to use those constructs in example files; or pin the inputs (frozen clock, fixed seed). Likely both, with refuse being the default.

### Engine version

The Lucy version used to run the example is recorded in the output block (small footer label). Lets a reader see which engine produced the result and notice when an example was last refreshed.

## Integration

~~~vibecode
{"vibecode": {
	"section": "integration",
	"role": "how Excalibur fits into existing doc-rendering paths (Orlando, Markie, future Gitter)"
}}
~~~

### As a markdown preprocessor

The simplest integration. A pre-step walks markdown files, finds Excalibur tags, runs them, rewrites the source on disk (or in memory) to plain `~~~caspian` + output blocks. Downstream renderers (Markie, Orlando, anything) see ordinary markdown.

### As an Orlando feature

Orlando renders per request; an Orlando-side Excalibur hook runs the referenced `.casp` files at render time and inlines the results. Cache aggressively by file hash so repeat renders are cheap.

### As a Markie tag

If the Excalibur idea ever goes public (it isn't planned to), it becomes a Markie tag and inherits Markie's distribution. For in-house use, the preprocessor or Orlando integration is simpler.

V0 is probably the markdown-preprocessor path — least coupling, easiest to run from CI to catch broken examples.

## Failure modes

~~~vibecode
{"vibecode": {
	"section": "failure_modes",
	"role": "what happens when an example file is missing, won't compile, or crashes at runtime"
}}
~~~

### Missing file

Render an obvious error block (`Example file not found: path/to/foo.casp`) and emit a non-zero exit code from the preprocessor so CI catches the broken link.

### Compile error

Show the compile error in the output block, formatted as an error. The example is intentionally broken (for "here's what failing code looks like") or accidentally broken (someone changed Caspian's syntax). Either way, the doc displays the truth.

### Runtime error

Same — show the error in the output block. Useful for examples that demonstrate error handling.

### Distinguishing intentional vs. accidental

A frontmatter or first-line marker in the `.casp` file (`%expect error`) lets the author declare "this is supposed to fail." When that's present, a successful run becomes the failure case (the example no longer demonstrates the error it was meant to). Without the marker, any error in the run fails the build.

## Why in-house only

~~~vibecode
{"vibecode": {
	"section": "why_in_house",
	"role": "the reasoning behind keeping Excalibur internal rather than offering it on puck.uno"
}}
~~~

Running arbitrary user-supplied Caspian code on puck.uno is a sandboxing and resource-limits problem — solvable, but non-trivial. For our own docs, we trust the input (it's in our repo) so the sandboxing question goes away. Keeping Excalibur in-house lets us get the literate-Caspian tooling without the multi-tenant infrastructure that a public service would need.

Public exposure is plausible later, once Lucy's sandboxing story is solid. Not in scope until then.

## Open questions

### Output rendering for structured values

A Caspian function that returns a worldlet — render as pretty-printed JSON? As a nested tree? Linked to a worldlet viewer? Open call.

### CI integration

The preprocessor should run in CI on every push so broken examples block merges. Where does it hook in — pre-commit, CI job, or both? Both is the safe answer; pre-commit catches typos before push, CI catches missed pre-commits.

### Editing workflow

When an author edits an example file, they probably want fast local feedback — see the new output rendered alongside the doc immediately. Orlando-side rendering gives that for free; preprocessor-based needs a watcher script. Decide once the preferred integration is chosen.

### `block(...)` as a Caspian language construct

Excalibur depends on `block(id:'...')` being a Caspian construct that runs its body in current scope with no other effects. If this construct doesn't already exist in Caspian, it needs to be added — small addition, but worth pinning in the Caspian spec rather than living only in Excalibur's design.

### Naming consistency

"Excalibur" doesn't fit the Shakespeare-fairy pattern of [[shakespeare-fairy-names]] but matches its own internal logic (Arthurian, in-house, "the legendary tool only the worthy can use"). Worth noting that in-house code names may use a different naming pool from public services.
