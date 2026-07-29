# `core:http/request`

<span class="tag">http-request</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_http_request",
	"role": "spec for `core:http/request` — Caspian's outbound HTTP request class. Early sketch, not a full spec. Currently captures: the two construction paths (unauthenticated via a `%net`-style constructor TBD, authenticated via `$auth.request(url)`), the `.headers` slot with string-or-array value polymorphism (single string = one header line, array = N separate header lines, no auto-comma-joining), element-wise HTTP-sanity validation, cross-slot uniqueness with `.auth_headers` (only present on auth-produced requests), the un-nannied posture on `.headers[...]` (byte-set + collision only; everything else on the developer), and the header-helper pattern with `.accept` as the first example (array-accumulator via `<+`, OWNS its internal array — NOT a view on `.headers['Accept']`, produces the header's idiomatic comma-joined single-line wire form at send time, empty-at-send raises). Header helpers are subject to a cross-source collision rule with `.headers` and `.auth_headers` (each output header name can be populated by at most one source). Full API surface (method, body, response object, timeouts, redirects, cookies, streaming, multipart, retry policy) and the full list of header helpers are deliberately left for future passes. Naming: `core:http/*` reserves the HTTP-specific namespace; lower-level network primitives (sockets, DNS) belong under `core:net/*` if/when they graduate to first-class classes.",
	"status": "sketch — construction paths, `.headers` value shape, un-nannied posture, and the `.accept` helper pattern settled; full API and remaining helpers pending",
	"audience": "Caspian developers making outbound HTTP requests; anyone tracking the request surface as it firms up"
}}
~~~

