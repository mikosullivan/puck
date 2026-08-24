~~~vibecode
{"doc": "sprint-report", "sprint": "expressions",
	"role": "Assessment of how well the current CaspM already supports the sprint's core design decision — every command reduces to a single method_call at its root. Categorizes each source-language surface as (a) already in the right shape, (b) structurally aligned but needing a normalizer rewrite, or (c) needing transpiler work. Concludes with an overall fit assessment and prioritized recommendations. Distinct from [caspm-status](./caspm-status) — that's a per-construct action list; this is the analysis."}
~~~

# Report — CaspM's fit for the "every command is a method call" design

The sprint's core decision is that every Caspian command reduces to a single `method_call` invocation at its root — some dispatch through `.obj` methods on the left operand (binary operators), some through `engine` methods (standalone commands like `if` / `while`), some through named methods on user receivers (`$foo.bar`). This report assesses how well the CURRENT CaspM already supports that reduction — what fits, what needs normalizer work, what needs transpiler work, and what deep structural questions remain.

## Overall assessment

**CaspM's fit is substantially good** — the load-bearing atom shape (`fc`) already exists, the load-bearing wrapper (`cl` closures) already exists, and the transpiler already normalizes several categories (dot method calls, amp calls, arithmetic, comparison, property assignment) into the target shape. What remains is:

- Normalizer rewrites for four keyword-based constructs (`||`, `&&`, `if`, `while`) that produce non-`fc` atoms today.
- One transpiler addition (ternary `? :`) that doesn't parse at all.
- One structural decision about literals and var refs — whether to represent them as `Number.new` / `scope.lookup` method calls under walking-skeleton discipline, or leave them as leaf atoms.

The design isn't asking for a redesign of CaspM. It's asking for extensions to the normalizer's rewrite table and one parser addition. That's a manageable body of work, well within scope for implementation.

## Already aligned

| Source | Current CaspM | Notes |
|---|---|---|
| `$foo.bar(1, 2)` | `[{"in":"fc"}, {"rc": $foo, "fn": "bar", "a": [{"v":1}, {"v":2}]}]` | Dot method call → `fc`. Direct fit. |
| `&foo(x)` | `[{"in":"fc"}, {"rc": {"var":"foo"}, "fn": "call", "a": [{"var":"x"}]}]` | Amp-call → `fc` with `fn: "call"`. |
| `1 + 2` | `[{"in":"fc"}, {"rc": {"v":1}, "fn": "+", "a": [{"v":2}]}]` | Arithmetic → `fc`. Method on left operand. |
| `5 < 10` | `[{"in":"fc"}, {"rc": {"v":5}, "fn": "<", "a": [{"v":10}]}]` | Comparison → `fc`. |
| `$obj.foo = 5` | `[{"in":"fc"}, {"rc": {"var":"obj"}, "fn": "foo=", "a": [{"v":5}]}]` | Property assignment → `fc` with `.foo=` method. Elegant. |
| `unless X then Y end` | Normalized to `{if: {...}}` with `{op: "!", operand: X}` as test | The `unless` desugaring is already happening; whatever we do to `if` covers `unless`. |
| `closure($a) return $a end` | `{"cl": {"pm": ["a"], "bd": [["scope","return",{"var":"a"}]]}}` | First-class closures already exist as CaspM atoms. Values, not calls. Consumed as-is by the walker. |

**The `fc` atom is a first-class citizen and already the target shape for six of the most common command forms.** The `cl` closure atom is also first-class and directly usable as the "closure value" that `engine.if` / `engine.while` receive as args.

## Structurally aligned but needs normalizer rewriting

These have well-formed CaspM structure that the normalizer can rewrite to `fc` without transpiler changes.

| Source | Current CaspM | Target |
|---|---|---|
| `$a \|\| $b` | `{"op": "\|\|", "left": $a, "right": $b}` — unresolved op atom | `[{"in":"fc"}, {"rc": $a.obj, "fn": "or", "a": [<closure→$b>]}]` |
| `$a && $b` | `{"op": "&&", ...}` — unresolved op atom | `[{"in":"fc"}, {"rc": $a.obj, "fn": "and", "a": [<closure→$b>]}]` |
| `if X then A elsif Y then B else C end` | `{"if": {"conditions": [{test, action}], "else": ...}}` — special atom | `[{"in":"fc"}, {"rc": {"var":"engine"}, "fn": "if", "a": [<list of [test_cl, action_cl] pairs>, <else_cl or null>]}]` |
| `while X do Y end` | `["scope", "while_end", <test>, {"bd": <body>}]` — special atom | `[{"in":"fc"}, {"rc": {"var":"engine"}, "fn": "while", "a": [<test_cl>, <body_cl>]}]` |
| `$x = 5` | `[{"in":"as"}, "x", {"v":5}]` — special `as` atom | Either stays as-is (special-cased in the walker) OR normalizes to `[{"in":"fc"}, {"rc": {"var":"engine"}, "fn": "assign", "a": [{"v":"x"}, {"v":5}]}]`. See [primitives/assign](./primitives/assign). |
| `puts 'hello'`, `return 5`, `raise 'oops'` | `[{"bwc":"puts"}, ...]` / `["scope","return", ...]` / `[{"bwc":"raise"}, ...]` — bareword commands, various shapes | Each could become an `fc` on `engine`: `engine.puts`, `engine.return`, `engine.raise`. Whether they should is a design call — bareword commands might stay as their own atom category to preserve source fidelity. |

