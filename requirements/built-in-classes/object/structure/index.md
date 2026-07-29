# Object structure
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_object_structure",
	"role": "spec for how every Caspian value is structured at the object level — bucket (data hash), stack (ordered array of platters carrying class identity and other per-slot metadata), shadow (per-instance class for singleton methods), nested objects (UUID-linked sub-objects sitting inside the parent's bucket), and the primitive field (optional engine-managed slot holding a JSON primitive — string, number, boolean, null, array, hash — set at construction and immutable; determines the object's truthiness: primitive false or null → falsy, anything else or no primitive field → truthy). Also spec's the serialized JSON form the object round-trips to at every persistence or protocol boundary.",
	"status": "draft — structural fields, platter types, shadow lazy-creation, nested-UUID mechanism, primitive-field truthiness derivation, and JSON serialization form all spec'd; a few narrower rules (borrow, warning platter conventions, freeze axes) still to grow their own methods pages under object/methods/",
	"audience": "developers writing Caspian; engine implementers building the object runtime; class authors reasoning about what data structures they're working with; anyone reading serialized worldlet / Mikobase / Puck-protocol payloads and needing to know the shape"
}}
~~~

Every Caspian value has the same underlying shape. This page describes the fields the engine recognizes on every object, the rules that govern them, and the serialized JSON form the object takes when it crosses a persistence or protocol boundary.

## What every object has

Every value is composed of these parts:

