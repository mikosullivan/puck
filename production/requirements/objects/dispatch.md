~~~vibecode
{"doc": "requirements_objects_dispatch",
	"role": "Spec for method dispatch on any Caspian object. Names the layered walk the dispatcher performs (shadow → platters → primitive class → engine class → miss raises), the two implicit-at-bottom slots (primitive class from scalar_* columns; engine class from engine_class column) that live on the row rather than in refs, the `.obj` name-check fast-path that bypasses the whole walk to return a fresh agent, and the platter-participation rule: a platter must carry a `class` element to be considered during method search — platters lacking one stay in the array as valid metadata but sit inert during dispatch."}
~~~

# Method dispatch

Method lookup on any Caspian object follows a strict layered walk:

~~~text
shadow → platters (innermost-first) → primitive class → engine class → miss raises
~~~

Each layer contributes candidate methods. The walker consults them in order; first match wins; a walk to the end without a match raises method-not-found.

Everything below is an **engine-level convention** — the walk is how the dispatcher is written, not something the schema enforces. The schema stores the raw pieces (shadow ref, platters array, `scalar_*` columns, `engine_class` column); the dispatcher gives them meaning by the order and rules it applies.

## The layers

### Shadow — top

If the object has a shadow (a `key='s'` ref pointing at a hash), the shadow is consulted first. Any method the shadow defines wins over anything below.

### Platters — middle, innermost-first

If the object has platters (a `key='p'` ref pointing at an array), the walker iterates the array from index 0 (innermost) outward. Each platter is a `base='h'` hash. For a platter to participate in method search, **it must carry a `class` element** — an entry in the platter's hash keyed `class`, pointing at a class object. When present, that class contributes its methods at this step of the walk.

A platter that has no `class` element is still a valid platter and remains in the array. It just doesn't participate in method search. That leaves room for platter-shaped-but-non-class-carrying entries — warning platters (per `.warn`), per-instance metadata, tracking info, anything that wants a slot in the ordered array without contributing to dispatch.

Concretely, a class-carrying platter's storage shape is:

~~~text
platter hash (base='h')
├─ class → <class-object>
└─ ... any other metadata keys the platter's author wants
~~~

The dispatcher, at each platter step, does one lookup: `refs where parent = <platter_pk> and key = 'class'`. Empty result → skip the platter and continue to the next.

### Primitive class — implicit-at-bottom

If the row carries a primitive (one of the `scalar_*` columns is populated), the primitive's class is consulted at this layer. Number for `scalar_number`, String for `scalar_string`, Boolean for `scalar_bool`, one of the null flavors for `scalar_null`.

Not stored as a ref; the dispatcher reads the column and knows which class to consult. Immutable — the row's scalar column can't change, so the primitive class implicit at this layer is fixed for the object's lifetime.

Absent on non-scalar objects. Nothing to walk here for user-defined instances, bare Objects, agents, etc.

### Engine class — implicit-at-bottom

If the row carries `engine_class` (the column names a Lua module), the module's method registry is consulted at this layer. Sits BELOW the primitive class in the walk because the primitive-typed methods should win when both exist; engine class is the fallback for engine-provided behavior.

Not stored as a ref; the dispatcher reads the column and looks up the registered module.

Absent on most objects. Present on:

- **The Object class row** — `engine_class = 'object'`.
- **Agent rows** — `engine_class = 'obj'`.
- Other seeded built-in class rows as they're added.

### Miss raises

A walk that reaches this point without a match raises method-not-found.

## The `.obj` fast-path

`.obj` is not resolved through the walk above. It's a dispatcher name-check: any method call whose name is literally `obj` skips shadow, platters, primitive class, and engine class, and returns a fresh agent constructed via `obj.new(engine, receiver_pk)`.

Same style of mechanism-enforces-invariant as the primitive column: nothing in the walk consults `.obj`, so nothing in the walk can override it. Users can add methods called `obj` to their platters, their shadow, whatever — they're never reached, because dispatch never asks the walk about that name.

Two consecutive `$foo.obj` reads produce two distinct agent rows (per the spec's "no caching" rule). The current sprint's `obj.new` inserts + wires up the agent every time. Optimization is future work; the invariant matters more than the cost right now.

## Platters and other layers can coexist with engine class

Nothing schema-side prevents an object with `engine_class` set from also having platters or a shadow. If a user pushes a class onto an agent's platters, the walk becomes:

~~~text
shadow (empty) → user platters → primitive class (empty) → engine class ('obj') → miss raises
~~~

The user's platter methods win over the agent's built-in `.obj.*` catalog for the names they cover. The `.obj` reader itself is still unshadowable (that's the fast-path); this is only about methods on the agent AFTER `.obj` has produced it. Whether that's a feature or a footgun is a per-sprint decision; the dispatcher doesn't take a position.

## Summary

| Layer         | Storage                       | Dispatch-relevance |
|---------------|-------------------------------|--------------------|
| Shadow        | `refs` keyed `'s'`            | Consulted first if present |
| Platters      | `refs` keyed `'p'` → array of hashes | Each platter consulted iff it has a `class` element; innermost-first |
| Primitive class | `scalar_*` columns          | Consulted if any is populated |
| Engine class  | `engine_class` column         | Consulted if non-null |
| `.obj`        | not a layer — dispatcher name-check | Bypasses the whole walk |
