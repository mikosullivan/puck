# Grant and revoke
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_chain_grant_revoke",
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

`%chain.role.grant($role, :caps...)` grants capabilities to roles, not frames. See the full spec in [roles § Granting capabilities to other roles](https://puck.uno/documentation/requirements/caspian/roles/#granting-capabilities-to-other-roles).

## Rules

- **The do/end block on the `.grant` call IS the lifetime.** Every grant form takes a do/end block (e.g., `%chain.net.grant do ... end`); the grant is active for the duration of that block and evaporates when the block exits — whether via normal completion, early return, or an unwound exception. There is no persistent-grant form. Inside the block, the grant applies to the current frame and to every descendant frame that stays in the same role; crossing a role boundary still resets per the "Grants don't chain across role boundaries" rule below.
- **Idempotency.** Both `.grant` and `.revoke` are silent no-ops when the chain already reflects the requested state. Defensive code can call either without checking first.
- **Can't grant what you don't have.** Calling `.grant` on a capability the current frame doesn't possess raises. Granting requires possession.
- **A parent's revoke can't be undone by descendants.** Because granting requires possession and the descendant doesn't possess what was revoked, the revoke is enforceable, not just advisory.
- **Grants don't chain across role boundaries.** A grant to role `A` doesn't follow `A` into a method call that crosses into role `B` — `B` starts the call with its own default-grant set, not whatever `A` was carrying. If `B` needs the capability too, the grant has to be regranted at that boundary (typically with a fresh `%chain.role.grant($b_role, :caps)` block inside `A`'s frame, or with the non-targeted forms granting across the wider scope). Default-granted capabilities are the only ones that automatically traverse role boundaries; everything else is per-boundary opt-in. See [chain § Role boundaries reset everything](https://puck.uno/documentation/requirements/caspian/chain/#role-boundaries-reset-everything) for the full reset rule.
