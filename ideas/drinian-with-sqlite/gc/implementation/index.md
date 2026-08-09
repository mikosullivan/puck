# Implementation

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_gc_implementation",
	"role": "how Drinian's garbage collection is actually implemented — schema-level mark triggers that populate the needs_trace field on objects, and the Lua-side tracer routine that processes marked rows.",
	"status": "in progress — mark trigger inventory drafted; tracer drain-loop details still to come"
}}
~~~

The engine drives GC through two scratch columns on `objects`: `needs_trace` and `in_trace`. Both are null in the common case; they light up as rows travel through the drain.

## Mark triggers

Every table in the schema that holds a pointer to an `objects` row is a potential source of orphaning — when the pointer changes or the row holding it goes away, the previously-pointed-at object might have just lost its last incoming reference. The schema attaches a mark trigger to each such source. Each trigger does one thing: set `needs_trace = 1` on the row that just lost the incoming pointer. That's the trigger's entire job — no tracer call, no re-entry check, no other logic. Marking is schema-enforced; the actual drain is scheduled by the Lua write layer (see [The tracer](#the-tracer)).

Mark triggers are idempotent: setting `needs_trace = 1` on a row that's already marked is a harmless no-op.

The current inventory of triggers, one per pointer-source column:

- **`relationships.child`.** `after delete` — mark `old.child`. `child` is immutable per the schema, so no update-time mark is needed; rebinding an edge is expressed as delete + insert, and the delete fires the mark.
- **`locals.value_object_pk`.** `after delete` and `after update of value_object_pk` — mark `old.value_object_pk`. Fires on variable rebinding and on frame pop (cascade).
- **`frame_ambers.amber_pk`.** `after delete` and `after update of amber_pk` — mark `old.amber_pk`. Fires on frame pop (cascade) and on any rebinding of a frame's domain to a different amber instance. Amber instances themselves are ordinary objects; this bridge table is the anchor point.
- **`frame_delegations.target_role_pk`.** `after delete` and `after update of target_role_pk` — mark `old.target_role_pk`. (Deletes fire on frame pop via cascade.)
- **`frames.method_pk` / `method_class_pk` / `exception_class_pk`.** `after update of <col>` — mark `old.<col>`. Frame deletes cascade at the frames level; the outgoing FK pointers to objects on these columns don't cascade, so the after-update mark on repointing is the coverage.

Anything the schema grows in the future that adds a new FK column into `objects` gets a matching trigger. The invariant to maintain: **every column that FKs to `objects(object_pk)` has a mark trigger covering DELETE and UPDATE OF that column.** A test in the walking-skeleton harness enumerates FKs against `objects(object_pk)` and asserts each source column has a matching trigger — keeps the inventory honest as the schema grows.

## The tracer

The tracer is a Lua routine in the write layer. When the write layer performs any operation that might have dropped a reference, it invokes the tracer after that operation completes. The tracer processes every row with `needs_trace = 1` and either clears the flag (row proven reachable) or deletes the row (row proven orphaned).

Details of the drain-loop land here as we work through them.
