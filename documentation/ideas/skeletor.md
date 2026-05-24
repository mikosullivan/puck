# Skeletor

~~~json
{"vibecode": {
	"doc": "skeletor",
	"role": "Caspian's runtime state organization: all execution state lives in a single hash; eventually that hash can be serialized for snapshot-and-revive, enabling transparent process pause/resume across remote calls",
	"status": "V1.0 objective — narrow scope; broader capabilities deferred",
	"v1_0_scope": "in-memory state hash only; no export API; no snapshot/revive; no HTTP promise()",
	"future_scope": "serialize/revive machinery, enabling HTTP promise() and the full snapshot-and-resume flow",
	"depends_on": ["deterministic_gc"],
	"inspired_by": "Temporal / AWS Step Functions workflow engines, applied as a language primitive"
}}
~~~

**Skeletor** is the code name for Caspian's process-state organization: all execution
state lives in a single hash, and the interpreter accesses runtime state only through
that hash's interface. The longer-term goal is to serialize that hash for
snapshot-and-revive — letting a Caspian process pause across a remote call, release the
host process during the wait, and revive transparently when the response arrives. The
foundation (the hash) ships in V1.0; the snapshot/revive machinery is deferred.

<a id="v1-0-scope"></a>
## V1.0 scope

~~~json
{"vibecode": {
	"section": "v1_0_scope",
	"ships": "in-memory state hash + interpreter discipline",
	"does_not_ship": ["export_api", "snapshot_revive", "http_promise", "engine_provided_hash"]
}}
~~~

V1.0 of Skeletor ships **only the in-memory hash** and the structural commitment that
the interpreter goes through it for all execution state:

- The runtime creates a plain in-memory hash on startup (Lua-table-backed in Lucy).
- All execution state — objects, references, call stack frames, globals, PC, iterator
  positions, pending exceptions, role/chain context — lives in the hash.
- Working state (intermediate expression results, arguments being marshaled, return
  values being prepared) stays outside the hash.
- The interpreter never bypasses the hash interface. One rule, enforced in code
  review, opens every door that follows.

**Not in V1.0:**

- **No export API.** The hash cannot be serialized to JSON or any other format.
- **No snapshot/revive.** Without export, processes cannot be paused-and-resumed.
- **No HTTP `promise()`** — the user-facing feature described later in this doc
  depends on snapshot/revive, so it does not ship in V1.0.
