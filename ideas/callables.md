# Idea: Callables

~~~vibecode
{"vibecode": {
	"doc": "ideas_callables",
	"role": "spitball page for Caspian's unified callables model. Function IS method — the object is the same, invocation context (standalone vs method) determines receiver-globals binding. Closure ⊂ function but standalone-callable only (rebinding a captured lexical scope to a new receiver either shadows the capture or ignores the receiver, both wrong). Helper = function + .class field + canned body that instantiates the class and returns the instance, with lazy/fresh/default modifiers controlling per-parent caching. Receiver-globals (%self, %bucket, %stack) raise on access when the callable was invoked standalone. Conceptual object structure spec'd here at the Caspian-language level; Lua implementation is free to organize differently as long as observable behavior matches. Bucket fields and methods live in separate namespaces (`.class` is a method; `%bucket['class']` is a field; no collision, Ruby-style). Per-parent cache for helpers lives on the parent's bucket, not on the shared function object.",
	"status": "brainstorm — unification model settled; closure-as-method rule: V1 uses the blanket disallow (closures cannot be invoked as methods, matching the current spec), post-V1 narrowed-rule proposal (raise only when the closure captured %self / %bucket; otherwise method invocation works) documented for revisit with the two-case analysis and three-resolution comparison; open questions on default helper caching mode and accessor naming for the helper class",
	"context": "started while designing helper method semantics; unifying function-and-method into a single Callable simplified helper's story (it's just a function with extra bucket state) and clarified the receiver-context distinction"
}}
~~~

Caspian's callables — functions, closures, methods, helpers — are all specializations of a single Callable model. The label "function" vs "method" tracks how you're calling the thing right now, not what it fundamentally is. Different subtypes (closure, helper) add behavior on top; the base is a function that runs some code when called.

## Function IS method

A callable declared with `function &foo() ... end` and a callable declared with `method &foo() ... end` produce the **same underlying object**. The difference is attachment and invocation, not identity:

