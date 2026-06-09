# Raw sockets

~~~vibecode
{"vibecode": {
	"doc": "network_sockets",
	"role": "spec for Caspian's raw socket classes — the foundational layer of the network surface. Covers TCP, UDP, SSL/TLS wrapping, and the TCP listener. Used directly for custom protocols; used indirectly (by HTTP, SMTP, etc.) for everything else.",
	"parent_doc": "network/index.md",
	"classes": ["puck.uno/socket/tcp", "puck.uno/socket/udp", "puck.uno/socket/ssl", "puck.uno/socket/tcp_listener"],
	"audience": "Caspian programmers needing direct socket access; engine implementers wrapping Lua's socket layer",
	"key_concepts": ["foundational_socket_layer",
		"tcp_outbound_and_listener",
		"udp_connectionless_datagrams",
		"ssl_tls_wrapping_with_safe_defaults",
		"sync_blocking_io"]
}}
~~~

The foundational layer of Caspian's network surface. Most scripts won't use these directly — they'll use the [HTTP](http/) or other protocol classes built on top — but the raw layer is fully available without ceremony.

See [the network index](index.md) for the top-level `%net` surface, the permission model, and the cross-cutting exception classes.

---

<a id="tcp"></a>
## `puck.uno/socket/tcp`

A TCP connection — outbound or inbound.

**Construction (outbound):**

```
$sock = %net.tcp('host.com', 5000)
# or equivalent:
$sock = %puck['https://puck.uno/socket/tcp'].new(host: 'host.com', port: 5000, timeout: 30)
```

Opens a connection synchronously. Raises if the host isn't allowlisted, the connection is refused, DNS fails, or the connection times out.

**Construction (from accepted listener):**

```
$listener = %net.tcp_listen('0.0.0.0', 8080)
$sock     = $listener.accept    # returns puck.uno/socket/tcp
```

**Methods:**

| Method | Returns | Purpose |
|---|---|---|
| `.send(bytes)` | integer | Send bytes; returns number written |
| `.send_all(bytes)` | nil | Send bytes; retries until all sent or raises |
| `.recv(max_bytes, opts?)` | string | Receive up to `max_bytes`; blocks until at least one byte available or timeout |
| `.recv_line(opts?)` | string | Receive bytes up to next newline (newline included) |
| `.recv_exact(n, opts?)` | string | Receive exactly `n` bytes; blocks until all received or raises |
| `.close` | nil | Close the connection |
| `.shutdown(direction)` | nil | Half-close: direction is `:send`, `:recv`, or `:both` |
| `.starttls(opts?)` | ssl_socket | Wrap this TCP connection with TLS (see [`puck.uno/socket/ssl`](#ssl)) |

**Properties:**

| Property | Type | Description |
|---|---|---|
| `.host` | string | Remote host this socket is connected to |
| `.port` | integer | Remote port |
| `.local_host` | string | Local IP this socket is bound to |
| `.local_port` | integer | Local port |
| `.connected?` | boolean | `true` while the socket is open |
| `.timeout` | number | Current timeout in seconds; settable |

**Example — TCP echo client:**

```
$sock = %net.tcp('echo.example.com', 7)
$sock.send_all('hello\n')
$reply = $sock.recv_line
puts $reply
$sock.close
```

---

<a id="udp"></a>
## `puck.uno/socket/udp`

A UDP socket — connectionless datagram I/O.

**Construction (outbound):**

```
$sock = %net.udp        # ephemeral local port, no peer set
$sock = %net.udp('host.com', 53)    # default peer; send/recv use it
```

**Construction (listening — see [permissions](index.md#permissions)):**

```
$sock = %net.udp_listen('0.0.0.0', 5353)
```

**Methods:**

| Method | Returns | Purpose |
|---|---|---|
| `.send(bytes)` | integer | Send to the default peer |
| `.send_to(bytes, host, port)` | integer | Send to a specific peer |
| `.recv(max_bytes, opts?)` | string | Receive from any peer |
| `.recv_from(max_bytes, opts?)` | array | Receive; returns `[bytes, host, port]` |
| `.close` | nil | Close the socket |

UDP has no connection state — each datagram is independent. Allowlist enforcement: outbound `send_to` (or `send` to the default peer) checks the target against `--allow-net`; listening checks the bind port against `--allow-listen`.

---

<a id="ssl"></a>
## `puck.uno/socket/ssl`

A TLS-wrapped TCP socket. Either constructed from an existing TCP socket via `.starttls`, or created directly for connections that start TLS from the first byte (HTTPS, IMAPS, etc.).

**Construction (direct):**

```
$sock = %puck['https://puck.uno/socket/ssl'].new(host: 'host.com', port: 443)
```

**Construction (upgrade existing TCP):**

```
$tcp = %net.tcp('mail.example.com', 587)
$tcp.send_all('STARTTLS\r\n')
$tls = $tcp.starttls    # tcp socket becomes invalid; tls is the live socket
```

**Methods:** Same surface as [`puck.uno/socket/tcp`](#tcp) (`send`, `recv`, `recv_line`, `recv_exact`, `close`, `shutdown`). Plus TLS-specific:

| Method | Returns | Purpose |
|---|---|---|
| `.peer_cert` | hash | Subject, issuer, fingerprint, valid_from, valid_until, SANs |
| `.cipher` | string | Negotiated cipher suite name |
| `.protocol` | string | Negotiated TLS version (e.g., `'TLSv1.3'`) |

**Construction options:**

| Option | Default | Description |
|---|---|---|
| `verify` | `true` | Verify the peer certificate. Set `false` only for testing |
| `ca_bundle` | system default | Path to a custom CA bundle |
| `client_cert` | none | Path to client certificate (for mutual TLS) |
| `client_key` | none | Path to client private key |
| `sni` | host | Server Name Indication (defaults to the connect host) |
| `protocols` | `['TLSv1.2', 'TLSv1.3']` | Allowed protocols |

`verify: false` is a deliberate opt-out, not a default. Out-of-the-box TLS validates peer certificates against the system CA bundle.

---

<a id="tcp-listener"></a>
## `puck.uno/socket/tcp_listener`

Returned by `%net.tcp_listen`. Accepts inbound connections.

**Methods:**

| Method | Returns | Purpose |
|---|---|---|
| `.accept(opts?)` | tcp_socket | Block until a connection arrives; returns the new socket |
| `.close` | nil | Stop listening; refuse further connections |
| `.local_host` | string | What we bound to (e.g., `'0.0.0.0'`) |
| `.local_port` | integer | What port we bound to |

**Example — minimal TCP echo server:**

```
$server = %net.tcp_listen('127.0.0.1', 8080)
forever
    $client = $server.accept
    $line   = $client.recv_line
    $client.send_all($line)
    $client.close
end
```

Listening requires the listen grant — see [permissions](index.md#permissions).

---

## See also

- [Network index](index.md) — top-level `%net` surface, I/O model, exception classes, permission model.
- [HTTP](http/) — high-level HTTP client built on `puck.uno/socket/tcp` + `puck.uno/socket/ssl`.
- [DNS resolution (post-V1)](../../../ideas/caspian/dns.md) — explicit `%net.resolve` / `%net.reverse_resolve` is post-V1; sockets accept hostnames in V1 and the OS resolves implicitly.
