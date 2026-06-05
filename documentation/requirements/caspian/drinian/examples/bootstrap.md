# Bootstrap state

~~~json
{"vibecode": {"example": "bootstrap_state",
	"shows": "minimum_drinian_immediately_after_engine_bootstrap_before_any_dispatch",
	"shape": "single_top_level_frame_two_roles_no_srcs_no_exceptions",
	"slice_context": "what_aslan_ships"}}
~~~

The state of Drinian at the moment `engine.bootstrap()` completes and
before any statement dispatches. This is the **minimum** Drinian —
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

The Drinian hash:

```json
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
    },
    "stdlib": {
      "bucket": {
        "stdin": {"ref": "obj_3"},
        "stdout": {"ref": "obj_4"},
        "stderr": {"ref": "obj_5"}
      }
    },
    "puck": {
      "bucket": {
        "fetchers": [
          {"ref": "obj_2"},
          {"ref": "obj_6"}
        ]
      }
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
```

What to notice:

- **No `pending_exceptions` field needed.** Exceptions live in
  `call_stack` only when one is in flight. Bootstrap has none.
- **`srcs` is empty** because hand-written CaspianJ has no source
  files to register.
- **`src: null`** on the top_level frame for the same reason — no
  Caspian source line to point at.
- **Four roles in the registry.** `engine` for the host-process
  boundary (stdin/stdout/stderr live here because the engine is what
  wraps the host's file descriptors); `user` for the program's
  execution context; `stdlib` for built-in class methods and the
  user-facing I/O surfaces; `puck` for library resolution (owns the
  fetcher chain accessed through the `%puck` system surface). Roles
  live in Drinian as `state.roles`.
- **Each role has a `bucket`.** A role's bucket is its private store
  of role-owned resources — conceptually the same shape as an
  object's bucket (the `%bucket` instance-variable store from
  [`syntax/system-methods.md`](https://puck.uno/documentation/requirements/caspian/syntax/system-methods)),
  but scoped to a role rather than an object. At bootstrap,
  `puck.bucket.fetchers` holds the fetcher chain as an array — order
  matters, each entry is a fetcher object, and resolution walks the
  array in order until one succeeds. `engine.bucket` and
  `stdlib.bucket` both hold stdin/stdout/stderr; `user.bucket` is
  empty (user code adds nothing here automatically). Code running as
  a role reads its own bucket directly; reading another role's
  bucket is a cross-role access.
- **The I/O refs are shared, not duplicated.** `obj_3` / `obj_4` /
  `obj_5` appear in both `engine.bucket` and `stdlib.bucket` —
  same objects, two surfaces. The engine holds them because the
  engine is the boundary to the host process; stdlib holds them
  because user code reaches I/O through stdlib's surface. There's
  only one stdin object, one stdout object, one stderr object — the
  matching refs make that explicit.
- **No `classes` field in Drinian.** Built-in classes (string, etc.)
  are loaded into engine-private state during bootstrap — see
  [drinian.md § Classes are NOT in Drinian](../index.md#classes-not-in-drinian).
  The string class exists and is dispatched against, but it lives in
  the engine's private class registry, not in the snapshot.
- **Empty `locals` and empty `chain`.** No bindings yet, no chain
  writes yet.
- **One frame, with `action: "top_level"`.** The outermost execution
  context the engine pushed during bootstrap.
