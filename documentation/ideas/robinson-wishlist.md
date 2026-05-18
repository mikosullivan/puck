# Robinson Wishlist

~~~json
{"vibecode": {
	"doc": "robinson-wishlist",
	"role": "running capture-not-commit list of features wanted in the Charlie Robinson reincarnation, drawing on the prior Ruby Robinson; prioritization happens after the list is reasonably complete",
	"key_concepts": ["feature_wishlist", "capture_not_commit", "scales_down_and_up",
		"ruby_robinson_lineage"],
	"status": "wishlist"
}}
~~~

A running list of features wanted in Robinson, the Charlie HTTP middleware framework.
Background: Miko built a previous Robinson in Ruby — a comprehensive web framework
in the same conceptual space as Rails or Sinatra. This document captures features
to consider for the Charlie reincarnation.

**Purpose**: capture, not commit. Listing a feature here means "we want this
eventually." It does not commit Robinson to shipping it in any particular release.
Prioritization (what's in the first release, what's deferred, what gets dropped)
happens after the wishlist is reasonably complete.

**Method**: Miko describes features one at a time. Each gets a short entry under
its category. We refine names, semantics, and open questions as we go. When the
list feels complete, we sort by priority and decide what's in for v1.

---

<a id="design-goals"></a>
## 1 Design Goals

<a id="scales-down-small-scales-up-large"></a>
### 1.1 Scales Down Small, Scales Up Large

Robinson is intended to be a **common scalable solution** — the same framework
serves a tiny personal site, an internal tool, and a moderately high-traffic
production deployment. The same principle Mikobase follows: one tool for the
whole range, configured appropriately for each scale, with no "use the big
version when you get big" handoff. A microservice and an in-house API are
running the same Robinson; what differs is configuration.

**The target range**:

- Microservices and small daemons (lowest end)
- Internal company APIs and dashboards
- Small to mid-traffic public websites
- Self-hosted tools serving an organization

**The target range explicitly does NOT include** AWS-scale demand, hyperscale
public services, or systems needing extreme custom concurrency primitives.
We're aiming for the broad, common solution — not the top of the throughput
curve. That sort of ability might be developed down the road, but it is not
on the horizon right now.

What this means in practice:

- **Defaults match the small case.** Single process, sensible auto-config.
  The small-site convenience layer (the Sinatra handler, with its method
  selectors and built-in error pages) is one keyword away (`sinatra: true`)
  — not on by default, but trivial to turn on.
- **Opt-ins unlock the large case.** Worker pool with prefork concurrency,
  custom handler chains, fine-grained settings cascade, alternative routing
  models. A production deployment selects the parts it needs.
- **The transition is smooth, not a rewrite.** A site that grows from "small"
  to "large" turns on additional features incrementally. It doesn't abandon
  Robinson for a different framework, and it doesn't have to restructure its
  handlers to scale up.

Many of the design choices already in this wishlist follow directly from this
goal: the single-process default with `enable_forking` opt-in, the empty-by-
default server with a one-keyword `sinatra: true` opt-in for the small-site
convenience layer, the full handler-chain composability underneath everything.
Each is a small-case default with a large-case opt-in (or vice versa: a
clean-slate default with a convenience opt-in). The pattern repeats across
the design.

<a id="no-dangerous-defaults"></a>
### 1.2 No Dangerous Defaults

Robinson never ships with defaults that could harm the developer or
their users. For features that carry risk — admin access, forking,
exception exposure, anything that can leak data or grant elevated
privilege — the default is **off**. Turning them on requires an
explicit decision.

In many cases, Robinson ships with **no default at all**. The developer
has to declare an intent. There is no admin until you set one up. There
is no forking until you opt in (and the engine grants permission). There
is no Sinatra handler until you ask for one. Silence is not consent.

This is the inverse of the "convenient out-of-the-box" tradition. We
swap some initial setup for the certainty that the framework isn't
doing anything the developer didn't ask for. The setup is intentionally
cheap (often one keyword), but the choice is theirs to make explicitly.

Every opt-in in the design follows this rule — that's why the pattern
repeats.

<a id="dogfooding-puckuno"></a>
### 1.3 Dogfooding: puck.uno

Robinson will be used for the Puck project's own public site (puck.uno)
**as much as possible**. The Puck ecoverse is its own first serious user.
This sets a useful pressure on the design: the framework has to work well
enough for a real public-facing site before we can ship our own. We feel any
rough edges before anyone else does.

Practical consequence: puck.uno's needs are the de-facto v1 requirement set.
If Robinson can serve puck.uno well, it can serve the kinds of sites the
target range covers.

---

<a id="features"></a>
## 2 Features

<a id="settings-hierarchy"></a>
### 2.1 Settings Hierarchy

Everything in Robinson rests in a settings cascade with five levels:

1. **factory** — what ships with Robinson (the base/default settings hash)
2. **installation** — the server (a deployed Robinson instance)
3. **site** — a website served by this installation
4. **directory** — directories within the site (potentially nested)
5. **page** — individual pages

Settings flow **down** the hierarchy. Each level inherits everything from above
and can write its own settings, which then propagate to everything below it. Like
`%chain`, **changes do not propagate back up** — a setting written at the page
level is invisible to the directory level above it, and a setting written at the
directory level is invisible to the site level above it.

The factory defaults are the deepest baseline — every Robinson installation starts
from the same factory hash. The installation, site, directory, and page levels
each get a chance to extend or override before the page actually runs.

The settings hash itself is essentially a JSON hash — extensive but plain. Specific
settings categories (logging, sessions, asset paths, error pages, etc.) get their
own subsections of the hash; what those categories are is part of what gets spec'd
out in this wishlist.

Open: directory-level settings probably live in a per-directory file (a la
`.htaccess`), but the format and conventions are TBD. Multiple nested directories
each get their own chance to override.

<a id="storage-agnostic-page-resolution"></a>
### 2.2 Storage-Agnostic Page Resolution

Pages live wherever they are stored. The installation does not require a
filesystem; pages can come from:

