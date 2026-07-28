# `%engine`
<!--index: 3 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_root",
	"role": "root of the %engine API spec. %engine is the top-level-only gateway between user code and host-provided resources; this directory owns the canonical doc for each slot. Other docs link to slots from here rather than redefining them.",
	"audience": "developers writing Caspian programs that need host resources; engine implementers building conformance; AI tooling reasoning about what's available to user code"
}}
~~~

`%engine` is the gateway between Caspian code and the host process that's running it. It's a top-level-only system method — non-capturable by runtime enforcement so that non-user code can't squirrel away a reference and use host resources behind the user's back.

## Only `user` can call methods on `%engine`

**Every slot on `%engine` is reachable only from code running under the `user` role.** A method call on `%engine` (or `%engine[...]`) from any other role is a runtime error. There is no per-slot opt-in for non-user access; the gate applies to the whole surface.

This is what makes `%engine` the program's gateway and not just a convenient namespace. Host resources flow through `user` code. If non-user code needs something `%engine` exposes — an HTTP client, a manifest entry, a stdout stream — the user is the one who reaches into `%engine`, takes what's needed, and hands it across. The user is the actor; everything else is a tool the user employs.

## Engine methods

Each slot has its own page in this directory (or one pending, marked TBD).

The "Mirrored in `%chain`" column names the chain capability that gets seeded from the engine slot at bootstrap. Capabilities that reach outside the script all have a chain mirror; user-only metadata and control slots don't.

| Method | Description | Mirrored in `%chain` |
|---|---|---|
| [`%engine.argv`](argv) | Command-line arguments. | [`%chain.argv`](../chain/methods/argv) |
| `%engine.encryption` (TBD) | Cryptographic primitives. | [`%chain.encryption`](../chain/methods/encryption) |
| `%engine.env` (TBD) | Environment-variable accessor. | [`%chain.env`](../chain/methods/env) |
| `%engine.forks` (TBD) | Process forking. | [`%chain.forks`](../chain/methods/forks) |
| [`%engine.http_client`](http_client) | HTTP client. | via [`%chain.net.http`](../chain/methods/net) |
| `%engine.lua` ([doc](lua)) | Information about the Lua host running the reference engine. | — |
| `%engine.manifest` ([doc](manifest/)) | Hash describing the current process. | — |
| `%engine.net` (TBD) | Networking — HTTP, sockets, UDS. | [`%chain.net`](../chain/methods/net) |
| `%engine.now` (TBD) | Engine-controlled clock. | [`%chain.now`](../chain/methods/now) |
| [`%engine.platform`](platform) | Host platform information — OS, architecture, engine implementation. | — |
| `%engine.puck` (TBD) | Object download by URL. | [`%chain.puck`](../chain/methods/puck) |
| `%engine.random` (TBD) | Random-value primitives (libsodium → OS CSPRNG). | [`%chain.random`](../chain/methods/random) |
| [`%engine.require`](require) | Declarative dependency statement on a downloaded object. | — |
| `%engine.fs` (TBD) | Filesystem dirjail — the filesystem entry point. | [`%fs`](../global-methods/fs) |
| [`%engine.stderr`](stdout-and-stderr) | Diagnostic-output channel. | [`%chain.stderr`](../chain/methods/stdout-and-stderr) |
| [`%engine.stdin`](stdin) | Input channel. | [`%chain.stdin`](../chain/methods/stdin) |
| [`%engine.stdout`](stdout-and-stderr) | Primary output channel. | [`%chain.stdout`](../chain/methods/stdout-and-stderr) |
| `%engine.tmp` (TBD) | Temp-dir capability. | [`%chain.tmp`](../chain/methods/tmp) |
| [`%engine.util_paths`](util-paths) | Curated hash of absolute paths for non-POSIX system utilities (backs [`%fs.util`](../global-methods/fs-additions#util)). User-mutable. | — |

Entries marked **TBD** have no canonical doc yet — currently described from the chain side. Sweep tracked at [#881](https://github.com/mikosullivan/puck/issues/881).

## Custom resources via `%engine['name']`

Beyond the standard slots, a host may expose application-specific resources by name. `%engine['name']` is the access pattern; the key set is whatever this particular host chose to provide. The bracket form is what's required to reach anything not in the standard slot list.

## Testing

- **`%engine` reachable from `user`** — the first program statement (running under `user`) can call any documented slot.
- **`%engine` from a non-user role raises** — a method on a class owned by a non-user role calling `%engine.argv` raises the blanket `%engine` gate error.
- **Every slot is gated identically** — `%engine.stdout`, `%engine.http_client`, `%engine.manifest`, `%engine.roles`, and every other slot all raise from non-user role frames.
- **Bracket form is gated identically** — `%engine['argv']` from a non-user frame raises just as `%engine.argv` does.
- **`%engine` is non-capturable** — attempting `$e = %engine` and calling `$e.argv` from a non-user frame raises. Capturing the reference does not bypass the gate.
- **`%engine` is top-level-only** — a non-user role cannot receive a `%engine` reference through a constructor argument and later call methods on it; capture attempts at that layer raise.
- **A captured slot value is still usable across frames under method-runs-as-owner** — `$net = %engine.http_client` handed to a non-user object still works when the non-user code calls `$net.get(url)`, because the method runs under the user role.
- **Unknown standard slot raises a "no such slot" error** — `%engine.no_such_slot` raises a specific missing-slot error distinct from the blanket gate error.
- **Custom slot reachable via bracket form** — a host that populates `%engine['myapp']` makes that slot reachable to `user` code via `%engine['myapp']`.
- **Custom slot values subject to the same user-only gate** — `%engine['myapp']` from a non-user frame raises.
- **Bracket form required for non-identifier keys** — a slot whose name contains a dot is reachable only via bracket form.
- **Missing bracket-form key raises a "no such slot" error** — `%engine['undefined_key']` raises the missing-slot error.
- **`%engine` is a distinct object from `%chain`** — `%engine.stdout` and `%chain.stdout` are separate references with their own gates.
- **There is no per-slot opt-in surface** — attempting a hypothetical "grant slot X to role Y" mechanism raises or is not defined; the gate is on the whole `%engine`.
- **User default grants include `%engine`** — a fresh program run has `%engine` reachable from the first statement with no explicit grant.
- **Every standard slot has a `%chain` mirror or an explicit user-only marker** — the catalog table names either a chain counterpart or a dash.
- **TBD slots in the catalog raise "TBD" or the missing-slot error** — implementation status is discoverable; user code doesn't hit a silent hang.
- **`%engine` returns the same object identity across accesses** — `%engine == %engine` is true.
- **Non-user role reading via bracket iteration raises** — attempting to enumerate `%engine` keys from a non-user role raises the blanket gate error.
