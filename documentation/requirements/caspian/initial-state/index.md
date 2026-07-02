# Initial state
<!--index: 5 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_initial_state",
	"role": "canonical spec for the state of a Caspian engine immediately after bootstrap completes and before the first user statement executes; enumerates the values that are guaranteed to hold at that moment, including the current role, what's been seeded onto %chain, and what's empty",
	"audience": "engine implementers verifying conformance; host authors who need to know what they can rely on before any user code runs; AI tooling reasoning about engine startup"
}}
~~~

The **initial state** is the state the Caspian engine is in at the moment the first user statement is about to execute. Everything on this page describes that instant.

## Current role

The current role is `user`.

Caspian tracks which role owns the code that is currently executing. The first thing the engine runs is the program supplied by the host, and that program runs under the `user` role. Code running in other roles may switch to their own role for the duration of their own frames, but the entry point — the user's program — always starts as `user`.

## The chain is populated from `%engine`

Most of the methods user code reaches for at runtime live on [`%chain`](https://puck.uno/documentation/requirements/caspian/chain/), not on `%engine` directly. The chain is where capabilities propagate down through the call tree; the engine is the user-only gateway that hands the host's provisioned resources up to the chain in the first place.

At bootstrap, the engine walks every host-provisioned `%engine` slot and seeds the corresponding chain capability so user code (and, where granted, downstream roles) can reach it.

### Which `%engine` slots become chain capabilities

**Everything that reaches outside the script is an engine capability.** The engine is the user-only gateway to host-provisioned resources; the chain is where those resources flow once seeded. The seeding pairs each `%engine` slot with a `%chain.X` capability of the same name:

| `%engine` slot (user-only) | Seeded as | What it reaches |
|---|---|---|
| `%engine.argv` | `%chain.argv` | Command-line arguments. |
| `%engine.stdin` | `%chain.stdin` | Input channel. |
| `%engine.stdout` | `%chain.stdout` | Primary output. |
| `%engine.stderr` | `%chain.stderr` | Diagnostic output. |
| `%engine.tmp` | `%chain.tmp` | Temp-dir capability. |
| `%engine.now` | `%chain.now` | Engine-controlled clock. |
| `%engine.puck` | `%chain.puck` | Object download by URL. |
| `%engine.random` | `%chain.random` | Random-value primitives (libsodium → OS CSPRNG). |
| `%engine.encryption` | `%chain.encryption` | Cryptographic primitives (host's crypto). |
| `%engine.net` | `%chain.net` | Networking — HTTP, sockets, UDS. |
| `%engine.env` | `%chain.env` | Environment variables. |
| `%engine.forks` | `%chain.forks` | Process forking. |
| `%engine.root` | `%chain.root` | Root dirjail — the filesystem entry point. |

The host decides what to provision; the engine does the seeding mechanically. If the host didn't provision a slot (no stdin wired, no net granted, etc.), the corresponding chain capability is absent. User code reaching for an absent capability raises.

### Chain capabilities with no `%engine` counterpart

A handful of chain capabilities are pure runtime introspection or engine-internal accounting — they don't reach outside the script, so they're built into the engine itself rather than provisioned by the host:

- `%chain.memory` — introspection of this process's memory state.
- `%chain.steps` — Caspian-level evaluation step counter.
- `%chain.timeout` — wall-clock budget for a block. (Uses the clock provisioned via `%engine.now`, but is itself a chain-only block-scoping construct.)
- `%chain.timer` — elapsed-time measurement around a block. (Same — uses the engine clock but is itself a chain-only construct.)

These are present on the chain at initialization unconditionally.

### Default-grant status

Whether each chain capability propagates across role boundaries by default is set at this moment, per the [Two layers of grant](https://puck.uno/documentation/requirements/caspian/chain/#two-layers-of-grant) policy. Default-granted at initialization:

- `%chain.now`
- `%chain.puck`
- `%chain.random`
- `%chain.encryption`
- `%chain.timeout`
- `%chain.timer`
- `%chain.steps`

Everything else is default-deny — present on the chain for `user`, but a role boundary resets visibility unless `user` explicitly grants it through.

For the full catalog of chain methods and the canonical spec of the grant mechanism, see [`chain/`](https://puck.uno/documentation/requirements/caspian/chain/).

## The ambient hash slot is empty

`%chain['key']` is the ambient hash for arbitrary key/value context. At initialization it's empty — no entries, no inherited values. The first user statement that writes to it (`%chain['request_id'] = '...'`) creates the first entry.

## `%engine.return_val` starts in its no-assignment state

The engine slot that holds the program's return value (see [`%engine.return_val`](https://puck.uno/documentation/requirements/caspian/engine/return-val)) carries no user-set value at initialization. Whether that "no value" is represented as unset, as Caspian `null`, or as some implementation sentinel is **deliberately left to the implementation** — the spec only requires that if the program never assigns to it, `engine.run()` returns null to the host. Equivalent observable behavior; the slot's internal state is the implementation's choice.

## The call chain has one frame

The chain's frame stack contains exactly one entry — the entry-point frame, running as `user`. Calls and returns from here on push and pop frames.
