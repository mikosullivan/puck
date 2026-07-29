# Content-type-driven method inheritance on strings

*Post-V1 idea. When a string's `content_type` is set, the string inherits methods for parsing / manipulating content of that format. `$body.content_type = 'text/json'` gives the string JSON methods; `= 'text/html'` gives it HTML methods. Etc.*

~~~vibecode
{"vibecode": {
	"doc": "idea_content_type_methods",
	"role": "captures the idea that Caspian could let strings inherit format-specific methods based on their content_type — setting the content_type doesn't just annotate, it changes what methods are reachable. Includes the appeal, the design surface it opens, and lighter alternatives that preserve much of the ergonomics without the runtime dispatch complexity.",
	"status": "idea_captured_deferred_until_after_v1",
	"deferred_because": "makes content_type semantically load-bearing rather than annotational; adds a dispatch layer; opens real design work on method sourcing, precedence, security, and reflection semantics",
	"related": ["requirements/built-in-classes/primitives/string/heredocs (owns the content_type slot and its setter/getter semantics — V1 keeps them purely annotational)"]
}}
~~~

## The idea

When code sets a string's `content_type`, the string picks up methods specific to that format:

~~~caspian
$body = %chain.net.get('https://api.example.com/data').body
$body.content_type = 'text/json'

$parsed = $body.parse            # JSON parse method — available because content_type is JSON
$pretty = $body.pretty           # JSON pretty-print — also format-specific
~~~

Or with HTML:

~~~caspian
$page.content_type = 'text/html'

$dom = $page.dom                 # HTML methods
$text = $page.text_only
$title = $page.title
~~~

Same base string; the reachable method set depends on `content_type`. Change the type, get a different method set:

~~~caspian
$str.content_type = 'text/json'
$str.parse                       # parses as JSON

$str.content_type = 'text/html'
$str.parse                       # now parses as HTML — different method behind the same name
~~~

## The appeal

- **`content_type` becomes semantically load-bearing**, not just an annotation for tooling. The type actually decides what you can do with the value.
- **Zero-ceremony access to the parsed form.** No `parse_as_json($str)` helper functions, no `JSON.parse($str)` explicit calls. The string knows what it is.
- **Composable through the ecosystem.** An HTTP response body ships with its `Content-Type` header already reflected in the string; downstream code that consults the parsed form gets it without threading a type through the call chain.
- **Aligned with the "content_type is a real property" decision.** Once we've committed that strings carry their type, using it as a dispatch key follows naturally.

## The design surface it opens

Several substantial questions have to settle before this can ship:

**Where do the methods come from?**

- **Built-in per-type sets.** The engine ships JSON, HTML, XML, CSV, YAML method sets. Then the built-in String surface grows a large method inventory. Every format the engine cares about lives in the core.
- **Downloaded via `%fetch`.** The engine looks up `puck.uno/content-types/text/json` (or similar) when a content type is set and attaches its method set. Composes with the ecosystem — anyone can publish a format handler — but couples runtime behavior to network availability and the fetcher chain.
- **Hybrid.** Common types built in; unknown types delegate to `%fetch` lookup. Best of both, but two mechanisms to keep consistent.

**Method precedence.**

If `text/html` defines `.text` and String's base surface also defines `.text`, which wins? What about a downloaded method that also matches? Precedence rules become a real design surface: base-String < type-set < downloaded-method (`$obj.$fn`)? Or the reverse? Getting this wrong means shadowing or missed methods.

**Same name, different behavior across types.**

`$str.parse` means "parse as JSON" for one type, "parse as HTML" for another. Readers can't tell from the call site what will happen — they have to trace back to where `content_type` was set. Polymorphism via metadata is powerful but harder to reason about than polymorphism via class.

**Action-at-a-distance on content_type reassignment.**

Setting `$str.content_type = 'text/html'` in one function silently changes what methods are available on `$str` for every other holder of the same object. If module A cached `$str.parse` as a function value while `content_type` was JSON, and module B then sets it to HTML, module A's captured method is now stale — or, worse, still valid but referring to the JSON parser. The interaction between "content_type is mutable" and "content_type determines method set" is genuinely load-bearing.

