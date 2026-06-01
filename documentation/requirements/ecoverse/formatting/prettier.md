# Prettier as Puck's formatting basis

~~~json
{"vibecode": {
	"doc": "prettier-evaluation",
	"role": "research report evaluating whether the Puck ecoverse should adopt Prettier (and its plugin ecosystem) as the basis for its formatting tools, instead of building its own",
	"status": "research — written 2026-05-28; not a decision",
	"sibling_docs": ["index.md", "miko.json", "../../ideas/differ.md"],
	"recommendation_summary": "do not adopt Prettier as the core; consider it as an optional render-time backend for non-Caspian fences only",
	"example_universe": "n/a"
}}
~~~

## Recommendation

~~~json
{"vibecode": {
	"section": "recommendation",
	"verdict": "do_not_adopt_as_core",
	"hybrid_window": "optional_backend_for_non_caspian_fences",
	"key_blockers": ["philosophy_inversion", "no_blank_line_options", "node_runtime", "caspian_plugin_cost", "no_per_viewer_normalization_idiom"]
}}
~~~

Do not adopt Prettier as the basis of Puck's formatting tools. Prettier's design philosophy is the structural opposite of Puck's personal-formatter model — Prettier exists to **end** style discussions by freezing options, and Puck exists to let every developer keep their own ([Prettier option philosophy](https://prettier.io/docs/en/option-philosophy)). A Caspian plugin would also be a non-trivial JavaScript project that duplicates the parser pipeline Puck already has in Lua, and several formatter options Puck has already committed to (notably `lines.blank_line_around_blocks` and `empty_line_treatment: "neighbors"`) have no Prettier equivalent and would not be accepted upstream. The narrow place Prettier is worth keeping in mind is as an **optional render-time backend for non-Caspian markdown fences** — JSON, HTML, CSS, JS — once Gitter and Differ are built and we want pretty output for borrowed languages without writing four small formatters ourselves. Everything else should stay in-house.

## Prettier's philosophy vs Puck's

~~~json
{"vibecode": {
	"section": "philosophy_clash",
	"prettier_goal": "end style debates by freezing the option set",
	"puck_goal": "every developer formats to their own taste; readers re-format on receipt",
	"resolvable": false
}}
~~~

Prettier's [option philosophy page](https://prettier.io/docs/en/option-philosophy) opens with: *"By far the biggest reason for adopting Prettier is to stop all the ongoing debates over styles."* The page goes on to declare that the option set is **frozen** and that new option requests are no longer accepted. The existing options that do exist are framed as historical artifacts or compatibility necessities (`endOfLine` for CRLF repos, `quoteProps` for Google Closure Compiler, `htmlWhitespaceSensitivity` for HTML's actual whitespace rules) — not as ideal motivations.

