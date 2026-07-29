# `%chain`
<!--index: 8 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_chain",
	"role": "spec for %chain — the per-frame capability-permission store. Carries grants and revokes across role boundaries; supports the two-layer grant model (engine grants at startup, chain grants across role boundaries with a default-grant flag). This is all %chain does. It used to carry methods (%chain.net, %chain.tmp, etc.) and an ambient-hash slot; those responsibilities have moved (methods to downloadable core objects and top-level globals; ambient-hash slot to %amber, pending promotion from ideas/ambient-hash).",
	"status": "narrow scope — permissions only; broader capabilities (methods, ambient hash slot) have moved elsewhere or are being reworked",
	"audience": "Caspian engine implementers building the runtime; developers reasoning about capability propagation across role boundaries"
}}
~~~

`%chain` is the per-frame **capability-permission store**. Grants and revokes of capabilities live here; capability propagation across role boundaries happens here. That's the whole surface.

## What `%chain` no longer does

`%chain` used to be much bigger. Two responsibilities have moved:

- **Methods** — `%chain.net`, `%chain.tmp`, `%chain.encryption`, and the rest used to be canonical `%chain.X` surfaces. That's gone. The actual functionality lives elsewhere now (top-level globals like `%import`, downloadable core objects like `%('core:random')`, or its own file spec). `%chain` retains only the permission indicator for each capability, not the method surface.
- **Ambient hash slot** — the arbitrary-value ambient-context surface has moved to [`%amber`](../amber). If you're reading a doc that shows `%chain['key'] = value` for ambient context, that's stale content awaiting cleanup.

Any doc under [methods/](methods/) that still describes `%chain.X` methods is stale — being cleaned up in a separate sweep.

## Frame inheritance

Every grant, revoke, or capability-permission change applied to `%chain` is **scoped to the current frame**. When that frame returns, the parent's view of `%chain` is exactly what it was before the call. Chain reasoning is local: a frame can hand capabilities to its descendants (or withhold them) without affecting its caller, and any changes descendants make further down are invisible up the stack.

## Two layers of grant

Every capability goes through two grant decisions before code can reach it:

1. **The engine grants the capability at startup.** Nothing is automatically present. The host (CLI launcher, embedded runtime, custom host) decides per-capability what to provision. If the engine didn't grant a capability, no amount of `.grant` later can conjure it.

2. **The chain grants the capability across role boundaries.** Once granted by the engine, the user's chain has it. Whether descendants see it depends on the **default-grant** annotation on that capability:
   - **Default-granted across boundaries** — flows automatically to anything the user calls.
   - **Default-deny** — descendants get nothing until the user explicitly hands it down via `.grant`.

The full catalog of which capabilities are default-granted vs default-deny is being reworked as part of the broader `%chain` cleanup. Until it lands, individual capability docs are the source.

## Grant and revoke

Capabilities support `.grant` and `.revoke` operations that let a frame hand capabilities to (or withhold them from) descendant frames. Both take a `do ... end` block; the grant or revoke is active inside the block and gone the moment execution leaves it. There is no persistent-grant form.

Three forms exist — per-capability, multi-capability, and role-targeted. See [`grant-revoke`](grant-revoke) for the full spec.

## Role boundaries reset non-default-granted capabilities

Whenever a call crosses a role boundary (anything where the role changes from caller to callee), the new frame's chain reflects **default-granted capabilities only**. Default-deny capabilities are gone unless the caller used `.grant` to hand them across the boundary. The callee also cannot introspect what the caller revoked or hid — only its own view is visible.

This includes the return-to-user case: when non-user code invokes a user-supplied closure, the closure runs as `user` with a clean chain. The user's pre-boundary context isn't restored; the closure has to receive what it needs explicitly (via arguments, via lexical capture).

## `%role` is separate

The current frame's role is available as [`%role`](https://puck.uno/requirements/roles/#role) — a top-level global, not a chain surface. `%role` is always unconditionally available regardless of what capabilities the chain carries or has revoked. Frame-walking accessors (a full frames array, a parent-frame shortcut) are not part of V1.

## Implementation notes

The naïve implementation of `%chain` — give each frame its own deep copy of the inherited permission set — is expensive at every call. Caspian frames are cheap; copying the chain's state on every call would make them not cheap.

The reference implementation uses an [aggregate hash](../lua/aggregate-hash) — a stack of small hashes with bottom-up lookup, plus a sentinel mechanism for role boundaries. All operations are O(1) except lookup, which is O(depth-to-key) in the worst case, typically O(1) in practice (most permissions are set close to where they're read).

## Testing

- **Grant scoped to current frame** — a caller's `.grant` inside a `do ... end` block is visible to descendants but does not leak upward on block exit.
- **Grant in a block reverts when the block exits** — after the `do ... end` block, the granted capability is no longer available in the caller's frame.
- **Frame return removes grants applied in that frame** — a callee's grant inside its own frame is invisible to the caller after the callee returns.
- **Role boundary drops default-deny capabilities** — a callee in a different role starts without default-deny capabilities unless explicitly granted across the boundary.
- **Default-granted capabilities cross role boundaries automatically** — a capability marked default-granted is visible in a callee running under a different role, without any explicit grant.
- **Role boundary hides caller's grants** — the callee cannot introspect what the caller revoked or hid; only the callee's own view is visible.
- **Return-to-user via closure gets a clean chain** — when non-user code invokes a user-supplied closure, the closure runs as `user` with default-granted only, no leaked grants; the user's pre-boundary context is NOT restored.
- **`%role` reflects current frame** — `%role` returns the current frame's role regardless of chain state.
- **`%role` always available** — even a frame that had every capability revoked can still read `%role`.
- **Engine-startup grant gates presence** — if the host does not install a capability at startup, no chain-level operation can conjure it.
- **No frame-walking accessors in V1** — a parent-frame shortcut or full frames array is not part of V1.
