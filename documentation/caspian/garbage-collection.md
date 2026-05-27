# Garbage Collection

~~~json
{"vibecode": {
	"doc": "garbage_collection",
	"role": "spec for Caspian's deterministic garbage collection — root-trace model, on_close hook semantics, and the strict rules that keep cleanup fast and predictable",
	"section": "garbage_collection",
	"model": "deterministic_gc_immediate_collection_on_unreachable",
	"mechanism": "root_trace_not_reference_counting",
	"cycles": "handled_automatically",
	"close_method": "called_by_gc_not_user_code"
}}
~~~

<a id="deterministic-garbage-collection"></a>
<a id="perfect-garbage-collection"></a>
## Deterministic garbage collection

Caspian uses **deterministic garbage collection**: when an object becomes unreachable,
the runtime immediately collects it and calls a standard cleanup method on it. There are
no GC pauses, no periodic sweeps, and no tuning parameters. Collection happens at a
known, deterministic moment — the moment the last reference is severed.

No weak references are needed. No special lifetime annotations. No manual memory
management.

<a id="how-it-works"></a>
## How it works

Objects live in the engine's heap. They do not know what references them — they simply
exist until nothing holds them.

When a reference to an object is severed, the runtime traces from roots to determine
whether the object is still reachable. If it is not reachable from any root, the runtime
calls the object's close method and collects it.

Because this is a root trace rather than reference counting, cycles are handled
automatically. Two objects that reference each other but are held by nothing else are
both unreachable from roots — both are collected.

**The trace's root set is the uspace references** — reference
objects whose class declares `uspace: true`. Variables in live
frames are the canonical example; system-surface references
(`%foo`, etc.) declare the property too. Hash elements and
engine-internal references don't, so they're not roots in their
own right — they're reachable only through the chain of objects
that some uspace root points at. The `references` hash inside
Skeletor (see [references.md](skeletor/references.md)) maps every
reference object to the object it points at, making the trace
tractable without reference counting. This is what makes
deterministic GC work: every reference is in one hash, every root
declares itself via a class-level property, and the engine fires
the trace at every reference mutation that could drop something
out of reachability.

<a id="on-close"></a>
<a id="fooobjectclose"></a>
## `on_close`

~~~json
{"vibecode": {
	"section": "on_close",
	"role": "class-body BWC that registers a cleanup handler called by deterministic GC at scope exit; multicast across every platter in the object's class stack that defines it",
	"namespace": "separate from the class's main method namespace — not callable from user code",
	"called_as": "engine_invokes_each_matching_on_close_handler_top_of_stack_first",
	"dispatch_kind": "multicast; contrast with normal method calls which are unicast (first match wins)",
	"strictness": "hard 2ms cap PER HOOK enforced by raising puck.uno/error/gc_timeout which the engine catches per-hook, no resurrection, no allocation, no reliance on collection order; engine-wrapping catch around EACH invocation catches any exception (user-raised or engine-emitted) and routes to state.gc_errors; one platter's bad handler does not suppress the others; no_io is guidance backed by the cap, not a separate runtime check",
	"escape_hatch": "none in V1 — strict by design; revisit if the community has a concrete need for finer-grained control"
}}
~~~

