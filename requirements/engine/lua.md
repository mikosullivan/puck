# `%engine.lua`
<!--index: 7 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_lua",
	"role": "spec for %engine.lua — host introspection for the Lua reference engine. Present only when running on the Lua reference engine; other engines expose a parallel slot for their own host (%engine.python, %engine.wasm, etc.).",
	"availability": "Lua reference engine only"
}}
~~~

`%engine.lua` exposes information about the Lua VM that the reference engine is running inside — Lua version, the set of standard libraries available, bindings the host loaded, and other introspection bits user code might need when targeting the Lua reference engine specifically.

`%engine.lua` is present only when the host is the Lua reference engine. On other engines (a future Python-hosted engine, a wasm-hosted engine, etc.) the slot is absent, and a parallel slot named after that host appears in its place. Code that reads `%engine.lua` should expect it to be absent in non-Lua hosts and handle the absence — typically by also reading `%engine.platform.engine` to choose which host slot to interrogate.

Typical contents:

| Field | Meaning |
|---|---|
| `version` | The Lua version the engine is running on — `5.1`, `5.3`, `5.4`, etc. |
| `libraries` | Set of standard libraries available (`string`, `table`, `io`, etc.). Reflects what the host built in; not everything is always present. |
| `bindings` | Set of additional bindings the host loaded into Lua — third-party modules the engine can call out to. |

## Testing

- **`%engine.lua` is present when running the Lua reference engine** — under `lucy`, `%engine.lua` returns a non-null hash.
- **`%engine.lua.version` names the Lua version** — matches the actual Lua runtime (`'5.4'`, `'5.3'`, etc.).
- **`%engine.lua.version` is a string** — not a number; version comparison is string-shaped.
- **`%engine.lua.libraries` is a set-like collection of strings** — `.contains?('string')` returns `true` when the string library is available.
- **`%engine.lua.libraries` reflects what the host built in** — standard libraries not compiled into the Lua VM are absent.
- **`%engine.lua.bindings` enumerates host-loaded modules** — third-party modules registered by the host appear.
- **`%engine.lua.bindings` is empty when no host bindings are registered** — an empty set, not null.
- **`%engine.lua` is absent under a non-Lua engine** — on a hypothetical Python-hosted engine, `%engine.lua` is null; a parallel host-specific slot appears in its place.
- **`%engine.platform.engine` is the discriminator** — code that reads `%engine.lua` should first check `%engine.platform.engine == 'lucy'`.
- **`%engine.lua` is user-only** — a non-user frame reading `%engine.lua` raises the blanket gate error.
- **`%engine.lua` is read-only** — `%engine.lua.version = '99'` raises.
- **The returned hash is faucet-role-owned** — `%engine.lua.obj.role` is the host-info faucet role, not `user`.
- **Values are stable across reads within a run** — the version string doesn't change between calls.
- **`%engine.lua.libraries.contains?` on an unknown library returns false** — no raise; false result.
- **Deleting or mutating the returned hash raises** — every field is read-only.
- **`%engine.lua` co-exists with `%engine.platform`** — both are populated; each describes a different layer (host VM vs OS/engine).
