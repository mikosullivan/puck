# Multicast dispatch

~~~vibecode
{"vibecode": {
	"doc": "idea_multicast",
	"role": "design notes on multicast dispatch for class-body lifecycle hooks (on_close, after_set, after_delete, etc.); records the rationale, the spec we sketched, the contradiction that surfaced, and the V1 decision to defer",
	"status": "deferred for V1 — V1 dispatch is unicast (topmost match fires); reconsider when a real use case justifies the cost",
	"key_concepts": ["per_platter_cleanup_motivation",
		"on_close_canonical_case",
		"on_call_property_sketch",
		"per_call_site_vs_per_function_contradiction",
		"four_candidate_homes_for_the_bit",
		"deferred_not_killed"]
}}
~~~

This doc captures what's been considered about **multicast dispatch** for class-body lifecycle hooks — the idea that an event like `on_close` fires *every* matching handler on an object's class composition, not just the topmost one. V1 ships without it (unicast only). This is the record of why it came up, what shape it took, and why we set it down.

## The use case

A Caspian object's class composition can have multiple layered classes (the platter stack). Each platter normally writes to the shared object-level `bucket`, but **per-platter buckets exist** as an escape hatch for the unusual case where a class genuinely needs its own private state without conflicting with the other layers.

When the object is destroyed, the topmost class's `on_close` fires by default (unicast dispatch). If a deeper platter has its own private state — an open socket, an OS handle, a subscription to an external service — only its own `on_close` knows how to release it. Unicast leaves that cleanup undone.

Multicast was the proposed answer: every matching `on_close` along the platter walk fires, top to bottom, each one cleaning up its own layer.

## The original framing

We pitched multicast as a second mode of the existing dispatch walk, with a different terminator:

- Unicast (current default): walk the platter stack × inheritance chains; stop at first match.
- Multicast: walk the same tree; invoke every match.

That framing made multicast feel like a tweak rather than a separate mechanism. The walk is identical; only the stopping rule differs.

`on_close` was the canonical case. The intent was to generalize the mechanism so future lifecycle hooks (`on_create`, `on_freeze`, `on_thaw`, `after_set`, `after_delete`) could opt in without new language surface.

## The `on_call` sketch

The spec attempted to put the dispatch-kind bit on each function object as a property:

~~~caspian
class
    method on_close($call)
        @socket.close
    end
    $on_close.on_call = :all      # opt into multicast for this function
end
~~~

`on_call = :first` (the default) meant unicast; `on_call = :all` meant multicast. Convention was to put the assignment on the line after the function definition.

Generalizable: future dispatch-metadata properties (`priority` for ordering siblings, `error_strategy` for what happens when one raises) could slot in on the same function object without growing the language.

## Where the sketch broke

The contradiction surfaced when we asked: **where does the "this dispatch is multicast" bit physically live so the engine can read it before the walk starts?**

By the time the engine has found a matching function, it has already committed to a stopping rule. Stopping rule has to be known per *call site* (the name being called on this object), but the `on_call` sketch put it on each individual function object. An object's platter stack can have multiple classes that all define `on_close` with conflicting `on_call` values — class A says `:all`, class B says `:first`. The engine can't pick one without effectively electing one platter as authoritative, which defeats the multicast premise.

The candidate homes for the bit, each with a flaw:

### On each function object (the sketched spec)

Breaks when two implementations disagree. Needs a tie-breaker rule, and any tie-breaker effectively elects one platter as authoritative.

### On the object instance

Objects don't carry per-method metadata today. Adding it means a new layer of object state, set by whichever class loaded last. Same authority problem in different clothes.

### At the call site

Caller specifies multicast — `$foo.&on_close(multicast: true)`. Works for explicit calls, but the engine fires lifecycle hooks itself. There is no user call site for the engine's invocation to annotate.

### In the engine, by method name

A fixed allowlist that the engine knows is multicast: `on_close`, `after_set`, `after_delete`, ... Simple, works, but it's magic names. Extensibility means hard-coding into the engine, and any third-party class wanting its own multicast hook is locked out. It also admits that "multicast" isn't a general dispatch mode at all — it's a small, engine-curated category.

## Why we deferred

The cleanest of the four candidate homes is the engine-allowlist version, but it weakens the original framing of "multicast as a second mode of one mechanism" — it turns out to be a special case bolted onto a fixed list of method names.

