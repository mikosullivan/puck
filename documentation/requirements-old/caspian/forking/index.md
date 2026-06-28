# Forking

~~~vibecode
{"vibecode": {
	"doc": "forking",
	"role": "spec for Caspian's forking — how user code spawns OS-level child processes; the fork-point call returns to both processes, with the return value discriminating parent (manager object) from child (null)",
	"status": "in progress — replaces an earlier design; examples added incrementally",
	"key_concepts": ["fork_point_call_returns_to_both_processes",
		"return_value_discriminates_parent_from_child",
		"parent_gets_manager_object",
		"child_gets_null",
		"if_child_is_the_parent_only_idiom"]
}}
~~~

Forking in Caspian follows the classic Unix `fork()` shape: a single call that returns in both the parent and the freshly-spawned child. The return value tells each side which one it is — the parent gets a fork manager object, the child gets `null`. Code that follows the fork point runs in both processes.

## Single fork

~~~caspian
$child = %utils.forks.branch

$child   # fork manager object in parent process
$child   # null in child

if $child
    $child.wait()
    $child.status   # only available after wait()
    $child.stdout   # only available after wait()
    $child.stderr   # only available after wait()
end
~~~

`%utils.forks.branch` is the fork point. After it returns, the script is running in two processes:

- **Parent.** `$child` holds the fork manager object. The parent can wait for the child to finish, inspect its exit status, read its captured output, etc.
- **Child.** `$child` is `null`. The child continues executing the script from this line forward, just without a manager.

The `if $child` block runs only in the parent. The child, with `$child` as null (a falsy value), skips it.

