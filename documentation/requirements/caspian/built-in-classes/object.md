# Object

`.object` is a universal helper accessible on every value in Caspian. It carries a
small, fixed set of methods that the engine guarantees about every object
regardless of class — truthiness classification, null detection, and similar
introspection that doesn't belong to any one class but applies uniformly to all.

<a id="methods"></a>
## Methods

~~~json
{"vibecode": {
	"section": "methods",
	"role": "documents the engine-controlled surface of the universal .object helper: bool plus three derived predicates, plus identity equality via ==",
	"key_concepts": ["bool_is_underlying_property", "predicates_derived_from_bool",
		"equality_on_.object_is_identity_not_value", "all_engine_enforced_and_read_only"]
}}
~~~

The current set:

| Method | Returns | True (or its bool equivalent) when |
|---|---|---|
| `bool` | `true`, `false`, or `null` | the engine's tri-value classification of this value |
| `null?` | strict boolean | `bool` is `null` |
| `defined?` | strict boolean | the opposite of `null?` |
| `==` | strict boolean | the other side's `.object` refers to the same underlying value (see [Identity](#identity) below) |

All of these are **read-only** and **engine-enforced**: user code cannot override them
or change what they return for a given object. They give consistent answers
regardless of what classes, fields, or methods user code attaches to the object.

---

<a id="bool"></a>
### `bool`

~~~json
{"vibecode": {
	"section": "bool",
	"returns": "tri_value",
	"role": "underlying tri-value classification; the other three predicates are derived from this; locked at instantiation and engine-enforced",
	"rule": "only_null_and_false_return_non_true; everything_else_is_true",
	"locked": "bool_is_set_at_instantiation_and_cannot_change_for_the_object's_lifetime",
	"mechanism": "sticky_platter_directly_under_the_shadow_carrying_class_puck_uno_null_or_puck_uno_false; absence_of_such_a_platter_means_true",
	"implementation": "engine_caches_bool_at_instantiation_for_constant_time_read; safe_because_value_never_changes",
	"see_also": "requirements/caspian/truthy.md for the broader model"
}}
~~~

Returns the engine's tri-value classification of the value:

- `null` for null values (regardless of flavor)
- `false` for the boolean `false` literal
- `true` for **everything else**

This is the underlying property. The other three methods are derived from it.

```
true.object.bool      # true
false.object.bool     # false
null.object.bool      # null
"hello".object.bool   # true
"".object.bool        # true   ← empty string is still true
0.object.bool         # true   ← zero is still true
[].object.bool        # true
{}.object.bool        # true
$some_instance.object.bool   # true   ← any user-class instance
```

The rule is deliberately simple: there is no notion of "empty is falsy"
or "zero is falsy." Only the literal `false` and `null` return non-true
bool. This matches Ruby's semantics and avoids the corner cases that
make C/Python/JS-style truthiness rules trip people up.

**Truthiness is locked at instantiation.** Whatever bool an object gets
when it's created stays for the object's lifetime. The bool value can
**never** change:

- Adding classes to an object's stack doesn't change its bool. A null
  with platters added is still a null (bool: null), even if its method
  surface is now richer.
- Mutating the object's bucket, locals, or platter buckets doesn't
  change its bool.
- Even if the program would consider the object "transformed into
  something else," the engine still answers with the original bool.

