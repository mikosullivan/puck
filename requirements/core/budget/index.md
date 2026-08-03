# Floppy budget

~~~vibecode
{"vibecode": {
	"doc": "requirements_core_budget",
	"role": "The floppy budget — Caspian's byte budget against the 1.44 MB target. Per-component breakdown across four tiers (CLI, Caspian, External, wiggle room), pie chart of shares, and prose describing what each tier represents. Every entry in the table is measured or reasoned; totals sum against the 1,474,560 byte target.",
	"status": "live spec — updated when any component's shipped bytes change",
	"audience": "release maintainers watching the total; anyone adding a dependency and wondering what it'd cost"
}}
~~~

![Caspian floppy budget: CLI 450 kb, Caspian 152 kb, External 478 kb, wiggle room 100 kb, free 260 kb, of 1440 kb total](./floppy-budget.svg)

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
<tr><th colspan="3">Caspian</th></tr>
<tr>
	<td>Engine</td>
	<td class="align-right">84</td>
	<td>Live measurement: <strong>60% × total bytes</strong> of Caspian's own Lua source under <code>src/engine/</code>. Currently ≈140 kb of source (trivet.lua, normalize.lua, transpiler.lua); 60% is the expected shipped size after the minification levers below (empirically confirmed on Trivet at 56% reduction). Bundled into <code>caspian.lua</code> at build time along with Fiona and the Lua binding wrapper. Ships on disk under <code>caspian/</code>; any host embedding Caspian — the CLI, a Ruby host, a Python host — loads it via <code>require("caspian")</code>. Grows as the stdlib grows.</td>
</tr>
<tr>
	<td>Fiona</td>
	<td class="align-right">33</td>
	<td>Live measurement: <strong>60% × total bytes</strong> of Caspian's Lua source under <code>src/fiona/</code> + <strong>45% × total bytes</strong> of the SQL there. Currently ≈44 kb of Lua (<code>fiona.lua</code>) → ≈27 kb shipped, plus ≈12 kb of SQL (<code>fiona.sql</code>, <code>fiona-temp.sql</code>) → ≈6 kb shipped after whitespace / comment strip (45% is Miko's empirical ratio). Caspian's storage substrate — bundled into <code>caspian.lua</code> at build time with the SQL inlined as string constants, since Fiona is integral (there's no Caspian mode without it) and the shipping surface should stay minimal.</td>
</tr>
<tr>
	<td>Lua binding wrapper</td>
	<td class="align-right">20</td>
	<td>Generic wrapper for accessing Lua libraries from Caspian code via <code>%lua['name']</code>. Pure Lua, part of the engine's stdlib — bundled into <code>caspian.lua</code> at build time along with Engine and Fiona.</td>
</tr>
<tr>
	<td>Vibecode</td>
	<td class="align-right">10</td>
	<td>JSON blob of vibecode describing Caspian and its stdlib for AI consumers. Minified — 10 kb of JSON is enough for many pages of structured context (role, key concepts, invariants, non-obvious behaviors, cross-references to spec). Ships as a separate on-disk file under <code>caspian/</code> so any host can read it and so <code>caspian --vibecode</code> can dump it without unpacking the engine bundle. Reserved as a fixed budget so vibecode growth stays visible against the floppy line rather than creeping into general engine size.</td>
</tr>
<tr>
	<td>lua-confstr</td>
	<td class="align-right">5</td>
	<td>Caspian-authored Lua binding to POSIX <code>confstr()</code> — no existing Lua binding covers it. Backs <code>%fs.util</code> for locating canonical system utilities (<code>_CS_PATH</code> → the POSIX-blessed PATH for finding <code>tar</code>, <code>gzip</code>, etc. without trusting <code>$PATH</code>). Ships as a standalone <code>.so</code> under <code>caspian/</code>. Kept separate from the engine bundle so the code can eventually be published as a standalone <code>lua-confstr</code> luarocks rock without repackaging.</td>
</tr>
</tbody>

<tbody>
<tr><th colspan="3">External</th></tr>
<tr>
	<td>libsodium-minimal</td>
	<td class="align-right">200</td>
	<td>C library for hashing, signing, secure random. Ships as <code>libsodium.so</code> under <code>external/</code>; the engine loads it via the luasodium binding. The vault, protected-memory model, and password/passkey subsystems are keyed on libsodium's specific APIs — not swappable without redesign, so we lock the version by bundling the exact binary rather than falling back on system packages.</td>
