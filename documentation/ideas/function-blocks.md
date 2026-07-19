# Function blocks

~~~vibecode
{"vibecode": {
	"doc": "ideas_function_blocks",
	"role": "design exploration — redesign of how blocks and DSL setup work. Grounding: blocks are already first-class callable values (closures from `do ... end` or bare functions from `dofunc ... end`), so `yield` needs no separate primitive — it's a bare-word command that desugars to `%call.blocks[0].call`. Caller objects (built via `$callable.caller.new`) provide a reusable, configurable pending-call surface: params set by subscript (named-only), trailing blocks passed at the `.call()` invocation site, and DSL wiring via `.dsl` (bulk-write method that returns the underlying hash, so subscript access on the hash works too). The dispatcher class from the earlier design evaporates — a caller with a DSL wired up does the same job with less machinery. Related pattern worth calling out separately: class accessors on context (`.caller` is one; more will follow).",
	"status": "in progress — core mechanism settled; concrete syntax finalized enough to sketch worked examples; migration of the DSL requirements spec pending",
	"audience": "Miko for the design direction; anyone reasoning about the block-and-DSL surface once this settles into requirements",
	"related": []
}}
~~~

## Basics

**`%call.blocks` is an array of blocks.** Each element is a callable value — a closure (from a `do ... end` block at the call site) or a bare function (from a `dofunc ... end` block). Same as the current spec on [functions/call § do and dofunc blocks](https://puck.uno/documentation/requirements/caspian/functions/call#do-and-dofunc-blocks).

**`yield` is a bare-word command.** It desugars to:

~~~caspian
%call.blocks[0].call
~~~

`yield args...` calls block 0 with the given args. `yield` alone calls it with none. There is no separate `%call.yield` primitive — yielding is just a normal call on a normal callable value.

## Caller objects

A **caller object** is a reusable, configurable pending call to a specific callable — function, closure, method, or block. Build one, set its params, wire a DSL if desired, execute later — possibly by different code than what built it.

**Construction.** Every callable carries a `.caller` — the caller class specialized for that callable. `.new` on it produces a fresh caller instance:

~~~caspian
$caller = $function.caller.new
~~~

`$function.caller` is a **subclass** of the base caller class. The subclass carries one piece of context — which callable this caller is for. Everything else (`.call`, `.dsl`, the subscript surface for params) lives on the base class.

**Setting params.** Params are set via subscript on the caller. Named only — positional slots are not used in this form. `.new` does not accept initial params; subscript is the sole entry point:

~~~caspian
$caller[:foo] = 'bar'
$caller[:gup] = 2
~~~

**Setting a callable-typed param.** Since `do` and `dofunc` are trailing-block syntax at the method-call site, they're not available in a subscript-set position. Use `closure` or `function` at the declaration:

~~~caspian
$caller[:my_closure] = closure
	# body
end
~~~

**Execution.** `.call` on the caller invokes the underlying callable with the collected params:

~~~caspian
$caller.call
~~~

**Attaching trailing blocks at invocation.** `.call` is itself a method call, so its trailing blocks are just its trailing blocks — no special caller-object surface:

~~~caspian
$caller.call() do
	# block A
end
~~~

The block passed here lands in the target function's `%call.blocks[0]` when the caller invokes it. Multiple `do` / `dofunc` blocks chain at the `.call()` site the same way they chain anywhere else — the caller doesn't need its own "blocks" surface.

### Why subscript for params

Params live in a hash-shaped namespace on the caller. Subscript is the natural read/write shape for that. Two properties fall out:

- **No method-name collisions.** With property access (`.name = value`), a param called `call` would collide with the `.call` method that executes the caller. Subscript keys can't shadow method names.
- **Read and write use the same shape.** `$caller[:foo] = 'bar'` sets; `$caller[:foo]` reads back. Standard hash-subscript ergonomics.

### Named-only

Caller objects are strictly named-param. The direct-call form (`&function 'a', 'b'`) still supports positional args at the call site; caller objects don't.

## DSL wiring on the caller

Where the earlier design put DSL wiring on a separate dispatcher class, the redesign puts it directly on the caller. **`$caller.dsl` returns the underlying DSL hash** — a name-to-receiver mapping that's active for the caller's invocation. Called with args, it bulk-writes; called bare, it returns the hash.

~~~caspian
$foo = %['foo.bar/logger.casp'].new()

$caller = %call.blocks[0].caller.new
$caller.dsl $foo, :info, :warn, :error
$caller.call
~~~

Inside block 0, `info`, `warn`, and `error` are bwcs that route to the matching methods on `$foo` for the duration of the call.

**Two entry points into the same storage.** Both forms below write to the same hash:

~~~caspian
# Method form — bulk-write, one receiver, many names:
$caller.dsl $foo, :info, :warn, :error

# Subscript form — direct hash access, one name at a time:
$caller.dsl[:info]  = $foo
$caller.dsl[:warn]  = $foo
$caller.dsl[:error] = $foo
~~~

Emphasize the method form in docs. Reach for subscript when you need per-name control:

- **Introspection.** `$caller.dsl[:info]` reads the current receiver wired for `info`.
- **Programmatic wiring.** Loop over a hash and assign each entry, or wire conditionally.
- **Removal.** Assign `null` to un-wire a name.

**Multi-receiver DSLs.** Multiple `.dsl` calls on the same caller each add to the shared hash:

~~~caspian
$caller.dsl $log_handler, :info, :warn, :error
$caller.dsl $timer, :start, :stop
~~~

**Namespace separation.** The caller's own subscript surface (`$caller[:name]`) is for params. The caller's `.dsl` hash (`$caller.dsl[:name]`) is for DSL entries. They can never collide — different subscript targets.

## What falls away

- **`%call.dispatcher.new`** — gone. Dispatchers as a distinct class don't exist under this model.
- **`$dispatcher.yield`** — gone. Blocks are called via their own caller, not through a separate yielding verb.
- **`%call.yield`** — redundant. `yield` is sugar for `%call.blocks[0].call`; the primitive is just calling a callable.
- **"Targeting block N" ceremony** — gone. If you want block N, build a caller for `%call.blocks[N]`.

## Class accessors on context

`.caller` is one instance of a broader pattern. Because Caspian classes are URL-identified (Puck-resolved via `%[uns]`), fetching a class every time you'd want to construct one would force users to memorize URLs. Instead, an object that "knows" which class fits its context can expose an accessor pointing at that class — the user just chains through.

`$foo.caller` returns the caller class for `$foo` — a subclass of the base caller class that knows which callable it's for. The user writes `$foo.caller.new` instead of `%['caspian.uno/caller.casp'].new($foo)`.

This pattern will show up in more places as the design evolves. Whenever a specialized class would otherwise be the natural target for `%[uns]` retrieval, prefer to expose it as an accessor on whatever object provides the specialization context.

## Migration notes

Once this design settles, several requirements docs need updating:

- **[%call](https://puck.uno/documentation/requirements/caspian/global-methods/call/)** — drop `%call.yield` and `%call.dispatcher.new` from the surface. Add `%call.blocks[N]` as the mechanism and `yield` as its bwc sugar.
- **[dsl](https://puck.uno/documentation/requirements/caspian/global-methods/call/dsl)** — the dispatcher framing gets replaced by the caller-object framing. The four-tier token model and the dogfooding story (class-body DSL, instance-body DSL, loop-body DSL) all still apply — the mechanism they run on is now "the caller's `.dsl` hash" rather than "the dispatcher's `.dsl` hash."
- **A caller-object spec page** in requirements — probably under [functions/](https://puck.uno/documentation/requirements/caspian/functions/) — for the base caller class, `.caller` accessor convention, subscript surface for params, `.dsl` method, and `.call` semantics.
