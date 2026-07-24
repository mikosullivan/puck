# Grant and revoke
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_chain_grant_revoke",
	"role": "spec for granting and revoking %chain capabilities — the three forms (per-capability, multi-capability, role-targeted), the block-only lifetime rule, and the rules that govern them. Companion to chain/index.md (which mentions the feature and links here).",
	"audience": "developers writing code that grants downstream-role access to chain capabilities; engine implementers; AI tooling reasoning about capability flow"
}}
~~~

Every grant form **takes a do/end block** — and that block is the grant's entire lifetime. The grant is active inside the block and gone the moment execution leaves it. There is no persistent-grant form; no "remember to revoke" obligation.

Three forms exist for ergonomic reasons; all use the same do/end-block shape.

## Per-capability form

~~~caspian
%chain.net.grant do
	$lib.do_thing()
end
~~~

Grants one capability for the block. The capability is named by addressing it as a slot on `%chain` and calling `.grant`. Revoke is symmetric:

~~~caspian
%chain.tmp.revoke do
	$lib.do_thing_without_tmp()
end
~~~

## Multi-capability form

When several capabilities want to be granted for the same block, the per-capability form would nest; use the multi-capability form instead:

~~~caspian
%chain.grant(:net, :tmp, :stdout) do
	$lib.do_thing()
end
~~~

Names the capabilities as symbols. Equivalent in semantics to three nested per-capability grants, just without the visual nesting. Same applies to revoke:

~~~caspian
%chain.revoke(:net, :tmp) do
	...
end
~~~

## Role-targeted form

`%role.delegate_to($role) do ... end` extends the current frame's capabilities to a target role for the block. See the full spec in [roles § Granting capabilities to other roles](https://puck.uno/documentation/requirements/roles/#granting-capabilities-to-other-roles).

## Rules

