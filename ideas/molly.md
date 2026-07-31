# Molly — the Caspian VS Code extension

~~~vibecode
{"vibecode": {
	"doc": "ideas_molly",
	"role": "design notes for Molly, Caspian's VS Code extension. Primary purpose:
		a formatter that reformats other people's Caspian to your own preferences.
		Approach: round-trip Caspian → CaspJ → Caspian using the same transpiler
		library the Caspian runtime uses; VS Code doesn't need to understand Caspian
		syntax, it just shuttles bytes through the transpiler. Molly ships in its
		own repository, install-free for the user.",
	"status": "design — repository not yet created; transpiler forward direction
		is in flight in the Caspian repo (src/engine/transpiler.lua)",
	"key_concepts": ["vs_code_extension", "formatter", "round_trip",
		"caspj_as_intermediate", "wasmoon", "install_free", "separate_repo",
		"formatter_preferences"]
}}
~~~

Molly is Caspian's VS Code extension. Its primary purpose is not to teach VS Code the entire Caspian grammar — that's LSP-scale work Molly V1 doesn't attempt — but to provide a **formatter** that reformats Caspian source to a user's preferences. Everything else Molly does (syntax highlighting, autoclose, etc.) is a smaller supporting feature.

Molly lives in its own repository, distinct from the Caspian repo. This keeps Caspian's build/test tree focused on the language and runtime; Molly's build tooling and packaging live where they belong.

## The core insight

**Formatting is just re-serialization.** Given a Caspian file, format-on-save is:

~~~
parse(source)  |>  emit_with_preferences(caspj)
~~~

Where `parse` is Caspian → CaspJ (the forward transpiler) and `emit_with_preferences` is CaspJ → Caspian (the reverse transpiler, style-parameterized). Both directions share the SHAPE knowledge — what CaspJ looks like — but nothing else. Two focused modules on one contract.

Why this is a cleaner design than alternatives:

- **The extension stays tiny.** No grammar to maintain beyond the existing `.tmLanguage.json` for syntax highlighting. No LSP required. All syntactic understanding lives in the transpiler, not the extension. VS Code just wires up its `DocumentFormattingEditProvider` to call the transpiler and apply the result as edits.
- **Cross-editor reusability is free.** Any editor that can call the library — JetBrains, browser-hosted playgrounds, static "format my code" web pages, other extensions — gets the same formatter behavior. Molly is one host among several.
- **CaspianJ is a first-class execution input.** The runtime consumes CaspJ directly, so the reverse direction isn't operationally required for execution; it's purely a human-facing formatting concern. That keeps the reverse module's scope well-defined.
- **Idempotency is automatic.** `format(format(x)) == format(x)` holds because parsing throws away whitespace and style noise into a normalized CaspJ, and emitting is style-only given preferences. Standard formatter property, no extra work.

## Formatting preferences

Preferences are arguments to the reverse emit, not the forward parse. Initial candidates for what's tunable:

