# Formatting

~~~json
{"vibecode": {
	"doc": "formatting",
	"role": "canonical doc on how formatting works across the Puck ecoverse — philosophy, style.json structure, options, and the tools that consume it",
	"scope": "Charlie source, JSON, future per-language formatters, markdown code fences, file-system conventions",
	"status": "living — options accumulate as the formatter is built",
	"consumed_by": ["VS Code Charlie extension", "Gitter format toggle", "Differ normalization layer"]
}}
~~~

Formatting in the Puck ecoverse is a personal concern, not a project policy. This doc covers the philosophy, the on-disk `style.json` format, the catalogue of options known so far, the conventions Miko personally uses, and the tools that act on the file.

## Philosophy

~~~json
{"vibecode": {
	"section": "philosophy",
	"model": "personal_formatter_not_team_policy",
	"no_canonical_style": true,
	"no_project_level_config": true,
	"social_contract": "run_formatter_before_complaining_about_formatting"
}}
~~~

There is no canonical style for formatting Charlie. Instead, we developed
a `VS Code` extension so that you can easily format code to your own preference.

The rules are simple:

- Upload Charlie formatted however you like.
- When you read someone else's code, run it through your own formatter.

Let's keep bickering about tabs and spaces out of our community.

## The `style.json` file

~~~json
{"vibecode": {
	"section": "style_file",
	"location": "~/.config/charlie/style.json",
	"scope": "personal_not_project",
	"format": "strict JSON",
	"structure": "three top-level groups: indent, lines, languages"
}}
~~~

Personal style lives in `~/.config/charlie/style.json`. JSON keeps it consistent with the rest of the Puck ecosystem (CJS, vibecode blocks, Mikobase records, Puck wire format are all JSON) and avoids pulling in a separate parser. The file may carry a top-level `vibecode` block or `comment` field for human notes ([standard fields](../standard-fields.md)).

The format is **strict JSON** — no trailing commas, no `#` comments. Human notes go in the standard `vibecode` / `comment` fields.

### Structure

Three top-level groups: **`indent`**, **`lines`**, **`languages`**. Universal settings (the first two groups) apply to every language the formatter handles. Per-language overrides sit under `languages`, keyed by language name. **Per-language wins on conflicts** — Python's 88-column max_length overrides the global 100; JSON's spaces override the global tabs.

```json
{
  "indent": {
    "character": "tab",
    "width": 4
  },

  "lines": {
    "max_length": 100,
    "trim_trailing_whitespace": true,
    "empty_line_treatment": null,
    "max_consecutive_blank_lines": 1,
    "final_newline": false
  },

  "languages": {
    "charlie": {
      "blank_line_around_blocks": true,
      "class_body_packing": "tight",
      "empty_param_parens": true,
      "hash_spacing": "tight",
      "return_parens": true,
      "vibecode_placement": "top_of_section"
    },
    "json": {
      "indent": {
        "character": "space",
        "width": 2
      }
    },
    "python": {
      "indent": {
        "character": "space",
        "width": 4
      },
      "lines": {
        "max_length": 88
      }
    }
  }
}
```

The exact option set is defined as the formatter is implemented. Options known so far are documented below.

## Universal options

### `indent`

```json
"indent": {
  "character": "tab",
  "width": 4
}
```

#### `indent.character`

The indent character. Accepts `"tab"` / `"tabs"` / `"space"` / `"spaces"` — singular and plural forms both work, so writers don't have to think about it.

#### `indent.width`

Numeric. **Polymorphic on `character`:**

- When `character` is space-style (`"space"` / `"spaces"`): `width` is the **count of space characters** per indent level. File-content directive — the formatter emits exactly this many spaces per level.
- When `character` is tab-style (`"tab"` / `"tabs"`): `width` is a **display hint**, equivalent to CSS `tab-size`. The file always contains one tab character per level regardless; `width` tells renderers and editors how wide to draw each tab.

Same field, different consumers: spaces-mode talks to the formatter, tabs-mode talks to the renderer.

### `lines`

```json
"lines": {
  "max_length": 100,
  "trim_trailing_whitespace": true,
  "empty_line_treatment": null,
  "max_consecutive_blank_lines": 1,
  "final_newline": false
}
```

