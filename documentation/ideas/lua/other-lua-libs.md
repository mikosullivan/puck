# Other Lua libs

> **Archived.** This page is redundant to [requirements/core/](../../requirements/core/), which owns the authoritative "what ships with Caspian" table and detail pages. Kept here for the shopping-list framing and the design rationale that surfaced during the design process (Network / HTTP server / XML parser candidate discussions and the tier model that emerged).

*Shopping list — exploring which Lua libraries would be worth shipping with Caspian by default. Two ways this can happen: **bundled in the binary** (the current model for LPeg, libsodium, and luasodium — always in memory, no filesystem lookup) or **auto-installed at Caspian install time** into `~/.local/share/caspian/lua/`, loaded lazily by Lua's normal `require` only when actually used. Both count against the [floppy budget](../../requirements/core/binary#size-budget-floppy-fits) — every kb has to be transferred to the user's machine to complete the install. Developer-driven post-install downloads (via CLI) are a separate concern and out of scope for this document.*

~~~vibecode
{"vibecode": {
	"doc": "idea_other_lua_libs",
	"role": "ARCHIVED shopping-list brainstorm for Lua libraries shipped with Caspian by default. Redundant to the authoritative spec at requirements/core/ (both the unified downloads table and per-lib detail pages). Kept here for the shopping-list framing, the tier model discussion (Executable vs Cache), and the Network / HTTP server / XML parser candidate discussions that led to the current selection.",
	"status": "archived — redundant to specs at requirements/core/; retained for design rationale"
}}
~~~

## What already ships with Caspian

