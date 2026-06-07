# Caspian LSP build plan (post-V1)

> **Deferred from V1** (decided 2026-06-05). Originally planned as part of V1; pulled because the LSP requires a local Caspian install for editor users, conflicting with first-contact goals and remote workflows. Preserved here as the build plan for when LSP work resumes. The spec it builds is at [ideas/lsp/](../lsp/).

~~~json
{"vibecode": {
	"doc": "caspian_lsp_build_plan",
	"role": "build plan for the Caspian Language Server — phase progression, prerequisites against the Caspian engine slices, test plan, scope. Originally a V1 plan; now post-V1.",
	"status": "not_started — deferred from V1 (see banner above)",
	"feature_lock": "soft",
	"source_of_truth": "vibecode_blocks",
	"implementation_language": "caspian",
	"depends_on_caspian_engine_slice": "frank",
	"v1_features_when_active": ["diagnostics", "document_formatting", "hover",
		"local_go_to_definition", "basic_completion"]
}}
~~~

This is the V1 plan for **`caspian lsp`** — the Language Server Protocol implementation that ships bundled with the Caspian install. The spec for what `caspian lsp` does lives in [lsp.md](https://puck.uno/documentation/ideas/lsp); this doc is the build plan that gets us there.

The LSP is written in Caspian itself (dogfooding pattern, same as `install.casp`). That means it depends on the Caspian engine being far enough along to host a non-trivial long-running program with file I/O, JSON, and access to the engine's parser/AST machinery.

---

<a id="prerequisites"></a>
## Prerequisites

The LSP build doesn't start until the Caspian engine is at the right slice. From [the Caspian engine plan](https://puck.uno/documentation/requirements/development/v1/caspian/):

| LSP need | Caspian slice it requires | Why |
|---|---|---|
| `caspian lsp` invocable | [Frank](https://puck.uno/documentation/requirements/development/v1/caspian/frank) | The CLI launcher dispatches to subcommands; `caspian lsp` is one. |
| JSON-RPC encode/decode | [Edmund](https://puck.uno/documentation/requirements/development/v1/caspian/edmund) | LSP protocol is JSON-RPC. |
| Caspian source → AST | Already in [Bree](https://puck.uno/documentation/requirements/development/v1/caspian/bree) | The lexer/parser/transpiler stack is exposed to LSP code for diagnostics, hover, completion. |
| stdio I/O | [Aslan](https://puck.uno/documentation/requirements/development/v1/caspian/aslan) (stdin) + [Corin](https://puck.uno/documentation/requirements/development/v1/caspian/corin) (stdout/stderr) | Standard LSP transport. |
| `caspian fmt` to delegate to | TBD (formatter slice not yet plotted) | Document formatting feature shells out. |

**Net:** LSP work can begin once **Frank ships**. Earlier phases (bare server, diagnostics) can start in parallel with Frank if the engine team is ahead. Document formatting waits on the formatter shipping; everything else can land as soon as the engine pieces above are in.

---

<a id="phase-progression"></a>
## Phase progression

Phases are ordered by what they unlock. Each phase ends with the LSP running against a real editor (VSCode is the development driver) and providing the feature end-to-end. No phase ships in isolation; the LSP is one program that grows feature by feature.

| Phase | Delivers | What ends the phase |
|---|---|---|
| **0** | Bare server | `initialize` / `initialized` / `shutdown` / `exit` round-trip cleanly with a VSCode client; the LSP launches, handshakes, and exits cleanly. No actual language features yet. |
| **1** | Diagnostics | Editing a `.casp` file with a syntax error surfaces a squiggle in the gutter; fixing the error makes it disappear. `textDocument/publishDiagnostics` pushed on every change. |
| **2** | Document formatting | "Format Document" in VSCode reformats the file. Delegates to `caspian fmt`; output identical to the CLI. |
| **3** | Hover | Hover over a variable shows its source line and (when knowable) class. Hover over a method shows signature. |
| **4** | Local go-to-definition | Right-click → "Go to definition" on a variable/function jumps to its declaration in the same file. Cross-file deferred. |
| **5** | Basic completion | Typing triggers a completion popup: Caspian keywords, in-scope variables, methods on the receiver type. No imported-library symbols, no signature-aware filtering. |

Once Phase 5 is done, the LSP's V1 surface (per [lsp.md § What ships in V1](https://puck.uno/documentation/ideas/lsp#what-ships-in-v1)) is complete. Future-options features ([lsp.md § Future options](https://puck.uno/documentation/ideas/lsp#future-options)) are post-V1.

---

<a id="testing"></a>
## Testing

Two tiers, same as the Caspian engine plan:

- **Tier 1 — Lua-side tests** for any Lua-host scaffolding the LSP needs (JSON-RPC framing, stdio buffering harness). Minimal — most of the LSP is in Caspian.
- **Tier 2 — Bryton tests** for the LSP's Caspian-level behavior. `.casp` test files exercise each phase's feature using fixture documents and assert against expected LSP responses. Bryton ships at [Glenstorm](https://puck.uno/documentation/requirements/development/v1/caspian/glenstorm) — Phases 0–2 may have to wait for Bryton, or use a hand-rolled assertion harness on top of Caspian's own JSON/equality machinery.

**Integration tests** drive `caspian lsp` as a subprocess and exchange real LSP messages with it. Capture the response JSON, compare against expected. One test per phase's feature; smoke tests covering the protocol handshake and error recovery.

**Editor-driven manual verification** is required for each phase to end. Automated tests can prove "LSP responded with the right JSON"; only a real editor session proves "the experience works." Each phase ends only when the feature has been driven through VSCode with positive observation.

---

<a id="scope-notes"></a>
## Scope notes

**The V1 LSP intentionally stays small.** Anything in [lsp.md § Future options](https://puck.uno/documentation/ideas/lsp#future-options) is post-V1 — including cross-file analysis, find-references, rename, workspace symbol search, signature help, code actions, inlay hints, semantic tokens. Don't expand scope without explicit unlock.

**Workspace configuration discovery is unresolved.** How the LSP locates a project's library layout, `%puck` resolutions, etc. is flagged as an open question in [lsp.md § Future options](https://puck.uno/documentation/ideas/lsp#future-options). For V1, the LSP can assume single-file analysis only — no cross-file scope walking, no project-aware completion. Workspace awareness lands when cross-file analysis lands.

**Editor support is VSCode-driven during V1.** Other editors (Vim/Neovim, Emacs, Helix, Zed, etc.) can use the LSP — that's the whole point — but VSCode is the development driver because it's where the in-house extension lives. Documentation for setting up other editors lands when the surface is stable; until then, the LSP works in any editor but the setup story is "configure your LSP client to launch `caspian lsp`."

---

<a id="dependencies"></a>
## Dependencies

The LSP is pure Caspian source — no new C extensions, no new Lua libraries beyond what Caspian itself ships. The LSP runs on the same Lua + LPeg + libsodium-minimal foundation as everything else in the Caspian bundle. See [lua-dependencies.md](https://puck.uno/documentation/requirements/development/v1/details/lua-dependencies) for the complete dependency list.

Bundle footprint: ~80 KB of Caspian source, already accounted for in the [install bundle](https://puck.uno/documentation/ideas/installation/#what-the-installer-downloads).
