# Kiera HTML Format

JSON and HTML are both official formats for Kiera objects. An object can be expressed
in either form and converted between them losslessly. Neither is preferred over the
other.

The HTML format is intended for serving objects at their UNS URL — a human visiting
`borg.com/parser` in a browser sees a readable page; a machine reading the same page
can reconstruct the JSON exactly.

## Design Goal: AI Cold-Start (Tuvok II)

**An AI agent that visits a Kiera class page with no prior knowledge of Kiera should
be able to understand what the page is, what the object does, and how to use Kiera —
from the page alone.**

This context is page-level information about the system, not data belonging to the
object itself. It lives in a `<meta name="kiera:vibecode">` tag in the `<head>`:

```html
<meta name="kiera:vibecode" content='{"ecoverse":"kiera",
"ecoverse_description":"Kiera is a distributed object system...",
"this_page":"class definition — describes a type with typed fields and callable methods",
"how_to_use":"...",
"verification":"object provenance and integrity can be verified via blockchain.kiera.uno",
"ecoverse_info":"kiera.uno/vibcode"}'>
```

Because it is page metadata and not object data, it does not appear in the JSON
translation of the object. An AI reading the page sees it in `<head>`; a parser
doing JSON conversion ignores it.

The meta tag must include:

- What Kiera is — a brief description of the distributed object system and UNS addresses
- What this page is — a class definition with fields and methods
- How to use it — fetch from the UNS address, read fields and methods sections
- Where to verify — the blockchain API at `blockchain.kiera.uno`
- Where to learn more — `kiera.uno/vibcode`

See `json.html` in this directory for a worked example.

---

## Data Attributes (Annika Voyager)

The machine-readable structure is carried entirely in `data-kiera-*` attributes. The
visible HTML is purely for display and has no effect on conversion.

| Attribute | Purpose |
|-----------|---------|
| `data-kiera-type` | The type of this node: `hash`, `array`, `string`, `number`, `boolean`, or `null` |
| `data-kiera-key` | The key name when this node is a value inside a parent hash |
| `data-kiera-value` | The scalar value for `string`, `number`, and `boolean` nodes |
| `data-vibecode` | A JSON object providing a compact specification of this element. Parsed and included as a `"vibecode"` key in the element's JSON object. |

Array items carry no `data-kiera-key`. Their position in the DOM is their position in
the array.

When `data-vibecode` is present on an element, its value is parsed as JSON and included
as `"vibecode"` in that element's JSON object. This is the mechanism for lossless
round-tripping of vibecode — the `"vibecode"` key in JSON maps directly to the
`data-vibecode` attribute in HTML, and vice versa.

---

## Type Mapping (EMH Mark II)

| JSON type | `data-kiera-type` | Value location |
|-----------|-------------------|----------------|
| `{}` hash | `hash` | Child elements with `data-kiera-key` |
| `[]` array | `array` | Child elements in DOM order |
| `"string"` | `string` | `data-kiera-value` attribute |
| `123` number | `number` | `data-kiera-value` attribute |
| `true`/`false` | `boolean` | `data-kiera-value` attribute |
| `null` | `null` | No value attribute needed |

---

## Conversion Rules (Lewis Zimmerman)

**JSON → HTML**

1. The root object becomes an element with `data-kiera-type="hash"`.
2. Each key-value pair becomes a child element with `data-kiera-key` set to the key
   name and `data-kiera-type` set to the value's type.
3. For scalar values, `data-kiera-value` holds the raw value as a string.
4. For hash and array values, recurse into child elements.
5. If an object has a `"vibecode"` key, serialize its value as the `data-vibecode`
   attribute on that element. Do not emit it as a child element with `data-kiera-key`.
6. Display content (labels, badges, layout) may be added freely — it is ignored during
   conversion back to JSON.

**HTML → JSON**

1. Find the root element with `data-kiera-type`.
2. For `hash`: collect all direct structural children with `data-kiera-key` as
   key-value pairs.
3. For `array`: collect all direct structural children in DOM order.
4. For `string`, `number`, `boolean`: read `data-kiera-value`.
5. For `null`: value is `null`.
6. If `data-vibecode` is present, parse it as JSON and include it as the `"vibecode"`
   key in that element's object.
7. Ignore all elements without `data-kiera-type` — they are display-only.

---

## UNS Values as Links (Reginald Voyager)

When a scalar string value is a UNS address, the display text may be wrapped in an
`<a>` tag linking to the UNS URL. The `data-kiera-value` attribute still holds the
bare UNS string; the link is display-only and does not affect conversion.

```html
<div data-kiera-type="string" data-kiera-value="kiera.uno/tag/parsing" class="kiera-field">
  <div class="field-key">[0]</div>
  <div class="field-value">
    <a href="https://kiera.uno/tag/parsing" target="_blank">kiera.uno/tag/parsing</a>
  </div>
</div>
```

---

## Vibecode (Barclay Voyager)

Any element may carry a `data-vibecode` attribute containing a minified JSON
specification of that element's semantics. Vibecode is supplementary — it does not
replace the `data-kiera-*` attribute structure, but provides a compact formal summary
that tools and AI agents can read without traversing the full tree.

Vibecode on the root element describes the object as a whole:

```html
<div data-kiera-type="hash"
     data-vibecode='{"class":"kiera.uno/class","name":"borg.com/parser","version":"2.1.0",
"description":"Parses structured text input into a normalised output hash.",
"tags":["kiera.uno/tag/parsing","kiera.uno/tag/text","kiera.uno/tag/validation"]}'>
```

Vibecode on a section element describes that section:

```html
<div data-kiera-key="fields" data-kiera-type="hash"
     data-vibecode='{"section":"fields","input":{"type":"string","required":true},
"output":{"type":"hash","required":true},"max_length":{"type":"number","required":false,
"default":65536}}'>
```

Vibecode on a method element describes that method:

```html
<div data-kiera-key="parse" data-kiera-type="hash"
     data-vibecode='{"method":"parse","returns":"hash","args":{"text":{"type":"string",
"required":true},"options":{"type":"hash","required":false}}}'>
```

Vibecode values use single quotes as the HTML attribute delimiter so that JSON's double
quotes need no escaping. Multi-line values are soft-wrapped at 90 characters, breaking
after `,` or `:`, with flush-left continuations.

---

## Notes (Hirogen Alpha)

- Key order in the JSON is preserved by DOM order. Parsers must iterate child elements
  in order, not sort them.
- The `class` attribute on HTML elements is used for styling only and has no meaning
  in the Kiera HTML format.
- There is no required element type. A `<div>`, `<span>`, `<tr>`, or any other element
  may carry `data-kiera-*` attributes. The format is element-agnostic.
