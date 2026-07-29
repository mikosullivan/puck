# What Caspian ships

~~~vibecode
{"vibecode": {
	"doc": "requirements_core",
	"role": "index for requirements/core/ — everything downloaded at Caspian install time. Covers the caspian binary (statically-linked runtime with bundled Lua interpreter, engine, stdlib, select C extensions, musl libc), how it's built and distributed, and the small set of Lua libraries pre-installed to disk at Caspian install time (Cache tier, loaded lazily by require). Every entry counts against the floppy budget. Separate from caspian/installation/, which specs the install PROCESS (prompts, flow, setup).",
	"status": "spec — inventory of what's downloaded settled; individual detail pages live in this directory",
	"audience": "release maintainers building the caspian distribution; developers checking what's available at runtime without installing anything themselves"
}}
~~~

Everything downloaded at Caspian install time — the runtime binary itself and the small set of Lua libraries pre-installed alongside it. Every entry counts against the floppy budget. The install process (prompts, flow, setup) is a separate topic — see [installation](../installation/).

## Contents at a glance

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 220" width="356" role="img" aria-label="Caspian floppy budget: 1238 kb used, 202 kb free, of 1440 kb total">
	<title>Caspian floppy budget</title>
	<g transform="translate(110 110)">
		<path d="M 0,-80 A 80,80 0 1,1 -61.6,-51.0 L 0,0 Z" fill="#ffb74d"/>
		<path d="M -61.6,-51.0 A 80,80 0 0,1 0,-80 L 0,0 Z" fill="#81d4fa"/>
	</g>
	<g font-family="sans-serif" font-size="14" fill="currentColor">
		<rect x="220" y="65" width="16" height="16" fill="#ffb74d"/>
		<text x="244" y="78">Used: 1238 kb (86%)</text>
		<rect x="220" y="95" width="16" height="16" fill="#81d4fa"/>
		<text x="244" y="108">Free: 202 kb (14%)</text>
		<text x="220" y="145" font-weight="bold">Total: 1440 kb</text>
	</g>
</svg>

All sizes approximate, in kb.

