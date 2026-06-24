# Unix domain sockets

~~~vibecode
{"vibecode": {
	"doc": "network_uds",
	"role": "spec for Caspian's Unix domain socket server — pathname-form UDS that runs a Sammy HTTP server under the hood. User code registers routes with HTTP-verb methods (.get, .post, etc.) and starts the server with .wait. User-role only by default. Filesystem path is exposed for cross-process coordination.",
	"parent_doc": "network/index.md",
	"status": "committed for V1.0 — server side, authentication, client side, forked-workers pattern, and connection retry all settled. Remaining opens (SO_PEERCRED exposure, socket-file cleanup details, concurrency model, explicit path kwarg, retry parameters) settle during implementation rather than block design. Shared-hash ([uds/shared-hash.md](shared-hash.md)) and the broader IPC layer ([forking/ipc.md](../../forking/ipc.md)) are built on top.",
	"key_concepts": ["unix_domain_socket_server_class",
		"sammy_under_the_hood_so_http_semantics",
		"route_registration_via_http_verbs",
		"wait_method_runs_the_server",
		"user_role_only_by_default",
		"engine_picks_the_path_user_can_read_it",
		"client_side_deferred"]
}}
~~~

The UDS surface is a Sammy HTTP server bound to a Unix domain socket instead of a TCP port. User code registers routes the same way it would for any Sammy server; the `.wait` method runs the server. Under the hood, all the HTTP framing, request parsing, and response handling is Sammy's responsibility — the UDS class just provides the local-socket transport.

See [the network index](../index.md) for the top-level `%net` surface, the permission model, and the cross-cutting exception classes. This doc covers only the server side; the client side is deferred.

---

<a id="constructor"></a>
## Construction

~~~caspian
$uds = %utils.network.uds.new()
~~~

`%utils.network.uds.new()` returns a UDS server object. The engine picks a path for the socket file automatically — typically under an engine-managed temp area. The path is bound at construction time, before any client has connected, so user code can read it and pass it to other processes that need to connect.

The path is readable:

~~~caspian
$uds.path    # the filesystem path where the socket lives
~~~

It's just a string. User code can pass it through any channel (argv to a forked child, environment variable, written to a file, embedded in a config) to let other processes know where to connect.

User code can also specify the path explicitly at construction time if it has a specific path in mind (TBD — `%utils.network.uds.new(path: '/custom/path.sock')` or similar).

---

<a id="routes"></a>
## Route registration

The server runs HTTP under the hood via Sammy. Routes register via HTTP-verb methods on the UDS object:

~~~caspian
$uds.get('/status') do($request)
	# handler for GET /status
end

$uds.post('/work') do($request)
	# handler for POST /work
end

$uds.put('/things/{id}') do($request)
	# handler for PUT /things/<id>
end

$uds.delete('/things/{id}') do($request)
	# handler for DELETE /things/<id>
end
~~~

`$request` is a Sammy HTTP request object — same shape as Sammy requests served over any other transport. See the Sammy spec for the full request surface (path, method, headers, body, path-segment captures, etc.).

The route methods follow the same conventions as elsewhere in the Sammy ecosystem; the UDS class is just a thin Sammy host that happens to bind to a Unix socket.

---

<a id="wait"></a>
## Running the server

`.wait` starts the server and blocks. Two forms:

### `wait` with no block — routes only

~~~caspian
$uds.get('/status') do($request)
	...
end

$uds.wait    # blocks; routes the registered handlers; unmatched requests get a default response
~~~

Unmatched paths get a default 404-style response from Sammy.

### `wait` with a fallback closure — catch-all for unmatched

~~~caspian
$uds.get('/status') do($request)
	...
end

$uds.wait do($request)
	# fires for any request that didn't match a registered route
end
~~~

Mirrors the Dogberry pattern: registered routes match first; the `wait` closure is the catch-all for everything else. The fallback closure can return any HTTP response Sammy produces.

---

<a id="permissions"></a>
## Permissions

`%utils.network.uds.new()` is **user-role only by default**. Other roles (nested libraries, agent code, stdlib internals) get an exception if they try to call it directly — same pattern as `%net` (HTTP) and `%engine`.

To give a downstream role UDS access, user code creates the UDS and passes the `$uds` object as a parameter:

~~~caspian
$uds = %utils.network.uds.new()
$lib = %puck['https://my-lib.example.com/widget'].new(uds: $uds)
~~~

The library can now register routes on `$uds` and call `.wait` on it. The capability is bounded to that specific UDS handle; the library can't create new UDSes of its own.