**Security surface.**

`$str.content_type = 'text/attacker_supplied'` becomes a way to route method calls to different code. If any of the resolution paths involve `%fetch` fetch, the type string becomes a URL fragment — an attacker who controls the type controls what code runs. Any per-type method set needs a trust anchor decision (baked-in whitelist? blockchain-signed only? user-configured?), which is real security work.

**Reflection.**

- `$str.class` — is that `String` or `String::Json`? Programs that dispatch on class see one or the other, with implications.
- `$str.methods` — different list at different times? A method-inspection tool has to know to include the type-set contribution.
- Comparison: `$str1 == $str2` where they have the same text but different types — equal or not? (Probably yes-equal on value grounds, but that means the type isn't part of identity, which is inconsistent with "the type changes what methods exist.")

**Serialize round-trip.**

A typed string serialized to JSON is just its text. Round-tripping loses the type (and therefore the method set). Consumers can re-set `content_type` on the way back in, but "get the string back and reattach the type" is a step someone will forget.

## Lighter alternatives worth considering first

The polymorphism-via-type idea is elegant but crosses a line — the language runtime becomes content-type-aware in a way it currently isn't. Two lighter shapes preserve most of the ergonomics without the runtime dispatch:

### Alternative 1: explicit `.parsed_X` methods

Base String exposes `.parsed_json`, `.parsed_html`, `.parsed_xml`, etc. as regular methods. Each looks at the string's content_type (or accepts an explicit override) and returns the parsed object:

~~~caspian
$body.content_type = 'text/json'
$parsed = $body.parsed_json         # or: $body.parsed (with content_type)
~~~

Zero runtime dispatch complexity — the methods are always available on every string; calling `.parsed_json` on a non-JSON string is just an error at runtime like any other bad call. String stays simple; content_type stays annotational.

### Alternative 2: type-aware parser lookup via `%fetch`

No String method inheritance at all. Consumers explicitly reach for the parser they want:

~~~caspian
$body.content_type = 'text/json'
$parsed = %('puck.uno/json').parse($body)
~~~

The string carries the type; the parser is a Puck-downloaded library. Fully explicit, no dispatch magic, uses existing mechanisms end-to-end. Less ergonomic than the "methods just appear" version, but every step is greppable and every failure mode is legible.

### Alternative 3: `.as(type)` returning a typed wrapper object

Base String has a `.as(type)` method that returns a **wrapper object** whose class matches the type. The wrapper's methods are the format-specific ones; the underlying string stays untyped:

~~~caspian
$json = $body.as('text/json')       # returns a Json object wrapping $body
$parsed = $json.parse
~~~

Separates the "I know what this is" declaration (`content_type` on the string) from the "I want the typed representation" action (`.as(type)`). The wrapper is a proper object with its own class, its own methods, its own reflection story — no runtime type-dispatch on String, no method-set changes triggered by attribute writes.

## When to revisit

Once V1 ships and real Caspian code accumulates that touches HTTP bodies, config files, downloaded artifacts, and so on — we'll have concrete data on how often the ergonomics of "typed string with format methods" actually pays for itself. If the answer is "constantly," the design surface above is worth working through carefully. If callers happily reach for `%('puck.uno/json').parse($body)` and don't miss the inheritance form, then the base-annotation-only story is enough.

Until then, V1 keeps `content_type` purely annotational as spec'd in [heredocs § Type annotation](https://puck.uno/requirements/built-in-classes/primitives/string/heredocs#type-annotation).

## Related

- [heredocs § Type annotation](https://puck.uno/requirements/built-in-classes/primitives/string/heredocs#type-annotation) — the V1 spec for `content_type`: getter/setter, no validation, no runtime dispatch.
- [ideas/pluggable-syntax.md](pluggable-syntax.md) — a related "make the language more extensible" idea also deferred until after V1.
