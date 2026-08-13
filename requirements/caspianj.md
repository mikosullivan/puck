# CaspJ (source-fidelity) and CaspM (the AST)
<!--index: 18-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspianj",
	"role": "spec for the two JSON formats the transpiler / engine boundary trades in. CaspJ (CaspianJ) — source-fidelity output of the transpiler, preserving comments, pipes, dot operators, bareword commands, amp atoms for &x calls, number-base annotations, dq-string flags, symbol-notation flags for `:foo`-style strings, and optional line-number annotations. CaspM (Caspian machine) IS THE AST — the fully-resolved tree the engine executes, produced by normalize(caspj); has its own vocabulary tuned for direct dispatch, including internal primitives (`{in: 'fc'}` for function_call etc.) that never appear in CaspJ. `&x` invocations collapse in CaspM to `function_call` with `fn:'call'` — no runtime property lookup, always dispatches to the receiver's `.call` method. Two atom types for commands: `bwc:` for source-writable barewords (puts, return, field...) and `in:` for CaspM-only normalizer-synthesized primitives (fc, as, si/pi/sd/pd) from a closed registry with 2-char short values. Every atom shape in CaspM has one execution semantic — the engine walks the tree, dispatches by atom shape, no per-execution parsing or ambiguity resolution. The two vocabularies OVERLAP on shared atoms (var, value, varobj, hash/array literals, splat markers) but neither is strictly nested inside the other. Files: .caspj for CaspJ, .caspm for CaspM. Content-types: text/x-caspianj for CaspJ, text/x-caspm for CaspM. Caches store source (.casp) plus a .caspm sidecar tagged by transpiler version; source is authoritative and re-transpiled when the version tag says stale. Design principle for CaspM: anything the normalizer can decide once at compile time shouldn't be re-decided per execution — push structural analysis, DSL resolution, transformer chains, constant folding, and any other pre-computable work to norm time.",
	"status": "spec — the two-format split, CaspM-as-AST framing, the CaspJ / CaspM vocabulary distinction, the transpile/normalize API pair, and the cache-storage strategy are settled. The exhaustive list of atom shapes present only in CaspJ (source-fidelity) or only in CaspM (engine-execution) tracks the transpiler as it lands features.",
	"audience": "transpiler and engine implementers wiring the format boundary; cache implementers deciding what bytes to write per version; tool authors (debuggers, source-map viewers, formatters) picking which format to consume"
}}
~~~

The Caspian transpiler produces **CaspJ** (CaspianJ), a JSON tree preserving what the source expressed. The normalizer converts that into **CaspM** (Caspian machine), which IS the AST the engine executes.

**Three phases, clean responsibilities:**

~~~
Caspian source  →  CaspJ  →  CaspM = AST  →  execution
                (transpile)  (normalize)      (engine walk)
~~~

- **Transpiler** — source → CaspJ. Source-fidelity JSON. Preserves everything the source expressed (comments, pipes, dots as op atoms, bwc atoms for known-at-parse-time commands, base annotations, dq flags, sym-notation flags, line info).
- **Normalizer** — CaspJ → CaspM. Produces the AST. Everything the engine would have parsed or decided per execution moves here: collapse of all calls to the `function_call` internal primitive, operator-sugar resolution, class-body DSL resolution, transformer-chain application, constant folding where possible.
- **Engine** — walks the AST. Every atom shape has ONE dispatch handler; there's no interpretation of ambiguous shapes, no per-execution parsing, no runtime figuring-out of what an atom means.

The two vocabularies share many atoms (variables, values, hash / array literals, splat markers — anything both the source can express AND the engine can execute directly) but **neither is strictly nested inside the other**. CaspJ has source-fidelity atoms CaspM resolves or drops; CaspM has AST-only atoms CaspJ never emits.

## The design principle

**Anything the normalizer can decide once at compile time shouldn't be re-decided per execution.** Every ambiguity resolved at norm time is runtime cost saved and one less thing the engine has to know about. When adding a new construct, always ask: "does the engine need to decide anything at runtime for this?"

- **Yes, for genuinely dynamic reasons** (receiver type on method dispatch, live variable values, fetched content) → stays as an engine primitive.
- **No, it's known at norm time** (DSL command meaning, transformer chain results, class-body declarations, literal-operand constant folding) → the normalizer pre-resolves it.

Corollary: CaspM's atom vocabulary can evolve freely for dispatch efficiency. Adding a new pre-resolved atom shape (like `{field: {...}}` for class-body DSL) doesn't affect the source language, doesn't affect CaspJ, doesn't affect tools — just makes the engine faster.

## CaspJ

**CaspJ** is the direct output of `transpile(source)`. It has **two purposes**:

1. **Input to the normalizer** that produces CaspM for execution.
2. **Round-trippable representation** for tools that recompile back to Caspian source — formatters, differs, linters, refactor tools. Every tool that reads Caspian source should go through the canonical transpiler, never parse Caspian text directly.

Preserving every distinction the source expressed is what makes both purposes work:

- **Comment atoms** — `{comment: "text"}` appear inline where source comments did. Positional; a comment atom at index N in the enclosing list sits between statement N-1 and statement N+1. With `{lines: true}` each carries a `line` field, so formatters can distinguish "trailing on the same line as statement X" from "standalone before statement Y."
- **`vibecode` heredocs** — `[{bwc: "vibecode"}, {value: "..."}]` statement rows preserved intact. These are parse-time metadata (AI-consumer context) with no runtime effect.
- **`documentation` heredocs** — `[{bwc: "documentation"}, {value: "..."}]` statement rows preserved intact. Same category as vibecode — parse-time only, no runtime effect.
- **Line annotations** — opt-in via `transpile(source, {lines: true})`. Every value-atom object carries a `line` field. **Multi-line statement rows** additionally carry a trailing `{line: N}` meta-atom recording the line where the statement ends (typically where `end`, `)`, or the closing marker sits). **Single-line statements** get no trailing meta — the inner atoms already share the statement's line, so the meta would be redundant. See [§ Statement-line meta](#statement-line-meta) for the rule in detail.
- **Number-base annotations** — a literal written `0o755` produces `{value: 493, base: "oct"}`; a literal written `493` produces `{value: 493}`.
- **Double-quote flag** — a string written `"hi"` produces `{value: "hi", dq: true}`; `'hi'` produces `{value: "hi"}`.
- **Symbol-notation flag** — a string written `:foo` produces `{value: "foo", sym: true}`; `'foo'` produces `{value: "foo"}`. `:foo` and `'foo'` are the same string value (Caspian has no symbols), but the source-form distinction is preserved in CaspJ for tools that want to render it back exactly as written.
- **Bareword-command atoms** — `field`, `private`, `inherits`, etc. stay as `{bwc: "field"}` atoms rather than being resolved.
- **Op atoms** — pipes (`A | B` → `{op: "|", left, right}`), dots (`$foo.bar` → `{op: ".", left, right, args?}`), bumps (`$foo++` → `{op: "++_suffix", operand}`), and other source-level operators stay as op atoms.
- **Bareword calls stay row-shaped** — `&func(1, 2)` produces `[{amp: "func"}, {value: 1}, {value: 2}, {line: N}]`, preserving the source's positional-arg layout.

