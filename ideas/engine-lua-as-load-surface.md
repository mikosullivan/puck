# `%engine.lua` as the dynamic load surface for Lua libraries

~~~vibecode
{"vibecode": {
	"doc": "idea_engine_lua_as_load_surface",
	"role": "placeholder idea note: future evolution of %engine.lua from a read-only introspection slot into the official, permission-gated surface for dynamically loading Lua libraries from Caspian user code",
	"status": "idea — explicitly NOT V1",
	"related": ["%engine.lua spec — requirements/engine/lua.md",
		"%engine surface and user-only rule — requirements/engine/index.md"]
}}
~~~

**Not V1.** Captured for later.

Today, [`%engine.lua`](../requirements/engine/lua.md) is a read-only window — user code can see what Lua files and libraries are loaded, but can't add to the set. Future direction: extend the slot to be the **official load surface** for Lua libraries dynamically requested from Caspian user code.

## What it would buy

- **The permission gate is the load-bearing part.** The engine decides what's loadable; user code only consumes what was approved. Same security model that makes [`%engine` user-only](../requirements/engine/index.md#user-only) extends naturally to library loading. Without that gate, this is "Caspian user code can pull in arbitrary C bindings" — a backdoor through every sandbox guarantee Caspian otherwise gives.
- **Obvious location.** Right now `%engine.lua` is a window into what's loaded; making it the official load surface keeps the location obvious — auditors and future devs know exactly where to look. No ambient "global require" mystery; everything dynamic lives here.
- **Symmetric across hosts.** The pattern generalizes: `%engine.rust` becomes the controlled load surface for Rust crates (when a Rust engine permits it), `%engine.js` for JS modules, etc. One pattern, applied per host. The host-specific slot is *the* interop surface, not just an introspection window.

## What needs working out

- **Permission model.** Several reasonable shapes: static allowlist in engine config; per-call dynamic check (engine prompts or consults policy); capability-per-library handed in at startup as part of the bootstrap pattern. Each has different tradeoffs against the existing user-only model. Worth thinking through when the feature comes online.
- **API shape.** Read-style (`%engine.lua.libs["lsqlite3"]` auto-loads if permitted) vs. explicit-load (`%engine.lua.load("lsqlite3")` returning a handle) vs. something else.
- **Interaction with the rest of `%engine.lua`.** Once a library is dynamically loaded, does it show up in `%engine.lua.files` / `%engine.lua.bindings` alongside the natively-loaded ones? Presumably yes — same shape, same introspection surface.

Not designed. Captured here so the intent is on record when the V2-ish work picks up.
