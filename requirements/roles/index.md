# Roles
<!--index: 6 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_roles",
	"role": "spec for Caspian's role system — the identities code runs under. Owns the role catalog (user, engine, plus one role per engine-provided faucet), the mechanism of role objects and switching, and the relationship between roles and capabilities.",
	"status": "settled at the concept level — user + engine + one role per engine-provided faucet (per plumbing/faucets); post-V1 candidates (stdlib distinction, forks role semantics, request/agent identity roles) remain deferred",
	"audience": "engine implementers who will eventually have to enforce this; AI tooling reasoning about who can do what"
}}
~~~

A **role** is the identity that owns currently-executing code. Every frame on the call stack has a role; switching between frames may switch the role. Roles are the unit of capability gating, output attribution, and audit.

## What roles are for

Four purposes, listed in order of how load-bearing each one is:

1. **Capability gating.** A surface is reachable only from roles that have been granted the capability. The blanket gate on [`%engine`](../engine/) (user-only) is the strongest example; finer-grained gating on individual `%`-prefixed globals is more typical.
2. **Provenance.** Code's identity travels with it. When something happens — output written, exception raised, object downloaded — we can answer "who did that?" by reading the role.
3. **Output attribution.** Bytes written to `%stdout` and `%stderr` are stamped with the producing role. Hosts can route or filter on that stamp.
4. **Audit.** Logs, traces, and the `%engine.manifest` carry role information without code having to thread it through every call.

The whole point of roles is to make these four purposes work with **no opt-in from the caller**. User code doesn't have to remember to identify itself to non-user code; the role is already attached to the frame.

## The `user` role

The `user` role is the program's own code. The first statement of the program runs as `user`.

`user` is special — it's the **only role that can call `%engine`**. Every slot on `%engine` is reachable only from `user`-role code; any other role reaching for `%engine` gets a runtime error. That makes `user` the closest analog Caspian has to a Unix `root`: it owns the gateway to host resources, and everything else has to go through code that runs as user to reach them.

The privilege is **not** a property of the user — it's a property of the role. When other roles need a specific user capability (once those roles exist), the right pattern is **role-targeted grants** — see [Granting capabilities to other roles](#granting-capabilities-to-other-roles) below. The user grants specific capabilities to the non-user role for a block, scoped to that block. There is no role-acquisition surface; the grant mechanism is the only path.

Identifying the user role: it carries a stable name (`user`) the engine knows by string, not a generated ID. There's only ever one `user` role per engine.

## Role names are convenience labels

**Only `user` is a required name.** The name `user` is the one string identifier the runtime treats as significant — that role always exists, always has `%engine` access, and always runs the program's first statement. Everything else about role names is presentation, not spec.

