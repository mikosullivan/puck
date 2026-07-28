# CaspJ (source-fidelity) and CaspM (the AST)
<!--index: 18-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspianj",
	"role": "spec for the two JSON formats the transpiler / engine boundary trades in. CaspJ (CaspianJ) — source-fidelity output of the transpiler, preserving comments, pipes, dot operators, bareword commands, number-base annotations, dq-string flags, and optional line-number annotations. CaspM (Caspian machine) IS THE AST — the fully-resolved tree the engine executes, produced by normalize(caspj); has its own vocabulary tuned for direct dispatch, including primitives like function_call that never appear in CaspJ. Every atom shape in CaspM has one execution semantic — the engine walks the tree, dispatches by atom shape, no per-execution parsing or ambiguity resolution. The two vocabularies OVERLAP on shared atoms (var, value, varobj, hash/array literals, splat markers) but neither is strictly nested inside the other. Files: .caspj for CaspJ, .caspm for CaspM. Content-types: text/x-caspianj for CaspJ, text/x-caspm for CaspM. Caches store source (.casp) plus a .caspm sidecar tagged by transpiler version; source is authoritative and re-transpiled when the version tag says stale. Design principle for CaspM: anything the normalizer can decide once at compile time shouldn't be re-decided per execution — push structural analysis, DSL resolution, transformer chains, constant folding, and any other pre-computable work to norm time.",
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

- **Transpiler** — source → CaspJ. Source-fidelity JSON. Preserves everything the source expressed (comments, pipes, dots as op atoms, bwc atoms for known-at-parse-time commands, base annotations, dq flags, line info).
- **Normalizer** — CaspJ → CaspM. Produces the AST. Everything the engine would have parsed or decided per execution moves here: bwc-dispatch collapse to `function_call`, operator-sugar resolution, class-body DSL resolution, transformer-chain application, constant folding where possible.
- **Engine** — walks the AST. Every atom shape has ONE dispatch handler; there's no interpretation of ambiguous shapes, no per-execution parsing, no runtime figuring-out of what an atom means.

The two vocabularies share many atoms (variables, values, hash / array literals, splat markers — anything both the source can express AND the engine can execute directly) but **neither is strictly nested inside the other**. CaspJ has source-fidelity atoms CaspM resolves or drops; CaspM has AST-only atoms CaspJ never emits.

## The design principle

**Anything the normalizer can decide once at compile time shouldn't be re-decided per execution.** Every ambiguity resolved at norm time is runtime cost saved and one less thing the engine has to know about. When adding a new construct, always ask: "does the engine need to decide anything at runtime for this?"

- **Yes, for genuinely dynamic reasons** (receiver type on method dispatch, live variable values, fetched content) → stays as an engine primitive.
- **No, it's known at norm time** (DSL command meaning, transformer chain results, class-body declarations, literal-operand constant folding) → the normalizer pre-resolves it.

Corollary: CaspM's atom vocabulary can evolve freely for dispatch efficiency. Adding a new pre-resolved atom shape (like `{field: {...}}` for class-body DSL) doesn't affect the source language, doesn't affect CaspJ, doesn't affect tools — just makes the engine faster.

## CaspJ

**CaspJ** is the direct output of `transpile(source)`. It preserves every distinction the source expressed:

- **Comment atoms** — `{comment: "text"}` appear inline where source comments did.
- **Line annotations** — opt-in via `transpile(source, {lines: true})`. Every value-atom object carries a `line` field; every statement row carries a trailing `{line: N}` meta-atom.
- **Number-base annotations** — a literal written `0o755` produces `{value: 493, base: "oct"}`; a literal written `493` produces `{value: 493}`.
- **Double-quote flag** — a string written `"hi"` produces `{value: "hi", dq: true}`; `'hi'` produces `{value: "hi"}`.
- **Bareword-command atoms** — `field`, `private`, `auto_run`, etc. stay as `{bwc: "field"}` atoms rather than being resolved.
- **Op atoms** — pipes (`A | B` → `{op: "|", left, right}`), dots (`$foo.bar` → `{op: ".", left, right, args?}`), bumps (`$foo++` → `{op: "++_suffix", operand}`), and other source-level operators stay as op atoms.
- **Bareword calls stay row-shaped** — `&func(1, 2)` produces `[{amp: "func"}, {value: 1}, {value: 2}, {line: N}]`, preserving the source's positional-arg layout.

CaspJ is the readable, round-trippable form. Test fixtures assert against it; debuggers, formatters, and source-map tools consume it; it's the starting point every other format is derived from.

## CaspM

