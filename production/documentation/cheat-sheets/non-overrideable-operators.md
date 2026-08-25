# Cheat sheet: non-overrideable operators

~~~vibecode
{"vibecode": {
	"doc": "cheat_sheets_non_overrideable_operators",
	"role": "one-view reference to every Caspian operator that is a language primitive — user code cannot redefine it on a class the way it can for `+`, `==`, and other method-ops. These are the operators the engine dispatches directly on `op:` in CaspM (short-circuit boolean ops, pipes, ternary) or that desugar to a fixed internal primitive (bumps). Contrast with method-ops which collapse to method_call and dispatch through the receiver's class — those live in caspianj § Calls.",
	"status": "cheat sheet — canonical semantics live per-operator on the linked spec pages",
	"audience": "developers writing Caspian who want to know 'can I override this on my class?' at a glance; engine implementers cross-referencing which ops stay as op atoms in CaspM"
}}
~~~

Operators Caspian reserves as language primitives — user classes cannot redefine them by declaring a method with the operator's name. Two reasons an operator lands here:

- **Short-circuit or non-uniform evaluation** — the operator's semantics require deciding at the operator level whether to evaluate a sub-expression at all. A method call would evaluate all arguments before dispatch, so the semantic can't fit.
- **Dispatch to a fixed engine primitive** — the operator has one canonical behavior baked into the runtime; overriding it would break assumptions the engine makes.

All operators NOT on this list are method-ops (`+`, `-`, `*`, `/`, `%`, `**`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `<=>`, dot method calls, subscript get). Those DO dispatch through the receiver's class and CAN be overridden — a class defining `method &+($other) ... end` handles `$self + $other`.

## Short-circuit boolean

The evaluate-only-what's-needed operators. A method call can't be short-circuit because its args evaluate before dispatch.

`&&` and `||` are **value-preserving**: the return value is the actual left or right operand that decided the result, not a coerced `true` / `false`. That's what makes idioms like `$user && $user.name || 'anonymous'` work — the whole expression yields the user's name if the user exists, otherwise the string `'anonymous'`.

| Operator | Alias | Purpose |
|---|---|---|
| <code>&#124;&#124;</code> | `or` | Logical OR. Evaluates left; if truthy, returns it and does NOT evaluate right. If left is falsy, evaluates right and returns it (whatever its truthiness). |
| `&&` | `and` | Logical AND. Evaluates left; if falsy, returns it and does NOT evaluate right. If left is truthy, evaluates right and returns it (whatever its truthiness). |
| `!` | `not` | Logical NOT (unary). Returns `false` for truthy input, `true` for falsy. Coerces to boolean; the only op in this section that does. |

Concrete cases for `$foo && $bar`:

| `$foo` | `$bar` | Result |
|---|---|---|
| truthy | truthy | `$bar` |
| truthy | falsy | `$bar` (still — `&&` returns the right operand once it evaluates it) |
| falsy | (not evaluated) | `$foo` |

And for `$foo || $bar`:

| `$foo` | `$bar` | Result |
|---|---|---|
| truthy | (not evaluated) | `$foo` |
| falsy | truthy | `$bar` |
| falsy | falsy | `$bar` |

Falsy values in Caspian are strictly `false` and `null`. Everything else is truthy. See [built-in-classes/primitives/boolean](https://puck.uno/requirements/built-in-classes/primitives/boolean).

## Ternary conditional

| Operator | Purpose |
|---|---|
| `?:` | `cond ? then : else` — evaluates `cond`, then evaluates and returns exactly one of `then` / `else`. The unchosen branch is never evaluated. Same short-circuit rationale as <code>&#124;&#124;</code> / `&&`. |

## Pipes

Value-into-call composition. Not a method because the LHS becomes the first argument of a call whose shape is decided at parse time, not by dispatching through a class.

| Operator | Purpose |
|---|---|
| <code>&#124;</code> | Pipe. <code>LHS &#124; &amp;fn args</code> becomes `&fn LHS, args`. <code>LHS &#124; $obj.method args</code> becomes `$obj.method LHS, args`. See [syntax/pipes](https://puck.uno/requirements/syntax/pipes). |
| <code>&#124;&amp;</code> | Null-safe pipe. Same rewrite; skips the call and returns `null` if LHS is `null`. Once a chain enters <code>&#124;&amp;</code>, subsequent <code>&#124;</code> links stay null-safe. |

## Bumps

Not "operators" in the op-atom sense in CaspM — the transpiler produces op atoms in CaspJ (`{op: "++_suffix", operand}`, etc.), and the normalizer collapses each to a dedicated internal primitive (`{cmd: "si"}` for suffix increment, and so on). But they belong here because user code has no way to override them: `++` and `--` always mutate through the same slot-write primitive as `.value=` / subscript-set.

| Source | CaspJ op | CaspM primitive |
|---|---|---|
| `$x++` | `{op: "++_suffix", operand: X}` | `[{cmd: "si"}, X-as-lvalue]` |
| `++$x` | `{op: "++_prefix", operand: X}` | `[{cmd: "pi"}, X-as-lvalue]` |
| `$x--` | `{op: "--_suffix", operand: X}` | `[{cmd: "sd"}, X-as-lvalue]` |
| `--$x` | `{op: "--_prefix", operand: X}` | `[{cmd: "pd"}, X-as-lvalue]` |

The operand is an lvalue atom (`{varobj: NAME}` for variables, `{subscript: {receiver, key}}` for subscripts). See [caspianj § Bumps](https://puck.uno/requirements/caspianj#bumps).

## Assignment

`=` is a language construct, not an operator that dispatches through a class. It desugars to the `assign` internal primitive (`[{cmd: "="}, LVALUE, VALUE]`) at CaspM. Compound assignments (`+=`, `-=`, `*=`, etc.) are sugar for `LHS = LHS OP RHS` — they inherit whatever the underlying op-method does but the assignment step itself is not overrideable. See [caspianj § Assignment](https://puck.uno/requirements/caspianj#assignment).

## Not on this sheet

- **Method-ops** — `+`, `-`, `*`, `/`, `%`, `**`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `<=>`, `.` (method-call), `[]` (subscript-get). These CAN be overridden on a user class by declaring the method with the operator's name (`method &+($other) ... end`). In CaspM they collapse to `method_call` with the op string as `function:`. See [caspianj § Calls](https://puck.uno/requirements/caspianj#calls).
- **Global-method sigils** — `%name` names, `@name` bucket shorthand, `$$name` varobj sigil, `&name` amp invocation. Not operators — they're parsing-level surface for reaching a specific runtime feature. See the [global methods cheat sheet](global-methods).