Every other role in the system has a name too, but those names exist for **readable diagnostics, logs, and documentation** — the runtime compares role references by identity (per [Comparing role references](#comparing-role-references)), not by matching strings. Some roles happen to get memorable names because they're referenced often — the engine role, the individual faucet roles (stdin, argv, net, etc.). Others may end up with generic labels like `faucet_1`, `faucet_2` if a concrete short name doesn't add clarity.

In examples in this spec (see [object-access § Class instantiation is not an exception](object-access#class-instantiation-is-not-an-exception) and elsewhere), a placeholder like `faucet_1` stands in for "some non-user role" without implying the role has any particular category or catalog entry. The mechanics — creator-owns, holding-is-access, methods-run-as-object's-role — don't depend on the role's name.

## Core roles

V1 has two program-frame roles (`user`, `engine`) plus one role per engine-provided faucet. Other candidates (`stdlib` distinction, `request`, `agent`, fork behavior, etc.) remain deferred — see [Deferred until post-V1](#deferred-until-post-v1) at the bottom.

### `user`

Already covered above. The program's own code; the only role with `%engine` access.

### `engine`

The engine itself, when it produces output not on behalf of user code. A panic trace, an internal diagnostic, a "you hit a TODO" message — bytes written by the engine itself rather than by any frame the user wrote. Hosts can choose to suppress engine-role bytes in production and surface them in development.

`engine` is the only role that doesn't run user-program frames. It exists for attribution.

### One role per engine-provided faucet

Every engine-provided faucet has its own distinct role, and every value that comes through the faucet is owned by that role. For the enumeration of faucets, the model of how narrowing works, and why the role count stays bounded, see [plumbing/faucets](https://puck.uno/requirements/plumbing/faucets/) — that page owns the catalog.

These roles never run program frames — the code executing is always some `user`/`engine`/downloaded-object role. Faucet roles exist for **value provenance**: an audit or capability check asking "where did this string come from?" reads the value's role and gets a definitive source name.

## Objects also have roles

Roles aren't just for code — every **object** in the runtime carries an owning role too, set at creation, immutable thereafter. A string created by user code is user-owned.

Objects can flow between roles once other roles exist (per the faucet decision). **Holding an object is not the same as owning it** — the owner is stamped on the value at creation and travels with the value regardless of where it's held.

Why this matters: ownership determines what a non-owning role is allowed to DO with an object — call methods, mutate state, hand it onward. That's the [object-access spec](object-access).

## Role references

When code needs to refer to a role — to compare identities, to use as a grant target, to pass as an argument — it works with **role objects**: small first-class objects that represent a role. A role reference is a variable holding one of these role objects.

A role object is NOT a string. It's an object with methods (`==`, `.current?`, etc.). The role's *name* is a string the object exposes (and you can read it for display), but the object itself is what you compare and pass around. Treating a role as a string — comparing by name, building from a name — bypasses the role system and isn't supported.

### `%role`

`%role` is the top-level global that returns the role reference for the **current frame**. It is **always unconditionally available** — no default-grant to check, no capability check to make, no chain state to inspect. Every frame, in every role, can read `%role` and get back a role object.

`%role` is a language primitive; it does **not** live on `%chain`. Chain-scoped state (grants, ambient hash, capability slots) resets at role boundaries; `%role` doesn't — it's the accessor for whichever role the current frame is running under, and its value is set by the frame's identity, not by chain state.

`%role.delegate_to($target_role) do ... end` temporarily extends the current frame's capabilities to a target role for the block's duration, riding the chain grant mechanism under the hood. See [Granting capabilities to other roles](#granting-capabilities-to-other-roles) below for full semantics.

### Getting a role object from an object

The primary mechanism: `$obj.object.role` on any object returns the role object that owns it.

~~~caspian
$role = $some_object.object.role
%role.delegate_to($role) do
	$some_object.do_thing()
end
~~~

This works for any code that holds the object. Reading the role doesn't grant any permissions — it just tells you whose object it is.

For delegation, this is usually enough: you delegate to the role that's actually going to USE the capability, which means you have an object owned by that role somewhere in your code. The general pattern is **get the role from the object that the delegation target will use**.

### User-only enumeration

The `user` role has broader access via `%engine.roles`, which returns every role currently registered with the engine. Non-user code cannot reach `%engine` and so cannot enumerate roles.

~~~caspian
%engine.roles.each do ($role)
	# iterate every role known to the engine
end
~~~

**V1 limitation: this doesn't actually do much.** A role reference in V1 is mostly an identity handle — you can compare it (equality, identity), use it as a grant/revoke target, and read its name (a string identifier). You cannot introspect the role's state, its held objects, its current permissions, or anything else about it. `%engine.roles` mainly exists for completeness and future use; in V1 it gives you a list of handles that you can't get much information from. The `$obj.object.role` pattern covers nearly every practical case.

### Comparing role references

A **role reference** is a handle to a role — a value you hold in code that points at one of the roles in the system. The `==` operator on role references asks one question: do these two references point at the same role?

~~~caspian
$s = 'hello'           # user-owned (created by user code)
$h = {a: 1}             # also user-owned

$role_of_s = $s.object.role
$role_of_h = $h.object.role

$role_of_s == $role_of_h   # true — both reach the user role
~~~

Both `.object.role` calls land on the same role (`user`), so the two references compare equal even though they were obtained from completely different objects.

The point: comparing references is reliable. Code that wants to check "is the caller's role the same as my role?" can do it by comparison:

~~~caspian
$caller_role = $passed_in_object.object.role
$my_role     = $my_own_object.object.role

if $caller_role == $my_role
	# caller is in the same role as me
end
~~~

Without this rule, code would have to compare role NAMES (strings), which is fragile — typos, naming-convention drift, ambiguity between roles with similar names. With `==` doing the right thing, comparing identities is one expression.

### `.current?`

Every role reference has a `.current?` method that returns true if the role it names is the role the calling frame is currently running in.

~~~caspian
if $some_object.object.role.current?
	# the calling frame is running in $role
end
~~~

This is convenience sugar — `$role == %role` would compute the same answer (compare the reference to whichever role the chain reports for the current frame). `.current?` is the named form for the question "am I running as this role right now?" because that question comes up often enough to deserve its own method.

Trivial to implement: the engine already knows the current role (it's what `%role` returns) and equality comparison is already defined. `.current?` is `==` against the current role under the hood.

## Methods run as their object's role

This is a central security feature of the system. When a frame calls a method on an object owned by a different role, **the method body runs as the object's owner** — not as the caller. The caller's role is unchanged; when the method returns, the caller's frame resumes with its original role.

The role boundary is enforced by the dispatch mechanism itself. A method defined on an object owned by some non-user role can't run as the user code that called it — it always runs as that object's owner. The user's `%engine` access doesn't leak across the method-call boundary, and the called object's restricted permissions apply to its own code regardless of who invoked it.

Roles themselves don't get traded, swapped, or modified. They're permanent identities; what changes between frames is which role the engine treats as "running right now," and that change is driven entirely by **which object's method is being called**.

(V1 has only `user`, so cross-role dispatch doesn't happen yet. `engine` doesn't run user-program frames either. The mechanism above is what will be in effect once other roles are spec'd.)

## How capabilities flow

Capabilities are granted **per role**, not ambient. A grant attaches a surface (e.g., `%chain.net`) to a role; code in frames with that role can reach the surface.

Grants flow down the call chain explicitly. When code calls into a different-role frame, the caller can pass capabilities through `%chain` — the new frame sees those capabilities as available; descendants see them too. When the caller doesn't pass a capability, the callee doesn't get it. The chain is the only way capabilities propagate.

The default grant set per role:

| Role | Default grants |
|---|---|
| `user` | `%engine`, everything the host has provisioned. |
| `engine` | N/A — engine doesn't run user-program frames. |

The "nothing by default" rule is doing most of the security work. The role catalog is just the vocabulary; with only `user` and `engine` committed, the vocabulary is intentionally narrow until faucets are spec'd.

## Granting capabilities to other roles

The V1 primitive for cross-role capability delegation is **`%role.delegate_to`**: temporarily extend the current frame's capabilities to a target role for the duration of a block. `%role` is the top-level accessor for the current frame's role; `.delegate_to` on it delegates everything the current role has to the target role.

~~~caspian
%role.delegate_to($agent.object.role) do
	$agent.act_as_me()
end
~~~

Inside the block, `$agent.object.role` gains every capability the granting frame currently has — including the default-granted ones. When the block exits, the extension lifts cleanly. The target's role identity doesn't change; only its permissions are temporarily broadened. Audit trails continue to attribute actions to the target role; the elevation is visible in source as the enclosing `delegate_to` block.

### Rules

- **Target lookup is by role identity, not by frame position.** If the target role never appears in the call tree inside the block, the delegation just sits unused — no error.
- **Can't delegate what you don't have.** The granting frame must possess each capability being delegated; delegation is bounded by what the granter currently holds.
- **Snapshots at the call site.** The set of capabilities delegated is whatever the granting frame has at the moment of the `%role.delegate_to` call. Adding capabilities to the granting frame inside the block does not retroactively expand the delegation.
- **Block-scoped only.** No persistent delegation — the extension lifts on block exit.
- **Composes with capability grants that flow through the chain.** A delegation and a `%chain.X.grant` can both be in effect for the same descendant frame; the descendant sees the union.

### Deferred: fine-grained grant and revoke

Post-V1, this section will grow forms for grant-specific-capabilities-only and symmetric revoke — `%role.grant($target, :net, :stdout) do ... end` and `%role.revoke($target, :net) do ... end`. V1 ships only `delegate_to` (all-or-nothing) to keep the surface small; the more granular forms wait until there's a forcing use case that `delegate_to` doesn't cover.

## What's settled

- The `user` role and its `%engine`-only privilege.
- The `engine` role for engine-emitted attribution.
- One role per engine-provided faucet, with the narrowing rules that come with it (see [plumbing/faucets](https://puck.uno/requirements/plumbing/faucets/)).
- The mechanism: role objects, `$obj.object.role`, `==` and `.current?`, the switch-at-frame-boundary rule.
- Cross-role capability delegation goes through the role-targeted grant on `%chain` ([#830](https://github.com/mikosullivan/puck/issues/830)), not through any role-acquisition surface.

## Deferred until post-V1

- Whether `stdlib` is a real role distinct from `user`.
- Whether forks behave with no-role-change semantics or with something more nuanced.
- Whether `request`, `agent`, or other identity-bearing roles are baked in.

Each of these is a separate design question, not blocked on any single other spec.

## Testing

- **`%role` returns the current frame's role reference** — inside the top-level program, `%role.name` is `'user'`.
- **The `user` role always exists** — `%role.name == 'user'` at program start.
- **`%role` is always available regardless of grants** — even a role with zero granted capabilities can read `%role`; no gate.
- **`%role` is a role object, not a string** — `%role.class` is not the string class.
- **`%role == 'user'` is false or raises** — comparison against a string doesn't match the role object.
- **`%role.name` returns the role's name as a string** — for the user role, `'user'`.
- **`user` is the only role that reaches `%engine`** — from a `user` frame, `%engine.argv` succeeds; from any non-user frame it raises.
- **Non-user role attempting any `%engine` slot raises** — the gate is blanket, not per-slot.
- **`engine` role does not run user program frames** — no user code runs under `engine`; the role exists for attribution.
- **`$obj.object.role` returns the object's owning role** — reading it grants no permissions.
- **Two role references to the same role compare equal via `==`** — `$s.object.role == $h.object.role` when both are user-owned.
- **`==` on role references compares identity, not name strings** — the check is by role identity.
- **`%role == %role` is true** — trivial identity.
- **`.current?` on the current frame's role reference is true** — `%role.current?` is `true`.
- **`.current?` on a non-current role reference is false** — points to a different role than the frame is running as.
- **A string literal's `.object.role` matches the creating frame's role** — literals in user code are user-owned.
- **A value pulled through a faucet has the faucet's role** — `%chain.stdin.read.object.role != %role`.
- **Faucet roles never run user program frames** — provenance only.
- **`%engine.roles` enumerates every registered role** — returns a list of role references.
- **`%engine.roles` from a non-user frame raises** — the blanket gate applies.
- **A role reference from a faucet-owned value is a valid delegation target** — `%role.delegate_to($str.object.role) do ... end` runs.
- **Cross-role dispatch runs the method as the object's owner** — calling `$other_role_obj.method()` from a `user` frame runs the method body under the object's owner role.
- **On method return, the calling frame's role is restored** — control returns to the caller with its original role.
- **Roles are permanent identities** — a role object compares equal to itself across the entire process lifetime.
- **User default grants: `%engine` plus everything the host provisioned** — a fresh `user` frame has full user-role access.
- **Non-user role default grants: empty** — nothing without an explicit delegation.
- **`%role.delegate_to($target) do ... end` extends grants to the target for the block** — inside the block, target frames see the granter's capabilities.
- **Delegation does not apply to other roles** — a frame running as some third role inside the block does not see the delegated capabilities.
- **Delegation snapshots at the call site** — adding capabilities to the granting frame inside the block does not retroactively expand the delegation.
- **Can't delegate what you don't have** — capabilities not held by the granting frame don't appear at the target either.
- **`%role.delegate_to`'s target lookup is by role identity** — if the target role never appears in the call tree, the delegation sits unused; no error.
- **`%role.delegate_to` is block-scoped only** — after the block ends, target loses the delegation.
- **Delegation composes with `%chain.X.grant`** — a descendant sees the union of both paths.
- **`%role` inside a downloaded object's method returns the object's owning role** — not `user`.
- **A role reference obtained via `.object.role` and one via `%role` compare equal when they name the same role** — regardless of retrieval path.
- **`%role.name` for a faucet role is a stable string identifier** — same value across reads.
- **`%role` does not appear on `%chain`** — reading `%chain.role` raises or is undefined; `%role` is a language primitive.
- **A role held in a variable and later used for delegation behaves the same as inline access** — capture doesn't change semantics.
