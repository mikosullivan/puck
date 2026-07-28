# Idea: Callables

~~~vibecode
{"vibecode": {
	"doc": "ideas_callables",
	"role": "spitball page for Caspian's unified callables model. Function IS method — the object is the same, invocation context (standalone vs method) determines receiver-globals binding. Closure ⊂ function but standalone-callable only (rebinding a captured lexical scope to a new receiver either shadows the capture or ignores the receiver, both wrong). Helper = function + .class field + canned body that instantiates the class and returns the instance, with lazy/fresh/default modifiers controlling per-parent caching. Receiver-globals (%self, %bucket, %stack) raise on access when the callable was invoked standalone. Conceptual object structure spec'd here at the Caspian-language level; Lua implementation is free to organize differently as long as observable behavior matches. Bucket fields and methods live in separate namespaces (`.class` is a method; `%bucket['class']` is a field; no collision, Ruby-style). Per-parent cache for helpers lives on the parent's bucket, not on the shared function object.",
	"status": "brainstorm — unification model settled; open questions on default caching mode, closure-in-method receiver interaction, and accessor naming for the helper class",
	"context": "started while designing helper method semantics; unifying function-and-method into a single Callable simplified helper's story (it's just a function with extra bucket state) and clarified the receiver-context distinction"
}}
~~~

Caspian's callables — functions, closures, methods, helpers — are all specializations of a single Callable model. The label "function" vs "method" tracks how you're calling the thing right now, not what it fundamentally is. Different subtypes (closure, helper) add behavior on top; the base is a function that runs some code when called.

## Function IS method

A callable declared with `function &foo() ... end` and a callable declared with `method &foo() ... end` produce the **same underlying object**. The difference is attachment and invocation, not identity:

