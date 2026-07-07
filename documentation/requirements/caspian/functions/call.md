# Calling functions, closures, and methods
<!--index: 6-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_calling",
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

Keyword arguments use `name: value` syntax. Positional and named can mix; all positional args must come before the first named arg.

~~~caspian
&fetch 'https://example.com', timeout: 30, retries: 3
~~~

Splat expansion:

~~~caspian
$args = ['alice', 'captain']
&greet *$args              # expands positionally

$opts = {timeout: 30}
&fetch 'https://example.com', **$opts   # expands as named
~~~

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

Blocks trail the argument list — they're passed after the last positional or named argument. The receiver reads them from [`%call.blocks`](https://puck.uno/documentation/requirements/caspian/global-methods/call/#call-blocks) and invokes them via [`%call.yield`](https://puck.uno/documentation/requirements/caspian/global-methods/call/#call-yield).

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

Full parameter mechanics (metadata, optionality, defaults, `*args`, `**opts`, lazy parameters, public vs. private names) are on the [bare-function page § Parameters](https://puck.uno/documentation/requirements/caspian/functions/bare#parameters).
