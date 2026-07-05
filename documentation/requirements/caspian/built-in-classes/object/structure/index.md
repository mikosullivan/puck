# Object structure
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_object_structure",
	"role": "spec for how every Caspian value is structured at the object level — bucket (data hash), stack (ordered array of platters carrying class identity and other per-slot metadata), shadow (per-instance class for singleton methods), nested objects (UUID-linked sub-objects sitting inside the parent's bucket), truthy bit (set at construction, immutable), and the primitive value slot (for the Primitive subclasses only). Also spec's the serialized JSON form the object round-trips to at every persistence or protocol boundary.",
	"status": "draft — structural fields, platter types, shadow lazy-creation, nested-UUID mechanism, truthy bit, and JSON serialization form all spec'd; a few narrower rules (borrow, warning platter conventions, freeze axes) still to grow their own methods pages under object/methods/",
	"audience": "developers writing Caspian; engine implementers building the object runtime; class authors reasoning about what data structures they're working with; anyone reading serialized worldlet / Mikobase / Puck-protocol payloads and needing to know the shape"
}}
~~~

Every Caspian value has the same underlying shape. This page describes the fields the engine recognizes on every object, the rules that govern them, and the serialized JSON form the object takes when it crosses a persistence or protocol boundary.

## What every object has

Every value is composed of these parts:

