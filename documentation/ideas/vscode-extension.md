# Charlie VS Code Extension

~~~json
{"vibecode": {
    "status": "active_brainstorm",
    "started": "2026-05-17",
    "subsystem": "vscode_charlie_extension",
    "canonical_location": "ideas/ until firm enough to promote to formatter.md or a new dedicated vscode-extension.md",
    "scope": "first_contact_polished_self_contained_vs_code_extension_for_charlie_files",
    "co_authoring": "claude_capturing_miko_decisions_in_realtime"
}}
~~~

Brainstorm in progress.

---

<a id="architectural-constraint"></a>
## 1 Architectural constraint

~~~json
{"vibecode": {
    "section": "architectural_constraint",
    "rule_1": "extension_must_be_completely_independent_no_puck_install_required",
    "rule_2": "battle_tested_approach_not_experimental",
    "context": "first_contact_situation_for_charlie; syntax_must_show_up_nice_and_clean",
    "rules_out": ["subprocess_to_charlie_fmt_cli",
                   "language_server_requiring_charlie_lsp_process",
                   "wasm_artifact_compiled_from_charlie"],
    "implication": "self_contained_typescript_javascript_vs_code_extension"
}}
~~~

The extension must work for someone who has never installed Puck. They
install the extension from the VS Code Marketplace, open a `.charlie`
file, and everything works. No external runtime, no CLI dependency, no
language server process.

This rules out:
- Subprocess calls to `charlie fmt` (requires Puck installed)
- Language Server Protocol with a Charlie-based server (requires Puck)
- WASM artifacts compiled from Charlie (complex build, not battle-tested
  for editor extensions)

What's left: a **self-contained TypeScript/JavaScript extension** — the
standard, well-trodden VS Code extension model. This aligns with the
[[feedback_first_contact_strategy]] principle: useful results before
buying into the whole system.

---

<a id="settings-location"></a>
## 2 Settings location

~~~json
{"vibecode": {
    "section": "settings_location",
    "decision": "use_vs_code_built_in_settings_json",
    "rationale": "simplicity; standard_vs_code_pattern; integrated_with_settings_ui",
    "decided_2026-05-17": true,
    "diverges_from_formatter_md": "formatter_md_says_extension_reads_external_charlie_style_toml; this_brainstorm_supersedes_for_the_vs_code_extension_specifically; future_charlie_fmt_cli_can_still_use_external_file_or_can_align"
}}
~~~

The extension's user preferences live in **VS Code's own `settings.json`**.

- The extension declares its configurable settings in its `package.json`
  (via a `contributes.configuration` block).
- The settings appear in VS Code's Settings UI (`Ctrl+,`) under a
  "Charlie" heading.
- User scope (`~/.config/Code/User/settings.json` or the VS Code Server
  equivalent) applies everywhere; workspace scope (`.vscode/settings.json`
  in a project) overrides for that project.

This is simpler than the existing
[formatter.md](../charlie/formatter.md) plan to read
`~/.config/charlie/style.toml`. That external-file plan still makes
sense for a future `charlie fmt` CLI (so the CLI doesn't depend on
VS Code being installed), but the VS Code extension uses VS Code's
native settings instead.

Open: should a future `charlie fmt` CLI and the VS Code extension share
the same settings somehow (e.g., extension can optionally read
`style.toml` as a fallback)? Not load-bearing for the v1 extension;
defer.

---

<a id="formatter-v1-spec"></a>
## 3 Formatter v1 spec

~~~json
{"vibecode": {
    "section": "formatter_v1",
    "approach": "line_based_regex_rules_no_ast",
    "rationale": "battle_tested; handles_syntactically_broken_files; no_parallel_charlie_parser_in_typescript_to_maintain; can_evolve_to_parser_based_later",
    "language": "typescript",
    "self_contained": true,
    "scope_v1": ["indentation_normalization", "hash_option_spacing",
                  "trailing_whitespace_removal", "final_newline",
                  "blank_lines_collapse", "assignment_spacing"],
    "deferred_to_v2": ["line_wrapping_at_max_length",
                        "arithmetic_and_comparison_operator_spacing",
                        "parens_on_return_value_convention",
                        "hash_splat_preference",
                        "comment_and_vibecode_reformatting",
                        "folding_markers"]
}}
~~~