| Component | Size | Location | Purpose |
|---|---:|---|---|
| Lua 5.4 interpreter (stripped, static) | 250 | Executable | The interpreter itself. |
| LPeg | 50 | Executable | C extension for PEG-based pattern matching — used by Caspian's source parser, regex engine, and JSON parser. Compiled into the binary rather than lazy-loaded from disk: it's on the critical path at engine startup (CaspianJ parsing = JSON parsing, which is LPeg-based), so it's effectively always loaded — and being an engine implementation detail, there's no user-facing reason to make it independently upgradable. |
| libsodium-minimal | 200 | Executable | C library for hashing, signing, secure random. The vault, protected-memory model, and password/passkey subsystems are keyed on libsodium's specific APIs — not swappable without redesign. |
| luasodium | 10 | Executable | Lua bindings for libsodium — how the engine reaches libsodium at all. |
| luasocket | 50 | Executable | TCP / UDP sockets + basic HTTP client. Backs both `%chain.net` (user-facing network access) and `%fetch` (the engine's own object-fetch mechanism). Since `%fetch` is how downloadable Caspian classes reach the runtime, network is engine machinery — not a per-program feature. Minute-detail coupling to luasocket's specific API means a version drift could silently break engine assumptions; bundling locks the version. |
| pegasus | 15 | Executable | Pure-Lua HTTP/1.x server. Handles TCP accept (on top of luasocket), connection lifecycle, request parsing, response writing. Compiled into the binary because HTTP is core to how Caspian does IPC — engine machinery, not per-program feature. Same identity argument as luasocket: minute-detail coupling to pegasus's specific API, no user-facing upgrade path, version drift would silently break engine assumptions. |
| luaexpat | 63 | Cache | Lua binding to libexpat (C-native SAX parser) — backs out-of-box XML support. ≈40 kb for the `lxp.so` binding (per arch) + Lua helpers ≈23 kb (`lom.lua` DOM, `totable.lua`, `threat.lua` billion-laughs protection). The `.so`-only minimum-viable install is ≈40 kb if the Lua-side helpers are dropped. The `libexpat.so.1` it links against is a documented prerequisite in the same posture as `libsqlite3.so.0`, `luarocks`, `openssl`, and `tar` (universally present on Linux, in macOS base, distributed via package managers on Windows). C-native SAX parse is ≈100× faster than pure-Lua alternatives, with correct namespaces, entity handling, and encoding auto-detect. |
| lsqlite3 | 55 | Cache | Lua binding to SQLite — backs out-of-box SQLite support. Dynamic-link build stripped ≈55 kb; the `libsqlite3.so.0` it links against is a documented prerequisite in the same posture as `luarocks`, `openssl`, and `tar` (universally present on target platforms). |
| lua-confstr | 5 | Cache | Lua binding to POSIX `confstr()` — Caspian-authored, since no existing Lua binding covers it. Backs `%fs.util` for locating canonical system utilities (`_CS_PATH` → the POSIX-blessed PATH for finding `tar`, `gzip`, etc. without trusting `$PATH`). Standalone `.so` file, not baked into the binary. Kept as a separate file so the code can eventually be published as a standalone `lua-confstr` luarocks rock without repackaging. |
| Caspian engine + stdlib | 320 | Executable | This project. |
| Lua binding wrapper | 20 | Executable | Generic wrapper for accessing Lua libraries from Caspian code via `%lua['name']`. Pure Lua, part of the engine's stdlib. |
| musl libc (statically linked) | 200 | Executable | System C library baked into the binary — zero runtime dependencies. |
| **Total** | **1238** | | Against the 1.44 MB floppy target — leaves 202 kb of headroom. |

**Location** column: **Executable** means compiled into the `caspian` binary. **Cache** means stored on disk under `~/.local/share/caspian/lua/` after Caspian install time, loaded lazily by `require`.

## Core Caspian code storage

Caspian code that ships in the core binary — the stdlib written above the primitive line, per [concepts § Caspian is written in Caspian](../concepts#caspian-is-written-in-caspian) — is stored as **minified CaspM** (the [AST format](../caspianj)). The transpiler runs at build time; the Caspian source doesn't ship in the binary. This is the V1 storage strategy for the floppy budget.

**Line info kept during V1.** Core CaspM is built with line info intact — every value atom carries `l:` and multi-line statements carry the trailing meta. The originally-planned `normalize(caspj, {lines: false})` strip is deferred until the stdlib is stable enough that mystery bugs inside it are rare. During the harden-and-stabilize phase, tracing a stdlib runtime error to a specific source line matters more than the ≈11 KB of budget that line info costs (against ≈200 KB of free headroom in the current build). The strip opt itself stays in the spec; see [caspianj § Stripping line info from CaspM](../caspianj#stripping-line-info-from-caspm) for the trigger criterion. User-provided code (application source, downloaded classes) has always kept line info.

If further reductions are needed pre-release, levers to consider in order of engineering cost:

1. **`luac` bytecode-compile the Lua host code** (`transpiler.lua`, `normalize.lua`, engine internals) — ≈50% reduction on those files, uses existing Lua tooling, no new engine code.
2. **gzip / brotli compression** on the minified CaspM blobs at build time; decompress at load.
3. **Caspian-native bytecode** below CaspM — biggest engineering investment (new compiler + interpreter, versioned spec); only if the previous levers aren't enough.

Nothing on this list is committed for V1. Minified CaspM is the current baseline; the other levers stay in the pocket.

## Feature cost estimates

Rough sizing of what specific subsystems contribute to Caspian's own engine + stdlib code. Not exhaustive — a running notebook for features whose cost has been sized during design. All sizes in kb; actual figures shake out at implementation time.

| Feature | Size | Notes |
|---|---:|---|
| Protected memory subsystem | 60 | Vault management (≈20), `core:protected/memory` primitive (≈25), Password class (≈10), process-security wiring (≈5). See [protected/](../protected/). Uses libsodium + luasodium which are already bundled — no new C libraries needed. |
| Passkey subsystem | 15 | Passkey server-side + authenticator-side classes in Caspian (≈15). See [protected/passkey/](../protected/passkey/). The CBOR decoder is now a V1 download requirement reached via `%(caspian.uno/cbor.casp)` — zero install-download cost, fetched lazily on first passkey use. Impl spec deferred. libsodium's Ed25519 verify, CSPRNG, and key-generation primitives are already bundled and reused. ES256 / RS256 signature verify calls the operator-installed `openssl` binary directly via `.execute` — subprocess invocation, no shell involved — treated as a Caspian prerequisite in the same posture as `luarocks` and `tar`. Zero bundled cost. Per [concepts § Caspian is written in Caspian](../concepts#caspian-is-written-in-caspian), both Passkey classes and all assertion-validation logic live above the primitive line as Caspian code — the ≈15 kb bumps the Caspian engine + stdlib line when the work lands. |

## In this section

- [binary](binary) — the `caspian` binary itself: what's compiled into it, how it's built (musl-static, per-CPU-arch), and how it's distributed.

## Related

- [installation](../installation/) — the install PROCESS (prompts, paths, flow).
