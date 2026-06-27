# Structure

~~~vibecode
{"vibecode": {
	"doc": "object_structure_fields",
	"role": "spec for the bucket and stack fields on every object — bucket is a free-form data hash, stack is an ordered array of platters. Also covers the lazy shadow, the add vs ensure methods for adding class platters, warning-only platters, and the UUID-based nested-object mechanism that keeps the bucket namespace constraint-free.",
	"status": "active_design en route to settled spec",
	"audience": "Caspian implementers and security reviewers"
}}
~~~

Every object has two structural fields: `bucket` (the data) and `stack` (an ordered array of platters carrying class identity and other meta-information). This page describes each, plus the rules that govern the stack — most importantly that there are no reserved keys in any bucket, and the stack is the only source of truth for what the object is.

**The structure shown here is the serialized form** — what an object looks like as JSON, whether stored in a worldlet, written to a Mikobase record, or carried in a Puck protocol message. Caspian's in-memory representation has some differences (engine-internal references, cached dispatch tables, per-object identity slots, the actual sodium_malloc / vault pointers that back protected values, and so on). Those differences don't change the contract: the object round-trips to this JSON shape on every serialization boundary, and a JSON value in this shape rehydrates to a full Caspian object on every deserialization. Anywhere an object crosses a boundary, the shape below is what it looks like.

The minimum object — empty bucket, no platters:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": []
}
```

In practice either field may be absent — for example, when importing from a plain JSON hash that doesn't carry them. Absence is equivalent to the default empty form. The template above is the **full** structure; what actually ships in JSON can omit any field that's at its default.

A small worked example — a color object — looks like this:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {
        "hex": "#ac1260"
    },
    "stack": [
        {"class": "https://puck.uno/color/"}
    ]
}
```

One field of data, one class platter. No shadow (nothing to put on one).

A composite object exercising every feature — a text object with a foreground color as a nested object, a runtime warning, and a singleton `shout()` method (which forced the shadow to exist):

<a class="copy" href="#">copy</a>

```json
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
        {"class": "https://foo.bar/gup/"},
        {"warning": "color contrast below WCAG AA"},
        {"nested": "9c440335-a5fa-406a-8676-1da39a1a4617",
         "class": "https://puck.uno/color/"}
    ]
}
```

The sections below cover each piece.

## Bucket

~~~vibecode
{"vibecode": {
	"section": "bucket",
	"role": "describes the bucket field — a hash that holds the object's data; no reserved keys, no namespace rules, no patterns the engine claims"
}}
~~~

`bucket` is a hash. You can put anything in it that a hash can hold.

**There are no namespace rules inside `bucket`** — no reserved keys, no reserved key patterns, nothing the runtime claims. Every key in a bucket belongs to the class designer. This is a load-bearing guarantee: the rest of the structure is designed to avoid leaning on any specific bucket key.


## Stack

~~~vibecode
{"vibecode": {
	"section": "stack",
	"role": "describes the stack field — an ordered array of platters, each carrying class identity, a shadow flag, a nested-object link, a warning, a private bucket, or a vibecode block (any subset)"
}}
~~~

`stack` is an **ordered array**. Each element is a **platter** — a hash holding some subset of the engine-recognized fields below. The platter at index 0 is the top; method dispatch walks from top to bottom.

A platter can carry any of:

- **`class`** — the class this platter contributes to the object's identity.
- **`shadow: true`** — flags this platter as the object's shadow (zero or one platter per stack carries this).
- **`nested: <UUID>`** — links this platter to a nested object whose data sits at the matching UUID-keyed entry somewhere in the bucket.
- **`warning`** — a warning object attached to this platter, observational, never raises.
- **`bucket`** — a private per-platter hash for classes that need state separate from the host object's bucket.
- **`vibecode`** — an AI-readable annotation block.

A platter can also carry additional fields a specific class uses for its own purposes; the six above are the ones the engine itself recognizes. Order in the platter object is irrelevant — these are just keys on a hash.

