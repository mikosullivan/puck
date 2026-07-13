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

## Testing

- **`%chain.net` is `null` or absent without the grant** — without the networking capability, `%chain.net` is unreachable.
- **Default-deny across role boundaries** — a non-user role does not see `%chain.net` until the capability is explicitly granted down the chain.
- **`.fetch(url)` performs an HTTP GET** — default method is GET; the response exposes status, headers, and body.
- **`.fetch` response status** — for a URL returning 200, the response's status is `200`.
- **`.fetch` response headers preserved** — response headers appear as sent by the server, without lowercasing or reformatting values.
- **`.fetch` response body bytes** — the body is available as bytes; UTF-8 body decoded on demand.
- **`.fetch` unicode body round-trip** — a UTF-8 response containing non-ASCII code points is returned unchanged.
- **`.fetch` POST body** — `.fetch(url, method: 'POST', body: ...)` sends the body and receives the server's response.
- **`.fetch` custom headers** — headers passed to `.fetch` appear on the outbound request.
- **`.fetch` 4xx returns a response** — a 404 is returned as a normal response object (status `404`), not raised.
- **`.fetch` 5xx returns a response** — a 500 is returned as a normal response object (status `500`), not raised.
- **`.fetch` DNS failure raises** — an unresolvable host causes `.fetch` to raise.
- **`.fetch` connection refused raises** — a reachable host with no listener on the port causes `.fetch` to raise.
- **`.fetch` timeout raises** — a configured timeout that elapses causes `.fetch` to raise.
- **`.http_client` reuses connections** — repeated requests to the same host through one client share a connection.
- **`.http_client` default headers** — headers set on the client are applied to every request from that client.
- **`.sockets` TCP constructor** — a plain TCP socket can be opened to a listening peer and used to send and receive bytes.
- **`.sockets` UDP constructor** — a UDP socket can send and receive datagrams.
- **`.sockets` SSL** — an SSL/TLS wrapper handshakes with a compatible peer.
- **`.uds` server** — a Unix-domain-socket server can be constructed at a filesystem path and accepts client connections.
- **Response body carries net role provenance** — bytes read from a `.fetch` response carry the role tag of the net faucet.
- **Matches `%engine.http` semantics** — the same request through `%chain.net.fetch` and `%engine.http` returns equivalent responses under identical inputs.
- **Revoke clears the surface** — after `%chain.net` is revoked in a nested block, it is `null` inside that block and reverts on block exit.

## See also

- [`%engine.http`](../../engine/http) — user-only access to the same underlying HTTP client.