- Tabs vs spaces + indent width
- Blank-line rules around blocks (matches the existing [format skill spec](https://puck.uno/documentation/ecoverse/formatting/))
- Bracket spacing (`{a:1}` vs `{a: 1}`)
- Multi-line vs single-line for short constructs (short `if` on one line vs three)
- Comment placement rules (leading vs trailing on shared lines)
- Trailing semicolons or not
- Line-length target for wrapping

Miko-style defaults ship as one preset; other users can override via a preferences file (probably `.caspianformat` or equivalent, or straight VS Code settings). The preferences shape should be spec'd early — it's part of the reverse-transpiler contract.

## Distribution and embedding

The transpiler is written in Lua (matches the Caspian reference implementation). VS Code extensions run in Node.js, so the extension needs a way to execute Lua. Two viable install-free options:

- **wasmoon (recommended)** — Lua 5.4 compiled to WebAssembly. Matches Caspian's target Lua version, actively maintained, ≈450 KB compressed. `npm install wasmoon`; load the transpiler source at extension activation; call across the JS/Lua boundary for each format request.
- **fengari** — Lua 5.3 written entirely in JavaScript, no WASM step. ≈300 KB, faster startup, but Lua 5.3 not 5.4 (some tiny syntactic differences to guard against) and less actively maintained.

The install-free footprint:

| Component                        | Size    |
| ---                              | ---     |
| Extension code (thin)            | ≈50 KB  |
| wasmoon (Lua 5.4 WASM runtime)   | ≈450 KB |
| transpiler.lua + dependencies    | ≈20 KB  |
| Existing syntax-highlighting grammar | ≈10 KB |
| **Total**                        | **≈530 KB** |

Reasonable for a VS Code extension. Users download once from the marketplace.

## Performance

Lua-in-WASM runs ≈1×-3× slower than native Lua depending on workload. A 1000-line Caspian file formats in the 50-100 ms range. That's well within format-on-save territory — no user-visible lag. For very large files (10 000+ lines), consider an async / worker approach so the UI doesn't jank.

## The install-free constraint

Molly V1 commits to being install-free: the user installs the extension from the VS Code marketplace and it works. No `caspian` binary required on `$PATH`, no runtime download step, no `luarocks` install. The bundled wasmoon-plus-transpiler covers everything the formatter needs.

That constraint is what makes the "everything through the transpiler" design mandatory. If the user had to install the Caspian runtime anyway, Molly could just shell out to `caspian fmt`. Because it can't, Molly has to embed.

## Molly V1 scope

Primary:

- **Formatter** — via forward-then-reverse round-trip. Format-on-save and manual `Format Document`.

Supporting features (still install-free):

- **Syntax highlighting** — existing `.tmLanguage.json` grammar; already in place.
- **Language configuration** — autoclose for `()`, `[]`, `{}`, `''`, `""`; comment character `#`. Recently added.
- **File-icon and file-type registration** for `.casp` (and `.caspj`?).

Post-V1 candidates (require more scope):

- **Full LSP** — jump-to-def, hover, workspace refactor, incremental diagnostics. Bigger project, separate module.
- **Snippets** — templated inserts for common patterns. Small; can slot in whenever.
- **Playground / REPL panel** — evaluate a Caspian snippet inline; probably requires Caspian runtime, so not install-free.
- **CaspJ-mode formatter** — for `.caspj` files, format the JSON canonically. Small.

The five specific install-free features Miko has committed to for V1 aren't enumerated in a single doc yet; this list needs pinning down as a separate design decision.

## Interaction with Caspian's own transpiler

The **same transpiler library** powers:

- The Caspian runtime's source-to-CaspJ pass at execution time.
- Molly's format-on-save.
- Any future LSP's syntax-error surface.
- Web playgrounds, other-editor extensions, and CI linters.

That's why the transpiler is packaged as a **standalone module** in the Caspian repo — not tangled into the runtime's execution machinery. Molly loads it as a peer, not as part of Caspian.

Concretely: the Caspian repo publishes `transpiler.lua` (plus its dependencies) as a fetchable artifact — either bundled inside a Caspian release, or fetched from the Caspian repo at Molly's build time. Molly's package script pulls the current transpiler snapshot in, bundles it with wasmoon, ships the whole thing.

Reverse-direction module (CaspJ → Caspian, style-parameterized) is a **new** module Molly needs — it doesn't exist in the Caspian repo yet, and probably belongs in the Caspian repo alongside `transpiler.lua` for the same reason: many hosts want it, not just Molly.

## Failure modes and edge cases

- **Parse errors block formatting.** If the user's file has a syntax error, forward transpile fails, and format-on-save has nothing to emit from. Standard formatter behavior — most editors handle this gracefully (skip formatting, surface the error separately). Molly should surface the specific parse error in the Problems panel.
- **Whitespace and comments are semi-preserved.** Per Caspian's design, comments are preserved in CaspJ but exact position has wiggle room (mid-cond comments get hoisted out, for example). Format-on-save necessarily normalizes comment placement to a consistent scheme. Users who care about pixel-perfect comment placement will notice; the fix is documenting the normalization rules.
- **Round-trip stability across Caspian versions.** If the transpiler evolves and CaspJ shapes shift, older Molly bundles may produce different output than newer ones. Molly should pin the transpiler version it embeds and document how to upgrade.
- **Very large files.** As noted above, the format pass is linear-time but Lua-in-WASM has real constant factors. Async fallback for files above some threshold.

## Related

- The transpiler forward direction is in the Caspian repo at [src/engine/transpiler.lua](https://github.com/mikosullivan/puck) (not yet on puck.uno as it's implementation, not documentation).
- [concepts § Caspian is written in Caspian](https://puck.uno/requirements/concepts#caspian-is-written-in-caspian) — the design principle that makes CaspJ a first-class execution input, which is what lets Molly skip needing a runtime install.
- [mcp-cold-start-agents](https://puck.uno/ideas/mcp-cold-start-agents) — parallel design question for AI agents. Molly serves humans-in-editors; MCP serves AI agents; both benefit from the transpiler being available as a standalone library.
- The Caspian syntax-highlighting grammar is already published as the earlier "Caspian" VS Code extension. Molly V1 is essentially that extension plus the formatter plus language-configuration wiring, all in a new dedicated repo.

## Open questions

- **Repository name and slug.** `molly`, `caspian-vscode`, `molly-vscode`?
- **Package publisher name for the VS Code marketplace.** `mikobase`, `caspian`, `puck`?
- **Preferences schema.** What's tunable in V1, what's deferred? File format for `.caspianformat`? Or VS Code settings only?
- **Enumerate the 5 install-free V1 features.** Currently in memory as "5 install-free features"; specifics not written down.
- **Transpiler versioning between Molly and Caspian.** Semver in the Caspian repo's transpiler module? A fetchable snapshot URL that Molly's build script consumes?
- **Reverse transpiler lives where?** Caspian repo (peer to forward) or Molly repo? Recommendation: Caspian repo, since other hosts benefit too.
- **CaspJ formatter mode.** Should Molly also format `.caspj` files (JSON, canonically)? Small feature but a real user-visible surface.
- **JetBrains and other-editor equivalents.** Named or spec'd yet? Same library, different host wiring; worth flagging the reusability early.