- **bucket** — a hash holding the object's data. Free-form; no reserved keys.
- **stack** — an ordered array of platters carrying class identity and per-platter metadata. Some platters have special purposes (the shadow, nested-object markers); see [Stack](#stack) below for the full list.
- **[primitive field](#primitive-field)** (optional) — an internal, engine-managed slot holding a JSON primitive value (string, number, boolean, null, array, hash). Set at construction and immutable. Not exposed at the Caspian level; engine-level methods reach it directly. Its presence and value determine the object's truthiness — see [§ Truthiness](#truthiness).

The bucket and stack are visible at the Caspian level via the `object` namespace (`$foo.object.bucket`, `$foo.object.stack`). Truthiness is exposed via `$foo.object.truthy?`. The primitive field is deliberately not directly inspectable — it's how the engine represents primitives, not something Caspian code manipulates directly.

## Serialized form

**The structure shown throughout this doc is the serialized form** — what an object looks like as JSON, whether stored in a [worldlet](https://puck.uno/requirements/mikobase/worldlets), written to a Mikobase record, or carried in a Puck-protocol message. <!-- outbound-link-allowed --> Caspian's in-memory representation has some differences (engine-internal references, per-object identity slots, the actual sodium_malloc / vault pointers backing protected values). Those differences don't change the contract: the object round-trips to this JSON shape on every serialization boundary, and a JSON value in this shape rehydrates to a full Caspian object on every deserialization.

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

The bucket holds the object's data — the state that describes what this object *is*. Class methods read and write it via `@field` or `%bucket['field']`. Downloaded methods applied via `$foo.$method` also reach the bucket, subject to the receiver-ownership rule ([classes/downloaded-methods § The receiver-ownership rule](https://puck.uno/requirements/classes/downloaded-methods#the-receiver-ownership-rule)).

**The bucket never contains the primitive value.** For String, Number, and other Primitive subclasses, the raw representation lives in the engine's internal slot alongside the bucket, not inside it. The bucket is empty by default; the one metadata slot the primitive surface treats as spec'd is a Null's `@flavor`, and beyond that anything sitting in a primitive's bucket got there because user-level code (a class method, a downloaded method, or a direct `@field =` assignment) wrote it. See [primitive-buckets](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets) for the full model.

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

## Primitive field

<span class="tag">primitive-field</span>

Some objects additionally carry a **primitive field** — an internal, engine-managed slot holding a JSON primitive value. The value is set at construction and is immutable thereafter. Not exposed at the Caspian level; engine-level methods reach it directly.

The primitive field can hold any JSON primitive:

- **String** — the raw UTF-8 bytes.
- **Number** — the raw integer or fractional bits.
- **Array** — the underlying element sequence.
- **Hash** — the key/value table.
- **True** — the boolean `true`.
- **False** — the boolean `false`.
- **Null** — the JSON `null`.

Objects that don't wrap a JSON primitive (user classes without a primitive-carrying ancestor) have no primitive field at all — the slot is simply absent.

The field lives alongside the bucket, not inside it. Engine methods (Lua-implemented) reach the field directly through the internal representation and bypass the bucket entirely. Caspian methods reach the value through `%self` — the engine unwraps `%self` to the raw representation at the point of arithmetic, string operations, or indexing.

**The field is invisible at the Caspian level.** There is no `.value` or `.raw` method that returns it as inspectable data. This is a load-bearing invariant: the primitive value can only be read via operations on `%self` (arithmetic, comparisons, string methods, etc.), never as a bare hash-shaped inspection. This closes the recursion where a primitive's own value would otherwise have to be a Caspian object with its own bucket and its own primitive field forever ([primitive-buckets § How this resolves the turtles problem](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets#how-this-resolves-the-turtles-problem)).

**Set at instantiation, immutable.** The value is written once by the constructor and never changes. Every string-modifying operation, arithmetic operation, or hash mutation on a primitive returns a **new** instance — the original's primitive field stays whatever it was.

**No interning.** Every primitive literal in source materializes a fresh instance — every `5`, every `'hello'`, every `null`. Two `5`s in source compare `==` (same value in the field) but are distinct objects with distinct buckets. See [primitive-buckets § No interning](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets#no-interning-every-primitive-literal-is-a-fresh-instance) for the full rule.

### Truthiness

**Truthiness is derived from the primitive field.** The engine reads the field on every truthiness check:

- If the primitive field is `false` → the object is **falsy**.
- If the primitive field is `null` → the object is **falsy**.
- Anything else (including any other primitive value — `0`, `''`, `[]`, `{}`, `true`, or a user-defined value) → the object is **truthy**.
- If the object has **no primitive field at all** → the object is **truthy**.

Consequence: a class inheriting from `False` has instances whose primitive field is `false` (because `False`'s constructor sets it), so those instances are falsy. Same for subclasses of `Null`. User classes with no primitive-bearing ancestor have no primitive field and are truthy. The rule falls out of the class inheritance chain without needing a separate mechanism.

The check is against the JSON-level value, not against a Caspian object wrapper. The engine reads the raw primitive and does a native `is-false-or-null` comparison — no method dispatch, no method-not-found risk, no way for user code to intercept.

The Caspian-level surface is [`$foo.object.truthy?`](../methods/#truthy), which reads the primitive field and returns the resulting boolean. See the [truthy/falsy syntax rule](https://puck.uno/requirements/syntax/truthy-and-falsy) for how truthiness is consumed by `if`, `while`, `and`/`or`, and other truth-consuming constructs.

## Testing

### Bucket

- **Fresh object has an empty bucket** — a bare object has `%bucket` equal to `{}`.
- **No reserved keys** — writing every key spelling — including `class`, `stack`, `bucket`, `shadow`, `nested`, `warning`, `vibecode`, and UUID-formatted strings — into the top-level bucket via `%bucket[$key] = $value` succeeds and reads back the same value.
- **`@field` reads the bucket** — `$w.@name` returns whatever `%bucket['name']` holds.
- **`@field = value` writes the bucket** — after `$w.@name = 'x'`, `%bucket['name']` is `'x'`.
- **`%bucket['key']` is equivalent to `@key`** — both spellings resolve to the same slot.
- **Missing bucket key reads as null** — `$w.@undefined_key` returns null (or however the read primitive spec's it), never raises.

### Stack

- **Fresh object's stack contains just its class** — a `Widget.new()` produces an object whose stack has exactly one platter carrying the Widget class.
- **Bare object's stack contains just Object** — a `%('puck.uno/object').new()` has exactly one platter carrying Object.
- **Platter without `class` is skipped by dispatch** — a stack with a warning-only platter followed by a class platter still resolves methods against the class platter.
- **`class` field is a class object, not a string** — inspecting a platter's `class` value returns something for which class-object operations work; string identifiers are rejected at load.
- **Dispatch walks top-to-bottom** — a method defined on the platter at index 0 wins over the same method defined at index 1.

### Shadow

- **New object has no shadow** — a fresh object's stack has no platter with `shadow: true`.
- **Defining a singleton method creates the shadow** — after `method $w.greet() ... end`, the stack has exactly one shadow platter.
- **Shadow appears at position 0 by convention** — the shadow platter created by a singleton method definition sits at the top of the stack.
- **Only one shadow per stack** — attempting to load an object whose serialized stack has two `shadow: true` platters raises as malformed.
- **Shadow methods win** — a method defined on the shadow wins over the same method name on the base class.
- **Shadow can be created explicitly via `ensure: true`** — `$w.object.classes.shadow(ensure: true)` creates the shadow platter without adding any singleton methods.

### Nested objects

- **Nested platter with UUID marks a bucket entry** — a stack with `{nested: 'UUID', class: Color}` combined with a bucket hash containing the UUID key marks that hash as a Color object.
- **UUID key in bucket without matching nested platter is plain data** — a bucket hash containing a UUID-formatted key that no `nested:` platter nominates is treated as ordinary data, not as a nested-object marker.
- **Nested object at any bucket depth is recognized** — a UUID marker inside a value nested inside a value inside the bucket is still matched to the corresponding `nested:` platter.
- **Multiple nested objects with distinct UUIDs coexist** — two `nested:` platters with different UUIDs each match their own bucket hash and each carry their own class.
- **Nested objects can themselves carry nested objects** — recursion through nested objects works to arbitrary depth.
- **Nested platter can carry `bucket`, `warning`, `vibecode`** — those fields on a nested platter round-trip through serialization.
- **Nested platter cannot be the shadow** — a platter carrying both `nested: ...` and `shadow: true` is malformed and raises on load.

### Per-platter bucket

- **Per-platter bucket is separate from the object's bucket** — writing to `%platter['key']` from a method running under a platter does not affect `%bucket['key']`.
- **`%platter` resolves to the currently dispatching platter** — inside a method, `%platter` is the platter that supplied the method, not any other.
- **`@field` continues to reach the object bucket** — `@field` inside a method still means `%bucket['field']`, not `%platter['field']`.
- **No `@`-shorthand for per-platter bucket** — `%platter['key']` is the only spelling; there is no per-platter `@` sigil.
- **Per-platter bucket must be a hash when present** — an array or scalar in the `bucket` field of a platter raises on load.
- **Missing per-platter bucket is fine** — most platters have no `bucket` field.

### Per-platter vibecode

- **Any platter can carry `vibecode`** — a class platter with a `vibecode` block round-trips through serialization.
- **Standalone vibecode-only platter is legal** — a platter with only `vibecode` (no `class`) round-trips and does not affect dispatch.
- **Vibecode-only platter is skipped by dispatch** — a stack whose first platter is vibecode-only still resolves methods against the next platter down.
- **Vibecode contents are free-form** — arbitrary JSON-serializable values inside a `vibecode` block are preserved without validation.

### Warning platter

- **Warning-only platter is legal** — a stack with a platter carrying only `warning: <obj>` (no `class`) round-trips.
- **Warning-only platter is skipped by dispatch** — method resolution walks past a warning-only platter to the next class-carrying platter.
- **Warning travels with the object** — after serializing and deserializing an object with a warning, the warning is still on the stack.

### Truthiness

- **True instance is truthy** — `true.object.truthy?` is `true` (primitive field is `true`).
- **False instance is falsy** — `false.object.truthy?` is `false` (primitive field is `false`).
- **Null instance is falsy** — `null.object.truthy?` is `false` (primitive field is `null`).
- **String instance is truthy** — including the empty string (primitive field is a UTF-8 byte sequence, neither `false` nor `null`).
- **Number instance is truthy** — including 0 (primitive field is a number, neither `false` nor `null`).
- **Array instance is truthy** — including the empty array (primitive field is an element sequence).
- **Hash instance is truthy** — including the empty hash (primitive field is a key/value table).
- **User class instance is truthy** — a fresh instance of a user-defined class has no primitive field and is therefore truthy.
- **Subclass of Null inherits falsy** — a class extending Null inherits Null's constructor path, which sets the primitive field to `null`; instances read as falsy.
- **Subclass of False inherits falsy** — same mechanism; primitive field is `false`.
- **Primitive field is immutable** — no bucket write, class-add, or method call changes an existing instance's primitive field, so truthiness is stable for the object's lifetime.
- **`if`, `while`, `and`, `or` consult the primitive field** — a subclass of Null in `if $inst` skips the consequent because the engine reads the primitive field and sees `null`.

### Primitive value slot

- **Slot is not exposed** — there is no `.value`, `.raw`, or `%slot` accessor at the Caspian level that returns a primitive's underlying representation as a bare inspectable value.
- **Slot is engine-managed** — the value survives serialization and rehydration without any user-level access.
- **Number arithmetic reaches the slot** — `5 + 3` returns 8 without user code touching a value slot.
- **String operations reach the slot** — string comparisons and slicing work without exposing the underlying bytes.
- **Primitive's bucket is not the slot** — the bucket on a primitive can be independently written and read without affecting the primitive's value; e.g., writing `@custom = 'x'` on the number 5 does not change what `5 + 1` produces.

### No interning

- **Two number literals with the same value are distinct instances** — writing a bucket key on one does not appear on the other.
- **Two string literals with the same value are distinct instances** — same test with strings.
- **Two null literals with the same value are distinct instances** — same test with nulls.
- **Two boolean literals with the same value ARE the same shared instance** — `true` refs share identity, as spec'd on the boolean page.
- **Equality (`==`) still holds across independent primitive instances** — `5 == 5`, `'x' == 'x'`, `null == null` all return `true` despite distinct identities.

### Serialization

- **Empty bucket is optional in JSON** — an object serialized with no bucket field rehydrates identically to one with `bucket: {}`.
- **Empty stack is optional in JSON** — same for `stack: []`.
- **Round-trip preserves shape** — serializing and deserializing an arbitrary object produces the same structure (bucket, stack, per-platter fields, nested-object markers, warnings, vibecode).
- **Class is embedded inline as a class object** — the serialized platter's `class` field is a full class-object hash, not a URL or lookup key.
- **Reserved-field rule survives round-trip** — writing arbitrary UUIDs and reserved-looking key names into a bucket, serializing, and deserializing preserves them exactly.
- **Warnings survive round-trip** — a warning-carrying platter comes out with the same warning after serialize-then-deserialize.
- **Nested objects survive round-trip** — the UUID marker and matching `nested:` platter remain paired after serialize-then-deserialize.
- **Vibecode blocks survive round-trip** — vibecode contents come through unchanged.

## Related

- [Object](../) — the parent Object class doc.
- [Object methods](../methods/) — the `object` method namespace, which is how the structure spec'd here is inspected at the Caspian level.
- [classes/nested](https://puck.uno/requirements/classes/nested) — the nested-method-namespace mechanism `object` uses.
- [classes/downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods) — how downloaded methods reach a receiver's bucket, subject to the receiver-ownership rule.
