# Structure

~~~json
{"vibecode": {
	"doc": "object_structure_fields",
	"role": "spec for the bucket and stack fields on every object, plus the stickiness rules that govern stack mutability; part of the universal object structure spec (see index.md)",
	"status": "active_design en route to settled spec",
	"audience": "Caspian implementers and security reviewers"
}}
~~~

Every object has two structural fields: `bucket` (the data) and `stack` (the class identity plus other meta-information). This page describes each, plus the stickiness rules that govern how the stack can change.

**The structure shown here is the serialized form** — what an object looks like as JSON, whether stored in a worldlet, written to a Mikobase record, or carried in a Puck protocol message. Caspian's in-memory representation has some differences (engine-internal references, cached dispatch tables, per-object identity slots, the actual sodium_malloc / vault pointers that back protected values, and so on). Those differences don't change the contract: the object round-trips to this JSON shape on every serialization boundary, and a JSON value in this shape rehydrates to a full Caspian object on every deserialization. Anywhere an object crosses a boundary, the shape below is what it looks like.

The full template:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {
            "sticky": true,
            "class":  {}
        }
    }
}
```

In practice either field may be absent — for example, when importing from a plain JSON hash that doesn't carry them. Absence is equivalent to the default empty form. The template above is the **full** structure; what actually ships in JSON can omit any field that's at its default.

## Bucket

~~~json
{"vibecode": {
	"section": "bucket",
	"role": "describes the bucket field — a hash that holds the object's data; accepts anything storable in a JSON hash"
}}
~~~

`bucket` is a hash. You can put anything in it that a hash can hold.

There are no namespace rules inside `bucket` — no reserved keys, no reserved key patterns, nothing the runtime claims. Every key in a bucket belongs to the class designer.

## Stack

~~~json
{"vibecode": {
	"section": "stack",
	"role": "describes the stack field — a hash of platters that holds the object's class identity and other meta-information"
}}
~~~

`stack` is a hash. Each entry is called a **platter** — the key is the platter's identifier (an arbitrary string), and the value is itself a hash holding that platter's own fields (`class`, `sticky`, `warning`, `bucket`, `vibecode`, and whatever else the platter needs to carry).

A platter carries meta data about the object. The order of the platters is significant in method resolution. The hash keys for the platters themselves are arbitrary. By custom we call the first one `"shadow"`.

Five keys are currently defined on a platter: `class`, `sticky`, `warning`, `bucket`, and `vibecode`. A platter hash can also carry additional fields a specific class uses for its own purposes; the five below are the ones the engine itself recognizes.

### class

The class this platter contributes to the object's identity. Method dispatch consults `class`; see [method-resolution.md](method-resolution.md).

In Caspian, `class` is a reference to an **actual class object** — a runtime instance with its own methods, fields, identity. The forms shown here are what that class object looks like when serialized to JSON:

- **A UNS string** (`"puck.uno/color"`) — the named class identified by that UNS. The serializer writes the name; the deserializer looks the class up from wherever it lives (a Mikobase record, the engine's built-in registry, etc.).
- **An inline hash** (`{...}`) — the class object's definition serialized into the platter. Used when the class doesn't have a name that can be referenced from elsewhere — most commonly the shadow class, which is unique per object and never registered under a UNS. An empty inline class (`{}`) is still a real class object; it just has no methods yet.
- **Absent** — equivalent to an empty inline class.

**The shadow platter doesn't hold an empty hash at runtime — it holds an actual class object** that serializes as `{}` until someone adds methods to it. Singleton methods added to the shadow (the canonical way to give one specific object behavior that no other object has) get added to that class object directly; the next time the platter serializes, the `{}` expands to a hash describing the methods.

Method dispatch consults the class object regardless of how it serializes. A class with no methods contributes nothing for the walk to find, so dispatch moves on to the next platter — that's how unmatched calls end up at method-not-found rather than landing on a no-op.

### sticky

Boolean. When true, the platter cannot be removed from the stack. If it sits at the top of the stack, it cannot be moved.

`sticky` is engine-only and one-way: only the engine can set it, and once set it can't be cleared.

How sticky platters interact across the stack — the propagation rule that turns adjacent sticky platters into stuck positions — is spelled out in the [Stickiness](#stickiness) section below.

### warning

Carries a warning object attached to this platter. Any code — engine, framework, or application — can attach a warning to an object when it detects a condition worth surfacing without interrupting execution. A canonical engine case is a stored value whose class disagrees with its declared schema at deserialization time, but application code uses the same mechanism: "this user record looks suspicious," "this date value was parsed leniently and may not be what the source intended," anything that's worth noting alongside the value but not worth raising.

Letting warnings ride on the object itself means they travel with the data: a value loaded from a database, passed through several scopes, and inspected hours later still carries any warning attached when the condition was first noticed. Observational rather than control-flow; the warning never raises, it just sits there for code that cares to look.

The contents of the `warning` field are themselves an object — typically of a class under `puck.uno/warning/...` — describing the condition.

### bucket

A platter can have its own private bucket — a hash for state that belongs to this platter's class, separate from the object's shared `bucket` at the top level.

The shared object bucket holds data that's "what this object is." The platter bucket holds data that's "what this class needs to remember about its participation in this object." For most platters the distinction doesn't matter — the platter is just contributing methods to a host object, and any data lives on the shared bucket. For **mix-in classes** the distinction matters a lot: a mix-in added to many different host classes can't safely store state on the host's bucket because key names would collide with whatever the host is doing. Its own platter bucket gives it a private namespace.

Trivet (a tree-node mix-in that can be attached to almost any object) is the canonical example. Inside Trivet's methods, code stores tree-state in the platter bucket via `%platter`:

~~~caspian
%platter['parent']   = $other_node
%platter['children'] = $children_array
%platter['id']       = 'food'
~~~

`%platter` is the in-method accessor for the currently-dispatching platter's bucket; `%bucket` continues to be the in-method accessor for the object's shared top-level bucket. `@foo` remains shorthand for `%bucket['foo']` (the shared bucket); there is no `@`-style shorthand for the platter bucket — `%platter[...]` is always explicit. Method dispatch tracks "which platter am I running under" automatically, so `%platter` resolves without ambiguity.

The same invariants apply as the object-level bucket: when present, it must be a hash (never a scalar, array, or null); empty `{}` is fine; no reserved keys inside. Most platters do NOT have a per-platter bucket — the field is absent. Only mix-in-style classes and other platter-local-state cases need it.

Serialized form:

~~~json
{
    "bucket": {},
    "stack": {
        "shadow":      {},
        "trivet_node": {
            "class":  "puck.uno/trivet/node",
            "bucket": {"parent": ..., "children": ..., "id": "food"}
        }
    }
}
~~~

The shadow platter's `sticky: true` and `class: {}` are defaults; an empty shadow expands to the full form. Subsequent examples in this doc will show shadow empty unless the explicit form matters:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {}
    }
}
```

