# Shared mikobase

~~~vibecode
{"vibecode": {
	"doc": "uds_shared_mikobase",
	"role": "spec for sharing a Mikobase across forked workers via UDS — the bigger sibling of $uds.share for hashes. Engine spawns an in-memory Mikobase server plus N forked workers; each worker gets a $db wrapper that proxies the full Mikobase interface to the server. Same wrapper-and-server pattern as shared-hash, just with the richer Mikobase surface.",
	"parent_doc": "network/uds/index.md",
	"related": ["network/uds/shared-hash.md", "mikobase/"],
	"status": "active design — entry point, fork model, and backend choice settled. Wrapper interface follows whatever Mikobase's surface ends up being. Return value, schema setup, transactions across workers, and listener semantics are open.",
	"depends_on": "Mikobase (full spec) + the UDS toolbox + the shared-hash patterns",
	"key_concepts": ["shared_mikobase_across_workers",
		"entry_point_uds_dot_mikobase_with_fork_count",
		"wrapper_proxies_full_mikobase_interface_through_uds",
		"default_backend_in_memory_sqlite",
		"reuses_shared_hash_pattern_at_richer_surface"]
}}
~~~

The bigger sibling of `$uds.share`. Same shape (spawn server, fork workers, each worker gets a wrapper) but instead of sharing a JSON-shaped hash, workers share a full Mikobase — with Q0 queries, class definitions, records, all the standard Mikobase machinery.

The wrapper is structurally identical to shared-hash's: a thin proxy that translates each Mikobase method call into an HTTP request against the server holding the authoritative store. Once Mikobase's interface is settled, the shared version follows it.

---

## Entry point

~~~caspian
$uds.mikobase(20) do($db)
    # each of the 20 forked workers runs this block with $db bound
    # to a wrapper that proxies to the shared Mikobase server.
end
~~~

Same pattern as `$uds.share(N)`:

- The engine spawns a Mikobase server in its own lightweight process.
- The engine forks N tracked workers.
- Each worker runs the block with `$db` bound to a wrapper.
- When all workers finish, the server tears down.

The block runs **inside the forks** — same model as shared-hash where `$hash` is bound inside each worker.

---

## Backend

Default: **`https://mikobase.uno/sqlite/memory`** — in-memory SQLite Mikobase. Full Mikobase semantics (Q0, class definitions, the works), ephemeral, fastest for in-process worker coordination.

The memory backend is the natural fit because:

- **Full Q0 for free.** SQLite under the hood means standard Mikobase queries work without any reimplementation.
- **Fast.** No disk I/O; everything stays in the server's memory.
- **Ephemeral matches the share-block lifecycle.** The data exists for the duration of the share; no persistence machinery to coordinate with.

Future versions might let the caller specify a different backend (file-backed SQLite for persistence, worldlet for very small workloads), but in-memory SQLite is the V1.0 default.

---

## Wrapper interface

`$db` exposes the **full Mikobase interface** — once that interface is settled, the shared version supports all of it. The wrapper translates each call into an HTTP request against the server; the server unwraps and runs the call against its local in-memory Mikobase; results come back over the wire.

User code treats `$db` exactly as it would treat any Mikobase:

~~~caspian
# Q0 queries
$results = $db.q0({action: 'select', classes: 'foo.com/character'})

# Convenience reads
$character = $db.record_by_pk($pk)
$all = $db.by_class('foo.com/character')

# Class definitions and instance creation
# (per whatever Mikobase's canonical surface ends up being)

# Listeners
# (TBD how before_save / after_save work across forks)
~~~

The shape of those calls is whatever Mikobase's spec says — the shared version doesn't define a separate API.

**What might get left out.** Some Mikobase features are hard across forks. Transactions in particular — coordinating "this set of operations happens atomically" across multiple worker processes is substantial concurrency machinery. If transactions prove hard to support in V1.0, they're the kind of thing we can defer rather than block the whole shared-mikobase feature.

The principle: full Mikobase surface where possible; punt on features that require cross-worker coordination if they're too expensive for V1.0.

---

## Open points

- **Return value when share ends.** Worldlet snapshot of the final Mikobase state, like `$uds.share` returns the final hash? Or nothing — server tears down, data is gone? Worldlet-snapshot is the natural parallel; nothing is fine if the use case is purely temporary coordination.
- **Schema setup.** Mikobase has class definitions. Where do those get loaded? Plausible answers: a `schema:` kwarg on `$uds.mikobase()` (`$uds.mikobase(20, schema: $my_classes)` — server starts with classes registered); load-from-worldlet at startup; first worker sets up schema then signals others; or schema setup happens inside the worker block and is idempotent.
- **Transactions across workers.** Worker A starts a transaction; worker B reads or writes during it; what's visible? Worker A commits; do worker B's mid-transaction operations see consistent state? Genuinely hard. Probably defer for V1.0; document the limitation.
- **Listener semantics.** Mikobase has `before_save` / `after_save` listeners. In a shared Mikobase, which worker's listener fires on a save from a different worker? All listeners on all workers? Just the server's? Defer this thinking until the listener spec for Mikobase itself settles.
- **Concurrent reads vs writes.** Server is single-threaded; requests serialize naturally. Any need for read/write distinction or snapshot isolation? Probably not for V1.0.
- **Wire-protocol shape.** Each Mikobase call serialized as a Q0 request (Mikobase's own canonical interface), or per-method HTTP endpoints (REST-shaped)? Q0 is the unifying abstraction in Mikobase already; reusing it for the wire format is simplest.
- **Worker reads while another's call is mid-flight.** Server's single-threaded request loop serializes everything, so technically not a concern, but the user-facing semantics need to be clear (workers see a consistent point-in-time view at the moment their call is processed).
- **`$uds.mikobase` and `$uds.share` interaction.** Can a single `$uds` host BOTH a shared hash AND a shared Mikobase simultaneously? Probably not in V1.0 (each `$uds` is for one kind of shared resource); but worth noting the constraint.