Per [installation/binary § What's in the binary](../../requirements/core/binary#whats-in-the-binary) for the bundled parts. All sizes are approximate and in kb.

| Component | Size | Location | Purpose |
|---|---:|---|---|
| Lua 5.4 interpreter (stripped, static) | 250 | Executable | The interpreter itself. |
| LPeg | 50 | Executable | C extension for PEG-based pattern matching — Caspian's regex facility. |
| libsodium-minimal | 200 | Executable | C library for hashing, signing, secure random — blockchain verification and general Caspian needs. |
| luasodium | 10 | Executable | Lua bindings for libsodium. |
| luasocket | 50 | Cache | TCP/UDP sockets + basic HTTP client — backs `%chain.net`, loaded lazily on first use. |
| lua-http-parser | 25 | Cache | HTTP/1.x request parser (C extension) — server-side, on top of luasocket TCP accept. Loaded only when Caspian code does HTTP-server work. |
| xml2lua | 30 | Cache | Pure-Lua XML parser — DOM-style, produces Lua tables. Backs out-of-box XML support. |
| Caspian engine + stdlib | 260 | Executable | This project. |
| Lua binding wrapper | 20 | Executable | Generic wrapper for accessing Lua libraries from Caspian code via `%lua['name']`. Pure Lua, part of the engine's stdlib. |
| musl libc (statically linked) | 200 | Executable | System C library baked into the binary so it has zero runtime dependencies. |
| **Total** | **1095** | | Against the 1.44 MB floppy target — leaves 345 kb of headroom. |

**Location** column: **Executable** means compiled into the `caspian` binary (Tier 1). **Cache** means stored on disk after Caspian install time, loaded lazily by `require` when the code touches the library (Tier 2).

Sub-totals: **Executable** rows sum to 990 kb (that's the actual binary size); **Cache** rows sum to 105 kb; combined total 1095 kb.

## Notes before shopping

- **Tier 1 — bundled in binary.** Compiled in as `luaL_requiref`'d built-ins so `require('lpeg')` finds pre-loaded modules with no filesystem lookup or dynamic loader involvement. Right fit for internal-use primitives Caspian's own runtime depends on (regex engine, crypto). Adds to binary size; always in memory whether used or not.
- **Tier 2 — auto-installed at Caspian install time.** Downloaded during `install.sh`, extracted to `~/.local/share/caspian/lua/`, loaded lazily by Lua's normal `require` when the code actually touches them. Right fit for user-facing features Caspian promises out-of-box (XML parsing, etc.) where implementing in pure Caspian would be painful. Adds to install-download size but not binary size or per-startup cost. Updatable independent of the binary.
- **Both tiers count against the [floppy budget](../../requirements/core/binary#size-budget-floppy-fits).** Room isn't a mandate to fill; each addition earns its weight.
- **Deciding between tiers.** If the lib is needed at process startup or by Caspian's own runtime, Tier 1. If it backs a user-facing feature that might not be touched every run, Tier 2. If it's neither, probably not in scope for this file — that's Tier 3 territory (opt-in CLI install, spec'd elsewhere).

## Candidates

Each candidate is tagged **Tier 1** (bundle in binary) or **Tier 2** (auto-install).

### XML parser — adopted

**Status: adopted — xml2lua** (~30 kb, Cache), listed in the [table above](#what-already-ships-with-caspian). Pure-Lua DOM-style parser that produces Lua tables. Design rationale kept here for reference.

**Purpose.** Out-of-box XML parsing for Caspian code. XML has enough edge cases (encoding, entities, namespaces, CDATA, etc.) that reaching for a mature Lua library beats implementing it in pure Caspian.

**Why xml2lua?**

- **Actively maintained** — commit within the last ~13 months, 327 stars, 78 forks (as of 2026-07). More community activity than the alternatives.
- **Pure Lua.** No C ABI concerns; single arch-independent artifact rather than per-arch builds.
- **DOM-style output** — parsed XML arrives as Lua tables, which is nicer to use than SAX callbacks for most out-of-box cases.
- **Small footprint** (~30 kb) fits comfortably in the Cache tier.

**Considered and passed over:**

- **LuaExpat + LOM.** Lua bindings for the Expat C library (SAX-style, fast). Would require bundling `libexpat.so` plus per-arch builds, ~200 kb total. Overkill for the out-of-box case; reach for it only if we hit real performance issues on very large XML.
- **SLAXML.** Pure-Lua streaming (SAX-style) parser (~15 kb). Smaller, but ~2 years since last push and smaller community. DOM output more useful for typical out-of-box parsing than streaming.

**Deferred details.** Namespace-handling depth, XML 1.0-vs-1.1 scope, and whether we ever want to expose a SAX-style variant alongside the DOM API are open — not blocking on any of these to ship the initial version.

### Network (TCP/UDP) — adopted

**Status: adopted.** Both listed in the [table above](#what-already-ships-with-caspian): luasocket (~50 kb, Cache — auto-installed, lazy-loaded on first `%chain.net` use), lua-http-parser (~25 kb, Cache — auto-installed, lazy-loaded when HTTP server work happens). Design rationale kept here for reference.

**Prior decision: luasocket**, from `requirements-old/development/v1/details/lua-dependencies.md`. Confirmed starting point.

- **What luasocket provides.** TCP and UDP sockets, plus a basic HTTP client module (`socket.http`). No HTTP-server library of its own — server-side request parsing comes from lua-http-parser (see below); response building is Caspian-level.
- **Size.** ~50 kb.
- **Tier.** Tier 1 (backs [`%chain.net`](../../requirements/chain/methods/net), a first-class Caspian primitive).

**Driving use case: IPC** — inter-process communication between Caspian processes. Spec'd elsewhere. HTTP client and server are related capabilities that fall out of the same primitive.

**Explicitly not in scope:**

- **TLS / HTTPS.** Not included. For public HTTPS, developers should put something like nginx in front of Caspian — nginx terminates TLS for HTTPS and forwards plain HTTP to Caspian's socket. Caspian's built-in networking speaks plain HTTP only.
- **HTTP/2, WebSockets.** Same story — those live in front of the reverse proxy, not in Caspian.

Client and server are separate concerns, spec'd below.

#### Client

Outgoing HTTP requests. Basics needed: choose the method (GET, POST, PUT, DELETE, etc.), set request headers, send a request body, receive the response (status code, response headers, response body).

**What luasocket provides.** `socket.http.request()` — an HTTP/1.1 client that covers those basics out of the box.

**Not covered:**

- **Redirect following.** Not automatic; callers handle 3xx themselves if they want to follow.
- **Connection pooling.** Each request opens a new TCP connection.

**Sufficient for V1?** For basic API calls and IPC, yes. If pooling or auto-redirect becomes a real need, we'd probably wrap `socket.http` in a Caspian-level helper rather than pull in a heavier library like `lua-http`.

#### Server

Incoming HTTP requests. Basics needed: accept connections, parse the request line + headers + body, build responses and write them back.

**How it works:**

- **TCP accept.** Raw luasocket listener via `socket.bind()`.
- **Request parsing.** **lua-http-parser** — Lua binding for Node.js's `http_parser` C library. ~20–30 kb; C extension, so per-arch builds required. Battle-tested (every HTTP request Node.js handled from ~2009 through ~2019 went through this parser), Lua 5.4-compatible via the standard Lua C API. HTTP parsing is fiddly enough that we don't want to hand-roll it in Caspian.
- **Response building.** Caspian-level. Response format (status line + headers + body) is simple enough to construct without a library.

**Why lua-http-parser over `lua-picohttpparser`?** Broader Lua-binding maturity (Node.js legacy spawned more Lua wrapper activity) and more assured Lua 5.4 compatibility (some `picohttpparser` bindings are LuaJIT-FFI only, which doesn't work with our regular Lua 5.4 build). The underlying `http_parser` C library is essentially sunset — Node.js moved to `llhttp` around 2019 — but HTTP/1.x is a settled protocol; a parser doesn't need active development to keep parsing correctly.

**Tier:** Tier 2 (stored in the cache, lazy-loaded). HTTP server work is a distinct feature Caspian code opts into; no reason to pay the binary weight when the code doesn't touch it.

**Not covered:** complex request routing, HTTP/2, WebSockets. Out of scope per the not-in-scope decisions at the top of this section.
