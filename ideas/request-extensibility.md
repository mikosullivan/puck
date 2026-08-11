# Idea: Request extensibility

~~~vibecode
{"vibecode": {
	"doc": "ideas_request_extensibility",
	"role": "spitball page for how third-party code (SDKs, downloaded classes, application code) can extend or customize the outbound HTTP request class (spec started at requirements/http/request) without the core class having to know about every use case up front. Explores: SDK integration patterns (subclass vs compose), custom header helpers (whether developers can register their own `.my_header` accessors or whether the pattern is fixed to what the engine ships), body serialization plug-ins, response auto-parsing based on content-type, send-time / receive-time interceptors, request signing schemes that need whole-request access (AWS SigV4), retry / timeout / cancel, and the cross-cutting question of how much lives in `core:http/*` versus downloadable classes in the ecosystem. Deliberately open-ended — spitballing, not spec.",
	"status": "brainstorm — unfiltered ideas; nothing committed",
	"context": "prompted after speccing core:http/request's headers surface and header-helper pattern. The core class is deliberately small and un-nannied; question is where the natural extension points are for the ecosystem."
}}
~~~

## What "extensibility" means here

The [`core:http/request`](https://puck.uno/requirements/http/request) spec is deliberately small: URL, headers (with a few helpers), body TBD, response TBD, send trigger TBD. That footprint leaves a lot of ground uncovered — SDK-specific auth schemes, custom serializers, retry policies, streaming, observability. This page collects unpressured ideas about which of those belong IN the class, which live in downloadable classes above it, and what extension points the core class should expose to make the ecosystem's code fit cleanly.

## Suggestions

### Custom header helpers

Current spec ships a few named helpers (`.accept`, `.content_type`, TBD). What if a developer wants `$request.my_org_signature <+ ...` because their SDK uses a specific idiom?

Three shapes:

- **Fixed helper set.** Only helpers the engine ships. Custom headers go through `.headers[NAME] = ...`. Simple, honest, no plugin API. Downside: SDK code looks visually inconsistent — `.my_org_sig` uses `.headers[...]` while a sibling `.accept` uses the sugar accessor.
- **Register-a-helper.** SDKs declare their own helpers via a class-body DSL when they subclass or wrap the request class. Ergonomic; needs a helper-registration API surface on the core.
- **Helper protocol.** Any object that implements `<+` and a "what wire form" query can be dropped into `.headers[NAME]`. Then `.accept` isn't a special-case — it's an instance of a general pattern any developer can implement. Cleanest but heaviest design lift.

The tension: no-nanny says let developers do what they want; small-surface says don't add plugin machinery without proven need. Where's the balance?

### Body serialization

`.body = ...` — what does the class accept, and does it help with serialization?

Options:

- **Bare `.body`, developer serializes.** Simple: `.body = %json.encode(obj)`. Developer sets Content-Type themselves.
- **Body helpers.** `.body_json = obj`, `.body_form = {...}`, `.body_multipart = {file: $f, ...}` — each sets `.body` AND the appropriate Content-Type. Ergonomic for common cases.
- **`.body = obj` with type dispatch.** Hash → JSON, string → raw, etc. Too magic; probably skip.

Streaming body (chunked transfer, large file upload): iterator? Stream object? Callback? Each has ergonomic trade-offs.

### Response object

Not spec'd yet. Two mental models:

- **Blocking send returns a response object.** `$response = $request.send`. Has `.status`, `.headers`, `.body`, `.body_json`, `.body_yaml`, etc.
- **Streaming interface.** `$request.send do |chunk| ... end` yields chunks. Or `.send` returns an iterator.

Auto-parsing based on Content-Type: does `.body_json` on the response parse on read, or is that always the developer's job? If we auto-parse, malformed input raises (per the fail-loud rule).

### Interceptors / middleware

Hooks into the request lifecycle:

- **Before-send** — mutate the request before it goes out (add default headers, sign, add tracing).
- **After-receive** — inspect / mutate the response before returning to the caller.
- **On-error** — retry, circuit breaker, fallback.

Shapes:

- **Middleware chain.** Register interceptors in order; each wraps the next. Familiar from Rack, Express, Django, etc. Flexible but adds mental overhead ("what's actually running here?").
- **Class-based hooks.** Subclass the request and override `before_send` / `after_receive`. Requires subclassing.
- **Event callbacks.** Attach a callable to a named event; multiple callbacks per event.

Would the core class carry the middleware machinery, or does the ecosystem invent it above? Depends on whether the interceptor pattern is common enough to warrant baking it in.

### Request signing beyond `core:auth/api`

[`core:auth/api`](https://puck.uno/requirements/protected/auth/api) handles the "credential template in a header" pattern — Bearer tokens, API-key-in-header, simple HMAC over a fixed string. Other schemes need more:

- **AWS SigV4** signs method, URL, headers, and body together — needs whole-request visibility at signing time.
- **HTTP Signatures (RFC 9421)** — configurable component set, similar full-request access.
- **OAuth 1.0 signature** — parameter-based, needs URL and body.

The pattern is "a signer that runs just before send and adds headers." Options:

- **Signer slot on the request.** `$request.signer = $sig_obj`. `core:auth/api` is one kind of signer; SigV4 is another. Send-time invokes `$signer.sign($request)` before transmission.
- **Sibling `core:auth/*` classes.** `core:auth/sigv4`, `core:auth/http_signatures`, each with its own send-time integration.
- **Middleware.** Signer is just a before-send interceptor.

The signer-slot option feels cleanest — it makes the "one signer per request" invariant structural rather than convention.

### Retry, timeout, cancel

Standard HTTP concerns:

- Connection timeout, read timeout, total timeout
- Retry policy: max attempts, backoff strategy, retriable status codes / errors
- Cancellation from caller or timeout

Fields on the request (`.timeout = 30`, `.retries = 3`)? Separate policy object passed to `.send()`? Middleware? Probably fields for simple cases, middleware or a policy object for complex ones — but the split is a real design choice.

### SDK integration patterns

Two shapes for wrapping the request in SDK code:

- **Subclass.** `class StripeRequest < core:http/request; ... end`. SDK gets to add methods, override behavior, register custom helpers. Requires the ecosystem to know how to inherit from core classes cleanly.
- **Compose.** SDK holds a `core:http/request` internally and exposes its own methods. Request stays a well-defined dependency, not part of the SDK's public class shape.

Caspian's [class inheritance](https://puck.uno/requirements/classes/inheritance) supports either. Which pattern the ecosystem gravitates toward depends partly on what extension points the core exposes — if custom helpers require subclassing, that pushes toward subclass; if they don't, compose is often cleaner.

### Cross-cutting: how much lives in `core:http/*` vs the ecosystem?

The consistent tension: every extension point added to the core class is one more thing to maintain and one more thing that can go wrong. The alternative — "the ecosystem writes wrapper classes for its needs" — keeps the core simple but risks ten different `MyOrgRequest` patterns with subtly different shapes.

`core:http/request` is a base primitive. Everything above (auth flavors, signing schemes, response parsers, retry policies, observability) COULD live in downloadable classes reached via `%(URL).new`. That matches Caspian's "libraries are cached, not installed" model — SDKs are just downloadable classes that wrap or subclass the core.

Worth asking early: what fraction of these ideas should sit in `core:http/*` versus live as separate classes downloaded on demand? "Nothing until it earns its way in" is a defensible starting point.

## Helper helper

Promoted to requirements. See [`caspian.uno/helpers.casp`](tag:helpers) for the full spec — inheritance-based `.helpers` slot, name-collision rule, hash-like interface, delete-then-set rotation, isolation from parent guts, and duck-typed convention model.

Open questions still on the table (not yet addressed in the spec):

- **Serialization.** How do helpers interact with CVM snapshots? Re-instantiated on revival, or preserved with their internal state? What if the helper's class URL isn't reachable at revival time?
- **Standard hook names.** Should there be a `caspian.uno/` convention for common hook names (`.set_header`, `.format_body`, `.on_snapshot`, `.render`), or does each parent class name its own without shared conventions?

## Request helpers

Concrete helpers that plug into `core:http/request` via the [helpers](tag:helpers) pattern. This section covers both the shared base classes that most single-header helpers inherit from and the individual concrete helpers.

**Inheritance is convenience, not requirement.** The base classes below (`helper.casp`, `header.casp`, `array.casp`, `hash.casp`) codify common shapes for single-header helpers. Ad-hoc classes that just implement the convention methods the request scans for (`.set_header`, `.format_body`, etc.) work fine without inheriting from any of them — the framework is duck-typed. Multi-header helpers, one-off helpers, or helpers with a completely different internal structure are all allowed; they just have to speak the same convention. The current `(name, value)` return shape from `.set_header` only fits single-header helpers; a multi-header helper would need either an array return or a different convention method — TBD if/when someone builds one.

### `caspian.uno/http/request/helper.casp` (general helper base)

The general base for any helper — not just HTTP header helpers. Provides just the parent-reference machinery; helpers that need HTTP-header-specific behavior inherit from `header.casp` (which itself inherits from `helper.casp`).

Provides:

- **`%bucket['request']`** — the parent request reference, stashed by the constructor. Accessible from the helper's methods (typically as `@request` in Caspian shorthand). The constructor signature is `.new($request)`; when a helper is added via the framework's `.helpers.add(name, class)`, the framework passes `%self` (the parent) as this argument.

That's the whole base. Any helper that inherits gets the standard "here's the parent I'm attached to" surface for free. Context-free helpers (per the [Helpers don't have to know their parent](#helpers-dont-have-to-know-their-parent) rule) don't need to inherit at all.

### `caspian.uno/http/request/header.casp` (HTTP-header helper base)

Inherits from `helper.casp`. The base for HTTP-header-specific helpers — those that produce exactly one outgoing HTTP header. Handles the standard machinery so subclasses only need to implement value formatting.

Provides:

- **`header_name`** — class-level attribute. The name of the HTTP header this helper produces (`'Accept'`, `'Cookie'`, `'Content-Type'`, etc.). Set by the subclass at class-init.
- **`unique` flag** — class-level attribute. Whether the header this helper produces must be unique on the request. Default `true` (most HTTP request headers are singleton). Subclasses override to `false` for the rare case of legitimate duplication.
- **`.percent_encode` getter/setter** — per-instance flag as shared vocabulary. Default `false`; concrete helpers override the default in their class-init if they want it on. What the flag DOES is per-subclass — the base provides the slot; each subclass decides how to interpret it (or ignore it entirely).
- **`unique_header(name)` method** — the mechanism that enforces uniqueness. Walks the parent request's `.headers`, `.auth_headers`, and other registered helpers to see if `name` is already claimed; raises if it is. The helper's own contribution is excluded from the check.
- **`set_header()` framework method** — orchestrates the standard flow:
	1. Call the subclass's `stringify_current()` hook to get the current value.
	2. If the hook returned null (nothing to contribute), return without emitting.
	3. If `unique = true`, call `unique_header(header_name)` — raises on collision.
	4. Return `(header_name, value)` to the request for emission.

Subclasses implement `stringify_current()` to turn their internal state into the wire string. The base handles orchestration.

The `unique` flag is declarative ("this header is a singleton"); the `unique_header` method is the mechanism that enforces it. Both are exposed — the flag is the ergonomic path (framework calls the method automatically); the method is the escape hatch for custom checks (a subclass that wants to check a different header name conditionally, for example).

### `caspian.uno/http/request/array.casp` (list-shaped header)

Inherits from `header.casp` and [`core:array`](https://puck.uno/requirements/built-in-classes/primitives/array/) via multiple inheritance. For headers whose value is a list of items joined by a separator — Accept, Accept-Language, Accept-Encoding, Cache-Control, etc.

Provides on top of `header.casp`:

- **All of `core:array`** — `<+`, `.length`, `.each`, indexed access, `.remove`, `.clear`, etc.
- **`separator`** — class-level attribute. Character(s) that join list items into the wire value. Default `,` (comma; most `#`-list HTTP request headers idiomatically comma-join).
- **`stringify_current()`** — implements the base class hook. Joins the underlying array's contents with `separator`. If the array is untouched, returns null. If touched-but-empty, raises (unless `.empty_ok = true`).
- **`.empty_ok` getter/setter** — opt-out for the touched-but-empty raise. Default `false`. Rare but sometimes legitimate (e.g. empty Accept semantically means "no representation is acceptable").

Concrete subclasses declare `header_name`, optionally override `separator` and the default for `.percent_encode`. Everything else is inherited.

### `caspian.uno/http/request/hash.casp` (hash-shaped header)

Inherits from `header.casp` and [`core:hash`](https://puck.uno/requirements/built-in-classes/primitives/hash/) via multiple inheritance. For headers whose value is a set of name=value pairs joined by a separator — Cookie is the canonical example.

Provides on top of `header.casp`:

- **All of `core:hash`** — `[]=`, `[]`, `.delete`, `.keys`, `.each`, `.length`, etc.
- **`pair_separator`** — class-level attribute. Character(s) between key and value inside each pair. Default `=`.
- **`element_separator`** — class-level attribute. Character(s) between pairs. Default `; `.
- **`stringify_current()`** — implements the base class hook. Joins each key/value pair with `pair_separator`, then joins the pairs with `element_separator`. If the hash is untouched, returns null. If touched-but-empty, raises (unless `.empty_ok = true`).
- **`.empty_ok` getter/setter** — same opt-out as `array.casp`.

Base value handling assumes string-valued pairs (`.hash[name] = 'value'`). Subclasses can override for structured values — Cookie handles hash-valued entries by JSON-encoding them when `.percent_encode = true`.

### `caspian.uno/http/accept.casp`

The Accept helper. Inherits from `caspian.uno/http/request/array.casp`. Class-init declares:

- `header_name = 'Accept'`
- `unique = true` (inherited default)
- `separator = ', '` (comma-space, for readability; overrides bare `,` default)
- `.percent_encode = false` (inherited default; percent-encoding media types would produce `text%2Fhtml`, invalid Accept syntax)

Usage:

~~~caspian
$request.helpers.add 'accept', %('caspian.uno/http/accept.casp')

$request.accept <+ 'text/html'
$request.accept <+ 'text/svg'
~~~

Wire form:

~~~
Accept: text/html, text/svg
~~~

Everything else — storage, `<+` append, `.length`, `.each`, uniqueness check via the framework's automatic `unique_header('Accept')` call, empty-behavior (untouched → no header, touched-but-empty → raise, `.empty_ok = true` opt-out) — inherits from `array.casp` / `header.casp` / `helper.casp`.

Note on empty Accept: an empty Accept semantically means "no representation is acceptable" (server would 406 Not Acceptable). Almost never intended; the touched-but-empty raise catches the common bug where the developer expected empty = no header. `.empty_ok = true` opts in to the semantically-loaded state.

### `caspian.uno/http/cookie.casp`

The Cookie helper — for the outbound `Cookie` request header (client → server; the cookies the client has stored for this origin, sent back on each request). Not `Set-Cookie` (response header, out of scope; response-side parsing lives on the response object, spec'd separately).

Inherits from `caspian.uno/http/request/hash.casp`. Class-init declares:

- `header_name = 'Cookie'`
- `unique = true` (inherited default; RFC 6265 § 5.4 explicitly requires exactly one Cookie header per request)
- `pair_separator = '='` (inherited default)
- `element_separator = '; '` (inherited default)
- `.percent_encode = true` (overrides `header.casp` default of `false` — cookie values need encoding often enough that it's the sensible default)

Usage:

~~~caspian
$request.helpers.add 'cookie', %('caspian.uno/http/cookie.casp')

$request.cookie['session_id'] = 'abc123'
$request.cookie['user_pref'] = 'dark'
~~~

Wire form:

~~~
Cookie: session_id=abc123; user_pref=dark
~~~

**Set-time validation on names.** Cookie names must match HTTP `tchar` (same rule as HTTP header names, per RFC 9110). Violations raise at the `.cookie[name] = value` call, naming the offending byte and position.

**Value handling depends on `.percent_encode`.** Cookie overrides `hash.casp`'s base string-value handling to add per-value encoding logic:

- **`percent_encode = true` (default), string value:** any bytes outside `cookie-octet` (whitespace, `"`, `,`, `;`, `\`) get percent-encoded before assembling. `;` becomes `%3B`, `,` becomes `%2C`, etc.
- **`percent_encode = true` (default), hash value:** the helper serializes the hash to JSON, then percent-encodes the entire JSON string. Example:

	~~~caspian
	$request.cookie['session'] = {'id': 'x', 'pw': 'y;z'}
	~~~

	produces on the wire:

	~~~
	Cookie: session=%7B%22id%22%3A%22x%22%2C%22pw%22%3A%22y%3Bz%22%7D
	~~~

	which is the percent-encoded form of the JSON `{"id":"x","pw":"y;z"}`. The receiver reverses (percent-decode, then JSON-parse) to recover the hash. It's the receiver's responsibility to know a given cookie is JSON — the helper commits both sides to the same envelope, but the server has to hold up its end.
- **`percent_encode = false`, no encoding, no nanny:**
	- **String values** sent raw. If a value contains `;`, `,`, `"`, or `\`, that goes on the wire as-is — the resulting cookie is malformed by RFC 6265 and servers handle it inconsistently. Developer opted out; they figure out why the request breaks.
	- **Hash values** JSON-encoded but not percent-encoded. Since JSON structure uses `"` and `,` (both cookie-octet violations), the result is invariably malformed. If you want a hash-shaped cookie, leave `.percent_encode = true`.
	- The general HTTP-sanity check on `.headers` (VCHAR + SP + HTAB, reject CR / LF / NUL) still applies at composition time, so injection-vector bytes are still caught even with `.percent_encode = false`. Cookie-syntax violations are on the developer; header-injection attacks aren't.

**Values that can't be JSON-encoded** (function objects, unsupported types) raise at the set call regardless of `.percent_encode`.

**Empty behavior** — inherited from `hash.casp`. Untouched → no header, no error. Touched-but-empty → raises. `.empty_ok = true` opts in to sending an empty `Cookie:` header.

#### Cookie header vs Set-Cookie header

Because it's a common source of confusion, quick contrast:

| Header | Direction | Multiplicity on the wire | Format |
|---|---|---|---|
| `Cookie` (this helper) | Client → server | Exactly one header per request (RFC 6265 § 5.4) | `name1=value1; name2=value2` — semicolon-space separated pairs |
| `Set-Cookie` (response side) | Server → client | Multiple headers allowed, one per cookie being set | `name=value; Domain=...; Path=...; Expires=...; Max-Age=...; Secure; HttpOnly; SameSite=...` — pairs plus attributes |

Only `Cookie` (outbound) is this helper's concern. Set-Cookie parsing on incoming responses belongs to the response object.

### `caspian.uno/http/accept_language.casp`

Same shape as [Accept](#caspianunohttpacceptcasp). Inherits `array.casp`. Class-init declares:

- `header_name = 'Accept-Language'`
- `separator = ', '` (comma-space, matching Accept)
- Other defaults inherited (`unique = true`, `.percent_encode = false`).

Usage:

~~~caspian
$request.helpers.add 'accept_language', %('caspian.uno/http/accept_language.casp')

$request.accept_language <+ 'en-US'
$request.accept_language <+ 'en;q=0.9'
$request.accept_language <+ 'fr;q=0.5'
~~~

Wire form:

~~~
Accept-Language: en-US, en;q=0.9, fr;q=0.5
~~~

Values use standard HTTP quality-value (`q=...`) syntax when the developer wants preference ordering (see the Accept helper for the same pattern). The helper doesn't parse — comma-joined output only.

### `caspian.uno/http/accept_encoding.casp`

Same shape as Accept. Inherits `array.casp`. Class-init declares:

- `header_name = 'Accept-Encoding'`
- `separator = ', '` (comma-space)
- Other defaults inherited.

Usage:

~~~caspian
$request.helpers.add 'accept_encoding', %('caspian.uno/http/accept_encoding.casp')

$request.accept_encoding <+ 'gzip'
$request.accept_encoding <+ 'deflate'
$request.accept_encoding <+ 'br;q=0.9'
~~~

Wire form:

~~~
Accept-Encoding: gzip, deflate, br;q=0.9
~~~

Same q-value syntax available for preference ordering.

### `caspian.uno/http/cache_control.casp`

Same shape as Accept. Inherits `array.casp`. Class-init declares:

- `header_name = 'Cache-Control'`
- `separator = ', '` (comma-space)
- Other defaults inherited.

Usage:

~~~caspian
$request.helpers.add 'cache_control', %('caspian.uno/http/cache_control.casp')

$request.cache_control <+ 'no-cache'
$request.cache_control <+ 'max-age=0'
~~~

Wire form:

~~~
Cache-Control: no-cache, max-age=0
~~~

Directive strings can be bare tokens (`no-cache`, `no-store`) or token=value pairs (`max-age=0`, `max-stale=60`). The helper doesn't parse — comma-joined output only. Note that Cache-Control also appears on responses with its own directive vocabulary (`public`, `private`, `s-maxage`, `must-revalidate`, `immutable`, etc.); those belong on the response object, not this helper.

### Under consideration

Candidates discussed but not spec'd here. Each either graduates to a concrete helper subsection above, or moves to another spec entirely.

**Handled as built-in fields on `core:http/request`** (not helpers — simple singleton getter/setters that fit more naturally as direct fields on the request class):

- **`.host`** — auto-derived from URL by default, overridable for testing or proxying.
- **`.content_type`** — string setter/getter.
- **`.user_agent`** — string setter/getter with a Caspian default value (something like `Caspian/<version>`).

Spec'd on the [request page](https://puck.uno/requirements/http/request).

**Deferred to post-V1 (may land in core later, or in community-authored classes):**

- **`.body_json` / `.body_form`** — body + Content-Type coordinators. Complex enough to defer; someone can build them as separate helper classes or as body-handling extensions.
- **`.if_match` / `.if_none_match`** — ETag-based conditional requests. Useful when servers publish ETags but many APIs don't; deferred.

**Not on the list (out of scope):**

- **Range** — niche.
- **Referer, Origin** — usually auto-set by the transport or omitted.
- **If-Modified-Since / If-Unmodified-Since** — date-format complexity; wait for the date-library story to firm up.
- **Authorization** — via [`core:auth/api`](https://puck.uno/requirements/protected/auth/api), not a plain request helper.

## What's not on this page

Consciously left out of this brainstorm — belongs in related pages or later:

- Cookie jars, session management (probably its own topic once we spec a client).
- HTTP/2 or HTTP/3 semantics (multiplexing, push, priorities) — big design, separate page.
- WebSocket upgrade path — different protocol; probably lives at `core:net/websocket` or similar.
- Server-Sent Events — a streaming-response shape but with its own semantics.
- Observability contracts (tracing headers, metric emission) — likely a middleware / interceptor concern once that's decided.

## Related

- [`core:http/request`](https://puck.uno/requirements/http/request) — the base class this page brainstorms extensions for.
- [`core:auth/api`](https://puck.uno/requirements/protected/auth/api) — the first "extension" of the request pattern (auth-scoped `.auth_headers` slot and send-time credential composition).
- [class inheritance](https://puck.uno/requirements/classes/inheritance) — the mechanism SDKs would use to subclass the request if that's the pattern.
