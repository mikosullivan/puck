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
| `truthy?` | strict boolean | `bool` is `true` |
| `null?` | strict boolean | `bool` is `null` |
| `defined?` | strict boolean | `bool` is `true` or `false` (not null) |
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
	"mechanism": "two_sticky_restricted_addition_marker_classes_puck_uno_class_bool_null_and_puck_uno_class_bool_false; absence_of_both_means_true",
	"implementation": "engine_caches_bool_at_instantiation_for_constant_time_read; safe_because_value_never_changes"
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

This is engine-enforced, by the nanny.

```
$x = null
$x.object.bool                              # null
$x.object.classes.add 'foo.bar/magic'       # adds methods
$x.object.bool                              # still null
```

<a id="bool-mechanism"></a>
#### Mechanism

Conceptually, an object's bool value is determined by which of two
engine-managed marker classes (if any) appear in its pinned region:

- **`puck.uno/class/bool_null`** — present on every null instance
- **`puck.uno/class/bool_false`** — present on the literal `false`
- **Neither** — every other object (defaults to bool true)

```
null.object.classes      # pinned region includes bool_null
false.object.classes     # pinned region includes bool_false
"hello".object.classes   # no bool_* marker → defaults to true
```

The markers live in the **pinned region** of the class stack (see
[base-class-use.md § Pinned and mutable regions](../../ideas/base-class-use.md#pinned-and-mutable-regions)),
which means:

- They sit at fixed positions in the stack and cannot be moved,
  removed, or replaced. The engine adds them at instantiation;
  nothing can change them afterward.
- User code calling `.classes.add 'puck.uno/class/bool_null'` raises
  — pinned-region addition is restricted to the engine.
- User code calling `.classes.remove(<marker-uuid>)` on the marker
  raises — pinned platters can't be removed.

Both classes are **pure markers** — no methods, no bucket contents.
The engine reads "is this class in the pinned region?" to determine
the bool.

`puck.uno/class/bool_null` and `puck.uno/class/bool_false` are
reserved UNS strings. Two more entries in the engine-owned
namespace; the cost of an inspectable, uniform mechanism that
uses no parallel structure outside the class stack.

#### Immutable primitives

**`null`, `true`, and `false` are fully immutable.** Their entire
class stacks (pinned region included) are engine-frozen — no
`.classes.add`, no `.classes.remove`, no `.object.define`, no
bucket mutation. The whole object is a sealed unit.

The reason is load-bearing: if any program could mutate `true` or
`null`, every truthiness check everywhere in the system becomes
unreliable. These primitives sacrifice flexibility entirely so
everything else can rely on them.

This is stricter than the marker classes' restriction. The marker
classes can't be removed from the specific objects they're on
(nulls, falses), but in general user-class objects can still grow
their class stacks. The three primitives can't grow at all.

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

<a id="truthy"></a>
### `truthy?`

~~~json
{"vibecode": {
	"section": "truthy",
	"returns": "strict_boolean",
	"role": "predicate that collapses false and null into not-truthy; matches if-statement branching"
}}
~~~

Returns strict `true` if `bool` is `true`; otherwise strict `false`.

Collapses `false` and `null` into "not truthy" — the same way `if` does. Useful
when you want a clean boolean that follows the same rule as `if`-statement
branching:

```
"hello".object.truthy?    # true
0.object.truthy?          # true    ← zero is still truthy
"".object.truthy?         # true    ← empty string is still truthy
false.object.truthy?      # false
null.object.truthy?       # false
```

The Ruby idiom `def ready?; @ready ? true : false; end` is just
`@ready.object.truthy?` in Caspian.

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

~~~json
{"vibecode": {
	"section": "defined",
	"returns": "strict_boolean",
	"role": "predicate for testing whether a value is non-null (true or false)"
}}
~~~

Returns strict `true` if `bool` is `true` or `false`; strict `false` if `bool` is
`null`. Equivalent to `not(null?)`.

Useful when you want "does this have a definite value?" — distinguishing "the
field has a real value, even if that value is `false`" from "the field is null":

```
true.object.defined?     # true
false.object.defined?    # true   ← false is still defined
0.object.defined?        # true
"".object.defined?       # true
null.object.defined?     # false  ← only null is undefined
```

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
a value freely. None of those customizations affect what `.object.bool` (or any of
the derived predicates) returns. The engine ignores user-defined methods named
`bool`, `truthy?`, `null?`, or `defined?` if any are attached to a value's classes
— the `.object.*` access path goes to the engine's enforced versions, not to user
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

The methods could have been put directly on every value (`$foo.truthy?`), but
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
