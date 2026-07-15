# Pre-installed Lua libs

~~~vibecode
{"vibecode": {
	"doc": "requirements_core_pre_installed_libs",
	"role": "spec listing the Lua libraries pre-installed at Caspian install time — libs that aren't compiled into the caspian binary but are fetched during install.sh and extracted to ~/.local/share/caspian/lua/. Loaded lazily by Lua's require when the code touches them. Currently: lua-http-parser (HTTP/1.x server-side request parsing, C extension), xml2lua (pure-Lua XML parser), and lua-cbor (CBOR decoder backing the Passkey / WebAuthn class).",
	"status": "spec — initial set of pre-installed libs settled (lua-http-parser, xml2lua, lua-cbor); expansion decisions get evaluated separately before landing here",
	"audience": "release maintainers building the pre-installed-libs bundle; developers who want to know what's already available for `require()` without installing anything themselves"
}}
~~~

At Caspian install time, in addition to the caspian binary itself, `install.sh` fetches a small set of Lua libraries and extracts them into the user's `~/.local/share/caspian/lua/`. These libraries back specific out-of-box features but aren't compiled into the binary — they're loaded lazily by Lua's `require` mechanism only when the code actually touches them.

## What's pre-installed

All sizes are approximate and in kb.

| Component | Size | Location | Purpose |
|---|---:|---|---|
| lua-http-parser | 25 | Cache | HTTP/1.x request parser (C extension). Server-side, on top of luasocket TCP accept. Loaded only when Caspian code does HTTP-server work. |
| xml2lua | 30 | Cache | Pure-Lua XML parser (DOM-style, produces Lua tables). Backs out-of-box XML support. |
| lua-cbor | 25 | Cache | CBOR decoder. Backs the Passkey / WebAuthn class — used to parse COSE_Key public-key structures and attestation / assertion objects. Loaded only when Caspian code touches passkey authentication. |
| **Total** | **80** | | |

**Location** column: **Cache** means the library is stored on disk under `~/.local/share/caspian/lua/` after Caspian install time and loaded lazily by `require`. Every row on this page is Cache — this doc covers only pre-installed libs, not what's compiled into the `caspian` binary itself.

## How they're loaded

Caspian's `package.path` and `package.cpath` are set at engine startup to include `~/.local/share/caspian/lua/share/` (pure-Lua modules) and `~/.local/share/caspian/lua/lib/` (C extensions). Ordinary `require('xml2lua')` or `require('http_parser')` from Caspian code triggers Lua's normal path-search lookup and loads the module the first time it's referenced. Zero cost if the code never touches the library.

## Where the libs come from

Fetched at install time from the same download infrastructure that serves the `caspian` binary. Per-architecture builds for anything with C code (like lua-http-parser), single arch-independent artifact for pure-Lua libs (like xml2lua). Exact URL scheme, tarball packaging, and cache-refresh behavior are settled in the same download design as the binary itself.

## Adding a new pre-installed lib

New candidates get evaluated separately before landing here. Criteria: does it back an out-of-box feature Caspian promises, is it small enough that eating the install-time download is worth it, is it healthy enough as a project to be worth committing to. Once adopted, the entry moves here as a spec fact.

## Related

- [core index](./) — the unified downloads table and section overview.
- [binary](binary) — what's compiled into the `caspian` binary itself.
- [installation](../installation/) — the install flow that fetches these libs.
