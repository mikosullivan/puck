# `%chain`
<!--index: 8 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_chain",
	"role": "spec for %chain — the ambient call-frame chain. Every global method lives on %chain; capability propagation across role boundaries happens through %chain; ambient context flows down %chain; inspection reads %chain.",
	"settled": "frame inheritance, grant/revoke as methods on capabilities, idempotency, hash slot semantics, role-boundary reset",
	"open": "cross-role-boundary value passing — revisit post-V1.0"
}}
~~~

`%chain` is the call-frame chain — the linked sequence of frames from the engine entry point down to the currently-executing frame. Every Caspian call adds a link; every return removes one. Every global method lives on `%chain`; capability state is per-frame; ambient context is per-frame; the chain mechanism is what makes "what's reachable here?" a single answer.

## What `%chain` does

1. **Gives every frame its own `%chain`.** Changes made to the chain (grants, revokes, hash assignments) propagate downward only. Descendants see the changes; the parent frame sees its chain exactly as it was before the call. When the subroutine returns, the changes go with it. This is the underpinning property — everything else on this list depends on it. See [Frame inheritance](#frame-inheritance) for the details.
2. **Holds the global methods.** Everything under [`methods/`](methods/) — `%chain.net`, `%chain.tmp`, `%chain.encryption`, etc. — is canonically `%chain.X`. The bare `%X` forms (for the surfaces that have them) resolve through the same chain entries.
3. **Gates capability propagation.** When a frame calls into a different role, the new frame's chain reflects what the calling frame has handed across. Grant and revoke happen on the capabilities themselves.
4. **Carries ambient context.** Arbitrary values can be attached to a frame; descendants see them; a role boundary resets them.
5. **Supports inspection.** Code can read who called it, how deep the stack is, what role is on each frame.

## Frame inheritance

Every change to `%chain` — grants, revokes, hash assignments — is **scoped to the current frame**. When that frame returns, the parent's view of `%chain` is exactly what it was before the call.

~~~caspian
function &foo()
	%chain['request_id'] = 'abc'   # foo's frame stores this
	return null
end

# Caller frame:
&foo()                             # foo runs and returns
%chain['request_id']               # null — foo's assignment didn't propagate up
~~~

This makes chain reasoning local: a frame can mess with its descendants' chain however it likes without affecting its caller. The dual is also true — anything a descendant does is invisible up the stack.

(Grants and revokes work the same way but require a `do ... end` block — see [Grant and revoke](#grant-and-revoke) below. Hash assignments are the only form of chain mutation that doesn't need block scope, since the frame itself supplies the scope.)

## Two layers of grant

Every global method goes through two grant decisions before code can reach it:

1. **The engine grants the surface at startup.** Nothing on this page is automatically present. The host (CLI launcher, embedded runtime, custom host) decides per-surface what to provision. If the engine didn't grant `%chain.net`, no amount of `%chain.X.grant` later can conjure it.

2. **The chain grants the surface across role boundaries.** Once a surface is in the engine, the user's chain has it. Whether descendants see it depends on the **default-grant** annotation:
   - **Default-granted across boundaries** (`%chain.puck`, `%chain.encryption`, `%chain.timeout`, `%chain.timer`, `%chain.steps`) — flows automatically to anything the user calls.
   - **Default-deny** (everything else) — descendants get an empty slot until the user explicitly hands it down.

See the catalog at [methods/](methods/) for which surface is which.

## Grant and revoke

`%chain.X.grant` and `%chain.X.revoke` let a frame hand specific capabilities to (or withhold them from) the descendant frames it calls into. Both take a `do ... end` block; the grant or revoke is active inside the block and gone the moment execution leaves it. There is no persistent-grant form.

Three forms exist — per-capability, multi-capability, and role-targeted — covered in the full spec at [`grant-revoke`](grant-revoke).

## Ambient hash slot

`%chain` doubles as a hash for arbitrary ambient values, **descending only into methods of the same role**. At a role boundary, the hash slot is emptied — values set by the caller are not visible to a callee running under a different role.

~~~caspian
%chain['request_id'] = '550e8400-e29b-41d4-a716-446655440000'

# later, deep in the call tree (same role):
$id = %chain['request_id']

# but inside a call into a different role:
# %chain['request_id'] returns null — the slot was emptied at the boundary
~~~

Rules:

- **Per-frame inheritance within a role.** Values set in a frame are visible to descendant frames running in the same role; a descendant that sets the same key creates its own scoped value that disappears when the descendant returns.
- **Role boundaries empty the slot.** Any call that crosses into a different role starts the new frame with an empty hash slot. The caller's values do not carry across.

For V1.0 we don't allow passing chain values across role boundaries. We can revisit that policy post-V1.0 once the threat model is clearer.

## Role boundaries reset everything

Whenever a call crosses a role boundary (anything where the role changes from caller to callee), the new frame's chain reflects:

- **Default-granted capabilities only.** Default-deny capabilities are gone unless the caller used `.grant` to hand them across the boundary.
- **No hash values** (for V1.0).
- **No record of the caller's grants.** The callee can't introspect what the user revoked or what was hidden from it.

This includes the return-to-user case — when non-user code invokes a user-supplied closure, the closure runs as user with a clean chain. The user's pre-boundary context isn't restored; the closure has to receive what it needs explicitly (via arguments, via lexical capture).

## Inspection

`%chain` itself does not carry chain-frame inspection methods. **The current frame's role is available as [`%role`](https://puck.uno/requirements/roles/#role) — a top-level global, not a chain surface.** `%role` is always unconditionally available regardless of what the chain carries. Frame-walking accessors (a full frames array, a parent-frame shortcut) are not part of V1.

## Complete catalog

Every method that lives on `%chain`. Each method's surface is documented per-method under [`methods/`](methods/); inspection methods are documented in the section above.

| Method | Shortcut | Default-granted | Kind | Description |
|---|---|---|---|---|
| [`%chain.argv`](methods/argv) | | no | capability | Command-line arguments. |
| [`%chain.encryption`](methods/encryption) | | **yes** | capability | Ed25519 signing, SHA hashing, HMAC. |
| [`%chain.env`](methods/env) | | no | capability | Read-only environment-variable accessor. |
| [`%chain.forks`](methods/forks) | | no | capability | Spawn forked child processes. |
| [`%chain.net`](methods/net) | | no | capability | Networking — HTTP client, sockets, UDS. |
| [`%chain.puck`](methods/puck) | `%fetch` | **yes** | capability | Object download by URL. `%(url)` is the further-shortened form. |
| [`%chain.stderr`](methods/stdout-and-stderr) | `%stderr` | no | capability | Diagnostic-output channel. |
| [`%chain.stdin`](methods/stdin) | `%stdin` | no | capability | The program's input channel. |
| [`%chain.stdout`](methods/stdout-and-stderr) | `%stdout` | no | capability | Primary output channel. |
| [`%chain.steps`](methods/steps) | | **yes** | capability | Count Caspian-level evaluation steps. |
| [`%chain.timeout`](methods/timeout) | | **yes** | capability | Limit a block's wall-clock duration. |
| [`%chain.timer`](methods/timer) | | **yes** | capability | Measure elapsed time around a block. |
| [`%chain.tmp`](methods/tmp) | | no | capability | Fresh temp dirjail per access. |

The capability layer is gated by **two** decisions: the engine grants the surface at startup (if it doesn't, the surface isn't there at all), and the chain grants it across role boundaries (default-grant flag, or explicit `%chain.X.grant`). See [Two layers of grant](#two-layers-of-grant) above.

**Not on the chain: clock and randomness.** Timestamps and random values are downloadable core objects, not chain-mediated capabilities. Reach them via `%('core:now')` and `%('core:random')` — `%(...)` is the shorthand for `%fetch(...)`. Each call returns a fresh object. No grant machinery; if a role can `%fetch`, it can read the clock or draw randomness.

## Where the rest of the spec lives

- Each global method has its own page documenting its surface and whether it's default-granted across boundaries.
- The [role catalog](../roles/) defines what roles exist and what crosses a "role boundary."
- The detailed jasmine ambient-logging system (which rides on `%chain` hash slots) is at [requirements-old/caspian/packages/jasmine/caspian](https://puck.uno/documentation/requirements-old/caspian/packages/jasmine/caspian) <!-- outbound-link-allowed --> pending migration.

## Implementation notes

The naïve way to implement `%chain` — give each frame its own deep copy of the inherited hash — is expensive at every call. Caspian frames are cheap; copying the chain's hash on every call would make them not cheap.

A general "inherits-downward-but-not-upward" hash structure handles the chain's hash slot AND the grant/revoke state AND any other downward-only inheritance pattern Caspian ends up needing. The recommended approach in the Lua reference engine is a **stack of hashes**.

### The data structure

A `chain_hash` object is an array of small hashes:

```
[
  { foo: "a" },           # bottom — set by frame 1
  {},                     # frame 2 (set nothing locally)
  { foo: "b", bar: "c" }, # top — set by current frame
]
```

Lookup `chain_hash['foo']`:

1. Walk the array from the **bottom up** — start at the last (most recent / current frame) element and work back toward the first.
2. First hash that has the key wins; return its value.
3. If no hash on the stack has the key, return `nil`.

Lookup `chain_hash['foo']` in the example above returns `"b"` (from the top frame's local hash), not `"a"`. Lookup `chain_hash['bar']` returns `"c"`. Lookup `chain_hash['baz']` returns `nil`.

### The operations

- **New frame.** Push an empty hash onto the array. O(1).
- **Frame return.** Pop the top hash. O(1). Everything the frame wrote is discarded; the caller's view is exactly what it was.
- **Read.** Walk bottom-up (current-frame-first) for the key. O(depth-to-key) — typically very small, because most reads find the key in the local frame's hash or in a nearby ancestor.
- **Write `chain_hash[key] = value`.** Write only to the **top** hash. O(1). Never modifies any ancestor frame's hash, so the caller's view is unaffected.
- **Role boundary.** Push a sentinel that hides everything below (a marker the lookup recognizes to stop walking). The new frame starts with an effectively-empty chain. When the boundary frame returns, the sentinel pops; the caller's view is restored.

### Why this generalizes

The same data structure handles `%chain`'s hash AND the grant/revoke state. Granting a capability is the same shape as setting a chain hash key: write `{net: granted}` (or some sentinel) to the top frame's hash. Revoking is writing `{net: revoked}`. The lookup logic for "is X granted in the current frame?" is the same bottom-up walk, with the first matching entry winning. Default-grant becomes the bottom-of-stack initial state.

Anywhere Caspian needs "inherits downward, never modifies parent, evaporates on return," this same `chain_hash` library (or its equivalent in another host language) is the right backbone.

### Cost characteristics

- Memory: O(total writes across all live frames). Empty frames cost a near-zero per-frame hash. Frames that wrote nothing don't bloat memory.
- Allocation: one small hash per frame push.
- Reads: in practice O(1) — depth-to-key is dominated by "most reads find the key in a nearby frame." Pathological deep-stack reads are O(depth) but rare.
- Writes: O(1).

The naïve "copy the parent's hash" approach is O(parent hash size) per frame push, plus the entire chain hash sits in memory per frame. For programs with non-trivial chain state and deep call stacks, that's prohibitive.

## Testing

- **Frame inheritance: descendant sees ancestor value** — a caller sets `%chain['id'] = 'x'` then invokes a same-role subroutine; the subroutine reads `'x'` via `%chain['id']`.
- **Frame inheritance: descendant assignment invisible to caller** — a callee's `%chain['x'] = 'v'` does not appear in the caller's view after the callee returns.
- **Frame inheritance: local shadow of ancestor value** — a descendant writing the same key creates a locally-scoped value that disappears on descendant return; the ancestor's value is unchanged.
- **Frame inheritance: hash assignment needs no block** — unlike grant/revoke, `%chain['k'] = 'v'` mutates the current frame directly.
- **Missing key returns null** — reading `%chain['nonexistent']` returns null, not raise.
- **Global methods accessible via `%chain.X`** — `%chain.puck`, `%chain.net`, `%chain.tmp`, and every catalog entry are addressable through the chain.
- **Shortcut form equivalent to `%chain.X`** — for surfaces with a bare shortcut (`%stdout`, `%fetch`, `%stderr`, `%stdin`), the shortcut and `%chain.X` return the same value.
- **Engine-startup grant gates presence** — if the host does not install `%chain.net` at startup, calling `%chain.net` raises even inside a grant block; no chain-level operation conjures a withheld surface.
- **Default-granted list** — `%chain.puck`, `%chain.encryption`, `%chain.timeout`, `%chain.timer`, `%chain.steps` cross role boundaries automatically.
- **Clock and randomness are downloads** — `%('core:now')` and `%('core:random')` reach the clock and RNG; no `%chain.now` or `%chain.random` slot exists.
- **Default-deny list** — every other catalog entry (`%chain.net`, `%chain.tmp`, `%chain.stdout`, `%chain.stdin`, `%chain.stderr`, `%chain.argv`, `%chain.env`, `%chain.forks`) is unreachable in a callee of a different role unless explicitly granted.
- **Full catalog rows verified** — every method in the table exists, its shortcut is correct, its default-grant flag matches, and its `Kind` is `capability`.
- **Same-role descent preserves hash slot** — a same-role subroutine sees the caller's ambient hash values.
- **Role boundary empties hash slot** — a call into a different role starts the callee with an empty `%chain` hash; the caller's values are not carried.
- **Role boundary drops default-deny capabilities** — a callee in a different role starts with only the default-granted surfaces available.
- **Role boundary hides caller's grants** — the callee cannot introspect what the caller revoked or hid; only the callee's own view is visible.
- **Return-to-user via closure gets a clean chain** — when non-user code invokes a user-supplied closure, the closure runs as `user` with default-granted only, no hash values, and no leaked grants; the user's pre-boundary context is NOT restored.
- **`%role` reflects current frame** — `%role` returns the current frame's role regardless of chain state.
- **`%role` always available** — even a frame that had every capability revoked can still read `%role`.
- **`%role` is not a chain slot** — accessing `%chain.role` or `%chain['role']` does NOT return the current role; `%role` is a distinct top-level global.
- **No frame-walking accessors in V1** — a parent-frame shortcut or full frames array is not part of V1.
- **Chain-hash lookup bottom-up** — with `{foo: 'a'}` at the base and `{foo: 'b'}` at the top, `%chain['foo']` returns `'b'`.
- **Empty frames cost near-zero memory** — a chain of 100 frames that write nothing does not allocate 100 populated hashes.
- **Frame push adds empty hash** — entering a frame pushes an empty hash; no values seeded.
- **Frame return pops the top hash** — after return, the caller's view is exactly what it was before the call.
- **Write only writes to top frame** — `%chain['k'] = 'v'` inside a callee never mutates an ancestor's hash.
- **Grant state uses the same stack** — a granted capability is resolved by the same bottom-up walk that resolves hash keys.
- **Role-boundary sentinel hides ancestors** — crossing into a different role pushes a sentinel that stops the walk from reaching the caller's values.
- **Sentinel pops on boundary-frame return** — when the boundary frame returns, the caller's chain view (grants included) is fully restored.
- **Default-grant is the base of the stack** — the base frame reads engine-granted surfaces as if written into the bottom hash.
- **`%chain` inspection surface is minimal** — only `%role` (elsewhere) and the hash-slot / grant / revoke methods; no chain-walking accessors ship in V1.
