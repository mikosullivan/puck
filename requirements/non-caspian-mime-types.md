# Non-Caspian MIME types
<!--index: 17-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_non_caspian_mime_types",
	"role": "spec for how %fetch and the engine handle content whose Content-Type is NOT `text/x-caspian` or `text/x-caspianj`. Two-tier model: recognized Content-Types are run through a parser registered in `%fetch.parsers` (a plain hash keyed by MIME type, user-role writes, ambient reads, process-scoped, matching the shape of `%fetch.locals` and `%fetch.maps`) and returned as a parsed object; unrecognized Content-Types are returned as a typed byte blob for the caller to handle. Caspian ships built-in parsers for plain text, JSON, YAML, and XML. Additional parsers are registered by the script that needs them; future config-file mechanisms may let developers assign parsers at engine-launch time. Empty content raises for structured Content-Types (Caspian, CaspianJ, SVG, and any unfamiliar type by default); text/plain allows empty; per-type rules can override.",
	"status": "stub — two-tier model settled; parser registry shape settled; empty-content posture settled; parser signature and per-type behavior to be filled in as concrete needs arrive.",
	"audience": "developers using %fetch to download non-Caspian content; developers registering custom parsers; engine implementers realizing the per-type dispatch; anyone thinking about how format-specific handling composes with the fetch pipeline"
}}
~~~

`%fetch` is a general-purpose downloader — it fetches by URL and does not restrict what the URL serves. Caspian and CaspianJ are the two content types the engine parses and evaluates natively; **everything else** is handled by a two-tier model driven by the Content-Type the server returns (or the `meta.json` value the cache stores).

## The two-tier model

For any Content-Type other than `text/x-caspian` and `text/x-caspianj`, `%fetch` operates in one of two modes:

