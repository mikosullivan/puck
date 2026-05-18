# Project Information

~~~json
{"vibecode": {
	"doc": "uma-history-vibecode",
	"role": "imported per-project documentation from the prior Ruby Uma library: purpose, primary files, core object model, and public behavior of Uma as a Nokogiri::HTML5 wrapper",
	"key_concepts": ["ruby_uma_project_info", "nokogiri_wrapper", "canon_json_schema",
		"uma_element_extension"],
	"status": "historical"
}}
~~~

<a id="purpose"></a>
## 1 Purpose

`uma` is a Ruby HTML document builder and DOM helper built on top of `Nokogiri::HTML5`.

The library wraps a parsed HTML5 document, adds convenience methods for creating and editing elements, and enforces a project-defined HTML schema built from `lib/uma/canon.json`.

This file should describe only the current implemented state of the project. Future plans, proposals, and open design questions belong in `documentation/ISSUES.md`.

<a id="primary-files"></a>
## 2 Primary Files

- `lib/uma.rb` is the main public entry point.
- `lib/uma/builder.rb` builds the runtime tag-definition hash from `lib/uma/canon.json`.
- `lib/uma/canon.json` is the canonical normalized source of truth for the HTML tag model.
- `lib/uma/tags.json` is derived from `lib/uma/canon.json` and is rarely used directly in practice.
- `lib/uma/development.rb` provides development helpers such as the bundled `midsummer.html` fixture.
- `command-line/tests/` contains the project test tree.
- `command-line/misc/canon/denormalize.rb` prints the fully built tag-definition model.

<a id="core-object-model"></a>
## 3 Core Object Model

`Uma.new(html=nil, **opts)` creates an `Uma` wrapper around a `Nokogiri::HTML5::Document`.

If no HTML is supplied, `Uma` builds a default HTML5 document with `html`, `head`, `title`, `meta charset`, and `body`.

Each parsed element is extended with `Uma::Element`, and the document is extended with `Uma::Document`.

The `Uma` instance delegates `header`, `main`, and `footer` to the wrapped document.

The document keeps a back-reference to the owning `Uma` instance through `doc.uma`.

<a id="public-behavior"></a>
## 4 Public Behavior

The main user-facing patterns in the current code are:

- `Uma.create` or `Uma.basic` creates a default HTML5 document.
- `Uma.new(raw_html)` parses an existing document.
- `uma.doc` exposes the wrapped `Nokogiri::HTML5::Document`.
- `uma.body`, `uma.head`, `uma.header`, `uma.main`, and `uma.footer` expose common document sections.
- `uma.to_html` returns the raw document string.
- `uma.pretty` or `uma.generate` returns HTML beautified through `HtmlBeautifier`.
- `uma.content_type` returns `text/html`.
- `uma.tidy` consolidates adjacent text nodes through recursive element cleanup.
- `uma.import(other_docs...)` imports content from source documents into `.target` / `.source` placeholders or matching `data-tgt` / `data-src` pairs.
- `uma.sanitize` removes attributes that are not allowed by the built tag definitions.
- `uma.title` reads the current title, and `uma.title = value` writes both the document `<title>` and any `.title` elements during serialization.
- `Uma.wrap(str, width:, sep:)` wraps long strings with configurable width and separator text.
- `Uma.json_css` returns the bundled stylesheet used by the JSON-ish HTML rendering helpers.

In current usage, Uma is mainly used to build full HTML pages.
Uma should be thought of primarily as an HTML builder; for general DOM editing, Nokogiri already provides the baseline editing methods.
In normal use, Uma should favor strict schema validation so it catches authoring mistakes rather than accommodating messy real-world HTML.
For messy real-world HTML, Nokogiri should handle parsing first; once the document is parsed, Uma can be used for its HTML-focused builder features on top of that document.
In practice, Uma objects are created both from scratch with `Uma.basic()` and from existing documents with `Uma.new(existing_html)`.
In day-to-day use, the most important Uma feature is dynamic child creation through tag-name methods.
In practice, tag information derived from `canon.json` is used to decide whether a tag or attribute is allowed.
`set_tag_mod` is more of a power-user feature than a normal extension path for everyday Uma usage.
There is effectively a single real-world Uma user, so there is no meaningful recurring class of new-contributor mistakes to document from shared usage.
`pretty()` prettifies the HTML before returning it.
The key mental model for using Uma is that it helps build syntactically correct, secure HTML documents.

<a id="element-extensions"></a>
## 5 Element Extensions

`Uma::Element` adds convenience methods on top of Nokogiri elements. These methods are the core of the builder-style API used throughout the tests.

Important behaviors:

- Calling a tag name as a method creates that child if the schema allows it. Example: `body.div`, `table.tr`, `body.radio`.
- `radio`, `checkbox`, and `hidden` are aliases that create `<input>` with the appropriate `type`.
- Unknown children raise `Uma::Error::UnknownChild`.
- Unknown attributes raise `Uma::Error::UnknownAtt`.
- Adding children to a void element raises `Uma::Error::EmptyElement`.
- `id` and `id=` are convenience wrappers for the `id` attribute.
- `classes` returns a `Uma::Classes` helper for toggling CSS classes.
- `separator` and `bulletize` provide serialization-time text separators between sibling children.
- `unwrap` removes an element while preserving its children.
- `show`, `show_hash`, and `show_array` render JSON-like structures into HTML tables and text containers.

