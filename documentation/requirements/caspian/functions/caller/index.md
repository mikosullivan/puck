# Caller objects

<span class="tag">caller</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_functions_caller",
	"role": "spec for caller objects — reusable, configurable pending calls to a specific callable (function, closure, method, or block). Built via `$callable.caller.new`; each function's `.caller` is a subclass of the base caller class specialized to that callable. Params are set via subscript (named-only; `.new` accepts no initial params). `.call` invokes the underlying callable. Trailing blocks pass at the `.call()` site using standard trailing-block syntax. Caller objects are reusable — invoke `.call` any number of times with params sticky between invocations. Callable-typed params use `closure`/`function` at declaration since `do`/`dofunc` are trailing-block syntax only. DSL wiring on a caller has its own sub-page at caller/dsl (the .dsl method + subscript surface, multi-receiver, virtual getters/setters, namespace separation from params).",
	"status": "spec — mechanism, param surface, and reuse rules settled. Jails and additional introspection surface (enumerate all params) deferred.",
	"audience": "developers building configurable pending calls; anyone reasoning about how DSLs get wired at call sites"
}}
~~~

A **caller object** is a reusable, configurable pending call to a specific callable — function, closure, method, or block. Build one, set its params, wire a DSL if desired, execute later. The caller can be passed to other code that eventually invokes it.

Caller objects are the single mechanism for **configured** calls. The direct-call forms (`&fn args`, `$obj.method args`) remain for the common "call it right now with these args" case; caller objects are for when you need to configure the call before firing it, reuse the configuration across multiple invocations, or install a DSL for the call's duration.

## Construction

Every callable carries a `.caller` accessor — the caller class specialized for that callable. `.new` on it produces a fresh caller instance:

~~~caspian
$caller = $function.caller.new
~~~

`$function.caller` is a **subclass** of the base caller class. The subclass carries one piece of context — which callable this caller is for. Everything else (`.call`, `.dsl`, the subscript surface for params) lives on the base class.

**`.new` accepts no arguments.** Params are set exclusively through subscript after construction (see below). There is no shortcut for "construct with initial params" — the same mechanism configures every caller.

## Setting params

Params are set by subscript on the caller. **Named-only** — positional slots are not used with caller objects. Direct-call forms still accept positional args; caller objects don't.

~~~caspian
$caller[:foo] = 'bar'
$caller[:gup] = 2
~~~

