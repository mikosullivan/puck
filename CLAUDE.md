# CLAUDE.md

~~~json
{"vibecode": {
	"doc": "claude-md",
	"role": "project-guidance file for Claude Code: repo overview, layout, build/test commands, conventions, and design principles to honor when editing this codebase",
	"key_concepts": ["puck_ecoverse", "walking_skeleton_v001", "two_tier_testing",
		"engine_pipeline", "vibecode_blocks", "no_nanny_code"]
}}
~~~

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Cross-project AI preferences

User-level AI collaboration preferences live in [~/CLAUDE.md](../../../../CLAUDE.md) — communication style, workflow cadence, writing conventions, and engineering principles that travel with Miko across every project. Claude Code reads that file automatically. This project's CLAUDE.md (the one you're reading) only covers things specific to this codebase.

## What this repo is

The Puck ecoverse: a designed-from-scratch suite of interconnected tools (Caspian language, Mikobase object store, Puck remote-object protocol, etc.). The repository is **design-heavy and implementation-early** — the bulk of value lives under [documentation/](documentation/), and code under [code/](code/) is a walking skeleton.

The directory is named `mikobase` for historical reasons; the umbrella name is **Puck**. Read [README.md](README.md) and [documentation/overview.md](documentation/overview.md) before doing substantive design work.

Current development target is **V0.01 "hello-world"** — see [documentation/development/index.md](documentation/development/index.md) for the walking-skeleton roadmap and the canonical statement of what is in/out of scope. The development plan uses a **soft feature lock**: do not expand V0.01 scope without explicit unlock.

## Repo layout (non-obvious bits)

- [documentation/](documentation/) — canonical specs. Markdown here is the source of truth.
- [code/](code/) — implementation, organized by component then host language: `code/<component>/<lang>/`. Only `lib/lua/caspian/` has substantial code today; `code/mikobase/`, `code/puck/`, `code/dogberry/` are placeholders for future work.
- [tests/](tests/) — mirrors `code/` shape. Only `tests/caspian/` has tests today.
- [experiments/](experiments/) — scratch files; not part of the build or tests.
- [domain/](domain/) — one-off Ruby script for finding available `.io` domain names ([domain/find_io.rb](domain/find_io.rb)). Unrelated to Puck the protocol.
- [web/](web/) — nginx site config for the portia host. Not application code.
- [vscode/](vscode/) — VSCode extension scaffolding for Caspian syntax highlighting.
- `settings.json` at the repo root is **gitignored**. Any `settings.json` you see locally is a personal config and may legitimately contain hardcoded credentials — do not flag those.

## Build, run, test

There is no build step. The Lua reference engine runs directly.

**Run the Lua test suite (currently the only test suite):**
```
lua5.4 tests/caspian/run.lua
```
Run from the repo root — the runner sets `package.path` to resolve `require("caspian")` against `lib/lua/caspian/` and test modules against `tests/caspian/`. Exits 0 on all pass, 1 on any failure. Requires Lua 5.4.

