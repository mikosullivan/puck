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

Objects live in object space. They do not know what references them — they simply exist
until nothing holds them.

When a reference to an object is severed, the runtime traces from roots to determine
whether the object is still reachable. If it is not reachable from any root, the runtime
calls the object's close method and collects it.

Because this is a root trace rather than reference counting, cycles are handled
automatically. Two objects that reference each other but are held by nothing else are
both unreachable from roots — both are collected.

<a id="on-close"></a>
<a id="fooobjectclose"></a>
## `on_close`

~~~json
{"vibecode": {
	"section": "on_close",
	"role": "class-body BWC that registers a cleanup handler called by deterministic GC at scope exit",
	"namespace": "separate from the class's main method namespace — not callable from user code",
	"called_as": "$foo.object.close (by the runtime; never by user code)",
	"strictness": "hard 2ms cap, no resurrection, no allocation, no I/O, no catching the abort, no reliance on collection order",
	"escape_hatch": "none in V1 — strict by design; revisit if the community has a concrete need for finer-grained control"
}}
~~~

`on_close` is a **class-body hook**, not a method. It registers a cleanup handler the
runtime calls during garbage collection. It does not live in the class's main method
namespace — `$foo.on_close` is not a thing user code can call, and `$foo.close` is not
either. The runtime calls the handler exactly once, automatically, the moment the object
becomes unreachable. Per [deterministic garbage collection](#deterministic-garbage-collection), that
moment is deterministic: the variable that held the last reference goes out of scope and
the runtime traces, frees, and runs `on_close` immediately.

```caspian
class 'myapp.com/connection'
    on_close do($call)
        @socket.close
    end
end
```

`$call` is the same structured-call object passed to `method_missing` and other
class-body call hooks. For `on_close`, `$call.receiver` is the dying object; the other
fields (`args`, `opts`, `block`, `super`) are null, since the GC isn't passing arguments.

`on_close` runs synchronously in the calling function's stack — the function that drops
the last reference pays the cleanup cost as part of its own runtime. That makes the
strict rules below essential: slow, allocating, or fragile handlers don't just break
themselves; they break the calling code in non-obvious ways.

<a id="on-close-2ms-cap"></a>
### 2 ms hard cap

The handler must complete within **2 milliseconds** of starting. If it doesn't, the
runtime aborts the handler — uncatchable from inside the handler — and continues with
other collections. The cleanup is incomplete; whatever the handler hadn't done is left
undone. The runtime stays responsive.

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

<a id="on-close-no-allocation"></a>
### No allocation

Creating new Caspian objects inside `on_close` raises. Allocation can trigger nested
GC; in a single-threaded interpreter that's either recursion or starvation. If your
cleanup needs a "goodbye message" object or a temporary buffer, construct it before
scope exit and pass it in (capture it in the handler's closure via a class field).

<a id="on-close-no-io"></a>
### No I/O

Network calls, file reads/writes, process spawns, and other blocking operations are
rejected at the runtime call site with an explicit error: "on_close cannot call
`%file.read`." The 2 ms cap would catch most of these by timing them out, but the
explicit ban gives a sharper, earlier error — at the offending call site, not after
the handler has already partially run.

<a id="on-close-no-catching-the-abort"></a>
### No catching the timeout abort

The handler cannot `catch` its own forced termination. Without this rule, a handler
could spin: catch the abort, keep going, catch the next one, never letting the
runtime move on. The timeout abort is uncatchable to be a real cap.

<a id="on-close-no-reliance-on-cleanup-order"></a>
### No reliance on cleanup order

During a single GC pass, multiple objects may be unreachable and queued for cleanup.
The order in which their `on_close` handlers run is **undefined**. The handler can
safely touch `self`, fields that already held references when it started, and system
primitives — but it cannot reach for any other Caspian object, because that object
may already have been collected (or about to be) in the same pass.

<a id="on-close-errors"></a>
### Errors during on_close

If the handler raises, the runtime catches the error, logs it via `%chain.warn` (with
the class name and the error message), and continues with other collections. One buggy
`on_close` cannot break GC for the whole process.

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