- A filesystem (the common case for larger installations)
- A mikobase (e.g., for IPC scenarios where no filesystem is needed)
- In-memory registrations (e.g., for testing or embedded scenarios)
- Remote fetches via the Puck protocol
- Generated on the fly

The installation asks "give me the page for this URL" and the site (or whoever
owns page storage at that level) answers. Robinson itself doesn't care which
backend a site uses.

<a id="installation-object"></a>
### 2.3 Installation Object

A Robinson **installation** is the HTTP-facing process — the thing that gets
called over HTTP. It owns:

- The HTTP listener (Unix socket when behind a reverse proxy, TCP when serving
  directly, possibly other transports later)
- The Charlie runtime (one long-lived interpreter for the installation's
  lifetime)
- The installation-level settings (cascade level 2, extending factory defaults)
- The set of sites it serves, plus the dispatch logic to route incoming
  requests to the right one (typically by `Host` header)
- The chain of request handlers (see below)

An installation is the second level of the settings cascade — between factory
defaults below and sites above. Whether the process is reached via a reverse
proxy, a direct TCP bind, or another transport is an implementation detail; the
installation's job is "speak HTTP and dispatch."

<a id="installationjson"></a>
#### 2.3.1 `installation.json`

The Robinson installation reads its configuration from `installation.json`.
The shape (initial version):

```json
{
    "sites": {
        "unotate": "/path/to/unotate-site-dir",
        "borg": "/path/to/borg-site-dir"
    }
}
```

The `sites` hash declares which sites this installation hosts.

- **Keys are arbitrary operator-facing labels** — they identify each site
  for the operator (in logs, in admin tooling, etc.) but carry no semantic
  meaning. The label `"unotate"` doesn't determine which domain the site
  responds to; the site's own `site.json` does.
- **Values are filesystem paths** to each site's directory. That directory
  contains the site's `site.json`, its content tree, and any
  per-site `messages/` overrides.

**Order matters.** When dispatching an incoming request by `Host` header,
Robinson walks the `sites` hash in insertion order and the first site
whose `domains` hash contains the requested host wins. The operator
controls precedence by ordering entries in `installation.json`.

**At least one site is required.** An installation with no sites can't do
anything useful; this is a configuration error at startup.

> **Revisit later**: the at-least-one-site rule is the current spec but
> Miko flagged this as a topic to come back to. Possible alternatives:
> some site-less mode (handlers serve everything without per-host
> dispatch), or installation-level pages outside the site hierarchy.
> Not in scope right now.

Resolved (from earlier open): **How sites get registered with an
installation.** Static config in `installation.json`. Dynamic
registration and discovery are not in scope for v1.

Open:

- Whether one installation can listen on multiple transports
  simultaneously (Unix socket *and* TCP, for example)
- Process model long-term — single process forever, or
  coordinator-of-workers later
- What happens if a path in `sites` doesn't exist or doesn't contain a
  valid `site.json` — almost certainly a startup error, but worth
  pinning the exact behavior (fail-fast vs. skip-with-warning)

<a id="request-handlers-middleware-chain"></a>
### 2.4 Request Handlers (Middleware Chain)

Every installation has **one or more request handlers** registered in an
**ordered hash**, keyed by nickname. Each handler is a modular object that can
implement up to three optional methods.

The hash representation is a convenience for developers: handlers are referred
to by nickname (`$server.handlers['csrf']`, `$server.handlers['sinatra']`)
rather than by position. The keys are purely labels — Robinson doesn't
interpret them or enforce any pattern. Because Puck hashes are order-sensitive
(see [hashes.md](../charlie/built-in-classes/hashes.md)), the handlers still
have a well-defined processing order; the hash just gives each one a memorable
identifier.

A request flows through the chain in three phases:

**Phase 1: `before_process(request)`** — runs on every handler in order. Used
mainly for security checks (CSRF, authentication, rate limiting, etc.). If any
handler raises an exception in this phase, the chain halts and the exception
becomes the response.

**Phase 2: `process(request)`** — runs on each handler in order. The handler
either:

- Returns a **response object** to claim the request
- Returns **null** to decline (pass to the next handler)

