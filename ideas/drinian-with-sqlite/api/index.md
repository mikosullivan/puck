# API

~~~vibecode
{"vibecode": {
	"doc": "ideas_mvm_with_sqlite_api",
	"role": "landing page for the MVM API — the surface the engine calls to read and write state. Everything that lives here specifies that API.",
	"status": "first-pass method sketch — candidates to react to, not settled surface"
}}
~~~

The engine talks to MVM through a defined API — the calls the engine makes to read and write state. This subdirectory spec's that API.

Method names are placeholder; grouping matters more than naming at this stage. Each group is a category of operation the engine needs. Nothing here is settled — the point is to see the shape.

## Object CRUD

The core table. Most engine ops route through here.

### `create_object`

Insert a row. Caller names `primitive` and (for scalars) `scalar_type` + `scalar_value`. Optional `source_pk` + `line` for source tagging. Returns the assigned `object_pk`.

### `read_object`

Fetch a row by pk. Returns the full column set (primitive, scalar\_type, scalar\_value, bucket\_pk, stack\_pk, source, etc.).

### `exists_object`

Cheap "is this pk still live?" check without pulling the row.

### `update_object`

Write to the mutable columns (`bucket_pk`, `stack_pk`, GC scratch). Immutability trigger enforces which are permitted.

### `delete_object`

Remove a row. Cascades to bucket, stack, incoming references (subject to RESTRICT on `relationships.child`).

## Bucket + stack management

Buckets and stacks are lazy — the engine creates them on first use, not at object creation.

### `ensure_bucket`

Return the object's bucket pk, creating the HashPrimitive row and its `bucket_for` link if it doesn't exist yet. Idempotent.

### `ensure_stack`

Same shape as `ensure_bucket`, for the ArrayPrimitive stack.

### `has_bucket`

Cheap check for whether the object has a bucket provisioned yet — no side effects.

### `has_stack`

Same for the stack.

## Reference graph

The `relationships` table — the graph edges GC walks.

### `add_ref`

Insert an edge from a container primitive (parent, always a hash or array primitive) to a child object under a key or idx.

### `remove_ref`

Delete an edge by (parent, key/idx).

### `get_child`

One edge lookup: given (parent, key/idx), return the child.

### `iter_children`

All edges out of a parent, in key/idx order.

### `iter_parents`

Reverse lookup: all edges pointing at a child. Backs orphan detection and reachability queries.

## Runtime stack

The frames, locals, amber, delegations, and captured frames that describe live execution.

### `create_process`

New row in `processes`. Called at engine startup and per fork/coroutine.

### `push_frame`

Add a frame to a process's stack. Caller supplies `type`, `lexical_parent_pk`, `method_pk` / `method_class_pk`, iterator state, source position — whatever the frame type requires.

### `pop_frame`

Remove the top frame. Cascades to its locals, amber layers, delegations.

### `set_local`

Bind a name in a frame to an object pk.

### `read_local`

Look up a name in a frame (single frame; lexical-chain walk is a higher-level operation on top of this).

### `push_amber`

Add a per-frame amber layer (a domain init, remove marker, or grant entry).

### `read_amber`

Look up a domain-scoped amber value for a frame. Walks the amber stack; `amber_cleared` on any frame ends the walk with an empty result.

### `clear_amber`

Set the full-surface walk-stop on a frame — the `amber_cleared` flag.

### `add_delegation`

Grant a target role at the current frame.

### `capture_frames`

*(removed — exception design deferred / dropped from MVM)*

## Source registry

### `register_source`

Insert-or-fetch a source row. Caller supplies `type` + `path`; returns the `source_pk`. Duplicates permitted at the schema level right now; whether the API dedupes is a policy call.

### `read_source`

Fetch a source row by pk.

## Transactions

The primitive that gives Caspian its transaction feature (see [features § Full-process rollback via transactions](../features#full-process-rollback-via-transactions)).

### `begin`

Start a transaction. Modes: deferred (default), immediate, exclusive.

### `commit`

Commit the top-level transaction.

### `rollback`

Abort and revert.

### `savepoint`

Named nested rollback point inside a transaction. Supports partial undo.

### `release`

Commit a named savepoint into the enclosing transaction.

### `rollback_to`

Roll back to a named savepoint without ending the enclosing transaction.

## GC

The drain that operates on the `needs_trace` / `in_trace` scratch columns.

### `mark_needs_trace`

Set the mark on one or more object pks.

### `next_needs_trace`

Pop one candidate for tracing (bounded by the drain's inner loop).

### `is_in_uspace`

Query the `uspace` view for a single pk. Fast path used per-object during the drain.

### `iter_uspace`

Walk every uspace anchor. Used to seed traces.

### `collect_dead`

Remove an object and its cascade. Fires on_close hooks (through whatever mechanism lands).

## Session

The connection lifecycle and per-connection state.

### `open`

Connect to a MVM (file path, `:memory:`, socket path, HTTP URL). Applies schema if fresh; creates `current_process` TEMP table.

### `close`

Release the connection.

### `current_process`

Read the per-connection active process pk from the `current_process` TEMP table.

### `set_current_process`

Write the per-connection active process pk.

## What's not here yet

Things the engine will eventually need but that this pass doesn't scope:

- Query surfaces for the introspection features described in [features](../features) — SQL-as-debugger-protocol, JSON queries into CaspM, FTS5.
- Anything backend-specific (SQLite export formats for transfer, connection-string forms, capability negotiation).
- Notification / trigger surface — how UDFs and reactive-propagation callbacks plug in.

Those get added when we settle whether they're API-level (every backend implements) or SQLite-implementation-detail (leaky if we standardize).
