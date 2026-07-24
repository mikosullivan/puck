# HTTP client

~~~vibecode
{"vibecode": {
	"doc": "network_http_client",
	"role": "spec for Caspian's HTTP client surface — puck.uno/http/client and puck.uno/http/response. The most common high-level network client; sugar form is %net.fetch. Built on the raw socket layer (puck.uno/socket/tcp and puck.uno/socket/ssl); user code doesn't see that.",
	"parent_doc": "network/index.md",
	"classes": ["puck.uno/http/client", "puck.uno/http/response"],
	"sugar_surface": "%net.fetch",
	"body_encoding_decision": "explicit_kwargs_body_json_body_form_body_file_body_multipart",
	"audience": "Caspian programmers making HTTP requests",
	"key_concepts": ["primary_high_level_network_client",
		"client_class_plus_response_class",
		"sugar_form_percent_net_fetch",
		"explicit_body_encoding_kwargs",
		"composition_with_puck_uno_lookup_path"]
}}
~~~

The most common high-level network client. Built on [`puck.uno/socket/tcp`](../../sockets.md#tcp) (or [`puck.uno/socket/ssl`](../../sockets.md#ssl) for HTTPS) under the hood; user code doesn't see that.

See [the network index](../../index.md) for the top-level `%net` surface, the permission model, and the cross-cutting exception classes.

---

## `puck.uno/http/client`

The primary client class for HTTP requests. Use it directly for configured, reusable clients; the `%net.fetch` form is sugar for "make a default client and use it once."

**Instantiation:**

```
$client = %puck['https://puck.uno/http/client'].new()
```

Per [%puck lookup form](../../../puck/lookup.md). For a configured client, pass options at creation time:

```
$client = %puck['https://puck.uno/http/client'].new(
    timeout: 30,
    headers: {'User-Agent': 'my-script/1.0'}
)
```

Configuration options apply to every request the client makes.

**Methods:**

| Method | Returns | Purpose |
|---|---|---|
| `.get(url, opts?)` | http_response | HTTP GET |
| `.post(url, body, opts?)` | http_response | HTTP POST |
| `.put(url, body, opts?)` | http_response | HTTP PUT |
| `.delete(url, opts?)` | http_response | HTTP DELETE |
| `.fetch(url, opts?)` | http_response | Generic — method via `opts.method`, defaults to GET |

`opts` is a hash: `{headers, timeout, body, follow_redirects, ...}`. Per-request opts override client-level config.

**Body shapes** (one of):

| Option | Body | Content-Type set |
|---|---|---|
| `body: 'raw'` | The string sent as-is | None (caller sets) |
| `body_json: {...}` | Hash JSON-encoded | `application/json` |
| `body_form: {...}` | Form-encoded | `application/x-www-form-urlencoded` |
| `body_file: $f` | Streamed from file | None (caller sets) |
| `body_multipart: {...}` | Multipart upload | `multipart/form-data; boundary=...` |

Explicit kwargs by encoding instead of one polymorphic `body:` that guesses from type — closes the "hash means JSON" surprise per the explicit-encoding direction.

---

## `puck.uno/http/response`

Returned from every request. Read-only.

| Property | Type | Description |
|---|---|---|
| `.status` | integer | HTTP status code (200, 404, 500, etc.) |
| `.ok?` | boolean | `true` if `200 ≤ status < 300` |
| `.headers` | hash | Response headers, keys lowercased |
| `.body` | string | Raw body |
| `.json` | hash/array/scalar | Parsed JSON body. Raises if body isn't valid JSON |
| `.url` | string | The final URL (after redirects, if followed) |
| `.redirect_chain` | array of strings | All intermediate URLs that were followed |

```
$resp = %net.fetch('https://foo.com/users/42')
if $resp.ok?
    $user = $resp.json
    puts $user['name']
end
```

HTTP status codes (4xx, 5xx) are NOT exceptions — they're returned as the response with `.ok? == false`. The [network-wide exception classes](../../index.md#exceptions) are for transport-level failures only.

---

## Defaults

Sensible defaults for the common case; override per-client or per-request:

| Default | Value | Rationale |
|---|---|---|
| `timeout` | 30 seconds | Bounded failure; matches what most scripts want |
| `User-Agent` | `caspian/<version>` | Honest identification (no Mozilla lie) |
| `follow_redirects` | `true`, max 10 hops | Standard browser-like behavior |
| `verify` (TLS) | `true` | Per system CA bundle |

These are tracked in the existing per-question issues — see [#570](https://github.com/mikosullivan/puck/issues/570) (timeout), [#571](https://github.com/mikosullivan/puck/issues/571) (User-Agent), [#572](https://github.com/mikosullivan/puck/issues/572) (redirects). The values above are the working defaults.

---

## HTTP jail

An **HTTP jail** is a narrowed HTTP client that can only connect to a specified set of domains. User code creates a jail and passes it to downstream roles (libraries, agents, anything not running as `user`) when it wants those roles to have HTTP capability bounded to a specific set of hosts.

This is the recommended pattern for [handing network capability to a downstream role](../../index.md#surface) when the role only needs to reach a handful of known hosts. Instead of passing a fully-capable client, user passes a jail; the role can call `.fetch(url)` for any URL on an allowed domain and gets the response back, but cannot reach anywhere else.

### Top-form sugar

```
$jail = %net.http.client.jail('foo.bar', 'gup.com')
```

Creates a jail that can only connect to `foo.bar` and `gup.com`. Granularity is currently **domain-level** — every URL on those domains is reachable, every URL on any other domain raises. Later we may add expression-based matching (wildcards, paths, etc.).

The jail is passed downstream as a parameter:

```
$jail = %net.http.client.jail('foo.bar', 'gup.com')
$lib  = %puck['https://my-lib.example.com/widget'].new(http: $jail)
$lib.do_thing    # uses $jail internally; can only reach foo.bar and gup.com
```

### Middle form — explicit construction

The top-form sugar is shorthand for constructing a client, configuring its allowlist, and creating a jail on its `fetch` method:

```
$client = %['https://puck.uno/network/http/client'].new()
$client.allow = ['foo.bar', 'gup.com']
$jail = $client.object.jail('fetch')
```

Each step:

- `%['...'].new()` instantiates a regular HTTP client.
- `$client.allow = [...]` sets the host allowlist on the client. Any `fetch` (or other request) the client makes is bounded to these domains; out-of-list raises `puck.uno/error/network/host_not_allowed`.
- `$client.object.jail('fetch')` creates a jail wrapping the client's `fetch` method. The jail is a callable object — passing it downstream gives the recipient `.fetch(url)` capability and nothing else from the underlying client.

### Underlying primitive

The middle form is itself sugar for instantiating a jail object directly. The general mechanism (`.object.jail(method_name)`) is a property of every object, not specific to HTTP — see the broader object-jail spec for the primitive.

### What the downstream role sees

The downstream role receives a callable. From the role's perspective:

```
# Inside the library, $jail is whatever user passed
$resp = $jail.fetch('https://foo.bar/api/thing')   # OK — foo.bar is allowed
$resp = $jail.fetch('https://elsewhere.com/...')   # raises host_not_allowed
```

The role cannot:

- Call methods on the jail other than `.fetch` (the jailed method).
- Modify the jail's allowlist (the jail is a snapshot of user's configuration at jail-creation time).
- Reach back to the underlying client.
- Use `%net` directly (only user has `%net`).

### Composition with `--allow-net`

Jail allowlists compose by **intersection** with the launcher's `--allow-net` grant. If user has `--allow-net=foo.bar` and creates a jail with `['foo.bar', 'gup.com']`, the jail's effective allowlist is just `['foo.bar']` — the engine's grant is the upper bound. Out-of-grant entries in the jail's `allow` are silently dropped (or noted, TBD) at jail-creation time.

This means a jail can NEVER grant access user doesn't already have. Capability flows down the chain only narrows, never widens.

### Granularity

Currently **domain-only** — entries in `allow` are bare hostnames (`'foo.bar'`, `'api.example.com'`). No port specification, no path matching, no wildcards.

Future extensions, not in V1.0:

- Wildcards (`'*.example.com'`)
- Path patterns (`'foo.bar/api/*'`)
- Port narrowing (`'foo.bar:443'`)
- More expressive matchers (regex, predicate functions)

When those land, the existing bare-hostname form stays valid; richer forms layer on as additional entry types in the `allow` array.

---

## Composition with `%puck`

`%puck['https://foo.com/bar']` already reaches the network — through the [fetcher chain](../../../downloads/) — to resolve library URLs. That path is library-resolution-specific (handles caching, version constraints, blockchain endorsement, etc.) and is NOT the same as `%net.fetch`.

Distinction:

- **`%puck[url]`** — library lookup. Goes through the fetcher chain; respects caching; returns a class or value with full library semantics.
- **`%net.fetch(url)`** — general HTTP request. Raw response; no caching by default; no library interpretation.

Both require network access (granted via `--allow-net`); the fetcher chain for `%puck` may be selectively disabled via the [remote-downloads shortcut](../../../engine/require.md#disabling-remote-downloads) without affecting `%net`.

---

## See also

- [Network index](../../index.md) — top-level `%net` surface, I/O model, exception classes, permission model.
- [Raw sockets](../../sockets.md) — the foundation HTTP is built on.
- [HTTP server](../server/index.md) — the server side of HTTP (Touchstone + Sammy).
- [`%puck` lookup](../../../puck/lookup.md) — library-resolution path; reaches network through the fetcher chain.
