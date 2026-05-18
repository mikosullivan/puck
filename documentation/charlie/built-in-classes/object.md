# Object

`.object` is a universal helper accessible on every value in Charlie. It carries a
small, fixed set of methods that the engine guarantees about every object
regardless of class — truthiness classification, null detection, and similar
introspection that doesn't belong to any one class but applies uniformly to all.

<a id="methods"></a>
## 1 Methods

```
vibecode: {
	"section": "methods",
	"role": "documents the four engine-controlled methods on the universal .object helper: bool plus three derived predicates",
	"key_concepts": ["bool_is_underlying_property", "predicates_derived_from_bool",
		"all_four_engine_enforced_and_read_only"]
}
```

The current set:

| Method | Returns | True (or its bool equivalent) when |
|---|---|---|
| `bool` | `true`, `false`, or `null` | the engine's tri-value classification of this value |
| `truthy?` | strict boolean | `bool` is `true` |
| `null?` | strict boolean | `bool` is `null` |
| `defined?` | strict boolean | `bool` is `true` or `false` (not null) |

All four are **read-only** and **engine-enforced**: user code cannot override them
or change what they return for a given object. They give consistent answers
regardless of what classes, fields, or methods user code attaches to the object.

---

<a id="bool"></a>
### 1.1 `bool`

```
vibecode: {
	"section": "bool",
	"returns": "tri_value",
	"role": "underlying tri-value classification; the other three predicates are derived from this"
}
```

Returns the engine's tri-value classification of the value:

- `true` for any truthy value (the boolean `true`, numbers other than `0`, non-empty
  strings, hashes, callables, etc.)
- `false` for the boolean `false` value
- `null` for null values

This is the underlying property. The other three methods are derived from it.

```
"hello".object.bool   # true
0.object.bool         # false
false.object.bool     # false
null.object.bool      # null
```

<a id="truthy"></a>
### 1.2 `truthy?`

```
vibecode: {
	"section": "truthy",
	"returns": "strict_boolean",
	"role": "predicate that collapses false and null into not-truthy; matches if-statement branching"
}
```

Returns strict `true` if `bool` is `true`; otherwise strict `false`.

Collapses `false` and `null` into "not truthy" — the same way `if` does. Useful
when you want a clean boolean that follows the same rule as `if`-statement
branching:

```
"hello".object.truthy?    # true
0.object.truthy?           # false
false.object.truthy?       # false
null.object.truthy?        # false
```

The Ruby idiom `def ready?; @ready ? true : false; end` is just
`@ready.object.truthy?` in Charlie.

<a id="null"></a>
### 1.3 `null?`

```
vibecode: {
	"section": "null",
	"returns": "strict_boolean",
	"role": "predicate for testing whether a value is null"
}
```

Returns strict `true` if `bool` is `null`; otherwise strict `false`.

The correct tool for "is this value null?" — never `eq(x, null)`, never `x ==
null` (which works but is less clear than the predicate).

```
null.object.null?     # true
false.object.null?    # false
0.object.null?        # false
"hello".object.null?  # false
```

<a id="defined"></a>
### 1.4 `defined?`

```
vibecode: {
	"section": "defined",
	"returns": "strict_boolean",
	"role": "predicate for testing whether a value is non-null (true or false)"
}
```

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

<a id="identity-guarantees"></a>
## 2 Identity Guarantees

```
vibecode: {
	"section": "identity_guarantees",
	"role": "states that all four .object methods are read-only and engine-controlled; user code cannot override them"
}
```

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
## 3 Why `.object`

```
vibecode: {
	"section": "why_dot_object",
	"role": "explains the design choice to namespace these methods under .object rather than directly on every value"
}
```

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
## 4 Naming Conventions

A small set of method names carry agreed-upon meanings across the project.
These are **conventions**, not framework features — the runtime doesn't
enforce them and individual classes implement them however makes sense.
They exist so a reader sees the name and knows what it signals.

<a id="destroy"></a>
### 4.1 `destroy`

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
