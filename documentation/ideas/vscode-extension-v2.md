# Charlie VS Code Extension — V2 ideas

```
vibecode: {
    "status": "future_planning_not_v1_work",
    "started": "2026-05-17",
    "subsystem": "vscode_charlie_extension",
    "parent_doc": "vscode-extension.md (V1 spec)",
    "purpose": "park_features_deferred_from_v1_and_speculate_about_the_architectural_jump",
    "co_authoring": "claude_capturing_decisions_in_realtime"
}
```

V1 is a self-contained TypeScript extension with line-based regex
formatting — six small rules, masked-string pre-pass, no Charlie parser
in TS. See [vscode-extension.md](vscode-extension.md) for that spec.

V2 is for ambitions that need either (a) a Charlie parser in TypeScript
or (b) a Language Server Protocol shape. Both are bigger than v1; both
unlock features v1 can't reach.

---

## The architectural jump

```
vibecode: {
    "section": "architectural_jump",
    "v1_constraint": "line_based_regex_no_parser",
    "v2_options": ["typescript_charlie_parser_embedded",
                    "language_server_protocol_with_charlie_server"],
    "tradeoff": "lsp_unlocks_more_features_but_requires_a_running_charlie_capable_server_which_re_introduces_the_kiera_dependency_unless_the_server_is_also_in_typescript"
}
```

Two shapes for v2 to consider — they're not mutually exclusive but each
costs:

### Option A: TypeScript-based Charlie parser, still no external runtime

A real Charlie parser written in TypeScript, embedded in the extension.
Still self-contained — no external runtime, no Kiera install. Unlocks
all the features that need to know about syntactic structure
(structural re-indent, line wrapping, operator spacing with edge case
awareness, parens-on-return-value, etc.).

Cost: a second Charlie parser to maintain (the Lua reference engine has
the canonical parser; this would be a parallel TS implementation). The
two implementations must agree about what's valid Charlie.

**A TS parser is also valuable in its own right, beyond the extension's
formatting features:**

- **Reference implementation in a mainstream language.** The Lua engine
  is canonical but Lua is niche. A TS parser is readable to a much
  wider pool of programmers — easier to bring in contributors,
  easier for skeptics to evaluate the language, easier to embed in
  web demos.
- **Spec validation.** Two independent implementations agreeing forces
  the [CharlieJSON](../charlie/charliejson.md) spec to be precise
  enough that two people can build the same thing from it. That's a
  real spec quality check no single-implementation language gets.
- **Drop-in for web tooling.** Any JS/TS project — build pipelines,
  documentation generators, code playgrounds, online sandboxes —
  can consume the parser directly without spinning up Lua.
- **A reference for further ports.** Future Python or Go parsers have
  two implementations to compare against instead of one.

So even if structural re-indent, line wrapping, etc. weren't on the
roadmap, the TS parser would still be worth building. The formatter
features are a bonus.

### Option B: Language Server Protocol with a TypeScript-based language server

Same parser as Option A, but exposed via LSP. The extension talks LSP
to a long-running language server process (also TypeScript, also
self-contained, packaged with the extension). Unlocks diagnostics,
completion, hover, go-to-definition, find-references, refactor — not
just formatting.

Cost: substantially more code than Option A. LSP is well-specified but
non-trivial to implement well.

**Recommendation when v2 lands: probably Option A.** The features v2
wants for formatting (structural indent, line wrapping, sophisticated
operator spacing) don't need LSP — they need a parser. Diagnostics and
completion are valuable but can be added later in v3 by wrapping the
parser in an LSP layer.

---

## Features deferred from V1

```
vibecode: {
    "section": "deferred_features",
    "from_v1": ["structural_reindent", "line_wrapping_at_max_length",
                 "arithmetic_and_comparison_operator_spacing",
                 "parens_on_return_value_convention",
                 "hash_splat_preference",
                 "vibecode_block_internal_formatting",
                 "folding_markers"]
}
```

### Structural re-indent

V1 trusts the per-line indent level the developer wrote and only
normalizes tab/space style and indent size. V2 with a parser can
recompute the correct indent based on `do`/`end`/`class`/`function`/
`if`/`while` block boundaries and fix nesting errors.

### Line wrapping at `maxLineLength`

V1 has a `maxLineLength` option that nothing reads. V2 with a parser
can split long lines at sensible breakpoints (after `,` in argument
lists, between operators with correct precedence, etc.).

### Arithmetic and comparison operator spacing

V1 normalizes `=` (safe — assignment is unambiguous in context) but
leaves `+`, `-`, `*`, `/`, `==`, `!=`, `<`, `>`, `<=`, `>=` alone
because the line-based pass can't tell `-1` (negation) from `x - 1`
(subtraction) or `*args` (splat) from `a * b` (multiplication).
V2 with a parser handles all of them correctly.

### Parens-on-return-value convention

Miko's personal style preference: `$foo.bar 1, 2, 3` for side-effect
calls; `$gup = $foo.bar(1, 2, 3)` for return-value capture (see
[[feedback_miko_style_preferences]]). V1 can't enforce this without
knowing whether a call's return value is captured — needs a parser.

### Hash-splat preference

Per Miko's style: prefer `&something **$args` over inline keyword
arguments when there are several. V1 can't reformat one shape into the
other without parsing the call. V2 candidate.

### Vibecode block internal formatting

The `vibecode:` JSON blocks have their own format convention
(minified, soft-wrapped at 90 columns, breaks after `,` or `:`; per
[[feedback_vibecode_json_format]]). V1 just masks these blocks
(leaves them untouched). V2 could format them according to the
convention.

### Folding markers / region comments

V1 doesn't add or respect folding markers. V2 could let users
collapse classes, functions, or `vibecode:` blocks via VS Code's
folding UI — needs structural awareness.

---

## Open questions for V2 planning

- **Cross-tool config sharing.** V1 reads from VS Code's
  `settings.json` only. A future `charlie fmt` CLI will likely read
  `~/.config/charlie/style.toml`. V2 might let the extension
  optionally read the external file as a fallback so the two tools
  share style settings — useful for developers who use both.
- **Where the parser lives in the repo.** If V2 introduces a TS-based
  Charlie parser, does it live in `vscode/syntax/src/`? Or a peer
  package `vscode/parser/` that the extension consumes? Affects code
  organization and possibly future LSP work (which would want to
  reuse the parser).
- **Reconciliation with the canonical Lua parser.** Two parsers for
  the same language can drift. Possible mitigations: shared test
  fixtures (the same `.charlie` files must parse identically on both
  sides), or generating one from the other (probably overkill).
- **Distribution.** V1 is Marketplace-ready as a single TypeScript
  extension. V2 with a TS parser is still single-extension. V3 with
  LSP would package a server binary inside the extension — still
  single artifact from the user's perspective.
- **Whether `vscode-extension.md` (V1) and this file should
  eventually merge** into a single canonical extension spec under
  `documentation/charlie/vscode/` (replacing the current zero-byte
  `vscode/syntax/syntax.md`), or stay separate as "shipped" vs
  "future" reference docs.
