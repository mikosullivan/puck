# Registering event handlers on other objects

~~~json
{"vibecode": {
	"doc": "idea_event_handlers",
	"role": "design note for a Caspian feature: any object can register a handler on another object that fires when the second one mutates. Originated as a way to propagate the per-hash `changed` flag up through nested structures, but generalizes to a full observer / event-handler pattern as a language feature.",
	"status": "idea — open design questions; not yet pursued",
	"key_concepts": ["observer_pattern_as_language_feature",
		"opt_in_propagation_for_changed_flag",
		"role_boundaries_unresolved",
		"many_use_cases_beyond_logging"]
}}
~~~

A possible Caspian feature: **any object can register a handler on another object that fires when the second one mutates.** Originated as a solution to the nested-`changed`-flag propagation problem (a parent hash needs to know when a nested hash changes, without every hash being instrumented by default), but the same primitive opens up a much wider set of patterns — observer / reactivity / cache invalidation / derived values / cross-object invariants.

Not in active design. Captured here so the idea isn't lost.

---

<a id="the-trigger"></a>
## The trigger: propagating changes through nested structures

Caspian has a per-hash / per-array [`changed` flag](../../requirements/caspian/packages/jasmine/index.md) (per the recent Jasmine work). The flag is local to its hash — a mutation to `$entry['user']['name']` flips `$entry['user'].changed` but doesn't propagate up to `$entry.changed`. For the log-entry-bug-chasing use case this matters because GC-autosave checks `$entry.changed` and would miss nested edits.

The obvious fix — on_change handlers wired into every hash by default — is too heavy: most hashes will never use the feature, and the cascade adds platter overhead to every nested object.

The proposal: make handler registration its own feature. Hashes that **want** to listen can register on hashes they care about. Hashes that don't want to listen pay nothing.

```
$entry.object.register($entry['user'], :after_change) do
    %self.changed = true
end
```

The listener (`$entry`) calls `register` on its own `.object` meta-namespace, passing the source (`$entry['user']`) and an event-name symbol (`:after_change`). The block is the handler. Inside the block, **`%self` refers to the listener** — the object that registered the handler — so the handler doesn't need to capture the listener by name. See [Sketch of a plan § Register from the listener side](#sketch-of-a-plan) for the rationale and surrounding semantics.

When the nested hash mutates, the handler fires, the parent flips its own flag. Opt-in, no cascade.

**Update — the logging trigger turned out to be solvable without this.** The actual log-entry save semantics landed on a `$entry.persist` flag plus a "saved" flag instead of `changed`-tracking propagation; see the [Jasmine save plan](../../requirements/caspian/packages/jasmine/index.md). The propagation problem this idea was originally motivated by no longer exists for logging specifically. The other use cases below still motivate the feature; logging is no longer one of them.

---

<a id="generalizes-beyond-logging"></a>
## Generalizes beyond logging

The same primitive serves many patterns:

- **Reactivity / data binding** — a view registers a handler on a data object; refreshes when the data changes.
- **Cache invalidation** — a cache registers on its sources; invalidates entries when sources mutate.
- **Cross-object invariants** — object A re-validates when object B changes.
- **Derived / computed values** — a derived property registers on its inputs; recomputes when any input changes.
- **Mikobase change subscribers** — record listeners as a natural application.
- **Audit / observability hooks** — anything that wants to know when something mutated, without instrumenting every mutation site.

Once the primitive exists, all of these become straightforward library code. Without it, each pattern has to invent its own mechanism (manual notification, polling, custom subscriber lists).

---

<a id="open-design-questions"></a>
## Open design questions

None of these are settled. Recording them so they don't get rediscovered later.

### API shape

Several plausible surfaces:

- `$parent.on_change_of($child) do ... end` — block form, register from the listening side.
- `$child.after_change do ... end` — block form, register on the source side. Anyone with access can hook.
- `$child.subscribers.add($fn)` — explicit collection.
- A method that returns a handle the listener can use to unregister.