Combined with the narrowness of the use case in current spec — per-platter buckets exist but are explicitly the unusual case; the common case uses the shared object-level bucket — the cost of designing in multicast for V1 outweighs the value. Per-platter cleanup gaps will exist in V1 for classes that use per-platter buckets and don't manually delegate cleanup; that's an accepted trade for a smaller V1.

## What V1 actually does

- All engine-invoked methods (`on_close`, `init`, `to_string`, `to_json`, `to_primitives`, `evaluate`) dispatch **unicast** — topmost match fires.
- If a class needs to clean up multiple layers' state, it does so explicitly in its own `on_close` body (calling parent or peer methods, delegating to helpers, etc.).
- The `on_call` property is not in the spec. Function objects don't carry dispatch-kind metadata.
- The `after_set` and `after_delete` lifecycle hooks are also not in V1 — they were predicated on multicast.

## Leading future direction: caller-side multicast

The shape we like most for a future revisit splits the question into two independent decisions:

1. **Engine-fired hooks** (`on_close`, future lifecycle events) are multicast by engine policy. The engine knows which method names it treats this way; the developer is expected to know the list. No language surface needed for this — it's just what the engine does.
2. **User-fired calls** are unicast by default. User code that wants multicast asks for it explicitly at the call site through `.obj.multicast`:

   ~~~caspian
   $foo.obj.multicast :bar              # fire every matching :bar along the platter walk
   $foo.obj.multicast(:bar, args...)    # general form with args
   ~~~

`.obj.multicast` lives in the engine-protocol namespace alongside `.obj.classes`, `.obj.freeze`, etc. — symmetric with the rest of the surface that addresses the object's structure rather than its instance methods.

### What this resolves

- **The per-call-site authority problem evaporates.** The caller decides per invocation; no need to elect a platter as authoritative, no tie-breaker rule when classes disagree on dispatch kind.
- **No per-function metadata.** Function objects stay clean — no `on_call` property to set or read, nothing the engine has to consult before the walk.
- **Two layers, two mechanisms, one idea.** Engine policy and user opt-in share the *concept* of multicast without sharing an implementation. Each is the simplest thing that solves its own case.
- **Extensibility is honest.** A third-party class can opt its callers into multicast on any of its methods just by being called via `.obj.multicast`. No magic-name registration, no per-class declaration, no engine-side allowlist for user methods.

### What still needs design

- **Return shape.** A regular method call returns one value. `multicast :bar` returns... what? An array of values from each handler in walk order? A summary? Nothing? Lifecycle hooks don't care about return values, but if user code can multicast arbitrary methods, the return type matters.
- **Error handling.** If one handler raises, do the rest fire? `on_close` already has the GC's per-handler catch-anything wrapper; user multicasts would need their own error story. Candidates: collect-all-errors, fail-fast, ignore-and-continue.
- **Argument shape.** Whether `multicast :bar` for the no-arg lifecycle case and `multicast(:bar, args...)` for the general case are one method or two; whether args are passed identically to each handler or shaped per-handler somehow.
- **Whether engine-fired hooks ever route through `.obj.multicast`** internally (so the mechanism is uniform), or stay a separate engine-internal path that just happens to behave the same way.

## Other paths considered

The leading direction above grew out of these alternatives, each set aside for the reason noted:

- **`on_call` as a function property** (the original sketch). Set aside for the per-call-site vs. per-function contradiction described above.
- **Engine-allowlist only.** Lifecycle hooks become a curated set; extensibility for third-party multicast hooks is rejected as a non-goal. Workable but admits that "multicast" isn't really a general dispatch mode.
- **Per-class "this hook is multicast" declaration.** Resolves the per-function ambiguity by binding the decision to the call site name at class-definition time, but still has the multi-class conflict when two classes disagree.
- **Give up on a general mechanism.** Each lifecycle hook gets its own bespoke dispatch rule documented at its home. Cheapest, but loses the unifying frame.

Reopening requires either: the leading direction above gets refined enough to land (with the design questions above resolved), or a fifth option none of these captures.

## Related

- [garbage-collection.md § on_close](../requirements/garbage-collection.md#on-close) — V1 `on_close` spec (unicast).
- [engine-invoked-methods.md](../requirements/engine-invoked-methods.md) — cheat sheet of engine-invoked methods, all unicast in V1.
- GitHub issue [#343](https://github.com/mikosullivan/puck/issues/343) — earlier closure resolved as "multicast model adopted." Superseded by this deferral.
