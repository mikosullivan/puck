# Charlie in the browser

```
vibecode: {
    "status": "active_brainstorm",
    "started": "2026-05-17",
    "subsystem": "browser_charlie_engine",
    "purpose": "run_an_entire_charlie_processor_inside_a_web_browser",
    "related_docs": ["vscode-extension.md", "vscode-extension-v2.md"],
    "related_memories": ["feedback_first_contact_strategy"],
    "co_authoring": "claude_capturing_miko_brainstorm_in_realtime"
}
```

Brainstorm in progress.

---

<a id="why"></a>
## 1 Why

```
vibecode: {
    "section": "motivation",
    "use_cases": ["online_sandbox_playground", "spec_docs_with_live_runnable_examples",
                   "tutorials_and_learning", "browser_repl", "zero_install_marketing_demos"],
    "first_contact_alignment": "matches_feedback_first_contact_strategy_user_experiences_charlie_before_installing"
}
```

A Charlie engine that runs entirely in the browser unlocks:

- **Online sandbox / playground** — like Rust Playground, Go Playground,
  kotlinplayground.com. Standalone URL; type code, click Run, see output.
- **Spec docs with live examples** — the existing markdown specs could
  embed runnable snippets right next to the prose. Click Run on the
  hello-world fixture and watch it return `"hello"`. Beats screenshots.
- **Tutorials and learning** — interactive walkthroughs where the
  reader edits and re-runs each example.
- **Browser REPL** — a single page that lets someone type Charlie at a
  prompt and see results.
- **Zero-install marketing demos** — the lowest possible bar to "try
  it." No CLI install, no Puck setup; just click a link.

All of these align with the [[feedback_first_contact_strategy]] memory:
let people experience Charlie before buying into the whole system.

---

<a id="architecture-three-independent-artifacts"></a>
## 2 Architecture: three independent artifacts

```
vibecode: {
    "section": "architectural_decisions",
    "decided_2026-05-17": true,
    "for_browser_sandbox": "wasm_compiled_lua_engine",
    "for_community_and_portability": "ts_engine_consuming_charliejson_only",
    "for_source_parsing_in_typescript": "ts_parser_per_vscode_extension_v2",
    "rejected": "hybrid_ts_parser_plus_wasm_lua_engine_too_much_glue",
    "all_three_artifacts_independent_and_can_ship_separately": true,
    "composition_possible": "ts_parser_plus_ts_engine_gives_full_source_to_result_pipeline_in_pure_js"
}
```

Three distinct artifacts, each with its own job, all independently
shippable. The browser sandbox uses one (the WASM engine); the other
two are for adjacent purposes that compose freely with it.

<a id="artifact-1-wasm-compiled-lua-engine-the-browser-sandbox"></a>
### 2.1 Artifact 1: WASM-compiled Lua engine — the browser sandbox

The canonical Lua reference engine compiled to WASM (Fengari, lua.vm.js,
wasm-lua, or similar). Run the same engine bytes in the browser as on
the server.

- **Pros**: single canonical implementation; zero synchronization
  burden; the browser engine IS the Lua engine.
- **Cons**: bigger payload (Lua-as-WASM is hundreds of KB to several
  MB depending on tooling); WASM ↔ JS bridge for host calls.
- **Use case**: online playground; doc pages with live runnable
  examples; zero-install marketing demo.

This is the **primary browser sandbox approach**.

<a id="artifact-2-ts-charliejson-only-engine-community-and-portability"></a>
### 2.2 Artifact 2: TS CharlieJSON-only engine — community and portability

A TypeScript engine that **consumes canonical CharlieJSON** and
executes it. No Charlie source parser. No transpiler. Just the
runtime: bootstrap, materialize, dispatch, role transition, built-in
classes.

- **Pros**: small scope (parallels V0.01 Lua engine exactly —
  CharlieJSON-only execution); community-readable mainstream-language
  reference implementation; validates the canonical CharlieJSON spec by
  forcing it to be precise enough for two implementations to agree;
  drop-in for web tooling that has CharlieJSON in hand and wants to execute
  it.
