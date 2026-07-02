# `%engine`
<!--index: 3 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_root",
	"role": "root of the %engine API spec. %engine is the top-level-only gateway between user code and host-provided resources; this directory owns the canonical doc for each slot. Other docs link to slots from here rather than redefining them.",
	"audience": "developers writing Caspian programs that need host resources; engine implementers building conformance; AI tooling reasoning about what's available to user code"
}}
~~~

`%engine` is the gateway between Caspian code and the host process that's running it. It's a top-level-only system method — non-capturable by runtime enforcement so that non-user code can't squirrel away a reference and use host resources behind the user's back.

## Only `user` can call methods on `%engine`

**Every slot on `%engine` is reachable only from code running under the `user` role.** A method call on `%engine` (or `%engine[...]`) from any other role is a runtime error. There is no per-slot opt-in for non-user access; the gate applies to the whole surface.

This is what makes `%engine` the program's gateway and not just a convenient namespace. Host resources flow through `user` code. If non-user code needs something `%engine` exposes — an HTTP client, a manifest entry, a coverage block — the user is the one who reaches into `%engine`, takes what's needed, and hands it across. The user is the actor; everything else is a tool the user employs.

## Engine methods

Each slot has its own page in this directory (or one pending, marked TBD).

The "Mirrored in `%chain`" column names the chain capability that gets seeded from the engine slot at bootstrap. Capabilities that reach outside the script all have a chain mirror; user-only metadata and control slots don't.

| Method | Description | Mirrored in `%chain` |
|---|---|---|
| [`%engine.argv`](argv) | Command-line arguments. | [`%chain.argv`](../chain/methods/argv) |
| `%engine.coverage` ([doc](coverage)) | Line-level coverage tracking. | — |
| [`%engine.dir`](dir) | Working directory at startup. | [`%chain.root`](../chain/methods/root) |
| `%engine.encryption` (TBD) | Cryptographic primitives. | [`%chain.encryption`](../chain/methods/encryption) |
| `%engine.env` (TBD) | Environment-variable accessor. | [`%chain.env`](../chain/methods/env) |
| `%engine.forks` (TBD) | Process forking. | [`%chain.forks`](../chain/methods/forks) |
| [`%engine.http`](http) | HTTP client. | via [`%chain.net.http`](../chain/methods/net) |
| `%engine.lua` ([doc](lua)) | Information about the Lua host running the reference engine. | — |
| `%engine.manifest` ([doc](manifest)) | Hash describing the current process. | — |
| `%engine.net` (TBD) | Networking — HTTP, sockets, UDS. | [`%chain.net`](../chain/methods/net) |
| `%engine.now` (TBD) | Engine-controlled clock. | [`%chain.now`](../chain/methods/now) |
| [`%engine.platform`](platform) | Host platform information — OS, architecture, engine implementation. | — |
| `%engine.puck` (TBD) | Object download by URL. | [`%chain.puck`](../chain/methods/puck) |
| `%engine.random` (TBD) | Random-value primitives (libsodium → OS CSPRNG). | [`%chain.random`](../chain/methods/random) |
| [`%engine.require`](require) | Declarative dependency statement on a downloaded object. | — |
| [`%engine.return_val`](return-val) | Settable slot holding the explicit return value the host receives from `engine.run()`. Omit and the host gets null. | — |
| `%engine.root` (TBD) | Root dirjail — the filesystem entry point. | [`%chain.root`](../chain/methods/root) |
| [`%engine.stderr`](stdout-and-stderr) | Diagnostic-output channel. | [`%chain.stderr`](../chain/methods/stdout-and-stderr) |
| [`%engine.stdin`](stdin) | Input channel. | [`%chain.stdin`](../chain/methods/stdin) |
| [`%engine.stdout`](stdout-and-stderr) | Primary output channel. | [`%chain.stdout`](../chain/methods/stdout-and-stderr) |
| `%engine.tmp` (TBD) | Temp-dir capability. | [`%chain.tmp`](../chain/methods/tmp) |

Entries marked **TBD** have no canonical doc yet — currently described from the chain side. Sweep tracked at [#881](https://github.com/mikosullivan/puck/issues/881).

## Custom resources via `%engine['name']`

Beyond the standard slots, a host may expose application-specific resources by name. `%engine['name']` is the access pattern; the key set is whatever this particular host chose to provide. The bracket form is what's required to reach anything not in the standard slot list.