CaspJ is the readable, round-trippable form. Test fixtures assert against it; debuggers, formatters, and source-map tools consume it; it's the starting point every other format is derived from. Original whitespace and blank-line choices are NOT preserved — those are the formatter's domain (regenerated per the user's `style.json`), not something CaspJ owns.

## CaspM

**CaspM** is the engine-execution format produced by `normalize(caspj)`. Its vocabulary is tuned for the interpreter — a small set of dispatch shapes the runtime dispatches on directly, with as much structural analysis pushed to normalization time as possible.

Compared to CaspJ:

- **All calls collapse to a single CaspM internal primitive, `function_call` (`{in: "fc"}`).** Bareword calls, dot method calls, closure invocations, downloaded-method applications — all become one shape. See [§ Calls](#calls) below.
- **Operator sugar dispatches to internal primitives.** Pipes desugar to their equivalent calls. Bumps (`++`, `--`) become direct `{in: "si"}` / `{in: "pi"}` / etc. dispatches. See [§ Bumps](#bumps).
- **Bareword-command atoms resolve** where the meaning is settled. A `{bwc: "field"}` at class-body position becomes the concrete field-declaration shape; a `{bwc}` whose meaning is still runtime-decided stays.
- **Comment, `vibecode`, and `documentation` atoms drop.** All three are parse-time metadata with no runtime effect — preserved in CaspJ so tools that recompile back to Caspian source can render them, absent from CaspM because the engine has no use for them.
- **Cosmetic flags fold.** `dq: true` folds into the string's escape processing before it lands in CaspM; `base` annotations drop (the numeric value carries the meaning); `sym: true` drops (since `:foo` and `'foo'` produce the same string value, the source-form distinction has no runtime meaning).
- **Line annotations are kept.** Runtime errors need them to point at source. Value-atom `line` fields survive; trailing statement-row meta-atoms survive only on multi-line statements (same rule as CaspJ — the transpiler emits them only there in the first place).

**CaspM primitives are documented using Caspian-shaped syntax** as an explanatory convenience — a call to `function_call(function: X, args: [Y])` reads more naturally than the raw JSON. **Those primitives are not user-writable in Caspian source.** They exist only in CaspM; only the normalizer emits them. Developers write ordinary Caspian; the normalizer produces the CaspM shape.

### Key mapping

**CaspM uses short keys for size efficiency; CaspJ keeps the long readable keys.** The normalizer rewrites keys during CaspJ → CaspM conversion. Every high-frequency key gets a short form; keys that are already three characters or fewer stay unchanged.

| Long (CaspJ) | Short (CaspM) | Bytes saved per occurrence |
|---|---|---|
| `line` | `l` | 3 |
| `function` | `fn` | 6 |
| `receiver` | `rc` | 6 |
| `args` | `a` | 3 |
| `opts` | `o` | 3 |
| `blocks` | `b` | 5 |
| `value` | `v` | 4 |
| `body` | `bd` | 2 |
| `params` | `pm` | 4 |
| `begin_end` | `be` | 7 |
| `varobj` | `vo` | 4 |
| `subscript` | `sub` | 6 |
| `closure` | `cl` | 5 |
| `array` | `ar` | 3 |
| `splat` | `sp` | 3 |
| `double_splat` | `dsp` | 9 |
| `fetch` | `ft` | 3 |
| `key` (in subscript atom) | `k` | 2 |
| `var` | unchanged (3 chars) | — |
| `bwc` | unchanged (3 chars) | — |
| `hash` | unchanged (4 chars) | — |
| `if` | unchanged (2 chars) | — |

**CaspJ-only keys** (never appear in CaspM, so no mapping needed): `op`, `left`, `right` (op-atom slots), `sym`, `dq`, `base`, `comment`.

**Rationale:** minified CaspM ships in the core binary; every byte counts. Key repetition is where JSON is fattest — atom-key names appear thousands of times across a stdlib. Shortening high-frequency keys yields ~15-25% file-size reduction with no format-format change (still JSON, still tool-compatible with a mapping in hand). Tools that consume CaspM directly learn the mapping from this table — modest developer-side cost, real deployment savings.

**Debuggability during engine development:** engine devs inspecting a CaspM file to trace normalizer output see short keys. Not as immediately readable as long keys, but the mapping is small enough to memorize with light reference. Devs can also run CaspJ (long keys) side-by-side during debugging — same tree, readable form.

**Example update status:** the CaspM JSON examples throughout this doc still show the long-key form; they'll be updated to short keys in a mechanical sweep. Where an example currently shows a long key, refer to the mapping above for the CaspM name — the example's shape and semantics are unchanged, only the key spellings change.

### CaspM-only internals: the `in:` atom type

CaspM has two distinct kinds of command atom:

- **`{bwc: "name"}`** — a **bareword command** the source could have written. `puts`, `return`, `field`, `private_const`, etc. Present in both CaspJ (the transpiler's representation of a source-level bareword call) and CaspM (unchanged, or resolved further where the meaning is settled).
- **`{in: "SHORT"}`** — a **CaspM internal primitive** the normalizer synthesized. Never appears in CaspJ; never callable from Caspian source. Distinct atom type so a reader of CaspM can tell "the normalizer put this here" apart from "source wrote this." `in` for "internal."

The `in:` value comes from a **closed registry** (short, engine-only tokens):

| Primitive | `in:` short | Purpose |
|---|---|---|
| `function_call` | `fc` | The unified call primitive. See [§ Calls](#calls). |
| `assign` | `as` | The unified assignment primitive. See [§ Assignment](#assignment). All source-level assignments (variable, subscript, future attribute) collapse to this. |
| `suffix_increment` | `si` | `$foo++`. See [§ Bumps](#bumps). |
| `prefix_increment` | `pi` | `++$foo`. |
| `suffix_decrement` | `sd` | `$foo--`. |
| `prefix_decrement` | `pd` | `--$foo`. |

Future normalizer-emitted primitives (scope-frame push/pop, dispatch fast-paths, etc.) get an entry here when spec'd.

**Why a separate atom type instead of `{bwc: "function_call"}`.** Two reasons:

1. **Semantic clarity.** `bwc` conflates source-writable commands with normalizer-only synthesized ones — they share the atom shape but have very different provenance. Splitting them is a truer model: `bwc` = source spoke it, `in` = normalizer synthesized it.
2. **Byte cost.** These primitives are the highest-frequency atoms in CaspM (every call is `function_call`). Under `bwc`, `{"bwc":` `"function_call"}` costs 27 bytes per occurrence; under `in`, `{"in": "fc"}` costs 14 — savings of 13 B on the single most common atom in the format. Similar wins on the bump primitives (17 B each).

**Rule for value shortening.** Because the `in:` registry is closed and engine-only, values in it get a 2-character short form. Contrast with `bwc:` values, which are source-writable words and stay verbatim — a `bwc:` value is a real command name, not a token that maps through a table.

**Debuggability.** Engine devs seeing `{"in": "fc"}` in a CaspM file know immediately: normalizer-synthesized, look up in the table above. Seeing `{"bwc": "puts"}` — source wrote `puts` (perhaps still context-decided, perhaps already resolved). The visual distinction pays for the small extra mental cost of the second table.

### Statement-line meta

**When line annotations are enabled** (via `transpile(source, {lines: true})`), value atoms all carry a `line` field. Statement rows additionally carry a trailing meta-atom `{line: N}` (or `{l: N}` in CaspM) — but **only when the statement spans more than one source line**.

**Rule:** the trailing statement-line meta appears iff the statement's first token is on a different source line than its last token.

- **Single-line statement** — inner atoms all share the same line; the meta would be pure redundancy. Omit it.
- **Multi-line statement** — inner atoms carry the line of the atom, which may differ from the line where the statement closes. The trailing meta records the statement's END line, used for stack-frame and error reporting.

**Examples.**

Single-line statement (no trailing meta):

~~~caspian
&foo 1, 2
~~~

~~~json
[{"amp": "foo"}, {"value": 1, "line": 1}, {"value": 2, "line": 1}]
~~~

Multi-line statement (trailing meta on the outer row; inner rows follow the same rule recursively):

~~~caspian
$fn = function()
	&foo
end
~~~

~~~json
[
	{"in": "as"},
	"fn",
	{"function": {
		"body": [
			[{"amp": "foo"}]
		],
		"params": []
	}},
	{"line": 3}
]
~~~

The outer `assign` row spans lines 1-3, so it gets `{"line": 3}`. The inner `&foo` row is a single-line statement on line 2, so it gets no trailing meta (its atoms carry `line: 2` where line info is needed).

**Why this shape.** The distinguishing marker for a line-meta atom is still the sole-`line`-key shape — parsers that walk statement rows check the last atom for `{line: N}` (or `{l: N}` in CaspM) and treat it as meta iff it has exactly that one key. The rule change is only about WHEN the transpiler emits the atom, not about its shape.

**Rejected alternatives.**

- **Always emit.** Simple rule, but wastes 6-8 bytes on every single-line statement — the common case. Adds up on large stdlibs.
- **Never emit; derive from inner atoms.** Saves the most bytes, but runtime error reporting on multi-line statements loses the "where did this statement end" info. A statement's LAST line often reads more naturally in stack traces than the FIRST.

**Cost of the middle-ground check.** The normalizer already walks statement rows; asking "is the statement's first atom's line == last atom's line?" is an O(1) check per statement. Negligible.

### Stripping line info from CaspM

`normalize(caspj, {lines: false})` produces CaspM with all line annotations removed — every value atom loses its `l` field, and no trailing statement-line meta is emitted. The output is byte-for-byte the same as if the source had been transpiled with `{lines: false}` in the first place.

**Deferred for V1: core binary keeps line info.** The core-build originally intended to use `{lines: false}` to shrink the stdlib CaspM, since runtime errors inside stdlib code point at CaspM the user can't see anyway. That's the eventual target, but during the harden-and-stabilize phase Caspian devs need line info in stdlib CaspM to triage bugs surfacing from inside the stdlib itself. The opt stays in the spec; the core build defers using it until the stdlib is proven stable. See [core § Core Caspian code storage](https://puck.uno/requirements/core/#core-caspian-code-storage) for the deferral note.

**When to strip.** The strip should be flipped on when stdlib code has demonstrated stability — a rough criterion like "N months without a stdlib bug that traces to a specific line," "the test suite covers X% of stdlib," or "V1 has been running in real deployments for M weeks." Without a trigger, "defer" tends to become "forever."

**Where the opt DOES apply.** Tools that build shipped bundles from Caspian source (packaged apps, embedded runtimes) may already flip `{lines: false}` to save space when the code is not the debug target. User code (application source, downloaded classes fetched at runtime) should keep `{lines: true}` — runtime errors need to report the actual source line.

**Size impact estimate.** Line info dominates when it's present: every value atom carries `"l": N` (≈8 bytes with the short key) plus the multi-line-statement trailing metas. On a stdlib file that's ~25-30% of the bytes; stripping is a bigger single lever than key-shortening was — worth remembering when the trigger fires.

**Why not always strip at the CaspJ level?** Because the same CaspJ may feed multiple downstream consumers — a cache holds one canonical CaspJ, and different builds (test runner needs lines, core-binary embed eventually doesn't) normalize it differently. Stripping at normalize time keeps the CaspJ shape stable and puts the decision at the last step where it matters.

## Reserved passthrough fields

**`misc`** and **`corporate`** are reserved as passthrough field names on any CaspJ or CaspM node. The engine promises never to use those names for anything else. Developer metadata stashed under either name is safe from name collisions when the engine's vocabulary grows.

Same reservation applies to [all Puck hashes](https://puck.uno/requirements/bryton/xeme/) and drives the built-in [Misc / Corporate](https://puck.uno/requirements/built-in-classes/misc-and-corporate) utility classes.

## Calls

<span class="tag">function-call-bwc</span>

Every call in Caspian — amp call (`&x`), method call (via dot), closure invocation, downloaded-method application — collapses in CaspM to a single internal primitive: `function_call` (`{in: "fc"}`). One shape, one dispatch. Amp calls (`&x`) become function_call with `receiver: x, function: "call"` — always dispatching to the receiver's `.call` method, no runtime property lookup. Dot method calls (`$foo.bar(...)`) become function_call with `receiver: {var:"foo"}, function: "bar"`. This unification matches the callables model where a function IS a method (see [callables idea](https://puck.uno/ideas/callables#function-is-method)) — the object is the same, invocation context varies.

Source-writable bareword commands (`puts`, `return`, `field`, `private_const`, etc.) are a separate atom type — `{bwc: "name"}` — and DON'T collapse to function_call. They stay as-is or get resolved further where their meaning is settled.

### The function_call envelope

Documented in Caspian-shaped syntax as an explanatory aid — this is CaspM notation, not user-writable:

~~~caspian
function_call(
	function: <callable-or-name-expression>,
	receiver: <expression>,
	args: [<expression>, ...],
	opts: {<name>: <expression>, ...},
	blocks: [<callable>, ...]
)
~~~

Fields:

- **`receiver`** (required) — an atom that evaluates to the receiver object. Every function_call has one — amp calls use the callable itself; dot calls use the left side of the dot. `%self` and `%bucket` inside the invoked method's body are bound to this receiver.
- **`function`** (required) — either a plain string that names a method to look up on the receiver, OR an atom that evaluates to a callable. String form is by far the most common: amp calls use `"call"`; dot calls use the bareword method name. Callable-atom forms (`{var: NAME}`, `{fetch: ...}`, `{begin_end: ...}`, `{closure: ...}`) appear when the source used a callable expression on the RHS of a dot (`$foo.$fn`, `$foo.%('url')`, etc.).
- **`args`** (optional) — the positional args to pass to the callable, as a JSON array of atoms. Splat markers may appear as entries; see [§ Splat atoms](#splat-atoms).
- **`opts`** (optional) — the keyword args to pass to the callable, as a JSON **array of entries** where each entry is either `[key_string, value_atom]` (a keyed entry) or `[{double_splat: X}]` (a kw-splat marker). See [§ Splat atoms § Kw splat](#kw-splat-double_splat-x) for the shape rationale.
- **`blocks`** (optional) — a JSON array of atoms (typically `{closure: ...}` or `{function: ...}` atoms) representing trailing `do end` / `dofunc end` blocks. Order preserved from source.

Fields are omitted when they carry no information — a no-arg amp call has an envelope with just `receiver` and `function`.

### CaspJ (source-fidelity) shapes

CaspJ preserves the source shape of the call for tools that need to see what the developer wrote.

**Bareword call.** `&func(1, 2)` in CaspJ is a row starting with the amp atom, preserving the transpiler's positional-arg layout:

~~~json
[{"amp": "func"}, {"value": 1}, {"value": 2}, {"line": N}]
~~~

**Method call (dot).** `$foo.bar(1, 2)` in CaspJ is a `{op: "."}` op atom, with args attached to the op:

~~~json
{
	"op": ".",
	"left": <receiver-atom>,
	"right": <method-spec-atom>,
	"args": [ ... ],
	"opts": { ... },
	"blocks": [ ... ]
}
~~~

The `right` slot accepts three source-level shapes:

- **Bareword method name.** `$foo.bar` — RHS is the plain string `"bar"`. Engine looks up a method by that name on the receiver.
- **String expression.** `$foo.('bar')` — RHS is any expression that evaluates to a string. Same runtime behavior as bareword form once the string is in hand.
- **Function-producing expression.** `$foo.$fn`, `$foo.&getname`, `$foo.(begin ... end)`, `$foo.%('url')` — RHS is any expression that evaluates to a callable.

Dispatch at eval time discriminates on the evaluated `right` (which becomes envelope `function` in CaspM): string → name lookup on the receiver's class; callable → invoke on the receiver.

### CaspM: everything is function_call

Both amp calls and dot method calls collapse to the same shape — a `function_call` internal-primitive dispatch with a structured envelope. Every one has both `receiver` and `function`.

**Amp call `&func(1, 2, baz: 'bear') do end`:**

~~~json
[
	{"in": "fc"},
	{
		"receiver": {"var": "func"},
		"function": "call",
		"args": [{"value": 1}, {"value": 2}],
		"opts": [["baz", {"value": "bear"}]],
		"blocks": [{"closure": {"body": [], "params": []}}]
	},
	{"line": N}
]
~~~

**Dot method call `$foo.bar(1, 2, baz: 'bear') do end`:**

~~~json
[
	{"in": "fc"},
	{
		"receiver": {"var": "foo"},
		"function": "bar",
		"args": [{"value": 1}, {"value": 2}],
		"opts": [["baz", {"value": "bear"}]],
		"blocks": [{"closure": {"body": [], "params": []}}]
	},
	{"line": N}
]
~~~

The only difference: amp uses `"call"` as the function name, dot uses the source method name. Structure identical.

### As a sub-expression

When a call appears as a value (RHS of assignment, arg to another call, receiver of a chained dot, etc.), the CaspM form is the same call array WITHOUT the trailing `{line: N}` meta-atom — line info lives on the individual value atoms inside:

~~~json
[{"in": "fc"}, {"function": ..., "receiver": ..., "args": ...}]
~~~

### Chained method calls

`A.B.C(x)` nests left-associatively. The inner call evaluates first, producing an intermediate value that becomes the receiver of the outer call.

CaspJ:

~~~json
{"op": ".", "left": {"op": ".", "left": A, "right": B}, "right": C, "args": [x]}
~~~

CaspM:

~~~json
[{"in": "fc"}, {
	"function": C,
	"receiver": [{"in": "fc"}, {"function": B, "receiver": A}],
	"args": [x]
}]
~~~

### Runtime dispatch

The engine's `function_call` handler:

1. Evaluate `envelope.receiver` — the object to bind `%self` and `%bucket` to.
2. Evaluate `envelope.function`. If it's a string, look up the method by that name on the receiver's class. If it's a callable atom, invoke it against the receiver.
3. Read `envelope.args`, `envelope.opts`, expanding any splat markers.
4. Make `envelope.blocks` available for the callable's body to reach via `%call.blocks`.
5. Invoke the resolved callable.

One handler, one envelope shape, one dispatch path. Every call in the language reduces to this in CaspM.

### Rationale

Neither amp calls nor dot operators are primitive — both are "invoke a method on a receiver" in different clothing. Amp calls always target `.call` (convention over configuration — anything that wants to be `&`-invocable defines `.call`); dot calls target the named method. Making both collapse to `function_call` in CaspM (while CaspJ preserves the source shapes) captures that truthfully. Wins:

- **Interpreter loop is minimal.** After normalization, no `{op: "."}` cases survive in CaspM; no `[{amp: X}, ...]` implicit-call row shape survives. Every call is a `{"in": "fc"}` dispatch with a structured envelope.
- **Structural analysis happens at normalization**, not per-call. Kwargs are separated from positional args; blocks are collected; splat markers are in place. The engine reads named envelope fields directly.
- **One implementation to maintain.** Bugs in "how do trailing blocks attach to a call?" get fixed in the normalizer, not spread across multiple runtime handlers.
- **Extensible.** Future call flavors (safe-nav, super, iter) become new envelope fields or new bwcs sharing the envelope shape, without new interpreter cases.
- **CaspJ stays clean.** The `function_call` primitive is CaspM-only — CaspJ readers (tools, debuggers, formatters) never see it. Full source fidelity in CaspJ; execution primitives in CaspM.

Same pattern pipes already use: `{op: "|"}` in CaspJ, desugared to a plain call in CaspM. Function/method calls follow suit.

## Splat atoms

<span class="tag">splat-atoms</span>

Splat is a universal spreading marker atom that appears in **both CaspJ and CaspM** — the source can express it (`*$parms`, `**$opts`), and the runtime processes it. Same atom shape works wherever a "list of values" (for `*splat`) or a "mapping" (for `**splat`) is expected: function call args, method call args, array literals, hash literals, method-call `opts`.

### Sequence splat: `{splat: X}`

An atom of shape `{splat: <expr>}` in a list context evaluates `<expr>` at runtime, expects an array, and spreads its elements into the surrounding list at the splat's position.

**In call args:**

~~~caspian
&func(1, *$parms, 2)
~~~

CaspM:

~~~json
[{"in": "fc"}, {
	"function": {"amp": "func"},
	"args": [
		{"value": 1},
		{"splat": {"var": "parms"}},
		{"value": 2}
	]
}]
~~~

**In array literals:**

~~~caspian
[1, *$parms, 2]
~~~

CaspM:

~~~json
{"array": [
	{"value": 1},
	{"splat": {"var": "parms"}},
	{"value": 2}
]}
~~~

### Kw splat: `{double_splat: X}`

An atom of shape `{double_splat: <expr>}` in a hash context evaluates `<expr>` at runtime, expects a hash, and merges its entries into the surrounding hash at the splat's position.

**`opts` and hash literals use the ordered-entries shape.** Rather than a JSON hash keyed by strings (which can't hold splat entries), `opts` is a JSON **array** of entries. Each entry is either:

- **A `[key, value]` two-element array** — a keyed entry.
- **A `[{double_splat: X}]` one-element array** — a kw-splat marker.

Length discriminates. Runtime walks the array in order; two-element entries contribute their `[key, value]` pair; one-element entries evaluate the splat, expect a hash, and merge its entries into the surrounding position. Duplicate keys follow last-wins semantics (whichever entry appears later in the array — including entries produced by splat expansion — takes precedence).

**In call opts:**

~~~caspian
&func(**$more_opts, foo: 'bar')
~~~

CaspM:

~~~json
[{"in": "fc"}, {
	"function": {"amp": "func"},
	"opts": [
		[{"double_splat": {"var": "more_opts"}}],
		["foo", {"value": "bar"}]
	]
}]
~~~

**In hash literals:**

~~~caspian
{foo: 'bar', **$more}
~~~

CaspM:

~~~json
{"hash": [
	["foo", {"value": "bar"}],
	[{"double_splat": {"var": "more"}}]
]}
~~~

Same array-of-entries shape at every use site.

**Design rationale.** Ordered entries handles four things uniformly:
- **Splat entries have no key.** A JSON hash requires keys; an array of tuples doesn't. No reserved-name gymnastics.
- **Order matters when splats and explicit keys mix.** The last-wins rule for duplicate keys needs deterministic iteration order; arrays preserve source order exactly.
- **Hash literals and call opts share one shape.** Both are ordered key-value collections that may contain splat markers. Same primitive, no divergence.
- **Consistent with existing hash-literal atom shape.** The transpiler already emits `{hash: [[key, value], ...]}` — this just extends the same pattern to accept splat entries and to be reused as the `opts` shape.

Cost: even a splat-free `opts` becomes an array (`opts: [["foo", {value: "bar"}]]`) rather than a hash — slightly more verbose. Worth it for the uniformity.

### Runtime

For any splat atom encountered while processing a list/hash context:

1. Evaluate the inner expression.
2. Verify it produces the expected type (array for `{splat}`, hash for `{double_splat}`); raise if not.
3. Spread its elements/entries into the surrounding context at the splat's position.

Splat markers are compile-time-visible — the normalizer emits them where the source has `*` or `**`. Runtime just walks the list/hash and expands when it hits a marker. A fast-path "any splats present?" check keeps the no-splat common case cheap.

### Rationale

Splat is a language-level feature, not a call-specific one. Any construct that expects a sequence or mapping (call args, array literals, hash literals, opts) accepts a splat marker in the same shape. Same atom, same runtime semantics, at every use site. Nothing about the marker cares whether it's inside a call or an array literal; the surrounding context defines the expected type.

## Assignment

<span class="tag">assign-bwc</span>

Variable assignment (`$foo = value`), subscript assignment (`$hsh['a'] = value`), and (future) attribute assignment (`$obj.field = value`) all collapse in CaspM to a single internal primitive: `assign` (`{in: "as"}`). It takes an lvalue and a value; runtime dispatches on the lvalue's shape.

### CaspJ (source-fidelity)

Assignment stays as its current scope-op row form or as an op atom — the transpiler's existing shape (`["scope", "setvar", NAME, VALUE, {line}]` for variables, subscript row for subscript writes). No change from the current transpiler output.

### CaspM

Every assignment becomes an `assign` internal-primitive dispatch. Documented in Caspian-shaped syntax as an explanatory aid — this is CaspM notation, not user-writable:

~~~caspian
# Variable assign (Caspian source: $foo = 'bar')
assign 'foo', 'bar'

# Subscript assign (Caspian source: $hsh['a'] = 'bar')
assign {subscript: {receiver: {var: 'hsh'}, key: {value: 'a'}}}, 'bar'
~~~

**Actual CaspM JSON — variable assign `$foo = 'bar'`:**

~~~json
[
	{"in": "as"},
	"foo",
	{"value": "bar"},
	{"line": 1}
]
~~~

**Actual CaspM JSON — subscript assign `$hsh['a'] = 'bar'`:**

~~~json
[
	{"in": "as"},
	{"subscript": {"receiver": {"var": "hsh"}, "key": {"value": "a"}}},
	{"value": "bar"},
	{"line": 1}
]
~~~

### Lvalue-shape dispatch

The `assign` handler dispatches on the second positional arg (the lvalue):

- **String** → variable name. Delegates to `current_scope_agg.set(name, value)` — see [aggregate-hash § Writing via .set](https://puck.uno/requirements/lua/aggregate-hash#writing-via-setkey-value). The scope agg handles find-or-create-in-innermost.
- **`{subscript: {receiver, key}}`** → subscript write. Delegates to the receiver's subscript-set (e.g., `hash.set(key, value)` for hashes, `array.set(index, value)` for arrays).
- **`{attribute: {receiver, name}}`** (future) → attribute write.

Variable assignment doesn't use `{varobj: NAME}` because the varobj might not exist yet (create-if-missing case). The name-string atom identifies the variable-by-name; the scope agg's `.set` handles the find-or-create.

### Frozen-lvalue writes raise

Same as bumps — the frozen check lives in the underlying mutation primitive, not in `assign`. If the target slot is frozen (`$$foo.freeze` for variables, `.freeze_field 'a'` or `.freeze` for hash entries), the underlying write raises. The `assign` primitive just delegates.

### Compound assignments

Source `$x += 5`, `$x -= 5`, `$x *= 2`, `$x /= 2`, `$x %= 3`, `$x **= 2` are sugar for `$x = $x + 5`, etc. The normalizer expands them at CaspM time:

- **CaspJ** — preserves the source form as `["scope", "setvar_op", OP, NAME, VALUE, {line}]`.
- **CaspM** — expands to `[{in: "as"}, NAME, [{in: "fc"}, {receiver: {var: NAME}, function: OP, args: [VALUE]}], {line}?]` — the same `assign` primitive plus a `function_call` for the method-op. No new atom shape.

**Example.** Source `$x += 1` → CaspM:

~~~json
[
    {"in": "as"},
    "x",
    [{"in": "fc"}, {
        "rc": {"var": "x"},
        "fn": "+",
        "a": [{"v": 1}]
    }]
]
~~~

**Same rule for subscript-target compound assigns** (`$hsh['a'] += 1`), with the lvalue's subscript form as the second arg to `assign` and a subscript-read on the receiver for the LHS of the `+` call.

**Trade-off: LHS double-evaluation.** The expanded CaspM reads the lvalue expression once for the RHS computation and once for the write. For a plain variable that's cheap. For a subscript with a computed key (`$hsh[complex_expr()] += 1`), the computed key runs twice — the second one has to match the first. The normalizer hoists the key to a temp binding to preserve single-evaluation semantics (implementation detail; the CaspM shape reflects the hoisted form).

**Removes `setvar_op` from CaspM's primitive vocabulary.** Only `assign` handles all writes; only `function_call` handles the op.

### Rationale

- **One primitive for all assignments.** Bareword variable, subscript, future attribute — all use the same `in:` atom. Dispatch on lvalue shape.
- **Reuses the aggregate `.set` primitive.** Scope-agg write semantics come from the aggregate-hash spec directly; no scope-specific logic.
- **Fail-loud on frozen lvalues** inherits from the underlying mutation primitives.
- **Extensible.** Adding a new lvalue kind (attribute access, path access, etc.) means adding one branch to `assign`'s dispatch — no new primitive.

## String interpolation

<span class="tag">string-interpolation</span>

Source `"foo #{expr} bar"` (double-quoted with `#{...}` interpolation, or interpolating heredocs `<<"EOF"`) is sugar for string concatenation. The normalizer collapses to a left-folded chain of `+` method calls — no dedicated interpolation atom in CaspM.

### CaspJ (source-fidelity)

The transpiler emits an interp atom carrying the parts:

~~~
{interp: [<atom>, <atom>, ...]}
~~~

Every entry is a full atom — literal parts are `{value: "..."}` atoms; interpolated expressions are their normal atoms. Order preserved from source.

**Example.** Source `"total is #{$whole + $frac}"` produces:

~~~json
{"interp": [
    {"value": "total is "},
    {"op": "+", "left": {"var": "whole"}, "right": {"var": "frac"}}
]}
~~~

For `"#{$a} middle #{$b}"` (interpolation at both edges):

~~~json
{"interp": [
    {"var": "a"},
    {"value": " middle "},
    {"var": "b"}
]}
~~~

### CaspM

The normalizer left-folds the parts with `+` method calls, guaranteeing a `String` result:

~~~caspian
"total is #{$whole + $frac}"
~~~

becomes:

~~~
"total is " + ($whole + $frac)
~~~

which is a single `function_call` on `String`'s `+` method. In JSON:

~~~json
[{"in": "fc"}, {
    "rc": {"v": "total is "},
    "fn": "+",
    "a": [
        [{"in": "fc"}, {"rc": {"var": "whole"}, "fn": "+", "a": [{"var": "frac"}]}]
    ]
}]
~~~

Multi-part strings deepen the nesting left-to-right. `"prefix #{$a} middle #{$b} suffix"` folds as `(((("prefix " + $a) + " middle ") + $b) + " suffix")` — four `function_call` atoms, each with the previous chain as receiver.

### Guaranteed-String rule

The chain must START with a string-value atom so the accumulator is a `String` throughout — `String`'s `+` method knows how to stringify its right operand.

- If the source starts with a literal (`"foo #{...}"`), the first `parts[]` entry is already a string atom. Nothing to add.
- If the source starts with an interpolation (`"#{$x} rest"`), `parts[0]` is a non-string atom. The normalizer prepends `{value: ""}` before folding, so the chain becomes `"" + $x + " rest"` — the leading empty string forces `String`'s `+` to dispatch first.

Same rule for the single-interpolation case (`"#{$x}"` with no literals). Prepending `""` yields `"" + $x` — a `String` regardless of `$x`'s type.

### Rationale

- **No new atom shape at the engine level.** `function_call` handles the concat; the interp atom exists only in CaspJ for source-fidelity tools.
- **String's `+` handles stringification.** Numbers, Booleans, and other types get their `.to_string` implicitly through the `+` dispatch. No explicit `.to_string` chain in CaspM. If the developer wants explicit stringification, they can write `$x.to_string` in the interpolation.
- **Cost of the collapse: locality.** A debugger seeing CaspM loses the "this was one interp expression" hint. In practice line info (still kept during V1) plus the source form recoverable from CaspJ make this a small loss.
- **Locality loss is bounded.** CaspJ preserves the interp atom, so any tool that wants to reason about interpolation as a unit can read CaspJ. Only CaspM sees the fully-expanded chain.

## If

<span class="tag">if-atom</span>

The `if / elsif / else` control-flow construct produces an `{if: {...}}` atom that appears in BOTH CaspJ and CaspM — the source's `elsif` chain naturally flattens to the same structured shape at both levels, so no separate desugaring stage exists between them.

### Shape

~~~
{if: {
    conditions: [
        {test: <atom>, action: [<statement-atoms>]},
        {test: <atom>, action: [<statement-atoms>]},
        ...
    ],
    else: [<statement-atoms>]
}}
~~~

Fields:

- **`conditions`** (required) — array of `{test, action}` pairs. Order preserved from source (`if COND1 ... elsif COND2 ... elsif COND3 ...` produces one entry per condition, in source order).
- **`test`** — any atom that evaluates to a truthy or falsy value.
- **`action`** — a body (list of statement atoms) to execute when the corresponding test evaluates truthy.
- **`else`** (optional) — a body to execute when no test matches. Omitted when source has no `else` clause.

### Example

Source:

~~~caspian
if $foo
	puts 'found foo'
elsif $bar
	puts 'found bar'
else
	puts 'found nothing'
end
~~~

Same shape in both CaspJ and CaspM:

~~~json
{
	"if": {
		"conditions": [
			{
				"test": {"var": "foo"},
				"action": [
					[{"bwc": "puts"}, {"value": "found foo"}, {"line": 2}]
				]
			},
			{
				"test": {"var": "bar"},
				"action": [
					[{"bwc": "puts"}, {"value": "found bar"}, {"line": 4}]
				]
			}
		],
		"else": [
			[{"bwc": "puts"}, {"value": "found nothing"}, {"line": 6}]
		]
	}
}
~~~

### Runtime dispatch

The engine's `if`-atom handler:

1. Walk `conditions` in order.
2. Evaluate each `test`; if truthy, execute the corresponding `action` (body of statements) and RETURN the last value of the action.
3. If no test evaluated truthy AND `else` is present, execute `else` and return its last value.
4. If no test truthy AND no `else`, return `null`.

### As an expression

`if` returns the last value of whichever action ran (or the else body, or `null` if nothing matched and no else). Enables both statement-form (return value discarded) and expression-form (`$result = if $foo then 'a' else 'b' end`) with the same atom shape — no distinction at the CaspM level.

### Unless

Source `unless COND ... end` is sugar for `if !COND ... end` — the normalizer collapses `unless` to the same `if` shape with the test wrapped in `{op: "!", operand: <cond>}`. One control-flow shape at the engine level; source `unless` is a parse-time convenience only.

**Example.** Source:

~~~caspian
unless $yes
	&denied
end
~~~

CaspJ preserves the source form for round-trip tooling — the transpiler emits it as an `unless_end` scope-op row (or the equivalent `{unless: ...}` atom in expression position). The normalizer rewrites it:

~~~caspian
if !$yes
	&denied
end
~~~

...and produces the same CaspM shape as if the source had been written that way. Downstream engine dispatch has one code path.

**Rule.** For unless with an else clause, the negation applies to the unless-cond only; the else branch is unchanged. Unless with elsif is not supported in source (per V1); if it were, the sensible rule would be to negate the leading `unless` test but leave subsequent `elsif` tests un-negated (matching Ruby's non-support and Python's absence of elif-in-unless).

### Ternary

Source `cond ? then : else` normalizes to the same `if`-atom shape as a full `if / else` expression. `{op: "?:", cond, then, else}` in CaspJ becomes `{if: {conditions: [{test: <cond>, action: [<then>]}], else: [<else>]}}` in CaspM.

**Example.** Source:

~~~caspian
$label = ($x > 0) ? 'positive' : 'non-positive'
~~~

CaspM:

~~~json
{"if": {
    "conditions": [
        {
            "test": [{"in": "fc"}, {"rc": {"var": "x"}, "fn": ">", "a": [{"v": 0}]}],
            "action": [{"v": "positive"}]
        }
    ],
    "else": [{"v": "non-positive"}]
}}
~~~

The `then` and `else` branches become single-statement `action` / `else` bodies. Semantics match: the untaken branch never evaluates.

**Rationale.** Ternary IS a special case of if — same short-circuit evaluation, same last-value return. Keeping a distinct `{op: "?:"}` shape would require the engine to carry two if-like dispatch paths. Collapsing to `{if: ...}` unifies them.

### Nested if

An if-atom inside an `action` body is just another statement. Recursion falls out naturally; no special handling.

### Rationale

- **Flat conditions array** collapses source-level `elsif` chains to a linear structure the engine walks in one loop. No nested-else traversal.
- **`else` omitted when absent** — no sentinel, no wrapper. Missing field IS the "no else clause" signal.
- **Unless and ternary collapse to this shape** — one control-flow atom serves three source forms.

## Loops

<span class="tag">loops</span>

Two condition-driven loop constructs: `while` and `until`. Same relationship as `if` and `unless` — `until COND` is sugar for `while !COND`.

### While

CaspJ preserves the current transpiler shape:

~~~json
["scope", "while_end", <cond-atom>, {body: [<statements>]}, {line: N}?]
~~~

CaspM keeps the same shape. Runtime dispatch:

1. Evaluate `cond`. If falsy, exit the loop.
2. Execute `body`.
3. Go to 1.

### Until

Source `until COND ... end` normalizes in CaspM to a `while_end` row with the cond negated — same rule as `unless` → `if`. `{op: "!", operand: <cond>}` wraps the condition; everything else is unchanged.

**Example.** Source:

~~~caspian
until $ready
	&poll
end
~~~

CaspM:

~~~json
["scope", "while_end",
    {"op": "!", "operand": {"var": "ready"}},
    {"bd": [
        [{"in": "fc"}, {"rc": {"var": "poll"}, "fn": "call"}]
    ]}
]
~~~

**Rule.** Applies uniformly to `until ... end` and to the post-condition form `begin ... until COND`. The `begin_until` scope-op row similarly rewrites to `begin_while` with negated cond (same transformation, different opening).

### Rationale

- **One loop shape at the engine level.** `while` is the primitive; `until` is source-level negation sugar.
- **Symmetric with `unless` → `if`.** Same negation pattern, same reasoning: the extra keyword buys source-reader clarity, not runtime distinction.
- **Composes with `!`** — an existing op atom shape. No new atom vocabulary needed.

## Bumps

<span class="tag">bump-operators</span>

The `++` and `--` operators are the ONLY Caspian-source way to bump a variable. In CaspJ they stay as op atoms preserving the source form; in CaspM they collapse to direct dispatches on four **CaspM-only** internal primitives: `suffix_increment` (`si`), `prefix_increment` (`pi`), `suffix_decrement` (`sd`), `prefix_decrement` (`pd`). These primitives cannot be called from Caspian source — attempting to write `suffix_increment $$foo` is a parse error. Only the normalizer emits them.

Four variants and the C-idiomatic return semantics:

| Source | CaspM primitive | `in:` value | Sets | Returns |
|---|---|---|---|---|
| `$foo++` | `suffix_increment` | `si` | new value | OLD value (before increment) |
| `++$foo` | `prefix_increment` | `pi` | new value | NEW value (after increment) |
| `$foo--` | `suffix_decrement` | `sd` | new value | OLD value (before decrement) |
| `--$foo` | `prefix_decrement` | `pd` | new value | NEW value (after decrement) |

Mnemonic: **prefix does it first, suffix does it after.** Same convention as C, C++, Java, JavaScript.

### CaspJ (source-fidelity)

Bump operators produce op atoms preserving the source form:

~~~json
{"op": "++_suffix", "operand": {"var": "foo"}}   // $foo++
{"op": "++_prefix", "operand": {"var": "foo"}}   // ++$foo
{"op": "--_suffix", "operand": {"var": "foo"}}   // $foo--
{"op": "--_prefix", "operand": {"var": "foo"}}   // --$foo
~~~

The `operand` slot holds an **lvalue expression** — a settable location the bump can mutate. Currently supported lvalues:

- **Plain variable reference** — `{var: NAME}` for `$foo++`.
- **Subscript access** — the transpiler's subscript row-shape (`[{var: NAME}, "[]", {args: [<key>]}]`) for `$hsh['a']++` / `$arr[0]++`. The key can be any expression; the receiver can be any expression that produces a subscriptable value.
- **Attribute access** — planned; `$obj.field++` would produce an attribute-shaped operand. Not yet spec'd; noted for future.

Bump on an expression that ISN'T an lvalue (`($foo + 1)++`, `&get_something()++`) is a parse error. The transpiler validates the operand at parse time.

### CaspM (direct internal-primitive dispatch)

Each op atom collapses to a direct `in:`-primitive dispatch. The primitive's `in:` value names the operation; the sole positional arg is a **CaspM lvalue atom** that identifies the settable location. The runtime handler dispatches on the lvalue atom's shape.

**Lvalue atom shapes in CaspM:**

- **`{varobj: NAME}`** — the storage slot of a variable. Used for `$foo++` and friends.
- **`{subscript: {receiver, key}}`** — the storage slot at a subscript position. Used for `$hsh['a']++`, `$arr[0]++`, etc. The receiver evaluates to a subscriptable object; the key evaluates to the subscript key.
- (Future: `{attribute: {receiver, name}}` for `$obj.field++` when that lands.)

Example — `$foo++` (variable):

~~~json
[{"in": "si"}, {"varobj": "foo"}, {"line": N}]
~~~

Example — `$hsh['a']++` (subscript):

~~~json
[{"in": "si"}, {"subscript": {"receiver": {"var": "hsh"}, "key": {"value": "a"}}}, {"line": N}]
~~~

The other three bump variants (`prefix_increment` / `pi`, `suffix_decrement` / `sd`, `prefix_decrement` / `pd`) take the same shape with the appropriate `in:` value.

**Notice the argument is an lvalue atom, not a plain value atom** — bumps mutate; the lvalue tells the handler both how to READ the current value and how to WRITE the new value. For a varobj, the handler uses `.value` / `.value=`; for a subscript, it uses subscript get/set; for an attribute (future), attribute get/set.

### Frozen lvalues raise

Bumping a frozen lvalue raises — the fail-loud behavior falls out of the underlying primitives without any bump-specific check:

- **Frozen variable slot** (`$$foo.freeze` was called) — the varobj's `.value=` raises; `$foo++` inherits that.
- **Frozen hash field** (`$hsh.freeze_field 'a'` was called) — the subscript write raises; `$hsh['a']++` inherits that.
- **Frozen whole hash** (`$hsh.freeze` was called) — same subscript-write raise; any bump on any key of `$hsh` raises.

The bump handlers just call the underlying mutator; they don't check frozen state themselves. Freeze enforcement is centralized in the slot / hash-write primitives, and every mutation path (assignment, bump, `.value=`, subscript-set) inherits it consistently.

**Not wrapped in function_call.** Bumps dispatch directly to their engine primitive. `function_call` is one internal primitive (the one that handles user-facing function/method invocation); `suffix_increment` and friends are separate internal primitives, each with its own direct-dispatch handler. The interpreter's dispatch mechanism is uniform (look up the `in:` value, invoke handler); different primitives just have different handlers.

### As a sub-expression

Bumps can appear anywhere an expression can (they return a value, after all). When nested inside another row, the CaspM form is the call array without the trailing `{line: N}` — same rule as any other call sub-expression:

~~~caspian
$new_value = $foo++    # $new_value gets the OLD value of $foo; $foo is now incremented
~~~

CaspM:

~~~json
[
	{"in": "as"},
	"new_value",
	[{"in": "si"}, {"varobj": "foo"}],
	{"line": N}
]
~~~

### Rationale

Bumps are not primitive operators in the source-facing sense — they're syntactic sugar. But the underlying operation IS primitive (mutate a variable-object's value, return old or new). Giving each bump its own CaspM internal primitive:

- **Direct dispatch — no function_call wrapping.** Bumps take one hop to the primitive; general function/method calls take one hop to `function_call` which then handles the callable resolution. Direct primitives keep hot-path operator sugar as cheap as possible.
- **Mutation-in-place semantics live in the variable-object**, not the bump operator. The `in:` value just names which primitive to invoke; the mutation is a normal `.value=` on the varobj.
- **Developers can still write similar mutators.** `&clamp($$x, 0, 10)`, `&swap($$a, $$b)`, `&multiply_by($$x, 2)` — user-defined functions taking varobj args go through `function_call` in CaspM (like any user function). Only the built-in bumps get direct internal-primitive treatment; that's an internal engine optimization for the hottest primitives, invisible from the source side.
- **Extends cleanly.** Any future compound assignment (`+= n`, `-= n`, `*=`, etc.) can either desugar to a direct internal primitive (if built-in) or to a `function_call` (if user code implements it).

## The transpiler API

Two independent primitives:

- **`transpile(source, opts?)`** → CaspJ. `opts.lines = true` adds line annotations; default off.
- **`normalize(caspj, opts?)`** → CaspM. `opts.lines = false` strips any line annotations present in the input; default `true` (preserve what CaspJ has). See [§ Stripping line info from CaspM](#stripping-line-info-from-caspm).

They stay separate so CaspJ-consumers (tests, debuggers, source-fidelity tools) don't pay normalization cost, and so the normalizer can be reasoned about independently of parsing.

The cache-fill pipeline is the composition:

~~~
caspm = normalize(transpile(source, {lines: true}))
~~~

The core-binary build pipeline drops lines to save bytes:

~~~
caspm = normalize(transpile(source, {lines: true}), {lines: false})
~~~

## Where each format is used

| Consumer | Format | Why |
|---|---|---|
| Engine | CaspM | Fastest load path — `json.decode` + walk. Line info kept for runtime errors. |
| Cache | source + CaspM sidecar | Source is authoritative; CaspM is a pre-computed accelerator, invalidated on transpiler-version bump. See [cache-dir](https://puck.uno/requirements/cache-dir). |
| Test fixtures | CaspJ | Assertions match source shape; comments, `bwc`, pipes, op atoms, and line info all readable. Fixtures may also assert against CaspM when the desugaring behavior is what's being tested. |
| Debuggers, formatters, source-map tools | CaspJ or source | CaspJ preserves source-fidelity distinctions CaspM has dropped. |

## File extensions and Content-Types

| Format | Extension | Content-Type |
|---|---|---|
| CaspJ | `.caspj` | `text/x-caspianj` |
| CaspM | `.caspm` | `text/x-caspm` |

The two share a common JSON base but not a common vocabulary — a general-purpose CaspJ reader cannot process CaspM (it will encounter atoms it doesn't recognize, like `{"in": "fc"}` internal primitives), and vice versa. Tools should declare which they consume. See [content-types](https://puck.uno/requirements/content-types).
