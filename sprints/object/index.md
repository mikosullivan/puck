~~~vibecode
{"doc": "sprint-index", "sprint": "object",
	"role": "Implement Caspian's Object class and enough of the primitive classes (Number, String, Boolean, Null) to be useful — as first-class classes with their own class stacks and a `.new` method. The specs already exist under [requirements/built-in-classes](https://puck.uno/requirements/built-in-classes/); this sprint is where the engine grows real class-based dispatch instead of the walking-skeleton shortcut (direct `add_scalar`) that has stood in until now. Opens the door for `Number.new(1)`, `'foo'.upcase`, `$x.class`, and `%('puck.uno/object').new()` to actually dispatch through methods on the receiver's class chain.",
	"status": "seed — problem captured, spec exists, not yet implemented. The expressions sprint deferred class-based scalar materialization to this sprint; the direct add_scalar shortcut in production covers the immediate need."}
~~~

# object

Implement Caspian's Object class and enough of the primitive classes to make class-based dispatch real. First-class classes with class stacks, `.new` constructors, and per-instance method lookup — the foundation the rest of the language will build on.

## What already exists in spec

Spec is settled at [requirements/built-in-classes](https://puck.uno/requirements/built-in-classes/):

- [Object class](https://puck.uno/requirements/built-in-classes/object/) — root of the hierarchy; the `obj` cross-cutting namespace; bare-object construction via `%('puck.uno/object').new()`.
- [Object methods](https://puck.uno/requirements/built-in-classes/object/methods/) — the full `obj` catalog.
- [Object structure](https://puck.uno/requirements/built-in-classes/object/structure/) — the class-stack layout on an instance.
- [Primitives](https://puck.uno/requirements/built-in-classes/primitives/) — Boolean, Null, Number, String, Hash, Array.
- [Primitive buckets](https://puck.uno/requirements/built-in-classes/primitive-buckets) — how primitive instances carry state.

Nothing to design here — this sprint is about landing an implementation that honors the settled spec.

## What exists in the engine today

- **Direct scalar materialization** via `engine.data:add_scalar(value, owner_role)` in [production/src/engine/cvm/sqlite/object.lua](https://puck.uno/production/src/engine/cvm/sqlite/object.lua) — a walking-skeleton shortcut that inserts a scalar `objects` row without going through class dispatch. Used by the assign handler for `$x = 1` and by the future BareLiteralHandler.
- **`engine_class` column** on `objects` (see the schema) — hooks a row to a Lua-side engine-provided class implementation. Immutable via `objects_engine_class_immutable` trigger.
- **`class_listeners` table** — per-class event registration. Already schema-native.

No `Object.new` path exists yet. No primitive class objects exist yet. No class stack is materialized on any instance.

## Rough scope

Not a plan — a starting list. Details settle as work happens:

- **Object as a first-class class object.** An `objects` row (probably a seeded row created during bootstrap) that IS the Object class. `%('puck.uno/object')` resolves to this row.
- **`.new` on Object.** A method on the Object class object that constructs a new instance — allocates the row, wires up the class stack, materializes the bucket.
- **Primitive class objects.** `Number`, `String`, `Boolean`, `Null` — likely each seeded in bootstrap alongside Object. Each has a `.new` that produces a scalar instance with the right `scalar_*` column populated and the class stack pointing at the primitive class.
- **The `obj` cross-cutting namespace.** Class-agnostic methods every instance carries. Non-overridable.
- **Method dispatch through class stack.** When a method is called on an instance, walk the class stack innermost-first, dispatch to the first match. Miss raises.
- **Migration path for existing scalar materialization.** The direct `add_scalar` shortcut stays for the hot path (creating a Number from a literal), but its output is now a full-fledged Number instance — a class-stack-carrying scalar, not a bare untagged row.

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
- [sprints/method-call](https://puck.uno/sprints/method-call/) — the dispatch primitive that will walk the class stacks this sprint creates.
- [sprints/lazy-params](https://puck.uno/sprints/lazy-params/) — the `&` sigil for lazy parameters; some Object methods (e.g., short-circuits) need it.
