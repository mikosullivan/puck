# Inter-process communication

~~~json
{"vibecode": {
	"doc": "forking_ipc",
	"role": "spec for how Caspian processes communicate with each other. The answer: no dedicated IPC primitives. Caspian's IPC is the shared-resource pattern — a UDS-backed server holds the shared state; workers forked from the parent each get a wrapper proxying their operations to the server. Two flavors: shared-hash (lightweight, JSON-shaped state) and shared-mikobase (full database semantics). Both build entirely on the UDS + forking + auth toolbox.",
	"status": "committed for V1.0 (design) — implementation plan can't be fully written until Mikobase's own spec is settled, since shared-mikobase follows Mikobase's surface verbatim.",
	"depends_on": "UDS, forking, Mikobase, and shared-hash specs",
	"framing": "Caspian doesn't have threads, but its IPC is invisible — workers just touch a shared structure",
	"key_concepts": ["ipc_is_the_shared_resource_pattern",
		"no_dedicated_send_receive_primitives",
		"two_flavors_shared_hash_and_shared_mikobase",
		"server_holds_authoritative_state",
		"workers_see_a_wrapper_that_proxies_their_ops",
		"ipc_implementation_plan_gated_on_mikobase_spec"]
}}
~~~

Caspian doesn't have threads, and it doesn't have classical IPC primitives either. There's no `send_message`, no pipe API, no shared-memory protocol. Instead, **Caspian's IPC is the shared-resource pattern**: a small server process holds the shared state; each forked worker gets a wrapper that looks like a normal data structure but proxies every operation to the server.

Workers don't know they're doing IPC. They just touch a hash, or query a database, or make method calls on what looks like a regular object. The wrapper translates each operation into an HTTP request against the server; the server is single-threaded so all requests serialize naturally; workers see a consistent point-in-time view.

---

<a id="two-flavors"></a>
## Two flavors

Both built from the same UDS + forking + auth toolbox; differ only in what they share.

### Shared hash — lightweight JSON-shaped state

`$uds.share(N) do($hash) ... end` (see [shared-hash.md](../network/uds/shared-hash.md)).

- Each worker gets `$hash` — a wrapper that looks and behaves like a regular Caspian hash.
- Values are JSON primitives: strings, numbers, booleans, null, arrays, nested hashes. No class instances, no closures.
- Server holds the authoritative tree; PKs stored via class-stack platter.
- When all workers finish, share returns the final hash as regular Caspian data.

Use when workers need to coordinate via shared scratch state, accumulate results, share a counter or registry, etc. Lightweight, fast, no schema or query layer.

### Shared mikobase — full database semantics

`$uds.mikobase(N) do($db) ... end` (see [mikobase.md](../network/uds/mikobase.md)).

- Each worker gets `$db` — a wrapper that proxies the full Mikobase interface.
- Backed by an in-memory SQLite Mikobase (`https://mikobase.uno/sqlite/memory`).
- All Mikobase machinery available: Q0 queries, class definitions, records, convenience reads, etc. (Transactions across workers may be deferred from V1.0.)
- When all workers finish, the server tears down (return-value behavior TBD; see the mikobase spec).

Use when workers need real database semantics — query-based coordination, schema-validated records, complex object relationships, etc.

---

<a id="why-this-shape"></a>
## Why this shape

Caspian could have invented a dedicated IPC primitive — pipes, shared-memory channels, message queues, actor mailboxes, etc. It deliberately doesn't. Three reasons:

- **The shared-resource pattern is more general.** Once you have it, IPC is just "open the resource, mutate or read." Workers can coordinate via shared state without anyone designing a message protocol.
- **It reuses existing infrastructure.** UDS, auth, forking, wrappers — all are built for other reasons too. IPC comes "for free" once those land.
- **The mental model is familiar.** Touching a hash or querying a database is a pattern programmers already know. A message-passing API would be one more thing to learn.

The cost is per-operation HTTP round-trips. For high-throughput coordination this might be limiting; for the share-block use cases the cost is negligible (microseconds per round-trip on a same-host UDS). Atomic-update primitives (`.atomic_increment`, `.modify(key) do ... end`) can be added later for hot patterns without changing the API shape.

---

<a id="permissions"></a>
## Permissions

The whole IPC layer inherits the broader permission model:

- `$uds.share` and `$uds.mikobase` are entry points on `$uds`, which is itself reachable only with the UDS permission grant (currently `%utils.network.uds.new()` is user-role-only).
- Workers inherit the wrapper (`$hash` or `$db`) via closure capture — they don't need their own `$uds` access. The wrapper is the capability; possessing it is sufficient to talk to the server.
- The server uses token authentication (`$uds.authenticate = true` is on by default for shared-hash and shared-mikobase). The wrapper carries the token internally; clients without it get rejected at the HTTP layer.

No additional IPC-specific permission flags. The existing UDS / network / fork grants cover everything.

---

<a id="implementation-plan-status"></a>
## Implementation plan status

The DESIGN for IPC is committed for V1.0:

- [shared-hash.md](../network/uds/shared-hash.md) is fully spec'd.
- [mikobase.md](../network/uds/mikobase.md) is spec'd to the extent that the wrapper follows Mikobase's surface verbatim.

The IMPLEMENTATION plan can't be fully written yet because shared-mikobase's wrapper must mirror Mikobase's API — and that API is still being settled in the [Mikobase spec](../../mikobase/). Until Mikobase's interface is nailed down:

- The wrapper class for `$db` can't be enumerated (we don't know all the methods to translate).
- Server-side request handlers can't be enumerated (we don't know what Mikobase operations to handle).
- Wire protocol choices (Q0-shaped requests vs per-method REST endpoints) depend on how Mikobase's API surfaces.

Once Mikobase settles, the shared-mikobase wrapper and server are mechanically derivable from it — that's the whole "wrapper follows the surface" framing.

Until then, this doc captures the design; the implementation plan is gated on the Mikobase spec.

---

## See also

- [forking/](.) — the underlying fork mechanism.
- [network/uds/](../network/uds/) — the UDS layer everything's built on.
- [network/uds/shared-hash.md](../network/uds/shared-hash.md) — lightweight shared state.
- [network/uds/mikobase.md](../network/uds/mikobase.md) — full Mikobase semantics across workers.
- [mikobase/](../../mikobase/) — Mikobase's own spec (the surface that shared-mikobase wraps).
