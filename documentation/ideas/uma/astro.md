# Astro — the canonical Uma selector format

~~~json
{"vibecode": {
	"doc": "uma-astro",
	"role": "in-progress spec for Astro, the canonical JSON tree-selector format Uma matches against; CSS selector strings are sugar that compiles to Astro and the matcher operates on the JSON form",
	"key_concepts": ["astro_format", "selector_ast", "css_string_sugar",
		"reserved_keys", "combinators_then_then_child_then_next"]
}}
~~~

**Status:** Design in progress. **Astro** is the canonical
JSON-shaped tree-selector format used by Uma. It IS the AST
(abstract syntax tree) that selectors compile into; the matching
machinery operates directly on Astro.

CSS selector strings are **syntactic sugar over Astro**.
`"div > p.foo"` parses into an Astro tree; the matcher consumes
the Astro form. Handwritten code typically uses CSS strings;
programmatic code that constructs queries dynamically uses
Astro directly. Either way, the matcher sees the same JSON
tree.

The name is a tip of the hat to AST — Astro is the AST that
selectors compile to.

---

<a id="structure"></a>
## Structure

A selector is a hash with these reserved keys:

| Key | Type | Meaning |
|---|---|---|
| `tags` | Array of strings | Tag names. Element matches if its tag is in the list (implicit OR). |
| `atts` | Hash | Attribute conditions. All must match (implicit AND). See [Atts](#atts) below. |
| `return` | Boolean | Optional. If `true`, results return matches at this level (not innermost). See [Return marker](#return-marker). |
| `then` | Selector | Descendant match — next selector must match any descendant. |
| `then-child` | Selector | Child match — next selector must match a direct child. |
| `then-next` | Selector | Adjacent-sibling match — next selector must match the immediately-following sibling. |

At any level, at most one of `then` / `then-child` / `then-next`
appears (one combinator per level).

If more appear, there is no set precedence for which one to use.
Nanny should flag a warning on that.

---

<a id="atts"></a>
## Atts

Each entry in `atts` describes an attribute constraint:

```
"atts": {
    "href": null,                # attribute must exist, any value
    "src": "something",          # attribute must equal "something"
    "data-foo": {"starts_with": "abc"},      # prefix match
    "data-bar": {"contains": "x"},           # substring match
    "lang":    {"hyphen_prefix": "en"}       # hyphen-prefix (e.g., en, en-US)
}
```

| Value form | Meaning | CSS analog |
|---|---|---|
| `null` | attribute exists, any value | `[attr]` |
| String | attribute equals this string | `[attr=value]` |
| `{"starts_with": "x"}` | attribute value starts with `x` | `[attr^=x]` |
| `{"ends_with": "x"}` | attribute value ends with `x` | `[attr$=x]` |
| `{"contains": "x"}` | attribute value contains substring `x` | `[attr*=x]` |
| `{"word_match": "x"}` | attribute value has `x` as a whitespace-separated word | `[attr~=x]` |
| `{"hyphen_prefix": "x"}` | attribute value is `x` or starts with `x-` | `[attr\|=x]` |

---

<a id="combinators"></a>
## Combinators

Three combinator keys mirror the CSS subset Uma supports in v1:

- **`then`** — descendant. Next selector matches any descendant.
  CSS: ` ` (space).
- **`then-child`** — direct child. Next selector matches a direct
  child only. CSS: `>`.
- **`then-next`** — adjacent sibling. Next selector matches the
  immediately-following sibling. CSS: `+`.

General sibling (CSS `~`) is not in v1.

A selector is a chain: each level matches one element, then
defers to its combinator for the next level.

---

<a id="result-selection"></a>
## Result selection

By default, the result is the **innermost matched element** —
matches CSS's "rightmost selector is what you get" rule.

```
{
    "tags": ["div"],
    "then": {
        "tags": ["table"]
    }
}
```

→ returns tables that are descendants of divs.

<a id="return-marker"></a>
### Return marker

`"return": true` at any level **overrides the default** — the
result becomes matches at the marked level instead of innermost.
Useful for queries like "find divs that have a table inside"
without giving up the descendant constraint.

```
{
    "tags": ["div"],
    "return": true,
    "then": {
        "tags": ["table"]
    }
}
```

→ returns divs that have a table descendant. (CSS equivalent:
`div:has(table)`.)

<a id="multiple-return-markers"></a>
### Multiple return markers

If multiple levels carry `"return": true`, the **outermost wins**.
Deeper markers are ignored. A `puck.uno/uma/warning/multiple_return_markers`
warning is emitted via `%chain.warn` (Jasmine catches it
automatically). The query still runs deterministically; the
warning surfaces the smell.

```
{
    "tags": ["form"], "return": true,
    "then": {
        "tags": ["button"], "return": true,
        "then": {
            "tags": ["span"]
        }
    }
}
```

→ returns forms; warns about the redundant `return: true` on
button.

---

<a id="examples"></a>
## Examples

<a id="basic"></a>
### Basic

```
# CSS: div
{"tags": ["div"]}

# CSS: div, p
{"tags": ["div", "p"]}

# CSS: a[href]
{"tags": ["a"], "atts": {"href": null}}

# CSS: a[href^=https]
{"tags": ["a"], "atts": {"href": {"starts_with": "https"}}}
```

<a id="combinators-1"></a>
### Combinators

```
# CSS: div table  (descendant)
{
    "tags": ["div"],
    "then": {"tags": ["table"]}
}

# CSS: ul > li  (direct child)
{
    "tags": ["ul"],
    "then-child": {"tags": ["li"]}
}

# CSS: h1 + p  (adjacent sibling)
{
    "tags": ["h1"],
    "then-next": {"tags": ["p"]}
}
```

<a id="chained"></a>
### Chained

```
# CSS: div > p + span
{
    "tags": ["div"],
    "then-child": {
        "tags": ["p"],
        "then-next": {
            "tags": ["span"]
        }
    }
}
```

<a id="return-marker-1"></a>
### Return marker

```
# CSS: section:has(h1)
{
    "tags": ["section"],
    "return": true,
    "then": {"tags": ["h1"]}
}

# Form that contains a submit button — return the form
{
    "tags": ["form"],
    "return": true,
    "then": {
        "tags": ["button"],
        "atts": {"type": "submit"}
    }
}
```

---

<a id="mapping-table-css-astro"></a>
## Mapping table: CSS ↔ Astro

| CSS | Astro |
|---|---|
| `div` | `{"tags": ["div"]}` |
| `div, p` | `{"tags": ["div", "p"]}` |
| `.foo` | `{"atts": {"class": {"word_match": "foo"}}}` |
| `#bar` | `{"atts": {"id": "bar"}}` |
| `[disabled]` | `{"atts": {"disabled": null}}` |
| `[type=submit]` | `{"atts": {"type": "submit"}}` |
| `[href^=https]` | `{"atts": {"href": {"starts_with": "https"}}}` |
| `[lang\|=en]` | `{"atts": {"lang": {"hyphen_prefix": "en"}}}` |
| `div.container` | `{"tags": ["div"], "atts": {"class": {"word_match": "container"}}}` |
| `div table` | `{"tags": ["div"], "then": {"tags": ["table"]}}` |
| `ul > li` | `{"tags": ["ul"], "then-child": {"tags": ["li"]}}` |
| `h1 + p` | `{"tags": ["h1"], "then-next": {"tags": ["p"]}}` |
| `div:has(table)` | `{"tags": ["div"], "return": true, "then": {"tags": ["table"]}}` |

CSS strings get compiled into Astro internally; the matching
machinery then operates on Astro.

---

<a id="open-questions"></a>
## Open questions

- **Top-level OR via array?** A top-level selector list (CSS:
  `h1, h2, h3`) is currently `"tags": ["h1", "h2", "h3"]` —
  works because they share zero other constraints. But what about
  `div.foo, p.bar` (different compound selectors)? Need a way
  to express "any of these whole sub-selectors." Probably a
  top-level array of selectors, or an `"or"` key.
- **Class selector form.** Right now `.foo` translates to
  `{"atts": {"class": {"word_match": "foo"}}}`. Verbose. Maybe a
  shorthand `"classes": ["foo"]` (parallel to `tags`)?
- **ID selector form.** Right now `#bar` translates to
  `{"atts": {"id": "bar"}}`. Maybe a shorthand `"id": "bar"`?
- **Negation.** No `:not()` in v1, but Astro could support it
  later with a `"not"` key wrapping a sub-selector.
- **Where does the parser live?** Uma owns the CSS-to-JSON
  compiler; Trivet provides the tree walk; Q0 convergence (if
  any) happens later.
