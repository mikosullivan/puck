# HTTP Middleware

Kiera ships HTTP server classes for building web applications and
services. Each is its own standalone class — you instantiate,
configure, and run it.

| Class | UNS | Use case |
|---|---|---|
| **Touchstone** | `kiera.uno/touchstone` | Base class. Content-type defaults, Jasmine integration, shared HTTP plumbing. Sinatra and Robinson inherit from it; not for direct instantiation. |
| **Sinatra** | `kiera.uno/sinatra` | Small sites, microservices, single-file apps. Route handlers as closures, Ruby-Sinatra-style. |
| **Robinson** | `kiera.uno/robinson` | Filesystem-tree-served sites. Pages live as files in a directory tree; URL paths map to file paths. |
| **Dogberry** | `kiera.uno/dogberry` | **Deferred.** A more elaborate framework, planned for later releases. May turn out to be a very different sort of thing. |

## Architecture

**No layered servers.** Sinatra and Robinson are not "handlers
inside Dogberry" — they're standalone servers. You pick the one
that fits your use case and use it directly:

```
# A simple Sinatra-style app
$server = %['kiera.uno/sinatra'].new()
$server.get('/') do($request)
    response.new(200, {}, 'Hello world')
end
$server.run()
```

```
# A filesystem-tree-served Robinson site
$server = %['kiera.uno/robinson'].new(root: '/var/www/mysite')
$server.run()
```

This is a deliberate departure from the earlier "Dogberry as the
framework, Sinatra/Robinson as handlers" model. The current model
keeps each server simple and self-contained; Dogberry's eventual
shape will be designed without being constrained to slot Sinatra
and Robinson in as components.

## Picking one

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

## Shared facilities

### Jasmine logging

[Jasmine](../jasmine/jasmine.md) — Kiera's JSONL-based logging format — is
available to **both Sinatra and Robinson**. The ambient
`%chain.log` mechanism, the nested call-frame trees, the
directory and webhook stores, and the wrp / detached-write modes
all apply identically across both servers. Configure a Jasmine
log on the server and per-request entries flow through automatically.

If Dogberry returns later, it'll get Jasmine too — Jasmine isn't
coupled to any particular server.
