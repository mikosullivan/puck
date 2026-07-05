# Idea: how primitives have buckets

~~~vibecode
{"vibecode": {
	"doc": "primitive_buckets",
	"role": "brainstorm — how the seven primitive kinds (String, Number, Hash, Array, True, False, Null) carry buckets the way every other Caspian object does, and the related truthiness model. The core design is settled: primitives are subclasses of a Primitive base class; the primitive VALUE lives in an internal (Lua-side) slot alongside the bucket rather than in it; the bucket is available for optional metadata (null flavor, faucet provenance, downloaded-method-set fields) but does NOT contain the primitive's own value; there is NO interning — every literal in source materializes a fresh instance (including true, false, and null, which are not singletons); and every object carries an immutable truthiness bit set at construction (only False and Null construct with truthy=false; everything else is truthy). This resolves puck#946 (the turtles-all-the-way-down concern) and locks truthiness immutably. Remaining sub-questions: arithmetic bucket-inheritance and how mutability interacts with immutability.",
	"status": "brainstorm — core design settled (class hierarchy, value slot, bucket usage, no interning, truthiness); implementation details of arithmetic inheritance and mutability still to work out",
	"references": ["https://github.com/mikosullivan/puck/issues/946", "https://puck.uno/documentation/requirements/caspian/classes/downloaded-methods", "https://puck.uno/documentation/requirements/caspian/built-in-classes/null", "https://puck.uno/documentation/requirements/caspian/built-in-classes/number/", "https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy"]
}}
~~~

Every value in Caspian is an object with a bucket — including the seven primitive kinds. This doc covers how that works without the "turtles all the way down" recursion (the primitive's value can't itself decompose into more values-with-buckets forever) and what the resulting model implies for sharing, arithmetic, and mutability.

## Settled: class hierarchy and value-location model

Primitives are subclasses of a base `Primitive` class:

- `Primitive` (abstract base)
  - `String`
  - `Number` (with further subclasses `Decimal`, `Binary`, `Octal`, `Hex` — same numeric value, different `.to_string`)
  - `Hash`
  - `Array`
  - `True`
  - `False`
  - `Null`

The primitive's **own value** lives in a Lua-native slot on the object, NOT in the bucket. For a number, that slot holds the raw integer/float; for a string, the raw UTF-8 bytes; for an array, the underlying element sequence; for `True`/`False`/`Null`, a fixed tag; for a hash, the key/value table.

**Engine methods (Lua-implemented) reach the value directly** through the Lua-side slot. Arithmetic, string ops, array indexing, hash lookup — all bypass the bucket and work on the raw representation.

**Caspian-defined methods (including downloaded methods) reach the value through `%self`.** `%self` refers to the whole primitive object; when arithmetic is performed on it, the engine unwraps `%self` to its Lua-side value automatically. `@field` still reads and writes the bucket, unchanged from any other object.

## What "the bucket has nothing in it" means

The primitive's OWN VALUE isn't stored in the bucket. The bucket is still there and still usable for **optional metadata**:

- **Null flavors** — `@flavor = :not_found`, `@flavor = :not_set`, `@flavor = :pending`. Lives in the bucket of a Null instance.
- **Faucet provenance** — `@from_faucet = 'stdin'`. Attached by the faucet when the value first enters the runtime; travels with the value.
- **Downloaded-method-set fields** — `$str.$attach_metadata` running `@debug_id = 42` writes to the bucket normally.
- **Number-subclass tag** — NOT in the bucket. The subclass distinction is a class-level fact (`Hex` is a subclass of `Number`), not a bucket field. Left-operand-wins arithmetic determines the result's class without touching the bucket.

**By default, a primitive's bucket is empty.** Nothing populates it automatically; the value itself is elsewhere, and metadata only lands there when something explicitly writes it.

## How this resolves the turtles problem

The problem: if every value has a bucket, and the bucket contains values, and those values themselves have buckets, the recursion never bottoms out.

The resolution: the primitive value doesn't LIVE in the bucket. The bucket sits alongside the value, not around it. A number's bucket is empty (or has a few metadata fields); the number's actual numeric content is in a Lua-side slot. That slot is not itself a Caspian object; it's a raw C-level number as far as Lua sees it. No recursion because the value isn't a bucket-having object at that level.

