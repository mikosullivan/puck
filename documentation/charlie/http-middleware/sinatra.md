# Sinatra

~~~json
{"vibecode": {
	"doc": "sinatra",
	"role": "spec for puck.uno/sinatra, a small-site HTTP server with Ruby-Sinatra-style route handlers (closures bound to HTTP-method+path pairs); core middleware built on Touchstone",
	"key_concepts": ["route_handlers", "method_path_pairs", "closure_handlers",
		"catch_all_fallthrough", "touchstone_descendant"]
}}
~~~

`puck.uno/sinatra` — a small-site HTTP server with Ruby-Sinatra-style
route handlers. Closures register against HTTP-method + path pairs;
unmatched requests fall through to a catch-all.

Built on [Touchstone](touchstone.md), which provides content-type
defaults, Jasmine integration, and shared HTTP plumbing. Sinatra
adds the route-handler layer and its own approach to static file
serving on top.

---

<a id="status"></a>
## 1 Status

Spec in development. Material previously filed under the
[Dogberry wishlist](../../ideas/dogberry-wishlist.md) (Sinatra
Method Selectors section, error pages, etc.) applies here and
will be ported in as this doc fills out. Until that port is
done, treat the wishlist as the source of truth for Sinatra's
shape.

---

<a id="quick-example"></a>
## 2 Quick example

```
$server = %['puck.uno/sinatra'].new()

$server.get('/') do($request)
    response.new(200, {'Content-Type': 'text/plain'}, 'Hello world')
end

$server.get('/shakespeare/{play}/') do($request)
    response.new(200, {'Content-Type': 'text/html'}, render_play($request.steps['play']))
end

$server.post('/shakespeare/{play}/') do($request)
    # POST to the same path is a separate registration
end

$server.run() do($request)
    # catch-all fallback for unmatched requests; absent or no
    # response returned → 404
end
```

<a id="whats-in-scope"></a>
## 3 What's in scope

Small-case use:

- Method-selector API (`get`, `post`, `put`, `delete`, `patch`,
  `options`, `head`).
- Method-agnostic registration (`all_methods`) for routes that
  serve every method.
- A primitive `path(pattern, methods: [...])` form that the
  selectors are sugar for.
- Route patterns with named placeholders and named splats (see
  below).
- The `$request` object exposing path captures, params, and body
  (see below).
- Catch-all in `run()` for unmatched requests.
- Built-in, not-configurable error pages (404, 500, etc.).
- A standard `response` constructor.
- Static file serving via a directory object (see below).

<a id="route-patterns"></a>
## 4 Route patterns

A route pattern is a path string with two kinds of named captures:

- **`{name}`** — matches **exactly one path segment** (no slashes
  in the captured value). Lua-pattern equivalent: `([^/]+)`.
- **`*name`** — matches **one or more path segments**, slashes
  allowed. Lua-pattern equivalent: `(.+)`.

Captured values land in `$request.steps`, keyed by name.

```
# Single-segment placeholder
$server.get('/users/{id}') do($request)
    # matches /users/42 only (not /users/42/posts)
    $id = $request.steps['id']
end

# Named splat — capture the rest of the path
$server.get('/files/*path') do($request)
    # matches /files/spec.pdf, /files/docs/spec.pdf, etc.
    $path = $request.steps['path']     # 'spec.pdf' or 'docs/spec.pdf'
end

# Mixed placeholder + splat
$server.get('/users/{user_id}/files/*path') do($request)
    $user = $request.steps['user_id']
    $path = $request.steps['path']
end

# Multiple splats
$server.get('/say/*greeting/to/*name') do($request)
    # GET /say/hi/there/to/bob/jones
    $greeting = $request.steps['greeting']   # 'hi/there'
    $name     = $request.steps['name']       # 'bob/jones'
end
```

**Captured values are strings.** No type coercion at the routing
layer — the developer parses to numbers, dates, etc. as needed.

