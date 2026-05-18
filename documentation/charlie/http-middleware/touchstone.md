# Touchstone

`kiera.uno/touchstone` — the **base HTTP server class** that Sinatra
and Robinson inherit from. Touchstone is **not directly instantiable
as a working server.** It holds the shared infrastructure both
descendants need (content-type factory defaults, Jasmine
integration, common HTTP plumbing) but doesn't itself decide *how*
to serve content. That decision is each descendant's job.

Named after the clown in Shakespeare's *As You Like It*; the common
noun also means "a standard of comparison or judgment" — fitting
for a base class.

---

<a id="status"></a>
## 1 Status

Spec in development. The shape fills in as Sinatra and Robinson
surface their requirements — Touchstone is where shared behavior
crystallizes once both descendants need the same thing.

---

<a id="responsibilities"></a>
## 2 Responsibilities

<a id="content-type-factory-defaults"></a>
### 2.1 Content-type factory defaults

Touchstone ships a factory map from common file extensions to
`Content-Type` values (`.css` → `text/css`, `.png` → `image/png`,
`.json` → `application/json`, and so on). Sinatra and Robinson
share this map when serving files; developers can override
per-server.

<a id="jasmine-integration"></a>
### 2.2 Jasmine integration

Touchstone wires up [Jasmine](../jasmine/jasmine.md) logging. The ambient
`%chain.log` mechanism, the nested call-frame trees, and the
configured stores all flow through Touchstone — its descendants
don't reimplement any of it.

<a id="other-shared-infrastructure"></a>
### 2.3 Other shared infrastructure

To be detailed as it crystallizes. Likely includes: TLS handling
(or lack thereof), connection management, request parsing,
response writing, error-page rendering scaffolding.

---

<a id="the-transaction-object"></a>
## 3 The transaction object

Every request creates a single `$transaction` object that
threads through every handler method in the chain. It exposes:

- **`$transaction.request`** — the request. **Immutable.**
  Handlers read it but cannot change it; cross-stage state goes
  in the handler's own bucket (see [The handler chain](#the-handler-chain)).
