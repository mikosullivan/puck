# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The Kiera ecoverse: a designed-from-scratch suite of interconnected tools (KScript language, Mikobase object store, Kiera remote-object protocol, etc.). The repository is **design-heavy and implementation-early** — the bulk of value lives under [documentation/](documentation/), and code under [code/](code/) is a walking skeleton.

The directory is named `mikobase` for historical reasons; the umbrella name is **Kiera**. Read [README.md](README.md) and [documentation/overview.md](documentation/overview.md) before doing substantive design work.

Current development target is **V0.01 "hello-world"** — see [documentation/development/development.md](documentation/development/development.md) for the walking-skeleton roadmap and the canonical statement of what is in/out of scope. The development plan uses a **soft feature lock**: do not expand V0.01 scope without explicit unlock.

## Repo layout (non-obvious bits)

- [documentation/](documentation/) — canonical specs. Markdown here is the source of truth; the published HTML at https://mikosullivan.github.io/kiera-docs/ is a derivative and is regenerated from these files. **Do not regenerate the HTML unless explicitly asked.**
- [code/](code/) — implementation, organized by component then host language: `code/<component>/<lang>/`. Only `code/kscript/lua/kscript/` has substantial code today; `code/mikobase/`, `code/kiera/`, `code/dogberry/` are placeholders for future work.
- [tests/](tests/) — mirrors `code/` shape. Only `tests/kscript/` has tests today.
- [experiments/](experiments/) — scratch files; not part of the build or tests.
- [domain/](domain/) — one-off Ruby script for finding available `.io` domain names ([domain/find_io.rb](domain/find_io.rb)). Unrelated to Kiera the protocol.
- [web/](web/) — nginx site config for the portia host. Not application code.
- [vscode/](vscode/) — VSCode extension scaffolding for KScript syntax highlighting.
- `settings.json` at the repo root is **gitignored**. Any `settings.json` you see locally is a personal config and may legitimately contain hardcoded credentials — do not flag those.

## Build, run, test

There is no build step. The Lua reference engine runs directly.

**Run the Lua test suite (currently the only test suite):**
```
lua tests/kscript/run.lua
```
Run from the repo root — the runner sets `package.path` to resolve `require("kscript")` against `code/kscript/lua/kscript/` and test modules against `tests/kscript/`. Exits 0 on all pass, 1 on any failure. Requires Lua 5.4.

**Run a single test file:** edit [tests/kscript/run.lua](tests/kscript/run.lua) and comment out the other `require` lines, or `require` the single file from a one-liner with the same `package.path` prefix. There is no built-in single-test filter.

**Test framework** is the minimal `support/runner.lua` + `support/assert.lua` in [tests/kscript/support/](tests/kscript/support/) — `runner.suite(name)`, `runner.test(desc, fn)`, `runner.report()`. Module-global accumulator; don't `require` from multiple processes.

## Two-tier testing model

The development plan distinguishes two test tiers and they have different homes — keep them separate:

- **Tier 1 — Lua tests** for the engine and any other Lua-implemented infrastructure (including the Bryton runner itself, once written). Permanent. Lives next to the implementation in `tests/kscript/`.
- **Tier 2 — Bryton tests** for KScript-level language behavior. `.kscript` files emit Xeme JSON; a Bryton runner walks a directory and aggregates. Arrives at V0.1. Until then, KScript-level behavior is tested via Lua-host harnesses that call `engine.run("X.kscript")` and assert on the return value.

Engine tests never migrate to Bryton.

## Engine architecture (Lua reference)

Single public entry point: [code/kscript/lua/kscript/init.lua](code/kscript/lua/kscript/init.lua), which composes the pipeline:

```
KScript source  →  lexer  →  parser  →  transpiler  →  KScriptJSON  →  interpreter
                                                                       (or json.encode)
```

Modules under [code/kscript/lua/kscript/](code/kscript/lua/kscript/): `lexer.lua`, `parser.lua`, `transpiler.lua`, `interpreter.lua`, `json.lua`. KScriptJSON is the canonical runtime format — the interpreter consumes KScriptJSON, never KScript text. V0.01 hand-writes KScriptJSON fixtures and bypasses the source-text path entirely.

Use `kscript.null` (re-exported as `json.null`) for JSON null in KScriptJSON tables; Lua `nil` cannot round-trip.

## Conventions visible across the codebase

These are project-wide, not personal preferences — follow them in any file you edit:

- **Vibecode blocks.** Most documentation sections begin with a `vibecode:` JSON block giving AI-readable context for the surrounding prose. When adding or editing a documentation section, include or update its vibecode block. The development plan explicitly states vibecode blocks are the source of truth where prose disagrees with them.
- **UNS (Universal Namespace)** for class names: a URL without `https://`, e.g. `foo.com/character`. Built-ins are under `kiera.uno/...`.
- **Reserved pass-through fields** on every Kieraverse object: `vibecode`, `comment`, `misc`, `enterprise`. Always passed through; never stripped or validated. See [documentation/ecoverse/vibecode.md](documentation/ecoverse/vibecode.md).
- **Module headers in Lua code** are JSON `--[[ {...} ]]` blocks describing role, pipeline, exports, and dependencies. Per-function headers describe `in`/`out`/`note`. Match this style in new Lua code.
- **Field names use underscores; file names use dashes.** `fail_fast` in JSON, `foo-bar.md` on disk.
- **MIT license** for any code distributed through the ecosystem.

## Design principles to honor when proposing changes

- **No nanny code.** The system does not block legitimate developer choices for paternalism. Safe defaults and security guarantees stay; "you can't because I think you shouldn't" is rejected. See [documentation/overview.md](documentation/overview.md) "No Nanny Code".
- **KScript is single-threaded by default.** Forking is an opt-in, engine-granted feature; do not assume concurrency primitives in the language.
- **Mikobase is always a live process**, not a passive file.
- **Libraries are cached, not installed.** No package manager, no lockfile, no manifest — libraries are referenced by UNS and resolved on demand through a provider chain.
- **Surface conflicts; don't silently pick a winner.** When spec and code disagree, or two specs disagree, flag both sides and ask which way to resolve. There is no universal "spec wins" or "code wins" rule. The one documented exception is the development plan: vibecode blocks win over surrounding prose.
- **Don't formalize emerging conventions prematurely.** Describe informal patterns descriptively ("current usage clusters around…"), not prescriptively, until they've earned a rule.
