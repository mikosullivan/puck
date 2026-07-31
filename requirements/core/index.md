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

## Floppy budget

![Caspian floppy budget: CLI 450 kb, Engine 84 kb, everything else 513 kb, wiggle room 100 kb, free 293 kb, of 1440 kb total](./floppy-budget.svg)

All sizes approximate, in kb.

<table class="floppy-budget">
<thead>
<tr>
	<th>Component</th>
	<th class="align-right">Size</th>
	<th>Purpose</th>
</tr>
</thead>

<tbody>
<tr><th colspan="3">CLI</th></tr>
<tr>
	<td>CLI shim (Caspian-authored)</td>
	<td class="align-right">0</td>
	<td>Live measurement: <strong>90% × total bytes</strong> of Caspian's own CLI-side source under <code>src/cli/</code>. Currently ≈0.5 kb (<code>caspian.c</code>, a minimal C wrapper that hosts the Lua interpreter and loads the on-disk engine) — rounds to 0 kb at whole-KB granularity. 90% is a conservative estimate (worse-case minification) since CLI code tends to have less compressible structure than engine code. Grows as CLI features are added.</td>
</tr>
<tr>
	<td>Lua 5.4 interpreter (stripped, static)</td>
	<td class="align-right">250</td>
	<td>The interpreter itself. Statically linked into the caspian binary — hosts the CLI shim and, via that shim, loads the on-disk engine. Non-Lua embedders bring their own Lua interpreter (that second copy is the embedding tax and is not counted here).</td>
</tr>
<tr>
	<td>musl libc (statically linked)</td>
	<td class="align-right">200</td>
	<td>System C library baked into the caspian binary — zero runtime dependencies.</td>
</tr>
</tbody>

<tbody>
<tr><th colspan="3">Engine</th></tr>
<tr>
	<td>Engine</td>
	<td class="align-right">84</td>
	<td>Live measurement: <strong>60% × total bytes</strong> of Caspian's own Lua source under <code>src/engine/</code>. Currently ≈140 kb of source (trivet.lua, normalize.lua, transpiler.lua); 60% is the expected shipped size after the minification levers below (empirically confirmed on Trivet at 56% reduction). Ships as <code>engine.lua</code> (+ stdlib .lua files) on disk at <code>~/.local/share/caspian/lua/</code>; the caspian CLI and any non-Lua host embedding Caspian both load from this one canonical on-disk location. Grows as the stdlib grows.</td>
</tr>
<tr>
	<td>libsodium-minimal</td>
	<td class="align-right">200</td>
	<td>C library for hashing, signing, secure random. Statically linked into the caspian binary. The vault, protected-memory model, and password/passkey subsystems are keyed on libsodium's specific APIs — not swappable without redesign.</td>
</tr>
<tr>
	<td>luasodium</td>
	<td class="align-right">10</td>
	<td>Lua bindings for libsodium — how the engine reaches libsodium at all. Statically linked.</td>