- **`$transaction.response`** — the response. **Starts at null** but
  **auto-creates on first write**: writes to `$response.csp`,
  `$response.headers`, `$response.status`, or `$response.body`
  instantiate an empty response object on the spot. This means a
  handler can configure CSP or headers (see
  [CSP](#content-security-policy-csp)) without an explicit
  construction step — the first write is the construction. If stage
  2 ends with `$transaction.response` still null (no handler wrote
  anything), the built-in 404 / 5xx fallback fires. Stage 3 handlers
  always see a non-null response.
- **`$transaction.session`** — the mutable session cookie
  handle. See [Sessions](#sessions).

The sections that follow describe each of these in detail, then
the handler chain that processes the transaction.

---

<a id="the-request-object"></a>
## 4 The request object

`$transaction.request` (or `$request` inside handler closures
where it's bound for brevity) exposes everything about the
incoming request through a few clearly-scoped accessors. The
request is **immutable** — built once at the start of the
transaction, frozen before any handler runs.

<a id="requeststeps"></a>
### 4.1 `$request.steps`

Hash of the request's path segments, keyed by **both** position
and (where applicable) nickname.

- **Positional keys** — `steps[1]`, `steps[2]`, etc. The path
  is always split into segments and exposed positionally, even
  if no pattern matched.
- **Nickname keys** — `steps['play']`, `steps['act']`, etc.
  When a path pattern with `{name}` placeholders matches the
  URL, those positions get nickname aliases pointing at the
  same segment values.

Both flavors are populated **before any handler runs.** Touchstone
matches the URL against the patterns registered by descendant
classes (Sinatra via `$server.get/.post/...`) at request-build
time and bakes both positional and nickname keys into
`$request.steps` before locking the request. By the time
handlers see `$transaction`, `steps` is complete and immutable.

Touchstone handles the standard `{name}` pattern syntax for
free; subclasses that register patterns get nickname support
automatically. Custom handlers that implement their own richer
matching (regex, content-type filters, etc.) can do that work
inside their `process` methods — they just don't share
Touchstone's nickname machinery automatically.

**Open: full selector engine in core?** It may turn out that
keeping the matching logic split across "Touchstone handles
nicknames" and "custom handlers can override" is more trouble
than it's worth. The alternative is to provide the entire
selector engine in Touchstone — one library, one matching
implementation — and let custom richer matching live entirely
outside the path-selector concept (handlers that aren't
selectors at all). Filed as a forward direction; not committed.

**Open: pattern-syntax scope.** Ruby Sinatra supports a rich
zoo of pattern features (regex routes, splats with various
semantics, optional segments, file-extension matching, etc.).
Some are already out of scope (regex). Others may be trimmed
further if the implementation cost in the matcher outweighs
their value at microservice scale. The committed minimum:
literal segments, single-segment `{name}` placeholders, and
named splat (`*name`). Anything beyond is contingent on cost.

<a id="requestparams-requestparam_array-requestparam_hash"></a>
### 4.2 `$request.params`, `$request.param_array`, `$request.param_hash`

These three are **computed on demand.** None of them is parsed
at request-build time — each is produced (and memoized) the
first time it's accessed. Handlers that don't read params pay
nothing for the parse; handlers that only read `param_hash`
don't pay for the form-field decode of `params`. The request
stays immutable; lazy fields are still part of the request's
frozen shape, they just defer their work until asked.

<a id="requestparams"></a>
#### 4.2.1 `$request.params`

A merged hash of **query string + form fields + uploaded files** —
the structured params, however the client sent them. Files come
out as file objects (parsed from multipart), not raw bytes. When
the same name appears in multiple sources, **later sources
overwrite earlier ones**.

```
$server.post('/upload/{user_id}') do($request)
    $title      = $request.params['title']       # form field
    $attachment = $request.params['attachment']  # file object
end
```

Path placeholders are *not* in `params` — they live on
`$request.steps`. The two are separate by design: path captures
are part of the route, params are everything else the client
submitted.

<a id="requestparam_array"></a>
#### 4.2.2 `$request.param_array`

Returns an **array of `[name, value]` pairs** preserving order
and duplicates. This is the answer to a longstanding weakness in
most HTTP parsers, which expose only one value when a client
sent multiple with the same name.

```
# URL: ?tag=red&tag=blue&tag=green
$request.params['tag']         # 'green' (last wins)
$request.param_array           # [['tag', 'red'], ['tag', 'blue'], ['tag', 'green']]
```

Use `params` for the common case; reach for `param_array` when
you actually need to see every submission in order.

<a id="requestparam_hash"></a>
#### 4.2.3 `$request.param_hash`

Returns the **parsed JSON object from the query string** when the
query string is valid JSON, per the
[JSON URL parameters convention](../../kiera/json-urls.md). Returns `null`
if the query isn't JSON (including the case where it's a
traditional `?key=value` form).

```
# URL: /map?{"nw":[40.7,-74.0],"se":[40.8,-73.9]}
$request.param_hash            # {'nw': [40.7, -74.0], 'se': [40.8, -73.9]}

# URL: /map?key=value&other=thing
$request.param_hash            # null  (not JSON; use $request.params)
```

Cheap: attempt `JSON.parse` on the raw query string; on success
return the result, on failure return null. This is how Kiera
services receive machine-generated URLs with structured
parameters, while traditional `?key=value` URLs from
non-Kiera-aware clients still work through `$request.params`.

<a id="requestbody"></a>
### 4.3 `$request.body`

The raw request body, **potentially huge.** Exposed as a
streaming handle rather than slurped into memory — the developer
decides how to consume it. Useful when you want unparsed bytes
(custom protocols, content types Touchstone doesn't parse, etc.).

**Touchstone never slurps huge bodies into memory.** Large
bodies are buffered through an **FSO** (filesystem object) as they
arrive — see [Body buffering](#body-buffering) below. An FSO is
any engine-configured object that can accept byte writes for
storage; in v1, that means a [dirjail](../built-in-classes/filesystem.md)
the deployer configures into the Touchstone instance. The
abstraction leaves room for non-filesystem backings (network
storage, etc.) in future revisions without changing the handler-side
contract.

---

<a id="sessions"></a>
## 5 Sessions

`$transaction.session` is a hash-like handle on the session
cookie. Reading and writing behaves like an ordinary Charlie
hash; on response build, Touchstone reserializes any changes and
emits a `Set-Cookie` header.

```
$user_id = $transaction.session['user_id']
$transaction.session['user_id'] = 42
$transaction.session['preferences'] = {theme: 'dark', lang: 'en'}
```

Session lives on `$transaction`, not `$request`, because
sessions are **mutable through the chain** — handlers add and
remove keys, the response gets the new cookie. The request
itself stays immutable; the session's mutable state belongs on
the transaction.

The session cookie's value is a JSON object. Touchstone parses
it on the way in, exposes it as `$transaction.session`, tracks
mutations, and reserializes on the way out.

**Configuration is required.** A server with no domain configured
will raise `kiera.uno/touchstone/error/sinatra/no_cookie_domain`
the first time a handler accesses `$transaction.session`. Cookies
without a domain are unsafe; Touchstone refuses to issue them.

```
$server = %['kiera.uno/sinatra'].new(domain: 'example.com')

# Optional: override the cookie name (defaults to 'session')
$server = %['kiera.uno/sinatra'].new(domain: 'example.com',
                                      cookie_name: 'sid')
```

**Default cookie attributes** (all overridable per server):

| Attribute | Default | Note |
|---|---|---|
| `HttpOnly` | `true` | JS in the page cannot read it — XSS can't steal the session |
| `Secure` | `true` | Transmitted only over HTTPS |
| `SameSite` | `Lax` | Blocks the most common CSRF vectors while allowing normal top-level navigation |
| `Path` | `/` | Standard cookie scope |

To override:

```
$server = %['kiera.uno/sinatra'].new(
    domain: 'example.com',
    cookie_secure: false,       # local dev over HTTP
    cookie_samesite: 'Strict',
    cookie_path: '/api')
```

**Clearing the session.** Setting the session to null deletes
the cookie:

```
$transaction.session = null    # emit a Set-Cookie that expires the cookie
```

Removing individual keys (e.g., `$transaction.session.delete('foo')`)
just mutates the hash; the cookie itself stays.

**Bad cookies are treated as empty sessions.** If the client
sends a cookie with the configured name but its value isn't valid
JSON, Touchstone starts the handler with an empty
`$transaction.session` and emits a warning via Jasmine. Garbage
cookies from non-Kiera-aware clients won't crash the server.

**No expiration by default.** The cookie is a session cookie in
the HTTP sense — no `Expires` or `Max-Age`, so it goes away when
the user agent closes. Persistent sessions across browser
restarts aren't a core feature; if you need them, set
`cookie_max_age: <seconds>` on server creation, or migrate to a
different add-on that handles richer session semantics.

---

<a id="body-buffering"></a>
## 6 Body buffering

Touchstone buffers incoming bodies; it does not stream-process
them. Two backing stores are available:

- **In memory.** Cheap and simple. Fine for small-to-medium
  bodies — typical image uploads are a few MB, which is pocket
  change to modern RAM. An image-processing service that
  receives, transforms, and returns an image without ever
  touching disk is a totally reasonable use case.
- **FSO (filesystem object).** Required for genuinely large
  bodies (videos, archives, multi-gigabyte uploads, etc.). When
  configured, Touchstone spills incoming bytes to the FSO as
  they arrive rather than holding them in RAM.

The deployer configures **a memory limit** for incoming bodies.
Below the limit, bodies are held in memory. Above the limit:

- **If an FSO is configured**, the body spills to FSO
  transparently. The handler sees the same `$request.body` /
  file-object surface either way; where the bytes physically
  live is an implementation detail.
- **If no FSO is configured**, the body is rejected and
  Touchstone raises
  `kiera.uno/touchstone/error/sinatra/cannot_store_files`. The
  exception carries the request's `Content-Length` and the
  configured memory limit so the caller can produce a useful
  diagnostic.

This gives three coherent deployment shapes:

- **Tight IPC microservice.** No FSO, low memory limit. Accepts
  small requests; rejects anything larger.
- **In-memory image / data processor.** No FSO, generous memory
  limit (say, 20 MB). Handles typical image uploads entirely in
  RAM without disk dependency. Perfect for stateless processing
  services.
- **Full deployment.** FSO configured. Accepts uploads of any
  size, with FSO spillover for large ones.

The deployer picks the shape; Touchstone adapts. No unsafe
fallback ("just keep buffering in RAM until OOM") — the memory
limit is the hard ceiling and the FSO is the explicit opt-in
for going past it.

**Possible future feature.** Exposing request headers and
first-few-params *before* the body has finished buffering — so
a handler can early-reject (4xx) an upload without waiting for
the full body to arrive. Useful for auth checks, content-length
limits, etc. Not in v1; flagged if demand surfaces.

---

<a id="the-handler-chain"></a>
## 7 The handler chain

Touchstone processes each request through an **ordered chain of
handlers** registered on `$server.handlers`. Handlers are Kiera
objects; each can implement up to three methods that participate
in different stages of the transaction. This is the plug-in
surface that lets add-ons add features — auth checks, CORS
headers, metrics, logging enrichment, request-ID injection, the
built-in CSRF guard, etc. — without those features needing to
live in core. Sinatra's path-selector registrations and
Robinson's filesystem-tree dispatch both build on this same
chain mechanism.

```
$server.handlers << %['foo.bar/cors'].new(allow_origin: '*')
$server.handlers << %['foo.bar/auth']
$server.handlers << %['foo.bar/metrics']
```

<a id="the-three-stages"></a>
### 7.1 The three stages

Touchstone walks `$server.handlers` three times per request:

1. **Stage 1 — `before($transaction)`.** Every handler's
   `before` method (if any) runs in registration order. Each
   handler can inspect the request, set up its own per-transaction
   state, validate, log, or raise a response-producing exception
   that short-circuits the rest of the chain.
2. **Stage 2 — `process($transaction)`.** Every handler's
   `process` method (if any) runs in registration order. A
   handler signals "I'm handling this" by returning a response
   object — that response becomes `$transaction.response` and
   stage 2 ends. A handler signals "pass to the next" by
   returning null (or returning at all without producing a
   response). There is no separate `decline()` call or special
   flag — null is the only decline signal. If no handler returns
   a response, the framework's catch-all (the descendant class's
   responsibility — Sinatra exposes it via `$server.run`)
   fires; if that doesn't return a response either, the built-in
   404 page is produced.
3. **Stage 3 — `after($transaction)`.** Every handler's `after`
   method (if any) runs in registration order. Each can inspect
   or modify `$transaction.response`, add headers, replace it
   entirely, or raise to produce a different response.

A handler can implement any subset of `{before, process, after}`.
The CSRF guard handler has both `before` (verify token) and
`after` (inject token into HTML). A CORS handler has just
`after` (add headers). A logging handler has `before` (start log
entry) and `after` (flush log entry). Sinatra's path selectors
have just `process`.

<a id="one-handler-class-one-dispatcher"></a>
### 7.2 One Handler class, one dispatcher

The implementation collapses to a single `Handler` base class
and a single dispatcher function:

- **`Handler`** is the common type. It has optional `before`,
  `process`, and `after` methods. Any may be missing.
- **The dispatcher** walks an array of Handlers through the
  three stages (before each, process each until first response,
  after each).

That's the entire dispatch machinery. Every Handler in the
chain — Sinatra path selectors, Robinson tree-pages, CSRF guard,
CORS, etc. — implements the same interface; the dispatcher
doesn't know or care which is which. A path selector that
declines a request is no different from a CORS Handler that has
no `process` method at all — both just don't contribute a
response, and the dispatcher moves on.

The substrate also supports nesting: a Handler's `process` could
itself call the dispatcher on a sub-array, giving sub-app
composition, handler trees, route groups, etc. v1 doesn't expose
that as a user-facing surface — there's just one flat
`$server.handlers` array — but the machinery is in place if
needed.

<a id="per-transaction-state"></a>
### 7.3 Per-transaction state

Each handler is **instantiated fresh per transaction.**
Touchstone calls `.new()` on the handler at the start of every
request, so the handler's own `%bucket` (with the `@foo`
shorthand) is automatically per-transaction state. A handler's
`before` writes `@start_time = %now`; its `after` reads
`@start_time`. No new mechanism — the standard Charlie object
model carries it.

Cross-*handler* state (handler A's `before` talking to handler
B's `after`) is deliberately *not* a first-class concept. If two
handlers need to coordinate, package them as a single handler.

<a id="uncaught-exceptions-become-5xx-responses"></a>
### 7.4 Uncaught exceptions become 5xx responses

If any handler method (`before`, `process`, or `after`) raises
an exception that nobody catches, Touchstone catches it at the
top of the dispatch loop and renders a built-in error page with
an appropriate 5xx status code. The handler chain then continues
into stage 3 against that response — handlers' `after` methods
still run.

Touchstone maps known exception classes to specific status codes;
unknown classes fall back to 500:

| Exception class | Status |
|---|---|
| `kiera.uno/error/timeout` | 504 Gateway Timeout |
| (anything else, uncaught) | 500 Internal Server Error |

The mapping table is small in v1 and grows as more specific
classes earn their own codes. The fallback 500 is the safe
default; nothing crashes the request just because an exception
class isn't in the table.

Observability handlers (logging, metrics, tracing) are most
valuable on the error path; running stage 3 only on the happy
path would defeat them.

<a id="handler-attribution-on-exceptions"></a>
### 7.5 Handler attribution on exceptions

When an exception fires during dispatch, the Jasmine entry
records **which handler was running when it fired** — by name
and registration position. Without this, debugging a chain of
handlers means guessing which one threw. The handler-attribution
field is the first thing an operator looks at.

The attribution names the handler class (`kiera.uno/sinatra/csrf_guard`,
the developer's custom Handler's UNS, the Robinson page-tree
handler for a specific site, etc.) and its position in
`$server.handlers`. Subsystems that compose multiple handlers
(Robinson's per-site sub-chains) include enough detail to
identify the inner Handler too.

This information is then surfaced by descendant frameworks in
their admin error displays — see, for example,
[Robinson's admin error reporting](robinson.md#error-handling).

<a id="cleanup-errors-dont-mask-the-original"></a>
### 7.6 Cleanup errors don't mask the original

If an `ensure` block raises during cleanup while another
exception is unwinding, the cleanup error doesn't replace the
original. Touchstone preserves both: the **original** exception
remains the primary subject of the response (status mapping,
admin display, log entry); the **cleanup** error is attached as
a secondary `cleanup_exception` field on the log entry.

The default Charlie behavior would let the later error shadow
the earlier — Touchstone explicitly intercepts and keeps both
visible. Operators reading the log see "here's what failed, and
also here's what failed during cleanup," not just the second
one.

<a id="developer-controlled-status-codes"></a>
### 7.7 Developer-controlled status codes

If a handler wants a specific status code on a failure that
isn't covered by the mapping table, raise a response directly
instead of letting a bare exception propagate:

```
raise response.new(503, {'Content-Type': 'text/plain'}, 'busy')
```

The response is taken as the request's response; stage 3 runs
against it. No 500 fallback is applied because Touchstone
already has a response.

<a id="short-circuiting"></a>
### 7.8 Short-circuiting

A `before` method can prevent stage 2 from running by either
raising a response-producing exception (a redirect, for example)
or by directly populating `$transaction.response` and raising a
specific "skip-to-stage-3" flag. The standard pattern for auth
middleware that wants to redirect unauthenticated requests:

```
function before($transaction) do
    if not $transaction.session['user_id']
        raise response.redirect.temporary('/login')
    end
end
```

A `before` that returns null (or returns at all without
short-circuiting) is treated as "no opinion" — the next
handler's `before` runs.

---

<a id="the-response-object"></a>
## 8 The response object

A handler returns a response object. The bare constructor is
the full-control form:

```
response.new($status, $headers, $body)
```

- **`$status`** — HTTP status code (integer, e.g., `200`).
- **`$headers`** — **raw HTTP header hash.** Keys are canonical
  HTTP header names (`'Content-Type'`, `'Cache-Control'`,
  `'X-Custom-Whatever'`, etc.) with hyphens and standard casing.
  Touchstone writes them as-is — no normalization.

  **Each header value is either a string or a flat array of
  strings.** HTTP allows the same header to appear multiple
  times in a response (`Set-Cookie` is the canonical case); a
  flat array is the way to represent that. Touchstone emits one
  header line per element. Nested arrays, non-string elements,
  and other shapes are not supported — flat array of strings,
  full stop.

  ```
  {'Content-Type': 'text/html',                    # single value
   'Set-Cookie':   ['name=value; Path=/',           # multi-value, one
                    'theme=dark; Path=/; Secure']}  # line per entry
  ```

  **Duplicate-cookie-name warning.** Before serializing,
  Touchstone inspects all `Set-Cookie` headers in the response
  (including the one produced by the session machinery). If two
  or more cookies share a name — *regardless of scope*
  (`Domain`, `Path`) — Touchstone emits a
  `%chain.warn 'duplicate_cookie_name'` with the full set of
  conflicting cookie strings as details. Jasmine catches the
  warning automatically (see
  [jasmine.md § Automatic warning capture](../jasmine/jasmine.md#automatic-warning-capture)).
  This catches the common bug where the developer thinks they're
  updating one cookie but accidentally creates two with
  overlapping scopes — browsers handle the ambiguity
  inconsistently and the bug typically survives until production.
  The warning is not fatal; the response goes out unchanged.
  Same-name-with-different-scope is technically legal HTTP and
  may be intentional; the warning surfaces the situation rather
  than blocking it.

  **Two snake_case aliases are accepted** for the most-typed
  headers, as a small ergonomic concession:

  | Alias | Resolves to |
  |---|---|
  | `content_type` | `Content-Type` |
  | `location` | `Location` |

  Both forms are equivalent — the alias is normalized to the
  canonical name before emission. No other snake_case keys are
  recognized; everything else must be typed canonically. (If
  both forms are present in the same hash, the developer is on
  their own — the hash's insertion order determines which wins.)
- **`$body`** — string or bytes for the response body. Empty
  string for no body.

```
response.new(200,
    {'Content-Type':  'text/html',
     'Cache-Control': 'no-store',
     'X-Request-Id':  $request.id},
    $html_body)
```

For the common cases, helpers wrap the constructor with
sensible defaults for status, content-type, etc.

<a id="helpers"></a>
### 8.1 Helpers

```
response.html($status, $body)
    # content-type: text/html

response.json($status, $value)
    # content-type: application/json
    # $value is encoded to JSON; usually a hash or array

response.text($status, $body)
    # content-type: text/plain

response.empty($status)
    # empty body, useful for 204 No Content, 304 Not Modified, etc.
```

Status is **always required** in the helper signatures — kept
positional and first to match the bare constructor's shape. The
small ergonomic cost of typing `200` is worth the consistency
and unambiguity.

Anything that doesn't fit one of these helpers falls back to
`response.new(...)` for full control.

<a id="redirects"></a>
### 8.2 Redirects

Redirects are **exceptions**, not return values. Raising one
unwinds the call stack and produces a redirect response — the
handler doesn't need to "return" it. This lets deep code
redirect without threading a "should I redirect?" decision back
up through every intermediate caller.

Three explicit forms, **no default**:

```
response.redirect.permanent('/new-url')   # 301 Moved Permanently
response.redirect.temporary('/new-url')   # 302 Found
response.redirect.see_other('/new-url')   # 303 See Other
```

A bare `response.redirect('/url')` with no specifier is **not**
provided — it's too easy to forget which of "permanent" vs
"temporary" the unmarked default is. Requiring the explicit
choice prevents the wrong default from being silently picked.

**What happens on raise:**

- The call stack unwinds. GC runs `close` on each frame's
  objects going out of scope — open transactions roll back,
  file handles close, etc.
- The framework catches the redirect exception at the top of
  the request and builds the redirect response (status +
  Location header).
- Jasmine's `%chain.log.entry` block flushes on exception
  unwind (already specified), so the log entry is preserved
  with whatever was written before the redirect.

**Why exception, not return value:**

- **Deep code can redirect.** Auth middleware several calls
  down can throw the redirect; intermediate frames don't have
  to know about it.
- **No forgotten returns.** Raising *is* the action — nothing
  to forget.
- **Composability.** A function that might redirect can be
  called from anywhere without callers needing to handle the
  redirect case in their normal return-value logic.

---

<a id="csrf-protection"></a>
## 9 CSRF Protection

CSRF (Cross-Site Request Forgery) protection is built in and
**off by default**. Enable it with one line:

```
$server.csrf_guard = true
```

That's the whole opt-in. Internally this registers the built-in
CSRF guard handler in `$server.handlers`. The handler implements
two methods:

1. **`before($transaction)`** — on incoming POST / PUT / PATCH /
   DELETE requests, compares the submitted `csrf_token` field
   (or the `X-CSRF-Token` header, for AJAX) against
   `$transaction.session['csrf_token']`. Mismatch or missing →
   produces a `403 Forbidden` response and short-circuits the
   chain.
2. **`after($transaction)`** — on HTML responses
   (`Content-Type: text/html`), scans the response body for
   `<form method=POST>` (and PUT, PATCH, DELETE), injects a
   hidden `csrf_token` field with the per-session token, and
   writes the token to `$transaction.session['csrf_token']` if
   it isn't there already.

The session cookie is the carrier; the form field (or header)
is the second factor. Standard synchronizer-token pattern.

<a id="per-route-opt-out"></a>
### 9.1 Per-route opt-out

Some POSTs legitimately come from third parties without a token
— webhooks, bearer-token API clients, public ingestion endpoints.
Disable the check on a single route with `csrf: false`:

```
$server.post('/webhooks/stripe', csrf: false) do($request)
    # Stripe's POST has no CSRF token — that's expected.
    process_webhook($request.body)
end
```

The default is "guard on" when `$server.csrf_guard = true`. The
kwarg only suppresses verification for that specific route. (The
`csrf: false` kwarg shape lives on Sinatra's path-selector
registrations; Robinson exposes the same opt-out via its own
page-config mechanism.)

<a id="ajax-path"></a>
### 9.2 AJAX path

JavaScript clients that POST JSON instead of forms read the
token from `$transaction.session['csrf_token']` (delivered to
the client via a `<meta name="csrf-token" content="...">` tag
in the rendered HTML, or however the developer chooses to
surface it) and send it back as the `X-CSRF-Token` header. The
guard accepts either form field or header.

<a id="limits-of-the-html-scanner"></a>
### 9.3 Limits of the HTML scanner

The injection step uses a narrow purpose-built scanner — it
finds `<form method=POST>` opening tags and injects the hidden
field right after them, skipping over `<!-- comments -->`,
`<script>`, and `<style>` regions. It is **not** a full HTML5
parser: exotic constructs (CDATA sections, deeply malformed
tags, forms generated by JavaScript on the client) may not get
a token injected. Server-side rendered HTML covers the common
case; pages assembled client-side need the AJAX header path
instead.

<a id="why-this-is-in-core-not-an-add-on"></a>
### 9.4 Why this is in core (not an add-on)

CSRF is a class of attack that most developers know about but
many don't actually implement. Opt-in features that
should-be-default get skipped. Making it one line to enable,
with no boilerplate in handlers, is the next-best thing to
on-by-default — and it avoids breaking servers that don't
render HTML (most JSON APIs) or that have CSRF handled upstream
(reverse proxy, gateway).

The infrastructure overlap with the session cookie is real:
storing the token, parsing the cookie, mutating it on response
— all of which already exists for sessions. CSRF guard adds
the HTML scanner and the verification check; the session
cookie machinery is shared.

---

<a id="content-security-policy"></a>
## 10 Content Security Policy

CSP is the strong defense-in-depth against XSS — it tells the
browser which sources are allowed for scripts, styles, images,
etc., so that injected attacker content is refused by the browser
even when it slips through the application. Touchstone provides
the mechanism; both Sinatra and Robinson inherit it unchanged.

Touchstone exposes CSP as a **per-response** hash on
`$response.csp`. Each handler composes the policy for its own
response; no global server-level configuration. Pages with strict
policies and pages with loose policies coexist freely.

The hash's shape is a JSON format — directive name keys, array
of source strings as values — that's also the wire format for
**CSPM**, a separate forthcoming system for managing CSPs at a
larger scale (composition, inheritance, named policies, etc.).
For v1 the hash itself is the only interface; CSPM tooling will
plug into the same shape later without breaking existing
handlers.

```
{
    "default-src": ["'none'"],
    "script-src":  ["'self'", "cdn.example.com"],
    "img-src":     ["'self'", "data:"]
}
```

```
$response.csp['default-src'] << 'none'
$response.csp['script-src']  << 'self'
$response.csp['script-src']  << 'cdn.example.com'
$response.csp['style-src']   << 'self'
$response.csp['img-src']     << 'self'
$response.csp['img-src']     << 'data:'
```

Each directive key is **auto-vivified on access** — you can
always `<<` into any directive without pre-initializing it. The
value is a list of sources.

<a id="header-emission-rule"></a>
### 10.1 Header emission rule

The `Content-Security-Policy` header is emitted **if any
directive has at least one source**. Empty directives are
silently elided. A response that never touches `$response.csp`
gets no CSP header at all.

To explicitly drop a CSP that an earlier handler may have set:

```
$response.csp.clear
```

`.clear` empties the hash, so no directives have any sources, so
no header is emitted.

<a id="keyword-quoting"></a>
### 10.2 Keyword quoting

CSP wraps certain keywords in single quotes in the actual header:
`'self'`, `'none'`, `'unsafe-inline'`, `'unsafe-eval'`,
`'strict-dynamic'`, `'report-sample'`, and the nonce/hash forms.
Touchstone **auto-quotes** these when serializing the header.
Developers write plain strings (`'self'` as a Charlie string
literal); the serializer produces `'self'` in the header.
Hostnames and URLs are written bare (`cdn.example.com` stays
unquoted).

The auto-quote list is the fixed set of CSP keywords plus the
patterns `nonce-*` and `sha{256,384,512}-*`. Anything else is
treated as a source expression and emitted as-is.

<a id="serialization"></a>
### 10.3 Serialization

On response build, Touchstone walks `$response.csp` and produces
a single `Content-Security-Policy` header. Directives are joined
with `; ` and each directive's sources are space-separated:

```
Content-Security-Policy: default-src 'none'; script-src 'self' cdn.example.com; style-src 'self'; img-src 'self' data:
```

Directive order in the header follows the order they were first
added; sources within a directive follow insertion order. Both
are stable but neither carries semantic meaning to the browser.

<a id="whats-not-in-core"></a>
### 10.4 What's not in core

- **No `Content-Security-Policy-Report-Only` mode.** If demand
  surfaces, the natural API is `$response.csp_report_only` as a
  parallel hash. Not in v1.
- **No CSP violation report endpoint.** Easy to register
  manually in a server's route handlers and log to Jasmine.
- **No per-request nonce auto-injection** into `<script>` tags.
  Developers can generate a nonce in the handler, push it into
  `$response.csp['script-src']`, and include it manually in the
  rendered HTML. Auto-injection (similar to Sinatra's CSRF
  guard's form-tag injection) is a candidate for a later
  version if it proves light.

---

<a id="not-for-direct-use"></a>
## 11 Not for direct use

Static file serving is **not** a Touchstone responsibility.
Sinatra and Robinson each handle static files in their own way —
their needs differ enough that a shared implementation in the base
class would compromise both. Touchstone provides the *facts* (the
content-type map) but leaves the *behavior* to descendants.

If you want a server, instantiate Sinatra or Robinson — not
Touchstone directly.