<a id="public-api"></a>
### 3.1 Public API

```ts
export interface FormatterOptions {
    indentSize: number;              // default 4
    indentStyle: 'spaces' | 'tabs';  // default 'spaces'
    maxBlankLines: number;           // default 2
    trimTrailingWhitespace: boolean; // default true
    ensureFinalNewline: boolean;     // default true
    normalizeHashSpacing: boolean;   // default true
    normalizeAssignmentSpacing: boolean; // default true
}

export function formatCharlie(
    source: string,
    options: Partial<FormatterOptions> = {}
): string;
```

One entry point. Options have safe defaults; the VS Code extension fills
them from `settings.json`; tests can pass them explicitly.

<a id="rule-pipeline"></a>
### 3.2 Rule pipeline

`formatCharlie()` is a pipeline of independent rules. Order matters:

1. `applyAssignmentSpacing` — `$x=1` → `$x = 1`
2. `applyHashSpacing` — `{a:1,b: 2}` → `{a: 1, b: 2}`
3. `applyIndentation` — normalize leading whitespace
4. `applyBlankLines` — collapse 3+ blank lines down to `maxBlankLines`
5. `applyTrailingWhitespace` — strip trailing spaces/tabs
6. `applyFinalNewline` — ensure exactly one terminating `\n`

Indentation runs before trailing-whitespace so any whitespace it
introduces survives the strip pass.

<a id="file-layout"></a>
### 3.3 File layout

```
vscode/syntax/
├── package.json                   # manifest, adds main + formatter contributions
├── syntaxes/
│   └── charlie.tmLanguage.json    # existing syntax highlighting
├── language-configuration.json    # NEW: brackets, comments, indentation
├── src/
│   ├── extension.ts               # NEW: activate(), registers formatter
│   ├── formatter.ts               # NEW: formatCharlie() + pipeline
│   └── rules/                     # NEW: one file per rule
│       ├── indentation.ts
│       ├── hashSpacing.ts
│       ├── trailingWhitespace.ts
│       ├── finalNewline.ts
│       ├── blankLines.ts
│       └── assignmentSpacing.ts
├── tests/formatter/               # NEW: input/expected fixtures per rule
└── tsconfig.json                  # NEW
```

<a id="user-preferences-shape"></a>
### 3.4 User preferences shape

~~~json
{"vibecode": {
    "section": "preferences_shape",
    "decided_2026-05-17": true,
    "shape": "flat_at_top_polymorphic_values_per_feedback_flat_at_top_data_structures",
    "rationale": "common_settings_at_outer_level; truthiness_carries_meaning_to_allow_evolution_without_key_fragmentation"
}}
~~~

Conceptually:

```json
{
    "tab":          4,
    "blanks":       2,
    "wrap":         100,
    "quote":        "single",
    "trim":         true,
    "final_newline": true,
    "hash_colon":   "loose",
    "hash_comma":   "tight-open",
    "parens":       "on-return",
    "splat":        "prefer"
}
```

Value-type semantics where they apply:

- `tab`: integer = N spaces; `true` = actual tab character.
- `blanks`: integer = max consecutive blank lines.
- `wrap`: integer = max line length.
- `quote`: `"single"` or `"double"`.
- `trim`: `true` strips trailing whitespace.
- `hash_colon`: `"loose"` (`lazy: true`) or `"tight"` (`lazy:true`).
- `hash_comma`: `"tight-open"` (no space before, space after) or `"loose"` (space both sides).
- `parens`: `"on-return"` (preferred default), `"always"`, `"never"`.
- `splat`: `"prefer"` reformats inline keyword args to hash-splat; `"keep"` leaves as written.

Translation to VS Code's `settings.json` (which is flat with dotted
keys) prefixes each setting with `charlie.formatter.`:

```json
"charlie.formatter.tab":        4,
"charlie.formatter.blanks":     2,
"charlie.formatter.wrap":       100,
"charlie.formatter.hashColon":  "loose"
```

<a id="settings-declaration-in-packagejson"></a>
### 3.5 Settings declaration in `package.json`

The configurable options surface in VS Code's Settings UI through a
`contributes.configuration` block:

