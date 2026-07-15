# Lua

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_lua",
	"role": "index for requirements/caspian/lua/ — Caspian's Lua-ecosystem integration beyond what ships in the core install. Currently covers third-party Lua library installation (both pure Lua and C bindings) via `caspian --install-lua <name>`, which wraps a user-supplied luarocks. See ../core/ for the caspian binary and pre-installed Lua libraries.",
	"status": "index — one spec so far (third-party), more to come as the Lua-integration story firms up",
	"audience": "developers using Lua from Caspian; anyone maintaining Caspian's Lua-side surface area"
}}
~~~

Requirements for Caspian's Lua-ecosystem integration beyond what ships in the [core install](../core/).

## In this section

- [third-party](third-party) — how developers install third-party Lua libraries. Wrapper command `caspian --install-lua <name>` shells out to luarocks (a documented prerequisite), targeting a Caspian-owned tree and forcing the build against Lua 5.4 for ABI match. Both pure Lua and C bindings supported.
- [binding](binding) — how Caspian code accesses Lua libraries. `%lua['name']` sigil returns a wrapper object; type marshalling handles the common conversions in both directions; Lua errors surface as Caspian exceptions. First-draft design.
