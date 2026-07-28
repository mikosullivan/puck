# `%engine.http_client`
<!--index: 6 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_http_client",
	"role": "spec for %engine.http_client — the HTTP client for making outbound network requests"
}}
~~~

`%engine.http_client` is the HTTP client — the surface for making outbound network requests from a Caspian program. It covers the standard verbs (GET, POST, PUT, DELETE, etc.) plus the common ergonomics: query strings, request headers, body encodings, response decoding, redirect handling, and timeouts.

Most user code reaches this through the global shortcut `%chain.net.http` (or further-shortened helpers like `%fetch.download`); `%engine.http_client` is the underlying surface those globals are built on.

The detailed method-level spec (the exact call shapes, options, error classes) lives in the HTTP doc — to migrate from `requirements-old/caspian/network/http.md` into this tree.

## Testing

- **`%engine.http_client.get(url)` returns a response object** — a successful GET has `.status`, `.headers`, and `.body`.
- **`.status` is an integer** — a 200 response yields `.status == 200`.
- **`.body` is a string** — the payload comes back as bytes decoded into a Caspian string.
- **`.headers` is a hash** — reachable as `.headers['content-type']`.
- **`%engine.http_client.post(url, body: ...)` sends the body** — the server observes exactly the bytes passed.
- **`%engine.http_client.put(url, body: ...)` sends a PUT** — verb mapping matches the method name.
- **`%engine.http_client.delete(url)` sends a DELETE** — verb mapping matches the method name.
- **`%engine.http_client.head(url)` returns headers with no body** — `.body` is empty; `.headers` present.
- **`%engine.http_client.patch(url, body: ...)` sends a PATCH** — verb mapping matches.
- **Custom request headers are sent** — `%engine.http_client.get(url, headers: {authorization: 'Bearer xyz'})` puts the header on the wire.
- **Response header names are reachable case-insensitively** — `.headers['content-type']` and `.headers['Content-Type']` both reach a `Content-Type: text/plain` header.
- **4xx status codes do NOT raise** — `%engine.http_client.get(url_returning_404).status` is `404`; no exception.
- **5xx status codes do NOT raise** — `%engine.http_client.get(url_returning_500).status` is `500`; no exception.
- **Connection refused raises a network error** — fetching an unreachable local port raises a distinct network-error class.
- **DNS resolution failure raises** — a URL with an unresolvable host raises a distinct DNS-error class.
- **Timeout raises** — a request exceeding the configured timeout raises a timeout error rather than blocking indefinitely.
- **HTTPS with a valid CA-signed certificate succeeds** — an `https://` URL with proper certs returns a response.
- **HTTPS with an expired certificate raises** — TLS verification failure surfaces as an error.
- **HTTPS with a self-signed certificate raises by default** — verification is on by default; no silent acceptance.
- **Redirects follow by default** — a 302 to another URL returns the body from the redirect target.
- **Redirect chain has a bounded max hops** — an infinite redirect loop terminates by raising rather than looping.
- **Unicode in URL paths is percent-encoded** — `%engine.http_client.get('https://example.com/path/Zoë')` reaches the correct URL server-side.
- **Response body defaults to UTF-8 decoding** — a response with `charset=utf-8` returns a string with unicode intact.
- **Request body accepts a string** — passing `body: 'abc'` sends those three bytes.
- **Chunked-encoded response bodies assemble correctly** — `transfer-encoding: chunked` results in a body equal to the concatenation of all chunks.
- **Empty response body is the empty string** — a 204 returns `.body == ''`, not null.
- **Response object is role-tagged with the network faucet's role** — `response.object.role` is that role, not `user`.
- **`.body` contributors list includes the network faucet role** — `.body.contributors` records the source.
- **`.headers` values are strings** — every value in the hash is a string, not parsed to another type.
- **Repeated response headers are captured** — a server sending two `Set-Cookie` headers is exposed via `.headers` in a way that preserves both.
- **Non-user role calling `%engine.http_client` raises** — the `%engine` blanket gate.
- **Capturing `%engine.http_client` and calling from a non-user frame** — under method-runs-as-owner, the underlying call runs as the capturer's role; a non-user frame that directly calls `%engine.http_client` (never captured) raises.
- **Sending a request with a non-string body raises** — `%engine.http_client.post(url, body: 42)` raises rather than coerces silently.
- **A GET with a nil URL raises** — `%engine.http_client.get(null)` raises a validation error.
- **HTTP verb methods are read-only slots** — `%engine.http_client.get = ...` raises.
- **Response body preserves binary bytes** — a body sending non-UTF-8 bytes round-trips as those exact bytes in the string.