Each implies different security/lifetime semantics.

### Handler signature

What does the handler receive?

- **Nothing** — `fn()`. "Something changed, the listener can re-inspect the object." Minimal.
- **The mutation context** — `fn($key, $old, $new)`. More information; more state for the engine to compute and pass.
- **The mutated object** — `fn($obj)`. Listener gets a reference.

For the changed-flag-propagation use case, the listener doesn't need details — it just flips its own flag. Minimal signature suffices.

### When does it fire?

- **On every mutation** — write to a key, delete a key, append/pop array, etc.
- **On the changed-flag transition only** (false → true). Avoids handler-spamming on hot loops; loses fidelity for "many small changes" cases.
- **Coalesced** — fires once per batch / tick / framework boundary.

For `changed` propagation, "transition only" is the natural choice. For reactivity / observers, "every mutation" might be wanted. The engine probably needs to support both, with the registration choosing.

### Lifetime and unregistration

- Are handlers explicitly unregisterable?
- Do they hold weak references to the listener (so the listener can be GC'd despite being registered)?
- Tied to a role boundary, a block, a function call?
- What happens if the listener is collected but the handler is still registered on a live source?

These choices determine whether handler-registration creates retention cycles, leaks, or quiet failures.

### Recursion / reentrancy

If a handler mutates the source it's registered on (or another object that has handlers), do those fire more handlers? Spirals are easy here.

Three reasonable defaults:

- **No reentry** — engine suppresses handler firing while a handler is running.
- **Bounded reentry** — fire up to N levels deep, then suppress.
- **Free reentry** — handlers can cascade arbitrarily; user code is responsible for not infinite-looping.

### Performance

Every mutation now has an extra step: check if there are handlers, call them. Cost is:

- **Zero** when no handler is registered (just check an empty list).
- **Per-handler** when handlers exist (one call each).

For hot mutation loops on objects with many handlers, this could be measurable. Worth being aware but not a blocker; users opt in to the cost by registering.

### Role / security boundaries

The big one. Caspian's [role model](../../requirements/caspian/roles.md) keeps untrusted code structurally contained — each function only sees and writes its own entries / state. If any role can register a handler on any object, you get a back-channel: an untrusted callee registers a handler on the caller's hash, the handler fires later in the caller's role, the untrusted code has effectively executed code in the caller's role.

Three rules to consider:

- **Same-role only.** A handler can only be registered on objects owned by the same role as the listener. Strictest; preserves role isolation airtightly.
- **Owner-only.** Only the object's owning role can register handlers on it. Middle path; caller-of-callee typically owns the object being mutated, so the natural register-from-the-caller pattern works.
- **Read-access implies register-access.** If you can see the object, you can register. Most permissive; almost certainly too permissive given Caspian's containment principles.

**Same-role-only** is probably right — keeps the existing isolation properties intact. Cross-role propagation would need an explicit capability hand-off (i.e., the owner of the source object hands the listener a registration capability). Worth thinking through deliberately when this is pursued.

---

<a id="sketch-of-a-plan"></a>
## Sketch of a plan

**Not for V1.0** — this is a brainstorm at the "what would this look like if we did it" level, not a committed design. Recording it so the trajectory is on paper.

Tentative answers to the open questions above, chosen to be the least surprising starting point. Each one is a candidate, not a lock.

### Register from the listener side

```
$handle = $listener.object.register($source, :after_change) do
    %self.changed = true     # %self == $listener, the registering object
end
```

The listener calls `register` on its own `.object` meta-namespace, passing the source object and an event-name symbol. The block is the handler. Inside the handler, `%self` refers to the listener (the object that registered) — so the handler doesn't capture the listener by name and doesn't break if the variable holding the listener is renamed or rebound. Returns a handle for explicit unregistration.

Why listener-side rather than source-side:

- **Matches Caspian's containment story.** The listener is opting in to listening, in the listener's role. The handler code lives in the listener's role. The same-role check is naturally "the registering role" (the listener) checked against the source's role. Cleaner alignment than a `$source.after_change` form where the source is the entry point.
- **Goes through `.object`.** Event registration is a *meta-operation*, not a regular hash method — putting it on `.object` keeps it from polluting the standard hash interface. Same neighborhood as `$foo.object.method(...)`, `$foo.object.stack`, etc.
- **Symbol-named events extend naturally.** `:after_change` today; `:before_change`, `:on_delete`, other named events later, all through one `register` method. No new methods on every object for each event type.

### Handler signature: `%self` is the listener; no other args

The handler is a block with no explicit arguments, but **`%self` inside the handler is the listener** — the object that called `register`. That gives the handler everything it needs without closure-capturing the listener by name:

```
$foo.object.register($bar, :after_change) do
    %self.changed = true     # %self resolves to $foo
end
```

The source is reachable through closure if the handler needs it (it was an explicit argument to `register`). Anything more elaborate — the mutated key, the old value, the new value — is a future extension if a use case justifies it.

### Fires on `changed` transition only

The handler fires when the source's [`changed` flag](#the-trigger) transitions from `false` to `true` — **not** on every individual mutation. Two reasons:

- Avoids handler-spam in mutation-heavy code.
- Matches the use case shape: the listener usually cares "has something changed since last I looked" rather than "tell me about every key write."

If a finer-grained variant is wanted later, it can land as a separate method (`after_every_mutation` or similar) without disturbing this one.

### Lifetime tied to source; unregister via the returned handle

- The handler list lives on the source. If the source is collected, all handlers on it are collected with it. No listener code runs after the source is gone.
- The handle returned from `after_change` has an `unregister` method:

```
$handle.unregister    # removes the handler from the source's list
```

- Otherwise the handler persists for the source's lifetime.
- The handler closure holds a normal reference to whatever it captures, including the listener; if you want the listener to be collectible despite an outstanding handler, capture it weakly or use an explicit unregister.

### No reentrancy and no looping registrations

Two related rules, both pointing at the same goal: handler firing must terminate.

**No reentrancy** — while a handler is running, the engine suppresses further handler firing. A handler that mutates its source (or any other object with handlers) doesn't recursively re-trigger handler chains. At most one handler fires at a time within a dispatch.

**No looping registrations** — beyond the runtime reentry check, the registration graph itself shouldn't be allowed to form cycles that would loop on mutation. If A registers a handler on B and B registers a handler on A, a mutation to either side could chain. The engine should detect cyclic registration at `register` time and reject — either by tracking the listener→source edge set and rejecting registrations that would close a cycle, or by enforcing a layered registration discipline (parents listen to children but not vice versa, etc.). The exact mechanism is a design choice; "no cycles allowed in the registration graph" is the invariant.

Both rules together mean: even a handler that performs mutations can't kick off an unbounded chain. Loop protection is structural (registration graph) plus runtime (reentry suppression).

A future option for "cascade through N levels" can land if a use case needs it; the defaults stay no-reentry and no-cycles.

### Same-role-only registration

`after_change` can only be called when the source's owning role matches the role of the listener (the code making the registration call). Cross-role registration raises immediately at registration time.

Rationale: preserves Caspian's structural containment. Cross-role propagation would need an explicit capability hand-off — the owner exposes a "registration capability" the listener can call. Out of scope for the basic mechanism.

### Performance

- No handlers registered → cost is one empty-list check at mutation time. Negligible.
- Handlers registered → cost is one block call per handler at each `changed` transition. Pay-for-what-you-use.

The transition-only firing rule keeps the per-mutation cost low even for hot loops on heavily-listened objects.

### Fitting into Drinian

Registrations are runtime state — they have to survive between mutations, persist through snapshot/revive (eventually), and be reachable for GC tracing. The natural home is **inside the [Drinian](../../requirements/caspian/drinian/) hash**, as a top-level field alongside `call_stack`, `references`, `roles`, etc.

**Shape**: a `registrations` hash at the Drinian top level, keyed by registration ID:

```json
"registrations": {
  "r1": {
    "source": "<reference-id of the source object>",
    "event": "after_change",
    "listener": "<reference-id of the listener>",
    "handler": "<closure object id>",
    "role": "<the role the handler runs in — captured at registration time>"
  }
}
```

The handle returned from `$listener.object.register(...)` is a small user-space object that holds the registration ID and exposes `.unregister`. The handle is a reference like any other; the engine traces it through the standard reachability machinery.

**Indexing for mutation-time lookup.** A mutation needs to find any handlers registered on the mutated source. The naive approach (scan the whole `registrations` table on every mutation) is O(N); preferable is a `by_source` inverse index — `{<source-id>: [registration-id, ...]}` — maintained by the engine alongside the main table. Built incrementally as registrations are added and removed; never user-visible.

**GC interaction**:

- A registration creates reachability edges to its source, its listener, and its handler closure.
- **The source pins the registration.** When the source is collected, its registrations are collected with it (no source means no firing).
- **The listener is referenced weakly by the registration.** If the listener is otherwise unreferenced, the registration silently goes inert (the engine cleans it up next sweep). This prevents registration-pins-listener cycles.
- **The handler closure** holds its captured scope by normal reference. If the handler captures the source explicitly, that pin lives in the closure, not in the registration entry — same model as any other captured reference.

**Snapshot / revive (post-V1.0)**: registrations live in Drinian, so when Drinian serializes they serialize too. Blocks already need to serialize for snapshot/revive to work end-to-end (per [drinian.md § Future: snapshot-and-revive](../../requirements/caspian/drinian/index.md#future-snapshot-and-revive-post-v1-0)); handlers come along for free. On revive, the `registrations` table comes back intact and the `by_source` index is rebuilt from it.

**No new structural commitment for V1.0**: since this feature is post-V1.0 anyway, the Drinian hash doesn't need to grow yet. When this feature lands, adding a top-level `registrations` field follows the same incremental-growth pattern Drinian already uses ([per the Aslan-to-future arc](../../requirements/caspian/drinian/index.md#v1-0-scope)).

**A Mikobase counterpart is also needed.** The Drinian `registrations` hash covers live in-process state. Mikobase records — persistent, possibly cross-process — will need their own way to attach registrations so that mutations to a stored record can fire handlers. Separate design exercise; mentioned here so the parallel concern doesn't get forgotten when this feature is eventually pursued.

### Implementation order, if this ever gets built

1. Land the `changed` flag mechanism (already planned).
2. Add a lazily-allocated handler list to hashes and arrays (nil when no handlers — no per-instance cost for the common case).
3. Add the `after_change do ... end` method and the handle object with `unregister`.
4. Wire the transition-detection logic: mutation that flips false→true fires handlers; mutations while already-true are silent.
5. Add the same-role check at registration time.
6. Land a real test suite around reentrancy, role-boundary rejections, and GC interaction.

Each stage is incrementally useful; the feature is shippable after stage 4 (without the role check, only safe for fully-trusted code) and complete after stage 6.

---

<a id="foreign-registrants"></a>
## Foreign registrants (wild brainstorm)

The mechanism above assumes a local Caspian object as the listener. **What if the listener could be a remote endpoint?** When the event fires, the source dispatches an HTTP message (a webhook) to the foreign registrant. Same registration shape; different listener identity.

```
$bar.object.register('https://example.com/webhook', :after_change)
$bar.object.register('borg.com/audit-listener',     :after_change)
```

The first form points at a literal URL; the second uses a UNS that the engine resolves through `%puck` to a concrete endpoint. Same mechanism, two listener naming styles.

### What the source sends

When the event fires, the engine **POSTs a payload** to the registered URL. Shape TBD — minimal contents probably include:

- The source's identity (UNS or object reference, depending on what makes sense to surface remotely)
- The event name
- A timestamp
- Some snapshot of the relevant state (whatever the design eventually says is appropriate to expose; probably opt-in per-source)

Optionally, the registration could carry a **payload-shaping block** that runs locally before dispatch:

```
$bar.object.register('https://example.com/webhook', :after_change) do
    {kind: 'cache_invalidated', uns: %self.uns, ts: %now}
end
```

The block returns the payload; the engine POSTs it. This keeps payload-shaping in user space and the dispatch mechanism in the engine.

### Use cases this opens up

- **Webhooks for object changes** — directly, no separate infrastructure.
- **Cross-process notifications** — event on object in process A triggers a callback to process B.
- **Integration with external systems** — monitoring, CRM, observability, alerting.
- **Distributed log replication** — every mutation to a flagged object posts to a remote log.
- **Audit trail to external compliance systems** — without polluting the program with explicit notification calls.

### Async semantics

The HTTP send is **fire-and-forget by default** — mutation in Caspian doesn't block on the network. If a use case needs the remote to acknowledge before proceeding, that's a different (probably promise-based) mechanism.

What happens on send failure (remote down, DNS fails, etc.) is an open question. Reasonable defaults: warn (consistent with [Jasmine's warning-not-stderr pattern](../../requirements/caspian/packages/jasmine/index.md#logger-failure-cascade)), drop the event, keep the process running. A more careful registration could opt into queuing-for-retry, but that's its own design exercise.

### Security implications

This is where the design space gets genuinely tricky.

- **Who's allowed to register a foreign listener?** Not the same-role check used for local listeners — there's no remote "role" to compare against. Probably requires an outbound-HTTP capability (akin to `%engine.http` access).
- **Which URLs are valid targets?** The engine could enforce a URL allowlist (parallel to the [source-allowlist](../../requirements/caspian/downloads/service/index.md#opt-in) story on the download side).
- **Authentication of the message.** Puck's [blockchain signing](../../requirements/caspian/downloads/service/blockchain/) could underwrite this: the source signs the payload, the receiver verifies against Puck's baked-in key. Same trust-anchor as the rest of the ecoverse.
- **Replay protection.** A signed payload with a timestamp and unique event ID prevents replay attacks.

### Snapshot / revive

Foreign registrations are **easier to snapshot than local ones** — no closure to serialize, just a URL string and an event name. On revive, the registration comes back and outbound events resume.

### Relationship to the Puck protocol

If both ends speak Puck, the HTTP message could be a Puck-formatted call. The receiver deserializes it into an object and acts on it through normal Puck dispatch. That unifies "event handler" with "remote method call" — they become the same thing, just initiated by a mutation rather than by user code.

---

<a id="relationship-to-existing-mechanisms"></a>
## Relationship to existing mechanisms

This idea overlaps with several existing Caspian concepts that should be considered together when the design is pursued:

- **Per-hash / per-array `changed` flag** — the original trigger; this idea is the propagation mechanism for it.
- **Role boundaries** — the security framework the design has to fit inside.
- **Mikobase change tracking** — if mikobase records already have built-in change-tracking, much of this is already half-built at the data layer.
- **`%chain.log` per-function-call entries** — the existing change-tracking mechanism for logs; this idea is what would let standalone entries match its ergonomics.

---

<a id="why-this-is-an-idea-not-a-spec"></a>
## Why this is an idea, not a spec

It's a foundational language addition with broad implications. Adding it commits Caspian to a particular reactivity model, locks in security rules that need careful thought, and changes the mental model for what every hash and array can do. The use cases are real, but the design space is wide and the tradeoffs aren't settled. Best to keep this in `ideas/` until there's a concrete pressing need that forces the design forward.
