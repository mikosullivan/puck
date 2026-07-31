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

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 220" width="356" role="img" aria-label="Caspian floppy budget: 1383 kb used, 57 kb free, of 1440 kb total">
	<title>Caspian floppy budget</title>
	<g transform="translate(110 110)">
		<path d="M 0,-80 A 80,80 0 1,1 -19.7,-77.5 L 0,0 Z" fill="#ffb74d"/>
		<path d="M -19.7,-77.5 A 80,80 0 0,1 0,-80 L 0,0 Z" fill="#81d4fa"/>
	</g>
	<g font-family="sans-serif" font-size="14" fill="currentColor">
		<rect x="220" y="65" width="16" height="16" fill="#ffb74d"/>
		<text x="244" y="78">Used: 1383 kb (96%)</text>
		<rect x="220" y="95" width="16" height="16" fill="#81d4fa"/>
		<text x="244" y="108">Free: 57 kb (4%)</text>
		<text x="220" y="145" font-weight="bold">Total: 1440 kb</text>
	</g>
</svg>

**Available for Caspian: 377 kb** (floppy size minus everything that isn't the Caspian engine — the ceiling the engine + stdlib could grow to without breaking the floppy budget).

All sizes approximate, in kb.

| Component | Size | Location | Purpose |
|---|---:|---|---|
| Lua 5.4 interpreter (stripped, static) | 250 | Executable | The interpreter itself. |
| LPeg | 50 | Executable | C extension for PEG-based pattern matching — used by Caspian's source parser and regex engine. Compiled into the binary rather than lazy-loaded from disk: it's on the critical path at engine startup (parser is invoked on every source load), and being an engine implementation detail, there's no user-facing reason to make it independently upgradable. |
| lua-cjson | 35 | Executable | C-native JSON parser/encoder. JSON parsing is critical path — CaspianJ IS JSON, and the engine reads/writes it on every run. Native cjson runs ≈10-50× faster than pure-Lua alternatives (dkjson, rxi/json.lua) and ≈5-10× faster than LPeg-driven pure-Lua JSON. Same critical-path / version-lock argument as luasocket and pegasus: minute-detail coupling to cjson's specific API (sparse-array config, `cjson.null` sentinel, integer-precision handling), no user-facing upgrade path, version drift would silently break engine assumptions. Handles null (via `cjson.null`), 64-bit integers on Lua 5.3+, Unicode escapes including surrogate pairs, and duplicate keys correctly. |
| libsodium-minimal | 200 | Executable | C library for hashing, signing, secure random. The vault, protected-memory model, and password/passkey subsystems are keyed on libsodium's specific APIs — not swappable without redesign. |
| luasodium | 10 | Executable | Lua bindings for libsodium — how the engine reaches libsodium at all. |
| luasocket | 50 | Executable | TCP / UDP sockets + basic HTTP client. Backs both the `net` capability (user-facing network access) and `%fetch` (the engine's own object-fetch mechanism). Since `%fetch` is how downloadable Caspian classes reach the runtime, network is engine machinery — not a per-program feature. Minute-detail coupling to luasocket's specific API means a version drift could silently break engine assumptions; bundling locks the version. |
| pegasus | 15 | Executable | Pure-Lua HTTP/1.x server. Handles TCP accept (on top of luasocket), connection lifecycle, request parsing, response writing. Compiled into the binary because HTTP is core to how Caspian does IPC — engine machinery, not per-program feature. Same identity argument as luasocket: minute-detail coupling to pegasus's specific API, no user-facing upgrade path, version drift would silently break engine assumptions. |
| luaexpat | 63 | Cache | Lua binding to libexpat (C-native SAX parser) — backs out-of-box XML support. ≈40 kb for the `lxp.so` binding (per arch) + Lua helpers ≈23 kb (`lom.lua` DOM, `totable.lua`, `threat.lua` billion-laughs protection). The `.so`-only minimum-viable install is ≈40 kb if the Lua-side helpers are dropped. The `libexpat.so.1` it links against is a documented prerequisite in the same posture as `libsqlite3.so.0`, `luarocks`, `openssl`, and `tar` (universally present on Linux, in macOS base, distributed via package managers on Windows). C-native SAX parse is ≈100× faster than pure-Lua alternatives, with correct namespaces, entity handling, and encoding auto-detect. |
| lsqlite3 | 55 | Cache | Lua binding to SQLite — backs out-of-box SQLite support. Dynamic-link build stripped ≈55 kb; the `libsqlite3.so.0` it links against is a documented prerequisite in the same posture as `luarocks`, `openssl`, and `tar` (universally present on target platforms). |
| lua-confstr | 5 | Cache | Lua binding to POSIX `confstr()` — Caspian-authored, since no existing Lua binding covers it. Backs `%fs.util` for locating canonical system utilities (`_CS_PATH` → the POSIX-blessed PATH for finding `tar`, `gzip`, etc. without trusting `$PATH`). Standalone `.so` file, not baked into the binary. Kept as a separate file so the code can eventually be published as a standalone `lua-confstr` luarocks rock without repackaging. |
| Caspian engine + stdlib | 320 | Executable | This project. |
| Vibecode | 10 | Executable | Embedded JSON blob of vibecode describing the Caspian binary and its stdlib for AI consumers. Minified — 10 kb of JSON is enough for many pages of structured context (role, key concepts, invariants, non-obvious behaviors, cross-references to spec). Extractable externally via `caspian --vibecode`. Reserved as a fixed budget so vibecode growth stays visible against the floppy line rather than creeping into general engine size. |
| Lua binding wrapper | 20 | Executable | Generic wrapper for accessing Lua libraries from Caspian code via `%lua['name']`. Pure Lua, part of the engine's stdlib. |
| musl libc (statically linked) | 200 | Executable | System C library baked into the binary — zero runtime dependencies. |
| Wiggle room | 100 | Executable | Reserved slack for size uncertainty in the components above, small dependencies that don't warrant their own line, and rounding. Absorbs surprise growth without triggering a floppy-budget alert. |
| **Total** | **1383** | | Against the 1.44 MB floppy target — leaves 57 kb of headroom. |

**Location** column: **Executable** means compiled into the `caspian` binary. **Cache** means stored on disk under `~/.local/share/caspian/lua/` after Caspian install time, loaded lazily by `require`.

## Core Caspian code storage

Caspian code that ships in the core binary — the stdlib written above the primitive line, per [concepts § Caspian is written in Caspian](../concepts#caspian-is-written-in-caspian) — is stored as **minified CaspM** (the [AST format](../caspianj)). The transpiler runs at build time; the Caspian source doesn't ship in the binary. This is the V1 storage strategy for the floppy budget.

**Line info kept during V1.** Core CaspM is built with line info intact — every value atom carries `l:` and multi-line statements carry the trailing meta. The originally-planned `normalize(caspj, {lines: false})` strip is deferred until the stdlib is stable enough that mystery bugs inside it are rare. During the harden-and-stabilize phase, tracing a stdlib runtime error to a specific source line matters more than the ≈11 KB of budget that line info costs (against ≈200 KB of free headroom in the current build). The strip opt itself stays in the spec; see [caspianj § Stripping line info from CaspM](../caspianj#stripping-line-info-from-caspm) for the trigger criterion. User-provided code (application source, downloaded classes) has always kept line info.

To hit the 377 kb Caspian-itself target, we use every minification lever below. Ordered by engineering cost (cheapest first):

1. **LuaSrcDiet** on all Lua host code (`transpiler.lua`, `normalize.lua`, engine internals) — pure-Lua source minifier. Strips comments, collapses whitespace, renames locals to 1-char names. Free win, no new engine code.
2. **`luac -s`** bytecode-compile the Lua host code after LuaSrcDiet — ≈50% additional reduction; `-s` strips debug info. Uses existing Lua tooling.
3. **Concatenate related Lua modules** into single files before compilation — removes per-file boilerplate. Small build-time script.
4. **gzip / brotli compression** on the minified CaspM blobs at build time; decompress at load. Modest runtime cost at startup.
5. **Caspian-native bytecode** below CaspM — largest engineering investment (new compiler + interpreter, versioned spec). Only if levers 1-4 don't reach the target.

## In this section

- [binary](binary) — the `caspian` binary itself: what's compiled into it, how it's built (musl-static, per-CPU-arch), and how it's distributed.

## Related

- [installation](../installation/) — the install PROCESS (prompts, paths, flow).
