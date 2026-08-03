# Floppy budget

~~~vibecode
{"vibecode": {
	"doc": "requirements_core_budget",
	"role": "The floppy budget — Caspian's byte target and the per-tier share against it. Pie chart + total + headroom + tier descriptions. The authoritative inventory of what ships in each tier lives at requirements/core/; this page is the visualization and headline number.",
	"status": "live spec — updated when any component's shipped bytes change",
	"audience": "release maintainers watching the total; anyone wondering how the shipped bytes divide up"
}}
~~~

Caspian's total shipped size targets a 1.44 MB floppy — **1,474,560 bytes**. The [core inventory](https://puck.uno/requirements/core/#contents) lists every component and its shipped size; the numbers below are the tier totals rolled up from that table.

![Caspian floppy budget: CLI 450 kb, Caspian 152 kb, External 478 kb, wiggle room 100 kb, free 260 kb, of 1440 kb total](./floppy-budget.svg)

| Tier | Bytes (kb) | Share |
| ---- | ---: | ---: |
| CLI | 450 | 31% |
| Caspian | 152 | 11% |
| External | 478 | 33% |
| wiggle room | 100 | 7% |
| **Committed** | **1,180** | **82%** |
| free | 260 | 18% |
| **Total** | **1,440** | **100%** |

**Headroom: 260 kb** against the 1.44 MB target — the free wedge in the pie.

## Tiers

- **CLI** — statically linked into the `bin/caspian` binary. The binary is a thin embedder: just the Lua 5.4 interpreter, musl libc, and the CLI shim that loads the engine. Specific to running the CLI; non-Lua embedders (Ruby, Python, other host languages) bring their own Lua interpreter and load the engine directly, so they don't need this binary at all.
- **Caspian** — everything Caspian-authored: the engine (`caspian.lua` bundle with Fiona and the Lua binding wrapper inlined), the vibecode JSON blob, and `lua-confstr`. Ships under `caspian/`. Loaded via `require()` by whatever host is embedding Caspian — the CLI, a Ruby program, a Python program. Same files, any host.
- **External** — third-party libraries the engine depends on. `.so` binaries per arch and their `.lua` wrappers where applicable, shipped under `external/`. Loaded via `require()` the same way — a host that adds `external/` to its `package.cpath` gets the whole engine's C surface for free. Bundled at exact versions rather than fetched from system packages because the engine's coupling to each lib's API is tight enough that version drift silently breaks assumptions.
- **wiggle room** — reserved slack, unassigned to any specific tier because surprise growth can happen anywhere.

## Related

- [core](https://puck.uno/requirements/core/) — the authoritative inventory of what ships, per component.
- [build](https://puck.uno/requirements/core/build) — the build script that measures the produced tree against this target on every run.