This is engine-enforced, by [the nanny](https://puck.uno/documentation/overview#no-nanny-code).

```
$x = null
$x.object.bool                              # null
$x.object.classes.add 'foo.bar/magic'       # adds methods
$x.object.bool                              # still null
```

<a id="bool-mechanism"></a>
#### Mechanism

An object's bool value is determined by what sits **directly under the shadow** in its stack:

| Stack under shadow | `.object.bool` returns |
|---|---|
| Nothing, or a platter whose class is anything other than null/false | `true` |
| A sticky platter with class `puck.uno/null` | `null` |
| A sticky platter with class `puck.uno/false` | `false` |

```
null.object.stack       # shadow, then sticky platter with class puck.uno/null
false.object.stack      # shadow, then sticky platter with class puck.uno/false
"hello".object.stack    # shadow, optionally other platters — none of them null/false
```

When the engine creates a `null` or `false` instance, it adds a sticky platter directly under the shadow carrying the appropriate class identity. The platter is sticky, the shadow above it is sticky, and stickiness propagates downward — so the non-truthy platter is pinned at position 1, cannot be moved, cannot be removed. Combined with [`sticky` being engine-only and one-way](../../ecoverse/objects/structure.md#sticky), this means:

- A value created as `null` stays `null` for its entire lifetime; same for `false`.
- A truthy value can never be made non-truthy at runtime. User code can't push a sticky `puck.uno/null` or `puck.uno/false` platter onto a value's stack because only the engine can mark a platter sticky.

There is no separate `puck.uno/truthiness` class; the platter's own class IS the null-or-false signal. See [truthy.md](../truthy.md) for the broader truthiness model.

#### Immutable primitives

**`null`, `true`, and `false` are fully immutable.** The engine freezes their entire stacks — no `.classes.add`, no `.classes.remove`, no `.object.method`, no bucket mutation. The whole object is a sealed unit.

The reason is load-bearing: if any program could mutate `true` or `null`, every truthiness check everywhere in the system becomes unreliable. These primitives sacrifice flexibility entirely so everything else can rely on them.

This is stricter than the marker classes' restriction. The marker classes can't be removed from the specific objects they're on (nulls, falses) because of stickiness, but user-class objects in general can still grow their stacks. The three primitives can't grow at all.

#### Implementation note

The conceptual model is a class-stack check on every `.object.bool`
call. Under the hood, the engine **caches** the bool value on each
object at instantiation time — a single internal slot per object,
read directly on every `.object.bool` call. The cache is safe
because the rule guarantees the value never changes; there is
nothing to invalidate.

The cache is not user-visible. Inspecting `$obj.object.classes`
shows the marker classes (the canonical source of truth); querying
`$obj.object.bool` returns the cached value (the fast read).
Programs and debuggers see consistent results either way.

<a id="null"></a>
### `null?`

~~~json
{"vibecode": {
	"section": "null",
	"returns": "strict_boolean",
	"role": "predicate for testing whether a value is null"
}}
~~~

Returns strict `true` if `bool` is `null`; otherwise strict `false`.

The correct tool for "is this value null?" — never `eq(x, null)`, never `x ==
null` (which works but is less clear than the predicate).

```
null.object.null?     # true
false.object.null?    # false
0.object.null?        # false
"".object.null?       # false   ← empty string is not null
"hello".object.null?  # false
```

<a id="defined"></a>
### `defined?`

Returns the opposite of [`null?`](#null) — strict `true` if `bool` is `true` or `false`; strict `false` if `bool` is `null`. Useful when "does this have a definite value?" reads more naturally than its negation.

---

<a id="object-methods"></a>
## `.object` methods

~~~json
{"vibecode": {
	"section": "object_methods",
	"role": "catalogs the .object methods that inspect or manipulate the platter stack, dispatch to specific classes, lock the object against modification, or expose a capability-restricted proxy",
	"key_concepts": ["object_classes_inspector", "isa_predicate", "shadow_access",
		"define_methods_on_shadow", "explicit_dispatch_call_with", "borrow_temporary_platter",
		"jail_capability_proxy", "freeze_classes_and_bucket"]
}}
~~~

These methods reach the platter stack, dispatch, and lifecycle controls through the `.object` namespace. The conceptual model — what `bucket`, `stack`, platters, and stickiness *are* — lives in [ecoverse/objects/](../../ecoverse/objects/) and [lucy/index.md § Object Model](../lucy/index.md#object-model); the entries below are the method catalog.

| Method | Returns | What it does |
|---|---|---|
| `classes` | array of just the classes in the stack | inspect class identity, or call `.add` to push a class |
| `stack` | the stack hash (platters with their `class`/`sticky`/`bucket`/`warning` fields) | full structural access including per-platter metadata |
| `isa?(uns)` | strict boolean | whether the named class is anywhere in the stack |
| `shadow` | the object's shadow class | direct handle to the per-instance class |
| `method(name) do(params…) … end` | the receiver | define a method on this one object (lives on its shadow) |
| `call_with(receiver, method, args…)` | whatever the method returns | dispatch the method on `receiver` using the receiver of `call_with` as the class providing the body |
| `borrow(uns) do … end` | the block's value | push a non-sticky platter for the duration of the block, then pop it |
| `jail(method_syms…)` | a new jail object | capability-restricting proxy exposing only the named methods |
| `freeze [do … end]` | the receiver | lock both class stack and bucket; with a block, releases on block exit |
| `classes.freeze [do … end]` | the receiver | lock the class stack only |
| `bucket.freeze [do … end]` | the receiver | lock the bucket only (via the bucket-jail; see below) |
| `bucket` | a jail wrapping `%bucket` with only `:freeze` permitted | hand external code the ability to freeze without exposing the data |
| `track` | writable boolean | set `track = true` to start recording every file:line where this object is used; off by default |
| `uses` | array of `{file, line}` records | the recorded use-sites for this object when tracking is on |

<a id="classes"></a>
### `classes`

Returns an array of just the classes in the object's platter stack — no platter metadata, just the class identities, in stack order (shadow first).

```
$foo.object.classes              # array of classes, top to bottom
$foo.object.classes.add 'foo.bar.gup'
```

`.add` pushes a class onto the stack as a new platter.

For the full structural view including per-platter `sticky` / `bucket` / `warning` fields, use [`stack`](#stack) instead.

<a id="stack"></a>
### `stack`

Returns the stack hash itself — the ordered map of platter-key → platter, where each platter carries its `class`, `sticky`, `warning`, and per-platter `bucket` per [ecoverse/objects/structure.md](../../ecoverse/objects/structure.md):

```
$foo.object.stack         # the full stack hash
null.object.stack         # shadow + sticky platter with class puck.uno/null
"hello".object.stack      # shadow, optionally other platters — none null/false
```

Use this when you need to see platter metadata; use [`classes`](#classes) when you only care about class identities.

<a id="isa"></a>
### `isa?`

Walks the stack and returns strict `true` if the named UNS matches any class in it (including any class's inheritance chain). Use it for class-membership checks without caring about the exact resolution path:

```
$foo.object.isa? 'puck.uno/color'    # true if 'puck.uno/color' is in the stack
                                       # (the object's class or any superclass)

if $foo.object.isa? 'puck.uno/error'
    # $foo is an error of some kind
end
```

The trailing `?` is the Caspian convention for predicate methods (boolean-returning).

<a id="shadow"></a>
### `shadow`

Returns the object's shadow class — a unique, fresh class the engine creates for each object at instantiation. Adding methods to it adds methods to that one object only. Usually accessed through `.object.method` (below); the direct handle is available when you need it explicitly.

<a id="method"></a>
### `method`

Defines a method on this one object. The method lives on the object's shadow, so it doesn't affect any other object — even other instances of the same class.

```
$foo.object.method('foo') do($bar, $gup)
    ...
end
```

The first argument is the method name (a string). The block's parameters are the method's parameters. The block body is the method body — normal method context applies (`@field`, `%bucket`, `self` is `$foo`).

Inside a class body, `self` refers to the class object itself, so class-level methods are defined the same way:

```
class 'color'
    self.object.method('blue') do
        return color.new(hex: '#0000ff')
    end
end
```

`null`, `true`, and `false` are fully locked — `.object.method` on any of them raises.

<a id="call-with"></a>
### `call_with`

To call a method from a specific class in the stack — bypassing the normal top-down walk — use `call_with`. The class must be present in the receiver's stack:

```
$class = $foo.object.classes.find(...)
$class.object.call_with($foo, 'greet', name: 'Jean-Luc')
```

Rare. Normal method resolution handles the common case; `call_with` is for code that needs to reach a specific class's implementation directly.

<a id="borrow"></a>
### `borrow`

Pushes a class onto the receiver's stack as a non-sticky platter, runs the block, then pops the platter. Inside the block, methods on the receiver dispatch through its augmented stack — borrowed methods are reachable alongside everything else:

```
$result = $foo.object.borrow('bar.gup/serializer') do
    $foo.to_xml(indent: 2)
end
```

Rules:

- **The block is required.** No bare-call form. Inside the block, `self` is unchanged — the borrow modifies the receiver's stack, not the calling context. Method calls go through `$foo.method()` explicitly.
- **Exception-safe.** The platter is popped even if the block raises.
- **The platter is always non-sticky.** Borrow is transient by definition; if the platter were sticky, it couldn't be popped at block end. Borrow takes no sticky flag.
- **Classes that declare themselves sticky-required cannot be borrowed.** A class whose security guarantee depends on never being removable (e.g. `puck.uno/class/redact`) raises before the block runs. Better to fail explicitly than silently weaken the class's intent.
- **At block end the engine deletes the platter outright** (it didn't hold user-allocated data; `%platter` access is not permitted inside a borrow). No accumulating inactive borrow platters in the stack.
- **Local borrow, not remote.** The borrowed class works directly on the receiver, no clone. For send-a-clone-to-another-process semantics, use Puck (`%puck[...]`) instead.

What the borrowed class sees: the receiver's shared bucket (via `%bucket` / `@field`), the other classes in the stack (via normal dispatch), `self` as the receiver. Role transitions apply normally — cross-role borrows transition like any other cross-role method call.

Nested borrows compose. Each `borrow` pushes; each block end pops its own:

```
$foo.object.borrow('class_a') do
    $foo.object.borrow('class_b') do
        # both class_a and class_b are in $foo's stack here;
        # class_b dispatches first (pushed later, sits above class_a in
        # the non-sticky portion of the stack)
    end
    # only class_a in $foo's stack now
end
# back to $foo's original stack
```

Typical use cases: pluggable interpretations of the same data through different specialized classes, visitor patterns, adapter dispatch (applying protocol-specific behavior to objects that don't carry the protocol class).

<a id="jail"></a>
### `jail`

Creates a capability-restricting proxy that wraps the receiver and exposes only the named methods. Calls to allowed methods are forwarded transparently to the underlying object; calls to anything else fail:

```
$jail = $foo.object.jail(:greet, :save)
$jail.greet(name: 'Jean-Luc')   # forwarded to $foo
$jail.destroy                   # fails — not in the allowed list
```

The wrapped object is unaware it's being called through a jail (a method that explicitly inspects the call stack can see it). When the wrapped object is a function, jailing with `:call` produces a callable jail:

```
$bar = $foo.object.jail(:call)
&bar                            # forwards to $foo
```

Jail fits the object-capability security model — pass a jail instead of the full object when the recipient only needs a subset of its capabilities. The jail's internals (wrapped object, allowed list) live in its own bucket as `@prisoner` / `@allowed`; external code cannot reach the prisoner directly through the jail — that's the point.

<a id="freeze"></a>
### `freeze`

Locks the receiver against modification. Caspian splits this into two independent axes — the class stack and the bucket — rather than conflating them:

```
$foo.object.freeze         # freeze both classes and bucket
$foo.object.stack.freeze   # freeze the stack only
$foo.object.bucket.freeze  # freeze %bucket only
```

Any of these can be called by whoever holds a reference to the object — freezing is not restricted to the object itself.

**Permanent without a block.** There is no `unfreeze`. Once frozen, that axis stays frozen for the lifetime of the object.

**Temporary with a block.** The freeze holds for the duration of the block and releases when the block exits:

```
$foo.object.freeze do
    # both classes and bucket are frozen here
end
```

What each freeze prevents:

- **Classes freeze** — the class stack cannot be modified. No platters can be added or removed, and `object.method` is blocked. The methods the object has at freeze time are the methods it will always have.
- **Bucket freeze** — `%bucket` becomes read-only. Any attempt to write to `@foo` or otherwise modify the bucket hash raises.

<a id="bucket-helper"></a>
### `bucket`

Returns a jail wrapping `%bucket` with only `:freeze` permitted. This is what gives external code the ability to freeze the object's bucket without exposing the data itself:

```
$foo.object.bucket.freeze       # fine — one permitted operation
$foo.object.bucket['key']       # fails — not in the allowed method list
```

<a id="track"></a>
### `track`

Setting `$foo.object.track = true` turns on **per-object use tracking**. The engine records every file and line where this object appears in running code — passed as an argument, returned, stored in a hash, used as a method receiver, anywhere it shows up. Tracking is off by default; setting `track = true` opts in for this one object.

```
$foo.object.track = true

$foo                       # use recorded here
some_method($foo)          # and here
$bar = $foo                # and here ($bar is now a separate name for the same object,
                           # so $bar also exercises this object's tracking)
```

Tracking follows **object identity**, not variable names. Any name that resolves to the same object counts as a use of that object.

Use cases:

- **Find unexpected uses** — realize the object showed up somewhere it shouldn't have.
- **Find missing uses** — realize the object was *absent* from places it should have appeared.
- **Trace where it ended up** — useful for objects that get passed deep into library code.

This is the beginner baseline: file + line per use, nothing else. Later work will add change tracking (when did the bucket mutate, what changed), richer event metadata (timestamps, call frame, role), and possibly value snapshots. Those land as the feature settles.

<a id="uses"></a>
### `uses`

Returns the recorded use-sites for this object — an array of `{file, line}` records in the order they were encountered. Empty when tracking is off or when no uses have been recorded yet.

```
$foo.object.uses          # [{file: ..., line: ...}, ...]
```

The exact record shape may grow over time (timestamps, frame info, etc.); for now it's just file and line. The accessor name is provisional — could become `history`, `sites`, or something else as the feature lands.

---

<a id="identity"></a>
## Identity

~~~json
{"vibecode": {
	"section": "identity",
	"role": "reference-equality semantics on .object",
	"key_concepts": ["==_between_two_.object_results_is_identity_not_value_equality",
		"engine_enforced_cannot_be_overridden",
		"split_value_eq_on_the_value_identity_on_.object"]
}}
~~~

Comparing two `.object` results with `==` tests **object identity** (reference
equality) — true only when both `.object` accesses refer to the same underlying
value:

```
$foo = {name: 'Picard'}
$bar = $foo
$baz = {name: 'Picard'}

$foo.object == $bar.object   # true  ← same underlying object
$foo.object == $baz.object   # false ← distinct objects, equal contents
$foo == $baz                 # true  ← value equality
```

The split is clean:

- `$foo == $bar` — **value equality**. Controlled by the value's class; can be
  overridden by user code (e.g., a class defining its own `==`).
- `$foo.object == $bar.object` — **object identity**. Engine-enforced;
  cannot be overridden.

**Default `==` is identity equality.** Every object inherits a base
`==` from the root that returns `true` only when the other side is
the same object — equivalent to `$foo.object == $other.object`.
Classes that want value-based equality (string, number, hash,
array, null) override `==` for their own use case. A class that
doesn't override gets the identity default automatically, so
unfamiliar user-defined classes start with the safe behavior
(two distinct instances are not equal) instead of an undefined
state.

**No built-in `===` operator.** Caspian does not define `===` at the
language level. The canonical "same object?" check is
`$foo.object == $bar.object`. Programs or libraries are free to
define their own `===` for whatever semantics make sense in their
domain — the operator name is not reserved by the engine.

**Engine-only equality classes.** `puck.uno/null`,
`puck.uno/false`, and `puck.uno/true` all declare
`engine_only: true` at the class level
(see [base-class-use.md § engine_only](../../ideas/base-class-use.md#engine-only)).
User code cannot push any of them onto another object's class
stack:

```
$foo = 'bar'
$foo.object.classes.add 'puck.uno/null'    # raises — engine_only
```

This closes off the path where a truthy object could be made to
return `true` for `$x == null` by inheriting the null class's
`==` override. The classes' identity-bearing `==` only applies
to objects the engine itself created as null, false, or true.

A reader seeing `==` between two `.object` accesses knows immediately that it's
an identity check, not a value comparison. The `.object` namespace already
signals "the engine talking, not the class," and `==` between two engine views
is the natural place for identity semantics — no new operator is needed.

Like the other `.object` methods, identity equality is **read-only and
engine-enforced**. No user class can change what counts as "the same object."

---

<a id="identity-guarantees"></a>
## Identity Guarantees

~~~json
{"vibecode": {
	"section": "identity_guarantees",
	"role": "states that all four .object methods are read-only and engine-controlled; user code cannot override them"
}}
~~~

The values returned by these four methods are determined at object creation and
cannot be changed by user code. The engine maintains them at a level user code
cannot reach. This is the protection mechanism that makes null/true/false
reliable across the language — see [nulls.md](nulls.md#identity-guarantees) for
the related guarantees on tri-value identity.

User code can attach classes, set fields, define methods, and otherwise customize
a value freely. None of those customizations affect what `.object.bool` or
its derived predicates return. The engine ignores user-defined methods named
`bool`, `null?`, or `defined?` if any are attached to a value's classes — the
`.object.*` access path goes to the engine's enforced versions, not to user
overrides.

---

<a id="why-object"></a>
## Why `.object`

~~~json
{"vibecode": {
	"section": "why_dot_object",
	"role": "explains the design choice to namespace these methods under .object rather than directly on every value"
}}
~~~

The methods could have been put directly on every value (`$foo.null?`), but
that would mix engine-controlled methods into every object's normal method
namespace. The `.object` indirection keeps a clean separation:

- Methods under `.object` — universal, engine-controlled, can't be overridden.
- Methods directly on a value — belong to that value's class hierarchy and can
  be overridden as usual.

A reader seeing `$foo.bar?` knows this is the value's class talking. A reader
seeing `$foo.object.bar?` knows this is the engine talking. The visual
distinction makes the reasoning clearer.

The cost is one extra dot per call. Worth it for the clarity.

---

<a id="naming-conventions"></a>
## Naming Conventions

A small set of method names carry agreed-upon meanings across the project.
These are **conventions**, not framework features — the runtime doesn't
enforce them and individual classes implement them however makes sense.
They exist so a reader sees the name and knows what it signals.

<a id="destroy"></a>
### `destroy`

A method named `destroy` on a class indicates that calling it **closes
the object down and renders it useless**. What "useless" means in
practice is up to the class:

- A database connection's `destroy` might close the network handle and
  roll back open transactions.
- A file handle's `destroy` might flush and close the underlying stream.
- A subscription object's `destroy` might unregister itself from
  notifications.

After `destroy` returns, subsequent operations on the object are expected
to fail (typically with a clear error). The class designer decides the
specifics — there's no framework-imposed `destroyed?` predicate, trust
check, or cascade rule.

This is a convention for classes that **own a resource with a lifecycle**.
Plain data classes (hashes, arrays, strings, etc.) should not have a
`destroy` method — they have no lifecycle to close down. A reader seeing
`$foo.destroy` should be able to assume `$foo` represents a resource.
