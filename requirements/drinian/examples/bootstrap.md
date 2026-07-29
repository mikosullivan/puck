# Bootstrap state

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_examples_bootstrap",
	"role": "worked Drinian snapshot showing the minimum state immediately after engine bootstrap, before any statement dispatches; single top-level frame, engine and user roles seeded, no exceptions, no sources",
	"status": "draft — the shape a V1 engine produces just before running its first fixture"
}}
~~~

The state of Drinian at the moment `engine.bootstrap()` completes and before any statement dispatches. This is the **minimum** Drinian — what a V1 engine produces just before running its first fixture.

Hand-written CaspM fixture:

~~~json
[[{"value": "hello"}, "to_string"]]
// CAPTURED BEFORE THIS STATEMENT DISPATCHES
~~~

There's no in-source pause line for this state — bootstrap finishes *between* setup and the first dispatch. The fixture isn't transpiled from Caspian source either, so no `srcs` entries exist; every value later born from this fixture will be born without a `src` tag.

The Drinian hash:

~~~json
{
	"srcs": {},
	"roles": {
		"engine": {
			"bucket": {
				"stdin": {"ref": "obj_3"},
				"stdout": {"ref": "obj_4"},
				"stderr": {"ref": "obj_5"}
			}
		},
		"user": {
			"bucket": {}
		}
	},
	"call_stack": [
		{
			"action": "top_level",
			"role": "user",
			"lexical_parent": null,
			"src": null,
			"locals": {}
		}
	]
}
~~~

What to notice:

- **No `pending_exceptions` field needed.** Exceptions live in `call_stack` only when one is in flight. Bootstrap has none.
- **`srcs` is empty** because hand-written CaspM has no source files to register.
- **`src: null`** on the top_level frame for the same reason — no Caspian source line to point at.
- **Two roles in the registry.** `engine` for the host-process boundary (stdin/stdout/stderr live here because the engine is what wraps the host's file descriptors); `user` for the program's execution context. Roles live in Drinian as `state.roles`. <!-- SPEC CONFLICT: archive lists four bootstrap roles (engine, user, stdlib, puck); current spec has only user + engine + one role per engine-provided faucet per roles/index.md — needs Miko decision on which roles seed Drinian at bootstrap -->
- **Each role has a `bucket`.** A role's bucket is its private store of role-owned resources — conceptually the same shape as an object's bucket (see [built-in-classes/object/structure](https://puck.uno/requirements/built-in-classes/object/structure)), but scoped to a role rather than an object. Code running as a role reads its own bucket directly; reading another role's bucket is a cross-role access.
- **The I/O refs live on the engine's bucket.** `obj_3` / `obj_4` / `obj_5` are the singular stdin, stdout, stderr objects. User code reaches them through the chain-mediated capabilities (`%stdout`, `%stdin`, `%stderr`) — see [chain/methods/stdout-and-stderr](https://puck.uno/requirements/chain/methods/stdout-and-stderr) and [chain/methods/stdin](https://puck.uno/requirements/chain/methods/stdin). <!-- SPEC CONFLICT: archive puts stdin/stdout/stderr into BOTH engine.bucket and stdlib.bucket as shared refs; current spec has no stdlib role and provisions I/O through the chain capability layer — needs Miko decision on where the I/O refs anchor in Drinian -->
- **No `classes` field in Drinian.** Built-in classes (string, etc.) are loaded into engine-private state during bootstrap — see [drinian § Classes are NOT in Drinian](https://puck.uno/requirements/drinian/#classes-are-not-in-drinian). The string class exists and is dispatched against, but it lives in the engine's private class registry, not in the snapshot.
- **Empty `locals` and empty `chain`.** No bindings yet, no chain writes yet.
- **One frame, with `action: "top_level"`.** The outermost execution context the engine pushed during bootstrap.