- `function &foo() ... end` at top level publishes as a bare function reachable via `&foo` (see [modules](https://puck.uno/documentation/requirements/modules/)).
- `method &foo() ... end` in a class body publishes as a method on that class.

Either way, the callable object itself has the same shape. And either can be invoked in either style:

~~~caspian
$fn = function()
end

&fn                 # standalone call
$foo.$fn            # applied as a method on $foo, %self bound to $foo
~~~

The `$foo.$fn` pattern already works today via [downloaded-methods](https://puck.uno/documentation/requirements/classes/downloaded-methods) — the callable is bound to the receiver at the call site.

The declaration keyword sets initial attachment; the CALL SITE decides receiver binding.

## Receiver-globals are runtime-conditional

`%self`, `%bucket`, `%stack` are available when a callable is invoked as a method. They raise on access when invoked standalone:

~~~caspian
$fn = function()
	%bucket['foo'] = 'bar'
end

&fn                 # raises — no receiver context, %bucket is not defined
$obj.$fn            # ok — %bucket is $obj's bucket
~~~

Fail-loud: the developer who wrote a body that needs `%bucket` gets a specific error the first time someone calls it standalone, at the exact line the receiver-global was accessed. Not silently swallowed.

## Closures

Closures are functions that **capture the enclosing lexical scope** at the point of definition. Because of that capture, closures are **standalone-callable only** — they cannot be invoked as methods:

~~~caspian
$closure = closure()
	# captures whatever's in scope here
end

&closure            # ok
$obj.$closure       # RAISES — closures don't support method invocation
~~~

The reason: closures already captured a lexical scope, potentially including an outer `%self` / `%bucket` (if defined inside a method). Rebinding those to a new receiver via method invocation would either shadow the capture (defeats the purpose of the closure) or silently ignore the receiver (defeats the reason for the method call). Cleanest to just disallow.

## Helpers

A helper is a **function with a `class` bucket field and a canned body**. No new subclass — just a function with extra state and a pre-written implementation.

The canned body:

1. Reads `%bucket['class']` (the helper-class definition, stored at helper-declaration time).
2. Applies the caching modifier (lazy / fresh / default):
	- **fresh** — instantiate the class with the parent as target; return the instance; no caching.
	- **lazy** — check the parent-instance cache; if empty, instantiate and cache; return.
	- **default** — TBD; likely eager (instantiate at parent construction) or lazy (first-call). See [Open](#open).
3. Returns the (fresh or cached) helper instance.

Because the body is pre-written by the framework, the developer's `helper &name() ... end` block is just declaring the helper CLASS — the fields, methods, and inheritance of the helper instance. The function-that-returns-the-instance is generated automatically.

### Where the cache lives

The function object (the helper) is stored on the parent CLASS's method table — one function per class-method entry, shared across all instances of the parent class. Per-parent-instance state can't live on the shared function object; it belongs on the **parent object's bucket** — something like `%bucket['helpers'][name]` on each parent instance.

Fresh helpers skip the cache entirely. Lazy/default helpers write to and read from the per-parent cache.

## Conceptual object structure

At the Caspian-language level:

~~~
function:
{
	bucket: {
		code: [...]         # compiled function body (CaspJ)
	},
	stack: [ Function ]     # class stack
}

helper:
{
	bucket: {
		code: [...]         # canned instantiate-and-return body
		class: {...}        # the helper class definition
	},
	stack: [ Function ]     # same class as any function
}
~~~

Same class in the stack — a helper doesn't need a Function subclass. The presence of the `class` bucket field is what makes it a helper.

**Implementation latitude.** The above is the observable conceptual model. Lua implementation is free to organize however makes sense (userdata pointing at a C struct, closures capturing internal state, separate hash tables, whatever's efficient) as long as observable behavior matches.

## Bucket fields vs methods: separate namespaces

Ruby-style separation applies: `$foo.class` invokes the `.class` method (from the object namespace); `%bucket['class']` reads the bucket field. They coexist without conflict.

This means the `class` bucket field on a helper doesn't collide with the built-in `.class` accessor:

~~~caspian
$helper.class              # returns Function (the object's own class)
%bucket['class']           # inside the helper's canned body, reads the stored helper class
~~~

If we want a public accessor for the stored helper class, it's an explicit method: `.helper_class` reading `%bucket['class']`, or the developer reaches through the bucket directly.

## Open

- **Default modifier semantics.** What does a plain `helper &foo() ... end` (no `lazy`, no `fresh`) do? Eager at parent construction, lazy on first call, or something else? Lazy would match the "untouched helper = no side effect" pattern spec'd for `.accept` earlier; eager reads simpler for the reader. Pick one.
- **Closure-inside-method receiver capture.** If a closure is declared inside a method body, does it capture the method's `%self` at definition time? If so, does the captured receiver-context follow the closure when invoked standalone (`&captured_closure`), or does the standalone invocation strip receiver-globals per the rule above? Interaction between "closure captures lexical scope including receiver-globals" and "standalone invocation raises on receiver-globals" needs pinning.
- **Naming for the helper's stored class.** `.helper_class` accessor reading `%bucket['class']`? Or namespaced under `.helper.class`? Or expose via `%bucket['class']` and don't provide a shortcut method? Design taste.
- **Cache-key convention on the parent bucket.** `%bucket['helpers']` hash keyed by helper name, or something else? Should match whatever the runtime uses for helper lookup.

## Related

- [functions/bare](https://puck.uno/documentation/requirements/functions/bare) — the current spec for bare functions; the "function IS method" unification here would revise the sharp distinction that page currently draws.
- [functions/method](https://puck.uno/documentation/requirements/functions/method) — the current method spec, similarly revised under this unification.
- [functions/closure](https://puck.uno/documentation/requirements/functions/closure) — closures are still a distinct subtype (standalone-only); this spec sharpens why.
- [downloaded-methods](https://puck.uno/documentation/requirements/classes/downloaded-methods) — the `$obj.$fn` pattern that already binds a callable to a receiver at the call site; the unification here generalizes that as the primary method-invocation mechanism.
- [ideas/helper-build](helper-build) — the inline-helper DSL that produces these helper objects.
