# Uma (idea)

**Status:** design ported from Ruby Uma. See
[history/VIBECODE.md](history/VIBECODE.md) and
[history/html5.json](history/html5.json) for the Ruby
implementation's spec.

---

<a id="contents"></a>
## 1 Contents

- [Purpose](#purpose)
- [Implementation: lean on Lua](#implementation-lean-on-lua)
- [Core Object Model](#core-object-model)
- [Builder Pattern](#builder-pattern)
  - [Aliases](#aliases)
  - [Special table behavior](#special-table-behavior)
- [Schema Enforcement](#schema-enforcement)
- [Selectors: CSS and Astro](#selectors-css-and-astro)
  - [Supported selectors (v1)](#supported-selectors-v1)
  - [Not in v1](#not-in-v1)
  - [`match_css?` — the fragment predicate](#match_css-the-fragment-predicate)
  - [Implementation: layered](#implementation-layered)
- [Helpers](#helpers)
- [Document-Level Operations](#document-level-operations)
- [Import](#import)
- [JSON Rendering](#json-rendering)
- [String Wrapping Utility](#string-wrapping-utility)
- [The schema: html5.json](#the-schema-html5json)
  - [Builder behavior](#builder-behavior)
  - [Editing html5.json](#editing-html5json)
- [Power-user features](#power-user-features)
  - [`set_tag_mod` (deferred)](#set_tag_mod-deferred)
- [Errors](#errors)
- [Posture](#posture)
- [To be specified](#to-be-specified)

---

<a id="purpose"></a>
## 2 Purpose

`puck.uno/uma` is an HTML document builder and DOM helper, ported
from Ruby Uma. It wraps a parsed HTML5 document (via an underlying
Lua HTML library), adds convenience methods for creating and
editing elements, and enforces a project-defined HTML schema built
from `html5.json`.

**Uma is fundamentally an HTML builder.** For general DOM editing,
the underlying Lua library already provides baseline editing
methods; Uma adds the builder DSL, schema enforcement, and
convenience helpers on top.

---

<a id="implementation-lean-on-lua"></a>
## 3 Implementation: lean on Lua

For HTML and XML, **prefer existing Lua libraries** rather than
building from scratch. The Ruby version sits on top of Nokogiri;
the Charlie version will sit on top of an equivalent Lua HTML
library — likely **gumbo** (Google's HTML parser, with Lua
bindings) or another well-maintained option.

The rough split:

- **Tree representation, parsing input, serializing output** —
  delegate to the Lua library.
- **Builder DSL, attribute access via `[]`, text helpers,
  block-receiving element methods, schema enforcement** — Uma's
  contribution; the Charlie-shaped wrapper around the underlying
  tree.

Diverge from the chosen Lua library only if a specific need
forces it.

---

<a id="core-object-model"></a>
## 4 Core Object Model

`%['puck.uno/uma'].new(html?, ...opts)` creates an Uma wrapper
around the underlying parsed HTML document.

If no HTML is supplied, Uma builds a default HTML5 document with
`html`, `head`, `title`, `meta charset`, and `body` already in
place.

Convenience constructors:

- `%['puck.uno/uma'].basic()` — same as `.new()` with no args;
  creates a default HTML5 document.
- `%['puck.uno/uma'].new($raw_html)` — parses an existing
  document.

The instance exposes common document sections directly:

- `$uma.doc` — the wrapped document object.
- `$uma.body`, `$uma.head`, `$uma.header`, `$uma.main`, `$uma.footer` —
  common sections.

---

<a id="builder-pattern"></a>
## 5 Builder Pattern

The core API. Each method call on an element creates a child of
that tag name, with the block receiving the new child for further
configuration:

```
$uma.body.a do($a)
    $a['href'] = 'https://example.com'
    $a.text 'Home page'
end
```

- `.a`, `.div`, `.p`, `.h1`, etc. — tag-name methods create
  children of that tag. The set of allowed tags comes from
  html5.json.
- Block parameter is the newly-created element.
- `$el['attr'] = value` — set an attribute via hash-style access.
- `$el.text 'content'` — set text content (HTML-escaped).

<a id="aliases"></a>
### 5.1 Aliases

Some tag-name methods are aliases for `<input>` with specific
types:

```
$body.radio       # <input type="radio">
$body.checkbox    # <input type="checkbox">
$body.hidden      # <input type="hidden">
```

<a id="special-table-behavior"></a>
### 5.2 Special table behavior

Calling `.tr` on a `<table>` automatically ensures a `<tbody>`
exists and inserts the row there:

```
$uma.body.table do($t)
    $t.tr do($row)  # tr lands inside an auto-created tbody
        $row.td.text 'cell'
    end
end
```

---

<a id="schema-enforcement"></a>
## 6 Schema Enforcement

Uma enforces the HTML schema defined in [html5.json](history/html5.json).
Schema violations raise flags:

- **`puck.uno/uma/error/unknown_child`** — attempting to create a
  tag that isn't valid in the current parent.
- **`puck.uno/uma/error/unknown_att`** — setting an attribute
  that isn't in the schema.
- **`puck.uno/uma/error/empty_element`** — adding a child to a
  void element (`<br>`, `<img>`, etc.).

The schema lives in `html5.json` and is normalized at startup
(see [Builder Behavior](#builder-behavior) below).

---

<a id="selectors-css-and-astro"></a>
## 7 Selectors: CSS and Astro

Uma element trees are searchable two ways:

- **CSS selector strings** — familiar string syntax.
- **Astro** — a JSON-shaped canonical selector format (the AST
  the matching machinery operates on; see
  [astro.md](astro.md)). CSS strings are sugar that compile to
  Astro.

Both go through the standard `find` / `find_first` / `find_last`
API inherited from the Trivet child_set surface; either form
works as the argument:

```
$uma.body.find('div.container > p[lang]')           # CSS string
$uma.body.find({"tags": ["div"], ...})              # Astro directly

$uma.body.find_first('h1.page-title')               # first match (or null)
$uma.body.find_last('input[type=submit]')           # last match (or null)
```

The matching machinery always operates on Astro internally. CSS
strings get compiled to Astro on the way in.

<a id="supported-selectors-v1"></a>
### 7.1 Supported selectors (v1)

| Selector | Example | Matches |
|---|---|---|
| Type | `div` | All `<div>` elements |
| Class | `.foo` | Elements with class `foo` |
| ID | `#bar` | Element with id `bar` |
| Attribute presence | `[disabled]` | Elements with the `disabled` attribute |
| Attribute equality | `[type=submit]` | Elements where `type` equals `submit` |
| Attribute substring | `[href*=example]` | Elements where `href` contains `example` |
| Attribute prefix | `[href^=https]` | Elements where `href` starts with `https` |
| Attribute suffix | `[src$=.png]` | Elements where `src` ends with `.png` |
| Attribute hyphen-prefix | `[lang\|=en]` | Elements where `lang` is `en` or `en-*` |
| Attribute word | `[class~=warning]` | Elements where `class` contains the word `warning` |
| Compound | `div.container#main[role=banner]` | Combined constraints on a single element |
| Descendant | `nav a` | `<a>` anywhere inside any `<nav>` |
| Child | `ul > li` | `<li>` that's a direct child of `<ul>` |
| Adjacent sibling | `h1 + p` | `<p>` immediately following an `<h1>` |
| Selector list | `h1, h2, h3` | Any element matching any of the listed selectors |

<a id="not-in-v1"></a>
### 7.2 Not in v1

| Selector | Reason |
|---|---|
| `~` (general sibling) | Requires sibling-list walks; polynomial in worst case |
| `:nth-child(n)`, `:nth-of-type(n)` | Positional indexing required |
| `:not(...)`, `:has(...)` | Recursive selector evaluation |
| `:hover`, `:focus`, `:checked`, etc. | Dynamic state — doesn't apply to a static DOM tree |
| `::before`, `::after` | Rendering concerns, not DOM |

<a id="match_css-the-fragment-predicate"></a>
### 7.3 `match_css?` — the fragment predicate

Every Uma element node has a `match_css?` method that tests a
**single compound selector fragment** against itself — no
combinators, no tree walking, just "does this one element
match this one fragment?"

```
$el.match_css?('a[href]')                    # boolean
$el.match_css?('div.container')              # boolean
$el.match_css?('div.container#main[role=banner]')  # compound — still one element
```

A fragment can combine type, class, ID, and attribute
constraints on a single element (compound selectors). It
**cannot** contain combinators like `>`, ` ` (descendant), or
`+` — those describe relationships across the tree and live at
the find/find_first level.

`match_css?` follows the [`?` suffix convention](../../charlie/charlie.md#the--suffix):
truthy on match, falsey on no-match, never throws.

Direct use:

```
if $el.match_css?('a[external]')
    # add an external-link icon
end
```

Non-element nodes (text nodes, etc.) implement `match_css?` to
return false — text doesn't have classes, IDs, or attributes, so
no CSS selector matches it.

<a id="implementation-layered"></a>
### 7.4 Implementation: layered

```
high-level:  find / find_first / find_last  ← takes full selector strings
                  │
                  ▼
             (parses selector, splits at combinators, walks tree)
                  │
                  ▼
low-level:   match_css?                     ← tests one fragment on one element
```

The selector parser splits a full selector (e.g.,
`'nav > ul > li.active'`) into fragments separated by
combinators, then orchestrates a tree walk using `match_css?`
on candidates at each step.

The selector parser and matcher live in Uma, not Trivet — they
require HTML-specific knowledge (class attribute parsing, the
`class` and `id` shortcuts, attribute-comparison rules). Trivet
provides only the tree-walk machinery.

Performance is unoptimized — naive walk-the-tree and test each
element. Suitable for server-side template manipulation (small
documents, one-shot queries). Not designed for browser-scale
real-time matching.

---

<a id="helpers"></a>
## 8 Helpers

- **`$el.id`** / **`$el.id = '...'`** — convenience wrappers for
  the `id` attribute.
- **`$el.classes`** — returns a Classes helper for toggling CSS
  classes (add, remove, toggle, contains).
- **`$el.unwrap`** — remove the element while preserving its
  children (children get re-parented to the element's parent).
- **`$el.separator = ' • '`** — set a separator inserted between
  sibling children during serialization.
- **`$el.bulletize`** — separator variant for bullet-list-style
  rendering.

---

<a id="document-level-operations"></a>
## 9 Document-Level Operations

- **`$uma.title`** / **`$uma.title = 'New title'`** — read or
  write the document `<title>`. Writing also propagates to any
  `.title`-classed elements during serialization.
- **`$uma.to_html`** — serialize to raw HTML.
- **`$uma.pretty`** / **`$uma.generate`** — serialize to
  beautified HTML.
- **`$uma.content_type`** — returns `'text/html'`.
- **`$uma.tidy`** — recursively consolidate adjacent text nodes.
- **`$uma.sanitize`** — strip attributes that aren't allowed by
  the schema (defensive cleanup).

---

<a id="import"></a>
## 10 Import

`$uma.import($other_docs...)` imports content from source
documents into placeholders in the target:

- `.target` / `.source` classes mark the placeholder pairs.
- Or `data-tgt` / `data-src` attribute pairs for matching.

Use case: templating. Build a base document with placeholders,
then merge in fragment documents.

---

<a id="json-rendering"></a>
## 11 JSON Rendering

Helpers that render JSON-like data into HTML tables and text
containers:

- **`$el.show($data)`** — render any JSON-shaped value.
- **`$el.show_hash($hash)`** — render a hash as a table.
- **`$el.show_array($arr)`** — render an array as a list/table.

Useful for debugging and admin UIs.

A bundled stylesheet is available:

- **`%['puck.uno/uma'].json_css`** — returns the CSS used by the
  JSON rendering helpers.

---

<a id="string-wrapping-utility"></a>
## 12 String Wrapping Utility

- **`%['puck.uno/uma'].wrap($str, width: N, sep: '…')`** — wraps
  long strings with configurable width and separator text.

---

<a id="the-schema-html5json"></a>
## 13 The schema: html5.json

[html5.json](history/html5.json) is the normalized source of
truth for the tag model. The format:

- **`default`** — attributes applied to every tag (e.g., `class`,
  `id`, `accesskey`, all global HTML attributes). Tags don't need
  to repeat these.
- **`sources`** — reusable fragments. A source can define shared
  `atts`, shared `children`, and `include` other sources.
- **`tags`** — tag-specific definitions. Tags can `include`
  sources to inherit shared structure.
- **`cannot-nest`** — tag-level array of descendant tags that must
  not appear anywhere inside that tag's subtree.

**Semantic groupings:**

- `inlines` — main reusable inline child set.
- `flow-content` — broader semantic source building on `blocks`
  and adding extra non-block flow children.

All schema entries reference the **WHATWG HTML Standard**
(<https://html.spec.whatwg.org/>) as the source of truth.

<a id="builder-behavior"></a>
### 13.1 Builder behavior

A builder loads `html5.json`, recursively resolves `include`s,
deep-merges fragments, and produces a final tag-definition hash.

For each tag:

- Included sources are expanded first.
- Tag-specific values override included values via deep merge.
- `default` is merged into every tag.
- Scalar keys are moved toward the top; `atts` and `children`
  keys are reordered and sorted.

The result is stored on each Uma instance and consulted at runtime
for element creation and attribute validation.

<a id="editing-html5json"></a>
### 13.2 Editing html5.json

- Empty hash values stay on one line as `{}` rather than
  expanding across multiple lines.
- `include` arrays with two or fewer elements stay on one line.
- Scalar values appear at the top of each tag hash.
- Manual edits / merges should be re-checked against the WHATWG
  spec to avoid reintroducing obsolete entries.

---

<a id="power-user-features"></a>
## 14 Power-user features

<a id="set_tag_mod-deferred"></a>
### 14.1 `set_tag_mod` (deferred)

The Ruby version exposes `set_tag_mod(tag_name, mod)` to extend
matching elements with Ruby modules — `'*'` applies to every
element. Used for tag-specific behavior injection after parsing.

The Charlie equivalent (probably class extension or duck-typed
dispatch) is a power-user feature. Defer until there's a real use
case.

---

<a id="errors"></a>
## 15 Errors

Uma raises flags from the `puck.uno/uma/error/` family:

- `puck.uno/uma/error/unknown_child` — child tag not allowed.
- `puck.uno/uma/error/unknown_att` — attribute not allowed.
- `puck.uno/uma/error/empty_element` — child added to void.

All catchable via `catch()` with the appropriate class.

---

<a id="posture"></a>
## 16 Posture

- **Strict schema validation by default.** Catches authoring
  mistakes rather than accommodating messy real-world HTML.
- **For messy real-world HTML**, parse it first with the Lua
  library directly; once parsed, Uma can be wrapped around the
  result for builder-style additions.
- **Builder, not editor.** General DOM editing is the Lua
  library's job; Uma adds the builder layer.

---

<a id="to-be-specified"></a>
## 17 To be specified

(Open questions accumulate here as design discussion continues.)
