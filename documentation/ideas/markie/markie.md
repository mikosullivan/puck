# Markie

~~~json
{"vibecode": {
	"doc": "markie",
	"status": "brainstorm — early; feature list is exploratory, no commitments",
	"role": "online HTML-DSL transpiler service at markie.uno; the SASS-or-TypeScript story for HTML — author compact DSL, get standard HTML back",
	"surface": "Puck protocol object AND standalone HTTP API (so non-Puck clients can use it too)",
	"ties": "Markie's built-in component vocabulary mirrors jqmin patterns — compact DSL forms expand to the full jqmin/HTML markup"
}}
~~~

**Markie is an HTML-DSL transpiler offered as a service.** You submit a document in Markie's DSL — compact, named components, nested constructs, remote-content placeholders — and you get back standard HTML. Same idea as SASS → CSS or TypeScript → JS, but for HTML.

Markie lives at `markie.uno`. Accessible through the Puck protocol (`%['markie.uno']` from Charlie) and through a standalone HTTP API (any client can POST a DSL doc and get HTML back, no Puck dependency).

The motivator: get the developer ergonomics of a component framework (compact source, named components, recursive nesting) without committing the browser to a client-side runtime. Markie does the expansion server-side; the client gets fully-formed HTML and only the lightweight CSS/JS it actually needs.

## Core transpilation

~~~json
{"vibecode": {
	"section": "core_transpilation",
	"role": "the fundamental DSL-to-HTML expansion mechanism"
}}
~~~

### Compact DSL to standard HTML

Submit a document written in Markie's component DSL — short tags with attributes — and receive standard HTML5 with the components expanded into their full markup. The output is browser-direct: no client-side library required to interpret it.

### Recursive expansion

Markie components can contain other Markie components, and the expansion is recursive. Nested `<menu>` constructs become nested `<details>` markup; a `<checkbox>` inside a `<form>` inside a `<panel>` all expand in one pass.

### Custom DSL extensions

Clients can register their own DSL tags and expansion templates with Markie, scoped to their account or document. Lets a team add domain-specific shorthand (`<product-card>`, `<order-summary>`) without forking Markie.

## Component library

~~~json
{"vibecode": {
	"section": "component_library",
	"role": "the built-in vocabulary of named components Markie understands"
}}
~~~

### Built-in jqmin vocabulary