</tr>
<tr>
	<td>luasocket</td>
	<td class="align-right">50</td>
	<td>TCP / UDP sockets + basic HTTP client. Statically linked into the caspian binary. Backs both the <code>net</code> capability (user-facing network access) and <code>%fetch</code> (the engine's own object-fetch mechanism). Minute-detail coupling to luasocket's specific API means a version drift silently breaks engine assumptions; bundling locks the version.</td>
</tr>
<tr>
	<td>pegasus</td>
	<td class="align-right">15</td>
	<td>Pure-Lua HTTP/1.x server. Statically linked into the caspian binary because HTTP is core to how Caspian does IPC and the engine's code is tightly matched to pegasus's specific API — a version drift would silently break engine assumptions. Handles TCP accept (on top of luasocket), connection lifecycle, request parsing, response writing.</td>
</tr>
<tr>
	<td>LPeg</td>
	<td class="align-right">50</td>
	<td>C extension for PEG-based pattern matching — used by Caspian's source parser and regex engine. Statically linked into the caspian binary (critical path at engine startup, engine implementation detail with no user-facing upgrade path).</td>
</tr>
<tr>
	<td>lua-cjson</td>
	<td class="align-right">35</td>
	<td>C-native JSON parser/encoder. JSON parsing is critical path — CaspianJ IS JSON, and the engine reads/writes it on every run. Statically linked into the caspian binary. Handles null (via <code>cjson.null</code>), 64-bit integers on Lua 5.3+, Unicode escapes including surrogate pairs, and duplicate keys correctly.</td>
</tr>
<tr>
	<td>Lua binding wrapper</td>
	<td class="align-right">20</td>
	<td>Generic wrapper for accessing Lua libraries from Caspian code via <code>%lua['name']</code>. Pure Lua, part of the engine's stdlib.</td>
</tr>
<tr>
	<td>Vibecode</td>
	<td class="align-right">10</td>
	<td>Embedded JSON blob of vibecode describing the Caspian binary and its stdlib for AI consumers. Minified — 10 kb of JSON is enough for many pages of structured context (role, key concepts, invariants, non-obvious behaviors, cross-references to spec). Extractable externally via <code>caspian --vibecode</code>. Reserved as a fixed budget so vibecode growth stays visible against the floppy line rather than creeping into general engine size.</td>
</tr>
</tbody>

<tbody>
<tr><th colspan="3">Cache</th></tr>
<tr>
	<td>luaexpat</td>
	<td class="align-right">63</td>
	<td>Lua binding to libexpat (C-native SAX parser) — backs out-of-box XML support. ≈40 kb for the <code>lxp.so</code> binding (per arch) + Lua helpers ≈23 kb (<code>lom.lua</code> DOM, <code>totable.lua</code>, <code>threat.lua</code> billion-laughs protection). The <code>.so</code>-only minimum-viable install is ≈40 kb if the Lua-side helpers are dropped. The <code>libexpat.so.1</code> it links against is a documented prerequisite in the same posture as <code>libsqlite3.so.0</code>, <code>luarocks</code>, <code>openssl</code>, and <code>tar</code> (universally present on Linux, in macOS base, distributed via package managers on Windows). C-native SAX parse is ≈100× faster than pure-Lua alternatives, with correct namespaces, entity handling, and encoding auto-detect.</td>
</tr>
<tr>
	<td>lsqlite3</td>
	<td class="align-right">55</td>
	<td>Lua binding to SQLite — backs out-of-box SQLite support. Dynamic-link build stripped ≈55 kb; the <code>libsqlite3.so.0</code> it links against is a documented prerequisite in the same posture as <code>luarocks</code>, <code>openssl</code>, and <code>tar</code> (universally present on target platforms).</td>
</tr>
<tr>
	<td>lua-confstr</td>
	<td class="align-right">5</td>
	<td>Lua binding to POSIX <code>confstr()</code> — Caspian-authored, since no existing Lua binding covers it. Backs <code>%fs.util</code> for locating canonical system utilities (<code>_CS_PATH</code> → the POSIX-blessed PATH for finding <code>tar</code>, <code>gzip</code>, etc. without trusting <code>$PATH</code>). Standalone <code>.so</code> file, not baked into the binary. Kept as a separate file so the code can eventually be published as a standalone <code>lua-confstr</code> luarocks rock without repackaging.</td>
</tr>
</tbody>

<tbody>
<tr><th colspan="3">wiggle room</th></tr>
<tr>
	<td>wiggle room</td>
	<td class="align-right">100</td>
	<td>Reserved slack for size uncertainty across every tier, small dependencies that don't warrant their own line, and rounding. Absorbs surprise growth without triggering a floppy-budget alert. Its own tier since surprise growth can happen anywhere — not tied to CLI, Engine, or Cache specifically.</td>
</tr>
</tbody>

<tfoot>
<tr>
	<td><strong>Total</strong></td>
	<td class="align-right"><strong>1147</strong></td>
	<td>Against the 1.44 MB floppy target — leaves 293 kb of headroom.</td>
</tr>
</tfoot>
</table>

Tiers:

- **CLI** — statically linked into the caspian binary. Specific to how the CLI runs; non-Lua embedders bring their own equivalent.
- **Engine** — the engine and everything it tightly depends on. Physical location varies per row: `engine.lua` itself lives on disk (loaded by both the CLI and non-Lua embedders); the C libraries and pure-Lua libs whose APIs the engine is intimately tied to (pegasus, luasocket, LPeg, cjson, libsodium, luasodium, Lua binding wrapper) are statically linked into the caspian binary to lock the version.
- **wiggle room** — reserved slack, unassigned to any specific tier because surprise growth can happen anywhere.
- **Cache** — optional, swappable libs stored on disk under `~/.local/share/caspian/lua/` after install, loaded lazily by `require`. Per-arch fetch at install time.

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