</tr>
<tr>
	<td>luasodium</td>
	<td class="align-right">10</td>
	<td>Lua bindings for libsodium — how the engine reaches libsodium at all. Ships as <code>luasodium.so</code> under <code>external/</code>.</td>
</tr>
<tr>
	<td>luasocket</td>
	<td class="align-right">50</td>
	<td>TCP / UDP sockets + basic HTTP client. Ships as <code>socket.so</code> + Lua wrappers under <code>external/</code>. Backs both the <code>net</code> capability (user-facing network access) and <code>%fetch</code> (the engine's own object-fetch mechanism). Minute-detail coupling to luasocket's specific API means a version drift silently breaks engine assumptions; bundling the exact version pins it.</td>
</tr>
<tr>
	<td>pegasus</td>
	<td class="align-right">15</td>
	<td>Pure-Lua HTTP/1.x server. Ships as Lua source under <code>external/</code>. HTTP is core to how Caspian does IPC, and the engine's code is tightly matched to pegasus's specific API; bundling the exact version keeps that coupling stable. Handles TCP accept (on top of luasocket), connection lifecycle, request parsing, response writing.</td>
</tr>
<tr>
	<td>LPeg</td>
	<td class="align-right">50</td>
	<td>C extension for PEG-based pattern matching — used by Caspian's source parser and regex engine. Ships as <code>lpeg.so</code> under <code>external/</code>. Critical path at engine startup; engine implementation detail with no user-facing upgrade path.</td>
</tr>
<tr>
	<td>lua-cjson</td>
	<td class="align-right">35</td>
	<td>C-native JSON parser/encoder. JSON parsing is critical path — CaspianJ IS JSON, and the engine reads/writes it on every run. Ships as <code>cjson.so</code> under <code>external/</code>. Handles null (via <code>cjson.null</code>), 64-bit integers on Lua 5.3+, Unicode escapes including surrogate pairs, and duplicate keys correctly.</td>
</tr>
<tr>
	<td>lsqlite3</td>
	<td class="align-right">55</td>
	<td>Lua binding to SQLite — the disk layer Fiona sits on. Ships as <code>lsqlite3.so</code> under <code>external/</code>. Dynamic-link build stripped ≈55 kb; the <code>libsqlite3.so.0</code> it links against is a documented prerequisite in the same posture as <code>libexpat.so.1</code>, <code>luarocks</code>, <code>openssl</code>, and <code>tar</code> (universally present on target platforms).</td>
</tr>
<tr>
	<td>luaexpat</td>
	<td class="align-right">63</td>
	<td>Lua binding to libexpat (C-native SAX parser) — backs out-of-box XML support. ≈40 kb for the <code>lxp.so</code> binding (per arch) + Lua helpers ≈23 kb (<code>lom.lua</code> DOM, <code>totable.lua</code>, <code>threat.lua</code> billion-laughs protection). Ships under <code>external/</code>. The <code>.so</code>-only minimum-viable install is ≈40 kb if the Lua-side helpers are dropped. The <code>libexpat.so.1</code> it links against is a documented prerequisite in the same posture as <code>libsqlite3.so.0</code>. C-native SAX parse is ≈100× faster than pure-Lua alternatives, with correct namespaces, entity handling, and encoding auto-detect.</td>
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
	<td class="align-right"><strong>1180</strong></td>
	<td>Against the 1.44 MB floppy target — leaves 260 kb of headroom.</td>
</tr>
</tfoot>
</table>

Tiers:

- **CLI** — statically linked into the `bin/caspian` binary. The binary is a thin embedder: just the Lua 5.4 interpreter, musl libc, and the CLI shim that loads the engine. Specific to running the CLI; non-Lua embedders (Ruby, Python, other host languages) bring their own Lua interpreter and load the engine directly, so they don't need this binary at all.
- **Caspian** — everything Caspian-authored: the engine (`caspian.lua` bundle with Fiona and the Lua binding wrapper inlined), the vibecode JSON blob, and `lua-confstr`. Ships under `caspian/`. Loaded via `require()` by whatever host is embedding Caspian — the CLI, a Ruby program, a Python program. Same files, any host.
- **External** — third-party libraries the engine depends on. `.so` binaries per arch and their `.lua` wrappers where applicable, shipped under `external/`. Loaded via `require()` the same way — a host that adds `external/` to its `package.cpath` gets the whole engine's C surface for free. Bundled at exact versions rather than fetched from system packages because the engine's coupling to each lib's API is tight enough that version drift silently breaks assumptions.
- **wiggle room** — reserved slack, unassigned to any specific tier because surprise growth can happen anywhere.