Markie ships with the [jqmin](https://puck.uno/documentation/site/frameworks/jqmin/) patterns as DSL constructs. `<checkbox prompt="...">` expands to the full custom-checkbox markup; `<dropdown link="..." label="...">` expands to the `<details>`-based dropdown; etc. Use Markie with jqmin and the markup is concise; use jqmin without Markie and write the full HTML by hand.

### Vocabulary versioning

A document declares which Markie vocabulary version it expects. Markie keeps prior versions live so existing documents don't break when the vocabulary evolves. Standard semver pin.

### Vocabulary discovery

Query Markie for the list of components it knows about, their accepted attributes, and example expansions. Lets tooling (editors, linters, dev consoles) offer autocomplete and validation.

## Remote content

~~~json
{"vibecode": {
	"section": "remote_content",
	"role": "fetch HTML fragments from elsewhere and splice them into the output server-side"
}}
~~~

### Server-side URL embedding

A DSL element like `<embed src="https://example.com/widget.html">` (final tag name TBD) tells Markie to fetch the URL and splice the response into the output. The browser receives one merged document; no iframe, no client-side fetch.

### Puck-object embedding

`<embed src="puck.uno/weather?zip=24136">` resolves via the Puck protocol — Markie calls the Puck object server-side and inlines its rendered output. Lets Puck objects act as first-class HTML widgets without a custom client.

### Per-URL caching

Embedded fetches are cached with sensible TTLs and respect upstream `Cache-Control` headers. The same URL referenced twice on a page costs one fetch. Configurable invalidation hooks.

## Composition

~~~json
{"vibecode": {
	"section": "composition",
	"role": "structural features for building larger documents from smaller pieces"
}}
~~~

### Template inheritance

Submit a base layout with placeholder slots plus a derived fragment that fills them; Markie returns the assembled document. Same shape as Robinson's [target/content cascade](https://puck.uno/documentation/ideas/robinson/robinson#targetcontent-cascade), but offered to any client without requiring Robinson to be in the pipeline.

### Local file includes

`<include src="header.html">` splices a sibling fragment from the same document submission. Lets a multi-file document share common pieces without going through the remote-embed machinery.

### Conditional rendering

`<if condition="...">` for simple conditionals. The condition language is small — equality, presence, comparison against submitted variables. Not a full programming layer.

### Iteration

`<for-each over="...">` repeats a fragment for each item in a list provided with the submission. Useful for tables, menus, repeated cards.

## Security

~~~json
{"vibecode": {
	"section": "security",
	"role": "the rules that make embedding remote content into your own DOM safe"
}}
~~~

### Sanitization of embedded content

Content fetched via `<embed>` runs through a sanitizer before splicing: scripts stripped by default, event handlers removed, dangerous attributes (`javascript:` URLs, etc.) blocked. Configurable allowlist for cases where the source is trusted.

### Resource allowlist

A document can declare which domains its embeds are allowed to fetch from. Markie rejects embed URLs outside the allowlist. Defense against accidental or compromised embed targets.

### Output limits

Bounded expansion size, bounded recursion depth, bounded embed-fetch count per request. Prevents runaway expansion (e.g. circular includes) from consuming server resources or producing multi-megabyte responses.

## Developer ergonomics

~~~json
{"vibecode": {
	"section": "developer_ergonomics",
	"role": "features that make Markie pleasant to author against and debug"
}}
~~~

### Validation mode

Submit a document with a `validate` flag and Markie returns DSL syntax errors, unknown components, attribute issues, and broken embed URLs without doing the actual expansion. Lets editors and CI catch problems fast.

### Source-position mapping

The expanded HTML can include comments or attributes mapping each region back to the source-DSL line. Useful for debugging "where did this HTML come from" when looking at the rendered output.

### Pretty / minified output

A flag chooses between formatted (indented, commented) output for development and minified output for production. Same expansion, different shape.

## API surfaces

~~~json
{"vibecode": {
	"section": "api_surfaces",
	"role": "the ways to call Markie"
}}
~~~

### REST POST endpoint

`POST https://markie.uno/expand` with the DSL document in the request body. Returns the expanded HTML. The canonical no-dependency API.

### URL-fetch endpoint

`GET https://markie.uno/expand?source=https://...` — Markie fetches the DSL document from the given URL, expands it, returns the result. Useful for CDN-cached static documents.

### Puck protocol object

`%['markie.uno'].expand(source: '...')` from Charlie. The first-class Puck integration; lets Charlie code generate Markie input and consume its HTML output without HTTP plumbing.

## Open questions

### Tag name for remote includes

Real HTML `<embed>` is a void element with `src`. Reusing it for Markie's server-side splicing creates source-reading confusion and bad fallback rendering when the doc bypasses Markie. Alternatives: `<markie src="...">`, `<include src="...">`, `<div data-markie="...">`. To be settled.

### Scope of the conditional/iteration layer

How far should Markie go toward being a full template engine? Conditionals and loops shade into "everything PHP / ERB / Jinja already does." A small subset is useful; the full menu turns Markie into a competitor of every template engine ever. Where to draw the line?

### Relationship to Robinson's cascade

Robinson's `<target>` / `<content>` cascade is structurally similar to Markie's template-inheritance feature. They could be the same engine offered in two contexts (inline at Robinson request time + as a service at markie.uno) or two separate implementations. Worth deciding before both grow far.

### Account model

Custom DSL extensions and per-doc resource allowlists imply some form of account or namespace. Public submission with no account works for the basic transpiler; the moment a client wants persistent custom vocabularies, identity matters. What's the minimum identity layer?

### Caching invalidation

Per-URL embed caching is easy; cache invalidation on upstream changes is the usual hard problem. TTL-based is the lazy answer; webhook-based is the powerful answer. Worth the work?