**CaspM** is the engine-execution format produced by `normalize(caspj)`. Its vocabulary is tuned for the interpreter — a small set of dispatch shapes the runtime dispatches on directly, with as much structural analysis pushed to normalization time as possible.

Compared to CaspJ:

- **All calls collapse to a single bwc, `function_call`.** Bareword calls, dot method calls, closure invocations, downloaded-method applications — all become one shape. See [§ Calls](#calls) below.
- **Operator sugar dispatches to primitive bwcs.** Pipes desugar to their equivalent calls. Bumps (`++`, `--`) become direct bwc dispatches to `suffix_increment` / `prefix_increment` / etc. See [§ Bumps](#bumps).
- **Bareword-command atoms resolve** where the meaning is settled. A `{bwc: "field"}` at class-body position becomes the concrete field-declaration shape; a `{bwc}` whose meaning is still runtime-decided stays.
- **Comment atoms drop.** The engine has no use for them.
- **Cosmetic flags fold.** `dq: true` folds into the string's escape processing before it lands in CaspM; `base` annotations drop (the numeric value carries the meaning).
- **Line annotations are kept.** Runtime errors need them to point at source. Both value-atom `line` fields and the trailing statement-row `{line: N}` meta-atoms survive normalization.

**CaspM primitives are documented using Caspian-shaped syntax** as an explanatory convenience — a call to `function_call(function: X, args: [Y])` reads more naturally than the raw JSON. **Those primitives are not user-writable in Caspian source.** They exist only in CaspM; only the normalizer emits them. Developers write ordinary Caspian; the normalizer produces the CaspM shape.

### CaspM-only primitives

The current list of bwcs and shapes that appear ONLY in CaspM (never in CaspJ, never callable from Caspian source):

- **`function_call`** — the unified call primitive. See [§ Calls](#calls).
- **`assign`** — the unified assignment primitive. See [§ Assignment](#assignment). All source-level assignments (variable, subscript, future attribute) collapse to this in CaspM.
- **`suffix_increment` / `prefix_increment` / `suffix_decrement` / `prefix_decrement`** — the bump primitives. See [§ Bumps](#bumps). The only Caspian-source way to bump a variable is via the `++` / `--` operators; the underlying bwcs are not directly callable.
- Future normalizer-emitted primitives (scope-frame push/pop, dispatch fast-paths, etc.) will be added here as they get spec'd.

Everything else — `puts`, `return`, `field`, `private_const`, and the rest of the source-writable bwcs — appears in both CaspJ (as the transpiler's representation of the source call) and CaspM (unchanged, or resolved further where the meaning is settled).

## Calls

<span class="tag">function-call-bwc</span>

Every call in Caspian — bareword function call, method call (via dot), closure invocation, downloaded-method application — collapses in CaspM to a single primitive: the `function_call` bwc. Only ONE call bwc exists; the presence or absence of a `receiver` field on its envelope discriminates method calls from bare function calls. This unification matches the callables model where a function IS a method (see [callables idea](https://puck.uno/documentation/ideas/callables#function-is-method)) — the object is the same, invocation context varies.

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

- **`function`** (required) — an atom that evaluates to a callable, OR a plain string that names a method to look up on the receiver. Can be `{amp: NAME}` (bareword function reference), `{var: NAME}` (variable holding callable), a JSON string (method-name lookup — requires `receiver` to be present), a `{fetch: ...}` atom (Puck fetch), a `{begin_end: ...}` atom, a `{closure: ...}` atom, or any expression that produces a callable-or-name.
- **`receiver`** (optional) — an atom that evaluates to the receiver object. When present, `%self` and `%bucket` inside the invoked callable's body are bound to this receiver, and a string `function` becomes a method-name lookup on the receiver's class. When absent, the call is a plain function invocation with no receiver binding.
- **`args`** (optional) — the positional args to pass to the callable, as a JSON array of atoms. Splat markers may appear as entries; see [§ Splat atoms](#splat-atoms).
- **`opts`** (optional) — the keyword args to pass to the callable, as a JSON **array of entries** where each entry is either `[key_string, value_atom]` (a keyed entry) or `[{double_splat: X}]` (a kw-splat marker). See [§ Splat atoms § Kw splat](#kw-splat-double_splat-x) for the shape rationale.
- **`blocks`** (optional) — a JSON array of atoms (typically `{closure: ...}` or `{function: ...}` atoms) representing trailing `do end` / `dofunc end` blocks. Order preserved from source.

Fields are omitted when they carry no information — a no-arg bareword call has an envelope with just `function`.

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

Both bareword calls and method calls collapse to the same shape — a `function_call` bwc dispatch with a structured envelope.

**Bareword call `&func(1, 2, baz: 'bear') do end`:**

~~~json
[
	{"bwc": "function_call"},
	{
		"function": {"amp": "func"},
		"args": [{"value": 1}, {"value": 2}],
		"opts": [["baz", {"value": "bear"}]],
		"blocks": [{"closure": {"body": [], "params": []}}]
	},
	{"line": N}
]
~~~

**Method call `$foo.bar(1, 2, baz: 'bear') do end`:**

~~~json
[
	{"bwc": "function_call"},
	{
		"function": "bar",
		"receiver": {"var": "foo"},
		"args": [{"value": 1}, {"value": 2}],
		"opts": [["baz", {"value": "bear"}]],
		"blocks": [{"closure": {"body": [], "params": []}}]
	},
	{"line": N}
]
~~~

The only structural difference: the method call has `receiver`, the bareword call doesn't. Everything else is identical.

### As a sub-expression

When a call appears as a value (RHS of assignment, arg to another call, receiver of a chained dot, etc.), the CaspM form is the same call array WITHOUT the trailing `{line: N}` meta-atom — line info lives on the individual value atoms inside:

~~~json
[{"bwc": "function_call"}, {"function": ..., "receiver": ..., "args": ...}]
~~~

### Chained method calls

`A.B.C(x)` nests left-associatively. The inner call evaluates first, producing an intermediate value that becomes the receiver of the outer call.

CaspJ:

~~~json
{"op": ".", "left": {"op": ".", "left": A, "right": B}, "right": C, "args": [x]}
~~~

CaspM:

~~~json
[{"bwc": "function_call"}, {
	"function": C,
	"receiver": [{"bwc": "function_call"}, {"function": B, "receiver": A}],
	"args": [x]
}]
~~~

### Runtime dispatch

The engine's `function_call` handler:

1. Read `envelope.function` and resolve to a callable-or-name.
2. If `envelope.receiver` is present, bind `%self` and `%bucket` to it. If `function` is a string, look up the method on the receiver's class.
3. Read `envelope.args`, `envelope.opts`, expanding any splat markers.
4. Make `envelope.blocks` available for the callable's body to reach via `%call.blocks`.
5. Invoke the callable.

One handler, one envelope shape, one dispatch path. Every call in the language reduces to this in CaspM.

### Rationale

Neither bareword calls nor dot operators are primitive — both are specific kinds of "invoke a callable, optionally with a receiver bound." Making them both collapse to `function_call` in CaspM (while CaspJ preserves the source shapes) captures that truthfully. Wins:

- **Interpreter loop is minimal.** After normalization, no `{op: "."}` cases survive in CaspM; no `[{amp: X}, ...]` implicit-call row shape survives. Every call is a `{bwc: "function_call"}` dispatch with a structured envelope.
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
[{"bwc": "function_call"}, {
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
[{"bwc": "function_call"}, {
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

Variable assignment (`$foo = value`), subscript assignment (`$hsh['a'] = value`), and (future) attribute assignment (`$obj.field = value`) all collapse in CaspM to a single primitive: the `assign` bwc. The bwc takes an lvalue and a value; runtime dispatches on the lvalue's shape.

### CaspJ (source-fidelity)

Assignment stays as its current scope-op row form or as an op atom — the transpiler's existing shape (`["scope", "setvar", NAME, VALUE, {line}]` for variables, subscript row for subscript writes). No change from the current transpiler output.

### CaspM

Every assignment becomes an `assign` bwc dispatch. Documented in Caspian-shaped syntax as an explanatory aid — this is CaspM notation, not user-writable:

~~~caspian
# Variable assign (Caspian source: $foo = 'bar')
assign 'foo', 'bar'

# Subscript assign (Caspian source: $hsh['a'] = 'bar')
assign {subscript: {receiver: {var: 'hsh'}, key: {value: 'a'}}}, 'bar'
~~~

**Actual CaspM JSON — variable assign `$foo = 'bar'`:**

~~~json
[
	{"bwc": "assign"},
	"foo",
	{"value": "bar"},
	{"line": 1}
]
~~~

**Actual CaspM JSON — subscript assign `$hsh['a'] = 'bar'`:**

~~~json
[
	{"bwc": "assign"},
	{"subscript": {"receiver": {"var": "hsh"}, "key": {"value": "a"}}},
	{"value": "bar"},
	{"line": 1}
]
~~~

### Lvalue-shape dispatch

The `assign` bwc handler dispatches on the second positional arg (the lvalue):

- **String** → variable name. Delegates to `current_scope_agg.set(name, value)` — see [aggregate-hash § Writing via .set](https://puck.uno/documentation/requirements/lua/aggregate-hash#writing-via-setkey-value). The scope agg handles find-or-create-in-innermost.
- **`{subscript: {receiver, key}}`** → subscript write. Delegates to the receiver's subscript-set (e.g., `hash.set(key, value)` for hashes, `array.set(index, value)` for arrays).
- **`{attribute: {receiver, name}}`** (future) → attribute write.

Variable assignment doesn't use `{varobj: NAME}` because the varobj might not exist yet (create-if-missing case). The name-string atom identifies the variable-by-name; the scope agg's `.set` handles the find-or-create.

### Frozen-lvalue writes raise

Same as bumps — the frozen check lives in the underlying mutation primitive, not in `assign`. If the target slot is frozen (`$$foo.freeze` for variables, `.freeze_field 'a'` or `.freeze` for hash entries), the underlying write raises. The `assign` bwc just delegates.

### Rationale

- **One primitive for all assignments.** Bareword variable, subscript, future attribute — all use the same bwc. Dispatch on lvalue shape.
- **Reuses the aggregate `.set` primitive.** Scope-agg write semantics come from the aggregate-hash spec directly; no scope-specific logic.
- **Fail-loud on frozen lvalues** inherits from the underlying mutation primitives.
- **Extensible.** Adding a new lvalue kind (attribute access, path access, etc.) means adding one branch to the assign bwc's dispatch — no new bwc.

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

Source `unless COND ... end` normalizes in CaspM to `{if: {conditions: [{test: <negated-atom>, action: [...]}]}}` — one shape at the engine level, source `unless` gets its test negated by the normalizer. CaspJ preserves source-level `unless` for source-fidelity tools (specific CaspJ shape for `unless` — TBD; likely a distinct `{unless: ...}` atom or a marker on the `{if: ...}` shape).

### Nested if

An if-atom inside an `action` body is just another statement. Recursion falls out naturally; no special handling.

### Rationale

- **Flat conditions array** collapses source-level `elsif` chains to a linear structure the engine walks in one loop. No nested-else traversal.
- **`else` omitted when absent** — no sentinel, no wrapper. Missing field IS the "no else clause" signal.
- **Same shape in CaspJ and CaspM** — nothing to desugar for the base `if / elsif / else` form. Source structure already matches the AST need.

## Bumps

<span class="tag">bump-operators</span>

The `++` and `--` operators are the ONLY Caspian-source way to bump a variable. In CaspJ they stay as op atoms preserving the source form; in CaspM they collapse to direct dispatches on four **CaspM-only** bwcs: `suffix_increment`, `prefix_increment`, `suffix_decrement`, `prefix_decrement`. Those bwcs cannot be called directly from Caspian source — attempting to write `suffix_increment $$foo` is a parse error. Only the normalizer emits them.

Four variants and the C-idiomatic return semantics:

| Source | CaspM bwc | Sets | Returns |
|---|---|---|---|
| `$foo++` | `suffix_increment` | new value | OLD value (before increment) |
| `++$foo` | `prefix_increment` | new value | NEW value (after increment) |
| `$foo--` | `suffix_decrement` | new value | OLD value (before decrement) |
| `--$foo` | `prefix_decrement` | new value | NEW value (after decrement) |

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

### CaspM (direct bwc dispatch)

Each op atom collapses to a direct bwc dispatch. The bwc name is the operation; the sole positional arg is a **CaspM lvalue atom** that identifies the settable location. The bwc's runtime handler dispatches on the lvalue atom's shape.

**Lvalue atom shapes in CaspM:**

- **`{varobj: NAME}`** — the storage slot of a variable. Used for `$foo++` and friends.
- **`{subscript: {receiver, key}}`** — the storage slot at a subscript position. Used for `$hsh['a']++`, `$arr[0]++`, etc. The receiver evaluates to a subscriptable object; the key evaluates to the subscript key.
- (Future: `{attribute: {receiver, name}}` for `$obj.field++` when that lands.)

Example — `$foo++` (variable):

~~~json
[{"bwc": "suffix_increment"}, {"varobj": "foo"}, {"line": N}]
~~~

Example — `$hsh['a']++` (subscript):

~~~json
[{"bwc": "suffix_increment"}, {"subscript": {"receiver": {"var": "hsh"}, "key": {"value": "a"}}}, {"line": N}]
~~~

The other three bump variants (`prefix_increment`, `suffix_decrement`, `prefix_decrement`) take the same shape with the appropriate bwc name.

**Notice the argument is an lvalue atom, not a plain value atom** — bumps mutate; the lvalue tells the handler both how to READ the current value and how to WRITE the new value. For a varobj, the handler uses `.value` / `.value=`; for a subscript, it uses subscript get/set; for an attribute (future), attribute get/set.

### Frozen lvalues raise

Bumping a frozen lvalue raises — the fail-loud behavior falls out of the underlying primitives without any bump-specific check:

- **Frozen variable slot** (`$$foo.freeze` was called) — the varobj's `.value=` raises; `$foo++` inherits that.
- **Frozen hash field** (`$hsh.freeze_field 'a'` was called) — the subscript write raises; `$hsh['a']++` inherits that.
- **Frozen whole hash** (`$hsh.freeze` was called) — same subscript-write raise; any bump on any key of `$hsh` raises.

The bump bwc handlers just call the underlying mutator; they don't check frozen state themselves. Freeze enforcement is centralized in the slot / hash-write primitives, and every mutation path (assignment, bump, `.value=`, subscript-set) inherits it consistently.

**Not wrapped in function_call.** Bumps dispatch directly to their engine-primitive bwc. `function_call` is one CaspM bwc (the one that handles user-facing function/method invocation); `suffix_increment` and friends are separate CaspM bwcs, each with its own direct-dispatch handler. The interpreter's dispatch mechanism is uniform (look up bwc by name, invoke handler); different primitives just have different handlers.

### As a sub-expression

Bumps can appear anywhere an expression can (they return a value, after all). When nested inside another row, the CaspM form is the call array without the trailing `{line: N}` — same rule as any other call sub-expression:

~~~caspian
$new_value = $foo++    # $new_value gets the OLD value of $foo; $foo is now incremented
~~~

CaspM:

~~~json
[
	"scope", "setvar", "new_value",
	[{"bwc": "suffix_increment"}, {"varobj": "foo"}],
	{"line": N}
]
~~~

### Rationale

Bumps are not primitive operators in the source-facing sense — they're syntactic sugar. But the underlying operation IS primitive (mutate a variable-object's value, return old or new). Giving each bump its own CaspM bwc:

- **Direct dispatch — no function_call wrapping.** Bumps take one hop to the primitive; general function/method calls take one hop to `function_call` which then handles the callable resolution. Direct bwcs keep hot-path operator sugar as cheap as possible.
- **Mutation-in-place semantics live in the variable-object**, not the bump operator. The bwc just names which primitive to invoke; the mutation is a normal `.value=` on the varobj.
- **Developers can still write similar mutators.** `&clamp($$x, 0, 10)`, `&swap($$a, $$b)`, `&multiply_by($$x, 2)` — user-defined functions taking varobj args go through `function_call` in CaspM (like any user function). Only the built-in bumps get direct-bwc treatment; that's an internal engine optimization for the hottest primitives, invisible from the source side.
- **Extends cleanly.** Any future compound assignment (`+= n`, `-= n`, `*=`, etc.) can either desugar to a direct bwc (if built-in) or to a `function_call` (if user code implements it).

## The transpiler API

Two independent primitives:

- **`transpile(source, opts?)`** → CaspJ. `opts.lines = true` adds line annotations; default off.
- **`normalize(caspj)`** → CaspM.

They stay separate so CaspJ-consumers (tests, debuggers, source-fidelity tools) don't pay normalization cost, and so the normalizer can be reasoned about independently of parsing.

The cache-fill pipeline is the composition:

~~~
caspm = normalize(transpile(source, {lines: true}))
~~~

## Where each format is used

| Consumer | Format | Why |
|---|---|---|
| Engine | CaspM | Fastest load path — `json.decode` + walk. Line info kept for runtime errors. |
| Cache | source + CaspM sidecar | Source is authoritative; CaspM is a pre-computed accelerator, invalidated on transpiler-version bump. See [cache-dir](https://puck.uno/documentation/requirements/cache-dir). |
| Test fixtures | CaspJ | Assertions match source shape; comments, `bwc`, pipes, op atoms, and line info all readable. Fixtures may also assert against CaspM when the desugaring behavior is what's being tested. |
| Debuggers, formatters, source-map tools | CaspJ or source | CaspJ preserves source-fidelity distinctions CaspM has dropped. |

## File extensions and Content-Types

| Format | Extension | Content-Type |
|---|---|---|
| CaspJ | `.caspj` | `text/x-caspianj` |
| CaspM | `.caspm` | `text/x-caspm` |

The two share a common JSON base but not a common vocabulary — a general-purpose CaspJ reader cannot process CaspM (it will encounter atoms it doesn't recognize, like `function_call` bwc dispatches), and vice versa. Tools should declare which they consume. See [content-types](https://puck.uno/documentation/requirements/content-types).