**Recognized (parser mode).** If a parser is registered for the Content-Type in [`%fetch.parsers`](#the-parser-registry), `%fetch` runs the response bytes through that parser and returns the resulting object. The parser understands the format; the caller receives a domain-appropriate value they can use directly.

~~~caspian
$config = %fetch('https://foo.bar/config.json')   # parsed JSON hash
$rules = %fetch('https://foo.bar/rules.yaml')     # parsed YAML value
~~~

**Unrecognized (blob mode).** If no parser is registered for the Content-Type, `%fetch` returns a **typed byte payload** — the raw bytes together with the Content-Type — to the caller. The engine does not parse or evaluate; the caller decides how to interpret the bytes.

~~~caspian
$blob = %fetch('https://foo.bar/image.png')       # blob: raw bytes + 'image/png'
&write_png_file $blob.bytes
~~~

The two-tier model gives the caller uniform ergonomics for common types (parsed objects arrive ready to use) without restricting what %fetch will fetch (unknown types still work, just as blobs).

## The parser registry

`%fetch.parsers` is a plain hash keyed by MIME type. Same conventions as `%fetch.locals` and `%fetch.maps`:

- **Plain hash.** Any standard hash operation works — iterate to inspect, assign to add or replace, unset to remove, `%fetch.parsers.has?('application/json')` to check.
- **User-role writes.** A non-user role attempting to assign to `%fetch.parsers` raises. Untrusted code cannot inject parsers or hijack what %fetch returns.
- **Ambient reads.** Any role that can use `%fetch` sees the registered parsers.
- **Process-scoped.** Registrations persist for the whole process run; `%fetch` does not live on `%chain`, so a parser registered in one script applies to every subsequent fetch anywhere in the process.
- **Last-write-wins.** One parser per Content-Type. Assigning to a Content-Type that already has a parser replaces the old one silently.

The parser value itself — whether it's a function, a class, a callable, or a specific interface — is not yet spec'd. Track that as an open question until concrete needs pin it down.

## Built-in parsers

Caspian ships with parsers pre-registered for four common Content-Types:

- **`text/plain`** — plain text. The bytes are decoded as a UTF-8 string and returned. Empty content is allowed (an empty string is a legal value).
- **`application/json`** — JSON parser. Returns hashes, arrays, strings, numbers, booleans, and null.
- **`application/yaml`** (also `text/yaml`, `application/x-yaml`) — YAML parser. Returns the same value types as JSON, plus YAML-specific structures where applicable.
- **`application/xml`** (also `text/xml`) — XML parser. Returns a document-tree object.

No explicit registration is needed to use these; they're on `%fetch.parsers` at engine startup.

## Adding parsers in scripts

Parsers for any Content-Type beyond the built-ins are added by the script that needs them, via direct assignment to `%fetch.parsers`. Only user-role scripts can register parsers (matching the write-restriction on the hash).

~~~caspian
%fetch.parsers['image/svg+xml'] = $svg_parser
%fetch.parsers['application/vnd.acme.thing'] = $acme_parser

$diagram = %fetch('https://foo.bar/logo.svg')     # parsed by $svg_parser
~~~

Once registered, the parser applies to every subsequent `%fetch` fetch (in any role) that returns a matching Content-Type.

## Future: config-file registration

Caspian doesn't currently have a launch-time config-file mechanism. If one is spec'd later, one of the things it should consider is **allowing parsers to be assigned to MIME types in the config**, so a project can register its parsers once at launch instead of repeating the registration in every script. Until then, the only way to extend `%fetch.parsers` beyond the built-ins is a script-level assignment.

## Empty-content handling

Whether an empty response is a legitimate result depends on the Content-Type. The engine applies these rules at fetch time — if the fetched content is zero bytes AND the Content-Type disallows empty content, the fetch raises.

| Content-Type | Empty content |
|---|---|
| `text/x-caspian` | **Raise.** An empty Caspian source file has no top-level value, so the evaluate step has nothing to produce. |
| `text/x-caspianj` | **Raise.** An empty CaspianJ file has no tree to evaluate. |
| `text/plain` | **Allowed.** An empty text string is a legal value. |
| `image/svg+xml` | **Raise.** An SVG document must have a root element; zero bytes is not valid SVG. |
| Other structured formats (JSON, XML, HTML, PNG, ...) | **Raise.** Most structured formats require at least a root or header; zero bytes is malformed for them. |
| Other unfamiliar Content-Types | **Raise** by default. |

**Default posture: raise on empty.** For any Content-Type the engine doesn't have a specific rule for, an empty fetch raises. This catches the common situations where zero bytes indicates a truncated download, a server misconfiguration, or a broken URL. If a specific Content-Type genuinely allows empty content, it can be added to the "allowed" side of the table with a rationale.

## Per-type handling

*(To be filled in as concrete situations arrive — Content-Types with parsing behavior beyond "hand the bytes to the caller," format-specific validation rules, cache-related considerations, and so on.)*

## Testing

- **Recognized Content-Type routes through the registered parser** — a fetch returning `application/json` calls the built-in JSON parser and returns the parsed value.
- **Unrecognized Content-Type returns a blob** — a fetch returning `image/png` yields an object exposing the raw bytes plus the Content-Type string; the engine does not attempt to parse.
- **`text/plain` returns a UTF-8 string** — a `text/plain` response is decoded and returned as a Caspian string value.
- **`text/plain` empty body returns an empty string** — a zero-byte `text/plain` response returns `""` without raising.
- **`application/json` returns Caspian data** — a JSON response of `{"a":1}` yields a hash with key `a` mapped to `1`.
- **`application/yaml` variants share a parser** — `application/yaml`, `text/yaml`, and `application/x-yaml` all route through the same parser.
- **`application/xml` and `text/xml` share a parser** — both media types route through the same XML parser.
- **Built-in parsers are registered at startup** — the first line of user code sees `text/plain`, `application/json`, `application/yaml`, and `application/xml` already in `%fetch.parsers`.
- **User-role script can register a new parser** — `%fetch.parsers['image/svg+xml'] = ...` succeeds and subsequent fetches of that Content-Type run through it.
- **Non-user role registration raises** — a non-`user` assignment to `%fetch.parsers` raises without mutating the hash.
- **Ambient read from non-user role** — a non-`user` fetch of a URL whose Content-Type has a registered parser returns the parsed value.
- **Last-write-wins on re-registration** — assigning a new parser to a Content-Type that already has one replaces the earlier parser silently.
- **Process-scoped persistence** — a parser registered in one script is used by subsequent fetches from any script in the same process.
- **Malformed JSON raises** — a Content-Type `application/json` body that is not valid JSON raises through the parser.
- **Malformed YAML raises** — a Content-Type `application/yaml` body that is not valid YAML raises.
- **Malformed XML raises** — a Content-Type `application/xml` body that is not valid XML raises.
- **Empty `text/x-caspian` raises** — a zero-byte `.casp` response raises with a "no top-level value" style message.
- **Empty `text/x-caspianj` raises** — a zero-byte `.caspj` response raises.
- **Empty `image/svg+xml` raises** — a zero-byte SVG response raises even though a parser is registered.
- **Empty unfamiliar Content-Type raises** — a zero-byte response with a Content-Type the engine has no rule for raises by default.
- **Parsed value carries the fetch's role tag** — a value returned through a parser carries the role of the surface that introduced the bytes, not `user`.
- **Blob value carries the fetch's role tag** — same for a returned blob value.
- **Blob `.bytes` returns the exact response body** — for an unrecognized type, `.bytes` on the returned object is byte-identical with the fetched response.
- **Content-Type parameter is ignored for registry lookup** — `application/json; charset=utf-8` and `application/json` both dispatch to the JSON parser.

## Related

- [content-types](https://puck.uno/requirements/content-types) — canonical Content-Type strings for Caspian source and CaspianJ tree files, plus how servers should return them.
- [cache-dir](https://puck.uno/requirements/cache-dir) — how the cache stores non-Caspian content alongside its Content-Type in `meta.json`. The empty-content rules on this page apply when the cache serves a stored version back to a caller.
- [`%fetch`](https://puck.uno/requirements/chain/methods/puck) — the Caspian-side gateway for URL fetches. `%fetch.parsers` sits alongside `%fetch.maps` and other `%fetch.X` state.
