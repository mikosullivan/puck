# `.has_method?`

<span class="tag">has-method</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_classes_has_method",
	"role": "spec for `.has_method?(name)` on class objects. Returns the method object if the class (or any class in its inheritance chain) publishes a method with the given name; returns a falsy value (null or false — implementation-time economy call) otherwise. Truthy-when-found and falsy-when-not, so it composes with `if $m = $class.has_method?(:foo)` idiom — the returned method captures if the caller wants it for introspection or direct invocation, but the check itself works as a plain predicate too. Consults the standard method-resolution graph, sees inherited methods just like real dispatch. Accepts the method name as a symbol or a string. Returning the method object rather than a synthesized boolean is cheaper — no allocation, the class already holds the reference. Used by delegation dispatch (see ideas/helper-build) and general introspection.",
	"status": "spec — return-method-or-falsy shape and lookup semantics settled; private-method visibility and nested-namespace behavior still open; specific choice of null-vs-false for the falsy return deliberately deferred to implementation",
	"audience": "developers writing delegation, introspection, or class-inspection tools; anyone building on top of class objects at runtime"
}}
~~~

Every class object exposes a `.has_method?` accessor: given a method name, returns the method object if the class would resolve one with that name for its instances; returns a falsy value otherwise. (Whether the falsy value is null or false is an [implementation-time economy call](#falsy-return-null-or-false); both work identically for callers.)

~~~caspian
$myclass.has_method?(:foo)     # method object, or falsy
$myclass.has_method?('foo')    # string form also accepted
~~~

Truthy-when-found and falsy-when-not, so the plain-predicate reading still works:

~~~caspian
if $class.has_method?(:foo)
	# ... class publishes a &foo method ...
end
~~~

And the capture idiom works too, when the caller wants the method itself:

~~~caspian
if $m = $class.has_method?(:foo)
	# $m is the method object — usable for introspection, or direct invocation
end
~~~

## Why the method object rather than a boolean

Returning the method object is cheaper than synthesizing a boolean — the class already holds the method reference, so returning it is a pointer copy with no allocation. Returning true would require producing the boolean value; returning the method is essentially free. The truthy semantics needed for `if` come along for the ride.

## Falsy return: null or false

When the method isn't found, `.has_method?` returns a falsy value. Whether that value is null or false is deliberately left to implementation — both work identically for the `if $m = $class.has_method?(...)` idiom, both fail truthiness checks the same way, and neither can be confused with the method-object return since methods aren't booleans and aren't null.

The choice is an **economy call**: whichever is cheaper to hand back at runtime. Null is likely (Caspian's ambient absence value; no synthesis needed), but if implementation reveals false is cheaper in the specific hot path, false is fine. The spec doesn't commit; the implementation picks.

Callers that need to distinguish "not found" from something else can compare against `null`, `false`, or check the return type — all work regardless of which falsy value the implementation returns, since methods are neither null nor false.

## What it checks

`.has_method?` walks the same method-resolution graph a real dispatch would ([method-resolution](tag:method-resolution)):

- **Methods declared on the class itself** — yes.
- **Methods inherited from parent classes** (any depth, following the class's `.inherited` array and each parent's inherited array) — yes.
- **Nothing found in the walk** — returns a falsy value (see [Falsy return: null or false](#falsy-return-null-or-false)).

The accessor doesn't call any method; it only asks "would resolution find one." Side-effect-free.

## Symbol or string

Method names accepted as either symbols (`:foo`) or strings (`'foo'`). Consistent with how method-related APIs elsewhere in Caspian accept both forms.

## Typical use

**Delegation dispatch** — when the engine walks a class's delegations looking for a match, class-ref entries are consulted via `.has_method?`. The engine only needs the boolean signal for the dispatch decision; the returned method is available if it's useful, and cheap regardless. See [ideas/helper-build § The dispatch model](https://puck.uno/ideas/helper-build#the-dispatch-model) for the driving use case.

Also useful for:

- **Introspection tools** categorizing a class's public surface.
- **Runtime feature checks** — "does this class provide `.serialize`?"
- **Direct capture and invoke** — `if $m = $class.has_method?(:name)` then use `$m` via [downloaded-methods](downloaded-methods) or the method object's own invocation surface.

## Not `.methods`

`.has_method?` is a single-name lookup, cheaper than materializing the full method surface. For enumeration, use the [`.methods`](https://puck.uno/requirements/built-in-classes/object/methods/#methods) accessor on the class object (which returns a lazy hash-like object of all methods). `.has_method?(name)` short-circuits at the first match; `.methods.has?(name)` has to touch the enumeration machinery.

## Testing

- **Locally-declared method** — `class # foo; method &bar() end; end`, then `$foo.has_method?(:bar)` returns the `&bar` method object (truthy).
- **Not declared** — `$foo.has_method?(:not_there)` returns falsy.
- **Inherited method** — parent class declares `&bar`, child inherits — `$child.has_method?(:bar)` returns the method object (via the chain).
- **Deep inheritance** — grandparent declares `&bar` — child still gets the method.
- **String or symbol** — `.has_method?(:bar)` and `.has_method?('bar')` return the same value.
- **Truthy in `if`** — `if $m = $foo.has_method?(:bar) ... end` enters the block when the method exists; `$m` is bound to the method object.
- **Falsy in `if`** — same idiom returns falsy for a missing method; the block is skipped.
- **After runtime inheritance mutation** — after `$foo.inherited.push($extra)`, `$foo.has_method?(:method_from_extra)` returns the method; after `.delete($extra)`, returns falsy. Consistent with the "no cache; live" model of `.inherited`.

## Open

- **Private methods.** When called from inside the class's own methods, does `.has_method?` return private methods (yes, since they're callable from that context)? From outside, does it return them (probably no, since they're not callable)? Access-scoped, matching how `.object.methods` handles the same question, is the likely answer — but needs confirming.
- **Nested-namespace names.** `$foo.has_method?(:object)` — does it return the top-level namespace-object for `.object` (which every class inherits)? What about `$foo.has_method?(:truthy?)` — does it walk into the `.object` namespace to find `truthy?`, or return falsy since `truthy?` isn't a top-level method on the class? Matches whatever [object/methods § `.methods`](https://puck.uno/requirements/built-in-classes/object/methods/#methods) does for the same case; worth restating here.

## Related

- [`.inherited`](tag:class-inheritance) — the parent-class array walked by method resolution; `.has_method?` follows the same chain.
- [method-resolution](tag:method-resolution) — the algorithm `.has_method?` consults.
- [object/methods § `.methods`](https://puck.uno/requirements/built-in-classes/object/methods/#methods) — the enumeration surface (`.methods` returns a lazy hash-like object); `.has_method?` is a cheaper single-name lookup.
- [downloaded-methods](downloaded-methods) — the `$obj.$fn` pattern for invoking a captured method value against a receiver.