The capability-passing model matches the broader principle ([per network/index.md § `%net` is user-role-only](../index.md#surface)): user is the only role that gets capabilities for free; everything else gets them explicitly or not at all.

---

<a id="uds-in-forks"></a>
## `$uds` inside a fork

`$uds` is the server-side handle. Forks are worker processes — they should be using `$client` (the inherited client wrapper), not the server object directly. Trying to do server operations on `$uds` from a forked child raises `puck.uno/error/uds/server_used_in_fork` (working name).

**Read-only params are allowed.** A fork can inspect `$uds`'s data without raising:

| Access from fork | Allowed |
|---|---|
| `$uds.path` | yes — read-only data |
| `$uds.token` | yes — read-only data |
| `$uds.authenticate = ...` | raises (server config) |
| `$uds.wait()` | raises (server operation) |
| `$uds.client` | raises (server-side constructor) |
| `$uds.get('/path') do ... end` | raises (route registration) |
| `$uds.post`, `.put`, `.delete`, etc. | raises (route registration) |

The rule: read-only inspection is fine; anything that would mutate server state, register routes, or start the server loop raises. The fork doesn't OWN the server; it can look at the server handle's data but not act on it.

If a fork needs to make requests, it uses `$client` (inherited from the parent via closure capture). If it needs the path or token to coordinate with other processes, it can read `$uds.path` and `$uds.token` directly.

---

<a id="authentication"></a>
## Authentication

A UDS server can require a token from every incoming request. Clients without a valid token are rejected at the HTTP layer. This adds an application-level check on top of the OS-level UDS protections (filesystem permissions on the socket path; optional kernel-verified peer credentials via SO_PEERCRED).

### Enabling auth

~~~caspian
$uds = %utils.network.uds.new()
$uds.authenticate = true
~~~

When `authenticate` is set to `true`, the engine generates a cryptographically random token for this server instance. The token is a high-entropy random string (secure random, not a UUID).

`$uds.authenticate = true` is settable **only before `wait()`** — once the server is bound and accepting requests, changing the auth requirement mid-flight raises ugly questions about existing connections. Lock it at startup; a future "rotate the token while running" feature could add a separate method if a use case ever emerges.

### Reading the token

~~~caspian
$token = $uds.token    # the engine-generated random secret
~~~

Read-only. User code reads it to pass to other processes that need to connect — written to a sibling file, passed via env var, embedded in argv, etc.

### Forks inherit automatically

The client wrapper (`$client = $uds.client`) carries the token internally. When workers fork, they get a copy of `$client` via closure capture — token included. No extra coordination needed:

~~~caspian
$uds = %utils.network.uds.new()
$uds.authenticate = true
$client = $uds.client

%utils.forks.multiple(20) do
    $client.get('/work')    # token attached automatically
end

$uds.wait()
~~~

Each worker's client carries the inherited token; requests just work.

### External processes

A different process that wants to connect to a token-protected UDS needs both the path AND the token. The path is in `$uds.path`; the token is in `$uds.token`. User code passes both through whatever out-of-band channel makes sense (env vars, argv, written to a config file, etc.).

The external process constructs a client with both pieces of context (TBD — `%utils.network.uds.client.new(path: ..., token: ...)` or similar; client-side construction is part of the deferred client spec).

### Wire format

Every request from a client (when auth is enabled) carries an HTTP header:

```
Authorization: Bearer <token>
```

Standard HTTP bearer-token format. The server validates the token on each request.

### Failure responses

Requests with no token, or with a wrong token, get:

- **401 Unauthorized** as the status code.
- A `WWW-Authenticate: Bearer realm="<uds>"` response header indicating what auth is expected.

Same response for both "no token" and "wrong token" cases. 403 Forbidden is reserved for "auth is valid but the action isn't allowed" (different concept; not relevant here unless future per-route permissions get added).

### Composition with other security layers

The token auth is one of three independent protections that can stack:

| Layer | What it controls |
|---|---|
| **Filesystem permissions** on the socket path | Who can even reach the socket file (e.g., other-user processes blocked by Unix file mode). |
| **SO_PEERCRED** (optional, surfaced via `$request.peer`) | Kernel-verified identity (PID/UID/GID) of the connecting process. Useful for "same-user only" or "specific UID only" checks in handler code. |
| **Token authentication** | "You must know the secret." Works regardless of who's connecting. |

All three can be on simultaneously. Filesystem perms restrict who can knock; SO_PEERCRED tells you who's knocking; the token confirms they know the secret.

---

<a id="client"></a>
## Client side

The same `$uds` object can produce a client handle that connects back to itself:

~~~caspian
$uds = %utils.network.uds.new()
$client = $uds.client
~~~

`$uds.client` returns a client object suitable for making requests against this UDS. The client is bound to the same path as the server but knows how to make outbound requests rather than serving incoming ones.

Calling the server through the client uses HTTP-verb methods to match the server's route registration shape:

~~~caspian
$response = $client.get('/status')
$response = $client.post('/work', body: $payload)
$response = $client.put('/things/abc', body: $data)
$response = $client.delete('/things/abc')
~~~

Returns a response object (Sammy's response shape — same as elsewhere in the Sammy ecosystem).

### Connection retry

The first call from a client may race ahead of the server's `wait()` — the socket isn't bound until `wait()` runs, so a client trying to connect immediately after `new()` (especially in a forked-workers pattern, see [below](#forked-workers)) can hit "no socket here yet."

`$client.<verb>(...)` handles this by **auto-retrying briefly on connect**: a few attempts with short backoff covers the parent's race to `wait()`. The retry is invisible to user code — it just waits a few hundred ms in the worst case, then succeeds once the server is up.

If the server never comes up at all (a more serious failure), the client gives up after the retry budget is exhausted and raises a connection-refused exception (TBD exception class).

**No log pollution.** The kernel doesn't log normal UDS connect failures — no `dmesg`, no `syslog`, no `journald` entries for `ENOENT` (path doesn't exist yet) or `ECONNREFUSED` (path exists but not listening). The retry loop is silent at the system level. Caspian's own retry logic is also silent — no engine-level log entries for the expected race window. The only thing that would record the retries is an externally-configured `auditd` rule watching `connect()` syscalls (rare; admin opt-in).

---

<a id="forked-workers"></a>
## Forked workers pattern

A common pattern: parent runs the server, forks N workers, workers talk back to the parent via the client.

~~~caspian
$uds = %utils.network.uds.new()
$client = $uds.client

# Fork 20 workers, each inheriting $client via closure capture
%utils.forks.multiple(20) do
	$response = $client.get('/work')
	# do something with the response
end

# Parent enters the accept loop
$uds.wait() do($request)
	# handle inbound requests from any of the 20 workers
end
~~~

How the timing works:

- `new()` creates the UDS object and picks a path. **Socket is not yet bound.**
- `$uds.client` creates a client handle pointing at the (not-yet-bound) path.
- `forks.multiple(20)` spawns 20 child processes. Each child inherits a copy of `$client` via closure capture (per the [fork closure semantics](../../forking/#closure-semantics) — separate process memory after fork).
- Children start running their block immediately and may call into `$client` before the parent's `wait()` has bound the socket.
- The connection-retry behavior on the client side covers the race: workers may try once or twice and fail with `ENOENT` / `ECONNREFUSED`, then succeed once the parent has reached `wait()`.
- Parent calls `$uds.wait()`, which binds the socket and starts the accept loop. From this point on, workers' requests are accepted and routed to the `do($request)` block.

Net: the user writes the code in the natural order (server setup → forks → wait) without thinking about timing. The auto-retry handles the race; the kernel doesn't log the brief connect failures.

---

<a id="open-points"></a>
## Open points

- **Cross-process client (non-forked).** The forked-workers pattern handles client access naturally (children inherit `$client` via closure capture). For unrelated processes that need to connect to a UDS — separate Caspian script, external program, etc. — the bootstrap is "user passes the path string somehow." That's fine in principle; exact ergonomics around process discovery aren't speced.
- **Authentication.** Unix domain sockets support kernel-verified peer credentials via `SO_PEERCRED` (sending process's PID/UID/GID). Sammy could expose these on `$request` (`$request.peer.pid`, etc.) — TBD whether they're always available, opt-in, or hidden.
- **Cleanup.** When the server stops, what happens to the socket file? Engine deletes it automatically? User has to clean up? What about crash recovery?
- **Concurrency.** Caspian is single-threaded. How does the UDS server handle multiple simultaneous requests — one at a time, or via forked workers (like Sammy's fork-detach-ignore mode)? Choice affects both throughput and the mental model.
- **Explicit path.** Can user code specify the path at construction time (`%utils.network.uds.new(path: '/custom/path.sock')`)? Probably yes, but the exact kwarg shape and the engine's behavior when a path already exists need confirming.
- **Path collision.** If the path already exists (stale socket file from a crashed previous run), what happens? Engine removes it and continues? Raises? Configurable behavior?
- **Stopping the server.** `.wait` blocks. How does user code stop the server cleanly? `.stop` from another fork? `.wait` returning when something specific happens? Signal handling?
- **Retry budget and exception.** Working assumption: a few attempts with short backoff. Exact number, backoff curve, and the exception class raised when the retry budget is exhausted need pinning down.
