# Initial state
<!--index: 5 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_initial_state",
	"role": "canonical spec for the state of a Caspian engine immediately after bootstrap completes and before the first user statement executes; enumerates the values that are guaranteed to hold at that moment, including the current role, what's been seeded onto %chain, and what's empty",
	"audience": "engine implementers verifying conformance; host authors who need to know what they can rely on before any user code runs; AI tooling reasoning about engine startup"
}}
~~~

The **initial state** is the state the Caspian engine is in at the moment the first user statement is about to execute. Everything on this page describes that instant.

## Current role

The current role is `user`.

Caspian tracks which role owns the code that is currently executing. The first thing the engine runs is the program supplied by the host, and that program runs under the `user` role. Code running in other roles may switch to their own role for the duration of their own frames, but the entry point — the user's program — always starts as `user`.

The current frame's role is exposed as [`%role`](https://puck.uno/requirements/roles/#role); see the roles spec for the full surface.

<!-- STALE: %chain.X syntax being reworked — most of the rest of this doc describes %chain.X as if %chain still carried methods; the model has changed (%chain is now permission-only). See [chain/index](https://puck.uno/archive/003/misc/chain-old/). -->

## The chain is populated from `%engine`

Most of the methods user code reaches for at runtime live on [`%chain`](https://puck.uno/archive/003/misc/chain-old/), not on `%engine` directly. The chain is where capabilities propagate down through the call tree; the engine is the user-only gateway that hands the host's provisioned resources up to the chain in the first place.

At bootstrap, the engine walks every host-provisioned `%engine` slot and seeds the corresponding chain capability so user code (and, where granted, downstream roles) can reach it.

### Which `%engine` slots become chain capabilities

**Everything that reaches outside the script is an engine capability.** The engine is the user-only gateway to host-provisioned resources; the chain is where those resources flow once seeded. The seeding pairs each `%engine` slot with a `%chain.X` capability of the same name:

| `%engine` slot (user-only) | Seeded as | What it reaches |
|---|---|---|
| `%engine.argv` | `%chain.argv` | Command-line arguments. |
| `%engine.stdin` | `%stdin` | Input channel. |
| `%engine.stdout` | `%stdout` | Primary output. |
| `%engine.stderr` | `%stderr` | Diagnostic output. |
| `%engine.tmp` | `%tmp` | Temp-dir capability. |
| `%engine.puck` | `%puck` | Object download by URL. |
| `%engine.encryption` | `%encryption` | Cryptographic primitives (host's crypto). |
| `%engine.net` | `%net` | Networking — HTTP, sockets, UDS. |
| `%engine.env` | `%chain.env` | Environment variables. |
| `%engine.forks` | `%chain.forks` | Process forking. |
| `%engine.fs` | `%fs` | Filesystem dirjail — the filesystem entry point. |

The host decides what to provision; the engine does the seeding mechanically. If the host didn't provision a slot (no stdin wired, no net granted, etc.), the corresponding chain capability is absent. User code reaching for an absent capability raises.

**Clock and randomness are not chain capabilities.** They're downloadable core objects reached through `%('core:now')` and `%('core:random')` — no `%engine.now` / `%engine.random` slot, no `%chain.now` / `%chain.random` seeding, no default-grant flag. If a role can `%fetch`, it can read the clock or draw randomness.

### Chain capabilities with no `%engine` counterpart

A handful of chain capabilities are pure runtime introspection or engine-internal accounting — they don't reach outside the script, so they're built into the engine itself rather than provisioned by the host:

- `%chain.steps` — Caspian-level evaluation step counter.
- `%timeout` — wall-clock budget for a block. Uses an engine-internal clock (not a chain-mediated capability); the surface itself is a chain-only block-scoping construct.
- `%timer` — elapsed-time measurement around a block. Same — uses the engine-internal clock, is itself a chain-only construct.

These are present on the chain at initialization unconditionally.

### Default-grant status

Whether each chain capability propagates across role boundaries by default is set at this moment, per the [Two layers of grant](https://puck.uno/archive/003/misc/chain-old/#two-layers-of-grant) policy. Default-granted at initialization:

- `%puck`
- `%encryption`
- `%timeout`
- `%timer`
- `%chain.steps`

Everything else is default-deny — present on the chain for `user`, but a role boundary resets visibility unless `user` explicitly grants it through.

For the full catalog of chain methods and the canonical spec of the grant mechanism, see [`chain/`](https://puck.uno/archive/003/misc/chain-old/).

## The ambient hash slot is empty

<!-- STALE: ambient-hash-slot moving to %amber -->
`%chain['key']` is the ambient hash for arbitrary key/value context. At initialization it's empty — no entries, no inherited values. The first user statement that writes to it (`%chain['request_id'] = '...'`) creates the first entry.

<!-- STALE: ambient-hash-slot moving to %amber -->
**Cleared at role boundaries.** Entries in `%chain[]` do not cross a role boundary. When a call transitions into a different role, the callee's frame sees an empty ambient hash — whatever the caller set is invisible to the callee's role, and nothing the callee sets propagates back or forward through further role transitions. Descendants that stay within the same role see the entries the parent frame set (that's the "flows downward within a role" property of `%chain` — see [chain § Frame inheritance](https://puck.uno/archive/003/misc/chain-old/#frame-inheritance)); crossing into a different role resets the ambient hash to empty as part of the same role-boundary reset that resets grants (see [chain § Role boundaries reset everything](https://puck.uno/archive/003/misc/chain-old/#role-boundaries-reset-everything)).

## The call chain has one frame

The chain's frame stack contains exactly one entry — the entry-point frame, running as `user`. Calls and returns from here on push and pop frames.

## Testing

- **First statement runs as `user`** — the entry-point statement observes `%role == 'user'`.
- **`%role` is reachable in first frame** — reading `%role` before any grant modification returns `'user'` without raising.
- **`%role` is not on `%chain`** — introspection of `%chain`'s catalog does not list `role`; `%role` is a top-level global.
- **Every provisioned `%engine` slot has a matching `%chain` capability** — for each `%engine.X` the host wired, `%chain.X` is present and callable in the first user statement.
- **Absent `%engine` slot leaves `%chain` capability absent** — a host that omits `%engine.net` leaves `%net` unreachable; user code raises on use.
- **`%chain.argv` mirrors `%engine.argv`** — reading `%chain.argv` returns the same array as `%engine.argv`.
- **`%stdin`, `%stdout`, `%stderr` mirror their engine slots** — each capability delegates to its host-installed callback.
- **`%tmp`, `%puck`, `%encryption`, `%net`, `%chain.env`, `%chain.forks`, `%fs` mirror their engine slots** — each capability is present when the host provisioned the corresponding `%engine.X`.
- **Clock and randomness via `%('core:X')`** — `%('core:now')` and `%('core:random')` return the clock and RNG sources respectively; no chain slot, no engine slot.
- **`%chain.steps` is present unconditionally** — the step counter is readable from the first statement.
- **`%timeout` is present unconditionally** — a `%timeout` block works without host provisioning beyond the clock.
- **`%timer` is present unconditionally** — a `%timer` block works without host provisioning beyond the clock.
- **Default-granted capabilities cross a role boundary** — `%puck`, `%encryption`, `%timeout`, `%timer`, `%chain.steps` are visible in a non-`user` frame without explicit grant.
- **Non-default-granted capabilities are absent across a role boundary** — `%net`, `%stdin`, `%stdout`, `%stderr`, `%tmp`, `%chain.env`, `%chain.forks`, `%chain.argv`, `%fs` raise in a non-`user` frame with no grant.
- **`%chain[]` is empty at start** — reading `%chain['anything']` before any write returns the empty/missing value. <!-- STALE: ambient-hash-slot moving to %amber -->
- **First `%chain[] = ...` creates the entry** — after `%chain['k'] = 'v'`, `%chain['k']` returns `'v'`. <!-- STALE: ambient-hash-slot moving to %amber -->
- **`%chain[]` clears at role boundary** — a call into a different role sees an empty ambient hash even after the caller populated it. <!-- STALE: ambient-hash-slot moving to %amber -->
- **`%chain[]` flows downward within the same role** — a same-role callee sees the caller's entries. <!-- STALE: ambient-hash-slot moving to %amber -->
- **Callee's `%chain[]` writes do not leak back** — after a same-role callee returns, the caller sees only its own entries. <!-- STALE: ambient-hash-slot moving to %amber -->
- **Only one frame present at first statement** — introspection of the frame stack shows exactly one frame before the first push.
- **Built-in primitive classes are reachable** — the string, number, hash, array, and boolean classes documented in built-in-classes are usable in the first statement.
- **Seeding runs before first user statement** — a program whose first statement calls a `%chain.X` capability succeeds; the seeding has already happened.