- **The do/end block on the `.grant` call IS the lifetime.** Every grant form takes a do/end block (e.g., `%chain.net.grant do ... end`); the grant is active for the duration of that block and evaporates when the block exits — whether via normal completion, early return, or an unwound exception. There is no persistent-grant form. Inside the block, the grant applies to the current frame and to every descendant frame that stays in the same role; crossing a role boundary still resets per the "Grants don't chain across role boundaries" rule below.
- **Idempotency.** Both `.grant` and `.revoke` are silent no-ops when the chain already reflects the requested state. Defensive code can call either without checking first.
- **Can't grant what you don't have.** Calling `.grant` on a capability the current frame doesn't possess raises. Granting requires possession.
- **A parent's revoke can't be undone by descendants.** Because granting requires possession and the descendant doesn't possess what was revoked, the revoke is enforceable, not just advisory.
- **Grants don't chain across role boundaries.** A grant to role `A` doesn't follow `A` into a method call that crosses into role `B` — `B` starts the call with its own default-grant set, not whatever `A` was carrying. If `B` needs the capability too, delegation has to happen at that boundary (typically with a fresh `%role.delegate_to($b_role) do ... end` block inside `A`'s frame). Default-granted capabilities are the only ones that automatically traverse role boundaries; everything else is per-boundary opt-in. See [chain § Role boundaries reset everything](https://puck.uno/documentation/requirements/chain/#role-boundaries-reset-everything) for the full reset rule.

## Testing

- **Per-capability grant activates the surface** — inside `%chain.net.grant do ... end`, a same-role subroutine sees `%chain.net` as granted.
- **Per-capability grant evaporates on block exit (normal completion)** — after the do/end block runs to completion, the frame no longer possesses the capability if it didn't have it before.
- **Per-capability grant evaporates on early return** — a `%call.return` from inside a grant block still evaporates the grant on the way out.
- **Per-capability grant evaporates on raised exception** — an exception unwinding through the block still evaporates the grant.
- **Per-capability grant evaporates on normal fall-through** — a block whose last statement completes normally evaporates the grant with no extra action needed.
- **Per-capability revoke is symmetric** — `%chain.tmp.revoke do ... end` withholds `%chain.tmp` inside the block and restores it on exit.
- **Revoke evaporates on all block exit modes** — normal completion, early return, and exception unwinding all restore the revoked capability.
- **Multi-capability grant activates all named capabilities** — `%chain.grant(:net, :tmp, :stdout) do ... end` grants all three inside the block.
- **Multi-capability grant is equivalent to nested per-capability grants** — the surface state inside matches three nested `.grant` blocks.
- **Multi-capability revoke** — `%chain.revoke(:net, :tmp) do ... end` withholds both for the block and restores on exit.
- **Role-targeted delegation `%role.delegate_to`** — `%role.delegate_to($role) do ... end` extends the current frame's capabilities to a target role rather than a frame; see the role spec for its full semantics.
- **Grant is silently idempotent** — calling `.grant` for a capability the frame already possesses is a no-op, not a raise.
- **Revoke is silently idempotent** — calling `.revoke` for a capability the frame doesn't have is a no-op, not a raise.
- **Multi-capability grant of already-possessed set is idempotent** — `%chain.grant(:net, :tmp)` in a frame that already has both is a no-op.
- **Can't grant what you don't have (single)** — calling `%chain.net.grant do ... end` in a frame that lacks `%chain.net` raises before entering the block.
- **Can't grant what you don't have (multi)** — `%chain.grant(:net, :tmp) do ... end` where the frame lacks either capability raises before entering the block.
- **Descendant can't undo parent revoke** — inside `%chain.net.revoke do ... end`, a descendant that tries `%chain.net.grant` raises because it doesn't possess `net`.
- **Parent revoke is enforceable, not advisory** — the enforceability follows from the "can't grant what you don't have" rule; there's no back door for descendants.
- **Grant flows to same-role descendants** — a same-role callee invoked from inside a grant block sees the granted capability.
- **Grant does not cross a role boundary** — a callee running under a different role starts with its own default-grant set, not the block's granted capability.
- **Role-targeted delegation needed for cross-role capability sharing** — inside a parent frame, `%role.delegate_to($b_role) do ... end` extends the parent's capabilities to role B across the boundary.
- **Default-granted capabilities cross role boundaries without help** — `%chain.now`, `%chain.puck`, etc. remain reachable across boundaries without any explicit grant.
- **No persistent-grant form exists** — there is no `.grant_forever` or grant-without-block; every grant is block-scoped.
- **No revoke-obligation on the developer** — the developer never has to remember to revoke; block exit handles it.
- **Nested grants compose** — an outer grant of `:net` and an inner grant of `:tmp` gives the inner block both capabilities; leaving the inner block drops `:tmp`; leaving the outer drops `:net`.
- **Nested revoke shadows outer grant** — an outer grant of `:net` and an inner revoke of `:net` withholds `:net` inside the inner block; the outer grant resumes when the inner block returns.
- **Grant plus revoke in the same frame** — a frame can grant one capability and revoke another for the same descendant call by using both blocks (nested or sequential).
- **Grant block yields the block's value** — the do/end block on `.grant` participates in expression evaluation; the block's last-expression value is the grant expression's value.
- **Grant with empty block is legal** — `%chain.net.grant do end` activates and immediately deactivates without raising.
- **Grant does not leak into sibling frame** — after `%chain.net.grant do end` returns, a subsequent sibling call in the same parent frame does not see `net` granted.
- **Grant blocks are re-entrant** — a grant block invoked twice in sequence works both times; there is no one-shot restriction.
- **Grant/revoke interact with `%role`-scoped delegation** — a `%role.delegate_to` targeting a role and a `%chain.X.grant` in the current frame produce compatible state; neither shadows the other unexpectedly.
- **Grant respects the two-layer rule** — attempting to grant a capability the engine never installed at startup raises regardless of whether the frame possesses the (non-existent) capability.