- `function &foo() ... end` at top level publishes as a bare function reachable via `&foo` (see [modules](https://puck.uno/requirements/modules/)).
- `method &foo() ... end` in a class body publishes as a method on that class.

Either way, the callable object itself has the same shape. And either can be invoked in either style:

~~~caspian
$fn = function()
end

&fn                 # standalone call
$foo.$fn            # applied as a method on $foo, %self bound to $foo
~~~

The `$foo.$fn` pattern already works today via [downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods) — the callable is bound to the receiver at the call site.

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

Closures are functions that **capture the enclosing lexical scope** at the point of definition. That capture includes `%self` and `%bucket` when the closure is defined inside a method's body.

### V1 rule: blanket disallow

**V1 rule: closures cannot be invoked as methods.** `$obj.$closure` raises regardless of whether the closure captured `%self` / `%bucket` or not. Blanket disallow — simplest rule to spec and implement; buys V1 time to see if the narrower rule proposed below is worth the runtime check.

~~~caspian
$closure = closure()
	# captures whatever's in scope here
end

&closure            # ok
$obj.$closure       # RAISES in V1
~~~

### Why not just let invocation shadow?

Because `%self` and `%bucket` in a closure body are potentially captured names. If the closure was defined inside a method, those names were already lexically bound to the method's receiver at definition time. Method invocation of that closure via `$other.$closure` would need to shadow those captures with the invocation's `%self` / `%bucket` — but the developer wrote the closure body expecting lexical-capture semantics. Silently changing what those names refer to at invocation time breaks the expectation.

Half-and-half doesn't work either: `%self` and `%bucket` are logically linked (`%bucket = %self`'s bucket). A design that took `%self` from the invocation but `%bucket` from the capture would produce a nonsensical pairing.

### The two-case distinction (deferred past V1)

The blanket V1 rule is broader than the ambiguity it protects against. Post-V1, worth revisiting with a narrower rule that fires only on the actually-ambiguous case.

**Case A: closure defined OUTSIDE any method.**

~~~caspian
$foo = 'bar'

$closure = closure()
	%bucket['foo'] = $foo
end
~~~

No `%self` / `%bucket` in scope at definition, so nothing gets captured for those names. `%bucket` inside the closure body has no captured referent. If this closure is invoked via `$obj.$closure`, the invocation's receiver's bucket is the only candidate `%bucket` can mean — no conflict. Disallowing this is nanny code.

**Case B: closure defined INSIDE a method's body.**

~~~caspian
$clss = class
	method &foo()
		$bar = 'gup'

		$closure = closure()
			%bucket['bar'] = $bar
		end

		return $closure
	end
end
~~~

`%self` and `%bucket` ARE in scope at definition and get captured by the standard lexical-capture rule. If this closure is later invoked via `$other.$closure`, `%bucket` in the closure body has two candidate referents — the captured one (the enclosing method's receiver's bucket) or the invocation-provided one (`$other`'s bucket) — with no obvious right answer.

### Three ways to resolve Case B

1. **Invocation shadows.** Invocation's `%self` / `%bucket` win; captured ones become inaccessible from inside the closure body. Consistent with normal lexical shadowing rules, but surprising for a developer who wrote a closure expecting capture semantics.
2. **Capture wins.** Invocation's `%self` / `%bucket` are ignored. Then the receiver in `$other.$closure` is provided but has no effect — the closure body silently uses the enclosing method's receiver. Very confusing.
3. **Raise.** Method invocation of a receiver-globals-capturing closure is disallowed. Developer invokes standalone (`&closure`, getting capture semantics), or restructures to capture an explicit local (`$outer_bucket = %bucket`) and references that local instead of `%bucket`.

Option 2 is clearly bad. Option 1 has a soft footgun (silent shadowing of what looks like a captured binding). Option 3 is loud and safe.

### Proposed post-V1 rule

**Closure invocation as a method raises IF the closure captured `%self` or `%bucket`. Otherwise method invocation works normally.**

- Case A → method invocation works. The closure sees the invocation's `%self` / `%bucket`.
- Case B → method invocation raises. Developer invokes standalone, or restructures to capture an explicit local (`$outer_bucket = %bucket`) and references that local from inside the closure body.

Not nanny code — the raise fires only on the specific case with a genuine ambiguity, and there's an explicit escape hatch. The narrower rule requires a runtime check ("did this closure capture `%self` / `%bucket`?"), which is cheap: a flag set on the closure object at definition time.

V1 defers this narrowing because the blanket rule is simpler to spec and implement, and the loss (Case A closures also can't be invoked as methods) is small — developers can wrap the closure in a bare function that takes the receiver explicitly, or use a downloaded-methods pattern.

### Lifetime capture and rejected alternatives

The closure's captured scope stays alive as long as the closure does — including whatever resources happen to be bound in that scope. The observable behavior is spec'd at [functions/closure § Captured scope keeps resources alive](https://puck.uno/requirements/functions/closure#captured-scope-keeps-resources-alive); the design commentary about why the trade-off looks the way it does lives here.

Two alternative designs surveyed and rejected:

- **Weak captures.** The closure captures the scope by weak reference; the scope can be GC'd out from under it if no other holder keeps it alive. Downside: closures become fragile — invoking a closure whose captured scope has been reclaimed produces surprises (variables gone, methods on captured objects no longer callable). Java's WeakReference-based patterns have this exact class of bugs. Rejected.
- **Explicit capture lists.** The developer enumerates in the closure declaration which outer names to capture (C++ lambdas take this approach). Downside: verbose at the call site, easy to forget a name that turns out to be needed later, and doesn't actually solve the lifetime issue — captured names still keep their referents alive as long as the closure lives. Rejected because the extra syntax buys no lifetime win.

**Actual choice: full-scope reference capture** — the standard model shared by Ruby Procs, JavaScript closures, and Python cells. Lifetime trade-off exists but is well-understood; developer-facing mitigation patterns (explicit close, narrow the capture, drop the closure reference early) are spec'd on the requirements page.

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
- **Closure-as-method rule refinement.** V1 uses the blanket disallow described in [§ Closures](#closures). The narrower post-V1 proposal (raise only when the closure captured `%self` / `%bucket`) is spec'd in the same section; needs implementation buy-in and a survey of real Case A use cases before promotion.
- **Naming for the helper's stored class.** `.helper_class` accessor reading `%bucket['class']`? Or namespaced under `.helper.class`? Or expose via `%bucket['class']` and don't provide a shortcut method? Design taste.
- **Cache-key convention on the parent bucket.** `%bucket['helpers']` hash keyed by helper name, or something else? Should match whatever the runtime uses for helper lookup.

## Related

- [functions/bare](https://puck.uno/requirements/functions/bare) — the current spec for bare functions; the "function IS method" unification here would revise the sharp distinction that page currently draws.
- [functions/method](https://puck.uno/requirements/functions/method) — the current method spec, similarly revised under this unification.
- [functions/closure](https://puck.uno/requirements/functions/closure) — closures are still a distinct subtype (standalone-only); this spec sharpens why.
- [downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods) — the `$obj.$fn` pattern that already binds a callable to a receiver at the call site; the unification here generalizes that as the primary method-invocation mechanism.
- [ideas/helper-build](helper-build) — the inline-helper DSL that produces these helper objects.
