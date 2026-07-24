# Calling functions, closures, and methods

<span class="tag">calling</span>
<!--index: 6-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_functions_call",
	"role": "spec for Caspian's call syntax — the `&name args` form for stored functions and closures, `.call` equivalence, receiver-first method calls (`$obj.method args`), keyword arguments, splat expansion, and trailing block arguments (`do ... end` for closures, `dofunc ... end` for bare functions). Full parameter mechanics live in a separate sub-page.",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

A stored function or closure can be called two ways — the `&` sigil form and the `.call` method form. They do exactly the same thing:

~~~caspian
&greet
$greet.call
~~~

The equivalence follows from **functions are objects**: `.call` is the method every function object carries, and `&name` is sugar for it. Use whichever reads better in context — `&name` is shorter and reads as a call, `$name.call` is useful when the callable is the result of an expression or when uniform method-call chaining matters.

Both forms accept arguments the same way. Parens around the argument list are optional to the parser in every position — whether the call is a standalone statement or part of a larger expression. All four of these are valid:

~~~caspian
&greet 'alice'
&greet('alice')

$result = &compute 10, 20
$result = &compute(10, 20)
~~~

Formatters may enforce a preferred shape (Miko's [miko.json](https://puck.uno/documentation/ecoverse/formatting/miko.json), for example, prefers parens when the return value is captured), but that's a formatter concern, not a parser rule.

Method calls use the receiver-first form:

~~~caspian
$obj.method_name(arg1, arg2)
$obj.method_name arg1, arg2
~~~

### Keyword arguments

**Every callable in Caspian — bwc call, function, closure, method — accepts keyword arguments.** Kwargs use `name: value` syntax. Positional and named can mix; all positional args must come before the first named arg.

~~~caspian
&fetch 'https://example.com', timeout: 30, retries: 3       # bwc call
$obj.fetch 'https://example.com', timeout: 30                # method call
$closure.call 'x', mode: :strict                             # closure via .call
~~~

There is no per-callable opt-out. A function or method that doesn't declare a matching parameter accepts the kwarg into its `**opts` catchall if it has one, or (if no catchall is declared) raises with an unknown-kwarg error at the call site.

### Splat expansion

Two distinct operators — Caspian keeps them separate so the caller's intent is visible at the call site.

- **`*expr` — positional splat.** The expression must evaluate to an **array**; the array's elements spread into the call as positional arguments. Passing anything other than an array raises at the call.
- **`**expr` — keyword splat.** The expression must evaluate to a **hash**; the hash's entries spread into the call as keyword arguments. Passing anything other than a hash raises at the call.

~~~caspian
$args = ['alice', 'captain']
&greet *$args                                # spread as positional

$opts = {timeout: 30}
&fetch 'https://example.com', **$opts        # spread as keyword

$args = ['alice', 'captain']
$opts = {timeout: 30}
&greet *$args, **$opts                       # both, in one call
~~~

Splats may appear anywhere in the argument list — mixed among literal positionals or literal kwargs — and they may repeat. The runtime concatenates positionals (literal + `*`-spread) in source order, and merges kwargs (literal + `**`-spread) in source order with later keys winning on conflict.

Splatting the wrong shape raises at the call site — `&foo *$hash` raises (`*` expects array); `&foo **$array` raises (`**` expects hash). The transpiler can't catch this because it doesn't know the runtime type of the expression.

The two operators aren't interchangeable — Caspian doesn't have a "figure out how to spread this at runtime" form. If you have a hash whose values you want as positionals, spread its values explicitly (`*$hash.values`); if you have an array of `[key, value]` pairs to turn into kwargs, convert it first (`**Hash.from_pairs($pairs)`).

## `do` and `dofunc` blocks

A **block** is a chunk of code passed to a function or method as a trailing argument. Two forms:

- **`do ... end`** — a **closure** block. Captures the surrounding lexical scope; the block body can name variables from where the call is written.
- **`dofunc ... end`** — a **bare-function** block. No captured scope; the block body can only see its own parameters, its locals, and `%chain`.

The split mirrors the definition-site split between [`closure`](closure) and [`function`](bare) — same tradeoff, same rationale. `do` is the common case; `dofunc` is for sealed-scope handoffs, where the caller wants to guarantee the block cannot reach into the surrounding scope (untrusted receiver, cross-role handoff, anywhere the [security model](bare#why-this-is-caspian-s-security-model) matters).

~~~caspian
$outer = 'ensign'

&some_method do
	%call.return $outer   # captured from the outer scope
end
~~~

~~~caspian
$outer = 'ensign'

&some_method dofunc
	%call.return $outer   # raises — dofunc has no captured scope; $outer isn't reachable
end
~~~

Blocks trail the argument list — they're passed after the last positional or named argument. The receiver reads them from [`%call.blocks`](https://puck.uno/documentation/requirements/global-methods/call/#call-blocks); each element is a callable value, so the receiver invokes one by calling it directly (`%call.blocks[N].call args...`) or via the `yield` bwc, which desugars to `%call.blocks[0].call`.

### Multiple blocks

A single call can trail **any number** of blocks — `do` and `dofunc` freely mixed. Chain them by starting each new block immediately after the previous block's `end`:

~~~caspian
&run_scenarios do
	%call.return &scenario_a
end do
	%call.return &scenario_b
end dofunc
	%call.return &scenario_c
end
~~~

Inside `&run_scenarios`, the blocks land in `%call.blocks` in the order they appeared at the call site — `%call.blocks[0]` is the first `do`, `%call.blocks[1]` is the second `do`, and `%call.blocks[2]` is the `dofunc`. Each block keeps its own scope semantics regardless of position: closures capture, `dofunc` blocks don't.

There's no cap on the count and no shape the receiver has to declare in advance. How many blocks a call passes is a runtime property of that call, not a static feature of the receiver's signature. A receiver that expects a specific count checks `%call.blocks.length` itself.

Full parameter mechanics (metadata, optionality, defaults, `*args`, `**opts`, lazy parameters, public vs. private names) are on the [bare-function page § Parameters](https://puck.uno/documentation/requirements/functions/bare#parameters).

## Testing

- **`&name` and `.call` are equivalent** — `&greet 'alice'` and `$greet.call 'alice'` produce identical return values.
- **Parens optional on statement call** — `&greet 'alice'` and `&greet('alice')` are equivalent.
- **Parens REQUIRED on expression call with args** — `$r = &compute(10, 20)` works; `$r = &compute 10, 20` doesn't. In expression position the parser can't otherwise tell where the arg list ends (e.g., `if &ok &yay end` — is `&yay` an arg to `&ok` or the body of the `if`?). Paren-less remains legal at statement position, where the statement boundary marks the end.
- **Bare `&bar` in expression position is a zero-args call** — `$foo = &bar` assigns bar's return value. Use `$bar` to hold the callable itself (assuming a variable slot is storing it).
- **Method call receiver-first** — `$obj.method_name(1, 2)` dispatches through `$obj`'s class.
- **Method call parens optional** — `$obj.method_name 1, 2` and `$obj.method_name(1, 2)` are equivalent.
- **Keyword argument syntax on bwc call** — `&fetch 'x', timeout: 30` binds `$timeout = 30`.
- **Keyword argument syntax on method call** — `$obj.fetch 'x', timeout: 30` binds `$timeout = 30` on the receiver's method.
- **Positional-then-named order** — positional args before the first `name:` are legal; a positional after a keyword raises.
- **Kwarg to a callable that doesn't declare it raises** — unless the callable declares a `**opts` catchall.
- **Positional splat expansion** — `$a = ['x', 'y']; &foo *$a` binds positionals as if `&foo 'x', 'y'`.
- **Named splat expansion** — `$o = {t: 30}; &foo **$o` binds keyword args as if `&foo t: 30`.
- **`*` on a non-array raises at the call** — `&foo *$hash` and `&foo *5` both raise; the transpiler doesn't catch this, the call site does.
- **`**` on a non-hash raises at the call** — `&foo **$array` and `&foo **'string'` both raise.
- **Multiple splats in one call** — `$a = ['x']; $b = ['y']; &foo *$a, *$b` binds `['x', 'y']` as positionals in that order.
- **Kwsplat merges with later-wins on conflict** — `$o1 = {k: 1}; $o2 = {k: 2}; &foo **$o1, **$o2` binds `$k = 2`.
- **Literal positional plus splat** — `$a = ['b', 'c']; &foo 'a', *$a` binds three positionals `'a'`, `'b'`, `'c'`.
- **Literal kwarg plus kwsplat** — `$o = {b: 2}; &foo a: 1, **$o` binds `$a = 1, $b = 2`.
- **`do` block captures outer scope** — inside a `do ... end` block, an outer local defined above the call is reachable.
- **`dofunc` block does not capture** — inside a `dofunc ... end` block, referencing an outer local raises.
- **Blocks land in `%call.blocks`** — a receiver reading `%call.blocks[0]` gets the first block passed at the call site.
- **Blocks preserve call-site order** — `&foo do end do end dofunc end` populates `%call.blocks[0..2]` in written order.
- **Mixed `do`/`dofunc` blocks legal** — a single call may pass any combination of `do` and `dofunc` blocks.
- **Multi-block count has no cap** — a call with 10 blocks populates `%call.blocks.length == 10`.
- **Each block keeps its scope semantics** — the second `do` block still captures; a `dofunc` in position 2 still does not, regardless of neighbors.
- **Splat expansion with empty array** — `&foo *[]` produces a call with no positional args.
- **Splat expansion with empty hash** — `&foo **{}` produces a call with no keyword args.
- **`yield` invokes the first passed block** — inside the receiver, `yield` desugars to `%call.blocks[0].call` and runs the first block.
- **No-block call with `yield` raises** — `yield` when `%call.blocks` is empty is an out-of-bounds read on `%call.blocks[0]` and raises.
- **Method chain** — `$obj.a().b().c()` calls each method in turn on the returned receiver.
- **Sealed-scope handoff via `dofunc`** — passing `dofunc` across a role boundary hands the receiver code that cannot read the caller's locals.