**Every construct in this table is a normalizer rewrite, not a transpiler change.** The transpiler already parses these; the normalizer today either leaves them in a not-yet-collapsed shape (op atoms, special tree atoms) or emits a dedicated positional-array shape (bareword commands). Extending the normalizer to rewrite them into `fc` atoms is well-defined work.

The `assign` case is worth deciding: under strict "everything is a method_call" the `[{"in":"as"}, ...]` shape becomes an `fc` on `engine.assign`. Under a lighter version, `as` stays as a special atom the walker recognizes directly (like `fc`) and the assign primitive is dispatched without the fc wrapper. Both are defensible; the strict version is more uniform, the light version is one less normalizer rewrite.

## Parser gaps

Two source-language constructs the transpiler doesn't parse today.

| Source | Status | What's needed |
|---|---|---|
| `$foo ? 1 : 0` (ternary) | Parse failure | Transpiler needs to recognize `? :` as a three-slot construct producing a CaspJ atom the normalizer can rewrite to `engine.if`. |
| `until X do Y end` | Parse failure (`do` block issue) | Transpiler needs to accept the `until` keyword-form; then normalizer can rewrite to `engine.while` with a negated test (mirror of how `unless` rewrites to `if`). |

Both are additive to the transpiler — no changes to existing parsing paths. Each contributes one more source surface that reduces to an existing primitive (`engine.if` and `engine.while` respectively).

## Deep alignment questions

These aren't gaps — they're design decisions the sprint has to make and the current CaspM doesn't force either way.

**Should literals be method calls?** The current `{"v": 1}` atom is a raw literal, not a method call. Under strict walking-skeleton discipline, `1` would become `Number.new(1)` — a call to a primitive that materializes the value. The engine would dispatch it as an `fc` on `Number`. Advantages: perfect uniformity, every value materialization runs through the same mechanism. Costs: every literal is a frame; a source like `1 + 2 + 3` involves five to seven frames instead of one.

The pragmatic answer is probably: **the sprint's walking-skeleton phase treats literals as method calls via a normalizer rewrite; leaf-inline optimization later bypasses the frame and materializes the value directly in the parent's walker.** The `{"v": ...}` atom can either be rewritten by the normalizer or handled by a leaf-optimization pass — the design accommodates both.

**Should variable references be method calls?** Same question, same shape. `{"var": "x"}` could become `scope.lookup('x')` — a method call on the current scope. Same pros and cons as literals; same probable resolution (walking-skeleton wraps; leaf-inline elides later).

**Should top-level command sequences be a call?** A program is currently an array of commands: `[cmd1, cmd2, cmd3, ...]`. Under "everything is a call," the program could be `engine.sequence(cmd1_closure, cmd2_closure, ...)` — a call to a sequencer that runs each in order. This is more uniformity but adds no expressive power. Probably not worth it; the array-of-commands shape is fine as a container.

**Should bareword commands (`puts`, `return`, `raise`, `field`) become `engine.<name>` fc calls?** They could. Currently they're dedicated atom categories (`{"bwc":"puts"}` and `["scope","return", ...]`). Rewriting to `fc` on `engine` unifies them with the "every command is a method_call" design. Not doing so keeps their source-level bareword identity visible in CaspM, which might be useful for tooling. Design call.

## Prioritized recommendations

**Highest priority** — normalizer rewrites for constructs already spec'd as primitives in this sprint:

- `||` → `.obj.or` fc call. Straightforward: turn the op atom into `fc` with `.obj` receiver, `fn: "or"`, and the right operand wrapped as a closure.
- `&&` → `.obj.and` fc call. Symmetric to `||`.
- Keyword `if` / `elsif` / `else` → `engine.if` fc call. Per [primitives/if](./primitives/if), takes a list of `[test_cl, action_cl]` pairs plus an optional else closure. Needs the normalizer to wrap tests as closures (bodies are already `cl` atoms).
- Keyword `while` → `engine.while` fc call. Per [primitives/while](./primitives/while), takes a test closure and a body closure. Needs the normalizer to wrap both as `cl` atoms.
- Assignment (`as` atom) → `engine.assign` fc call, or stay as special atom. Decide first, then implement.

**Middle priority** — transpiler additions for constructs that don't parse:

- Ternary `? :` → parses to a three-slot atom; normalizer rewrites to `engine.if`.
- `until` keyword → parses to a variant of the while atom (or its own); normalizer rewrites to `engine.while` with a negated test.

**Lower priority** — walking-skeleton uniformity for literals and var refs:

- Decide whether to wrap `{"v": ...}` and `{"var": ...}` as method calls at norm time or handle them via leaf-inline at execution time. Either works; the choice affects when the uniformity vs. performance tradeoff lands.

**Not needed** — CaspM doesn't need structural changes. The atom vocabulary is already adequate. What we're doing is extending the normalizer's rewrite rules and adding a couple of parser paths.

## Bottom line

The design fits. The core mechanism (`fc` atoms dispatched via `method_call`) is already the transpiler's target for most binary-operator and method-dispatch forms. The remaining gaps are localized normalizer rewrites for a few keyword constructs and one parser addition for the ternary. No fundamental CaspM redesign is required — the current shape already supports "every command is a method call" almost entirely; the work ahead is filling in the last few constructs.

## Related

- [index](./index) — sprint overview and the core design decision.
- [caspm-status](./caspm-status) — per-construct table of current vs. target CaspM shapes (prescriptive companion to this analytical report).
- [evaluation-model](./evaluation-model) — how the walker consumes CaspM under this design.
- [primitives/](./primitives/) — Lua-implemented primitives the normalizer targets.
