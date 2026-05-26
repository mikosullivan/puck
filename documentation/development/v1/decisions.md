# V1 design decisions log

~~~json
{"vibecode": {
	"doc": "v1_design_decisions_log",
	"role": "consolidated index of design decisions made during V1 planning; not a spec — pointers to where each decision is canonically documented",
	"status": "living document — append new decisions as they land",
	"format": "one row per decision: short statement + canonical doc reference"
}}
~~~

This page is an **index of decisions**, not the spec itself. Each row
captures a decision in one line and points to the canonical doc where
the full context lives. When two specs disagree, the **canonical
location wins**; this log is just a finder.

---

<a id="slice-and-roadmap"></a>
## Slice structure and roadmap

| Decision | Canonical reference |
|---|---|
| V1 development happens in named slices, not numbered versions. Numbers were removed from titles and identifiers. | [v1.md](v1.md) |
| Slices are alphabetical real English words. New slices between existing ones need a word that sorts between adjacent codenames. | [project_version_codenames memory](../../../../home/miko/.claude/projects/-home-miko-projects-kiera-working/memory/project_version_codenames.md) |
| Current sequence: Ashley → Aslan → Bree → Corin → Digory → Edmund → Frank → Gabbo → Glenstorm. | [v1.md § Slice progression](v1.md#slice-progression) |
| Nothing ships until V1.0. Intermediate slices are development checkpoints with their own definitions of done. | [v1.md](v1.md) |
| Each slice ends runnable. Walking-skeleton development, end-to-end thin band per slice. | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| Minimal surface per slice. No "generalize ahead of the test." | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| Tests drive the roadmap. What's missing in the next test is what gets built next. | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| Soft feature lock — anything not specced as V1 is deferred. | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| Roles are baked in from Aslan, not bolted on. | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| Skeletor state hash is baked in from Aslan, not bolted on. | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| Ashley is the baseline-inventory slice. Documents existing code; no new code. | [ashley.md](ashley.md) |

---

<a id="engine-and-runtime"></a>
## Engine and runtime

| Decision | Canonical reference |
|---|---|
| CaspianJ is the canonical runtime format. The engine consumes it; Caspian text transpiles to it. | [caspianj.md](../../caspian/caspianj.md) |
| Statement shape is uniform: `[receiver, method, arg1?, arg2?, ...]`. No `setvar`, no `'&'` sigil, no `{args:...}` wrapper. | [caspianj.md § Core Principle](../../caspian/caspianj.md#core-principle) |
| Positional args are variadic at index 3+. Each comma-separated Caspian arg becomes one CaspianJ slot. | [caspianj.md § Core Principle](../../caspian/caspianj.md#core-principle) |
| Kwargs are a single hash at index 3. Distinguish from a single positional hash literal by expression-marker key (`value`, `var`, `hash`, etc.). | [caspianj.md § Core Principle](../../caspian/caspianj.md#core-principle) |
| Assignment (`=`) is a regular method dispatch. No special form. `{"var": "foo"}` in receiver position materializes to an lvalue handle. | [caspianj.md § Assignment](../../caspian/caspianj.md#assignment) |
| The existing `interpreter.lua` consumes a pre-spec format and is retired incrementally as later slices realign each AST node. | [ashley.md § Format gap](ashley.md#format-gap) |
| Skeletor's Aslan state hash holds a single `call_stack` field with one `top_level` frame carrying role + chain. No top-level `current_role` or `chain` — those are derived from the top frame. Later slices grow the hash without changing shape. | [aslan.md § Data structures](aslan.md#data-structures-lua-tables), [skeletor.md](../../caspian/skeletor/skeletor.md) |
| Lua's table-reference semantics is V0.01's reference model. No custom object-id scheme. | [aslan.md § Notes on the sketch](aslan.md#notes-on-the-sketch) |
| Garbage collection lives in its own doc. Deterministic, root-trace, with strict `on_close` rules. | [garbage-collection.md](../../caspian/garbage-collection.md) |

---

<a id="parser-and-regex"></a>
## Parser, regex, and source pipeline

| Decision | Canonical reference |
|---|---|
| Hand-rolled lexer/parser/transpiler stay. Don't switch to LPeg-grammar. | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| LPeg is the V1 default pattern engine for regex (provides alternation). Lua patterns stay as the lightweight fallback. | [regexes.md](../../caspian/syntax/regexes.md) |
| Caspian's regex syntax compiles to LPeg under the hood (TBD: regex-style vs native LPeg syntax — open question). | [regexes.md § Pattern syntax](../../caspian/syntax/regexes.md#pattern-syntax) |
| JSON parser is pure Lua (no lua-cjson C dependency). | [details/lua-dependencies.md](details/lua-dependencies.md) |

---

<a id="dependencies-and-footprint"></a>
## Dependencies and disk footprint

| Decision | Canonical reference |
|---|---|
| Pure Lua is the baseline. C extensions only when the cost is worth it. | [v1.md § Cross-cutting principles](v1.md#cross-cutting-principles) |
| V1 accepts two C extensions: **libsodium-minimal** (Ed25519 signing + secure random) and **LPeg** (alternation + parsing toolkit). | [details/lua-dependencies.md](details/lua-dependencies.md) |
| libsodium-minimal is the build variant (`--enable-minimal`) — ~200 KB, not the full ~700 KB. | [details/lua-dependencies.md § libsodium](details/lua-dependencies.md#libsodium) |
| Avoid the word "crypto" in docs — name the specific primitive (Ed25519 signing, secure random, SHA-256) unless genuinely needed. | [feedback memory](../../../../home/miko/.claude/projects/-home-miko-projects-kiera-working/memory/feedback_avoid_crypto_word.md) |
| Install footprint target: under 1 MB; fits a 1.44 MB floppy with room to spare. Floppy is a soft commitment that drives dep decisions. | [installation.md § Download budget](../../ideas/installation/installation.md#download-budget) |
| Total install ≈ 850 KB: Lua 250, libsodium-minimal 200, Caspian files 340, LPeg 50, luasodium 10. | [installation.md § Download budget](../../ideas/installation/installation.md#download-budget) |
| The `caspj/` on-disk cache (next to source) skips lexer/parser/transpiler on subsequent runs. Lands in Gabbo slice. | [caspj-cache.md](../../ideas/caspj-cache.md), [gabbo.md](gabbo.md) |
| Cache validity: engine version + transpiler version + source mtime + source SHA-256. Atomic temp-then-rename writes. | [caspj-cache.md § Validity](../../ideas/caspj-cache.md#validity) |

---

<a id="install-experience"></a>
## Install experience

| Decision | Canonical reference |
|---|---|
| One-line `curl \| sh` install. Pre-built bundle, no from-source build for the common path. | [installation.md](../../ideas/installation/installation.md) |
| Default install location: `~/caspian/` — single visible directory holding everything (engine + libs + examples). Not `~/.caspian/`. | [linux.md](../../ideas/installation/linux.md) |
| PATH addition prepends: `$HOME/caspian/bin:$PATH`. Matches rustup/nvm/deno/bun convention. | [linux.md](../../ideas/installation/linux.md) |
| Per-user vs system-wide is a prompt at the first install step. Interactive only. | [linux.md § The conversation begins](../../ideas/installation/linux.md#the-conversation-begins) |
| Interactive install: examples copied to `~/caspian/` by default (Y). Non-interactive: no copy. | [non-interactive.md](../../ideas/installation/non-interactive.md) |
| The installer itself is a Caspian program (`install.casp`) bootstrapped from a tiny POSIX wrapper. First-contact dogfooding. | [linux.md § Under the hood](../../ideas/installation/linux.md#under-the-hood) |
| Caspian always bundles its own Lua — never shares with system Lua, even if versions match. ABI guarantee. | [linux-with-existing-lua.md](../../ideas/installation/linux-with-existing-lua.md) |
| VSCode extension is a thin LSP client. Caspian itself comes from the standard install; the extension offers to run it if missing. | [vscode.md](../../ideas/installation/vscode.md) |

---

<a id="docs-conventions"></a>
## Documentation conventions

| Decision | Canonical reference |
|---|---|
| Directory trees use 3-char single-dash indent (`├─ `, `└─ `, `│  `). | [feedback memory](../../../../home/miko/.claude/projects/-home-miko-projects-kiera-working/memory/feedback_tree_format.md) |
| Test IDs use codename-letter prefixes: TA (Aslan), TB (Bree), TC, TD, TE, TF, TGa (Gabbo), TGl (Glenstorm). | Slice files (each slice's Testing section) |
| Headings drop version numbers. Codename-only. | Slice files |
| Skeletor JSON snapshots in slice docs render with a purple border (Orlando page.lua). | [orlando/lua/orlando/page.lua](../../../orlando/lua/orlando/page.lua) (`mark_skeletor_blocks`) |
| TOC sits directly under the H1, before vibecode. | [orlando/lua/orlando/page.lua](../../../orlando/lua/orlando/page.lua) (`insert_auto_toc`) |
| Search results show the doc's intro prose (post-H1, post-vibecode, pre-first-H2). | [orlando/lua/orlando/search.lua](../../../orlando/lua/orlando/search.lua) |
| Search ranking: 10 pts filename match, 5 pts title match, 1 pt per body hit. | [orlando/lua/orlando/search.lua](../../../orlando/lua/orlando/search.lua) |

---

<a id="infrastructure"></a>
## Infrastructure

| Decision | Canonical reference |
|---|---|
| Quick-add endpoint is IP-gated to the same allow-list as Edit (2026-05-26, after the "katana" spam batch). | [project_quick_add_open memory](../../../../home/miko/.claude/projects/-home-miko-projects-kiera-working/memory/project_quick_add_open.md) |
| Edit feature gated by `~/.orlando/config.json` `edit.allowed_ips` (IP allow-list, checked at page render + API). | [orlando/lua/orlando/config.lua](../../../orlando/lua/orlando/config.lua) |
| `tests/caspian/` reorganized: existing pipeline tests under `v00/`; Aslan tests under `v001/`. Renames to `ashley/`/`aslan/` deferred to each slice's first edit. | [ashley.md § What's in tests/caspian/](ashley.md#existing-tests) |

---

<a id="open-questions"></a>
## Open / deferred

These came up during V1 design but were explicitly deferred or are
awaiting more context:

- **Lua-side API design** — under active work (see [ideas/lua-api.md](../../ideas/lua-api.md)).
- **Pre-spec → canonical realignment plan, slice by slice.** Each slice's "Step 1: Inventory" enumerates what it realigns. Cumulative plan is implicit, not yet written as a single chart.
- **Caspian regex syntax surface** (PCRE-like compiled to LPeg vs native LPeg syntax). [regexes.md § Pattern syntax](../../caspian/syntax/regexes.md#pattern-syntax).
- **Variable read materialization** — `{"var": "foo"}` in non-receiver position. Sketch exists in caspianj.md assignment section; engine.materialize specifics TBD.
- **`v00/`/`v001/` test-dir renames** to `ashley/`/`aslan/`. Deferred to each slice's first edit.
- **172-passing-tests verification** — pending Lua 5.4 install (see [ashley.md § Known issues](ashley.md#known-issues)).