#### `lines.max_length`

Soft wrap target in characters. Common values: 80, 88 (Black), 100, 120. Effect depends on the language's formatter: auto-wrapping formatters (Prettier, Black, gofmt's `-l`) enforce it; non-wrapping formatters treat it as a hint or use it as a ruler value only.

#### `lines.trim_trailing_whitespace`

Boolean. When true, trailing whitespace on populated lines is stripped — `$foo.bar    \n` becomes `$foo.bar\n`.

#### `lines.empty_line_treatment`

How to treat empty lines (lines with only whitespace).

- **`null`** (default) — follow the end-of-line rule. If `trim_trailing_whitespace` is true, empty lines get stripped to blank too. If trimming is off, empty lines are left alone. Removes the need to think about empty lines as a separate concern.
- **`"keep"`** — do nothing. Leave whatever whitespace is there (editor's default).
- **`"blank"`** — strip to a true blank line, regardless of the populated-line rule.
- **`"neighbors"`** — match the **least-indented neighbor**. Works even when neighbors differ in indent.

Note: `"neighbors"` causes generic `trim_trailing_whitespace` tools (editors, linters, `.editorconfig`) to fight the formatter. The Charlie formatter is the source of truth; other tools defer to it. Diff noise on whitespace changes is accepted — GitHub's diff renderer handles it fine.

#### `lines.max_consecutive_blank_lines`

Integer cap. Two or more consecutive blanks collapse to this count. Typical value: `1`.

#### `lines.final_newline`

Boolean. When false, the file ends with the last meaningful character — no trailing newline. When true (the common Unix convention), one newline is enforced at EOF.

The Puck formatter also strips trailing empty lines from the end of the file regardless of `final_newline`'s value; the setting only controls whether one newline gets added back.

### Terminology: blank vs empty

Two distinct concepts:

- **Blank line** — a line with zero characters. Truly empty.
- **Empty line** — a line with only whitespace characters (spaces, tabs) and nothing else.

**Blank ⊂ empty.** All blank lines are empty; not all empty lines are blank.

## Charlie-specific options

These appear under `languages.charlie` in `style.json`.

### `blank_line_around_blocks`

~~~json
{"vibecode": {
	"option": "blank_line_around_blocks",
	"type": "boolean",
	"effect": "every multi-line block gets a blank line before and after, except at parent boundaries"
}}
~~~

When `true`, every **multi-line block** (anything that spans multiple lines because it has its own `end` keyword — `do…end`, `if…end`, `while…end`, nested `function…end`, etc.) gets a blank line before it and a blank line after it.

**Exceptions:**

- No blank line before the block if it's the first statement in its parent.
- No blank line after the block if it's the last statement in its parent.

Single-line statements are *not* padded — they pack together. The rule visually distinguishes "blocks of logic" from "linear statements."

**Example** (`function &name` from `puck.uno/color`):

~~~charlie
function &name
	$h = .hex

	%bucket['named'].each do($n, $named_hex)
		if $named_hex == $h
			return ($n)
		end
	end

	return (null)
end
~~~

The `each…end` block is multi-line and sits between two single-line statements, so it gets blank lines on both sides. The first statement (`$h = .hex`) has no blank line before it (first in parent), and the last statement (`return (null)`) has no blank line after it (last in parent).

### `class_body_packing`

`"tight"` packs class bodies like function bodies: no blank line between the `class 'foo'` opening and the first body member; no blank line between the last member's `end` and the class's closing `end`. The same rule applies uniformly — class bodies are not visually framed.

### `empty_param_parens`

Boolean. When true, function definitions include empty parens even when the parameter list is empty. Charlie's parser accepts both forms; this preference makes the parens explicit so every function definition has the same visual shape.

```
function &to_hash()    # empty_param_parens: true
function &to_hash      # empty_param_parens: false (also accepted by the parser)
```

Applies to definitions only; call sites are unaffected.

### `hash_spacing`

`"tight"`: `{lazy: true}` — no space after `{` or before `}`. `"loose"` would be `{ lazy: true }`.

### `return_parens`

Boolean. When true, return values are wrapped in parens — `return ($x)` rather than `return $x`.

### `vibecode_placement`

Where `%vibecode` heredocs sit. `"top_of_section"`: immediately after the heading, before any prose intro.

## HTML-specific options

These appear under `languages.html` in `style.json`. HTML inherits the universal `indent` setting (tabs by default for Miko).

### `blank_line_around_block_tags`

~~~json
{"vibecode": {
	"option": "blank_line_around_block_tags",
	"type": "boolean",
	"effect": "transitions between block-element runs and inline-element runs get a blank line between them"
}}
~~~

When `true`, sibling HTML elements get a blank line at the boundary between a **block-tag** run (multi-line elements like `<details>`, `<div>`, `<section>`, `<ul>`) and an **inline-tag** run (single-line elements like `<a>`, `<span>`, `<img>`). Same-kind siblings (two inlines in a row, two blocks in a row) get no blank between them; the transition is what carries the blank.

Mirrors the spirit of Charlie's [`blank_line_around_blocks`](#blank_line_around_blocks): visually distinguishes block-of-markup from a run of inline siblings.

**Example:**

~~~html
<details class="dropdown">
	<summary>
		<a href="/products">Products</a>
		<span class="chevron"></span>
	</summary>

	<a href="/products/widgets">Widgets</a>
	<a href="/products/gadgets">Gadgets</a>
</details>
~~~

Inside `<summary>`, the two inline siblings (`<a>`, `<span>`) pack together. After `</summary>` (a block) and before the two `<a>` (inline), there's a blank line. The two `<a>` siblings then pack together — same kind.

## Markdown and file conventions

These are formatting decisions that apply to the project's docs and file layout rather than to executable code.

### Code fences

- **`~~~charlie`** for Charlie code samples. Honest label, future-Linguist friendly.
- **`~~~json`** for JSON samples (including vibecode blocks).

### Vibecode blocks in markdown

- **Always present** in Charlie source and markdown docs.
- **At the top of a section** — immediately after the heading, before any prose intro.
- Pretty-printed JSON in a `~~~json` fence, soft-wrapped at 100 columns, opening `{"vibecode": {` on the same line, closing `}}` flush at column 0.
- Charlie source vibecode (`%vibecode <<EOF ... EOF`): pretty JSON with 2-space indent inside the heredoc.

### Nest concepts under headings, not bullet lists

When the items in a list are distinct concepts that a reader might want to comment on, file an issue against, or anchor a link to, give each one its own heading at the appropriate level (H3 / H4 / H5 / H6) rather than a bullet. Orlando (and post-V1 Gitter) injects a "GitHub issue" / "Quick add" panel onto every heading H2 through H6, but bullet items have no anchor and no link surface. Distinct items deserve headings.

Plain prose paragraphs stay plain prose. Tight enumerations where the items aren't distinct enough to merit headings (e.g. "values: 80, 88, 100, 120"), code-flag tables, citation lists, and other reference-style lists are fine as bullets or tables — they aren't "concepts" in the sense that needs per-item discussion.

### Headers

- **Sentence case.** "Construction", not "Construction Section". Proper nouns (Charlie, Puck, Mikobase) and acronyms (HTTP, JSON) keep their case.
- **No numbered headings.** TOCs are auto-generated by Orlando.

### Naming

- **JSON field names use underscores** (`fail_fast`, `created_at`).
- **File names use dashes** (`puck-html.md`, `class-definition.md`).

### UNS-lookup short form

- **`%['puck.uno/foo']`** preferred over `%puck['puck.uno/foo']`. Long form only when specifically introducing `%puck` itself.

## Tools that consume `style.json`

The same `style.json` is the single source of truth across all surfaces:

| Tool | Status | Description |
|---|---|---|
| VS Code Charlie extension | V1.1 | Format-on-save and Format Document (`Shift+Alt+F`); reads `~/.config/charlie/style.json`; no project-level VS Code settings needed. |
| Gitter format toggle | TBD | Per-language formatting on code blocks in any rendered file. See [gitter.md](../../ideas/github/puck-site/gitter.md). |
| Differ normalization | TBD | Diff normalization layer for Charlie-aware diff service. See [differ.md](../../ideas/differ.md). |
| `charlie lint` | TBD | Optional linter (separate from formatting). |

There is no command-line formatter for Charlie. Formatting happens inside the tools above (editor extension, web viewer, diff service); no `charlie fmt` CLI is planned.

For Charlie specifically, formatters are CJS-in / Charlie-out generators on top of the canonical Charlie→CJS transpiler — no separate Charlie parsers in any tool. This depends on CJS preserving comments and `%vibecode` heredocs as first-class nodes ([issue #56](https://github.com/mikosullivan/puck/issues/56)).

### Parse-fail behavior

When a tool can't parse the input — syntax errors, work-in-progress code, an unknown construct, or a language we haven't built a formatter for — it falls back to **plain text rendering**. No errors, no half-broken highlighting, no partial reformatting. The principle is uniform across languages and tools: if we can't figure out how to display it cleanly, just output the text.

## Open questions

Unresolved formatter rules. The list shrinks as decisions land; answers move into the option sections above.

1. **Blank lines between method definitions inside a class.** With "no consecutive blanks" already settled, the two-blanks-between-methods option is ruled out. Remaining choice: one blank between method and its attached `%vibecode` heredoc, then one blank between the heredoc and the next method (heredoc sits between, padded on both sides) — OR the heredoc attaches to the function below it with no blank between (only one blank separating consecutive methods).
2. **Multi-line heredocs (`%vibecode <<EOF … EOF`) — do they count as "multi-line blocks"?** The current `blank_line_around_blocks` rule mentions `end`-terminated constructs explicitly. Heredocs use `EOF`. Treat them as blocks (blank-line padded) or as multi-line statements (no special padding)?
3. **Blank lines around `field` declarations.** Currently they pack tightly. When (if ever) should a blank line break them into groups?
4. **Comment-line treatment.** When a `#` comment immediately precedes a block, does the comment "belong to" the block (no blank between them; the blank goes above the comment) or to the surrounding flow?

## Revisit at V1: own format vs. adopting an existing one

We surveyed open-source formatting-config formats before deciding to build our own; none currently checks every box we need (viewer-side, multi-language with real inheritance, hand-editable JSON, room for Charlie-specific rules). Candidates looked at: **EditorConfig**, **dprint**, **Biome**, **Prettier**, **rustfmt**, **clang-format**, **Topiary**, **Treefmt**.

The decision: build our own for now. **Revisit close to V1** — by then the format will have been exercised across the VS Code Charlie extension, Gitter, and Differ, and we'll know which warts matter. Options at that point:

- Keep our format, optionally emit a derived `.editorconfig` for editor interop.
- Switch to EditorConfig as the universal subset with our own per-language overrides layered on top.
- Adopt one of the JSON-shaped formats (dprint, Biome) outright, accepting their constraints.
- Borrow EditorConfig's property vocabulary (`indent_style`, `indent_size`, `max_line_length`, `trim_trailing_whitespace`, `insert_final_newline`) into our own keys for easier interop.

The current spec stays the working format until that revisit.

## Example: Miko's preferences

The values Miko personally uses. Not project policy — see Philosophy above — but a worked example and the source of truth for the formatter's recommended defaults.

```json
{
  "indent": {
    "character": "tab",
    "width": 4
  },

  "lines": {
    "max_length": 100,
    "trim_trailing_whitespace": true,
    "empty_line_treatment": null,
    "max_consecutive_blank_lines": 1,
    "final_newline": false
  },

  "languages": {
    "charlie": {
      "blank_line_around_blocks": true,
      "class_body_packing": "tight",
      "empty_param_parens": true,
      "hash_spacing": "tight",
      "return_parens": true,
      "vibecode_placement": "top_of_section"
    }
  }
}
```

Pairing notes:
- `trim_trailing_whitespace: true` plus `empty_line_treatment: null` means empty lines get stripped to blank as well — one decision, two consistent behaviors.
- No per-language overrides for JSON — JSON gets tabs like everything else, inheriting the universal indent.
- `indent.width: 4` with `character: "tab"` is a display hint — the file gets one tab per level regardless; the `4` tells renderers and editors how wide to draw each tab.