**Splat captures contain embedded slashes but no leading slash.**
The slash is the segment separator, not part of the captured value.

**Greedy with backtracking.** When a pattern has multiple
splats, Lua's regex engine backtracks to find a match where every
piece fits. `/say/*greeting/to/*name` against `/say/hi/there/to/bob/jones`
resolves to `greeting='hi/there'`, `name='bob/jones'`.

**Only named forms.** There's no anonymous `*` splat (Ruby Sinatra
has one; we don't). Every capture has a name. Self-documenting and
keeps `$request.steps` a regular hash with no magic keys.

**Regex routes are out of scope.** Ruby Sinatra accepts raw regex
patterns; we don't, because Lua patterns aren't a full regex
engine and the feature isn't worth a separate engine. Use the
named-capture syntax above.

**Method mismatches return 404, not 405.** If the client sends
`POST /users/42` and only `GET /users/{id}` is registered,
Sinatra treats the request as unmatched — the path-with-this-method
doesn't exist. The request falls through to the catch-all on
`$server.run` (or the built-in 404 page if there's no catch-all).
No automatic 405 for the mismatch itself. This matches Ruby
Sinatra's behavior and keeps the routing dispatch simple — Sinatra
doesn't have to track which other methods exist for a given path
pattern just to refine an error response. Handlers that want
strict 405 semantics use [`$server.reject`](#explicit-405-serverreject)
to declare which methods are rejected per path.

Two narrow carve-outs do scan the registered methods for a path
and emit an `Allow:` header automatically:
[`$server.reject`](#explicit-405-serverreject) (explicit
405 responses) and [auto-OPTIONS](#auto-options) (default
response to `OPTIONS /path`). Both can be turned off; both are
defaults that yield to explicit registrations.

**Trailing slashes are significant.** `/foo` and `/foo/` are
**different routes.** A registration for `/foo` does not match
a request to `/foo/`; each must be registered independently if
both should be served. No automatic normalization, no 301
redirect. This matches Ruby Sinatra's explicit behavior. If
canonical-form redirects are wanted, the developer registers a
small redirecting handler — or an upstream reverse proxy
normalizes paths before Sinatra sees them.

**Route precedence: first match wins, by registration order.**
Each `$server.get/.post/.put/...` registration adds a path
selector Handler to `$server.handlers`. The dispatcher walks
the array in registration order — the first selector whose
method-and-pattern matches the incoming request is the one
that runs. No specificity ranking, no longest-prefix heuristic.
The developer orders their registrations deliberately:
more-specific routes before more-general ones.

```
$server.get('/user/edit')   do($request) ... end    # literal
$server.get('/user/{id}')   do($request) ... end    # placeholder

# GET /user/edit  → matches the literal route (registered first)
# GET /user/42    → falls through to the placeholder route
```

If the placeholder route had been registered first, it would
have matched `/user/edit` (capturing `edit` as the id) — and
the literal route would never be reached. This is the same
first-response-wins rule as the handler chain itself.

<a id="method-agnostic-registration"></a>
### 4.1 Method-agnostic registration

`$server.all_methods(pattern) do ... end` registers a path
selector that matches the pattern regardless of the request
method. Useful for catch-alls, OPTIONS responders that handle
preflight uniformly, and rare cases where one handler genuinely
serves every method.

```
$server.all_methods('/healthz') do($request)
    response.new(200, {'Content-Type': 'text/plain'}, 'ok')
end
```

The closure can inspect `$transaction.request.method` if it
needs to behave differently for different methods. (REST style
prefers distinct per-method registrations; `all_methods` is for
the cases where one response really is right for every verb.)

<a id="the-path-primitive"></a>
### 4.2 The `path()` primitive

The per-method selectors and `all_methods` are sugar for a
single primitive:

```
$server.path(pattern, methods: ['GET', 'POST']) do($request)
    # matches the pattern for the listed HTTP methods
end
```

The `methods:` kwarg is a list of HTTP method strings, or
`['*']` for "any method." Method strings are **case-insensitive**
on input — `'GET'`, `'get'`, `'Get'` are all accepted and
normalized internally. Examples in the doc use uppercase by
convention (matches the on-the-wire form), but writing them
lowercase is fine. The sugar mappings:

| Sugar | Equivalent primitive call |
|---|---|
| `$server.get(p)` | `$server.path(p, methods: ['GET'])` |
| `$server.post(p)` | `$server.path(p, methods: ['POST'])` |
| `$server.put(p)` | `$server.path(p, methods: ['PUT'])` |
| `$server.delete(p)` | `$server.path(p, methods: ['DELETE'])` |
| `$server.patch(p)` | `$server.path(p, methods: ['PATCH'])` |
| `$server.options(p)` | `$server.path(p, methods: ['OPTIONS'])` |
| `$server.head(p)` | `$server.path(p, methods: ['HEAD'])` |
| `$server.all_methods(p)` | `$server.path(p, methods: ['*'])` |

For uncommon method combinations (e.g., "POST and PUT but not
GET"), reach for the primitive:

```
$server.path('/items/{id}', methods: ['POST', 'PUT']) do($request)
    # create or update on the same handler
end
```

No further compound sugar (no `post_and_get`, no
`get_and_head`) — the named per-method selectors plus
`all_methods` plus the primitive cover the space without
ballooning the method-name surface.

<a id="explicit-405-serverreject"></a>
### 4.3 Explicit 405: `$server.reject`

For REST-conscious deployments that want strict
`405 Method Not Allowed` semantics (rather than the default 404
for method mismatches), `$server.reject` registers a path
selector that explicitly responds 405:

```
$server.get('/users/{id}')    do($request) ... end
$server.head('/users/{id}')   do($request) ... end
$server.reject('/users/{id}', 'POST', 'PUT', 'DELETE')

# Request: POST /users/42
# Response: 405 Method Not Allowed
#           Allow: GET, HEAD
```

The `Allow` header is **auto-populated** by Sinatra from the
cached [methods-per-path index](#methods-per-path-index) — the
same index that powers auto-OPTIONS. The developer doesn't have
to maintain the Allow list; it stays in sync with the
registrations automatically.

Variadic method args; at least one method required. Multiple
`reject` calls on the same path accumulate (each adds methods
to the rejected set).

For the explicit-405 case to work, the developer should still
register the methods that ARE allowed (via `$server.get`,
`$server.post`, etc.). Reject is the "everything else 405s"
shape; without positive registrations, there's nothing to put
in the Allow header and the response degrades to a bare 405.

Reject is **opt-in per path**. Paths without reject registrations
continue to return 404 for method mismatches (the default
behavior, matching Ruby Sinatra). Reject lets the developer
upgrade specific paths to strict-405 semantics without changing
the global default.

<a id="auto-options"></a>
### 4.4 Auto-OPTIONS

Sinatra ships with a **built-in default handler** that responds
to `OPTIONS /path` with `204 No Content` and an `Allow:` header
listing the methods registered for that path:

```
$server.get('/users/{id}')    do($request) ... end
$server.head('/users/{id}')   do($request) ... end
$server.delete('/users/{id}') do($request) ... end

# Request:  OPTIONS /users/42
# Response: 204 No Content
#           Allow: GET, HEAD, DELETE, OPTIONS
```

`OPTIONS` is always included in the Allow list (Sinatra is
answering the OPTIONS request, so OPTIONS is by definition
supported).

**It's a handler, not a special dispatch path.** At construction,
Sinatra appends a final-position OPTIONS-matching handler to the
handler chain. The chain's normal first-match-wins rule applies:
explicit `$server.options(path) do ... end` registrations live
earlier in the chain and win. This is the path for CORS
preflight responses, where the handler sets
`Access-Control-Allow-*` headers the default doesn't know about.

```
$server.options('/api/users/{id}') do($request)
    $response.headers['Access-Control-Allow-Origin'] = 'https://example.com'
    $response.headers['Access-Control-Allow-Methods'] = 'GET, POST'
    $response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    $response.status = 204
end
```

**Disabling auto-OPTIONS.** Skip registering the default handler
at server construction:

```
$server = sinatra.new(auto_options: false)
```

With it off, OPTIONS requests fall through like any other
unmatched method (404 via catch-all). Removing or replacing the
default handler directly via `$server.handlers` works too — the
default is a regular handler object, not a privileged
one.

**Server-wide OPTIONS** (`OPTIONS *`, the RFC 7231 asterisk
form) is not handled by the default. Register
`$server.options('*')` manually if needed.

<a id="methods-per-path-index"></a>
### 4.5 Methods-per-path index

Both auto-OPTIONS and [`$server.reject`](#explicit-405-serverreject)
need to know "which methods are registered for path X" to
populate the `Allow:` header. Sinatra maintains a cached
`{path_pattern → [methods]}` index, rebuilt lazily after any
registration call. After `$server.run` starts, registrations
are usually frozen — the index settles to one build and stays
there.

**Reject is O(1).** When a reject handler matches, it already
knows its own pattern (it was registered against one). The
handler does `index[pattern]` and filters out the rejected
methods. Single hash read.

**Auto-OPTIONS scans patterns.** The default OPTIONS handler
matches any path, so when `OPTIONS /users/42` arrives, the
handler doesn't know which registered patterns match
`/users/42`. To compute Allow, it walks the unique patterns
from the index and pattern-matches each against the concrete
path. That's O(unique_patterns) per OPTIONS request.

Three things keep this acceptable for v1:

1. **OPTIONS traffic is rare.** CORS preflight is the main
   source, and browsers cache preflights via
   `Access-Control-Max-Age` (hours). The scan runs on OPTIONS
   requests, not GET requests.
2. **Per-pattern match is cheap.** Patterns are parsed segment
   lists; matching is a per-segment compare, not a regex
   engine. A few hundred patterns is microseconds.
3. **Trie/radix indexing exists as a future escape hatch.** If
   a deployment ships thousands of routes and becomes
   OPTIONS-bound, patterns can be reorganized structurally
   (radix tree, prefix segmentation) to make concrete-path →
   matching-patterns lookup O(path_segments). Not v1 work.

The index is internal — handler code doesn't see it. It exists
so the two `Allow:`-emitting features stay cheap on the common
path.

<a id="request-transaction-sessions-body-buffering"></a>
## 5 Request, transaction, sessions, body buffering

All of these are universal HTTP infrastructure and live in
[Touchstone](touchstone.md):

- The [`$request` object](touchstone.md#the-request-object) —
  `steps` (positional and nickname), `params`, `param_array`,
  `param_hash`, `body`. Steps nicknames are populated by
  Touchstone's pattern matcher before the request is locked, so
  Sinatra path-selector closures see fully-formed steps
  including `{name}` captures.
- The [`$transaction` object](touchstone.md#the-transaction-object) —
  `request`, `response`, `session`.
- [Sessions](touchstone.md#sessions) — `$transaction.session`
  hash, domain configuration, default cookie attributes.
- [Body buffering](touchstone.md#body-buffering) — memory and
  FSO modes, `puck.uno/touchstone/error/sinatra/cannot_store_files`.

Sinatra inherits these unchanged.

<a id="static-file-serving"></a>
## 6 Static file serving

Sinatra **has no filesystem dependency by default.** A bare `.new()`
gives a routes-only server that never touches a filesystem — ideal
for IPC over Unix sockets, in-memory test fixtures, or any
environment where there's nothing to read from disk.

When you do want static files served, register a **directory
object** with `$server.static`:

```
$server.static $dir
```

The `$dir` is a directory object (Puck's filesystem abstraction).
Sinatra doesn't know or care what backs it — could be a real
filesystem path, an in-memory tree, a remote source, a tarball,
anything that implements the directory interface. Sinatra just
asks the directory for files by name and serves whatever comes
back, applying the content-type factory defaults from
[Touchstone](touchstone.md).

Multiple `static` registrations are fine; they layer in
registration order.

**Why a directory object, not a path string.** Sinatra is the
intended server for IPC and other very-light deployments. Taking
a path string would couple it to the filesystem; taking a
directory object decouples it. The directory abstraction handles
the "where do the bytes come from" question separately, so
Sinatra stays light.

**No entry, no serve.** Sinatra refuses to serve a file whose
extension does not have an explicit entry in
[`factory.json`](factory.json) (or a developer-supplied
extension). A file with an unknown or unlisted extension returns
404 — even if it physically exists in the configured directory.
This is a deliberate safety rule: unknown extensions don't get
guessed, so a stray file (a `.bak` from an editor, a `.charlie`
source, a `.env` left in the static directory by mistake) won't
leak. To serve an extension, add it to the factory list or the
server's local override.

**No directory listings by default.** A request that resolves to
a directory (rather than a specific file) returns 404 by default
— no auto-generated index of the directory's contents. This is
the `directory.list = false` factory setting in
[`factory.json`](factory.json). The developer can enable
listings explicitly when they're wanted; otherwise the
directory's inventory stays hidden, on the same "no dangerous
defaults" principle as the per-extension rule above.

<a id="concurrency"></a>
## 7 Concurrency

**Sinatra is single-threaded. One request at a time.** The accept
loop reads a request, runs the handler synchronously, writes the
response, then accepts the next connection. There is no thread
pool, no fiber pool, no async runtime — Charlie itself is
single-threaded by design, and Sinatra inherits that constraint
directly. This keeps the implementation tiny and makes handlers
trivial to reason about: no locking, no race conditions, no
shared-mutable-state hazards between requests in a single
Sinatra process.

**Multiple TCP connections waiting at once is fine** — they queue
at the OS level on the listen socket. The accept loop just
processes them serially. The same is true for a Unix domain
socket in IPC deployments.

**Scaling beyond one request at a time is process-level, not
thread-level.** Three deployment paths:

- **Externally supervised**: run N Sinatra processes behind a
  load balancer or per-Unix-socket, supervised by the host's
  process manager (systemd, k8s, etc.). The deployer owns the
  worker count and restart policy.
- **Forking add-on**: install the Sinatra forking add-on
  (downloadable, not in core) and let it manage a prefork pool
  of workers from a single `$server.run`. Each worker is itself
  a single-threaded Sinatra process; the add-on just handles
  fork/accept distribution and worker lifecycle.
- **Robinson**: if you want forking *and* the other features
  Robinson provides (multi-site dispatch, admin auth, factory
  pages), use Robinson instead of Sinatra+add-on.

**What this rules out for v1:**

- **Long-polling and streaming responses.** Holding a connection
  open blocks the entire server. Not supported.
- **WebSockets.** Same reason.
- **Background work during a request.** The handler completes
  synchronously and returns; there's no "fire-and-forget" task
  inside Sinatra. Spawn the work externally (a worker, a queue)
  if needed.
- **Per-request timeouts via threading.** Handler timeouts come
  from `%utils.timeout` wrapping the handler call, not from a
  reaper thread.

These are deliberate trade-offs. Sinatra is meant for small,
fast, predictable services; cases that need concurrency move
to Robinson or a deployer-level multi-process setup.

<a id="handlers"></a>
## 8 Handlers

The handler chain, three-stage dispatch (`before` / `process` /
`after`), the `$transaction` object, per-handler state, uncaught
exception handling, and short-circuit semantics all live in
[Touchstone](touchstone.md#the-handler-chain). Sinatra inherits
the full machinery; this section just notes the Sinatra-specific
details on top.

**Path selectors as Handlers.** The `$server.get('/foo') do ... end`,
`$server.post(...) do ... end`, etc. registrations are syntactic
sugar that creates a **path selector Handler** and adds it to
`$server.handlers`. A path selector is a small Handler whose
`process` method checks the request against its method + path
pattern, runs the registered closure if matched, and returns the
closure's response. If the pattern doesn't match, `process`
returns null — the next Handler in the array gets a turn.

Path selectors and add-on Handlers (CSRF guard, CORS, etc.) sit
in the same flat `$server.handlers` array. There's no separate
"route table" object — just an ordered list of Handlers, each
deciding whether to handle the request as it gets called.
Registration order is dispatch order.

**Catch-all.** Sinatra's `$server.run() do ... end` catch-all is
the Sinatra-specific fallback when no handler returned a response.
See [The three stages](touchstone.md#the-three-stages) in
Touchstone for how that slots into the dispatch flow.

<a id="csrf-protection-and-csp"></a>
## 9 CSRF Protection and CSP

Both are universal HTTP security features and live in
[Touchstone](touchstone.md):

- [CSRF Protection](touchstone.md#csrf-protection) — opt-in via
  `$server.csrf_guard = true`. Sinatra exposes the per-route
  `csrf: false` opt-out as a path-selector kwarg.
- [Content Security Policy (CSP)](touchstone.md#content-security-policy-csp) —
  per-response `$response.csp` hash.

Sinatra inherits both unchanged.

<a id="whats-out-of-scope"></a>
## 10 What's out of scope

The fancier features Robinson covers (multi-site dispatch,
filesystem trees, admin authentication, factory message overrides,
canonical redirects) do **not** apply to Sinatra. If you need
those, use Robinson.

<a id="candidates-for-v1"></a>
## 11 Candidates for v1

The features below are tempting to add. Each is a v1 candidate
**if and only if it proves light** — a short, clean implementation
that doesn't push Sinatra's core out of microservice territory.
A 50-line addition is a different proposal from a 500-line
subsystem. The general rule that catches most of these: if a
feature requires Sinatra to know something domain-specific about
HTTP semantics, auth, or the application's state model, it
probably doesn't belong in core.

As each is evaluated, it either gets promoted to scope (with a
full spec section above) or moved to add-on territory.

<a id="comfort-middleware"></a>
### 11.1 Comfort middleware

- **Cookies API / sessions.** **Promoted to scope** — see
  [`$transaction.session`](#sessions). Basic JSON-hash cookie
  with safe defaults; light enough to ship in core. Richer
  session semantics (server-side store, multiple cookies,
  persistent expiry) stay add-on.
- **Authentication / authorization helpers.** Auth is usually a
  deployment concern (reverse proxy, JWT verifier upstream).
  Sinatra shouldn't ship anything that touches credentials.
- **CORS.** Out of scope for v1. Headers the developer can set
  explicitly via their own `$server.options(...)` handler;
  baking in CORS rules ships a permission system Sinatra
  shouldn't own, and a permissive default would be a security
  hole. **Will need revisiting.** If the page-as-API story
  ([Robinson](robinson.md)) leads developers to commonly expose
  Puck endpoints to third-party JS, a `$server.cors(...)`
  helper may be worth designing — but as a deliberate addition,
  not casual accretion. Until that pattern is real, the
  framework provides the override slot (auto-OPTIONS yields to
  explicit registrations) and the developer fills in the policy.
- **Rate limiting.** Reverse proxy or add-on.

<a id="http-correctness-niceties"></a>
### 11.2 HTTP "correctness" niceties

- **Auto-HEAD from GET.** Tempting and small, but it implies
  "Sinatra knows your GET is side-effect-free," which it doesn't.
  Make HEAD an explicit `.head()` registration if wanted.
- **Content negotiation (Accept header parsing).** A whole
  subsystem disguised as one feature.
- **ETag / Last-Modified / Cache-Control helpers.** Handler sets
  the header explicitly. No magic.
- **HTTP method override** (Rails-style `_method` form field).
  Pure historical wart.

<a id="routing-power"></a>
### 11.3 Routing power

- **Before/after request hooks and middleware chain.**
  **Promoted to scope** — see [Handlers](#handlers). The
  three-stage handler chain (`before` / `process` / `after`
  methods on registered handler objects) covers both
  conventional pre/post-processing and the middleware-chain
  use case in one mechanism.
- **Multiple handlers per route, with fall-through.** One handler
  per (method, path).
- **Mount / sub-app composition.** Use path prefixes manually.
- **URL reverse routing / named routes.** Path strings are paths.

<a id="response-sugar"></a>
### 11.4 Response sugar

- **Status code symbols** (`:ok`, `:not_found`). Integer 200 is fine.
- **Auto-JSON-from-hash return.** Forces a JSON encoder into the
  response path even when not needed. The explicit
  `response.json(...)` is honest.
- **Pretty-print JSON by default.** No.

<a id="body-serialization"></a>
### 11.5 Body / serialization

- **XML, YAML, form-urlencoded-via-magic body parsers.** Multipart
  is already in because uploads need it. Everything else is the
  handler's problem.
- **Built-in gzip / brotli compression.** Reverse proxy.

<a id="observability"></a>
### 11.6 Observability

- **A logger interface separate from Jasmine.** Jasmine is the
  logging surface. Don't expose a second one.
- **Metrics / Prometheus endpoints.** Add-on territory.

<a id="testing"></a>
### 11.7 Testing

- **A built-in test client / mock request builder.** Bryton plus
  a real loopback socket is the path. No test-only mode inside
  the server.

<a id="streaming-async"></a>
### 11.8 Streaming / async

(Already ruled out by single-threaded — see [Concurrency](#concurrency).
Long-polling, WebSockets, SSE not viable in core.)

---

<a id="add-ons"></a>
## 12 Add-ons

Sinatra is designed to be extended by add-ons — installable
packages that layer additional behavior on top of the core
server. The architecture supports them, and the v1 surface is
deliberately small enough that third parties have room to add
real value (authentication helpers, template engines, websocket
support, content negotiation, rate limiting, etc.).

**First-party add-ons** that ship alongside Sinatra but are
explicitly opt-in downloads, not core:

- **Forking add-on.** Forks a worker process per incoming
  request. Each worker is a single-threaded Sinatra (or
  Robinson) process that handles one request and exits.
  **Mode: fork, detach, ignore.** Parent doesn't track the
  child, doesn't wait for it, doesn't reuse it — each request
  gets a fresh OS-level slate. Security upside is real: no
  state contamination between requests; runaway or compromised
  workers die with the request. **Worker reuse (the prefork-pool
  model where workers stay alive across requests) is way out
  past v1** — substantial additional machinery for IPC,
  idle/busy tracking, state-reset, lifecycle policy, and crash
  recovery. The fire-and-forget shape is the only mode for v1
  and the foreseeable future.

For v1, **everything currently spec'd stays in the core Sinatra
package** — routes, params, static file serving, multipart
uploads, response handling, error pages, the lot. The add-on
architecture is the extension point for things we *haven't*
specced. If a feature later proves heavy enough that splitting
it out is worthwhile, that's a non-breaking change to the
existing package shape.

Community add-ons are welcomed and expected.

---

<a id="the-response-object"></a>
## 13 The response object

The response constructor (`response.new($status, $headers, $body)`),
the convenience helpers (`response.html`, `response.json`, etc.),
header conventions (raw HTTP names, snake_case aliases for
`content_type` and `location`, multi-value flat arrays), the
duplicate-cookie-name warning, and the redirect machinery
(`response.redirect.permanent`, etc.) all live in
[Touchstone § The response object](touchstone.md#the-response-object).
Sinatra inherits them unchanged.

---

<a id="to-be-ported-from-the-wishlist"></a>
## 14 To be ported from the wishlist

- Detailed registration semantics
- Error page rendering
- Implicit-last-value return convention

<a id="open-issues"></a>
## 15 Open issues

(none currently)