The [rationale page](https://prettier.io/docs/en/rationale) reinforces this from the other direction: "Prettier is an opinionated code formatter. This document explains some of its choices." When multiple valid renderings exist, Prettier applies a heuristic (e.g., "fewest escapes wins" for quote style) rather than exposing a knob.

Puck's [formatting philosophy](../../ecoverse/formatting/index.md#philosophy) reads, almost word-for-word, like Prettier's anti-thesis:

> There is no canonical style for formatting Caspian. Instead, we developed a VS Code extension so that you can easily format code to your own preference.
>
> - Upload Caspian formatted however you like.
> - When you read someone else's code, run it through your own formatter.

The clash is structural, not cosmetic. Prettier's design assumption is that **one shared style** travels with the code; Puck's design assumption is that **no style** travels with the code and every reader projects their own. Differ ([differ.md](../../ideas/differ.md)) is the load-bearing example: its whole premise is that two contributors' edits get normalized to the **viewer's** style before diffing. That's not a corner case Prettier doesn't cover; it's a model Prettier is built to refuse.

The conflict isn't resolvable by switching defaults or wrapping the API. Adopting Prettier and then bolting on a half-dozen new options to let Caspian have a per-viewer style would put Puck on a permanent fork — option requests are explicitly no longer accepted upstream, so there's no path to merging the changes back. We would own a long-lived divergent codebase in a language (JavaScript) that the rest of Puck isn't written in.

## What Prettier gives us out of the box

~~~json
{"vibecode": {
	"section": "what_we_get",
	"strong_coverage": ["javascript", "typescript", "json", "css", "scss", "less", "html", "vue", "markdown_commonmark", "yaml", "graphql"],
	"missing": ["caspian", "lua"],
	"api_shape": "async, in_memory, no_disk_required",
	"server_side_friendly": true
}}
~~~

Out of the box, Prettier handles JavaScript, TypeScript, JSON, CSS / SCSS / Less, HTML, Vue, Angular, Markdown (CommonMark and GFM), YAML, and GraphQL ([prettier.io](https://prettier.io/)). Community plugins add Apex, Elm, Java, PHP, Ruby, Rust, TOML, XML, and others, with mixed maintenance quality.

The [programmatic API](https://prettier.io/docs/en/api) is server-friendly. `prettier.format(source, options)` takes a source string and an options object and returns a string — no disk I/O required. Options can be passed inline per call, which would allow a Differ-style service to pass each viewer's style into each format call. The public API is async; there is a `@prettier/sync` wrapper for cases that need a synchronous call.

For Puck's currently in-scope languages other than Caspian — JSON, HTML, CSS, markdown code fences — Prettier's out-of-the-box coverage is genuinely good. We would not have to write a CSS formatter from scratch if we wanted CSS fences in rendered docs to be pretty.

The catch is that "pretty" here means **Prettier's** pretty, not the pretty Miko has been specifying. Miko's CSS preferences ([miko.json](miko.json)) — single-declaration rules inline with no trailing semicolon, like `.foo {margin: 0}` — are not expressible in Prettier and would not be accepted as an option. Prettier would just override that style every time it ran.

## What we'd give up

~~~json
{"vibecode": {
	"section": "what_we_give_up",
	"hard_losses": ["blank_line_around_blocks", "empty_line_treatment_neighbors", "vibecode_placement", "css_single_declaration_inline", "hash_spacing_choice"],
	"soft_losses": ["lua_only_runtime", "single_source_of_truth_for_pipeline", "personal_formatter_social_contract"]
}}
~~~

The [options page](https://prettier.io/docs/en/options) is short and stable. Conspicuously absent: **any blank-line or empty-line handling at all**. Puck has already committed to `lines.blank_line_around_blocks` (the rule that gives multi-line constructs a blank line before and after) and to `lines.empty_line_treatment` with values like `"neighbors"` (match the indentation of the least-indented neighbor). Neither has a Prettier equivalent. Both have been ruled out as candidate options upstream by virtue of the frozen-option-set policy.

Other Puck options with no Prettier home:

### Caspian-specific options

`class_body_packing`, `empty_param_parens`, `bareword_call_parens`, `hash_spacing`, `return_parens`, `vibecode_placement` — these are Caspian-specific by definition, so they'd live in a Caspian plugin if we wrote one. The structural problem is upstream: even outside Caspian, Prettier's stance on per-language stylistic toggles is "no." A Caspian plugin could expose them, but doing so puts the plugin philosophically at odds with the host project, which complicates the long-term story (will Prettier maintainers be happy housing a plugin in their ecosystem that violates the option-set freeze? Probably tolerable, but not friction-free).

### CSS preferences

Miko's `single_declaration_rules: "inline"` / `single_declaration_trailing_semicolon: false` would be silently rewritten by Prettier on every save. There is no way to opt out short of disabling Prettier on CSS.

### Lua-only runtime story

Puck is Lua-centric. Adopting Prettier adds a hard Node.js dependency for any developer who wants formatting locally. The VS Code extension story is fine (VS Code already runs JS), but `caspian lint`, server-side Differ, and a future CLI all gain a Node.js runtime requirement they don't currently have.

### Single-source-of-truth pipeline

Puck's [formatting doc](../../ecoverse/formatting/index.md#tools-that-consume-stylejson) states explicitly: *"For Caspian specifically, formatters are CJS-in / Caspian-out generators on top of the canonical Caspian→CJS transpiler — no separate Caspian parsers in any tool."* A Prettier plugin must implement its own parser per the [plugin docs](https://prettier.io/docs/en/plugins) — Prettier loads source as a string and the plugin's `parse` function returns an AST. Either we reimplement Caspian parsing in JavaScript (now we have two parsers and they will drift), or we shell out from JavaScript to the canonical Lua transpiler (now we have a process boundary in every format call). The Ruby plugin solved this by running a persistent Ruby server in the background that Prettier talks to ([prettier-ruby](https://github.com/prettier/prettier-ruby)) — a workable pattern, but not free.

## The Caspian plugin problem

~~~json
{"vibecode": {
	"section": "caspian_plugin_cost",
	"required_exports": ["languages", "parsers", "printers", "options", "default_options"],
	"language": "javascript",
	"parser_options": ["reimplement_in_js", "shell_out_to_lua"],
	"reference_implementations": ["prettier-ruby (shells out)", "plugin-php (mixed JS+PHP)"]
}}
~~~

The [plugin documentation](https://prettier.io/docs/en/plugins) describes a five-export contract: `languages`, `parsers`, `printers`, `options`, `defaultOptions`. Plugins are loaded as JavaScript modules, and the printer's `print` function — the heart of any plugin — produces nodes in Prettier's internal Doc IR, which is a typed tree of `concat`, `group`, `indent`, `line`, `softline`, and similar combinators. Anyone writing a Caspian plugin would need to learn that IR and produce it for every Caspian construct.

That part is straightforward but real engineering work. The parser question is harder. Two paths:

### Reimplement the Caspian parser in JavaScript

Now Puck has two parsers — the Lua one used by the engine and a JS one used by the formatter. They will drift. Every Caspian language change requires updating both. This is the path Differ explicitly rejects ([differ.md](../../ideas/differ.md#how-it-works-and-why-to-trust-it)): *"every tool that reads Caspian goes through the one parser."*

### Shell out from the JS plugin to the Lua transpiler

This preserves single-source-of-truth but adds a process call inside every format call. The Ruby plugin precedent ([prettier-ruby](https://github.com/prettier/prettier-ruby)) shows this is workable — they keep a long-running Ruby server alive — but it converts what is currently a clean Lua-only pipeline into a JS-on-top-of-Lua architecture, with a daemon to manage and crash-recovery semantics to design.

Either path costs real effort and adds a long-lived JavaScript codebase to a project that, by V0.01 scope, doesn't otherwise need one.

## Per-viewer-style story

~~~json
{"vibecode": {
	"section": "per_viewer_normalization",
	"differ_requirement": "format each side using the viewer's style, per request",
	"prettier_supports_inline_options": true,
	"prettier_assumes_one_style_per_repo": true,
	"verdict": "mechanically possible, philosophically misaligned"
}}
~~~

Differ's whole premise is per-request, per-viewer normalization. The mechanical question is: can Prettier do this?

Mechanically, yes. The [configuration docs](https://prettier.io/docs/en/configuration) describe Prettier's config-file resolution (walk up the file tree, find `.prettierrc`, etc.) and the absence of any global config — both of which point toward "one repo, one style." But the [API docs](https://prettier.io/docs/en/api) make clear that `prettier.format(source, options)` accepts options inline, so a service like Differ could pass the viewer's `style.json` (translated into Prettier options) on each call and skip Prettier's config-resolution entirely.

The philosophical mismatch is that Prettier's whole model assumes a style **travels with the code** (via `.prettierrc` in the repo). Puck's whole model is that **style travels with the reader**. The API allows the per-viewer pattern; Prettier's UX, documentation, error messages, and community expectations all assume the opposite. The result is constant friction between what Puck wants from the tool and what the tool is designed to do.

Also: even if we drove Prettier per-viewer, the options it accepts are too narrow to express Puck's settled rules. There is no Prettier knob for `blank_line_around_blocks`, no knob for `empty_line_treatment: "neighbors"`, no knob for CSS inline-single-declaration. A per-viewer Prettier call would still produce Prettier's output, not the viewer's.

## Hybrid approaches

~~~json
{"vibecode": {
	"section": "hybrid_options",
	"option_a": "prettier_for_non_caspian_fences_only",
	"option_b": "prettier_for_initial_caspian_then_replace",
	"option_c": "borrow_doc_ir_concept_implement_in_lua",
	"recommended": "option_c_long_term_option_a_short_term"
}}
~~~

### Option A: Prettier for non-Caspian markdown fences only

Use Prettier as a render-time backend in Orlando / Gitter when a markdown fence labels itself `json`, `css`, `html`, `js`, etc., and skip it for `caspian` fences. This is the narrow case where Prettier earns its keep: it formats languages we don't want to formatter ourselves, and we can swallow Prettier's defaults for fenced examples in docs because nobody's authoring critical code there.

Costs: Node.js runtime on the render server. Inconsistent style across fences (Prettier's CSS conventions, not Miko's). No per-viewer customization for those fences — they get rendered to Prettier's defaults, not the viewer's preference, which dilutes the "personal formatter" story for non-Caspian content.

Workable, but explicitly second-class — and Orlando already exists and renders markdown today, so this is a future enhancement, not a foundational decision.

### Option B: Use Prettier for Caspian initially, replace later

Tempting (free time-to-market) but a trap. Once docs, tutorials, and the VS Code extension all depend on Prettier's option set and output, "replace later" becomes a never-ending migration. The Caspian-specific options Puck wants are not expressible in Prettier, so day-one users would see formatting that doesn't match the canonical doc. Reject.

### Option C: Borrow Prettier's Doc IR concept, implement in Lua

This is the most interesting hybrid. Prettier's intermediate representation — a tree of layout combinators (`group`, `indent`, `line`, `softline`, `fill`) descended from Wadler's "A prettier printer" — is a genuinely good design and is the actual technical contribution of the Prettier project, separable from its option-freezing politics. We can implement the same combinator IR in Lua, on top of the existing CJS pipeline. We get Prettier's layout-engine power without the runtime, without the philosophy clash, without the plugin contract, and with full freedom on options.

This is the path that fits Puck's principles: implementation in our own languages, no nanny code on options, full per-viewer freedom, lossless round-trip through CJS, and a small surface area we can evolve. It costs more than "just use Prettier," but it costs less than people assume — Wadler-style pretty-printers are a few hundred lines of clean code, and we already have the parser.

## Recommendation, expanded

~~~json
{"vibecode": {
	"section": "recommendation_expanded",
	"primary": "build_our_own_pretty_printer_for_caspian",
	"hybrid": "consider_prettier_as_backend_for_non_caspian_fences_in_orlando_gitter",
	"borrow": "wadler_doc_ir_design_implemented_in_lua",
	"avoid": "prettier_as_the_core_formatter_or_as_a_caspian_plugin_host"
}}
~~~

Stay the current course on the Caspian formatter. Build a small Lua pretty-printer that consumes CJS and renders Caspian using the viewer's `style.json`. Borrow Prettier's Doc IR shape (the `group` / `indent` / `line` / `softline` combinator vocabulary) but implement it in Lua, where the rest of the engine lives. This keeps Puck on a Lua-only runtime, keeps the single-parser invariant, keeps the personal-formatter philosophy, and keeps all the in-flight options (`blank_line_around_blocks`, `empty_line_treatment: "neighbors"`, the Caspian-specific knobs, Miko's CSS preferences) expressible.

Keep Prettier in mind as a **possible** render-time backend, much later, for non-Caspian fences inside Orlando-rendered docs — JSON, CSS, HTML, JS examples that nobody is going to argue about. That's the case where Prettier's opinionated defaults are an asset, not a liability. Even there, it's a deferred decision, not a V0.01 or V1 commitment.

Do not adopt Prettier as the core of Puck's formatting tools, and do not invest in writing a Caspian Prettier plugin.

## What would need to change if we adopted Prettier anyway

~~~json
{"vibecode": {
	"section": "if_we_adopted_anyway",
	"purpose": "documenting the cost so the trade-off is explicit",
	"changes": ["philosophy_doc_revision", "drop_options_without_prettier_equivalent", "node_in_runtime_stack", "caspian_plugin_project", "differ_redesign"]
}}
~~~

This section exists so the trade-off is on the record. If we did adopt Prettier:

### The philosophy doc would need rewriting

[index.md philosophy section](../../ecoverse/formatting/index.md#philosophy) would have to flip from "no canonical style" to "Prettier's defaults with these overrides." The social contract — "run your own formatter before complaining" — would be replaced by Prettier's "stop debating, accept the formatter's output."

### Several already-settled options would have to be dropped

`lines.blank_line_around_blocks`, `lines.empty_line_treatment: "neighbors"`, Miko's CSS inline-single-declaration rule, and likely several of the Caspian-specific options have no Prettier equivalent and would not be accepted upstream.

### Node.js would join the runtime stack

Every developer who wants local formatting would need Node.js installed. Server-side Differ would run on Node, not Lua. The "Lua-centric reference engine" framing in [CLAUDE.md](../../../CLAUDE.md) would need a footnote.

### A Caspian plugin project would have to be started

In JavaScript, implementing Prettier's plugin contract, with a parser either reimplemented in JS or wired to a long-running Lua transpiler daemon. This is a significant V1-or-later engineering project that doesn't exist on the roadmap today.

### Differ would need redesigning

Differ's per-viewer-style normalization can be done with Prettier's inline-options API, but the options vocabulary available is so much narrower than Puck's that "the viewer's style" would collapse to a small handful of toggles. Differ loses most of its product value.

The cumulative cost is too high to justify what Prettier brings to the table for Caspian specifically. The places Prettier is genuinely strong — JS, TS, JSON, CSS, HTML, Markdown — are exactly the places Puck either doesn't care intensely (rendered markdown fences) or has its own opinions that Prettier won't accommodate (CSS).

## Sources

- [Prettier option philosophy](https://prettier.io/docs/en/option-philosophy)
- [Prettier options](https://prettier.io/docs/en/options)
- [Prettier rationale](https://prettier.io/docs/en/rationale)
- [Prettier plugins](https://prettier.io/docs/en/plugins)
- [Prettier configuration](https://prettier.io/docs/en/configuration)
- [Prettier API](https://prettier.io/docs/en/api)
- [prettier.io](https://prettier.io/)
- [prettier-ruby](https://github.com/prettier/prettier-ruby)
- [plugin-php](https://github.com/prettier/plugin-php)
- Puck context: [formatting/index.md](../../ecoverse/formatting/index.md), [formatting/miko.json](../../ecoverse/formatting/miko.json), [ideas/differ.md](../../ideas/differ.md)