The **first handler that returns a non-null response wins**. Subsequent
handlers' `process` methods don't run. If every handler returns null, that's a
404. (Custom 404 pages are a separate concern, to be spec'd later.)

In almost all cases an unflavored null is sufficient when declining. Flavors
would only matter if a handler wanted to communicate *why* it declined to a
downstream observer.

**Phase 3: `after_process(response)`** — every handler gets a chance to refine
the response. Examples:

- A CSRF handler injects protection tokens into outgoing forms
- An HTML-tidying handler reformats the response body
- A compression handler gzips the body
- A logging handler records the final response

This three-phase chain dissolves the earlier "routing convention" question. There
is no single routing model in Robinson — routing is whatever a handler implements
internally. A Sinatra-style closure-based router is a handler. A Rails-style
class-based page resolver is a handler. A static-file server is a handler. They
all coexist on the same chain.

For light systems, a single Sinatra-style handler is enough. For larger systems,
the chain scales naturally: security at the front, several routing/processing
handlers in the middle (each owning different URL prefixes or content types),
and response-refinement handlers at the back.

Open:

- **`after_process` order**: same order as `before_process` (forward), or
  reversed (onion-style — first handler in is last handler out, common in Rack
  and Express)?
- **What if `process` raises** (not `before_process`)? Skip that handler and
  continue, or treat as a 500?
- **Can `after_process` replace the response entirely**, or only modify the
  existing one?
- **Where handlers are registered**: installation level, site level, both?
  Probably both — installation-wide handlers (logging, CSRF) plus site-specific
  handlers (routing).
- **Interaction with settings cascade**: handlers probably read settings from
  `%chain` at their level; details TBD.
- **Registration API**: plain hash assignment (`$server.handlers['csrf'] =
  $h`) appends at the end. Positional insertion (`insert_before`,
  `insert_after`) and removal need their own conventions — TBD.

<a id="concurrency-model"></a>
### 2.5 Concurrency Model

**Default behavior: single process, one request at a time, no forking.** No
opt-out from this; it's just what running Robinson means in the absence of
explicit configuration. A small site (or any site running on an engine that
hasn't been granted `%forks`) gets predictable single-process semantics for
free.

Concurrency is **doubly opt-in**:

1. **The engine must grant `%forks` permission** — without this capability,
   Robinson cannot fork, period. This is the same `%forks` engine permission
   documented in the Charlie runtime (`%forks` is `null` when the engine
   hasn't granted it). The developer cannot work around this from within the
   Robinson config; the host has to authorize it.
2. **The developer must opt into forking in Robinson's settings** — a
   configuration flag (working name: `enable_forking`) defaults to `false`.
   Even with `%forks` granted, Robinson runs single-process until told
   otherwise.

This layered default-no means a Robinson installation never accidentally
spawns child processes. The host controls the capability; the developer
controls the policy; both must agree.

<a id="prefork-pool-model-when-forking-is-enabled"></a>
#### 2.5.1 Prefork-Pool Model (when forking is enabled)

With both gates open, the main Robinson process becomes a supervisor:

- Forks N worker children, each a self-contained Charlie runtime with the full
  handler chain loaded
- Maintains a pool of "ready" workers (just-forked, no request handled yet)
- When a request comes in, hands it to a ready worker
- After the worker handles its one request, it **exits** by default
- The supervisor forks a replacement to keep the pool full

The fork cost is paid in the background by the supervisor, not synchronously
on the request path. Each individual worker is single-use, which means **no
state leaks between requests** — there's no surviving process to leak from.
This closes the entire category of vulnerabilities that plagued mod_perl and
CGI-Perl, where the persistent interpreter occasionally leaked data from one
request into another.

<a id="worker-recycling-opt-in-within-the-opt-in"></a>
#### 2.5.2 Worker Recycling (opt-in within the opt-in)

A third configuration option (working name: `recycle_workers`) lets developers
opt into the classic prefork-pool behavior: each worker handles many requests
before exiting. This trades isolation for performance — fork+init cost is paid
once per worker rather than once per request.

- **Default**: `recycle_workers = false` — every worker is single-use.
  Maximum isolation, no inter-request leakage.
- **Opt-in**: `recycle_workers = true` (with an associated max-requests-per-worker
  cap to bound memory growth). Suitable for high-traffic sites where the
  trust boundaries are elsewhere (e.g., reverse proxy enforces auth, each
  request is independently authenticated).

So three layers of opt-in to reach the lowest-isolation / highest-performance
mode: engine grants `%forks`, developer sets `enable_forking = true`,
developer sets `recycle_workers = true`. Each layer defaults to "no." This is
"secure by default, opt out for performance," consistent with the overall
Puck no-nanny-code principle: safe defaults with explicit, greppable
overrides.

Open:

- Whether the supervisor should also support multiple transports per process
  (e.g., one pool serving both a Unix socket and a TCP port)
- Whether dying workers should be subject to circuit-breaker logic (if workers
  keep dying on the same kind of request, stop trying)
- Pool sizing: static `N` at startup, or autoscale based on queue depth?
- What happens to in-flight requests during a graceful shutdown — wait, kill
  after a grace period, drop immediately?

<a id="sinatra-method-selectors"></a>
### 2.6 Sinatra Method Selectors

> **Feature lock.** Sinatra is locked for v1. It's intended for **simple
> cases** — single-file sites, microservices, small internal tools — not
> expansive multi-host sites with admin tooling. The fancier features
> Robinson covers (sites, admin authentication, per-host dispatch,
> `site.json`, canonical redirects, factory message overrides, etc.) do
> **not** apply to Sinatra-only servers. May revisit if a real use case
> surfaces; for now, Sinatra's surface is what's specified here.

A bare `%puck['puck.uno/Robinson'].new()` returns an **empty server** — no
handlers, no routes, nothing registered. To get the Ruby-Sinatra-style
method-selector API, opt into the **Sinatra handler**:

```
$server = %puck['puck.uno/Robinson'].new(sinatra: true)

$server.get('/') do($request)
    response.new(200, {content_type: 'text/plain'}, 'Hello world')
end

$server.get('/shakespeare/{play}/') do($request)
    # path parameter captured as $request.steps['play']
    response.new(200, {content_type: 'text/html'}, render_play($request.steps['play']))
end

$server.post('/shakespeare/{play}/') do($request)
    # POST to the same path is a separate registration
end

$server.run() do($request)
    # only reached if no method+path registration caught the request.
    # if no do block here, or the do block doesn't return a response,
    # Robinson returns a 404.
end
```

The handler is named **Sinatra** after Ruby Sinatra, whose method-selector
style Robinson borrows.

Each HTTP method has its own selector — `get()`, `post()`, `put()`, `delete()`,
`patch()`, `options()`, `head()`. A registration matches when **both** the HTTP
method and the URL path match the incoming request. The same URL with
different methods is fine — they're independent registrations.

Three things are happening:

- **`.new(sinatra: true)`** — instantiate a Robinson server with the Sinatra
  handler pre-registered under the `'sinatra'` key in the handler hash.
- **`$server.<method>('/path') do ... end`** — register a closure to handle a
  specific HTTP method at a specific URL path. The closure runs when an
  incoming request matches both.
- **`$server.run() do ... end`** — start the server. The optional `do` block
  acts as a **catch-all fallback** — reached only when no method+path
  registration matched. Without a fallback block (or with one that doesn't
  return a response), an unmatched request becomes a 404.

<a id="sinatra-true-is-just-sugar"></a>
#### 2.6.1 `sinatra: true` Is Just Sugar

The opt-in keyword is shorthand for what you could do manually: instantiate a
Sinatra handler, add it to the handler hash under the `'sinatra'` key, and
delegate the method selectors (`$server.get`, `$server.post`, etc.) to that
instance. Nothing about the wiring is special-cased inside Robinson — the
keyword just saves you the three lines.

If another handler wants to expose its own server-object shortcuts later,
it'll use the same delegation mechanism. There's no privileged path here.

<a id="built-in-error-pages"></a>
#### 2.6.2 Built-in Error Pages

The Sinatra handler ships with a **standard set of error pages** — 404, 500,
and the other common HTTP status conditions — rendered with plain, sensible
defaults. These error pages are **not configurable**. They are part of what
Sinatra gives you; take them as-is when you use it.

For small installations this is adequate — most personal sites, internal
tools, and prototype services never need a custom 404 page, let alone the
others. The plain defaults look professional enough and require zero work
from the developer.

For installations that need branded or custom error pages, don't opt into
Sinatra (or replace it with a customized equivalent). Once you're past
Sinatra's scope, you take responsibility for your own error handling.

Key design properties:

- **Simple things simple**: a small site is a single file, a handful of
  `get()` / `post()` calls, and `run()`. No subclassing, no config files, no
  directory conventions.
- **Complex things possible**: when a site outgrows the closure-per-route
  pattern, developers register their own handlers in the chain (Rails-style
  page classes, static-file servers, custom middleware) alongside or
  instead of Sinatra, without abandoning what's already there.
- **Catch-all in `run()`**: the fallback handler lives in the `run()` call
  itself rather than being a separate registration. Reads naturally as "start
  the server, and if nothing else handles it, fall through to this."
  For small use cases, the `run()` block may be all that's necessary.
- **Path parameter capture**: path segments wrapped in `{name}` are captured
  and exposed to the closure as `$request.steps['name']`. Example:
  `/shakespeare/{play}/{act}/{scene}` captures three values.
- **Ruby-Sinatra-style placeholders are a stated goal (not a hard requirement)**:
  the Sinatra handler aims to support the same kinds of placeholders Ruby Sinatra
  supports — named captures, splat patterns (`*`), and similar matchers — so
  that anyone familiar with Ruby Sinatra recognizes the route patterns
  immediately. The specific syntax differs (we use `{name}` rather
  than Ruby Sinatra's `:name`), but the semantics aim for parity. This is **a
  goal, not a requirement**: if implementation pressure makes any specific
  Sinatra-style pattern hard to support, it can be simplified or dropped
  without breaking the design. Parity in spirit, feature-by-feature as
  practical.

Open:

- **Specific placeholder set**: the Sinatra-style goal covers named captures
  (`{name}`) and splat (`*`) at minimum. Trailing-slash semantics, regex
  patterns, optional segments, file-extension matches, etc. are each a
  separate "do we support this?" decision.
- **Ordering and precedence**: if two registrations could match (e.g.
  `/user/{id}` and `/user/edit`), which wins? Specificity-based (literal beats
  parameter), registration-order, or both?
- **Multiple closures per method+path**: allowed? If so, do they all run, or
  first matching, or chain?
- **A method-agnostic `all(...)` or `any(...)`**: convenience for routes
  that handle every HTTP method, or stay strictly per-method?

<a id="json-url-parameters"></a>
### 2.7 JSON URL Parameters

Robinson will natively support the
[ecoverse JSON URL convention](../puck/json-urls.md): machine-generated
URLs that pass parameters as a JSON object in the query string
(`?{"map":true}`) rather than as conventional `?key=value` pairs.

Handlers receive parameters through a unified hash regardless of how
the URL was formed. Robinson's request layer:

1. Inspects the raw query string.
2. If it begins with `{` (after URL-decoding), parses it as JSON.
3. If it's conventional `?key=value`, parses it as such.
4. If it's a mix (`?{"map":true}&debug=1`), parses both halves and
   merges them into one hash.

Handlers see one parameter hash; the URL form is transparent to them.

Specific rules for mixing (parser order, precedence on key
collisions, cache-key canonicalization, edge cases) are TBD —
captured in [json-urls.md](../puck/json-urls.md) as a topic to revisit
when the JSON-URL convention is fully spec'd.

<a id="closure-interface-and-response-objects"></a>
### 2.8 Closure Interface and Response Objects

Handler closures (the `do ... end` blocks passed to `$server.get`,
`$server.post`, etc., and similarly the catch-all on `$server.run`) take a
single explicit parameter: the request.

```
$server.get('/') do($request)
    response.new(200, {content_type: 'text/plain'}, 'Hello world')
end
```

**The request is immutable.** Handlers read it but cannot mutate it. Any
transformation a handler wants to communicate to later handlers in the chain
goes through a different channel (TBD — possibly a per-request scratch
hash, possibly explicit context-passing). Mutating the request itself is
not how Robinson plumbs information forward.

**The closure must return a response object** — an instance of
`puck.uno/Robinson/response` (or whatever the final UNS turns out to be).
Returning `null` is how a handler declines (passes to the next handler in
the chain). Anything else must be a response.

<a id="the-response-bareword-dsl"></a>
#### 2.8.1 The `response` Bareword DSL

Inside handler closures, the bare identifier `response` is a DSL alias for
the response class. So instead of:

```
$server.get('/') do($request)
    %puck['puck.uno/Robinson/response'].new(200, {content_type: 'text/plain'}, 'Hello world')
end
```

you write:

```
$server.get('/') do($request)
    response.new(200, {content_type: 'text/plain'}, 'Hello world')
end
```

The DSL is scoped to handler closures specifically — it's not a global
alias. Outside a handler closure, you go through `%puck[...]` as usual.

<a id="constructor-shape-sketch"></a>
#### 2.8.2 Constructor Shape (Sketch)

The response constructor takes three positional arguments:

```
response.new(<status>, <options>, <body>)
```

- **Status** — HTTP status code as integer (`200`, `404`, `500`, etc.)
- **Options** — a hash of response-level settings (`content_type`,
  `headers`, anything else that affects how the response is serialized).
  Specific keys TBD.
- **Body** — the payload. String for character content, byte buffer for
  binary content, structured data (hash/array) for JSON content with the
  appropriate content type. Serialization handled by Robinson; charset
  appended automatically per the UTF-8 rules.

<a id="implicit-last-value-return"></a>
#### 2.8.3 Implicit Last-Value Return

The simple case ends with the response expression — no `%call.return`
needed, because closures return their last value naturally:

```
$server.get('/') do($request)
    response.new(200, {content_type: 'text/plain'}, 'Hello world')
end
```

The verbose form below works but adds clutter for no benefit. Don't write
it this way in examples or documentation:

```
$server.get('/') do($request)
    %call.return response.new(200, {content_type: 'text/plain'}, 'Hello world')
end
```

Reserve `%call.return` for actual early exits — when there's code below
the return that would otherwise run.

Open:

- **Where the `response` DSL is available**: confirmed for Sinatra-style
  closures. Should the same DSL appear inside custom handlers' `process`
  methods? Likely yes (parity), but worth pinning explicitly.
- **Specific options-hash keys**: `content_type` is the obvious one;
  `headers`, `cookies`, `cache_control`, etc. each need their own
  decision.
- **Convenience constructors**: e.g. `response.json(200, $data)`,
  `response.redirect(301, '/new-path')`, `response.text(200, 'hi')`. Worth
  having, but the canonical form is the three-arg `response.new(...)`.
- **How the request communicates immutability**: trust-based (developer
  follows the rule) or runtime-enforced (request is a frozen object that
  raises on mutation)? Frozen-object enforcement matches the no-nanny
  principle better — fail loudly if a handler tries to mutate.

<a id="robinson-handler-filesystem-tree-pages"></a>
### 2.9 Robinson Handler (Filesystem-Tree Pages)

A separate handler for sites structured along an actual file tree. Every
file in a directory tree corresponds to a page at the matching URL path —
the layout *is* the routing. Old CGI vibes, but with a much wider toolbox
for customizing the request and response than CGI ever offered.

(Origin story in [ramblings.md](ramblings.md). Short version: Robinson is
the name of a Ruby library still running unotate.com, named after the
author's old high school.)

<a id="terminology-installation-means-two-different-things"></a>
#### 2.9.1 Terminology: "Installation" Means Two Different Things

Two scoped meanings of "installation" coexist and shouldn't be confused:

- A **Robinson installation** is the outer server process — the HTTP-facing
  daemon. It has a home directory for its own use (logs, config, sockets,
  etc.), but the Robinson installation isn't *defined by* that directory;
  it's defined by being the running server.
- A **Robinson installation** (also called a **Robinson instance**) **is a
  directory**. One Robinson instance lives in exactly one root directory
  — that directory and everything underneath it is what the instance
  serves. The instance and the directory are the same thing in different
  words.

A single Robinson installation can host multiple Robinson instances if it
wants (one per site, or several within one site rooted at different
subpaths) — each pinned to its own root directory.

<a id="design-pressure-keep-the-basic-install-simple"></a>
#### 2.9.2 Design Pressure: Keep the Basic Install Simple

The previous Robinson (Ruby) eventually accumulated so many bells and
whistles that it *felt* too complicated, even when each individual feature
was legitimately useful. This isn't quite feature creep — the features were
real — it's that the cumulative surface area got intimidating. A new
developer opening the docs would see too many concepts at once and bounce.

Robinson must guard against this. Two rules:

1. **The basic installation stays very simple.** A directory of `.charlie`
   files and static assets, serving pages. Nothing else. Anyone can sit
   down and have a site running in minutes without learning a vocabulary.
2. **Introduce features carefully.** Every feature beyond the basic install
   has to justify the cognitive cost it adds. Where possible, advanced
   features stay out of sight until the developer goes looking for them
   (separate docs page, optional config, etc.). The first-impression
   surface area must stay tight.

This is a design pressure, not a hard rule about what features exist. Many
features will still land in Robinson — but the front door stays narrow.

<a id="page-file-contract"></a>
#### 2.9.3 Page File Contract

`.charlie` files in the tree are page files. Each one's last expression
must be a class inheriting from `puck.uno/Robinson/page` with a `process`
method. Robinson invokes the file, takes the returned class, instantiates
it, calls `process($request)`, and uses the returned response as the
page's response.

The class lives in the file and has no UNS — its identity is its location
in the tree. Giving it a global name would defeat the point of filesystem-
tree routing.

Invocation uses the Charlie runtime's general
[file-invocation model](../charlie/modules.md#invoking-a-file): a file is
invoked like a function call, runs in its own scope, returns the value of
its last expression. Robinson doesn't need a special invoker — it just
uses the standard invocation and expects the value to be a
`puck.uno/Robinson/page` subclass. (Page files that return something
else get a clear error.)

Note the deliberate distinction: Robinson **invokes** the file (runs it as
a function, captures the return value). "Load" is a different word for a
different operation (slurping bytes into memory) and isn't used here.

For the invocation to succeed, the site root jail must have
[execute permission](../charlie/built-in-classes/filesystem.md#jail-permissions) enabled.
Execute is off by default on jails (no dangerous defaults), so a Robinson
site root is configured at injection time with `read + execute` (plus
`write` if the site needs to author files at runtime — usually not).

Other file types in the tree (images, static HTML, CSS, JS, etc.) are
served as-is, with content type inferred from extension.

<a id="path-resolution"></a>
#### 2.9.4 Path Resolution

URLs map to files inside the site's root directory using **jail-based
lookup**. The site root is exposed to Robinson as a
[jail](../charlie/built-in-classes/filesystem.md) — a directory-scoped handle that
permits access only to the site root and everything underneath it. The
underlying real filesystem path is never exposed to handler code.

Resolution flow:

1. **Determine the request shape.** A path with no trailing slash is a
   *file request* (`/foo/bar`). A path with a trailing slash is a
   *directory request* (`/foo/bar/`). These are **distinct concepts**;
   `/foo/bar` and `/foo/bar/` are different requests, not the same URL
   with sloppy formatting.
2. **Hand the path to the site jail** via
   [`$jail.use_path`](../charlie/built-in-classes/filesystem.md#authorizing-untrusted-paths).
   This is required (untrusted strings can't be used for FS ops
   directly) and normalizes the path automatically. Robinson does not
   pre-normalize.
3. **Reconcile request shape with what's at the path**:
   - File request + entry is a file → serve it (invoke if `.charlie`,
     otherwise serve as static).
   - **File request + entry is a directory → 302 temporary redirect**
     to the path-with-trailing-slash. Keeps URLs canonical without
     guessing at the developer's intent.
   - Directory request + entry is a directory → serve the directory
     (what that means — index file, listing, 404 — is open below).
   - Directory request + entry is a file → symmetric case, behavior
     TBD.
   - Entry doesn't exist (missing or unsafe) → 404.

```
$entry = $jail.use_path($request.path)
# reconcile request shape with $entry's type per the table above
```

By the time Robinson sees `$request.path`, it has already been
URL-decoded — that's an HTTP-layer concern handled when the `$request`
object is built. `use_path` then performs filesystem-side normalization
(collapsing `//`, resolving or rejecting `.`/`..`, rejecting control
characters, etc.). Robinson stays out of normalization entirely.

**Directory traversal is not Robinson's concern.** The jail (via
`use_path`'s normalization plus the jail's own boundary check) refuses
any path that would escape root. Robinson doesn't implement traversal
protection; it inherits it from the runtime primitive.

Resolved (above): **Trailing slash semantics.** Distinct paths; file-request-
on-directory triggers a 302 redirect to the slash form.

Open:

- **What "serving a directory" means.** When a directory request hits
  an actual directory, what does Robinson return? Three options:
  index file (`index.charlie`, `index.html`, etc. by priority),
  directory listing, or 404 (no automatic content). Probably index
  files, but the priority list and listing-by-default question are
  unsettled.
- **Directory request resolves to a file.** Symmetric to the file-to-
  dir 302 case — probably a redirect to the no-slash form. Confirm.
- **Dotfile handling.** Files starting with `.` — served or hidden?
  `.git/` and `.env` should presumably never be served. `.well-known/`
  probably should.

<a id="reserved-filename-prefix-robinson"></a>
#### 2.9.5 Reserved Filename Prefix: `robinson.`

Robinson **refuses to respond to any HTTP request whose target name
starts with `robinson.`**. The prefix is a reserved namespace for
Robinson's own internal artifacts — config files, state, scratch
content, internal Charlie files that Robinson itself invokes.

**The rule is about the request boundary, not the file's existence.**
A file at `<site>/robinson.config.json` is perfectly fine on disk and
may be actively used by Robinson internally (read, written, even
invoked as a Charlie file in some internal context). What's prohibited
is **a request from outside resolving to that path** — that request
gets a 404 regardless of whether the file exists or what it contains.
Robinson's own internal access to these files happens through different
code paths than the HTTP request flow.

The rule runs at path resolution, before any handler dispatch. The 404
is indistinguishable from a missing file; no information disclosure
about whether the underlying object exists.

- **Blocked from request**: `robinson.json`, `robinson.lock`,
  `robinson.charlie`, `robinson.html`, etc.
- **Not blocked**: `robinson` (no trailing dot), `robinsons.json`
  (prefix is `robinsons.`, not `robinson.`), `my-robinson.json` (prefix
  not at start of name).

This is one of the few hardcoded special-case rules in Robinson. Not
overridable by any handler.

Open:

- **Case sensitivity.** Should `Robinson.json` and `ROBINSON.json` also
  be blocked? Probably yes (case-insensitive match) for cross-platform
  consistency, since case-insensitive filesystems would otherwise let
  developers bypass the rule by accident.
- **Path segments vs. file names only.** Does the rule apply to
  directory names too? E.g., should `/foo/robinson.config/data.html`
  also 404? Conservative answer: any path segment starting with
  `robinson.` blocks the whole request.
- **Case sensitivity.** Filesystem is case-sensitive on Linux,
  case-insensitive on macOS; URLs are case-sensitive in HTTP spec.
  Normalize or pass through?
- **Specific filesystem-path normalization rules.** Lives in
  `use_path`, not Robinson. Worth pinning the canonical list in
  [filesystem.md](../charlie/built-in-classes/filesystem.md) when the runtime gets
  spec'd in detail. URL decoding is upstream (HTTP layer, when
  `$request.path` is built), not part of `use_path`.

<a id="sites"></a>
#### 2.9.6 Sites

A Robinson installation can have **zero or more site objects**. A site
typically represents a single URL — `unotate.com`, for example.

<a id="domain-mapping"></a>
##### 2.9.6.1 Domain Mapping

A site declares its domains in `site.json` under a `domains` hash.
At least one domain is required:

```json
{
    "domains": {
        "www.idocs.com": true,
        "idocs.com": true
    }
}
```

The first key is the **canonical domain**. Requests arriving on any
other listed domain receive a **301 permanent redirect** to the
canonical (same path, same query string). So a request to
`idocs.com/foo?bar=baz` redirects to `www.idocs.com/foo?bar=baz`.

Puck hashes preserve insertion order, so the "first key is canonical"
rule works the same as it would with an array.

Compared to nginx or Apache — where canonical redirects are separate
config blocks layered on top of server blocks — declaring the domains
in order *is* the entire configuration.

**Truthiness rule**: any truthy value enables the domain. `true` is
the conventional choice. The hash structure leaves room for per-domain
settings later (replace `true` with a settings object) — but nothing
currently needs that, and there's no concrete plan to use it. Start
with `true` and upgrade only if a real need surfaces.

**Why a hash instead of an array**: arrays don't leave a clean place
for future per-item metadata without a structural change. Hash-with-
truthy-values is forward-compatible — growing into
`{ "domain": {settings...} }` is non-breaking if needed.

**No placeholders or wildcards.** Every domain a site serves is listed
explicitly. No `*.idocs.com`, no regex.

Resolved (from earlier open): **Relationship to Robinson-level sites.**
Robinson sites are the things Robinson dispatches to. The Robinson
installation reads each Robinson site's `domains` list and routes
incoming requests by `Host` header. No separate Robinson-level site
registry.

Open:

- **Scheme handling**: does the canonical redirect normalize scheme
  (HTTP → HTTPS) in addition to hostname? HTTPS termination is usually a
  reverse-proxy concern, so probably hostname only. Worth pinning.
- **Domain overlap across sites**: if two sites in the same Robinson
  installation declare the same domain, what happens? Two reasonable
  options, both consistent with the project's principles:
  - **First match wins** — since `installation.json` is order-sensitive,
    the operator chose the order; respect it. Silent but predictable.
  - **Startup error (fail loud)** — overlap is almost always a config
    mistake; refuse to start and surface it.
  Probably the latter is safer; the operator can always reorder.
- **Unknown-domain requests**: a request arriving on a domain no site
  claims — 404, decline to the next handler in the chain, or an
  installation-level fallback? Probably decline.
- **What "zero sites" means**: a Robinson instance with no sites —
  declines every request? Returns a 404? Spec it when we get there.

<a id="empty-site-welcome-page"></a>
#### 2.9.7 Empty Site Welcome Page

When a Robinson site has **zero servable files**, requests get a
built-in welcome page instead of a 404. Purely a first-run convenience
— confirms the framework is alive on the right host before any content
exists.

**Bounding rule**: the welcome page appears only when the site is
genuinely empty. The moment any file is added (even an empty
`index.charlie`), it disappears permanently for that site. Missing URLs
then return 404 the normal way.

This rule keeps it safe to ship by default: the welcome page cannot
appear in a working production deployment — only during dev setup or in
a deployment that's genuinely broken (nothing got copied). The latter
needs fixing anyway; the welcome page is decent diagnostic signal that
it did.

**Displayed content (deliberately minimal):**

- The requested host (e.g., `unotate.com`) — confirms what Robinson
  received in the `Host` header.
- Nothing else.

No site root path, no version, no request path, no "next steps." This
follows the [No Dangerous Defaults](#no-dangerous-defaults) stance: any
extra information is potential leakage if the page ever shows on a
misconfigured production deployment. The host alone is cheerful useless
information — a happy sense that you've got the server on the right
domain — with no diagnostic value to anyone with bad intentions.

**Other rules:**

- Visually obvious as a placeholder. Not styled to look like real
  content.
- No configuration knob to disable it. To turn it off, add a file.

Open:

- Exact page text and structure — TBD.
- Content negotiation: does a JSON-only request to an empty site get
  JSON or HTML? Probably HTML; empty-site is a setup scenario, not an
  API scenario.

<a id="factory-message-pages"></a>
#### 2.9.8 Factory Message Pages

> **Feature lock.** This subsection is closed to new features. The
> previous Robinson iteration went down a rabbit hole on customized
> messages; the design here is deliberately constrained to what's already
> specified. New ideas about customized messages get filed as Deferred or
> declined — not added to the spec.

Robinson ships with a **factory** that owns default content for error
responses. The factory contains a `messages/` directory with one
parameterized template per content type — not one file per status code.
Each template has placeholders for the status code and a message string,
filled in at render time.

A site overrides any factory template by dropping its own version in the
site's `messages/` directory. Lookup is **per-file**: site first, factory
fallback. Override one template without touching the others.

This is a **deliberately narrow** version of the broader "auxiliary site"
concept (see Deferred Ideas below). One specific directory name, one-deep
fallback, one template per content type.

<a id="the-templates"></a>
##### 2.9.8.1 The Templates

The factory ships these files in `messages/`:

- **`message.html`** — HTML, the general fallback.
- **`message.svg`** — SVG image, served when the request only accepts
  image types. Text-based, so placeholders work the same as HTML.
- **`message.json`** — JSON envelope, shape `{"status": <code>, "message":
  "<text>"}`. Served when the request accepts JSON.
- **`message.txt`** — Plain text, status and message appended at the end.

<a id="content-negotiation-non-200-responses"></a>
##### 2.9.8.2 Content Negotiation (Non-200 Responses)

When returning a non-200 response, Robinson matches the request's
`Accept` header against the available templates and picks the best fit:

1. Image-only Accept → `message.svg`
2. JSON-accepting → `message.json`
3. Plain-text-accepting → `message.txt`
4. Anything else (including the catch-all `*/*`) → `message.html`

If the client's Accept header matches none of these, Robinson serves the
HTML anyway. The client gets a valid HTTP response and deals with it.

Scope: this targets **error responses (4xx, 5xx)**. Redirects (3xx)
typically have no body and bypass this machinery.

<a id="no-coddling-stance-on-json-errors"></a>
##### 2.9.8.3 "No Coddling" Stance on JSON Errors

The JSON shape is deliberately simple — `{"status": <code>, "message":
"<text>"}`. Robinson does not add error sentinels, "is_error" flags, or
content-type tricks to protect clients from their own laziness. The HTTP
status code is the canonical error signal; clients that don't check it
are making a choice. The `{status, message}` shape is a mild courtesy:
it reads more like an error envelope than a resource representation, so
the most obvious foot-gun is somewhat mitigated. Beyond that, no
coddling.

Warning to site authors: a site-level `message.json` ships its entire
contents to the world. Don't put anything in that file that you don't
want public.

<a id="admin-exception-display-v1-core"></a>
##### 2.9.8.4 Admin Exception Display (v1 core)

When an exception is raised during request handling, the exception info
can be displayed *to authenticated admins only*. `message.html` carries
a placeholder for this — empty for non-admin requests, populated for
admin requests with the same content that goes to the error logs
(logging spec'd separately).

This is a **core v1 requirement**, not a deferred extension. Dogfooding
puck.uno on Robinson means we'll hit exceptions during early
development and need them visible without surgery. The feature pays for
itself immediately.

Rules:

- **Admins only.** The placeholder renders the exception content only
  when `$request.admin` is truthy. For everyone else it produces
  nothing. There's no toggle, no debug mode, no environment flag — the
  gating is the admin recognition, full stop. Stack traces and internal
  details to the public is the failure mode this is built to prevent.
- **HTML only** (in v1). SVG, JSON, and TXT don't include exception
  info. An admin debugging an error reaches for the HTML response;
  machine clients receive the same bare `{status, message}` whether
  they're admin or not. Can be revisited later if a real need surfaces.
- **Same content as the error log.** Whatever gets logged is what
  appears in the placeholder. One source of truth. Specific contents
  (message, stack, request snapshot, etc.) are part of the logging
  spec, which comes later.

Open:

- **Placeholder name in the template** (e.g., `{exception}`,
  `{admin_exception}`) — TBD.
- **Rendering format inside the placeholder**: pre-formatted text,
  collapsible sections, etc. — keep it tight; this isn't a debugging
  UI, it's an inline log dump.

<a id="open-questions"></a>
##### 2.9.8.5 Open Questions

- **Placeholder syntax** for templates: simple `{status}` / `{message}`
  substitution, or something more structured? Keep it tight either way.
- **Accept-header matching strategy**: simple substring match in fixed
  preference order versus full `q=` quality-value parsing. Probably the
  simple version is sufficient.
- **Where the message string comes from**: standard HTTP phrase as
  default (`"Not Found"` for 404), with per-response override available
  to dynamic pages.
- **Where the factory lives physically**: shipped with Robinson.
  Concrete path / packaging TBD.
- **Other shipped categories beyond `messages/`**: probably none — keep
  the factory tight.

<a id="admin-authentication"></a>
#### 2.9.9 Admin Authentication

A ready-made tool for authenticating admins and recognizing them across
subsequent requests on a site. Robinson ships this — auth is hard to get
right and rolling-your-own is a known foot-gun, so the framework
provides a known-good answer instead.

**Off by default.** A site has no admins until its `site.json` declares
some. There is no built-in admin account, no factory-shipped credentials,
no "root" user. Until a developer explicitly adds an entry to the
`admin` hash, `$request.admin` is always `null` and admin-gated features
(like the exception placeholder) produce nothing. This follows the
framework's [No Dangerous Defaults](#no-dangerous-defaults) rule.

**Status**: the basics go into the first release. Fancier extensions
(MFA, password rotation policies, admin management UI, etc.) stay out;
the v1 surface is what's specified here.

The surface is intentionally narrow — *admins only*, not end-user
sessions, public-facing accounts, OAuth flows, or general user
authentication. End-user auth is a separate concern outside the
framework. Admin auth is the specific case of "this operator has
elevated privileges on this site."

Shape:

- **Setup**: per-site, manual. Each site's configuration file (working
  name: `site.json`) has an `admin` hash mapping usernames to hashed
  passwords:

  ```json
  {
      "admin": {
          "stuart": "<hashed password>",
          "miko": "<hashed password>"
      }
  }
  ```

  Operators add an admin by hashing the password and editing the file.
  No self-serve registration, no admin-recovery flows, no built-in
  password-change UI, no admin-management web interface. Editing the
  file is the bar.

  Each site has its own admin list; different sites on the same
  Robinson installation have entirely separate admins. There's no
  global admin registry.
- **Login**: a simple login flow against those credentials.
- **Recognition**: once authenticated, the admin is recognized on
  subsequent requests within the session. Page code accesses
  `$request.admin` at any point during request handling:

  - Returns `null` if no admin is authenticated for this request.
  - Returns a **meta-info hash** if an admin is authenticated. The
    hash is *usually empty* — the bare existence of the value is what
    signals "an admin is present." Specific keys are TBD; the hash
    carries username or other admin context only when a page needs it.

  Typical usage is a truthy check:

  ```
  if $request.admin
      # admin-only behavior here
  end
  ```

  `$request.admin` is a property access (not a method call) — no
  parentheses, no `?` suffix. Reads cleanly as "ask the request who the
  admin is."

Open:

- **Hash algorithm**: bcrypt, argon2, scrypt — pick something strong
  and standard. The default must not be a fast hash; passwords
  shouldn't be brute-forceable from a config file leak.
- **Helper for hashing**: a CLI or runtime utility for generating the
  hash to paste into `site.json`. Operators won't roll their own hash
  calls.
- **Session mechanism**: cookies, signed tokens, server-side session
  store, etc. — TBD.
- **Meta-info hash contents**: the keys eventually exposed on the
  recognition hash (username, login timestamp, role tags, etc.). Default
  is empty; specific keys spec'd as needs arise.
- **Site configuration file**: the `site.json` reference here is the
  first hint of a per-site config file. The broader shape, format,
  and location of that file is a separate spec discussion not yet had
  in this wishlist.
- **Relationship to admin tooling** (still deferred — see Deferred
  Ideas): when admin-site or admin-handler is revisited, admin auth is
  the gate.

<a id="deferred-ideas"></a>
#### 2.9.10 Deferred Ideas

These are captured for future consideration but **not planned for v1**.
The reasoning is that they each have either a simpler alternative or no
strong current use case to justify the complexity.

**General auxiliary-site cascade.** The broader version of the factory-
messages mechanism: any site can declare any other site as an auxiliary,
and lookups fall through the chain. Deferred because the two motivating
use cases (factory messages, admin tooling) are better served by narrower,
more specific mechanisms. Revisit if a use case arises that *only* the
general cascade can solve cleanly.

**Admin site as auxiliary.** The idea of an admin toolbox that piggybacks
on every site through the auxiliary mechanism. Deferred entirely. The
admin-via-fallthrough approach mixes admin URLs into the main site's
namespace, which makes auth gating and URL discovery harder than they
need to be. If/when admin tooling lands, likely paths to evaluate at
that time:

- A separate URL prefix at the Robinson level (e.g. `/Robinson-admin/*`
  regardless of site), with its own auth boundary.
- A dedicated admin handler in the handler chain, alongside Robinson
  rather than inside it.

**RFC 7807 / `application/problem+json`.** The IETF standard for richer
JSON error responses, with structured fields (`type`, `title`, `detail`,
`instance`) and a dedicated content type that explicitly marks a
response as an error rather than a resource. Deferred — the simple
`{status, message}` shape is enough for current needs. If real-world
demand for richer JSON errors materializes, evolving toward RFC 7807 is
a clean migration rather than a redesign (the simple shape is a strict
subset of Problem Details with the same `status` field).

Specifics to be filled in as features are described.

---

<a id="open-questions-cross-cutting-concerns"></a>
## 3 Open Questions / Cross-Cutting Concerns

(For things that affect multiple features, design tensions, or "we'll figure it out
when we get there" notes.)

---

<a id="prioritization"></a>
## 4 Prioritization

(Empty for now. Filled in once the feature list stabilizes — typically with three
buckets: in v1, deferred to later, dropped or unlikely.)