Both string keys (`$caller['foo']`) and symbol keys (`$caller[:foo]`) work — the symbol notation is [sugar for identifier-shaped strings](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/string/#literal-forms).

**Why subscript.** With property access (`.name = value`), a param called `call` would collide with the `.call` method that executes the caller. Subscript keys can't shadow method names. Reads and writes share the same shape — `$caller[:foo]` reads back the value most recently assigned.

### Callable-typed params

`do` and `dofunc` are trailing-block syntax at a method-call site; they aren't legal in a subscript-set position. Use the definition-site keywords `closure` and `function` instead:

~~~caspian
$caller[:my_closure] = closure
	# body
end

$caller[:my_function] = function
	# body
end
~~~

The value assigned is a first-class callable — same shape as any other closure or bare function stored in a variable.

## Execution

`.call` on the caller invokes the underlying callable with the collected params and **returns the callable's return value**:

~~~caspian
$caller[:x] = 3
$result = $caller.call     # $result is whatever the target callable returned
~~~

**Missing required params raise at `.call` time.** The caller doesn't validate at set time; it accumulates whatever you assign. If a required param on the target hasn't been set by the time `.call` fires, the target's normal param-binding raises — same error the target would produce if called directly without the arg.

**Callers are reusable.** `.call` may be invoked any number of times on the same caller. Params are sticky between invocations — set once, fire many times. Change a param between calls to vary a single slot without rebuilding the caller:

~~~caspian
$caller[:foo] = 'first'
$caller.call             # fires with foo = 'first'

$caller[:foo] = 'second'
$caller.call             # fires with foo = 'second'; gup unchanged
~~~

The caller can be passed to other code before `.call` fires. Setting a param before passing restricts what the receiver needs to supply.

**Access checks fire at each `.call`, against the current frame.** Whether a call succeeds is determined by the frame invoking `.call`, not by wherever the caller was built. In particular, if the underlying callable is a private method, `.call` from a frame whose [`%call.method_class`](https://puck.uno/documentation/requirements/caspian/global-methods/call/#call-method-class) doesn't match the class carrying the private method will raise — even if the caller was built inside the class body where the private method was reachable. The caller object doesn't carry an access token; the calling frame governs. See [object § methods](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/methods/#methods) for the same rule applied to raw method-callable values.

### Trailing blocks at invocation

`.call` is itself a method call, so its trailing blocks are just its trailing blocks — no dedicated caller-object surface is needed:

~~~caspian
$caller.call() do
	# block body
end
~~~

The block passed here lands in the target callable's `%call.blocks[0]`. Multiple `do`/`dofunc` blocks chain at the `.call()` site the same way they chain at any call site — see [calling § Multiple blocks](tag:calling#multiple-blocks).

## DSL wiring

`.dsl` on the caller wires bare-word commands for the block invoked by `.call`. Full spec on [dsl](tag:dsl).

## Relationship to blocks

`yield` (bwc) desugars to `%call.blocks[0].call` — see [%call.blocks](https://puck.uno/documentation/requirements/caspian/global-methods/call/#call-blocks). For a plain block invocation with no configuration, that's the whole story. Reach for the caller-object form when you need to install a DSL, set params on the block, or reuse the same configured call.

~~~caspian
# Plain yield — no configuration needed:
yield 'starting'

# Same, without the bwc sugar:
%call.blocks[0].call 'starting'

# Configured yield with a DSL:
$caller = %call.blocks[0].caller.new
$caller.dsl $log_handler, :info, :warn, :error
$caller.call
~~~

## Class-accessors-on-context pattern

`.caller` on every callable is one instance of a broader pattern. Because Caspian classes are URL-identified (Puck-resolved via `%[uns]`), fetching a class every time you'd want to construct one would force users to memorize URLs. Instead, an object that "knows" which class fits its context can expose an accessor pointing at that class — the user just chains through.

`$foo.caller` returns the caller class for `$foo` — a subclass of the base caller class that knows which callable it's for. The user writes `$foo.caller.new` instead of `%['caspian.uno/caller.casp'].new($foo)`.

This pattern shows up elsewhere in Caspian. Whenever a specialized class would otherwise be the natural target for `%[uns]` retrieval, prefer to expose it as an accessor on whatever object provides the specialization context.

## Testing

- **`.caller` returns a class** — `$function.caller` is a class, not an instance; it has `.new`.
- **`.caller.new` returns a fresh instance** — two `.new` calls return two distinct callers.
- **`.caller` is specialized to the callable** — the class knows which callable it was accessed from; a caller for `$foo` invokes `$foo` on `.call`, not any other function.
- **`.new` accepts no arguments** — `$function.caller.new(foo: 1)` raises. Params go through subscript only.
- **Subscript-set stores param** — after `$c[:foo] = 'bar'`, `$c[:foo]` reads back `'bar'`.
- **Symbol and string keys are equivalent** — `$c[:foo] = 'bar'` then `$c['foo']` reads `'bar'`.
- **`.call` invokes with collected params** — `$c[:foo] = 'x'; $c.call` invokes the target callable with `foo = 'x'`.
- **`.call` returns the target callable's return value** — `$c.call` on a caller for a function that returns `42` produces `42`.
- **Missing required param raises at `.call`** — `$c.call` on a caller whose target requires `foo` but has no `foo` set raises the target's missing-required-arg error.
- **Setting a param does not validate against the target signature** — assigning `$c[:not_a_param] = 'x'` does not raise at set time; the target may accept or reject it when `.call` fires, per the target's own param-binding rules.
- **Callers are reusable** — invoking `.call` twice invokes the target twice.
- **Params are sticky between calls** — a param set before the first `.call` is still set for the second `.call`.
- **Changing a param between calls takes effect** — setting `$c[:foo] = 'A'; $c.call; $c[:foo] = 'B'; $c.call` invokes with `A` then `B`.
- **Callable-typed param assignment** — `$c[:handler] = closure ... end` stores a closure; on `.call`, the target callable receives that closure as the named param.
- **Trailing block at `.call()` populates target's `%call.blocks[0]`** — `$c.call() do ... end` inside the target reads the block from `%call.blocks[0]`.
- **Multiple trailing blocks at `.call()`** — chain freely, same as any call site.

DSL-wiring testing bullets are on [caller/dsl § Testing](dsl#testing).
