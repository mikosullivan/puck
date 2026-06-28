# HTTP server

~~~vibecode
{"vibecode": {
	"doc": "network_http_server",
	"role": "overview of Caspian's HTTP server stack — Touchstone (base class with shared per-request infrastructure) and Sammy (small-site framework with route handlers). Both inherit and compose; new HTTP middleware built on Puck will descend from Touchstone too.",
	"parent_doc": "network/index.md",
	"classes_in_v1": ["puck.uno/touchstone", "puck.uno/sammy"],
	"key_concepts": ["touchstone_is_the_base_class",
		"sammy_adds_route_handlers_on_top",
		"shared_transaction_request_response_objects",
		"per_route_closure_handlers_sinatra_style"]
}}
~~~

Caspian's HTTP server stack is two classes:

- **[Touchstone](touchstone/)** — the base class. Holds shared per-request infrastructure: the `$transaction`/`$request`/`$response`/`$session` objects, the handler chain, content-type factory defaults, Jasmine integration, CSP. Not directly instantiable — descendants decide how to actually serve.
- **[Sammy](sammy/)** — the small-site framework. Inherits Touchstone; adds Ruby-Sinatra-style route handlers (closures bound to HTTP-method + path), a catch-all fallthrough, named placeholders and splats, static file serving.

Most Caspian code uses Sammy directly. Touchstone is the inheritance target for any other HTTP middleware built on Puck.

Future descendants (not in V1.0) include [Robinson](../../../../ideas/robinson/index.md) — filesystem-tree page-server with per-directory handlers; ships on its own timeline as a Puck-resolved library.

---

## See also

- [HTTP client](../client/index.md) — the client side (`puck.uno/http/client`, `%net.fetch`).
- [Network index](../../index.md) — top-level `%net` surface, permission model, exception classes.
- [Touchstone](touchstone/) — base HTTP server class.
- [Sammy](sammy/) — small-site framework.
