# Parameter defaults

<span class="tag">parameter-defaults</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_functions_parameter_defaults",
	"role": "spec for how Caspian handles default parameter values. A default is stored as an unevaluated expression and re-evaluated on every call where the argument is omitted; each call therefore gets a FRESH object, not a shared one. This deliberately matches Ruby's `def` semantics and rejects Python's mutable-default-argument model. Covers the scope rules (function vs. closure), cross-parameter references, the distinction between an omitted argument and an explicitly-passed null, method defaults referencing %self, and the constant-folding optimization permitted for immutable literals.",
	"status": "spec — mechanism, scope rules, and edge-case handling settled; runtime shape sketched at the level required for the engine implementer",
	"audience": "engine implementers building parameter binding; developers reasoning about default semantics",
	"related": []
}}
~~~

A parameter's default value is an **unevaluated expression**, not a pre-computed value. When a caller omits the argument, the runtime evaluates the expression fresh and binds the result. Every call that omits the argument runs the default expression again.

The observable consequence: **a caller that omits a defaulted argument gets a fresh object each time.** Mutating that object doesn't affect subsequent calls; producing side effects in the default expression re-runs them per call.

This is Ruby's model. Python's opposite model — evaluate the default once at `def` time and share the object across every call — is the source of the mutable-default-argument bug class and is not what Caspian does.

## The mechanism

Every parameter with a default carries the expression's AST. On call:

1. Provided positional arguments bind to their slots left-to-right.
2. Provided keyword arguments bind to their slots by name.
3. For each parameter still empty:
   - If it has a default AST, evaluate the AST in the parameter scope (see below) and bind the result.
   - If it has no default and no argument was provided, raise a "missing required argument" error.