### class

The class this platter contributes to the object's identity. Method dispatch consults `class`; see [method-resolution.md](method-resolution.md).

In Caspian, `class` is a reference to an **actual class object** — a runtime instance with its own methods, fields, identity. The forms shown here are what that class object looks like when serialized to JSON:

- **A URL string** (`"https://puck.uno/color/"`) — the named class identified by that URL. The serializer writes the URL; the deserializer looks the class up from wherever it lives (a Mikobase record, the engine's built-in registry, etc.).
- **An inline hash** (`{...}`) — the class object's definition serialized into the platter. Used when the class doesn't have a URL that can be referenced from elsewhere — most commonly the shadow class, which is unique per object and never registered under a URL. An empty inline class (`{}`) is still a real class object; it just has no methods yet.
- **Absent** — for platters whose role is something other than carrying class identity (warning-only platters, nested-link platters that point at another object's data, etc.). Dispatch skips platters that have no class.

**The shadow platter doesn't hold an empty hash at runtime — it holds an actual class object** that serializes as `{}` until someone adds methods to it. Singleton methods added to the shadow (the canonical way to give one specific object behavior that no other object has) get added to that class object directly; the next time the platter serializes, the `{}` expands to a hash describing the methods.

### shadow

A platter carrying `shadow: true` is the object's shadow — the home for singleton methods defined on this one specific object. **The shadow is optional.** A stack with no shadow platter is fully legal and is the common case; most objects never need singleton methods.

**The shadow is lazy.** It comes into existence only when code defines a singleton method on the object — `method $foo.name(params) ... end`. At that moment, if no shadow platter exists, the engine creates one and inserts it at the top of the stack (position 0). Once it exists, it stays at the top: subsequent platter additions place themselves at position 1, below the shadow.

The shadow's class is always an inline anonymous class (`class: {}`), populated with whatever singleton methods get attached to it. It is never a URL-referenced class.

**At most one platter in the stack carries `shadow: true`.** Two shadows would be ambiguous; the engine treats that as malformed data.

### nested

A platter carrying `nested: <UUID>` declares that the object has a nested object whose data sits at the matching UUID-keyed entry somewhere in the bucket. The platter's `class` field carries the nested object's class; its presence here is what causes the engine to interpret the matching UUID-keyed bucket entry as a nested object rather than as ordinary bucket data.

This mechanism keeps the bucket's no-reserved-keys guarantee intact: the bucket itself never has to declare "this entry is a nested object" via a reserved key like `class` or `stack`. The declaration always lives in the stack; the bucket carries only the data and the UUID marker.

See [Nested objects](#nested-objects) below for the full mechanism.

### warning

Carries a warning object attached to this platter. Any code — engine, framework, or application — can attach a warning to an object when it detects a condition worth surfacing without interrupting execution. A canonical engine case is a stored value whose class disagrees with its declared schema at deserialization time, but application code uses the same mechanism: "this user record looks suspicious," "this date value was parsed leniently and may not be what the source intended," anything that's worth noting alongside the value but not worth raising.

Letting warnings ride on the object itself means they travel with the data: a value loaded from a database, passed through several scopes, and inspected hours later still carries any warning attached when the condition was first noticed. Observational rather than control-flow; the warning never raises, it just sits there for code that cares to look.

The contents of the `warning` field are themselves an object — typically of a class under `puck.uno/warning/...` — describing the condition.

**A warning-only platter is fine.** A platter that carries just `warning` (no `class`, no `nested`, no `shadow`) is a pure annotation. Dispatch walks past it (no class → no methods to find); it sits in the stack until something inspects it.

### bucket

A platter can have its own private bucket — a hash for state that belongs to this platter's class, separate from the object's shared `bucket` at the top level.

The shared object bucket holds data that's "what this object is." The platter bucket holds data that's "what this class needs to remember about its participation in this object." For most platters the distinction doesn't matter — the platter is just contributing methods to a host object, and any data lives on the shared bucket. For classes that get **added to many different host objects with their own unrelated data** the distinction matters a lot: such a class can't safely store state on the host's bucket because key names would collide with whatever the host is doing. Its own platter bucket gives it a private namespace.

Trivet (a tree-node class that can be attached to almost any object) is the canonical example. Inside Trivet's methods, code stores tree-state in the platter bucket via `%platter`:

~~~caspian
%platter['parent']   = $other_node
%platter['children'] = $children_array
%platter['id']       = 'food'
~~~

`%platter` is the in-method accessor for the currently-dispatching platter's bucket; `%bucket` continues to be the in-method accessor for the object's shared top-level bucket. `@foo` remains shorthand for `%bucket['foo']` (the shared bucket); there is no `@`-style shorthand for the platter bucket — `%platter[...]` is always explicit. Method dispatch tracks "which platter am I running under" automatically, so `%platter` resolves without ambiguity.

The same invariants apply as the object-level bucket: when present, it must be a hash (never a scalar, array, or null); empty `{}` is fine; no reserved keys inside. Most platters do NOT have a per-platter bucket — the field is absent. Only classes that need to carry per-platter state separate from the host's data use it.

Serialized form:

~~~json
{
    "bucket": {},
    "stack": [
        {"class": "puck.uno/trivet/node",
         "bucket": {"parent": "…", "children": "…", "id": "food"}}
    ]
}
~~~

### vibecode

A platter can carry its own `vibecode` block — an AI-readable hash of hints, context, or annotations about the platter. Use cases: an AI that generated the object recording what it was doing, why this platter is here, what assumptions it made, where it pulled data from. Anything an AI (or human auditing the trail later) might want to know about this platter that isn't load-bearing data.

```json
{
    "bucket": {},
    "stack": [
        {"class": "foo.com/something",
         "vibecode": {
             "generated_by": "weather-advisor agent",
             "source": "synthesized from NWS forecast 2026-06-02T18:30:45Z",
             "confidence": 0.85,
             "notes": "free-form notes the generator wanted to leave"
         }}
    ]
}
```

**Any platter can carry it.** A `vibecode` field on an existing platter (one already there for its class) is fine — the AI-info just rides alongside the platter's normal role.

**A standalone vibecode-only platter is also fine.** Add a platter whose only purpose is to carry vibecode — useful when the generating AI wants to attach metadata without affecting the object's class identity. Such a platter has no `class` (or an empty inline `{}`), carries `vibecode: {...}`, and nothing else. Its presence in the stack contributes nothing to method dispatch; it's pure annotation.

The contents of `vibecode` are free-form. The engine doesn't enforce a schema. Conventions for what to put in are situation-specific — see [worldlets/index.md](../worldlets/) and [puckai/bootstrap/](../puckai/bootstrap/) for examples of how vibecode is used in those contexts.

This is the same `vibecode` convention used at the top of markdown documents, at the top of worldlet JSON files, and on individual records: a structured AI-readable annotation that travels with whatever it sits on.

## Adding classes to the stack

~~~vibecode
{"vibecode": {
	"section": "adding_classes",
	"role": "describes the two methods for adding class platters to the stack — add (always creates a new platter) and ensure (creates only if the class isn't already present)"
}}
~~~

Developer code adds classes to the stack via two methods. **The operation is conceptually "add a class"; the engine wraps the class in a new platter automatically.

- **`$foo.object.classes.add $class`** — always creates a new platter, attaches the class to it, and inserts it at the top of the stack. If a shadow platter exists, the new platter goes at position 1 instead (shadow stays on top). Multiple platters can carry the same class via repeated `.add` calls.

- **`$foo.object.classes.ensure $class`** — same insertion behavior, but no-op if the stack already has a platter whose class matches. Idempotent. **`ensure` is the recommended way to add class platters** — most code wants "make sure this class is on the stack," not "add another copy regardless."

The placement-below-shadow rule preserves the shadow's override-everything-else semantics: singleton methods on the shadow always intercept dispatch before any other class.

## Inspecting classes

~~~vibecode
{"vibecode": {
	"section": "inspecting_classes",
	"role": "describes $foo.object.classes — a fresh per-call snapshot of the classes in the stack, with add and ensure attached as launch-pad methods for mutating the stack"
}}
~~~

`$foo.object.classes` returns an array of the classes present in the object's stack, in stack order (top to bottom). The shadow's class is included if a shadow exists.

- The array is **freshly built on every call**. Two successive calls produce independent arrays.
- The array is **not mutable as an array** — pushing or splicing it does nothing to the source object. The stack is the source of truth.
- The array carries **`.add`** and **`.ensure`** as methods that operate on the source object's stack (not on the array). The array is also the convenient launch pad for those operations.
- A reference held to a previous result is a snapshot of that moment, not a live view of the stack.

Typical pattern:

~~~caspian
$foo.object.classes              # array of classes, top to bottom
$foo.object.classes.ensure 'puck.uno/trivet/node'    # idempotent add via the snapshot
~~~

For the full per-platter view (including `warning`, per-platter `bucket`, per-platter `vibecode`, the `shadow` and `nested` flags), use `$foo.object.stack` — it returns the underlying stack array verbatim.

## Nested objects

~~~vibecode
{"vibecode": {
	"section": "nested_objects",
	"role": "describes the UUID-marker mechanism for nested objects — keeps the bucket free of reserved keys while letting an object carry sub-objects with their own classes"
}}
~~~

A nested object's data sits **inside the parent's bucket**; its class identity lives in **the parent's stack** as a `nested` platter. The two pieces are linked by a UUID.

The mechanism:

1. The nested object's data is a hash inside the parent's bucket — at any depth.
2. That hash carries a **UUID-formatted key** as a marker. The value associated with the marker key is unconstrained; convention is `true`, but the engine doesn't care.
3. The parent's stack carries one or more platters with `nested: "<UUID>"`. Each such platter pairs the marker with class metadata for the nested object.

The engine recognizes a nested object **because the stack lists it**, not because the bucket key looks like a UUID. A developer is free to put UUID-formatted keys in a bucket for their own reasons — only UUIDs the stack nominates are interpreted as nested-object markers.

Example — a text object with a foreground color:

```json
{
    "bucket": {
        "content": "Hello",
        "foreground": {
            "9c440335-a5fa-406a-8676-1da39a1a4617": true,
            "hex": "#aabbcc"
        }
    },
    "stack": [
        {"class": "https://foo.bar/gup/"},
        {"nested": "9c440335-a5fa-406a-8676-1da39a1a4617",
         "class": "https://puck.uno/color/"}
    ]
}
```

The `foreground` hash in the bucket carries two kinds of keys: the UUID marker (`9c440335-...`) and ordinary data (`hex`). The matching `nested:` platter in the stack carries the color class. Together they say: "the foreground hash is also a color object."

**Why the indirection.** Inline embedding (`"foreground": {"bucket": ..., "stack": ...}`) would force the engine to reserve `bucket` and `stack` as bucket-key names — breaking the no-reserved-keys guarantee. The UUID marker is the only way to flag a nested object without reserving any spelling in the bucket. The 128-bit UUID space is large enough that accidental collision with a developer's chosen field name is not a concern.

**Multiple nested objects.** Each nested object gets its own UUID and its own `nested:` platter in the stack. Nested objects can themselves carry nested objects, recursively — the same mechanism applies at every level.

**Reaching nested platter fields.** A `nested:` platter is otherwise a regular platter — it can carry `bucket`, `warning`, `vibecode` (each scoped to the nested object's role in the parent), in addition to `class`. The shadow flag is the one exception: a nested platter can't be the shadow, since the shadow belongs to the parent object's identity.
