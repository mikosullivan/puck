# `%engine.lua`

~~~vibecode
{"vibecode": {
	"doc": "engine_lua",
	"role": "spec for the %engine.lua slot — the host-specific introspection slot present when the running engine is the Lua reference implementation; primarily enumerates the loaded Lua files with their names and versions",
	"audience": "Caspian programmers writing user-role code that needs to know what Lua files are loaded into the running engine, plus future host implementers wiring parallel slots for their own hosts",
	"key_concepts": ["loaded_lua_files_with_names_and_versions", "host_specific_introspection_slot",
		"present_only_on_lua_engine", "parallel_slots_for_other_hosts"]
}}
~~~

`%engine.lua` is the slot through which user code introspects the **Lua host** running the engine. Its primary purpose is to **enumerate the Lua files in use** — the engine's own Lua modules, plus any further Lua code loaded into the process — with their names and versions, along with whatever other Lua-host metadata is useful (interpreter version, standard libraries available, registered C bindings, etc.).

It's a [standard slot on `%engine`](index.md#standard-slots), and like every engine slot, [user-role-only](index.md#user-only).

## Why a host-specific slot

Most slots on `%engine` are **universal** — `argv`, `stdin`, `stdout`, `dir`, `http`, etc. exist regardless of how the engine is implemented. The host underneath could be Lua, Rust, JavaScript, or anything else; these slots mean the same thing across all of them.

A few things, though, are inherently **host-specific**. Which Lua files are loaded? At what versions? Which Lua interpreter version is running? Which standard libraries and C bindings are present? Those facts only make sense in the Lua world. Cramming them into a universal slot would lie about portability.

So `%engine.lua` exists as a host-specific slot for Lua-host introspection. Other engines that implement Caspian expose their own parallel slot: a future Rust engine would expose `%engine.rust`, a JavaScript engine `%engine.js`, and so on. Same pattern, parallel namespaces.

## Presence

`%engine.lua` is present **only** when the running engine is the Lua reference implementation. On other engines, the slot is absent — accessing it raises. Portable user code should treat `%engine.lua` as optional and check before using it; code that genuinely needs Lua-host facts is, by definition, not portable across engines and lives with that tradeoff.

## What it exposes

The slot returns a hash. The headline field is `files`; the rest is supplementary Lua-host metadata.

<a id="files"></a>
### `files` — loaded Lua files

The primary surface. A hash describing every Lua file currently loaded into the running engine — the engine's own modules (`engine.lua`, `lexer.lua`, `parser.lua`, `transpiler.lua`, etc.) and any further Lua code loaded into the process.

Per-file entry carries at least:

| Field | What it is |
|---|---|
| `name` | The module name (e.g. `"caspian.lexer"`) or, when not loaded under a module name, the file path. |
| `version` | The file's declared version, when available. Source TBD — likely read from a version field in the file's module header (the `--[[ {...} ]]` JSON block convention used across the engine's Lua code), with falls-back behavior to be specified. |
| `path` | The filesystem path the file was loaded from. |

More per-file fields (size, mtime, hash, etc.) can land as user-code needs surface. The point of the slot is "what's actually running" — fields earn their place by answering that question.

### Other Lua-host metadata

Alongside `files`, the slot carries general Lua-host facts:

| Field | What it is |
|---|---|
| `version` | The Lua interpreter version string (e.g. `"5.4"`). |
| `version_full` | The full interpreter version string with patch level, when available (e.g. `"Lua 5.4.6"`). |
| `stdlibs` | A hash naming which Lua standard libraries are loaded (`string`, `table`, `math`, `io`, `os`, `coroutine`, `package`, `debug`, `utf8`, etc.). Truthy value = loaded. Hosts can withhold stdlibs in sandboxed setups; this is how user code finds out what's actually available. |
| `bindings` | A hash naming the C bindings registered into the Lua state — e.g. `lsqlite3`, `cjson`, `lpeg`, plus any project-specific bindings the host wired in. Same truthy-hash pattern. |

More fields will land as introspection needs become clear. The exact field set is not frozen.

The slot's value is a **plain hash**, not a method-bearing object — `%engine.lua.files['caspian.lexer'].version`, `%engine.lua.version`, `%engine.lua.stdlibs['utf8']`, etc. Field reads, no method calls.

## Cross-host parallel slots

When another engine implementation comes online, it exposes its own host-specific slot under the same parallel-slot pattern. The convention:

- The slot name is the host's short, lowercased identifier (`lua`, `rust`, `js`, ...).
- The contents are whatever introspection makes sense for that host — there's no requirement to mirror Lua's field set.
- Only one host-specific slot is present at a time (the one matching the running engine).

This keeps each host honest about what it offers, without forcing a lowest-common-denominator interface across hosts that don't actually share the same internals.

## See also

- [`%engine`](index.md) — the parent surface and the role/security rules every engine slot inherits.
- [`%engine.manifest`](manifest.md) — a sibling slot that returns a broader process-description hash; manifest includes engine-level info, whereas `%engine.lua` is specifically the Lua-host introspection layer.