`Uma::Document#set_tag_mod(tag_name, mod)` can extend matching elements with Ruby modules. `'*'` applies a module to every element. This is used in tests and developer scripts to inject tag-specific behavior after parsing and after newly created nodes are added.

`Uma::Element` also defines a special table behavior: calling `tr` on a `table` ensures a `tbody` exists and inserts the row there.

<a id="api-examples"></a>
## 6 API Examples

Create a default document and add content:

```ruby
uma = Uma.basic()
uma.body.h1.text 'Hello'
uma.body.p.text 'World'
puts uma.pretty
```

Create input aliases through dynamic tag helpers:

```ruby
uma = Uma.basic()
body = uma.body
body.radio
body.checkbox
```

Import placeholder content from other HTML documents:

```ruby
base = Uma.new(base_html)
base.import(fragment_a, fragment_b)
```

Apply a separator between sibling children during serialization:

```ruby
uma = Uma.basic()
body = uma.body
body.span.text 'a'
body.span.text 'b'
body.separator = ' • '
puts uma.pretty
```

Attach Ruby behavior to tags with `set_tag_mod`:

```ruby
mod = Module.new do
	def flagged?()
		true
	end
end

uma = Uma.new(html)
uma.set_tag_mod 'table', mod
puts uma.at_css('table').flagged?
```

Use JSON-style rendering helpers on elements:

```ruby
uma = Uma.basic()
uma.body.show({'a' => 1, 'b' => [2, 3]})
puts uma.pretty
```

<a id="tag-definition-system"></a>
## 7 Tag Definition System

`lib/uma/canon.json` is the normalized source of truth for the tag model.

Use `sources` for reusable fragments and `tags` for tag-specific definitions. A source may define shared `atts`, shared `children`, and `include` other sources.

Include expansion is recursive. When a source or tag includes another source, the builder deep-merges the included fragment into the working structure, and that merged result becomes the built description.

All tags automatically receive the attributes in `default`, so those attributes should not be repeated elsewhere unless there is a specific reason.

`inlines` is the main reusable inline child set. `flow-content` is a broader semantic source that currently builds on `blocks` and adds extra non-block flow children.

Some tag definitions also use `cannot-nest`, which is a tag-level array describing descendant tags that must not appear anywhere inside that tag's subtree.

<a id="builder-behavior"></a>
## 8 Builder Behavior

`Uma::Builder` loads `canon.json`, recursively resolves includes, deep-freezes the canonical data, and builds a final tag-definition hash.

When a tag is built:

- included sources are expanded first
- tag-specific values override included values through deep merge
- `default` is merged into every tag
- scalar keys are moved toward the top
- `atts` and `children` are reordered and their keys sorted

The final built tag definitions are stored on each `Uma` instance as `tag_defs`. Element creation and attribute validation consult those built definitions at runtime.

<a id="canon-json-formatting"></a>
## 9 Canon JSON Formatting

When editing `lib/uma/canon.json`, keep empty hash values on one line as `{}` instead of expanding them across multiple lines.

Example: write `"colspan": {},` instead of a multi-line empty hash.

If an `include` array has no more than two elements, write it on a single line.

In tag definitions, scalar values should appear at the top of the hash.

When `lib/uma/canon.json` is edited manually or merged from multiple changes, recheck the file against the WHATWG HTML Standard so obsolete or non-spec entries are not reintroduced.

<a id="external-html-reference"></a>
## 10 External HTML Reference

Use the WHATWG HTML Standard as the external source of truth for HTML 5.

Main specification:
- https://html.spec.whatwg.org/

Full index:
- https://html.spec.whatwg.org/multipage/fullindex.html

When `canon.json` is updated to reflect HTML 5 behavior, validate those decisions against the WHATWG HTML Standard rather than against secondary summaries.

<a id="tests-and-examples"></a>
## 11 Tests And Examples

The project test tree is `command-line/tests`.

Representative tests currently cover:

- basic document creation and parsing
- allowed and disallowed child creation
- allowed and disallowed attribute assignment
- errors on adding children to void elements
- alias tags such as `radio` and `checkbox`
- title reading and propagation
- import behavior for placeholder-based templates
- separator behavior during serialization
- tag module injection through `set_tag_mod`
- automatic `tbody` insertion when adding rows to `table`
- `id` helpers
- `tidy` text-node consolidation

Many tests use `Bryton` or `Minitestish` rather than stock Minitest.

<a id="execution-workflow"></a>
## 12 Execution Workflow

The project is edited locally in the mounted working directory and executed remotely on `autolycus.idocs.com`.

For tests under `command-line/tests`, use the standard remote test runner described in the global guidance:

```bash
ssh autolycus.idocs.com 	'~/run-test.rb /home/miko/mounts/oberon/projects/ruby/uma/working/command-line/tests/most.rb'
```

For non-test scripts, SSH to `autolycus.idocs.com` and run them directly in the project tree.

To see the full built HTML tag-definition model from `canon.json`, run `command-line/misc/canon/denormalize.rb` remotely from the `command-line/misc` tree with the required environment.

<a id="workflow-overview"></a>
## 13 Workflow Overview

- `AGENTS.md` should point here first.
- `documentation/ISSUES.md` tracks open issues.
- `documentation/CHANGELOG.md` is a flat summary of completed changes and resolutions.
- `documentation/PRIVATE.md` is optional and currently contains no project-specific guidance.
