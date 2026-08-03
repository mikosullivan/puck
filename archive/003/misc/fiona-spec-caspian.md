# Caspian interface

~~~vibecode
{"vibecode": {
	"doc": "ideas_fiona_spec_caspian",
	"role": "Caspian-facing interface to Fiona — the shape users write when working with Fiona in Caspian code. Complements the Lua reader/writer at ../lua/ and the schema layer at ../sqlite.md.",
	"status": "stub"
}}
~~~

## Use cases

### Interprocess communication

Fiona serves as a shared coordination store between processes on the same host. The pattern:

1. Fork off a Fiona server as a separate process.
2. Fork off worker processes that need to share state.
3. Workers write results into the shared Fiona store; the parent (or any process holding the handle) reads them back.

_The fork primitives below (`%forks.manager`, `$mgr.fork do ... end`, `$worker.id`) are provisional — the fork spec isn't settled. The pattern is what matters._

Full example — 10 workers running `&complicated_process` in parallel, aggregating results in Fiona:

~~~caspian
$server = %('caspian.uno/ipc/fiona.casp').new()
$mgr = %forks.manager.new

10.times do
	$fork = $mgr.fork do() as $worker
		$value = &complicated_process
		$server[$worker.id] = $value
	end
end
~~~

#### Mechanisms that make this work

- **The server is a forked child process.** `%('caspian.uno/ipc/fiona.casp').new()` doesn't just download a class — it instantiates a fresh Fiona server as its own OS process. `$server` is a handle to that child.

- **Communication is HTTP over a Unix domain socket.** The child creates a socket at a path like `/tmp/fiona-<uuid>.sock` and speaks HTTP. Local-only by design (no accidental network exposure), fast (no network stack), debuggable (`curl --unix-socket ...` works for one-off pokes), and language-agnostic (any HTTP client with Unix-socket support can be a Fiona client).

- **Authentication is bundled into the handle.** `$server` carries an auth credential the server expects on every request. Discovering the socket path (`ls /tmp`) isn't enough; without the credential, no calls succeed. Passing `$server` to other code is a deliberate grant of that authority.

- **The handle is stateless.** `$server` holds the socket path and credential; it does NOT hold an open connection. Connections are opened lazily, pooled where it helps, and re-established transparently when a stale one is detected. This is what makes the handle fork-friendly — a child inherits `$server` and can use it immediately without inheriting an open fd (avoiding the classic fork-after-connect fd-sharing bugs).

- **JSON primitives only, for now.** String, number, boolean, null, hash, and array. Matches Fiona's on-disk schema (`hsa` types plus scalar sub-types) exactly. Fancier object marshaling is a later problem.

- **Hash facade at the client.** `$server[$worker.id] = $value` reads like an ordinary hash write; behind the scenes it marshals to an HTTP request that the server turns into the appropriate Fiona ops. Nested literals wrap a transaction so multi-step builds are all-or-nothing.

- **Fan-out / gather without shared mutable state.** Because each worker uses `$worker.id` as its key (unique per fork), no two writes collide — no locks, no message-passing choreography. Just parallel writes to non-overlapping Fiona slots. After the workers finish, the parent reads the shared store to aggregate the results.