- **Cons**: a parallel implementation to keep in semantic sync with
  the Lua reference engine; doesn't accept Charlie source on its
  own.
- **Use case**: a JS/TS project that has a CharlieJSON tree (hand-written,
  transpiled elsewhere, or emitted by Artifact 3) and wants to run
  it without spinning up Lua. Also a clean educational reference
  for "how does a Charlie engine work" without the parser
  complexity.

**Parity test**: run the V0.01 `hello_world.ksj` fixture through both
the Lua engine and this TS engine; both must return a value with
`payload == "hello"`. Same fixture, same expected output. The Lua
engine's existing tests (now 213/213) become the conformance suite.

<a id="artifact-3-ts-source-parser-already-in-v2-extension-plans"></a>
### 2.3 Artifact 3: TS source parser — already in V2 extension plans

A TS-only Charlie parser, planned in
[vscode-extension-v2.md](vscode-extension-v2.md) for the formatter
work. Source → CharlieJSON.

- **Use case**: VS Code extension formatter (its original motivation),
  plus build pipelines, doc tooling, etc.
- **Composes with Artifact 2**: TS parser + TS engine = full
  source-to-result pipeline in pure JS, no WASM, no Lua. Useful for
  contexts where the WASM payload is too heavy or where pure-JS is
  required (some embedded JS environments don't support WASM).

<a id="what-was-rejected"></a>
### 2.4 What was rejected

A **hybrid** (TS parser handing CharlieJSON to a WASM-Lua engine) was on the
table but rejected as too much glue for not enough benefit. Each side
(TS, WASM-Lua) is well-suited to its own combinations; mixing them in
one runtime adds bug surface at the parse/execute boundary without
saving meaningful effort.

---

<a id="why-charlie-is-particularly-well-suited"></a>
## 3 Why Charlie is particularly well-suited

```
vibecode: {
    "section": "good_fit",
    "factors": ["role_model_is_a_perfect_sandbox_fit",
                 "currently_tiny_stdlib_means_small_payload",
                 "engine_already_designed_for_untrusted_code"]
}
```

- **The role model is a perfect sandbox fit.** Charlie already has a
  role-based capability system designed for "run untrusted code with
  a restricted surface" (see [roles.md](../charlie/roles.md)).
  Browser-embedded Charlie is exactly that use case. Just don't grant
  filesystem/network/eval roles; the browser also isolates the JS/WASM
  layer. Two layers of defense.
- **Tiny stdlib right now.** V0.01 ships exactly one method
  (`string.to_string`). A v1 browser engine for the current language
  surface would be very small. It grows in step with the stdlib.
- **Engine designed for hostable scenarios.** The Lua engine already
  separates host-level concerns (file reading, stdout) from runtime
  concerns. A browser host is just another shape of host —
  `engine.run_source(text)` with a capture buffer for stdout
  (already in V0.03 plan).

---

<a id="open-questions"></a>
## 4 Open questions

- **Which architectural option?** Native TS reimplementation vs WASM
  Lua vs hybrid. Each has real trade-offs; no clear winner without
  more design conversation.
- **Bundle size budget.** What's an acceptable payload for a
  playground page? Affects which option is viable. Pyodide is ~25MB
  (rules out tight pages); ruby.wasm is ~10MB; a hand-tuned Charlie
  engine could be <1MB while the stdlib is small.
- **Built-in capabilities for the browser host.** What roles get
  granted by default in a playground context? Likely: `user`,
  `clock`, `randomizer`, `utils`, plus a virtual stdout (text area)
  and stdin (input field). NOT: filesystem, network (unless via a
  controlled fetch faucet), env vars, child processes.
- **Persistence story.** Does the playground save state across
  reloads? localStorage? Per-session only? A "share this code"
  URL-encoding mechanism? Pure session vs persistence is a UX call.
- **Relationship to the canonical engine's `engine.run_source(text)`
  API** (V0.02/V0.03 spec). The browser engine should present the
  same public interface; the host (browser vs CLI vs server) is what
  varies.
- **Versioning.** When the canonical engine ships a new version, how
  does the browser engine stay in sync? Less of an issue if Option 2
  (WASM Lua) — the same artifact deploys both places.

---
