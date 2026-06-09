# Network

~~~vibecode
{"vibecode": {
	"doc": "network",
	"role": "spec for Caspian's network surface — general-purpose network access at the level of Python/Perl/Ruby. Two-layer model: raw sockets (TCP, UDP, TLS wrapping) plus per-protocol clients (HTTP, etc.) built on the socket layer. This index doc covers the top-level %net surface, I/O model, exception classes, and permission model. Per-protocol classes live in sibling files: sockets.md, http/.",
	"scope": "general_purpose_network_access; two_layer_model_sockets_plus_protocol_clients",
	"reference_protocols_v1": ["raw_sockets_tcp_udp_ssl", "http_client", "tcp_listen"],
	"reference_protocols_post_v1": ["explicit_dns_resolver", "smtp_send", "imap", "pop3", "ftp", "websocket", "sse"],
	"engine_implementation": "Lua reference engine wraps LuaSocket and standard Lua libraries; other host engines do equivalent wrappings",
	"per_protocol_files": ["sockets.md", "http/"],
	"audience": "Caspian programmers using outbound or inbound network access; engine implementers wiring the network faucet",
	"key_concepts": ["default_deny_via_launcher_grants",
		"top_level_percent_net_surface",
		"two_layer_raw_sockets_plus_protocol_clients",
		"per_host_allowlist_enforcement",
		"listening_separately_gated",
		"sync_blocking_io_by_default",
		"compose_with_puck_uno_lookup_path",
		"engine_config_declares_required_hosts"]
}}
~~~

The surface is **two layers**:

- **Low-level: raw sockets** — TCP, UDP, TLS wrapping. The building block. Used directly when you need a custom protocol; used indirectly (via protocol-specific classes) for everything else.
- **High-level: per-protocol clients** — HTTP and friends. Built on top of the socket layer. Provides the convenient API for the common case.