### vibecode

A platter can carry its own `vibecode` block — an AI-readable hash of hints, context, or annotations about the platter. Use cases: an AI that generated the object recording what it was doing, why this platter is here, what assumptions it made, where it pulled data from. Anything an AI (or human auditing the trail later) might want to know about this platter that isn't load-bearing data.

```json
{
    "bucket": {},
    "stack": {
        "shadow": {},
        "ai_generated": {
            "class":    "foo.com/something",
            "vibecode": {
                "generated_by": "weather-advisor agent",
                "source":       "synthesized from NWS forecast 2026-06-02T18:30:45Z",
                "confidence":   0.85,
                "notes":        "free-form notes the generator wanted to leave"
            }
        }
    }
}
```

**Any platter can carry it.** A `vibecode` field on an existing platter (one already there for its class) is fine — the AI-info just rides alongside the platter's normal role.

**A standalone vibecode-only platter is also fine.** Add a platter whose only purpose is to carry vibecode — useful when the generating AI wants to attach metadata without affecting the object's class identity. Such a platter typically has `class: {}` (or absent), `vibecode: {...}`, and nothing else. Its presence in the stack contributes nothing to method dispatch (an empty class has no methods); it's pure annotation.

The contents of `vibecode` are free-form. The engine doesn't enforce a schema. Conventions for what to put in are situation-specific — see [worldlets/index.md](../worldlets/) and [puckai/bootstrap/](../puckai/bootstrap/) for examples of how vibecode is used in those contexts.

This is the same `vibecode` convention used at the top of markdown documents, at the top of worldlet JSON files, and on individual records: a structured AI-readable annotation that travels with whatever it sits on.

## Stickiness

~~~json
{"vibecode": {
	"section": "stickiness",
	"role": "defines the sticky flag on a platter, the engine-only / one-way rule, and the downward-propagation rule that turns adjacent sticky platters into stuck positions"
}}
~~~

`sticky` on a platter means two things:

- You can't remove it.
- If it's at the top of the stack, you can't move it.

`sticky` is engine-only and one-way: only the engine can set it on a platter, and once set it can't be cleared.

**Stickiness propagates downward.** A sticky platter directly under a stuck platter is itself stuck — the position-lock chains through every contiguous sticky platter starting from the top. The first non-sticky platter ends the chain; platters below it can still move.

For example, both shadow and `foo` are sticky and adjacent here, so `foo` is stuck at the second position under shadow:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {"sticky": true, "class": {}},
        "foo":    {"sticky": true, "class": {}}
    }
}
```

Platters not marked as sticky can be moved around or deleted.

**Two initial use cases for stickiness.** The mechanism exists for these specifically; both are engine-driven:

- **The shadow platter.** The shadow is sticky by default so it can't be moved away from the top of the stack or removed. Singleton methods added to an object live on the shadow's class, and the engine relies on the shadow being predictably at position 0 during dispatch.
- **`null` and `false` instances.** When the engine creates a `null` or a `false`, it adds a sticky platter directly under the shadow that carries the null-or-false class identity. The stickiness keeps the value from being talked out of being null or false later — once a value is created as null, it stays null for its lifetime; same for `false`. Because the platter is sticky and adjacent to the (also-sticky) shadow, the propagation rule above pins it at position 1.
