# Structure

~~~vibecode
{"vibecode": {
	"doc": "object_structure_fields",
	"role": "spec for the bucket and stack fields on every object, including the rule that the platter at position 1 is always named shadow; part of the universal object structure spec (see index.md)",
	"status": "active_design en route to settled spec",
	"audience": "Caspian implementers and security reviewers"
}}
~~~

Every object has two structural fields: `bucket` (the data) and `stack` (the class identity plus other meta-information). This page describes each, plus the rules that govern the stack — most importantly that the platter at position 1 is always named `shadow`.

**The structure shown here is the serialized form** — what an object looks like as JSON, whether stored in a worldlet, written to a Mikobase record, or carried in a Puck protocol message. Caspian's in-memory representation has some differences (engine-internal references, cached dispatch tables, per-object identity slots, the actual sodium_malloc / vault pointers that back protected values, and so on). Those differences don't change the contract: the object round-trips to this JSON shape on every serialization boundary, and a JSON value in this shape rehydrates to a full Caspian object on every deserialization. Anywhere an object crosses a boundary, the shape below is what it looks like.

The full template:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {
            "class": {}
        }
    }
}
```

In practice either field may be absent — for example, when importing from a plain JSON hash that doesn't carry them. Absence is equivalent to the default empty form. The template above is the **full** structure; what actually ships in JSON can omit any field that's at its default — and as covered in the Stack section below, the shadow platter itself is implicit when absent, so a stack with no shadow entry is fine.

## Bucket

~~~vibecode
{"vibecode": {
	"section": "bucket",
	"role": "describes the bucket field — a hash that holds the object's data; accepts anything storable in a JSON hash"
}}
~~~

`bucket` is a hash. You can put anything in it that a hash can hold.

There are no namespace rules inside `bucket` — no reserved keys, no reserved key patterns, nothing the runtime claims. Every key in a bucket belongs to the class designer.

## Stack

~~~vibecode
{"vibecode": {
	"section": "stack",
	"role": "describes the stack field — a hash of platters that holds the object's class identity and other meta-information"
}}
~~~

`stack` is a hash. Each entry is called a **platter** — the key is the platter's identifier, and the value is itself a hash holding that platter's own fields (`class`, `warning`, `bucket`, `vibecode`, and whatever else the platter needs to carry).

A platter carries meta data about the object. The order of the platters is significant in method resolution.

**The first platter must be named `"shadow"`.** This is a hard rule: the key at position 1 in the `stack` hash is always `"shadow"`. The keys for the rest of the platters are arbitrary.

**The shadow is implicit when absent.** A `stack` that does not contain a `"shadow"` entry is understood to have an empty shadow platter sitting at position 1, ahead of whatever other platters the hash carries. The two objects below are equivalent — same shadow, same `foo` platter, same dispatch order:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {},
        "foo": {"class": "puck.uno/foo"}
    }
}
```

```json
{
    "bucket": {},
    "stack": {
        "foo": {"class": "puck.uno/foo"}
    }
}
```

Either form is legal — pick whichever reads better at the call site. Most objects don't need anything beyond the engine's empty-shadow default, so the second form is the common case; only objects that put something on the shadow (singleton methods, attached `vibecode`, etc.) need the explicit form. Examples elsewhere in the docs use whichever form makes the point at hand clearer.

**The shadow is the only platter with a fixed position.** Every other platter can be added, removed, or reordered freely — there is no engine-level lock holding any non-shadow platter in place. The shadow stays at position 1 because the rule above says it does (the name is reserved for position 1; the runtime treats the slot as implicit when no explicit entry is present), not because the platter itself is somehow pinned. Stack mutation is otherwise unrestricted.

Four keys are currently defined on a platter: `class`, `warning`, `bucket`, and `vibecode`. A platter hash can also carry additional fields a specific class uses for its own purposes; the four below are the ones the engine itself recognizes.

### class

The class this platter contributes to the object's identity. Method dispatch consults `class`; see [method-resolution.md](method-resolution.md).

In Caspian, `class` is a reference to an **actual class object** — a runtime instance with its own methods, fields, identity. The forms shown here are what that class object looks like when serialized to JSON:

- **A UNS string** (`"puck.uno/color"`) — the named class identified by that UNS. The serializer writes the name; the deserializer looks the class up from wherever it lives (a Mikobase record, the engine's built-in registry, etc.).
- **An inline hash** (`{...}`) — the class object's definition serialized into the platter. Used when the class doesn't have a name that can be referenced from elsewhere — most commonly the shadow class, which is unique per object and never registered under a UNS. An empty inline class (`{}`) is still a real class object; it just has no methods yet.
- **Absent** — equivalent to an empty inline class.

**The shadow platter doesn't hold an empty hash at runtime — it holds an actual class object** that serializes as `{}` until someone adds methods to it. Singleton methods added to the shadow (the canonical way to give one specific object behavior that no other object has) get added to that class object directly; the next time the platter serializes, the `{}` expands to a hash describing the methods.

Method dispatch consults the class object regardless of how it serializes. A class with no methods contributes nothing for the walk to find, so dispatch moves on to the next platter — that's how unmatched calls end up at method-not-found rather than landing on a no-op.

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
        "shadow": {},
        "trivet_node": {
            "class": "puck.uno/trivet/node",
            "bucket": {"parent": ..., "children": ..., "id": "food"}
        }
    }
}
~~~

The shadow platter's `class: {}` is the default; an empty shadow expands to the full form. Subsequent examples in this doc will show shadow empty (or omitted entirely) unless the explicit form matters:

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
            "class": "foo.com/something",
            "vibecode": {
                "generated_by": "weather-advisor agent",
                "source": "synthesized from NWS forecast 2026-06-02T18:30:45Z",
                "confidence": 0.85,
                "notes": "free-form notes the generator wanted to leave"
            }
        }
    }
}
```

**Any platter can carry it.** A `vibecode` field on an existing platter (one already there for its class) is fine — the AI-info just rides alongside the platter's normal role.

**A standalone vibecode-only platter is also fine.** Add a platter whose only purpose is to carry vibecode — useful when the generating AI wants to attach metadata without affecting the object's class identity. Such a platter typically has `class: {}` (or absent), `vibecode: {...}`, and nothing else. Its presence in the stack contributes nothing to method dispatch (an empty class has no methods); it's pure annotation.

The contents of `vibecode` are free-form. The engine doesn't enforce a schema. Conventions for what to put in are situation-specific — see [worldlets/index.md](../worldlets/) and [puckai/bootstrap/](../puckai/bootstrap/) for examples of how vibecode is used in those contexts.

This is the same `vibecode` convention used at the top of markdown documents, at the top of worldlet JSON files, and on individual records: a structured AI-readable annotation that travels with whatever it sits on.

