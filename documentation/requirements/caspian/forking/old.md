# Forking

~~~vibecode
{"vibecode": {
	"doc": "forking",
	"role": "spec for Caspian's forking feature — how user code spawns OS-level child processes, how the engine prevents zombie processes by default, the three spawn forms (tracked single, tracked pool, detached), and the manager-handle pattern for inspecting and controlling spawned children.",
	"status": "committed for V1.0 — three spawn forms, closure semantics, auto-close-at-script-end, disabling-auto-close via %engine.auto_close_forks all settled. Open points (manager-handle details, IPC, role/resource inheritance, crash behavior, grace period) settle during implementation rather than block design. Required by UDS, shared-hash, and the broader server-with-workers pattern.",
	"supersedes": "all prior fork mentions in syntax/system-methods.md, cli.md, frank.md, network/http/server/sammy/index.md, packages/bryton/runner.md, packages/jasmine/index.md, built-in-classes/filesystem.md, and incidental references elsewhere",
	"key_concepts": ["all_forking_lives_under_percent_utils",
		"three_spawn_forms_single_multiple_detach",
		"engine_auto_closes_tracked_forks_at_script_end",
		"detached_processes_survive_script_end",
		"standard_closure_semantics_for_the_block",
		"manager_handle_returned_from_every_spawn"]
}}
~~~

## Avoiding zombies

This design tries to make easy to avoid accidentally creating zombie processes. By default, every fork the user code spawns is tracked by the engine and automatically closed when the script ends. A developer who forgets to wait, reap, or kill a child doesn't pay for it with a polluted process table.

Detached processes are the explicit opt-out: code that genuinely wants a child to outlive the script uses `%utils.detach`, which is described separately below. Everything else gets the safety net.

---

<a id="three-spawn-forms"></a>
## Three spawn forms

All three live under `%utils`. No top-level `%forks` namespace.

### `%utils.forks.single()` — one tracked fork

~~~caspian
$mgr = %utils.forks.single() do
	# code that runs in the child process
end
~~~

Spawns one OS-level child. The child runs the block; the parent gets a manager handle (`$mgr`).

### `%utils.forks.multiple(N)` — pool of N tracked forks

~~~caspian
$multi_mgr = %utils.forks.multiple(20) do
	# code that runs in each child process
end
~~~

Spawns `N` OS-level children. Each child runs the same block independently.

Worker-pool primitive — common patterns include spawning N workers that poll a shared queue or read from a shared input source.

### `%utils.detach()` — one detached fork

~~~caspian
$mgr = %utils.detach() do
	# code that runs in the detached process
end
~~~

Same shape as `forks.single`, but **the child is not tracked by the engine and is not auto-closed at script end**. The parent's handle (`$mgr`) still exists for inspection and explicit control, but the lifecycle is no longer tied to the parent script's.

Use when the child genuinely needs to outlive the parent — daemon spawning, background workers that should survive a script restart, etc.

---

<a id="closure-semantics"></a>
## Closure semantics

The block passed to any of the three spawn forms captures the parent's lexical environment at fork time. Standard closure behavior.

- The child sees a **snapshot** of the parent's state as it was when the fork call happened.
- Mutations on either side after the fork **do not propagate** — the two processes have separate memory.
- This is consistent with how `fork(2)` works at the OS level: the kernel duplicates the address space; from that moment on, the two processes diverge.

No fresh-state / clean-slate mode. Spawn block always sees what was in scope.

---

<a id="auto-close-at-script-end"></a>
## Auto-close at script end

When the script terminates (normal exit, uncaught exception, signal, or any other path that ends the run), the engine **automatically closes any tracked forks** that are still alive.

- **Detached forks are not affected.** They keep running.
- **Tracked forks** (created via `%utils.forks.single` or `%utils.forks.multiple`) get cleaned up:
  - SIGTERM with a brief grace period so they can exit cleanly.
  - SIGKILL if they don't exit within the grace period.
  - Exit statuses reaped so nothing ends up as a zombie even briefly.

This makes the common case zombie-safe by construction. A developer who forks something and forgets to reap doesn't accidentally leave processes behind.

### Disabling auto-close

The behavior can be turned off:

~~~caspian
%engine.auto_close_forks = false
~~~

After this assignment, tracked forks are no longer cleaned up at script end — they survive, just like detached forks. Useful when a script's entire purpose is to spawn long-lived workers and using `%utils.detach` for every one would be tedious.

**User-role only.** Like every other `%engine` property, this assignment is restricted to the `user` role; nested libraries and other roles cannot reach `%engine` at all and so cannot flip this setting. The default-safe behavior cannot be silently disabled by anything other than the user's own code.

---

<a id="manager-handle"></a>
## The manager handle (`$mgr`)

Every spawn form returns a manager handle. The shape isn't fully spec'd yet, but it's expected to expose at least:

| Field / method | Purpose |
|---|---|
| `.pid` | OS process ID of the child (for single-child handles). |
| `.state` | Current state — `:running`, `:exited`, `:killed`, etc. |
| `.exit_code` | Available after the child has exited. |
| `.kill` | Terminate the child. |
| `.wait` | Block the parent until the child exits. |
| `.alive?` | Quick boolean check. |

The handle for `%utils.forks.multiple(N)` manages a pool rather than a single child; whether it exposes collective methods (`.kill_all`, `.wait_all`, `.alive_count`), an iterable array of per-child mgrs, or both is open.

---

<a id="open-points"></a>
## Open points

- **`$multi_mgr` shape.** Collective-methods-only, array-of-mgrs, or both? Affects how a parent works with a pool of children.
- **Parent/child communication.** No IPC primitive in the language today. Whether to add explicit `.send(message)` / `.receive` methods on `$mgr`, or whether to lean on the [event system](../events/) (parent registers listeners on `$mgr`; child broadcasts back via `%utils.broadcast`), or some other shape — TBD.
- **Per-child identification.** Children spawned via `%utils.forks.multiple(N)` have no in-band way to know which one they are. If a workload needs per-child distinction (logging to different files, sharding work by index, etc.), the mechanism for that hasn't been chosen yet.
- **Role inheritance.** What role does the child process run as? Same as parent at fork time? Configurable? Restricted in any way?
- **Resource inheritance.** Which engine-granted resources does the child inherit — `%net`, `%tmp`, fs handles, open sockets, environment variables? All? None? Configurable per fork?
- **Behavior on child crash.** Does the parent get notified (event broadcast? exception?)? Is there an auto-restart pattern, or is that left to user code?
- **Grace period for SIGTERM-before-SIGKILL.** Configurable, or fixed by the engine?
- **Detached process introspection.** `$mgr` for a detached process — does it have all the same methods (`.kill`, `.wait`, etc.) even though the engine isn't actively tracking the child? Probably yes, but worth confirming.
- **Multiple-detach form.** Does `%utils.detach.multiple(N) do ... end` exist as a parallel to `forks.multiple`, or is detaching always single-child? Probably the latter, but the symmetric option is available.