`core:http/request` is Caspian's outbound HTTP request class. **This page is an early sketch** — the pieces we've committed to so far, with most of the API left to future passes. The [What's not spec'd yet](#whats-not-specd-yet) section names what's missing.

## Getting a request

Two construction paths:

- **Plain unauthenticated request** — some `%net`-style constructor TBD (`%net.request(url)`? `%chain.net.request(url)`? See [Related](#related)). Returns a request pre-configured with the URL and no auth attached. <!-- STALE: %chain.X syntax being reworked -->
- **Authenticated request** — [`$auth.request(url)`](tag:auth-api) where `$auth` is a [`core:auth/api`](tag:auth-api) instance. Returns a request pre-configured with the URL AND the auth's policy — allowed-domains validation on the URL, an `.auth_headers` slot for credential-carrying header templates, allowed-headers scope check on that slot.

Both paths return the same class. An authenticated request just carries a reference to `$auth` and adds the `.auth_headers` slot on top; everything else is the same shape.

## Headers

The `.headers` slot holds regular (non-auth) HTTP headers.

**Un-nannied within the rules.** Direct `.headers[...]` setting is minimally-checked beyond the [non-negotiable HTTP rules](#non-negotiable-http-rules) below — the developer is responsible for writing well-formed HTTP. Cross-slot uniqueness against `.auth_headers` still runs. A small set of specific header-shape exceptions where the system enforces more will be documented as they're spec'd (Cookie's semicolon-vs-multi-line requirement, etc.). Everything else is trusted.

Values are strings or arrays of strings:

~~~caspian
$request.headers['Content-Type'] = 'application/json'
$request.headers['Accept'] = 'text/html, application/json'
$request.headers['X-Custom'] = ['a', 'b']
~~~

- **String value** — one header line on the wire.
- **Array value** — one header line per element. On the wire, `['a', 'b']` produces two separate `X-Custom: a` / `X-Custom: b` lines, not comma-joined. This is safer as a default than auto-joining (works for every header, no per-header knowledge required, and Set-Cookie-shaped exceptions can't be silently corrupted).
- **Empty array raises.** `.headers[key] = []` raises at set time. If a non-empty array is later mutated to empty (e.g., all values removed after being pushed via a helper), send-time composition raises with the same message. Almost always a bug — to remove a header use `.delete(key)`.
- **HTTP-sanity validation applies element-wise** — each string (whether alone or in an array) is checked against the same byte-set rule as [`core:protected/hash/http`](tag:protected-hash-http): keys must be in the `tchar` set, values must be VCHAR (0x21-0x7E) + SP (0x20) + HTAB (0x09). CR / LF / NUL / obs-text raise with a specific error naming the offending byte and position. Validation, not sanitization — bad bytes raise, they're never silently stripped or escaped.
- **Cross-slot uniqueness** — a header key in `.headers` cannot also appear in `.auth_headers` (the auth-scoped slot, only present on auth-produced requests). Bidirectional and case-insensitive. Value shape is irrelevant to the collision check — it's key-based. See [`core:auth/api` § No cross-slot duplicates](tag:auth-api).

### Idiomatic comma-joining vs multi-line

Most multi-value HTTP request headers idiomatically comma-join into a single line — `Accept`, `Accept-Language`, `Accept-Encoding`, `Cache-Control`, `Via`, and other combining-safe fields (RFC 9110 § 5.3 / § 5.6.1). For those, pass a comma-joined string:

~~~caspian
$request.headers['Accept'] = 'text/html, application/json'
~~~

Pass an array only when you specifically want N separate lines on the wire, or when the header type doesn't safely comma-join. Caspian doesn't auto-join — no nanny code, no per-header knowledge; the developer picks the wire form they want.

Exception worth naming: **Cookie** must be sent as one header with `;` separator (`Cookie: a=1; b=2`) per RFC 6265, not as multiple `Cookie:` lines. Use a single string with semicolons; an array of cookies would produce non-compliant output.

## Header helpers

For headers developers set frequently, `.headers[...]` is awkward — especially for headers whose value is an incrementally-built list. `core:http/request` grows a handful of helper accessors that build up an internal representation and produce the header's idiomatic wire form at send time.

Helpers own their internal storage — they are **not** views on `.headers[NAME]`. Both surfaces produce the same output header name, so setting a header both ways raises the cross-slot uniqueness rule: `.accept` populated AND `.headers['Accept']` set = collision, raise. See [Cross-source collision](#cross-source-collision) below.

### `.accept`

An accumulator for the `Accept` header. Use [`<+`](https://puck.uno/requirements/syntax/operators#-append) to append a media type:

~~~caspian
$request.accept <+ 'text/html'
$request.accept <+ 'text/plain'
~~~

- **Auto-created on first use.** The first `<+` creates the underlying array; subsequent appends grow it. Before any use, no Accept header goes out (unless `.headers['Accept']` was set directly).
- **Internal storage.** The array is owned by the helper, separate from `.headers`. Reading `$request.headers['Accept']` after `.accept <+ 'text/html'` returns the "not set" state; the value lives inside `.accept`, not in `.headers`.
- **After the first use, it's just an array.** The full [Array](https://puck.uno/requirements/built-in-classes/primitives/array/) API works on the underlying storage — `.length`, `.remove`, `<+`, indexed access, `.each`, etc.
- **Wire form: one comma-joined line.** At send time, the array becomes a single `Accept: text/html, text/plain` header — the idiomatic form for Accept per RFC 9110 § 5.6.1 (Accept is defined with `#` in ABNF, i.e., a comma-separated list). If a developer specifically wants multiple `Accept:` lines instead, they set `.headers['Accept'] = ['a', 'b']` directly (and don't use `.accept`).
- **Empty at send time raises.** If the array was created (via any `.accept` use) and is empty at send time — e.g., all values were removed after being pushed — send-time composition raises with `` .accept was populated then emptied; use nothing (never touch .accept) if you don't want the header, or provide at least one media type ``.
- **Collision with `.headers['Accept']` raises.** If both `.accept` is populated and `.headers['Accept']` is set, the second write raises. See below.

### Cross-source collision

The cross-slot uniqueness rule ([`core:auth/api` § No cross-slot duplicates](tag:auth-api)) extends to header helpers. Each output header name can be populated by exactly one source. The sources are:

- `.headers[NAME]`
- `.auth_headers[NAME]` (auth-produced requests only)
- Any helper that produces `NAME` at send time (`.accept` → `Accept`, `.content_type` → `Content-Type`, etc.)

Populating the same header from two sources raises at the second write with a message naming both sources: `` header `Accept` is already populated via .accept; can't also set .headers['Accept'] ``. Bidirectional, case-insensitive.

Overwrite within a single source is fine — `.accept <+ 'a'` then `.accept <+ 'b'` grows the same array; `.headers['Accept'] = 'a'` then `.headers['Accept'] = 'b'` overwrites in place. Only cross-source is a collision.

### Other helpers to come

The same pattern will grow for other frequently-set headers as they're needed. Sketch of the shape:

- `.accept_language <+ 'en-us'` — array accumulator, comma-joined wire form (like `.accept`).
- `.cache_control <+ 'no-cache'` — array accumulator, comma-joined wire form.
- `.content_type = 'application/json'` — singleton; simple `=` assignment.
- `.host = 'example.com'` — singleton.
- `.user_agent = 'MyApp/1.0'` — singleton.

Full list and exact shapes TBD. The pattern:

- **Array-accumulator helpers** use `<+` to append, produce the header's idiomatic multi-value wire form (comma-joined for Accept-shaped headers; the helper knows its specific header's rule), and raise on empty-at-send.
- **Singleton helpers** use `=` to assign, produce a single header line at send time.

Every helper is subject to the cross-source collision rule against `.headers[NAME]` and `.auth_headers[NAME]`.

## Built-in header fields

Some common headers are exposed as direct fields on the request class rather than requiring the helper machinery. Always present, no `.helpers.add` needed.

- **`.host`** — the target host. Auto-derived from the URL passed to `.request()` by default; overridable for testing or proxying.
- **`.content_type`** — string setter/getter. Common with POST/PUT bodies. `.content_type = 'application/json'`.
- **`.user_agent`** — string setter/getter with a Caspian default value (something like `Caspian/<version>`). Every request sends one unless explicitly cleared.

~~~caspian
$request.content_type = 'application/json'
$request.user_agent = 'MyApp/1.0'
~~~

- **Same cross-source uniqueness rule applies.** If `.headers['Host']` (or a helper) also produces the same header, the second write raises.
- **[Non-negotiable HTTP rules](#non-negotiable-http-rules) apply.** Names must be `tchar`, values must be HTTP-sanitary. No escape hatch.
- **Setting a field to `null` clears it.** No header goes out for that field (except `.user_agent`, where clearing removes the default and no User-Agent header goes out at all).

These are direct fields rather than helpers because they're simple singleton getter/setters where the helper machinery (registration, cross-source coordination, base-class inheritance) would be overkill. Header helpers make sense for structured accumulation (Accept-family, Cookie); direct fields make sense for "just set this string."

## Non-negotiable HTTP rules

Independent of any per-source setting or opt-out, these rules ALWAYS apply to every header that reaches the wire. No flag disables them, no `.percent_encode = false` bypasses them, no direct `.headers[...]` assignment slips past them, no helper output escapes them. Every source — `.headers`, `.auth_headers`, `.helpers`, built-in fields — is validated at the earliest layer that can see the bytes; anything that reaches the transport layer unchecked is caught there as a final backstop.

- **Header names** must match HTTP `tchar` (RFC 9110): ASCII letters, digits, and the fifteen specials `!` `#` `$` `%` `&` `'` `*` `+` `-` `.` `^` `_` `` ` `` `|` `~`. No whitespace, colon, control bytes, or high-bit bytes.
- **Header values** must be HTTP-sanitary: VCHAR (0x21–0x7E) + SP (0x20) + HTAB (0x09). No CR, LF, NUL, other C0 controls, DEL, or high-bit bytes.

Violations raise a specific error naming the offending byte and its position. **There is no escape hatch.** These aren't stylistic preferences — CR and LF are HTTP header injection vectors, NUL corrupts wire framing, and non-tchar name bytes produce malformed headers that servers handle inconsistently. Enforcing them is the system's floor, not paternalism the developer can opt out of.

The [un-nannied posture](#headers) in the Headers section covers cases where developers have legitimate reasons to bend HTTP conventions — a custom header with `,` in its value, a non-standard directive, a value the RFC would frown on but the server accepts. It does NOT cover cases where bending the rules produces malformed or hostile output. Those are non-negotiable.

## Send-time behavior

When the request fires, the transport composes and sends the HTTP request over TLS via luasocket + luasec + OpenSSL. Regular headers (from `.headers`) are ordinary Lua strings on the way to the socket. Auth headers (from `.auth_headers`, on auth-produced requests only) go through a purpose-built C binding that composes credentials from protected memory without them ever appearing as a Lua string. See [`core:auth/api` § Send-time composition](tag:auth-api).

## What's not spec'd yet

Deliberately deferred to future passes:

- **Method** (GET / POST / PUT / DELETE / PATCH / HEAD / OPTIONS) — setter, defaults, verb-specific behavior.
- **Body** — string, bytes, streaming, JSON serialization helpers, multipart/form-data, urlencoded-form helpers.
- **Response object** — return shape from the send trigger. Status, headers, body accessors. Streaming responses. Error responses.
- **Send trigger** — `.send`? `.execute`? `.call`? Blocking vs non-blocking? Naming TBD.
- **Timeouts, redirects, retries** — connection timeout, read timeout, redirect-follow policy, retry policy.
- **Cookies** — cookie jar, per-request cookie overrides, `Set-Cookie` handling on responses.
- **TLS configuration** — cert pinning, self-signed cert acceptance for dev, ALPN, minimum TLS version.
- **Connection reuse** — pooling, keepalive, HTTP/2 multiplexing.
- **Progress callbacks** — upload / download byte counts for large bodies.
- **Interaction with `%chain.net`** — how the request class connects to the existing `%chain.net.fetch` short-form and `%chain.net.http_client` long-lived-client patterns. <!-- STALE: %chain.X syntax being reworked -->
- **Header-helper design details** — the helper machinery, base classes (`helper.casp` / `header.casp` / `array.casp` / `hash.casp`), and concrete helpers (`.accept`, `.cookie`, `.accept_language`, `.accept_encoding`, `.cache_control`) are being spitballed on [ideas/request-extensibility](https://puck.uno/ideas/request-extensibility) and will promote here when settled. The [Header helpers § .accept](#accept) sketch on this page is a first-pass placeholder for the pattern.
- **The `.headers` exception list** — where the un-nannied posture yields to enforcement (Cookie's semicolon-vs-multi-line, etc.).

## Related

- [`core:auth/api`](tag:auth-api) — the auth object that constructs authenticated requests via `$auth.request(url)`; adds the `.auth_headers` slot for credential templates and the send-time composition machinery that keeps plaintext credentials out of Lua-visible memory.
- [`core:protected/hash/http`](tag:protected-hash-http) — the byte-set rules (`tchar` for keys, VCHAR+SP+HTAB for values) that `.headers` validation references.
- `%chain.net` (`requirements/chain/methods/net.md`) — the chain-mediated networking surface where `.fetch`, `.http_client`, `.sockets`, and `.uds` currently live. Overlap with this class's construction path is unresolved. <!-- STALE: %chain.X syntax being reworked -->