`on_close` is a regular function on the class with its `on_call`
property set to `:all` — that's what makes it multicast (see
[lucy.md § `on_call` property](lucy/lucy.md#on-call-property)).
The engine fires it automatically during collection; user code
calling `$foo.on_close` directly is possible but unusual — the
`on_*` name is convention signaling "this is for the engine to
fire," not enforced. The runtime calls the matching handlers
automatically the moment the object becomes unreachable. Per
[deterministic garbage collection](#deterministic-garbage-collection),
that moment is deterministic: the variable that held the last
reference goes out of scope and the runtime traces, frees, and
runs the `on_close` handlers immediately.

<a id="on-close-multicast"></a>
### Multicast across platters

`on_close` is **multicast dispatch**, in contrast to normal method
calls which are unicast (first match wins). When an object collects,
the engine walks every platter in its class stack and fires *every*
`on_close` handler it finds — not just the first one.

The walk:

1. Iterate platters **top to bottom** (newest addition first,
   original class last).
2. For each platter, walk its class's `inherits` chain with a
   visited set (same dedup discipline as normal dispatch — see
   [base-class-use.md § Method resolution](../ideas/base-class-use.md#method-resolution)).
3. For each distinct class encountered, if the class defines
   `on_close`, invoke it.

Top-first ordering mirrors typical destruction-reverses-construction:
the most recently added platter cleans up first, which is most
likely the one depending on earlier layers being intact.

**Each hook is wrapped independently** in the engine's catch-anything
(see [below](#on-close-catch-anything)). One platter's bad handler
raising or timing out doesn't suppress the others — each runs
inside its own protected frame, errors accumulate as separate
entries in `state.gc_errors`, and the next handler still fires.

**The 2 ms cap applies per hook**, not as a budget shared across an
object's handlers. An object with three `on_close` handlers gets
2 ms each. Per-hook keeps the budget predictable for each class
designer; if that turns out to be too generous in aggregate, a
total cap can be layered on later.

```caspian
$foo.object.classes   # has platters for myapp.com/connection,
                      # logging.uno/audit, and the base class

# When $foo collects:
#   1. connection's on_close fires first (top of stack) → 2ms budget
#   2. then audit's on_close                            → 2ms budget
#   3. then any inherited on_close found in the walk    → 2ms budget each
```

The same multicast model applies to any future class-body lifecycle
hook (`on_create`, `on_freeze`, `on_thaw`, etc.) when those land. See
[#343](https://github.com/mikosullivan/puck/issues/343) for the
broader formalization.

```caspian
class 'myapp.com/connection'
    on_close do($call)
        @socket.close
    end
end
```

`$call` is the same structured-call object passed to `method_missing` and other
class-body call hooks. For `on_close`, `$call.receiver` is the dying object and
`$call.platter` is the platter whose `on_close` is currently firing (so the handler
knows which class it's running as, useful when a single object has multiple
`on_close` hooks). The other fields (`args`, `opts`, `block`, `super`) are null —
the GC isn't passing arguments.

The handlers run synchronously in the calling function's stack — the function that drops
the last reference pays the cleanup cost as part of its own runtime. That makes the
strict rules below essential: slow, allocating, or fragile handlers don't just break
themselves; they break the calling code in non-obvious ways.

<a id="on-close-2ms-cap"></a>
### 2 ms hard cap

The handler must complete within **2 milliseconds** of starting. If it doesn't,
the runtime **raises a `puck.uno/error/gc_timeout` exception** at the handler's
current PC. The exception is caught by the engine's wrapping catch (see
[catch-anything](#on-close-catch-anything) below) — user code can't intercept
it because the catch is outside the user's handler body. The cleanup is
incomplete; whatever the handler hadn't done is left undone. The runtime stays
responsive.

Two milliseconds is generous compared to legitimate cleanup work: closing a file
descriptor, closing a socket, freeing a buffer, releasing an external refcount — all
single-digit microseconds. Anything that actually hits 2 ms is almost certainly doing
the wrong thing: I/O the developer didn't realize was I/O (a logger flushing, an ORM
committing), a complex computation, or a syscall that blocks (`SO_LINGER` on a socket
will).

If your cleanup work doesn't fit in 2 ms, it doesn't belong in `on_close`. Do it
explicitly on the object before scope exit; let `on_close` handle only the trivial
OS-handle release.

<a id="on-close-no-resurrection"></a>
### No resurrection

The handler cannot add the receiver to any reachable location. If it tries — assigning
the receiver to a global, stashing it in another live object's field, returning it from
the enclosing function via a side-channel — the runtime raises immediately, the
assignment is rejected, and the object dies as planned. This avoids the
Java/.NET-style "object resurrected, finalizer skipped on second pass" machinery.

<a id="on-close-allocation-allowed"></a>
### Allocation is allowed

Creating new Caspian objects inside `on_close` is fine. Temporary buffers,
formatted strings, intermediate hashes — whatever fits in the 2 ms cap is
fair game. Objects allocated locally go out of scope when the handler
returns; they collect normally afterward in their own cleanup pass (not
nested inside the current one).

What's NOT allowed is reaching out to acquire resources the handler
didn't already have a connection to — opening a new file, connecting to
a database, starting a process. Those count as I/O (above) and are
enforced by the 2 ms cap, not a separate allocation rule. If the
allocation completes in bounded time without touching the outside world,
it's fine.

(An earlier version of this spec banned allocation outright as a
guard against nested-GC recursion. That guard was overcautious —
deterministic GC fires at reference removal, not allocation, so
local allocations don't trigger nested collection. The cap is the
real enforcement.)

<a id="on-close-no-io"></a>
### No I/O (guidance, not a hard ban)

`on_close` handlers should not do I/O — network calls, file reads/writes, process
spawns, anything that can block. But this is **guidance**, not a separate
runtime check. The 2 ms cap is the actual enforcement: anything that blocks long
enough to matter will be aborted by the cap.

That deliberately puts the responsibility on the programmer. Closing a socket
in `on_close` is fine — until you've configured `SO_LINGER` on it, at which
point `close()` can block past the cap and you'll see the abort. The fix is
not for the runtime to maintain a syscall allowlist; the fix is to either
clear `SO_LINGER` before the object goes out of scope or close the socket
explicitly outside of `on_close`. The runtime doesn't try to second-guess
which file descriptors are "really" non-blocking; it just enforces the
cap.

This matches the "no nanny code" instinct: developers can write the obvious
thing (`@socket.close`) without the runtime intervening, and the cap catches
misuse without a special-case rule for every possible syscall.

<a id="on-close-catch-anything"></a>
### Engine wraps the handler in a catch-anything

Every `on_close` invocation runs inside an engine-level `try`/`catch` placed
at the call site where the engine invokes the handler — physically outside
the user's handler body. **Anything** that escapes the handler is caught
there:

- A user-raised exception bubbles up out of the handler and into the
  engine's catch.
- A violation (resurrection attempt, allocation attempt, etc.) raises an
  engine-emitted exception that the engine's catch handles.
- The 2 ms cap firing raises `puck.uno/error/gc_timeout` mid-handler;
  same catch handles it.

User code can `try`/`catch` inside the handler all it wants — but the
engine's catch is one frame further out and always wins for any exception
the engine itself raises (gc_timeout, no_resurrection, no_allocation,
etc.). Those exceptions are in an engine-protected class hierarchy that
ordinary user catches don't match. Without this protection, a handler
could spin: catch its own gc_timeout, keep going, catch the next one,
never letting the runtime move on.

If the engine's own catch ever fails — say, allocating the
`state.gc_errors` record runs out of memory — the engine reaches an
untenable state and halts. That's a Caspian bug to be fixed, not a
runtime condition the program needs to plan around.

<a id="on-close-deepest-first-order"></a>
### Cleanup order: deepest first

During a single GC pass, multiple objects may be unreachable and queued
for cleanup. The order is **deepest-first** — objects further from the
roots in the reachability graph have their `on_close` fired before
objects closer to the roots. Equivalently: inner objects close before
the containers that held them.

If an outer object's bucket pointed at an inner object, and both are
collecting in the same pass, the inner object's `on_close` fires first.
By the time the outer's `on_close` runs, the inner is already gone —
and the outer's bucket key that used to point at the inner now holds
plain `null`. The bucket key is preserved; only the value at that key
changes.

```caspian
# Outer object's bucket before collection:
%bucket = {bear: <ref to inner>}

# After inner's on_close completes and inner is collected:
%bucket = {bear: null}
```

`%bucket.has?('bear')` continues to return `true` — the key stays.
`%bucket['bear']` returns plain null (no flavor — keeping the null
type uniform regardless of why the slot is null).

The outer's `on_close` can read its bucket and see the structure of
what it used to hold. It can do pool-level / parent-level cleanup
without depending on the children being alive. It does NOT have to
recursively close children; the engine handled them already.

Practical consequences:

- **Connection pool (outer) with connections (inner):** each connection's
  `on_close` fires first to release its FD; the pool's `on_close` then
  does pool-level cleanup. The pool doesn't need to iterate connections
  to close them — that already happened.
- **File (outer) with buffer (inner):** the buffer's `on_close` flushes
  first; the file's `on_close` then closes the FD.
- **Tree node with children:** children close before parent.

**Cycle edge case.** If outer and inner reference each other and both
become unreachable together, there's no "deeper" between them. The
engine breaks the tie deterministically (typically by `object_id`
order) but the ordering within a cycle is essentially arbitrary. Within
a cycle, neither participant should depend on the other being alive.

<a id="on-close-errors"></a>
### Errors during on_close

Any exception caught by
[the engine's wrapping catch](#on-close-catch-anything) — user-raised
exceptions, violation exceptions, gc_timeout — is recorded as a
structured entry appended to `state.gc_errors`, then the engine
continues with other collections. One buggy `on_close` cannot break GC
for the whole process.

The record shape:

```json
{
  "class":   "myapp.com/connection",
  "message": "socket close failed: broken pipe",
  "src":     ["a", 9]
}
```

`state.gc_errors` is a top-level Skeletor field — an array that starts empty
and accumulates one record per on_close failure for the program's lifetime.
Why a list in state rather than a write to a diagnostic stream:

- It lives in Skeletor, consistent with the principle that all observable
  engine state is in the hash.
- It's inspectable from any snapshot — a debugger seeing a long `gc_errors`
  list immediately sees something's wrong.
- Programs can read it if they want (e.g., check `%state.gc_errors.length`
  at shutdown to see if anything went wrong during cleanup).
- It survives snapshot/revive cleanly: the receiver knows exactly what
  cleanup failures happened in the sending process.

This is **not** the per-frame `chain` mechanism. `chain` is frame-scoped
ambient context; `gc_errors` is process-wide engine state. They're different
things, and using different names keeps that clear.

The 2 ms cap abort (uncatchable, runs out the deadline mid-handler) is NOT
an error in this sense — the handler didn't raise, the engine just stopped
it. Whether timeout aborts also accumulate in `gc_errors` (or in a separate
`gc_timeouts` list, or nowhere) is an open design choice — see
[#332](https://github.com/mikosullivan/puck/issues/332).

<a id="on-close-future-budgets"></a>
### Future: per-class budgets and escape hatches

The 2 ms cap is a deliberate default — strict, uniform, no opt-out. If the community
has a real need for finer-grained control (per-class budgets, optional async cleanup
queue for heavy work, escape hatches for specific use cases), that's a conversation
worth having when the use case is concrete. V1 ships the strict version on purpose:
loosening is easier than tightening once people have written code that depends on the
looser behavior.

<a id="the-rule"></a>
## The rule

Objects die when they become unreachable from roots. That's the whole model — one rule
covers every object in the system.
