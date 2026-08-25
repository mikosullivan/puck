# Cheat sheet: CaspM commands

~~~vibecode
{"vibecode": {
	"doc": "cheat_sheets_caspm",
	"role": "one-view reference to every CaspM command atom — the two atom kinds the spec labels 'command' at caspianj § CaspM-only internals. Splits into internal primitives (`{cmd: SHORT}` — closed registry, normalizer-synthesized) and bareword commands (`{bwc: NAME}` — source-writable, open set). Not spec-authoritative — canonical shapes live at caspianj.md.",
	"status": "cheat sheet — table plus short prose; canonical semantics live per-primitive on caspianj § CaspM",
	"audience": "engine implementers and Caspian devs cross-referencing what an atom in a CaspM dump means; readers of the CaspM sidecar files"
}}
~~~

CaspM has two kinds of command atom: **internal primitives** (`{cmd: SHORT}`), which the normalizer synthesizes from a closed registry of short tokens, and **bareword commands** (`{bwc: NAME}`), which come from source-writable bareword identifiers. Every other atom in CaspM is data or structure — the two below are the "do something" atoms. See [caspianj § CaspM-only internals](https://puck.uno/requirements/caspianj#caspm-only-internals-the-in-atom-type) for the design rationale.

## Internal primitives — `{cmd: SHORT}`

Closed registry. Normalizer-synthesized; never appears in CaspJ. Two-character `SHORT` value per entry — chosen because these are the highest-frequency atoms in CaspM.

| `in:` | Long name | Purpose | Envelope |
|---|---|---|---|
| `fc` | `method_call` | The unified call primitive — every call in Caspian (amp, dot method, closure invocation, bareword call, binop) collapses to this shape. See [§ Calls](https://puck.uno/requirements/caspianj#calls). | `[{"cmd": "mc"}, {rc, fn, a?, kw?, blocks?, l?}]` |
| `as` | `assign` | The unified assignment primitive. All source-level assignments (variable, subscript, future attribute) collapse here. Lvalue-shape dispatch: string → variable, `{subscript: ...}` → subscript write. See [§ Assignment](https://puck.uno/requirements/caspianj#assignment). | `[{"cmd": "="}, LVALUE, VALUE, {l}?]` |
| `si` | `suffix_increment` | `$foo++`. See [§ Bumps](https://puck.uno/requirements/caspianj#bumps). | `[{"cmd": "si"}, NAME]` |
| `pi` | `prefix_increment` | `++$foo`. | `[{"cmd": "pi"}, NAME]` |
| `sd` | `suffix_decrement` | `$foo--`. | `[{"cmd": "sd"}, NAME]` |
| `pd` | `prefix_decrement` | `--$foo`. | `[{"cmd": "pd"}, NAME]` |

Future internal primitives (scope-frame push/pop, dispatch fast-paths) get an entry here when spec'd. The registry is closed — no adding a new short at runtime.

## Bareword commands — `{bwc: NAME}`

Source-writable identifiers the parser recognizes as bareword-command-shaped. Open set — anything not reserved as a construct keyword or logical connective can appear as a bwc in bareword-call position. In V1 the normalizer passes them through unchanged; future normalization passes may resolve some at compile time (spec: `{bwc: "field"}` at class-body position becomes a concrete field-declaration shape).

Commonly-seen bwcs in CaspM output:

| `bwc:` | Where it appears | Purpose |
|---|---|---|
| `puts` | Anywhere | Write to `%stdout` with trailing newline. |
| `print` | Anywhere | Write to `%stdout` without trailing newline. |
| `field` | Class body | Declare an instance field on the enclosing class. |
| `private` | Class body / method modifier | Mark following declaration as private to the class. |
| `inherits` | Class body | Declare parent class. |
| `abstract` | Class body / method modifier | Mark class or method as abstract. |
| `const` | Anywhere | Declare a constant binding. |
| `documentation` | Anywhere | Parse-time doc atom. **Dropped by normalize** — never survives to runtime CaspM. |
| `vibecode` | Anywhere | Parse-time AI-context atom. **Dropped by normalize** — never survives. |
| `comment` | Anywhere | Parse-time comment atom. **Dropped by normalize** — never survives. |
| class name (`MyThing`, etc.) | Class-header position | The class being declared. Currently unresolved in normalize; stays as `{bwc: "MyThing"}`. |

For the parser's full reserved-word list (words that never become bwcs), see `RESERVED_FOR_BWC_EXPR` in `src/engine/transpiler.lua`.

## What's NOT a command atom

Distinct from commands — these are data / structure / meta atoms, not "do something" atoms:

| Atom | Long form | Purpose |
|---|---|---|
| `{var: NAME}` | — | Variable reference. |
| `{v: X}` | `{value: X}` | Literal value. |
| `{vo: NAME}` | `{varobj: NAME}` | Variable-object reference (`$$foo`). |
| `{sys: NAME}` | — | System reference (`%foo`). |
| `{hash: [[k, v], ...]}` | — | Hash literal. |
| `{ar: [...]}` | `{array: [...]}` | Array literal. |
| `{cl: {pm, bd}}` | `{closure: {params, body}}` | Closure literal. |
| `{fn: {name, pm, bd}}` | `{function: {name, params, body}}` | Function definition. |
| `{method: {name, pm, bd}}` | — | Method definition. |
| `{class: {bd}}` | `{class: {body}}` | Class definition. |
| `{subscript: {rc, k}}` | `{subscript: {receiver, key}}` | Subscript access. |
| `{ft: URL}` | `{fetch: URL}` | Fetch atom. |
| `{sp: X}` | `{splat: X}` | Sequence splat. |
| `{dsp: X}` | `{double_splat: X}` | Kw splat. |
| `{l: N}` | `{line: N}` | Line meta — only on multi-line statements. |
| `{if: {conditions, else}}` | — | If atom (per spec; see caveat below). |
| `{op: OP, ...}` | — | General operator — should be normalized away (pipes to nested calls, binops to two-element method_call). |

## Actual vs spec

The `transpile` + `normalize` pipeline in `src/engine/` doesn't produce every shape the [caspianj.md](https://puck.uno/requirements/caspianj) spec describes for CaspM. Each subsection below names one divergence: what the spec says, what the pipeline actually emits, and why it matters. Verified by feeding representative Caspian source through `transpiler.transpile()` and `normalize.normalize()` and comparing the output.

Two clusters:

- **Normalizer hasn't visited these constructs** — bumps, subscript-lvalue dispatch, class-body BWC resolution. The transpiler emits the older shapes and normalize passes them through.
- **Transpiler-level gaps** — prefix bumps (`++$x`, `--$x`) don't parse; string interpolation is preserved as one literal instead of being decomposed.

### Bumps

**Spec** ([§ Bumps](https://puck.uno/requirements/caspianj#bumps)): all four bump forms collapse to internal primitives from the closed registry — `{cmd: "si"}`, `{cmd: "pi"}`, `{cmd: "sd"}`, `{cmd: "pd"}`.

**Actual**:

- `$x++` produces `[{"postinc": "x"}]` — a `{postinc: NAME}` atom, not the `{cmd: "si"}` primitive.
- `$x--` produces `[{"postdec": "x"}]` similarly.
- Prefix bumps (`++$x`, `--$x`) raise `transpile: cannot parse: ++$x` — they don't parse at the transpiler layer.

Four documented internal primitives are unemitted; two of them are unreachable from source.

### Subscript assignment

**Spec** ([§ Assignment](https://puck.uno/requirements/caspianj#assignment)): subscript writes collapse to `{cmd: "="}` with a `{subscript}` lvalue that the assign handler dispatches on:

~~~json
[{"cmd": "="}, {"subscript": {"receiver": ..., "key": ...}}, VALUE]
~~~

Lvalue-shape dispatch is a stated design principle — the same `assign` primitive handles variable, subscript, and (future) attribute writes.

**Actual**: `$h['k'] = 42` produces a method_call routing through the receiver's `[]=` method:

~~~json
[{"cmd": "mc"}, {"fn": "[]=", "rc": {"var": "h"}, "a": [{"v": "k"}, {"v": 42}]}]
~~~

Two different mechanisms for assignment (assign primitive for `$var = ...`, method dispatch for `$h[k] = ...`) instead of the spec's uniform `assign`-with-lvalue-dispatch.

### String interpolation

**Spec** ([§ String interpolation](https://puck.uno/requirements/caspianj#string-interpolation)): `"hi $name"` decomposes into a chain of `+`-method dispatches at CaspM time. String's `+` handles stringification of interpolated values via the receiver's implicit `.to_string`.

**Actual**: `"hi $name"` produces a single value atom carrying the literal source string:

~~~json
{"v": "hi $name"}
~~~

Interpolation isn't processed at either the transpiler or normalizer layer. The `$name` token is not parsed as a variable reference; no `+` chain materializes. Same for expression interpolation `${$a + $b}`.

### Class-body BWC resolution

**Spec** ([§ CaspM](https://puck.uno/requirements/caspianj#caspm)): "A `{bwc: 'field'}` at class-body position becomes the concrete field-declaration shape." Bareword-command atoms whose meaning is settled by context get resolved to their concrete atom shape at normalize time.

**Actual**: `field $x` inside a class body stays as a generic bareword-command row:

~~~json
[{"bwc": "field"}, {"var": "x"}]
~~~

The class name itself also stays as a BWC row (`[{"bwc": "MyThing"}]`) rather than resolving into any class-declaration atom. Contextual BWC resolution isn't implemented for class-body position.

### `return`

The spec doesn't formally define a return atom shape, but its design principle ("push structural analysis to normalize time") suggests `return` is a candidate for collapsing to a CaspM primitive.

**Actual**: `return 42` inside a function body comes out as `["scope", "return", {"v": 42}]` — an old scope-op row. Not a divergence from a stated spec, just an unvisited construct.

## Not divergences

Spec and code agree on these — listed here so the divergence list above isn't misread as covering everything:

- **Key shortening** — `line → l`, `value → v`, `body → bd`, `args → a`, `params → pm`, `closure → cl`, `fetch → ft`, `array → ar`, `varobj → vo`, `begin_end → be`. Applied consistently by the normalizer. (Spec examples still show long-key form pending a mechanical sweep; the code emits short keys.)
- **`{cmd: "mc"}` for calls** — amp calls, dot method calls, closure invocations, and binops all collapse to `method_call` with `{fn, rc, a, opts?, blocks?}` envelope. Matches spec.
- **`{cmd: "="}` for variable assignment** — `$x = 1` produces `[{"cmd": "="}, "x", {"v": 1}]`. Matches spec.
- **`unless` → negated-`if`** — the normalizer wraps the condition with `{op: "!"}` and rewrites `unless_end` → `if_end`, then that flows through the if-atom collapse below. Matches spec.
- **If-atom collapse** — `if / elsif / else` produces `{if: {conditions: [{test, action}], else: <action>}}`. `else` field omitted when the source has no else clause. Matches [§ If](https://puck.uno/requirements/caspianj#if) on the outer shape, but with an intentional deviation on the inner shape (see next entry).
- **`action` carries a closure envelope** — each branch's `action` (and the top-level `else`) is a `{cl: {pm, bd}}` closure atom, not a bare statement list. This is a deliberate design choice: blocks are closures, and at execution time each block invocation pushes a fresh frame with `lexical_parent` pointing at the enclosing frame. Variables assigned inside the block don't leak into the enclosing scope. Spec text at [§ If](https://puck.uno/requirements/caspianj#if) still shows action as a bare `[<statement-atoms>]` list — the spec needs updating to reflect this.
- **Ternary and if share the outer shape** — source `cond ? then : else` normalizes to the same `{if: {conditions, else}}` outer atom. Ternary branches are single expressions, not blocks, so they don't carry the closure envelope; statement-form if does. (Ternary's inner shape may be revisited when that walkthrough happens.)
- **`until` → negated-`while`** — same rewrite for the loop counterpart. Matches spec.
- **`{bwc: NAME}` atoms pass through unchanged in V1** — spec explicitly says this, and the normalizer honors it (see class-body BWC divergence above for the ONE place the spec asks for further resolution).
- **Comment, `documentation`, `vibecode` atoms dropped** — the normalizer strips all three. Matches spec.
- **Cosmetic flags dropped** — `base` (number-base annotation), `dq` (double-quoted marker), `sym` (`:foo` symbol form). All folded / dropped by normalize. Matches spec.
