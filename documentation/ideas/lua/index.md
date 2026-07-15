# Lua

~~~vibecode
{"vibecode": {
	"doc": "idea_lua_index",
	"role": "index for ideas/lua/ — clustered design notes for Caspian's Lua-language integration story. Covers what Lua libs ship with Caspian (bundled into the binary or pre-installed to disk) and how developers can install additional Lua libs via CLI on top of that baseline. Design still in ideas; the settled pieces are folded into requirements/caspian/core/ (which now covers the caspian binary itself plus pre-installed Lua libraries — everything downloaded on install).",
	"status": "index — pages here shift in scope as the design iterates"
}}
~~~

Design notes for how Caspian relates to the Lua ecosystem. All still in ideas — the settled pieces get folded into `requirements/caspian/core/` as they firm up.

## In this directory

- [other-lua-libs](other-lua-libs) — shopping list for Lua libraries that ship with Caspian by default. Two locations: **Executable** (compiled into the binary) or **Cache** (pre-installed to disk at Caspian install time, lazy-loaded by `require`). Currently: LPeg, libsodium, luasodium, luasocket in the binary; lua-http-parser and xml2lua in the cache.
- **third-party** — promoted to [requirements/caspian/lua/third-party](../../requirements/caspian/lua/third-party). `caspian --install-lua <name>` wraps a user-supplied luarocks, targeting a Caspian-owned tree; both pure Lua and C bindings supported.
- [lua-libs](lua-libs) — how developers install additional Lua libraries via CLI (the mechanism). Hybrid model: pure Lua by default, plus a curated pre-built set of C extensions. Explicit CLI, not hot-downloaded.