- **No engine-provided hash.** The runtime creates and owns its hash; engine
  overrides (SQLite, distributed, etc.) are a deferred extension point — see
  [#160](https://github.com/mikosullivan/puck/issues/160).

Why ship the foundation without the feature? Because the discipline matters even
without the export. The hash organization makes deterministic GC clean, makes the
reference graph natural, makes the runtime inspectable, and makes every future
serialization/persistence/snapshot story a contained addition rather than a runtime
overhaul. V1.0 ships the foundation; V1.x lands the export and the features that
depend on it.

<a id="future-snapshot-and-revive"></a>
## Future: snapshot-and-revive (post-V1.0)

The original Skeletor vision — transparent snapshot-and-revive across blocking remote
calls — depends on adding an export API to the V1.0 hash. The sections below describe
that target shape. None of it ships in V1.0; it's recorded here so the V1.0 work is
done with the post-V1.0 capability in mind.

The post-V1.0 flow: a Caspian program makes what looks like a synchronous call; under
the hood, the runtime serializes the entire process state, releases the host,
dispatches the remote operation, and revives the process with the response value in
hand when the operation completes. Code stays linear. Host resources go to zero during
the wait. Crashes during the wait are transparent — the snapshot revives on whatever
host picks it up next.

---

<a id="post-v1-0-api"></a>
## Post-V1.0 API (deferred)

~~~json
{"vibecode": {
	"section": "post_v1_0_api",
	"surface": "single method on a single class",
	"class": "puck.uno/http/request",
	"method": "promise()",
	"return": "puck.uno/http/response instance",
	"status": "deferred — requires the export API not in V1.0"
}}
~~~

The only way to make a promise (in the post-V1.0 design) is via an HTTP request object:

~~~caspian
$http = %['puck.uno/http/request'].new('https://foo.com?q=303')
$response = $http.promise()
~~~

From the developer's view, `promise()` is a blocking call that returns the HTTP
response. Under the hood, the runtime may snapshot the entire process, free the
host, dispatch the request through whatever HTTP infrastructure is available, and
revive the process with the response value bound to `$response`.

Whether a particular call actually snapshots, or completes inline because the
response is fast enough, is the runtime's decision — programs cannot distinguish
between the two cases. That gives the runtime room to optimize (inline-fast,
snapshot-slow) without changing program semantics.

---

<a id="what-happens-under-the-hood"></a>
## What happens under the hood

~~~json
{"vibecode": {
	"section": "under_the_hood",
	"steps": ["assign_correlation_id", "snapshot_to_disk", "dispatch_request",
		"host_exits", "watcher_monitors", "response_arrives",
		"revive_snapshot", "bind_response_value", "resume_execution"],
	"caller_visibility": "none — looks like a synchronous call"
}}
~~~

At the `promise()` call:

1. The runtime assigns the request a unique correlation ID.
2. The runtime serializes the entire process state — worldlet, call stack, PC, roots
   — tagged with the correlation ID. The snapshot includes everything needed to
   resume execution from the line after the `promise()` call.
3. The runtime hands `(correlation_id, request)` to an external dispatcher (a small
   daemon, a queue, or a Puck service — exact mechanism TBD per the host).
4. The Caspian host process exits. Memory is freed.
5. The dispatcher executes the HTTP request.
6. When the response arrives, the dispatcher locates the snapshot by correlation
   ID, revives it, and binds the response value as the return of `promise()`.
7. Execution continues from the line after the call as if nothing had happened.

No class-level hooks fire at snapshot or revive. The runtime serializes whatever's
in the worldlet; the worldlet is everything. Anything that genuinely needs to live
outside the worldlet (an open TCP socket, a file descriptor) belongs to the host
engine, not to user code — see
[no on_snapshot / on_revive hooks](#out-of-scope-snapshot-revive-hooks) below.

---

<a id="engine-granted-permission"></a>
## Engine-granted permission

~~~json
{"vibecode": {
	"section": "engine_permission",
	"role": "the host engine must grant a Caspian program permission to make promise() calls",
	"reason": "promise() exits the host process; embedding engines need explicit opt-in",
	"mechanism": "TBD"
}}
~~~

A Caspian program cannot make `promise()` calls unless the embedding engine has
granted it permission. This matters because `promise()` involves the host process
exiting — an engine that embeds Caspian inside a larger system needs to decide
whether that's acceptable behavior. A web framework that runs Caspian per-request
probably wants `promise()` allowed. A trigger-firing engine that expects every
invocation to complete in milliseconds probably does not.

The mechanism for granting and revoking this permission is TBD. See
[engine permission model](#open-engine-permission-model) below.

---

<a id="explicitly-out-of-scope"></a>
## Explicitly out of scope for V1

~~~json
{"vibecode": {
	"section": "out_of_scope_v1",
	"role": "scope-tightening — features that are plausible but not in V1",
	"principle": "narrow_surface_first_evolve_when_real_use_cases_emerge"
}}
~~~

<a id="out-of-scope-general-primitive"></a>
### A general `%utils.promise($anything)` primitive

V1 has no general "promise this arbitrary operation" entry point. The only thing
that gets `promise()` is `puck.uno/http/request`. Other plausible primitives
(`%fs.read_async`, `%db.query_async`, system-operation promises, etc.) are not
in V1.

<a id="out-of-scope-promise-all-race-timeout"></a>
### Parallel / race / timeout combinators

No `promise_all([reqs])`, no `race([reqs])`, no `promise(req, timeout: 5.minutes)`
in V1. The first version is one request, one wait, one response. Combinators are a
natural V2 extension when real workloads ask for them.

<a id="out-of-scope-cancellation"></a>
### Cancellation

No external-cancel of an in-flight promise in V1. Once dispatched, the promise
runs to completion or to whatever the underlying HTTP layer does on failure.

<a id="out-of-scope-promise-objects"></a>
### Promise objects you can pass around

V1 `promise()` returns the resolved value directly, not a promise/future object.
Promise-as-a-first-class-value (passing pending promises between functions,
storing them in variables before awaiting) is a different design that would
require changes to the language's evaluation model. Not in V1.

<a id="out-of-scope-snapshot-revive-hooks"></a>
### `on_snapshot` / `on_revive` class hooks

No per-class hooks fire at snapshot or revive time. The aspiration is **never to
need them**. The worldlet is the single source of truth for runtime state — if a
piece of state matters to the program, it lives in the worldlet, and serializing
the worldlet captures it. If it doesn't live in the worldlet (an open TCP socket
mid-transaction, a file descriptor, a kernel-managed resource), it isn't user
state at all — it's the host engine's state, and the engine handles its lifecycle
around the snapshot transparently to Caspian code.

This is a stronger position than "we haven't built the hooks yet." It's a design
choice that pushes external-resource management out of user code entirely. If we
ever discover a case where it genuinely can't be — where a Caspian class
unavoidably needs to participate in pre-pause/post-resume cleanup — we'll revisit.
Until then, treat the absence of these hooks as deliberate.

---

<a id="future-possibilities"></a>
## Future possibilities

These are not commitments, just things worth noting as the V1 design rules in or
rules out without saying so:

<a id="future-promise-all-and-race"></a>
### Parallel-promise combinators

If real workloads need to fire N HTTP requests and wait for all/any of them,
`promise_all([reqs])` and `race([reqs])` are the natural shape. The snapshot
mechanism doesn't need to change — only the dispatcher's correlation-tracking does.

<a id="future-non-http-promise-sources"></a>
### Non-HTTP promise sources

Filesystem, database, message queue, system-process-completion, human approval —
any operation that can be "fire and wait" is in principle a candidate. None
known to be needed for V1. Each new source would need its own request class
exposing `promise()`.

<a id="future-timeouts"></a>
### Timeouts

`puck.uno/http/request` could grow a `timeout` parameter that bounds how long
the wait can take before the promise raises a `puck.uno/error/timeout`. Same
under-the-hood — just expires the correlation ID after a deadline.

<a id="future-snapshot-replay-debugging"></a>
### Snapshot-as-debugging-tool

The snapshot infrastructure built for Skeletor is the same infrastructure
needed for time-travel debugging. Once Skeletor exists, "save the snapshot
on uncaught error, let the developer revive locally" is a small layer on top.

---

<a id="open-questions"></a>
## Open questions

<a id="open-engine-permission-model"></a>
### Engine permission model

How does the embedding engine grant a Caspian program permission to call
`promise()`? Options sketched, none chosen:

- A capability passed at engine setup: `%engine.allow_promise(true)` or similar
- A role-based check: programs running in a certain role have it; others don't
- A method-missing-style runtime intercept: every `promise()` call asks the
  engine "is this allowed?"
- A static check at code load: program declares it uses promises; engine
  decides at load time

<a id="open-snapshot-storage-location"></a>
### Snapshot storage location

Where do snapshots live during the pause? Local disk on the host that wrote
them? A shared object store (Mikobase worldlet)? A network-accessible blob
store so a different host can pick up the revive? Affects whether crash
transparency works across host failures.

<a id="open-snapshot-format-versioning"></a>
### Snapshot format versioning

A snapshot taken with Caspian V1.2 — can it be revived by Caspian V1.3? V2.0?
If not, deployments mid-flight could leave un-revivable snapshots. Spec needs
a compatibility rule.

<a id="open-snapshot-ttl"></a>
### Snapshot TTL

A snapshot for a request whose response never arrives is a leak. How long does
the runtime hold a snapshot before giving up? Per-request? Global default?
On expiry, does the promise raise `puck.uno/error/timeout` (requiring revive
just to deliver the error) or just silently drop?

<a id="open-side-effects-during-pause"></a>
### Side effects during the pause

Between snapshot and revive, the outside world changes. Files get modified,
database rows change, other Caspian processes mutate shared Mikobase state.
The revived program assumes its view of the world is current — it isn't.
Same problem as restoring a backup. Worth a doc note; probably not solvable
at the runtime level.

<a id="open-dispatcher-implementation"></a>
### Dispatcher implementation

The external dispatcher (the thing that holds the HTTP request and watches for
the response) is its own component. Is it part of every Caspian engine? A
sidecar daemon? A Puck-protocol service that engines talk to? Different choices
have different operational costs.
