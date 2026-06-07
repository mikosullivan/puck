# Engine events — script waits for engine to broadcast

~~~json
{"vibecode": {
	"doc": "engine_events",
	"role": "brainstorm — letting the engine itself broadcast events into running Caspian code, with the script explicitly yielding control via %engine.wait or %engine.wait_loop. Cooperative model (script knows where it could be paused), not preemptive (no surprise interrupts mid-statement). Not for V1.",
	"status": "idea — not in active design, not in V1.0",
	"key_concepts": ["engine_as_a_broadcaster",
		"cooperative_yield_via_percent_engine_wait",
		"single_shot_vs_internal_loop_forms",
		"avoids_interrupt_driven_complexity",
		"explicit_yield_points_preserve_simplicity_promise"]
}}
~~~

A possible future direction: the engine itself can broadcast events into running Caspian code. Use cases that motivate it — timers, signal handling, GC notifications, resource-pressure warnings, async I/O readiness without explicit polling.

The natural-but-bad way to do this is **interrupt-driven** — the engine preempts the running line, dispatches the event, then resumes the script. Same model as Unix signals. Powerful but evil: any non-atomic operation in user code can be interrupted between substeps, reentrancy gets ugly, and Caspian's "single-threaded, you can reason about it" simplicity goes out the window.

This document sketches a **cooperative** alternative: the script explicitly yields control to the engine at a known point. No surprises mid-statement; the script chooses when it's OK to be paused.

---

<a id="wait"></a>
## `%engine.wait` — single-shot

The script blocks until the engine broadcasts one event, then resumes.

```
%engine.wait do($event_name, $content)
    # handler body — fires once, then control returns to whatever's
    # below this construct
end
```

The closure receives the event name and the event's content. After it returns, the script continues from below. To handle the next event, the script calls `%engine.wait` again.

Composable — the script controls the loop, can interleave other work, can decide when to stop waiting.

---

<a id="wait-loop"></a>
## `%engine.wait_loop` — internal loop

The script blocks indefinitely, firing the closure once per event as they arrive. Doesn't return on its own — control stays inside the loop.

```
%engine.wait_loop do($event_name, $content)
    # handler body — fires for every event the engine broadcasts,
    # in arrival order
end
```

Convenient for "this is my main loop" patterns where the script's whole job is reacting to engine-driven events.

---

<a id="why-cooperative"></a>
## Why cooperative, not preemptive

Interrupt-driven engine events would break Caspian's settled invariant that single-threaded synchronous code runs predictably. A signal arriving mid-`@x = @x + 1` could split that into "load @x → INTERRUPT → store @x", and a handler running during the interrupt could observe inconsistent state.

The cooperative shape (`%engine.wait` and `%engine.wait_loop`) gives a clean yield point. The script knows EXACTLY where it could be paused — only at calls to these constructs. Outside of them, the synchronous, surprise-free promise still holds.

This matches well-trodden cooperative event-handling patterns in other languages:

- Erlang's `receive` — message-passing equivalent.
- Tcl's `vwait` — wait on a variable trigger.
- GUI toolkit mainloops — `Tk.mainloop`, GTK's main_iteration, etc.
- Node's event loop conceptually (though Node makes it implicit; this is explicit).

---

<a id="relationship-to-the-event-system"></a>
## Relationship to the existing event system

Caspian's [event-broadcasting system](../../requirements/caspian/events/) already lets any object broadcast and any object listen. The engine could just BE another broadcaster — `%utils.broadcast` calls fired from inside the engine's internals.

Under that framing, `%engine.wait` could be sugar for:

1. Register a closure on `%engine` for any event.
2. Yield control to the engine until one of those events fires.
3. Run the closure.
4. Unregister and return.

`%engine.wait_loop` would be similar but without the unregister-and-return step.

Whether to spec these as primitive constructs or as derived sugar over the registration mechanism is one of the [open points](#open-points).

---

<a id="open-points"></a>
## Open points

- **What does the engine actually broadcast?** Candidates: timer ticks (`%engine.every(5)` schedules), signals (`'sigint'`, `'sigterm'`), GC events (`'before_collect'`, `'after_collect'`), resource warnings (memory pressure, fd exhaustion), engine-state changes, async I/O readiness.
- **Exit mechanism for `wait_loop`.** How does the closure break out? Exception unwinds? Explicit `%call.return`? Specific exit signal? Or does it just run until the process terminates?
- **Filtering — wait for any vs specific events.** Is the closure called for every engine broadcast, or can the script declare which events it's interested in? Erlang's `receive` supports both via pattern matching; Caspian could too.
- **Broadcaster argument.** The current sketch has `do($event_name, $content)` — two args. The standard event-system handler signature has three (`$broadcaster, $event_name, $content`). Should `wait` match? If the source is always `%engine`, the broadcaster arg is redundant; if `wait` ever catches non-engine broadcasts the script registered for, it matters.
- **Timeout.** `%engine.wait(timeout: 5) do(...)` — wait for an event OR a timeout, whichever comes first?
- **Nesting.** Inside a `wait` closure, can the script call another `wait`? Recurse the event loop?
- **Coexistence with normal broadcasts.** While `wait` is blocking, can OTHER objects' broadcasts (from the regular event system) still propagate to their registered handlers? In single-threaded Caspian, only one thing runs at a time, so this is mostly a question of "do queued events from other sources fire when wait is the active call?"
- **Sugar vs primitive.** Implementable on top of the existing event system (`%utils.register` + a yield primitive), or built into the engine directly?
- **Primary vs only.** Is `%engine.wait` the only way to receive engine events, or are there parallel APIs (e.g., the regular `.object.listen_to` form also catches engine broadcasts when they fire)?

---

## Why this isn't in V1

V1's promise is a synchronous, single-threaded script model with no surprises. Adding any form of engine-broadcast events — even cooperative ones — expands the mental model. The cooperative version preserves the surprise-free promise IF the script never calls `%engine.wait`, but the moment it does, the script is in a different programming model and needs to think about event ordering, reentrancy, and exit conditions.

Worth doing eventually for the use cases (timers, signals, GC hooks) — but the design needs to settle before commitment, and V1 has enough to ship without it.