```json
"contributes": {
    "configuration": {
        "title": "Charlie",
        "properties": {
            "charlie.formatter.indentSize": {
                "type": "number", "default": 4,
                "description": "Number of spaces per indent level."
            },
            "charlie.formatter.indentStyle": {
                "type": "string", "enum": ["spaces", "tabs"],
                "default": "spaces",
                "description": "Use spaces or tabs for indentation."
            }
        }
    }
}
```

(One entry per `FormatterOptions` field.)

<a id="vs-code-wiring"></a>
### 3.6 VS Code wiring

`src/extension.ts` registers a Document Formatting provider on
activation; VS Code auto-wires the Shift+Alt+F shortcut, the
right-click → Format Document menu item, the Command Palette entry,
and (when enabled by the user) format-on-save.

```ts
export function activate(context: vscode.ExtensionContext) {
    context.subscriptions.push(
        vscode.languages.registerDocumentFormattingEditProvider('charlie', {
            provideDocumentFormattingEdits(document) {
                const config = vscode.workspace.getConfiguration('charlie.formatter');
                const options: Partial<FormatterOptions> = {
                    indentSize:  config.get('indentSize'),
                    indentStyle: config.get('indentStyle'),
                    // ... other settings ...
                };
                const formatted = formatCharlie(document.getText(), options);
                const fullRange = new vscode.Range(
                    document.positionAt(0),
                    document.positionAt(document.getText().length)
                );
                return [vscode.TextEdit.replace(fullRange, formatted)];
            }
        })
    );
}
```

<a id="testing"></a>
### 3.7 Testing

Each rule has an `input.charlie` and `expected.charlie` fixture pair
under `tests/formatter/`. The test runner reads the input, applies the
rule (or the full pipeline), and asserts the output matches expected.
Same shape as the existing Lua engine's `tests/charlie/fixtures/`
pattern but in TS.

<a id="marketplace-polish-vasquez"></a>
### 3.8 Marketplace polish (Vasquez)

~~~json
{"vibecode": {
    "section": "marketplace_polish",
    "logo": "tbd_image_will_be_supplied_later; declared_in_package_json_icon_field; typical_128x128_or_256x256_png",
    "site_links": "package_json_homepage_and_repository_urls_pending_site_url_decision",
    "purpose": "first_contact_polish_for_marketplace_listing_and_extensions_sidebar"
}}
~~~

Two polish items that show up in the Marketplace listing and the
Extensions sidebar:

- **Logo**: an extension icon will be supplied. Declared in
  `package.json` via the `icon` field (typically a 128×128 or 256×256
  PNG). Image content and design deferred.
- **Site links**: `homepage`, `repository`, and (optionally) `bugs`
  URLs in `package.json`. These render as clickable links in the
  Marketplace listing and in the Extensions sidebar's "More Info"
  panel.
  - `homepage`: **`https://puck.uno`** (cert/DNS propagation pending
    per [[project_puck_uno_cert_pending]]).
  - `repository` and `bugs` URLs: TBD.

<a id="v1-caveats-absorbed-into-scope"></a>
### 3.9 V1 caveats absorbed into scope

Two pieces of v1 work the rule list above doesn't make obvious:

1. **String/comment/heredoc/vibecode masking pre-pass.** Regex rules
   must not touch the contents of string literals, comments,
   heredocs, or `vibecode:` JSON blocks. The pipeline gains a
   mask-and-restore wrapper: a pre-pass replaces masked regions with
   placeholders (`__KSTRING_001__`, etc.), the rules run against the
   masked text, a post-pass restores. ~50 lines of TS. Without this,
   `lazy:true` → `lazy: true` would happily rewrite the string
   literal `'lazy:true'` (which it must not).

2. **Indentation normalization is tab/space style only, not
   structural re-indent.** Fixing broken nesting (where a developer
   wrote the wrong indent level for a block) requires knowing about
   `do`/`end`/`class`/`function` boundaries, which means tokenizing
   — a big jump in complexity. V1 trusts the per-line indent level
   the developer wrote and only normalizes tab/space style and indent
   *size*. Structural re-indent is a v2 candidate (see
   [vscode-extension-v2.md](vscode-extension-v2.md)).

---

