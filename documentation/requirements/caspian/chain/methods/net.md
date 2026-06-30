# `%chain.net`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_net",
	"role": "spec for %chain.net — networking surface. HTTP client, fetch helpers, raw sockets, Unix-domain sockets."
}}
~~~

**Default-granted across role boundaries:** no.  

`%chain.net` is the global networking surface — HTTP client, fetch helpers, raw sockets, Unix-domain sockets.

The host grants `%chain.net` (via the underlying networking capability) by policy. Without the grant, `%chain.net` is absent or returns `null`.

## Common entry points

| Surface | Purpose |
|---|---|
| `%chain.net.fetch(url, ...)` | One-shot HTTP request — the most common form. |
| `%chain.net.http_client` | Long-lived HTTP client with connection reuse, default headers, etc. |
| `%chain.net.sockets` | Raw TCP/UDP/SSL socket constructors. |
| `%chain.net.uds` | Unix-domain-socket server constructor (foundation for `$uds.share`, `$uds.mikobase`, etc.). |

## See also

- [`%engine.http`](../../engine/http) — user-only access to the same underlying HTTP client.