- **bucket** — a hash holding the object's data. Free-form; no reserved keys.
- **stack** — an ordered array of platters carrying class identity and per-platter metadata. Some platters have special purposes (the shadow, nested-object markers); see [Stack](#stack) below for the full list.
- **truthy bit** — a single boolean set at construction by the class's constructor. Immutable. Determines how the value evaluates in an `if`/`while` condition.
- **primitive value slot** (Primitive subclasses only) — an internal, engine-managed slot holding the raw representation of a primitive (the number's integer/float bits, the string's UTF-8 bytes, the array's element sequence, etc.). Not exposed at the Caspian level; engine-level methods reach it directly. See [primitive-buckets](https://puck.uno/documentation/ideas/primitive-buckets) for the design rationale. <!-- outbound-link-allowed -->

The bucket and stack are visible at the Caspian level via the `object` namespace (`$foo.object.bucket`, `$foo.object.stack`). The truthy bit is exposed via `$foo.object.truthy?`. The primitive value slot is deliberately not exposed — it's how the engine represents primitives, not something Caspian code manipulates directly.

## Serialized form

**The structure shown throughout this doc is the serialized form** — what an object looks like as JSON, whether stored in a [worldlet](https://puck.uno/documentation/requirements/mikobase/worldlets), written to a Mikobase record, or carried in a Puck-protocol message. <!-- outbound-link-allowed --> Caspian's in-memory representation has some differences (engine-internal references, cached dispatch tables, per-object identity slots, the actual sodium_malloc / vault pointers backing protected values). Those differences don't change the contract: the object round-trips to this JSON shape on every serialization boundary, and a JSON value in this shape rehydrates to a full Caspian object on every deserialization.

The minimum object — empty bucket, no platters:

~~~json
{
	"bucket": {},
	"stack": []
}
~~~

In practice either field may be absent — for example, when importing from a plain JSON hash that doesn't carry them. Absence is equivalent to the default empty form. The template above is the **full** structure; what actually ships in JSON can omit any field that's at its default.

### How class references are shown in these examples

In Caspian, the `class` field on a platter is always an **actual class object** — the class itself, embedded in the platter, never a string that names it and never a lookup key waiting to be resolved. Every class reference — the color class, the string class, the shadow class, everything — is a full class object serialized inline in the JSON.

To keep the examples readable without inlining a full class-object definition every time, they use an italic-gray placeholder like `color-class-object` in place of the embedded class. In a real serialized object each placeholder would be that class's own JSON serialization (an inline hash carrying methods, fields, and the class's own identity).

A small worked example — a color object — looks like this:

~~~json
{
	"bucket": {
		"hex": "#ac1260"
	},
	"stack": [
		{"class": color-class-object}
	]
}
~~~

One field of data, one class platter. No shadow (nothing to put on one).

A composite object exercising every feature — a text object with a foreground color as a nested object, a runtime warning, and a singleton `shout()` method (which forced the shadow to exist):

~~~json
{
	"bucket": {
		"content": "Hello",
		"foreground": {
			"9c440335-a5fa-406a-8676-1da39a1a4617": true,
			"hex": "#aabbcc"
		}
	},
	"stack": [
		{"shadow": true, "class": {}},
		{"class": text-class-object},
		{"warning": "color contrast below WCAG AA"},
		{"nested": "9c440335-a5fa-406a-8676-1da39a1a4617",
		 "class": color-class-object}
	]
}
~~~

The sections below cover each piece.

## Bucket

`bucket` is a hash. It can hold anything a hash can hold.

**There are no namespace rules inside the bucket** — no reserved keys, no reserved key patterns, nothing the runtime claims. Every key in a bucket belongs to the class designer. This is a load-bearing guarantee: the rest of the structure is designed to avoid leaning on any specific bucket key.

The bucket holds the object's data — the state that describes what this object *is*. Class methods read and write it via `@field` or `%bucket['field']`. Downloaded methods applied via `$foo.$method` also reach the bucket, subject to the receiver-ownership rule ([classes/downloaded-methods § The receiver-ownership rule](https://puck.uno/documentation/requirements/caspian/classes/downloaded-methods#the-receiver-ownership-rule)).

**The bucket never contains the primitive value.** For String, Number, and other Primitive subclasses, the raw representation lives in the engine's internal slot alongside the bucket, not inside it. The bucket is for optional metadata: null flavors, faucet provenance, and any downloaded-method-set fields. See [primitive-buckets](https://puck.uno/documentation/ideas/primitive-buckets) for the full model. <!-- outbound-link-allowed -->

## Stack

`stack` is an **ordered array**. Each element is a **platter** — a hash holding some subset of the engine-recognized fields below. The platter at index 0 is the top; method dispatch walks from top to bottom.

A platter can carry any of:

- **`class`** — the class this platter contributes to the object's identity.
- **`shadow: true`** — flags this platter as the object's shadow (zero or one platter per stack carries this).
- **`nested: <UUID>`** — links this platter to a nested object whose data sits at the matching UUID-keyed entry in the bucket.
- **`warning`** — a warning object attached to this platter; observational, never raises.
- **`bucket`** — a private per-platter hash for classes that need state separate from the host object's shared bucket.
- **`vibecode`** — an AI-readable annotation block.

A platter can also carry additional fields a specific class uses for its own purposes; the six above are the ones the engine itself recognizes. Order of fields within a platter is irrelevant — these are just keys on a hash.

### class

The class this platter contributes to the object's identity. Method dispatch consults `class`. In Caspian, **when present, `class` is always a class object** — a runtime instance with its own methods, fields, and identity. There is no other form: not a URL, not a string identifier, not an inline hash-of-fields waiting to be resolved into a class. If the platter carries `class`, that value is a full class object, serialized inline in the JSON.

The one time `class` is absent: platters whose purpose is something other than carrying class identity (warning-only platters, nested-link platters that point at another object's data, standalone vibecode platters). Dispatch skips platters that have no class.

(Other Puck systems — notably Mikobase — allow string identifiers or lookup references for a class field, resolved against a registry at read time. Caspian doesn't do that: the class either IS embedded in the platter, or the platter has no class. The tighter rule keeps runtime dispatch from ever having to fault-in a class definition to answer a method call.)

### shadow

A platter carrying `shadow: true` is the object's **shadow** — the home for singleton methods defined on this one specific object. The shadow is optional. A stack with no shadow platter is fully legal and is the common case; most objects never need singleton methods.

**The shadow is lazy.** It comes into existence only when code defines a singleton method on the object. At that moment, if no shadow platter exists, the engine creates one and inserts it at position 0 (the top of the stack).

**Convention: the shadow sits at position 0.** New class platters added via `.object.classes.ensure` (see [object/methods/](../methods/)) land at the bottom of the stack, leaving the shadow undisturbed at the top. That's the convention every well-behaved piece of code follows.

**The convention is not enforced.** User (or the object's owning role) can manually place the shadow anywhere in the stack — the engine doesn't (and practically can't) prevent it. Doing so is bad practice: dispatch walks top-to-bottom, so a shadow buried mid-stack loses its "override everything else" semantics for any platter above it. The rule is a spec-level convention, not a runtime guard. Code that moves the shadow deliberately owns the consequences.

The shadow's class is a per-instance class (`class: {}` when empty), populated with whatever singleton methods get attached to it — same class-object rule as everywhere else in the stack, just unique to this one object rather than shared with other instances.

**At most one platter in the stack carries `shadow: true`.** Two shadows would be ambiguous; the engine treats that as malformed data.

### nested

A platter carrying `nested: <UUID>` declares that the object has a nested object whose data sits at the matching UUID-keyed entry somewhere in the bucket. The platter's `class` field carries the nested object's class; its presence here is what causes the engine to interpret the matching UUID-keyed bucket entry as a nested object rather than as ordinary bucket data.

This mechanism keeps the bucket's no-reserved-keys guarantee intact: the bucket itself never has to declare "this entry is a nested object" via a reserved key like `class` or `stack`. The declaration always lives in the stack; the bucket carries only the data and the UUID marker.

See [Nested objects](#nested-objects) below for the full mechanism.

### warning

Carries a warning object attached to this platter. Any code — engine, framework, or application — can attach a warning to an object when it detects a condition worth surfacing without interrupting execution. A canonical engine case is a stored value whose class disagrees with its declared schema at deserialization time, but application code uses the same mechanism: "this user record looks suspicious," "this date value was parsed leniently and may not be what the source intended," anything worth noting alongside the value but not worth raising.

Letting warnings ride on the object itself means they travel with the data: a value loaded from a database, passed through several scopes, and inspected hours later still carries any warning attached when the condition was first noticed. Observational rather than control-flow; the warning never raises, it just sits there for code that cares to look.

The contents of the `warning` field are themselves an object — typically a Warning-class instance — describing the condition.

**A warning-only platter is fine.** A platter that carries just `warning` (no `class`, no `nested`, no `shadow`) is a pure annotation. Dispatch walks past it (no class → no methods to find); it sits in the stack until something inspects it.

### bucket (per-platter)

A platter can have its own private bucket — a hash for state that belongs to this platter's class, separate from the object's shared top-level bucket.

The shared object bucket holds data that's "what this object is." The platter bucket holds data that's "what this class needs to remember about its participation in this object." For most platters the distinction doesn't matter — the platter is just contributing methods to a host object, and any data lives on the shared bucket. For classes that get **added to many different host objects with their own unrelated data**, the distinction matters a lot: such a class can't safely store state on the host's bucket because key names would collide with whatever the host is doing. Its own platter bucket gives it a private namespace.

Inside methods running under this platter, `%platter` is the in-method accessor for the platter's own bucket; `%bucket` continues to be the accessor for the object's shared top-level bucket. `@foo` remains shorthand for `%bucket['foo']` (the shared bucket); there is no `@`-style shorthand for the platter bucket — `%platter['foo']` is always explicit. Method dispatch tracks which platter is currently dispatching automatically, so `%platter` resolves without ambiguity.

The same invariants apply as the object-level bucket: when present, the platter bucket must be a hash (never a scalar, array, or null); empty `{}` is fine; no reserved keys inside. Most platters do NOT have a per-platter bucket — the field is absent. Only classes that need to carry per-platter state separate from the host's data use it.

Serialized form:

~~~json
{
	"bucket": {},
	"stack": [
		{"class": tree-node-class-object,
		 "bucket": {"parent": "…", "children": "…", "id": "food"}}
	]
}
~~~

### vibecode (per-platter)

A platter can carry its own `vibecode` block — an AI-readable hash of hints, context, or annotations about the platter. Use cases: an AI that generated the object recording what it was doing, why this platter is here, what assumptions it made, where it pulled data from. Anything an AI (or a human auditing the trail later) might want to know about this platter that isn't load-bearing data.

~~~json
{
	"bucket": {},
	"stack": [
		{"class": some-class-object,
		 "vibecode": {
			"generated_by": "weather-advisor agent",
			"source": "synthesized from NWS forecast 2026-06-02T18:30:45Z",
			"confidence": 0.85,
			"notes": "free-form notes the generator wanted to leave"
		 }}
	]
}
~~~

**Any platter can carry it.** A `vibecode` field on an existing platter (one already there for its class) is fine — the AI-info rides alongside the platter's normal purpose.

**A standalone vibecode-only platter is also fine.** Add a platter whose only purpose is to carry vibecode — useful when the generating AI wants to attach metadata without affecting the object's class identity. Such a platter has no `class` (or an empty inline `{}`), carries `vibecode: {...}`, and nothing else. Its presence in the stack contributes nothing to method dispatch; it's pure annotation.

The contents of `vibecode` are free-form. The engine doesn't enforce a schema. Conventions for what to put in are situation-specific.

## Nested objects

A nested object's data sits **inside the parent's bucket**; its class identity lives in **the parent's stack** as a `nested` platter. The two pieces are linked by a UUID.

The mechanism:

1. The nested object's data is a hash inside the parent's bucket — at any depth.
2. That hash carries a **UUID-formatted key** as a marker. The value associated with the marker key is unconstrained; convention is `true`, but the engine doesn't care.
3. The parent's stack carries one or more platters with `nested: "<UUID>"`. Each such platter pairs the marker with class metadata for the nested object.

The engine recognizes a nested object **because the stack lists it**, not because the bucket key looks like a UUID. A developer is free to put UUID-formatted keys in a bucket for their own reasons — only UUIDs the stack nominates are interpreted as nested-object markers.

Example — a text object with a foreground color:

~~~json
{
	"bucket": {
		"content": "Hello",
		"foreground": {
			"9c440335-a5fa-406a-8676-1da39a1a4617": true,
			"hex": "#aabbcc"
		}
	},
	"stack": [
		{"class": text-class-object},
		{"nested": "9c440335-a5fa-406a-8676-1da39a1a4617",
		 "class": color-class-object}
	]
}
~~~

The `foreground` hash in the bucket carries two kinds of keys: the UUID marker (`9c440335-...`) and ordinary data (`hex`). The matching `nested:` platter in the stack carries the color class. Together they say: "the foreground hash is also a color object."

**Why the indirection.** Inline embedding (`"foreground": {"bucket": ..., "stack": ...}`) would force the engine to reserve `bucket` and `stack` as bucket-key names — breaking the no-reserved-keys guarantee. The UUID marker is the only way to flag a nested object without reserving any spelling in the bucket. The 128-bit UUID space is large enough that accidental collision with a developer's chosen field name is not a concern.

**Multiple nested objects.** Each nested object gets its own UUID and its own `nested:` platter in the stack. Nested objects can themselves carry nested objects, recursively — the same mechanism applies at every level.

**Reaching nested platter fields.** A `nested:` platter is otherwise a regular platter — it can carry `bucket`, `warning`, `vibecode` (each scoped to the nested object's purpose in the parent), in addition to `class`. The shadow flag is the one exception: a nested platter can't be the shadow, since the shadow belongs to the parent object's identity.

## Truthy bit

Every object header carries a single **truthy bit**, set by the constructor and never changed after that.

- `False`'s constructor sets `truthy = false`.
- `Null`'s constructor sets `truthy = false`.
- Every other constructor (String, Number, Hash, Array, True, and any user class) leaves `truthy = true`.
- Subclasses inherit the constructor path — a user-defined `Null_flavor_pending extends Null` gets `truthy = false` automatically.
- The bit is not user-writable. Nothing at the Caspian level can change an object's truthiness after construction.

Truthiness checks in `if`, `while`, `&&`, `||`, and every other truth-consuming construct resolve through this bit. The Caspian-level property is `$foo.object.truthy?`, always a boolean.

See [object/methods § truthy?](../methods/#truthy) and the [truthy/falsy syntax rule](https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy) for how the bit is used.

## Primitive value slot

Primitive subclasses — `String`, `Number` (with its Decimal/Binary/Octal/Hex subclasses), `Hash`, `Array`, `True`, `False`, `Null` — additionally carry an **internal value slot** holding the raw representation of the value.

- For a Number, the slot holds the raw integer or fractional bits.
- For a String, the raw UTF-8 bytes.
- For an Array, the underlying element sequence.
- For a Hash, the key/value table.
- For True, False, and Null, a fixed tag.

The slot lives alongside the bucket, not inside it. Engine methods (Lua-implemented) reach the slot directly through the internal representation and bypass the bucket entirely. Caspian methods reach the value through `%self` — the engine unwraps `%self` to the raw representation at the point of arithmetic, string operations, or indexing.

**The slot is invisible at the Caspian level.** There is no `.value` or `.raw` method that returns it as inspectable data. This is a load-bearing invariant: the primitive value can only be read via operations on `%self` (arithmetic, comparisons, string methods, etc.), never as a bare hash-shaped inspection. This closes the recursion where a primitive's own value would otherwise have to be a Caspian object with its own bucket and its own value slot forever ([primitive-buckets § How this resolves the turtles problem](https://puck.uno/documentation/ideas/primitive-buckets#how-this-resolves-the-turtles-problem)). <!-- outbound-link-allowed -->

**No interning.** Every primitive literal in source materializes a fresh instance — every `5`, every `'hello'`, every `null`. Two `5`s in source compare `==` (same value in the slot) but are distinct objects with distinct buckets. See [primitive-buckets § No interning](https://puck.uno/documentation/ideas/primitive-buckets#no-interning-every-primitive-literal-is-a-fresh-instance) for the full rule. <!-- outbound-link-allowed -->

## Related

- [Object](../) — the parent Object class doc.
- [Object methods](../methods/) — the `object` method namespace, which is how the structure spec'd here is inspected at the Caspian level.
- [classes/nested](https://puck.uno/documentation/requirements/caspian/classes/nested) — the nested-method-namespace mechanism `object` uses.
- [classes/downloaded-methods](https://puck.uno/documentation/requirements/caspian/classes/downloaded-methods) — how downloaded methods reach a receiver's bucket, subject to the receiver-ownership rule.
