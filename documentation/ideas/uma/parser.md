# Uma HTML Parser

**Status:** design in progress. This is the pure-KScript HTML
parser that Uma will use to read existing HTML documents into a
tree it can manipulate. Goal: avoid bundling a C HTML parser
(gumbo or similar) at the cost of accepting "well-formed-ish"
HTML rather than the full HTML5 quirky-recovery spec.

See [uma.md](uma.md) for the broader Uma builder / DOM helper
this parser feeds.

---

## Scope

**In scope:**
- Parse well-formed HTML5-style input into an element tree.
- Recognize void elements (per Uma's schema).
- Handle text content, attributes (single-quoted, double-quoted,
  unquoted, valueless), comments, CDATA, DOCTYPE, processing
  instructions.
- Recognize `<script>` and `<style>` content as opaque (don't
  parse tags inside them).
- Decode standard HTML named character references (`&amp;`,
  `&lt;`, `&nbsp;`, etc.) and numeric references (`&#42;`,
  `&#x2A;`).
- Reject malformed input loudly (raise a flag), don't attempt
  browser-style recovery.

**Out of scope:**
- Full HTML5 parsing-spec compliance (insertion modes, foster
  parenting, quirks-mode handling, foreign-element switching for
  SVG/MathML, encoding sniffing).
- Recovering from messy real-world HTML. Use a Lua HTML library
  outside KScript for that.
- Streaming. Whole-document parsing only.

The trade is: developers feeding Uma their own templates or
serialized output get a fast, small, native parser. Anyone
parsing wild-world HTML (scraping, malformed input) reaches for
a bundled library instead.

---

## Architecture (Kor (DS9))

Two layers, with **all tag knowledge supplied externally** via
a schema config:

```
raw input string                  schema config (e.g., html5.json)
      │                                  │
      ▼                                  ▼
[ TOKENIZER ]   ← dumb, fast,    [ SCHEMA ]  ← all rules about
      │           single linear        │       tags: which are
      │           pass; emits a        │       void, what can
      │           flat token stream    │       nest where, what
      │           with no tag-shape    │       are opaque
      │           knowledge            │       (script-like),
      │                                │       what attributes
      │                                │       are allowed, etc.
      │                                │
      ▼                                ▼
[ TREE BUILDER ] ← state machine that walks the token stream,
      │           consults the schema for tag rules, produces
      ▼           an element tree
element tree
```

The parser **knows nothing intrinsic about HTML.** It knows
how to tokenize an angle-bracket-and-attribute syntax, walk a
state machine, and ask a schema "is this tag void?" / "can this
tag close that tag?" / "should I treat this tag's content as
opaque?" Substitute a different schema and the same engine
parses a different language.

HTML5 is just the first schema (Uma's html5.json). Custom
schemas let developers define their own markup languages or
restricted HTML subsets — see [Schemas other than HTML5](#schemas-other-than-html5)
below.

Splitting tokenization from tree-building keeps both layers
small. The tokenizer doesn't know about any tag semantics; the
tree-builder doesn't deal with character-level parsing; the
schema knows nothing about parsing at all (it's just data).

---

## Tokenizer (Koloth (DS9))

Single linear pass over the input string. Splits on:

- `<` and `>` (tag delimiters, isolated as their own tokens)
- `=` (attribute-value separator)
- `"` and `'` (quote delimiters)
- `/` (in close tags and self-closing)
- `!` and `?` (for `<!--`, `<!DOCTYPE`, `<?...?>`)
- Whitespace runs (preserved as space tokens)
- Non-space runs of text (each emitted with the trailing
  whitespace, so the relationship is preserved)

The result is a flat array of tokens. Each token is a small
hash:

```
{type: 'tag-open',  value: '<'}
{type: 'word',      value: 'div'}
{type: 'space',     value: ' '}
{type: 'word',      value: 'class'}
{type: 'eq',        value: '='}
{type: 'quote',     value: '"'}
{type: 'word',      value: 'container'}
{type: 'quote',     value: '"'}
{type: 'tag-close', value: '>'}
```

Why this shape rather than a richer tokenizer that already knows
"open-tag" vs "attribute" vs "text": **the smart work belongs in
the tree-builder.** The tokenizer's job is splitting the string
fast. Lua patterns don't have alternation, so the tokenizer
either uses several `string.find` calls per chunk or a
hand-rolled character-level scan; either way it stays simple.

**Open: exact token type set.** The minimum is enough types for
the tree-builder to recognize structure (`tag-open`, `tag-close`,
`eq`, `quote`, `word`, `space`). Adding more (e.g., `comment-open`
for `<!--`) might be worth it if it simplifies the tree-builder.

---

## Tree builder (Kang (DS9))

State machine over the token stream. States:

| State | Description |
|---|---|
| `outside` | Default. Tokens are text or `<` starting a tag. |
| `tag-name` | Just after `<`. Next word is the tag name. |
| `attributes` | After tag name, inside the tag. Tokens are attribute names, `=`, values. |
| `attr-value-quoted` | After `="`. Collect tokens as the value until matching quote. |
| `attr-value-unquoted` | After `=` with no quote. Collect tokens as the value until whitespace or `>`. |
| `comment` | After `<!--`. Discard tokens until `-->`. |
| `cdata` | After `<![CDATA[`. Collect as raw text until `]]>`. |
| `doctype` | After `<!DOCTYPE`. Collect until `>`. |
| `pi` | After `<?`. Collect until `?>`. |
| `script-content` | Inside `<script>` / `<style>`. Treat all tokens (including `<`) as text until `</script>` / `</style>`. |

The state machine maintains a **stack of open elements**. On
`<tag-open><word>tagname`:

1. Look up `tagname` in the schema.
2. If `tagname` is void, create the element and don't push it
   (no closing tag expected).
3. If `tagname` is non-void, create the element, push it on the
   stack.

On `</tagname>`:

1. Pop the stack until we find a matching open tag.
2. If no matching open tag is on the stack: **malformed input;
   raise a flag** (specific class TBD).

On reaching EOF with a non-empty stack: **malformed input; raise
a flag** (unclosed tags).

### Schema-driven behavior

**All tag knowledge comes from the schema config.** The parser
queries the schema for:

- Which tags are void (no closing tag, no children).
- Which tags have content-model rules (e.g., `<p>` cannot
  contain block elements — `<p><div>` implicitly closes the
  `<p>`).
- Which tags trigger opaque-content modes (e.g., `<script>` and
  `<style>` in HTML5 — content treated as raw text until the
  matching close tag).
- Which attributes each tag accepts (used for `sanitize` and
  validation, but not for parsing per se).
- Which tags can nest inside which.

For HTML5, this schema is [Uma's html5.json](history/html5.json).
For other markup languages, a different config file describes
the same kinds of facts about a different tag set.

The implicit-close rules are the trickiest part. Common ones
for HTML5:

- `<p>` closes when a block element opens inside it.
- `<li>` closes when another `<li>` opens at the same level.
- `<tr>` closes when another `<tr>` or `</table>` is reached.
- `<dt>` / `<dd>` close when another `<dt>` or `<dd>` opens.

These belong in the schema, not the parser code — the parser's
job is "read schema, follow its rules," not "know HTML."

---

## Output: the element tree

Each element node carries:

- **tag** (string) — the tag name.
- **attrs** (hash) — attribute name → value. Boolean attributes
  (no `=value`) get value `true` or the attribute name itself
  (TBD).
- **children** (array) — child nodes. Mixed elements and text.
- **parent** (reference) — back-link for navigation. Set by the
  tree-builder; read-only after parsing.

Text nodes are represented as simple hashes:

```
{type: 'text', value: 'Hello world'}
```

Or possibly as bare strings in the children array — TBD on
which is cleaner.

Comments (if preserved at all) and DOCTYPE / PI nodes get their
own type tags if we keep them in the tree.

**Open: comment preservation.** Some Uma use cases (round-trip
edit-and-serialize) want comments preserved. Others (DOM
querying) treat them as noise. Probably preserve by default
with an option to strip; or always preserve and let the
serializer's `tidy` step strip them.

---

## Schemas other than HTML5

Because all tag knowledge lives in the schema config, the same
parser engine can parse any markup language that fits the
angle-bracket-and-attribute syntax model. Possible use cases:

- **Restricted HTML subsets** for security (allow only `<p>`,
  `<a>`, `<strong>`, etc.) or for stripped-down editors.
- **Domain-specific markup languages.** Recipe markup
  (`<ingredient>`, `<step>`, `<temperature>`), music notation
  (`<chord>`, `<verse>`), legal documents (`<clause>`,
  `<citation>`).
- **Project-internal markup** for build pipelines, where
  `<include>`, `<param>`, etc. are first-class tags with
  specific meanings.
- **XML-like configuration formats** with project-defined tags.

The parser engine doesn't care. Provide a schema that lists the
tags, their voidness, their nesting rules, their opaque-content
flags — and the parser produces a tree following those rules.

### A DSL for defining schemas (open)

Writing schema configs by hand in JSON is tolerable but
verbose. A DSL for **defining** these schemas — not for writing
documents in the resulting language — could make it much easier
to declare custom markup formats.

Rough sketch (purely speculative):

```
language 'recipe' do
    tag 'recipe' do
        contains 'metadata', 'ingredient', 'step'
    end
    tag 'ingredient', void: true
    tag 'step' do
        contains_text
    end
    tag 'temperature', void: true, attrs: ['unit']
end
```

The DSL emits a normalized schema config (the same shape Uma's
html5.json takes), which the parser then consumes. Schemas can
inherit from each other (HTML5 with extras, restricted-HTML
with subtractions, etc.).

This is a separate piece of work from the parser itself — the
parser only needs the resulting schema config. But it's worth
keeping in mind that the schema format should be ergonomic to
emit from a DSL, not just hand-written.

**Filed as a future direction.** Not in v1; the parser only
needs to consume schemas, regardless of how they're written.

---

## Error handling

Malformed input raises a flag rather than attempting recovery.
Specific flag classes (all under `kiera.uno/uma/error/`):

- `unbalanced_tag` — close tag without matching open, or open
  tag without close at EOF.
- `bad_attribute` — attribute syntax that doesn't parse (e.g.,
  `<div =value>`, `<div attr"value">`).
- `bad_entity` — entity reference that doesn't resolve.
- `truncated_comment` / `truncated_cdata` / `truncated_pi` —
  unterminated special structures.

Open: should the parser accept a `lenient: true` mode that tries
to recover from minor issues (e.g., unbalanced tags by auto-closing)?
Probably not in v1 — the explicit failure is the value. If
real-world HTML needs to be parsed, that's the Lua-library use
case.

---

## Performance

Rough budget:

- Tokenizer: a few hundred lines of KScript, single linear pass.
  Probably 5–10x slower than gumbo, which is fine for
  server-side template parsing where documents are small and
  parsed once.
- Tree builder: a few hundred more lines, also linear in token
  count.
- Total: **~1500–2000 lines of KScript**, ~30–50k of source.

Not the fastest HTML parser ever written. Suitable for
"developer-controlled HTML" use cases (server-side templates,
serialized output round-trips, builder validation). Not suitable
for parsing megabytes of scraped wild-world HTML.

---

## Open questions

- **Tokenizer implementation language.** Pure KScript? Lua-native
  helper for the inner loop? Pure KScript is simpler to
  maintain; Lua-native is faster.
- **Boolean attributes.** `<input disabled>` — does `attrs['disabled']`
  hold `true`, the empty string, or the attribute name?
- **Whitespace normalization.** Preserve all whitespace? Collapse
  runs in text content? HTML5 typically does inline-collapsing
  at render time, but the parser can leave it alone.
- **Comment preservation.** Default-preserve with strip option,
  or default-strip with preserve option?
- **Implicit close rules.** Encoded in the schema (declarative)
  or in parser code (imperative)?
- **Self-closing slash tolerance.** `<br/>` vs `<br>` — accept
  both? (HTML5 spec says the slash is ignored on non-foreign
  elements; we should probably accept it without complaint.)
- **Encoding.** Assume UTF-8 input always? Or honor `<meta charset>` /
  BOM if present?
- **Foreign content.** `<svg>` and `<math>` switch parsing rules
  in real HTML5. Probably skip the switch in v1 — they parse as
  normal HTML elements with whatever children they have.

---

## Why a hand-rolled parser is worth it

If we bundle gumbo: ~150–200k of native code, well-tested,
correct on real-world HTML. Pros: zero maintenance burden,
handles anything. Cons: significant binary-size hit; outside our
core budget; uses C; depends on Google's release cadence.

If we hand-roll: ~30–50k of KScript source, less correct on
weird HTML, but tractable to maintain and entirely inside our
own ecosystem. Pros: no native dep, fits the budget, can evolve
with our schema. Cons: never matches a browser exactly; rejects
HTML that browsers would accept.

The trade lands well for Uma's intended use cases:
**developer-controlled HTML** (templates, builders, internal
tools). For wild-world parsing, expect to install a Lua-library
adapter outside core.

---

## Next steps

- Pin the token type set.
- Decide schema vs. parser-code for implicit-close rules.
- Sketch the tokenizer state machine in pseudocode.
- Sketch the tree-builder state machine in pseudocode.
- Implement and benchmark.