No shortcut for literals: `$x = 42` and `$x = []` are both expressions evaluated per call. (The engine is free to optimize immutable literals — see [§ Constant folding](#constant-folding).)

## Scope for the default expression

The default expression runs in the **parameter scope**, whose contents depend on the callable's kind:

- **`function` defaults** can reference:
  - Globals (`%...`).
  - `%self` and instance state (for methods).
  - Earlier parameters in the same parameter list.

  They **cannot** reference the enclosing local scope. `function` does not capture; a default that names an outer local variable raises the same unbound-name error any other expression in the function body would.

- **`closure` defaults** can reference everything a `function` default can reference, plus the closure's captured variables. `closure` captures its defining scope, and the default expression runs in that same scope.

Both kinds forbid referencing the function body's own local variables; those don't exist yet at parameter-binding time.

The `function` restriction matches Ruby's `def` — inside a `def foo(bar = mystring)`, `mystring` from the enclosing scope is invisible, and the parser rejects the reference. Caspian's `function` behaves identically; `closure` is where captured-scope references belong.

**Consequence for authors:** a `function` that needs a default referencing outer state has three options — promote the state to a global, pass it as an earlier parameter, or define the callable as a `closure` instead.

## Cross-parameter references

A later parameter's default may reference earlier parameters:

~~~caspian
function &spaced($width, $pad = $width * 2)
	# ...
end

&spaced 10           # $pad defaults to 20
&spaced 10, 25       # $pad is 25
~~~

Evaluation order: positional slots bind left-to-right, then keyword slots by name. Each parameter is bound before the next one's default runs, so a later default sees earlier parameters as already-bound.

Referring to a parameter that hasn't been bound yet (either a later parameter, or the parameter's own name) is a parse-time error. See [§ Edge cases](#edge-cases).

## `null` vs. omitted argument

A caller passing `null` explicitly is **not the same as** omitting the argument. The default runs only when the argument is omitted.

~~~caspian
function &foo($x = 'default')
	return $x
end

&foo             # returns 'default' — argument omitted, default runs
&foo null        # returns null — argument provided (as null)
&foo 'hello'     # returns 'hello' — argument provided (as 'hello')
~~~

`null` is a first-class value in Caspian; conflating "not provided" with "provided as null" would recreate the Python sentinel workaround that this design rejects.

**Runtime implication:** the argument-binding machinery tracks a per-slot presence flag distinct from the slot's value. The check for "should the default run?" is on the presence flag, not on the value.

## Keyword and positional defaults

Same rule for both. A keyword parameter's default expression re-evaluates on every call where that keyword is omitted:

~~~caspian
function &connect(host: 'localhost', port: 8080, timeout: &default_timeout())
	# ...
end

&connect                                # host='localhost', port=8080, timeout=fresh call to &default_timeout
&connect host: 'db.example.com'         # port and timeout still default; each is fresh
&connect timeout: null                  # timeout is null (explicit), not the default
~~~

## Method defaults referencing `%self`

Method defaults evaluate in a scope where `%self` is bound to the receiver, so they can reference instance state:

~~~caspian
class # widget
	field @size

	method &area($side = @size)
		return $side * $side
	end
end

$w.area()           # $side defaults to @size on %self
$w.area 10          # $side is 10
~~~

Rationale: method defaults naturally want access to the instance. The `%self` binding is set up before default evaluation, same as it would be for the method body.

## Constant folding

The engine is free to optimize the case where a default expression is a compile-time-constant literal whose type is immutable — number, boolean, `null`, and other value types that cannot be mutated after construction.

For an immutable literal, "new object each call" is observationally identical to "same shared object each call" — nothing the caller can do would distinguish them, because the object can't be mutated.

For mutable literals (`[]`, `{}`, strings, class instances), the runtime **must** produce a new object each call. Sharing them would leak mutations across calls — the Python bug that this whole design exists to avoid.

The rule for the engine: **optimize only where correctness is preserved.** Cache immutable literal defaults; never cache mutable ones.

## Runtime shape

The engine's implementation follows the mechanism directly:

1. **Parser** — records each parameter as `(name, has_default, default_expression_ast)`. The AST is not evaluated at parse time.
2. **Callable object** — the compiled function / closure / method carries its parameter table, each entry including an optional pointer to a default AST subtree.
3. **Call time** — the argument-binding step runs the algorithm in [§ The mechanism](#the-mechanism).
4. **Parameter scope** — a fresh scope for the call; sees globals and `%self` (always); sees captured variables (closure only); sees earlier parameters (as each is bound); does not see the function body's locals.

The AST is walked from scratch each call. Simple literals (`'default'`, `42`, `[]`) are cheap; complex expressions (function calls, class instantiations) run every time — as intended.

## Edge cases

- **Self-reference in default.** `function &f($x = $x)` — the parameter isn't bound yet at the moment its default would run. Rejected at parse time.
- **Forward reference to a later parameter.** `function &f($a = $b, $b = 10)` — `$a`'s default runs before `$b` is bound. Rejected at parse time. The parser enforces "a default may reference only parameters earlier in the list."
- **Side-effecting defaults.** `function &log($msg, $when = &now())` — `&now()` runs on every call that omits `$when`. Intentional; the design doesn't try to prevent it.
- **Very expensive defaults.** `function &load($data = &fetch_huge_dataset())` — runs every time the caller omits `$data`. This is the developer's responsibility to notice; the runtime doesn't try to detect "the default is expensive."

## Not the same as

- **Constant expressions.** Even `$x = 42` is semantically an expression evaluated at binding time. The constant-folding optimization above may fold it internally, but the language semantic is "expression evaluated each call."
- **Lazy parameter binding.** Defaults evaluate at binding time (when the parameter is about to be bound because no argument was provided), not deferred until the value is first read inside the function body.

## Testing

- **Fresh mutable defaults per call.** Function with `$xs = []`, mutate the returned list, call again — the second call's `$xs` is empty.
- **Fresh object identity per call.** Compare the object identity of `$xs` from two consecutive calls; the identities differ.
- **Default expression runs per call.** Function with `$id = &generate_id()` where `&generate_id` returns increasing values; each call yields a new id.
- **null distinguishes from omitted.** Function returns its parameter; call with omitted vs. `null` vs. a value; the omitted call returns the default, the `null` call returns `null`, the value call returns the value.
- **Cross-parameter defaults resolve.** `function &f($a, $b = $a * 2)` — omitting `$b` binds it to `$a * 2` using the argument's `$a`.
- **Method defaults see `%self`.** `method &m($x = @field)` — omitting `$x` binds it to the instance's `@field`.
- **`function` default cannot reference an outer local.** With `$outer = 'x'` in the enclosing scope, `function &f($x = $outer) ... end` raises when `$x` is omitted (matching Ruby's `def`).
- **`closure` default can reference a captured local.** Same shape as above but declared as `closure`; the default resolves `$outer` from the closure's captured scope.
- **Forward-reference default is a parse error.** `function &f($a = $b, $b = 10)` — parse fails; the error identifies `$b` as an unbound reference.
- **Self-reference default is a parse error.** `function &f($x = $x)` — parse fails.
- **Keyword defaults follow the same rules.** Each of the above holds for keyword parameters as well.
