# HTTP Middleware

~~~json
{"vibecode": {
	"doc": "http-middleware",
	"role": "index of Puck's HTTP middleware classes: which ship in core (Touchstone, Sinatra), which are library-resolved (Robinson), which are deferred (Dogberry); explains the no-layered-servers architecture",
	"key_concepts": ["touchstone_base", "sinatra_core", "robinson_library",
		"dogberry_deferred", "no_layered_servers", "library_resolution"]
}}
~~~

Puck covers HTTP servers in two tiers: a small set of classes that
**ship with Puck** (always available out of the box) and a larger
set that are **available as libraries** — resolved on demand through
the Puck object model the same way any other library is, with no
install step.

<a id="ships-with-puck"></a>
### 0.1 Ships with Puck

| Class | UNS | Use case |
|---|---|---|
| **Touchstone** | `puck.uno/touchstone` | Base class. Content-type defaults, Jasmine integration, shared HTTP plumbing. Sinatra (and any HTTP middleware library) inherits from it; not for direct instantiation. |
| **Sinatra** | `puck.uno/sinatra` | Small sites, microservices, single-file apps. Route handlers as closures, Ruby-Sinatra-style. |

<a id="available-as-a-library-through-puck"></a>
### 0.2 Available as a library through Puck

| Class | UNS | Use case |
|---|---|---|
| **Robinson** | `puck.uno/robinson` | Filesystem-tree-served sites. Pages live as files in a directory tree; URL paths map to file paths. **Not bundled — Puck resolves and caches it on first use** (see [puck.md](../../puck/puck.md) for the resolution + caching model). |

<a id="deferred"></a>
### 0.3 Deferred

| Class | UNS | Use case |
|---|---|---|
| **Dogberry** | `puck.uno/dogberry` | A more elaborate framework, planned for later releases. May turn out to be a very different sort of thing. Likely also library-resolved when it lands. |

The point of the split: **Puck's core stays small.** Touchstone +
Sinatra is enough to serve HTTP responses; everything beyond is
opt-in via library resolution. A Charlie program that doesn't need
Robinson never pulls Robinson in.

<a id="architecture"></a>
## 1 Architecture

**No layered servers.** Sinatra and Robinson are not "handlers
inside Dogberry" — they're standalone servers. You pick the one
that fits your use case and use it directly. The fact that one
ships with Puck and the other arrives via library resolution
doesn't change the API: both are obtained through `%puck[...]`,
just with different resolution paths under the hood (Sinatra is
already in the engine's built-in table; Robinson is fetched from
its UNS source the first time it's referenced, cached locally for
subsequent calls).

```
# A simple Sinatra-style app — Sinatra ships with Puck
$server = %['puck.uno/sinatra'].new()
$server.get('/') do($request)
    response.new(200, {}, 'Hello world')
end
$server.run()
```

```
# A filesystem-tree-served Robinson site — Robinson is resolved
# via Puck on first use, then cached for subsequent runs
$server = %['puck.uno/robinson'].new(root: '/var/www/mysite')
$server.run()
```

This is a deliberate departure from the earlier "Dogberry as the
framework, Sinatra/Robinson as handlers" model. The current model
keeps each server simple and self-contained; Dogberry's eventual
shape will be designed without being constrained to slot Sinatra
and Robinson in as components.

<a id="picking-one"></a>
## 2 Picking one

- **Sinatra** if your app is mostly a handful of routes — closures
  that respond to HTTP methods and paths. Default for "I just need
  a few endpoints."
- **Robinson** if your content lives as files in a directory tree
  with page-style behavior (templates, metadata, etc.).
- **Dogberry** when it ships and we know what it is.

Touchstone isn't on this list — it's the base class. You wouldn't
instantiate it directly.

The three are not competing for the same use cases. They occupy
different points in the spectrum from "ad-hoc per-route code" to
"content-as-files" to (eventually, whatever Dogberry becomes).

<a id="shared-facilities"></a>
## 3 Shared facilities

<a id="jasmine-logging"></a>
### 3.1 Jasmine logging

[Jasmine](../jasmine/jasmine.md) — Puck's JSONL-based logging format — is
available to **both Sinatra and Robinson**. The ambient
`%chain.log` mechanism, the nested call-frame trees, the
directory and webhook stores, and the wrp / detached-write modes
all apply identically across both servers. Configure a Jasmine
log on the server and per-request entries flow through automatically.

If Dogberry returns later, it'll get Jasmine too — Jasmine isn't
coupled to any particular server.
