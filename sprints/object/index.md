~~~vibecode
{"doc": "sprint-index", "sprint": "object",
	"role": "Implement Caspian's Object class and enough of the primitive classes (Number, String, Boolean, Null) to be useful — as first-class classes with their own class platters and a `.new` method. The specs already exist under [requirements/built-in-classes](https://puck.uno/requirements/built-in-classes/); this sprint is where the engine grows real class-based dispatch instead of the walking-skeleton shortcut (direct `add_scalar`) that has stood in until now. Opens the door for `Number.new(1)`, `'foo'.upcase`, `$x.class`, and `%('puck.uno/object').new()` to actually dispatch through methods on the receiver's class chain.",
	"status": "track 1 landed — b/p/s object-property shape (schema triggers, view rewrites, engine-code sweep, .id→.pk spec rename, dispatch design doc promoted to production/requirements/objects/) all in production as of the object-sprint assimilation. Track 2 (Lua-side object + obj class implementations + real method-call dispatcher replacing the sprint's MethodCall stub) still resident in sprint pending the method-call sprint moving off seed-only."}
~~~

# object

Implement Caspian's Object class and enough of the primitive classes to make class-based dispatch real. First-class classes with class platters, `.new` constructors, and per-instance method lookup — the foundation the rest of the language will build on.

## Core concept — an object IS a record

Every object in Caspian is exactly one row in the `objects` table. There is no other kind of object. No transient in-memory-only objects, no Lua-side handles that stand in for a Caspian object without a record, no "value that will get an id later" — if it doesn't have a row, it isn't an object yet, and the language can't see it.

**"Object" and "record" are used interchangeably.** They aren't strictly synonymous — "record" names the storage row, "object" names the language-level entity that lives in it — but the mapping is one-to-one, so nothing in the design distinguishes them.

## The four object properties

Every object carries up to four properties. Which are present depends on what kind of object it is; all four are optional except that an object with none of them is just a bare stub and effectively useless.

The three ref-based properties (bucket, platters, shadow) live as keyed refs from the object row: `key='b'` for bucket, `key='p'` for platters, `key='s'` for shadow. The primitive lives on the row itself as a scalar column.

- **bucket** — the state hash. Physically, a `base='h'` object linked from the record via a `key='b'` ref, holding entries keyed by name (locals, fields, rv, whatever). Mutable — entries can be added, removed, or updated at any time. Fresh objects don't have a bucket until something needs to store state; materialize-on-demand.
- **platters** — the class chain the instance carries. Physically, a `base='a'` array linked from the record via a `key='p'` ref, holding the ordered list of classes contributing methods to this instance, innermost-first. Mutable — classes can be pushed on or popped off during the object's lifetime (that's how `add_class`, singleton methods, etc. work). Bare Object instances have Object as the only entry; primitives have their primitive class + Object; user-defined instances layer their class(es) on top.
- **shadow** — the top-of-dispatch hash. Physically, a `base='h'` object linked from the record via a `key='s'` ref. Consulted first at method dispatch, before the platters. Mutable. Same target shape as bucket, distinguished by the ref key.
- **primitive** — the underlying scalar payload. One of `scalar_string`, `scalar_integer`, `scalar_frac`, `scalar_bool`, or one of the null flavors. Present only on scalar instances (Number, String, Boolean, Null); absent on bare Object and user-defined non-scalar instances. Lives on the row itself as a scalar column (not a ref). **Immutable** — schema-enforced. Once written at row-insert time, it can never change. Every other property can shift over the object's life; the primitive is the one thing that's forever.

The immutability of primitive is what gives Caspian's scalars their value-type feel. A Number that IS `1` cannot BECOME `2` — you make a fresh Number for `2`. Two Numbers with the same primitive but different platters or buckets are still distinct objects (different rows), but they're indistinguishable at the primitive level. That asymmetry is deliberate.

**Dispatch order.** Method lookup walks `shadow → platters (innermost-first) → primitive class (if present) → engine class (if present) → miss raises`. Two implicit-at-bottom slots — primitive class from the row's `scalar_*` columns, engine class from the row's `engine_class` column. Both are dispatched by the engine, not stored in refs. Full write-up including the `.obj` name-check fast-path and the platter-participation rule (a platter must carry a `class` element to be considered during search) at [dispatch](./dispatch).

