# `%engine.lua`
<!--index: 7 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_lua",
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