The full surface of the `$child` object — methods, properties, detaching — lives in [§ Child object](#child-object).

## Fork manager

A fork manager provides a wider range of features for managing forked processes. The fork manager comes in two classes:

- A **base fork manager** has methods for managing an existing group of children — waiting for them, signalling them, killing them. [`%utils.forks.all`](#all-tracked-children) returns an instance of this class.
- The **extended fork manager** is a subclass that adds the methods needed to *create* groups of children: `.multiple`, `.max`, and the `.harvest` callback for reaping notifications. `%utils.forks.manager.new()` returns this class.

~~~caspian
$mgr = %utils.forks.manager.new()
~~~

The split is type-honest: `%utils.forks.all` returns a fresh manager every call, so a `.harvest` closure registered on one would silently disappear with the manager — confusing behavior. Putting `.harvest` only on the extended class means calling `%utils.forks.all.harvest do ... end` fails loudly (method-not-found), the way the developer needs.

### Base methods

The methods on the base class. Available on every fork manager — both `%utils.forks.all` and `%utils.forks.manager.new()`.

| Method | Description |
|--------|-------------|
| `.wait` | Blocks until every child in the manager's group has been reaped. |
| `.kill(signal)` | Sends a signal to every child in the group. See [Signal severity](#signal-severity). |
| `.term_kill(grace: 2)` | Polite-then-forceful shutdown across the whole group: send `:term`, wait up to `grace` seconds, then `:kill` any that haven't exited. |

The remaining subsections cover **extended-class methods** — available on `%utils.forks.manager.new()` but not on `%utils.forks.all`.

### Multiple forks

`.multiple(N)` spawns `N` children at once and runs the same block in each.

~~~caspian
# run 20 forks
$mgr.multiple(20) do
end

# wait for all the forks
$mgr.wait
~~~

The manager's `.wait` blocks until **every** child it spawned has finished. This is different from calling `.wait()` on an individual child manager (which blocks on just that one) — the manager-level `.wait` is the join point for the whole group.

Pass `wait: true` to fold the join into the spawn call:

~~~caspian
# run 20 forks, wait for them all to finish
$mgr.multiple(20, wait: true) do
end
~~~

Same behavior as the two-step form; just no separate `.wait` line. Convenient when you have nothing else for the parent to do between the spawn and the join.

### Branch

`$mgr.branch do ... end` spawns one child under the manager's tracking. **The block is the child's body** — the parent continues past the `do/end` immediately, the child runs the block content and exits when it finishes. Calling without a block is not allowed in V1.

~~~caspian
$child = $mgr.branch do
    # child process body
end

# parent reaches here right away, child is still running
~~~

The return value is the per-child object (see [Child object](#child-object)). Capturing it is optional — the manager already tracks the child, so `$mgr.wait`, harvest, and group operations all find it without the caller holding the reference.

If a concurrency cap is set via `.max =` (below), `.branch` blocks until a slot frees before spawning.

> V1 requires a block. The Unix-style standalone form `$child = $mgr.branch` — no block, returns to both processes — is not supported through a manager. Reach for bare [`%utils.forks.branch`](#single-fork) if you want that shape. We'll revisit if the community wants the no-block form on managers too.

### Maximum concurrent forks

`$mgr.max` is a property on the manager that caps how many children can run concurrently. Set it once, and every subsequent `.branch` (and any `.multiple` calls) honor the cap — spawn attempts that would exceed it block in the parent until a slot frees, then proceed.

~~~caspian
$mgr.max = 20

100.times do
    $mgr.branch do
        # child process
    end
end

$mgr.wait
~~~

At any moment during the loop, at most 20 children are running. As each one finishes, the next spawn proceeds. After all 100 spawn attempts complete, `$mgr.wait` joins the whole group.

The cap is a property of the manager, not of any block scope — set it once, change it later if you need to, leave it alone if you don't.

- `$mgr.max = N` (positive integer) — at most `N` children concurrent.
- `$mgr.max = null` — no cap (the default). `.branch` always spawns immediately.
- Reading `$mgr.max` returns the current value.

The cap applies only to spawns the manager is aware of — bare `%utils.forks.branch` calls don't count.

### Harvesting completed children

`$mgr.harvest do($child) ... end` registers a closure that runs each time one of the manager's children is reaped. The closure receives the reaped child's manager object. Its `.status`, `.stdout`, and `.stderr` are all available inside the closure.

~~~caspian
$mgr = %utils.forks.manager.new()

$mgr.harvest do($child)
    puts 'child finished with status ' + $child.status
    puts $child.stdout
end

$mgr.multiple(20, wait: true) do
    # child body
end
~~~

Calling `.harvest` by itself does nothing — it just stores the closure on the manager. The closure fires later, inside `$mgr.wait()` (or the equivalent `wait: true` variant of any spawn call). Each time the wait reaps a child, the manager passes that child's manager object to the closure before continuing on to the next reap.

Two behaviors worth being explicit about:

- **`$mgr.wait()` is wait-all.** It blocks until *every* child the manager spawned has been reaped — what other languages call `waitall`. Different from calling `.wait()` on an individual child manager (which blocks on just that one).
- **Set `.harvest` before any spawning.** The closure must be in place by the time the wait phase begins, since reaping only happens during the wait. The conventional order is `.harvest`, then spawn, then wait — even though setting it any time before the wait will work.

The harvest closure is optional. If unset, children are still reaped during `$mgr.wait()`; the parent just doesn't get a per-child callback. Per-child status remains readable directly on each manager object afterward.

## Child object

The `$child` returned by [`%utils.forks.branch`](#single-fork), [`%utils.forks.detach`](#detaching), and every spawn through a [fork manager](#fork-manager) is the same kind of object: a per-child handle that the parent uses to inspect, wait on, signal, or terminate one specific child process. The harvest closure ([§ Harvest](#harvest)) receives this same object as `$child`.

### Methods

| Member | Availability | Description |
|--------|--------------|-------------|
| `.active?` | always | `true` if the child process is still running. |
| `.detach` | always | Promote a tracked child to detached. No-op if already detached. See [Detaching](#detaching). |
| `.detached?` | always | `true` if the child is detached (not tracked by the engine). |
| `.exists?` | always | `true` if the OS still has any record of the process (active or zombie). False once the process has been fully reaped and removed from the process table. |
| `.kill(signal)` | always | Sends a signal to the child. See [Signal severity](#signal-severity). |
| `.status` | after `.wait()` | The child's OS exit code. |
| `.stderr` | after `.wait()` | Output the child wrote to its stderr, captured by the engine. |
| `.stdout` | after `.wait()` | Output the child wrote to its stdout, captured by the engine. |
| `.term_kill(grace: 2)` | always | Polite-then-forceful shutdown: send `:term`, wait up to `grace` seconds for the child to exit on its own, then send `:kill` if it hasn't. Grace is in seconds; default is 2. |
| `.tracked?` | always | `true` if the child is tracked. Opposite of `.detached?`. |
| `.wait()` | always | Blocks the parent until the child exits. |
| `.zombie?` | always | `true` if the child has exited but its exit status hasn't been collected yet — i.e., the child is dead but no `.wait()` has been called to reap it. |

### Detaching

A **detached** fork is one the engine does not track. It survives the parent script's exit and runs on its own from then on.

~~~caspian
$child = %utils.forks.detach

if $child
    # parent — $child has the same surface as a branched fork's manager
end
~~~

The fork manager object exposes the same members as for a branched fork (`.wait()`, `.kill(signal)`, `.status`, `.stdout`, `.stderr` — same availability rules). The difference is what happens around it:

- **No tracking.** The engine doesn't keep a record of the child. The parent's manager object is the only handle to it.
- **No auto-kill at script end.** Detached children survive the parent script's exit. They are NOT swept by the [auto-kill](#auto-kill-at-script-end) behavior, do NOT trigger the post-script exception, and do NOT influence the script's exit code.
- **Waiting is optional.** The parent can call `.wait()` if it wants to block on the child, but isn't required to — the child will keep running either way.

Use detach when the child genuinely needs to outlive the parent — daemon spawning, background workers that should survive a script restart, etc. Use branch for everything else and let the safety net catch leaks.

A tracked child can be promoted to detached at any time by calling `.detach` on its manager. The conversion is one-way — there's no way to re-track a detached child (the engine has already let go of it).

## Auto-kill at script end

Every tracked child process is automatically killed when the parent script ends. A developer who forks something and forgets to `.wait()` or `.kill()` it doesn't accidentally leave stray processes behind — the engine cleans up.

When the engine kills a tracked child this way, it treats the leftover process as a defect, not a clean shutdown:

- The script's **return value is non-zero** so the runner / shell / CI step can see that something went wrong.
- An **exception is raised after the script has finished**, surfacing which children were killed and why, so the developer gets a visible signal instead of a silent cleanup.

The intended habit is: every fork you spawn, you also wait for or explicitly kill. If you forget, the engine catches it and complains.

### All tracked children

Any role can reach for the tracked children:

~~~caspian
%utils.forks.all
~~~

Returns a fresh [base fork manager](#fork-manager) whose group is the set of currently-tracked children. (Base, not extended — `.harvest` and the spawn methods are deliberately absent.) What's included depends on the caller's role:

- **`user` role** sees every tracked child the engine knows about.
- **Any other role** sees only the children it spawned itself. Children spawned by the user or by other roles are not visible.

Because it's a fork manager, it carries the full manager surface. Most useful applications are group-level operations across everything the caller can see:

~~~caspian
%utils.forks.all.wait          # block until every tracked child is reaped
%utils.forks.all.term_kill()   # polite-then-forceful shut down of every tracked child
~~~

`.harvest` and the rest of the manager API apply the same way — registered on this object, they fire across the visible group.

### Disabling auto-kill

The behavior can be turned off:

~~~caspian
%engine.auto_close_forks = false
~~~

After this assignment, tracked children are no longer killed at script end — they survive the parent script and keep running on their own. No exception is raised; the script exits with whatever return value the user code chose. Useful when a script's entire purpose is to spawn long-lived workers and the developer is taking explicit ownership of their cleanup.

**User-role only.** Like every other `%engine` property, this assignment is restricted to the `user` role; nested libraries and other roles cannot reach `%engine` at all and so cannot flip this setting. The default-safe behavior can only be disabled by the user's own code, never silently by a library.

## Signal severity

`.kill` sends a signal to the child. Despite the method name, "kill" doesn't necessarily kill — it sends whatever signal you pick, and what that signal does depends on whether the child has installed a handler for it. The default is `:term`, the polite "please exit."

The options, from gentlest to most forceful:

| Symbol | OS signal | What it does | Can the child catch it? |
|--------|-----------|--------------|--------------------------|
| `:hup` | SIGHUP | "Your terminal closed." Long-running services conventionally treat this as "reload your config." | Yes; default is to exit. |
| `:int` | SIGINT | Interactive interrupt — what `Ctrl+C` sends. | Yes; default is to exit. |
| `:term` | SIGTERM | Polite "please exit." Lets the child clean up — close files, finish a write, run shutdown handlers. **Default.** | Yes; default is to exit. |
| `:quit` | SIGQUIT | Like `:term`, but additionally produces a core dump for post-mortem debugging. | Yes; default is to dump and exit. |
| `:kill` | SIGKILL | Forcible termination. The kernel terminates the process immediately, no cleanup. | **No.** Cannot be caught, blocked, or handled. |

There are also two pause/resume signals for suspending a child without killing it:

| Symbol | OS signal | What it does | Can the child catch it? |
|--------|-----------|--------------|--------------------------|
| `:stop` | SIGSTOP | Pauses the child. Execution freezes mid-instruction. | **No.** |
| `:cont` | SIGCONT | Resumes a previously stopped child. | Yes; default is to resume. |

Usage:

~~~caspian
$child.kill              # default — same as $child.kill(:term)
$child.kill(:term)       # polite ask; child cleans up
$child.kill(:kill)       # forceful; child has no say
$child.kill(:hup)        # "reload your config" if the child treats it that way
~~~

**Rule of thumb:** start with `:term` and give the child a moment to exit on its own. Escalate to `:kill` only if it doesn't. `:hup`, `:int`, and `:quit` are situational — reach for them when the child specifically advertises that it responds to them.