## What already exists in spec

Spec is settled at [requirements/built-in-classes](https://puck.uno/requirements/built-in-classes/):

- [Object class](https://puck.uno/requirements/built-in-classes/object/) — root of the hierarchy; the `obj` cross-cutting namespace; bare-object construction via `%('puck.uno/object').new()`.
- [Object methods](https://puck.uno/requirements/built-in-classes/object/methods/) — the full `obj` catalog.
- [Object structure](https://puck.uno/requirements/built-in-classes/object/structure/) — the class-platters layout on an instance.
- [Primitives](https://puck.uno/requirements/built-in-classes/primitives/) — Boolean, Null, Number, String, Hash, Array.
- [Primitive buckets](https://puck.uno/requirements/built-in-classes/primitive-buckets) — how primitive instances carry state.

Nothing to design here — this sprint is about landing an implementation that honors the settled spec.

## What exists in the engine today

- **Direct scalar materialization** via `engine.data:add_scalar(value, owner_role)` in [production/src/engine/cvm/sqlite/object.lua](https://puck.uno/production/src/engine/cvm/sqlite/object.lua) — a walking-skeleton shortcut that inserts a scalar `objects` row without going through class dispatch. Used by the assign handler for `$x = 1` and by the future BareLiteralHandler.
- **`engine_class` column** on `objects` (see the schema) — hooks a row to a Lua-side engine-provided class implementation. Immutable via `objects_engine_class_immutable` trigger.
- **`class_listeners` table** — per-class event registration. Already schema-native.

No `Object.new` path exists yet. No primitive class objects exist yet. No platters is materialized on any instance.

## Rough scope

Not a plan — a starting list. Details settle as work happens:

- **Object as a first-class class object.** An `objects` row (probably a seeded row created during bootstrap) that IS the Object class. `%('puck.uno/object')` resolves to this row.
- **`.new` on Object.** A method on the Object class object that constructs a new instance — allocates the row, wires up the platters, materializes the bucket.
- **Primitive class objects.** `Number`, `String`, `Boolean`, `Null` — likely each seeded in bootstrap alongside Object. Each has a `.new` that produces a scalar instance with the right `scalar_*` column populated and the platters pointing at the primitive class.
- **The `obj` cross-cutting namespace.** Class-agnostic methods every instance carries. Non-overridable.
- **Method dispatch through platters.** When a method is called on an instance, walk the platters innermost-first, dispatch to the first match. Miss raises.
- **Migration path for existing scalar materialization.** The direct `add_scalar` shortcut stays for the hot path (creating a Number from a literal), but its output is now a full-fledged Number instance — a platters-carrying scalar, not a bare untagged row.

## What this sprint does NOT touch

- **User-defined classes.** `class # widget ... end` syntax and its bootstrap semantics — that's a follow-on. This sprint stops at built-in Object + primitives.
- **Class inheritance in Caspian source.** The `<` inherit relation on user-defined classes. Follow-on.
- **Full `obj` method catalog.** The Object methods spec lists many methods; this sprint lands the ones needed to make bare-object construction and scalar materialization coherent, not the whole catalog.
- **Method-call dispatch primitive.** Already spec'd in [expressions/primitives/method-call](https://puck.uno/requirements/expressions/primitives/method-call); implementation lands with the method-call sprint. This sprint provides the receiver-side class chain that dispatch will walk.

## Related

- [production/requirements/built-in-classes/](https://puck.uno/requirements/built-in-classes/) — the settled spec this sprint implements.
- [production/requirements/classes/](https://puck.uno/requirements/classes/) — the general class-mechanism spec (inheritance, instance shape, etc.).
- [production/src/engine/cvm/sqlite/object.lua](https://puck.uno/production/src/engine/cvm/sqlite/object.lua) — where the direct scalar-materialization shortcut lives today.
- [production/src/engine/cvm/sqlite/schema.sql](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — `engine_class` column, `class_listeners` table.
- [sprints/method-call](https://puck.uno/sprints/method-call/) — the dispatch primitive that will walk the platterss this sprint creates.
- [sprints/lazy-params](https://puck.uno/sprints/lazy-params/) — the `&` sigil for lazy parameters; some Object methods (e.g., short-circuits) need it.