**Use `lua5.4` explicitly, not bare `lua`.** On systems with multiple Lua versions, `lua` may resolve to an older version; `lua5.4` is unambiguous. See [aslan.md § Lessons learned](documentation/development/v1/caspian/aslan.md#lessons-learned) for context.

**Always run the full test suite before moving to a new milestone.** No "I'll just check this one file" — run everything. Regressions in unrelated areas are how walking-skeleton development falls apart. The full suite is fast (under a second for current scope); there's no cost reason to skip it.

**Run a single test file:** edit [tests/caspian/run.lua](tests/caspian/run.lua) and comment out the other `require` lines, or `require` the single file from a one-liner with the same `package.path` prefix. There is no built-in single-test filter.

**Test framework** is the minimal `support/runner.lua` + `support/assert.lua` in [tests/caspian/support/](tests/caspian/support/) — `runner.suite(name)`, `runner.test(desc, fn)`, `runner.report()`. Module-global accumulator; don't `require` from multiple processes.

## Two-tier testing model

The development plan distinguishes two test tiers and they have different homes — keep them separate:

- **Tier 1 — Lua tests** for the engine and any other Lua-implemented infrastructure (including the Bryton runner itself, once written). Permanent. Lives next to the implementation in `tests/caspian/`.
- **Tier 2 — Bryton tests** for Caspian-level language behavior. `.casp` files emit Xeme JSON; a Bryton runner walks a directory and aggregates. Arrives at V0.1. Until then, Caspian-level behavior is tested via Lua-host harnesses that stage the parsed tree on `engine.caspianj` and call `engine.run()`, then assert on the return value.

Engine tests never migrate to Bryton.

## Engine architecture (Lua reference)

Two modules the host touches:

- **[lib/lua/caspian/engine.lua](lib/lua/caspian/engine.lua)** — the executor. Host configures via properties (`engine.caspianj`, `engine.std`, `engine.root`) then calls `engine.run()` with no args. Also hosts `engine.parse_caspian(source)` for the source-to-tree pipeline.
- **[lib/lua/caspian/init.lua](lib/lua/caspian/init.lua)** — lower-level entry points: `caspian.tokenize`, `caspian.parse`, `caspian.dump`, `caspian.null`. Useful for tooling that needs just tokens or just an AST.

```
Caspian source  →  lexer  →  parser  →  transpiler  →  CaspianJ  →  engine
                              (engine.parse_caspian)                 (engine.run)
```

Modules under [lib/lua/caspian/](lib/lua/caspian/): `engine.lua`, `lexer.lua`, `parser.lua`, `transpiler.lua`, `json.lua`. (`interpreter.lua` is dead code from the pre-Aslan pipeline; pending removal.) CaspianJ is the canonical runtime format — the engine consumes CaspianJ, never Caspian text. V0.01 hand-writes CaspianJ fixtures and bypasses the source-text path entirely.

Use `caspian.null` (re-exported as `json.null`) for JSON null in CaspianJ tables; Lua `nil` cannot round-trip.

## Conventions visible across the codebase

These are project-wide, not personal preferences — follow them in any file you edit:

- **Vibecode blocks.** Most documentation sections begin with a `vibecode:` JSON block giving AI-readable context for the surrounding prose. When adding or editing a documentation section, include or update its vibecode block. The development plan explicitly states vibecode blocks are the source of truth where prose disagrees with them.
- **UNS (Universal Namespace)** for class names: a URL without `https://`, e.g. `foo.com/character`. Built-ins are under `puck.uno/...`.
- **Reserved pass-through fields** on every Puckverse object: `vibecode`, `comment`, `misc`, `corporate`. Always passed through; never stripped or validated. See [documentation/ecoverse/standard-fields.md](documentation/ecoverse/standard-fields.md).
- **Module headers in Lua code** are JSON `--[[ {...} ]]` blocks describing role, pipeline, exports, and dependencies. Per-function headers describe `in`/`out`/`note`. Match this style in new Lua code.
- **Field names use underscores; file names use dashes.** `fail_fast` in JSON, `foo-bar.md` on disk.
- **MIT license** for any code distributed through the ecosystem.

## Miko's formatting preferences

Miko's personal code-formatting preferences live at [documentation/ecoverse/formatting/miko.json](documentation/ecoverse/formatting/miko.json) — the canonical source of truth. Consult it when generating or editing code in this repo: it covers indent, line rules, and per-language overrides.

The format spec the file follows is at [documentation/ecoverse/formatting/index.md](documentation/ecoverse/formatting/index.md). Per that spec's philosophy, these are personal preferences and not project policy, but for code written for Miko in this repo, miko.json is the working default.

## Design principles to honor when proposing changes

- **No nanny code.** The system does not block legitimate developer choices for paternalism. Safe defaults and security guarantees stay; "you can't because I think you shouldn't" is rejected. See [documentation/overview.md](documentation/overview.md) "No Nanny Code".
- **Caspian is single-threaded by default.** Forking is an opt-in, engine-granted feature; do not assume concurrency primitives in the language.
- **Mikobase is always a live process**, not a passive file.
- **Libraries are cached, not installed.** No package manager, no lockfile, no manifest — libraries are referenced by UNS and resolved on demand through a provider chain.
- **Surface conflicts; don't silently pick a winner.** When spec and code disagree, or two specs disagree, flag both sides and ask which way to resolve. There is no universal "spec wins" or "code wins" rule. The one documented exception is the development plan: vibecode blocks win over surrounding prose.
- **Don't formalize emerging conventions prematurely.** Describe informal patterns descriptively ("current usage clusters around…"), not prescriptively, until they've earned a rule.
