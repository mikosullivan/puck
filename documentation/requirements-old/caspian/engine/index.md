# `%engine`

~~~vibecode
{"vibecode": {
	"doc": "engine",
	"role": "spec for the %engine system method: the user-role-only gateway through which scripts reach host-provided resources",
	"audience": "Caspian programmers writing top-level user code, and host implementers wiring up engine slots",
	"key_concepts": ["%engine_returns_the_engine_object", "host_defined_key_set",
		"user_role_only_access", "dedicated_check_not_general_acl", "bootstrap_pattern_pull_then_pass_down"]
}}
~~~

`%engine` is a method that returns the engine object — the gateway through which the running script accesses resources provided by the host (capabilities, configuration, injected objects). The object has a small set of **standard slots** in well-known places, plus an open `%engine['name']` namespace where the host exposes whatever else this particular program needs.

Other system methods — `%stdout`, `%clock`, and the rest of the top-level `%`-namespace — sit outside `%engine` and are available to non-user roles when the host grants them. `%engine` itself is user-only (see [below](#user-only)).

## Standard slots

These slots are part of every engine. The names and meanings are fixed; the values the host wires into them can vary (a test host can substitute fakes, a sandbox host can withhold a slot entirely).

| Slot | What it is |
|---|---|
| `%engine.argv` | The command-line arguments the program was invoked with. |
| `%engine.stdin` | The program's input channel. Read by user code; not granted to libraries. |
| `%engine.stdout` | The program's output channel. Same underlying channel as `%stdout`, but the access rules differ: the host may grant `%stdout` to non-user roles, while `%engine.stdout` is always user-only. |
| `%engine.stderr` | The program's diagnostic-output channel. |
| `%engine.dir` | The directory the program is running in. |
| `%engine.http` | HTTP client for making outbound requests. |
| `%engine.lua` | Information about the Lua host running the engine — version, available standard libraries, loaded bindings, and other host-introspection user code might need. Present when running on the Lua reference engine; other engines would expose a parallel slot for their own host. See [lua.md](lua.md). |
| `%engine.manifest` | A hash describing the current process — OS, engine, Caspian version, loaded libs. See [manifest.md](manifest.md). |
| `%engine.require` | Declarative: `%engine.require 'uns'` says "this program uses this library." Primes the library cache (when caching is allowed) and adds the library to [`%engine.manifest`](manifest.md). Does not change how libraries are used — access stays via `%[uns]`. Calling it is optional. See [require.md](require.md). |
| `%engine.coverage` | Default is off. **Property form** — `%engine.coverage = <value>` enables tracking for the rest of the process. `true` keeps only uncovered lines; integer `N` keeps lines with hit count ≤ `N`; `:all` keeps every executable line with its count. **Block form** — `%engine.coverage do … end` scopes tracking to just the code that runs inside the block; afterward, [`%engine.manifest`](manifest.md#coverage) reports coverage for what ran there. Either way, coverage tracks every loaded `.caspian` file (user code plus all libraries); the setting controls retention, not scope. |

More slots will land here as new universal capabilities settle.

## Custom resources via `%engine['name']`

Beyond the standard slots, the host exposes application-specific resources by name. `%engine['name']` is the access pattern, and the key set is whatever this particular host chooses to provide:

```
$db      = %engine['db']
$docs    = %engine['docs']
$request = %engine['request']    # in an HTTP handler context
```

There is no fixed list. A database-backed app might expose `db` and `cache`; an HTTP handler context might expose `request` and `response`; a CLI might expose nothing beyond the standard slots. Whatever the host injects is what's there.

## `%engine` is user-only — deliberate special case

**Only the `user` role can call `%engine` at all.** Calling `%engine` from any other role raises immediately — non-user code does not get a reference to the engine object in the first place. The same check fires on any method invocation against the engine object, so even if a `user`-role caller hands the engine reference to a different role, the method call from that role still raises.

This is enforced by a **dedicated check in the engine object itself**, not derived from any general role-based access-control system. The check applies uniformly — to `%engine` and to every method call on the object it returns.

It's **deliberately a special case**. The engine object is too critical a security boundary to ride on whatever general role-access mechanism Caspian eventually grows. The dedicated check is defense in depth: even if a future general system has bugs or gaps, the engine object's hard-coded user-only rule keeps holding.

The general language rule otherwise stands — *if you can see an object you can call its methods*. The engine object is the one named exception.

## What this looks like in practice

- User code freely writes `%engine[...]` and gets the data. Normal.
- Loaded libraries (running in their own roles) cannot write `%engine` — the call raises before they ever see an engine reference.
- A library handed the engine reference by user code still cannot call methods on it — the engine-object check fires on the library's role.
- Closures defined in user scope that captured `%engine` work when called *from* user code. If somehow invoked from a non-user role, the engine object's check fires the moment the closure dispatches into it.

## The bootstrap pattern

User code calls methods on `%engine` directly to pull out the resources it needs, then passes those resources down to libraries explicitly as parameters. Libraries never reach back to `%engine` themselves.

```
$db   = %engine['db']
$docs = %engine['docs']

# Pass the capabilities down explicitly:
$service = my_service.new(db: $db, docs: $docs)
```

This keeps the security boundary visible at every call site: every cross-role transition makes the resources flowing across it explicit, and removing or restricting one of them is just changing what you pass.
