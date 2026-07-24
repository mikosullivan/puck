# CaspianJ formats: full and norm
<!--index: 18-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspianj",
	"role": "spec for the two CaspianJ (CaspJ) formats the transpiler / engine boundary trades in: `full` — source-fidelity output of the transpiler, preserving comments, pipes, bareword commands, number-base annotations, dq-string flags, and optional line-number annotations — and `norm` — the reduced vocabulary the engine actually executes, produced by a separate `normalize(full) -> norm` primitive. Norm keeps line info by default so runtime errors can point at source lines; everything cosmetic (comments, bwc atoms whose meaning is settled, dq flags, base annotations) is folded away or dropped, and pipes desugar to their equivalent nested calls. The `.caspj` extension and `text/x-caspianj` content-type cover both variants; distinguishing full from norm is a client concern based on which atom shapes appear. Caches store source (`.casp`) plus a norm sidecar tagged by transpiler version so the engine's load path is `json.decode + walk`, with the source alongside as the re-transpile fallback when the version tag says stale.",
	"status": "spec — the two-format split, the atom-shape distinction, the transpile/normalize API pair, and the cache-storage strategy are settled. The exhaustive list of atom shapes present only in `full` (and their `norm` equivalents) tracks the transpiler as it lands features.",
	"audience": "transpiler and engine implementers wiring the format boundary; cache implementers deciding what bytes to write per version; tool authors (debuggers, source-map viewers, formatters) picking which format to consume"
}}
~~~

The Caspian transpiler produces **CaspianJ** (CaspJ), a JSON tree the engine executes. There are two variants of CaspJ, sharing the same schema but drawing from different atom vocabularies: **full** and **norm**.

## Full

**Full CaspJ** is the direct output of `transpile(source)`. It preserves every distinction the source expressed:

- **Comment atoms** — `{comment: "text"}` appear inline where source comments did.
- **Line annotations** — opt-in via `transpile(source, {lines: true})`. Every value-atom object carries a `line` field; every statement row carries a trailing `{line: N}` meta-atom.
- **Number-base annotations** — a literal written `0o755` produces `{value: 493, base: "oct"}`; a literal written `493` produces `{value: 493}`.
- **Double-quote flag** — a string written `"hi"` produces `{value: "hi", dq: true}`; `'hi'` produces `{value: "hi"}`.
- **Bareword-command atoms** — `field`, `getter`, `private`, `auto_run`, etc. stay as `{bwc: "field"}` atoms rather than being resolved.
- **Pipe operators** — `A | B` stays as `{op: "|", left: A, right: B}` rather than desugaring to a call.
- Other structural sugars kept unresolved.

Full is the readable, round-trippable form. It is what test fixtures assert against; what debuggers, formatters, and source-map tools consume; and the starting point every other format is derived from.

## Norm

**Norm CaspJ** is the reduced vocabulary the engine actually executes, produced by `normalize(full)`:

- **Pipes desugar** to their equivalent calls. `A | B` becomes the call `B` would represent with `A` supplied as first-arg or receiver per [syntax/pipes](https://puck.uno/documentation/requirements/syntax/pipes).
- **Bareword-command atoms resolve** where the meaning is settled. A `{bwc: "field"}` at class-body position becomes the concrete field-declaration shape; a `{bwc}` whose meaning is still runtime-decided stays.
- **Comment atoms drop.** The engine has no use for them.
- **Cosmetic flags fold.** `dq: true` folds into the string's escape processing before it lands in norm; `base` annotations drop (the numeric value carries the meaning).
- **Line annotations are kept.** Runtime errors need them to point at source. Both value-atom `line` fields and the trailing statement-row `{line: N}` meta-atoms survive normalization.

Norm is what the engine loads. Its shape is a subset of full's — same schema, fewer atom kinds present — so any tool that reads full also reads norm.

## The transpiler API

Two independent primitives:

- **`transpile(source, opts?)`** → full CaspJ. `opts.lines = true` adds line annotations; default off.
- **`normalize(full_caspj)`** → norm CaspJ.

They stay separate so full-consumers (tests, debuggers, source-fidelity tools) don't pay normalization cost, and so the normalizer can be reasoned about independently of parsing.

The cache-fill pipeline is the composition:

~~~
norm = normalize(transpile(source, {lines: true}))
~~~

## Where each format is used

| Consumer | Format | Why |
|---|---|---|
| Engine | norm | Fastest load path — `json.decode` + walk. Line info kept for runtime errors. |
| Cache | source + norm sidecar | Source is authoritative; norm is a pre-computed accelerator, invalidated on transpiler-version bump. See [cache-dir](https://puck.uno/documentation/requirements/cache-dir). |
| Test fixtures | full | Assertions match source shape; comments, `bwc`, pipes, and line info all readable. |
| Debuggers, formatters, source-map tools | full or source | Full preserves source-fidelity distinctions norm has dropped. |

## Content-Type

Both variants use `text/x-caspianj` when served over HTTP or stored via a cache's `meta.json`. Distinguishing full from norm is a client concern — the two share the same schema, so a norm reader consumes full as well (paying no attention to the extra atoms full has and it doesn't), while a full reader consumes norm as valid input with no cosmetic atoms present. See [content-types](https://puck.uno/documentation/requirements/content-types).