This closes [puck#946](https://github.com/mikosullivan/puck/issues/946).

## No interning — every primitive literal is a fresh instance

Every time a primitive literal appears in source, the runtime materializes a **fresh instance** of the corresponding class. That applies uniformly:

- Every `5` in source is a distinct `Number` instance with its own bucket.
- Every `'hello'` is a distinct `String` instance with its own bucket.
- Every `true` is a distinct `True` instance; every `false` is a distinct `False` instance; every `null` is a distinct `Null` instance — none are singletons.
- Every `[1, 2, 3]` and `{a: 1}` literal is a distinct `Array` / `Hash` instance (as expected — these already worked this way in most languages).

Two mentions of the same literal compare `==` (they have the same primitive value) but they are NOT the same object. Identity comparison, if exposed, distinguishes them.

**What this gives us:**

- **No spooky action at a distance.** A downloaded method that writes `@debug_id = 42` on one `5` never affects a different `5` elsewhere in the program. Each primitive has its own private bucket that only its holders can touch.
- **Uniform model across all primitives.** Numbers, strings, arrays, hashes, and even the "singleton-looking" values (`true`, `false`, `null`) all follow the same per-instance rule. No special-case for constants.
- **Predictable metadata.** Faucet provenance, null flavors, and downloaded-method-set fields all attach to specific instances without leaking across other primitives with the same value.

**Trade-off:** every literal in source allocates a fresh object. Memory pressure is higher than in languages that intern their nulls and small integers. The runtime can still choose to represent bare (empty-bucket) primitives compactly at the engine level — that's an internal optimization, invisible at the Caspian level — but it can't collapse two literal mentions into a single shared object. The compact representation just has to be trivially-copyable so a downloaded method's bucket write always lands on a distinct instance.

## Truthiness — a bit at construction

Every object header carries a single truthiness bit, set by the constructor and never changed after that. The rule:

- `False`'s constructor sets `truthy = false`.
- `Null`'s constructor sets `truthy = false`.
- Every other constructor (String, Number, Hash, Array, True, and any user class) leaves `truthy = true`.
- Subclasses inherit the constructor path — a user-defined `Null_flavor_pending extends Null` gets `truthy = false` automatically.
- The bit is not user-writable. Nothing at the Caspian level can change an object's truthiness after construction.

Truthiness checks in `if`, `while`, `&&`, `||`, and any other truth-consuming construct resolve through this bit. The Caspian-level property is called **`truthy`** (positive framing — no negation) and is always a boolean value (`true` or `false`, never null and never any other type). The implementation representation is up to the engine — a single header bit is probably cheapest, but the property presents as a boolean at the language level.

**What this gives us:**

- **Immutable truthiness.** Set at construction, never changes. There's no method or bucket operation that can retroactively make `null` truthy or `true` falsy.
- **Cheap engine check.** One header lookup, no primitive-value inspection or class-hierarchy walk.
- **User classes can't accidentally become falsy.** Only `False`, `Null`, and their subclasses ever get `truthy = false`; anything else is truthy by construction.
- **Consistent with the number rule.** `0`, `-0`, `0.0` are all truthy — they're Numbers, and Number's constructor doesn't touch the truthiness bit.
- **Consistent with the empty-container rule.** `""`, `[]`, `{}` are all truthy — they're String/Array/Hash, none of whose constructors set falsy.

The name preference for `truthy` (positive, boolean-valued) over an internal negation like `falsy` is a language-level preference for readability: readers never have to mentally undo a double negative (`if not $x.falsy?`). Under the hood, the engine implementer picks whatever representation is cheapest — a bit, a boolean field, whatever — as long as the language-level property behaves as a boolean.

## Remaining sub-questions

### Arithmetic bucket-inheritance

`1 + 2 = 3`. What's `3`'s bucket?

The number subclass rule (left-operand-wins) is a CLASS-level fact, not a bucket field, so it's already handled: `Hex(0xff) + 1` returns a `Hex` regardless of the buckets involved.

For actual bucket fields (provenance, downloaded-method-set fields, null flavor — none of which apply to arithmetic results directly, but the general question does):

- **Empty by default.** The result gets a fresh empty bucket. Any metadata on the inputs is lost.
- **Inherit from left operand.** Result's bucket is a copy of the left operand's.
- **Merge from both.** Copies from both; needs conflict-resolution rules.

**Open question — provenance specifically.** If `1 + $network_number` returns a result with an empty bucket, the network provenance is silently stripped. That's a security concern. The likely resolution: **provenance-flavored bucket fields merge (any tainted input taints the result); other bucket fields empty-by-default.** Provenance would need to be identified as a special class of bucket field the runtime knows to preserve.

Not blocking the core model — arithmetic on plain numbers doesn't hit this — but needs a call before provenance lands.

### Bucket mutability on immutable primitives

Numbers, strings, booleans, and null are immutable (their VALUES can't change). But bucket writes look like mutation:

~~~caspian
$n = 5
$n.$attach do
	@debug_id = 42        # writes to the bucket
end
~~~

Two consistent readings:

- **Value-immutable, bucket-mutable.** The numeric value can't change (`5` is always `5`), but the bucket is a separate compartment that CAN be mutated. Callers who share a reference to a specific primitive object see each other's bucket writes.
- **Wholly immutable; bucket writes rebind.** `$n.$attach` produces a fresh 5-with-a-different-bucket and rebinds `$n` to it. Anyone else holding the original 5 sees the unchanged bucket.

The value-immutable/bucket-mutable reading is simpler and matches how the Lua-side implementation would work naturally. It also makes downloaded-method use cases cleaner ("attach a debug id to this specific 5" behaves as expected). Recommend that reading.

Under either reading, the value slot is untouchable — nothing can change what number a Number is or what characters a String has.

### User-defined subclasses of primitives

If a user defines `class # my_number extends number`, is that legal? What does an instance of `my_number` look like?

Probably legal, with the natural semantics: `my_number` inherits Number's Lua-side value slot and adds class methods and defaults for the bucket. Instances behave as numbers for arithmetic (unwrapping via `%self`) but have the extended surface for other method calls.

Concrete: a `Currency` class extending `Number` could give every currency amount a `.symbol` method (from the class) and store `@currency = 'USD'` in the bucket (per instance, or as a default). Arithmetic still works: `$10.dollars + $5.dollars = $15.dollars`, where the result's class follows left-operand-wins.

Not blocking; useful to have on the roadmap.

## Related

- [downloaded-methods](https://puck.uno/documentation/requirements/caspian/classes/downloaded-methods) — the spec that surfaced primitive-bucket access via `$n.$method`. This design cleanly supports that surface.
- [null](https://puck.uno/documentation/requirements/caspian/built-in-classes/null) — null flavors live in the bucket per this design.
- [number](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/) — Decimal/Binary/Octal/Hex are subclasses of Number; the subclass distinction is class-level, not a bucket field.
- [puck#946](https://github.com/mikosullivan/puck/issues/946) — the GitHub issue this brainstorm resolves.
