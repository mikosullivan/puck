# Example 01: Bootstrap state

~~~json
{"vibecode": {"example": "bootstrap_state",
	"shows": "minimum_skeletor_immediately_after_engine_bootstrap_before_any_dispatch",
	"shape": "single_top_level_frame_two_roles_no_srcs_no_exceptions",
	"slice_context": "what_aslan_ships"}}
~~~

The state of Skeletor at the moment `engine.bootstrap()` completes and
before any statement dispatches. This is the **minimum** Skeletor —
what an Aslan-era engine produces just before running its first
fixture.

Hand-written CaspianJ fixture:

```json
[[{"value": "hello"}, "to_string"]]
// CAPTURED BEFORE THIS STATEMENT DISPATCHES
```

There's no in-source pause line for this state — bootstrap finishes
*between* setup and the first dispatch. The fixture isn't transpiled
from Caspian source either, so no `srcs` entries exist; every value
later born from this fixture will be born without a `src` tag.

The Skeletor hash:

```json
{
  "srcs": {},
  "roles": {
    "user": {},
    "stdlib": {}
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
```

What to notice:

- **No `pending_exceptions` field needed.** Exceptions live in
  `call_stack` only when one is in flight. Bootstrap has none.
- **`srcs` is empty** because hand-written CaspianJ has no source
  files to register.
- **`src: null`** on the top_level frame for the same reason — no
  Caspian source line to point at.
- **Two roles in the registry.** `user` for the program's execution
  context; `stdlib` because the engine pre-loaded the string class
  during bootstrap and the string class is tagged with the stdlib
  role. Roles live in Skeletor as `state.roles`.
- **No `classes` field in Skeletor.** Built-in classes (string, etc.)
  are loaded into engine-private state during bootstrap — see
  [skeletor.md § Classes are NOT in Skeletor](../skeletor.md#classes-not-in-skeletor).
  The string class exists and is dispatched against, but it lives in
  the engine's private class registry, not in the snapshot.
- **Empty `locals` and empty `chain`.** No bindings yet, no chain
  writes yet.
- **One frame, with `action: "top_level"`.** The outermost execution
  context the engine pushed during bootstrap.