For permission grants themselves (the CLI flags and the role they create), see [Frank's permission table](../../development/v1/caspian/frank.md#permission-flags) and the [cli.md flag form](../cli.md#flag-form). For how a script declares it needs network access, see [`%engine.config`](../engine/config.md). This doc covers what happens AFTER the grant is in place — how user code uses it.

---

<a id="per-protocol-files"></a>
## Per-protocol files

Protocol-specific classes live in sibling files. This index doc covers only the cross-cutting concerns ([surface](#surface), [I/O model](#io-model), [exceptions](#exceptions), [permissions](#permissions)).

- **[sockets.md](sockets.md)** — raw TCP, UDP, SSL/TLS wrapping, TCP listener. The foundational layer.
- **[http/](http/)** — HTTP client (`puck.uno/http/client`) and HTTP server (Touchstone + Sammy); the most-used surface.

Post-V1 — explicit DNS resolver ([ideas/caspian/dns.md](../../../ideas/caspian/dns.md)) and email send/receive ([ideas/caspian/email/](../../../ideas/caspian/email/)). Basic name resolution still happens implicitly in V1 when sockets / HTTP client connect by hostname; the OS resolves under the hood.

---

<a id="surface"></a>
## Top-level surface: `%net`

A script that's been granted network access reaches network through the **`%net`** system method:

```
%net.fetch('https://api.example.com/users/42')
%net.tcp('host.com', 5000)
%net.resolve('host.com')
```

`%net` returns the network surface object. It exposes:

- **Convenience methods** for the common cases (`%net.fetch`, `%net.tcp`, `%net.udp`, `%net.resolve`).
- **Class instantiation** is also fine — `%puck['https://puck.uno/http/client'].new(...)`, `%puck['https://puck.uno/socket/tcp'].new(...)`. The convenience methods are sugar; classes are the underlying primitives.

`%net` is **engine-granted** — `null` if the script wasn't given any network grant. Guard usage with `if %net`:

```
if %net
    $resp = %net.fetch('https://foo.com/bar')
end
```

The per-host allowlist (from `--allow-net=HOST[:PORT]`) is enforced by the engine when a connection is attempted. User code asks for a host/port; the engine checks against the allowlist; in-list passes through, out-of-list raises `puck.uno/error/network/host_not_allowed`.

### `%net` is user-role-only

`%net` is available to **user role only**. Other roles (nested libraries, stdlib, agent code, anything not running as `user`) get `null` when they call `%net`, even if the program was launched with full network grants. The `--allow-net` family grants network capability TO USER; it doesn't broadcast capability to every role in the program.

**To give a downstream role network access, pass network objects as parameters.** A library that needs to fetch something receives a client (or a more-narrowed surface) from user code:

```
# User code — has %net, decides what to share
$client = %puck['https://puck.uno/http/client'].new()
$lib    = %puck['https://my-lib.example.com/widget'].new(http_client: $client)

$lib.fetch_something    # the library uses $client, which is user-granted
```

The library's role can't reach `%net` directly; it uses whatever the user handed it. This is consistent with Caspian's broader capability-passing model — capabilities flow as explicit parameters, not as ambient role attributes.

Variants of the same pattern:

- **Pass a configured client.** `http_client: $client` — the library has full HTTP capability via the client, bounded by what the user's `%net` allows.
- **Pass a single fetch closure.** `fetch: { |url| %net.fetch(url) }` — narrower; the library can only invoke that one closure form.
- **Pass a wrapped surface with a smaller allowlist.** A future utility might let user code create a `%net`-like object with its own per-host restrictions: `$narrow_net = %net.narrow(['api.example.com'])` — useful for handing a library a deliberately-narrow capability.

The general principle: user is the only role that gets network for free; everything else gets it explicitly or not at all.

### `%net` methods (summary)

| Method | Returns | Spec |
|---|---|---|
| `.fetch(url, opts?)` | http_response | [http.md](http.md) |
| `.tcp(host, port, opts?)` | tcp_socket | [sockets.md](sockets.md#tcp) |
| `.udp(host?, port?)` | udp_socket | [sockets.md](sockets.md#udp) |
| `.tcp_listen(host, port, opts?)` | tcp_listener | [sockets.md](sockets.md#tcp-listener) |
| `.udp_listen(host, port)` | udp_socket | [sockets.md](sockets.md#udp) |

(Explicit DNS resolution — `%net.resolve` / `%net.reverse_resolve` — is post-V1; see [ideas/caspian/dns.md](../../../ideas/caspian/dns.md). V1 sockets/HTTP accept hostnames; the OS resolves implicitly.)

Each is sugar over the underlying class — `%net.tcp(host, port)` is exactly `%puck['https://puck.uno/socket/tcp'].new(host: host, port: port)`. Use whichever form reads better.

---

<a id="io-model"></a>
## I/O model: synchronous blocking

Caspian is single-threaded by default ([per the language overview](../../../overview.md)). Network operations are **synchronous and blocking**: a call to `recv`, `connect`, `accept`, `fetch`, etc. blocks the only thread until the operation completes or times out.

This matches Python's blocking-by-default model and works fine for the overwhelming majority of scripts (sequential request → response → use the response). Scripts that genuinely need concurrent I/O use the opt-in [forking feature](../syntax/system-methods.md) (`%forks`, when it lands) to spawn parallel processes.

No async API in V1. No event loop. No `await`. The forking feature is the parallelism story; sockets stay simple synchronous calls.

**Timeouts are mandatory in spirit** — every blocking operation accepts a `timeout:` option, and sensible defaults apply.

---

<a id="exceptions"></a>
## Exceptions

Raised by network operations across all protocols:

| Class | When |
|---|---|
| `puck.uno/error/network/host_not_allowed` | Target host isn't in the launcher's allowlist |
| `puck.uno/error/network/port_not_allowed` | Target port (or listen port) isn't allowed |
| `puck.uno/error/network/timeout` | Operation didn't complete within timeout |
| `puck.uno/error/network/connection_refused` | TCP connection refused at the network layer |
| `puck.uno/error/network/connection_reset` | Connection reset mid-stream |
| `puck.uno/error/network/dns_failure` | DNS resolution failed |
| `puck.uno/error/network/tls` | TLS handshake or certificate validation failed |
| `puck.uno/error/network/protocol` | Server returned malformed protocol response (bad HTTP, etc.) |
| `puck.uno/error/network/socket` | Generic socket-layer error (covers EINTR-style cases not in the more specific classes) |

Protocol-level errors (HTTP 4xx/5xx, etc.) are NOT exceptions — they're returned as the response object with `.ok? == false` (or the protocol-specific equivalent). The exception classes above are for transport-level failures only.

---

<a id="permissions"></a>
## Permissions

Network access is gated by launcher flags per [Frank's permission table](../../development/v1/caspian/frank.md#permission-flags). The shape of grants for the broader network surface:

### Outbound (connecting / sending)

- `--allow-net=HOST` — connect to that host on any port
- `--allow-net=HOST:PORT` — connect to that host on that port only
- `--allow-net` (bare) — connect to any host on any port
- `--standard` — includes broad outbound (`--allow-net` equivalent for the bundle)

Enforced at connect time (raw sockets) or request time (HTTP). User code asks for a host/port; engine checks; out-of-list raises `host_not_allowed` or `port_not_allowed`.

### Listening (accepting inbound)

Listening is a **separate grant** from connecting. A script with broad `--allow-net` cannot listen unless it also has a listen grant.

- `--allow-listen=PORT` — bind to that port (any interface)
- `--allow-listen=HOST:PORT` — bind to that interface and port (e.g., `127.0.0.1:8080` for localhost-only)
- `--allow-listen` (bare) — bind to any port, any interface
- `--standard` does **not** include listen

Rationale: outbound network access exposes the script to the network; inbound listening exposes the SCRIPT to attackers. Different risk profile, different grant.

### DNS resolution (post-V1)

Explicit DNS resolver methods (`%net.resolve` / `%net.reverse_resolve`) are post-V1 — see [ideas/caspian/dns.md](../../../ideas/caspian/dns.md). Implicit name resolution (when sockets and HTTP client connect by hostname) is always available in V1 via the OS resolver; no separate permission flag.

### Allowlist semantics

- **Hosts match by name**, not by resolved IP. `--allow-net=api.example.com` allows the connection to whatever IP `api.example.com` resolves to at connect time.
- **DNS rebinding** is not a concern because the allowlist is hostname-based, not IP-based.
- **CIDR ranges** are not currently supported — only specific hostnames or wildcards (`*.example.com` — TBD; not yet specified).

Open design points (in addition to the HTTP-specific [issues already filed](#issues)):

- Wildcard hostname syntax in allowlists.
- Port range syntax for listen grants.
- Whether `--no-dns` is worth supporting.
- Interaction with VPN / proxy environments.

---

<a id="issues"></a>
## Open design issues

Per-question design questions tracked in GitHub:

- [#567](https://github.com/mikosullivan/puck/issues/567) — server-side class location
- [#568](https://github.com/mikosullivan/puck/issues/568) — streaming bodies
- [#569](https://github.com/mikosullivan/puck/issues/569) — allowlist check timing
- [#570](https://github.com/mikosullivan/puck/issues/570) — default timeout (working default: 30s)
- [#571](https://github.com/mikosullivan/puck/issues/571) — default User-Agent (working default: `caspian/<version>`)
- [#572](https://github.com/mikosullivan/puck/issues/572) — redirect handling defaults
- [#574](https://github.com/mikosullivan/puck/issues/574) — cookie handling
- [#576](https://github.com/mikosullivan/puck/issues/576) — Lua/LuaSocket integration plan
- [#577](https://github.com/mikosullivan/puck/issues/577) — listen-grant flag syntax
- [#578](https://github.com/mikosullivan/puck/issues/578) — post-V1 protocol enumeration (IMAP, POP3, FTP, WebSocket, SSE)
- [#579](https://github.com/mikosullivan/puck/issues/579) — SMTP-direct vs provider-API (now post-V1; see [ideas/caspian/email/](../../../ideas/caspian/email/))

Closed: [#565](https://github.com/mikosullivan/puck/issues/565) async model (settled: sync blocking), [#566](https://github.com/mikosullivan/puck/issues/566) TCP/UDP scope (settled: in V1.0), [#573](https://github.com/mikosullivan/puck/issues/573) JSON body encoding (settled: explicit kwargs).

---

## See also

- [Permission flags / `--allow-net`](../../development/v1/caspian/frank.md#permission-flags) — how network is granted at launch.
- [`%engine.config`](../engine/config.md) — how a script declares it needs network access.
- [`%puck` lookup](../puck/lookup.md) — library-resolution path; reaches network through the fetcher chain, separately from `%net`.
- [Disabling remote downloads](../engine/require.md#disabling-remote-downloads) — the `%puck`-fetcher closed-world shortcut; doesn't affect `%net`.
- Issue [#555](https://github.com/mikosullivan/puck/issues/555) — broader design conversation about the network surface.
