# What Caspian ships

~~~vibecode
{"vibecode": {
	"doc": "requirements_core",
	"role": "index for requirements/core/ — everything downloaded at Caspian install time. Covers the caspian binary (a thin embedder: Lua 5.4 interpreter, musl libc, CLI shim), Caspian-authored code (engine bundle, Fiona, vibecode blob), and the external libraries the engine loads via require. Every entry counts against the floppy budget, spec'd separately at requirements/core/budget/. Separate from caspian/installation/, which specs the install PROCESS (prompts, flow, setup).",
	"status": "spec — inventory of what's downloaded settled; individual detail pages live in this directory",
	"audience": "release maintainers building the caspian distribution; developers checking what's available at runtime without installing anything themselves"
}}
~~~

Everything downloaded at Caspian install time — the runtime binary itself and the small set of Lua libraries pre-installed alongside it. Every entry counts against the floppy budget. The install process (prompts, flow, setup) is a separate topic — see [installation](../installation/).

## Floppy budget

The per-component breakdown across four tiers (CLI, Caspian, External, wiggle room), with pie chart, table, and tier descriptions, lives at [budget](https://puck.uno/requirements/core/budget/).

## Core Caspian code storage

Caspian code that ships in the core binary — the stdlib written above the primitive line, per [concepts § Caspian is written in Caspian](../concepts#caspian-is-written-in-caspian) — is stored as **minified CaspM** (the [AST format](../caspianj)). The transpiler runs at build time; the Caspian source doesn't ship in the binary. This is the V1 storage strategy for the floppy budget.

**Line info kept during V1.** Core CaspM is built with line info intact — every value atom carries `l:` and multi-line statements carry the trailing meta. The originally-planned `normalize(caspj, {lines: false})` strip is deferred until the stdlib is stable enough that mystery bugs inside it are rare. During the harden-and-stabilize phase, tracing a stdlib runtime error to a specific source line matters more than the ≈11 KB of budget that line info costs (against ≈260 KB of free headroom in the current build). The strip opt itself stays in the spec; see [caspianj § Stripping line info from CaspM](../caspianj#stripping-line-info-from-caspm) for the trigger criterion. User-provided code (application source, downloaded classes) has always kept line info.

To hit the 377 kb Caspian-itself target, we use every minification lever below. Ordered by engineering cost (cheapest first):

1. **LuaSrcDiet** on all Lua host code (`transpiler.lua`, `normalize.lua`, engine internals) — pure-Lua source minifier. Strips comments, collapses whitespace, renames locals to 1-char names. Free win, no new engine code.
2. **`luac -s`** bytecode-compile the Lua host code after LuaSrcDiet — ≈50% additional reduction; `-s` strips debug info. Uses existing Lua tooling.
3. **Concatenate related Lua modules** into single files before compilation — removes per-file boilerplate. Small build-time script.
4. **gzip / brotli compression** on the minified CaspM blobs at build time; decompress at load. Modest runtime cost at startup.
5. **Caspian-native bytecode** below CaspM — largest engineering investment (new compiler + interpreter, versioned spec). Only if levers 1-4 don't reach the target.

## In this section

- [binary](https://puck.uno/requirements/core/binary) — the `caspian` binary itself: what's compiled into it, how it's built (musl-static, per-CPU-arch), and how it's distributed.
- [budget](https://puck.uno/requirements/core/budget/) — the floppy budget: per-tier byte breakdown, pie chart, and tier descriptions.
- [build](https://puck.uno/requirements/core/build) — the build script that produces the shipped distribution at `ecoverse/build/`.

## Related

- [installation](../installation/) — the install PROCESS (prompts, paths, flow).
