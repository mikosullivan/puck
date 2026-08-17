# Events

~~~vibecode
{"vibecode": {
	"doc": "requirements_events",
	"role": "spec for Caspian's per-instance event system. Explicit broadcast + explicit listener registration, no framework auto-triggering, no property-change interception. Object-methods: .listen_to (plain and block forms), .unlisten_to (arity-cascade), .unlisten_all, .broadcast, .listeners, .any_listeners?. Listener handlers get ($broadcaster, $event_name, ...args). Registrations are weak-ref: dropped automatically on participant GC. Companion feature: class-listeners at [listen-to-class](listen-to-class).",
	"audience": "Caspian programmers wiring event-driven behavior; engine implementers building the dispatch table",
	"key_concepts": ["explicit_broadcast", "method_name_registration", "weak_ref_lifetime",
		"idempotent_registration", "registration_order_dispatch", "no_wildcards",
		"manual_iteration_for_return_values", "block_form_scoped_registration"]
}}
~~~

Caspian's event system is deliberately simple: broadcasters explicitly fire named events; listeners explicitly register a method to run when a specific event fires on a specific broadcaster. No aspect-oriented programming, no property-change interception, no proxy machinery. What triggers a broadcast is entirely the class author's decision.

The companion feature for subscribing to events from every instance of a class lives at [listen-to-class](https://puck.uno/requirements/events/listen-to-class).

## Register a listener

A listener registers a method to be called when a specific event fires on a specific broadcaster:

~~~caspian
$listener.obj.listen_to $broadcaster, 'element_deleted', 'on_element_deleted'
~~~

Reads: "when `$broadcaster` broadcasts `'element_deleted'`, call the `on_element_deleted` method on `$listener`."

Three positional args to `.listen_to`:

1. The broadcaster object.
2. The event name (string).
3. The method name on the listener (string).

**Return value: true, always.** `.listen_to` under normal execution returns true. Failures (invalid args, engine errors) raise. Developer doesn't need to check the return value; success is uniform.

## Block-form registration

`.listen_to` accepts a `do ... end` block that owns the registration's lifetime:

~~~caspian
$listener.obj.listen_to $broadcaster, 'progress', 'on_progress' do
	&run_long_task
end
~~~

Registration is active for the duration of the block and removed when the block exits — regardless of how the block exits (normal completion, exception unwind, early return).

**Pre-existing registration is preserved.** If the same `(listener, broadcaster, event, method)` combo is already registered when the block starts, the block-form treats entry as a no-op for THIS registration and does NOT unregister it on exit. Only a registration created BY this block entry gets cleaned up on exit. Prevents block-scoped code from silently removing setup done by the caller.

**Return value: whatever the block evaluates to.**

Symmetric with `%amber` block-form scoping (`.init do end`, `.grant do end`) — block-form is the norm for scoped resource acquisition in Caspian.

## Unlisten

A listener removes registrations via `.unlisten_to`, at four levels of granularity determined by arity:

~~~caspian
$listener.obj.unlisten_to $broadcaster, 'event_name', 'method_name'
$listener.obj.unlisten_to $broadcaster, 'event_name'
$listener.obj.unlisten_to $broadcaster
$listener.obj.unlisten_all
~~~

- **Specific method:** removes exactly the matching `(broadcaster, event_name, method_name)` registration.
- **All methods for an event:** removes all of `$listener`'s registrations for that event on that broadcaster, regardless of method name.
- **All events on a broadcaster:** removes all of `$listener`'s registrations on `$broadcaster`, regardless of event or method.
- **Everything:** `.unlisten_all` removes all of `$listener`'s registrations everywhere, including class-listeners (see [listen-to-class](https://puck.uno/requirements/events/listen-to-class)). Separate method name (not a no-args `.unlisten_to`) to avoid ambiguity at the call site.

**Missing registrations silently succeed.** If `.unlisten_to` is called on a combo that isn't registered (never was, or already unregistered), it succeeds without raising. Matches hash `.delete` on a missing key returning null without raising. The invariant is "after this call, the registration is not present" — which is true whether it was there before or not.

**Return value: true, always.** Same convention as `.listen_to`. Failures raise; success is uniform. The count of registrations actually removed is not returned — if you need that information, count first with `.listeners()`.

## Broadcast an event

A broadcaster explicitly fires an event by name; additional args flow through to handlers:

~~~caspian
%self.obj.broadcast 'element_deleted'
%self.obj.broadcast 'element_updated', $key, $old_value, $new_value
~~~

**Nothing happens automatically.** Events fire only when code explicitly calls `.broadcast`. What triggers a broadcast — a specific point in a save method, a slot's setter after a change, a completion callback — is entirely the class author's decision.

**Return value: count of receivers.** `.broadcast` returns the integer count of listener handlers invoked during dispatch — zero when nothing was registered for the event. Useful for logging or debugging ("broadcast dispatched to 5 handlers") and gives a quick "did anything listen?" answer without a separate `.any_listeners?` call. If a handler raises during dispatch, the exception propagates normally and the caller doesn't see the return value; when dispatch completes normally, the count equals the number of registered listeners.

## Handler signature

The handler method receives three positional slots followed by whatever args the broadcaster passed:

~~~caspian
method &on_element_deleted($broadcaster, $event_name)
	# handles a broadcast with no additional args
end

method &on_element_updated($broadcaster, $event_name, $key, $old_value, $new_value)
	# handles a broadcast with three additional args
end
~~~

Positions are fixed:

- **Position 1:** the broadcaster object that emitted the event.
- **Position 2:** the event name string (e.g. `'element_deleted'`).
- **Position 3+:** additional args the broadcaster passed to `.broadcast`.

Parameter names are up to the developer.

**Why pass the event name always.** Even though a listener registration binds one method to one event name (so the method "knows" which event it handles), passing the event name as an arg lets one handler method serve multiple events by registering it against each event name — the handler branches on `$event_name`. Common case is one-method-per-event; the pattern of one-method-many-events is available when useful.

## No registration-time check

`.listen_to` does not validate that the broadcaster actually emits the event name being listened for. There is no schema on the broadcaster declaring "these are the events I emit"; there is no engine-side check that the target event will ever fire. Consistent with Caspian's general dynamic, no-nanny-code posture.

Implications:

- **Broadcasters don't pre-declare their events.** Any string is a legal event name; documentation and class name are what listeners rely on to know what to register for.
- **Typos go silent.** `$listener.obj.listen_to $broadcaster, 'befofe_save', 'handler'` (typo of `'before_save'`) registers successfully; when the broadcaster emits `'before_save'`, this listener's handler never fires. Developer discovers the bug when observed behavior doesn't match expectations.
- **Refactoring is on the developer.** Renaming an event doesn't visibly break listener code — the listener just stops receiving.

Same posture as missing hash keys returning null, and other dynamic-typing tradeoffs the language accepts. Trust the developer; keep the mechanism simple.

## Handler behavior

- **Registration is idempotent.** If `.listen_to` is called twice with the same `(listener, broadcaster, event_name, method_name)` combo, only one registration is stored. The handler fires once per broadcast, not twice. Accidental double-registration (defensive re-registration paths, code with multiple entry points) is safe; developer never has to reason about "did I register twice?" A developer who genuinely wants double-fire semantics registers with two different method names that call the same underlying logic.
- **Handlers fire in registration order.** When multiple listeners are registered for the same event on the same broadcaster, `.broadcast` invokes them in the order the corresponding `.listen_to` calls happened. Predictable; developer can rely on it for handlers with ordering-sensitive side effects.
- **Handler exceptions propagate normally.** If a handler raises during dispatch, the exception unwinds the stack like any other exception. No special case in `.broadcast`; no automatic catch-and-continue. Subsequent handlers do NOT fire (the dispatch was interrupted). Broadcasters that want per-handler isolation write manual iteration with try/catch around each call.
- **Missing method at broadcast time raises.** If a listener registered `'method_name'` but the listener object doesn't have that method when broadcast fires (misspelled at registration, or method was removed), the dispatch raises. Fails loudly at the point of the mistake; matches Caspian's fail-loudly-early convention.

## Registration lifetime

Registrations don't pin their participants. If either the listener or the broadcaster is garbage-collected via ordinary reachability rules, the registration rows referencing it are deleted automatically. Weak refs in effect: the engine's events table stores object IDs as bookkeeping data, not as reference edges that count toward reachability. A collected participant triggers cleanup of its rows as part of the collection cascade.

Practical consequence: developer never has to worry about "did I forget to unregister my listener before letting it die?" The registration goes when the listener does. Same for broadcasters — if a broadcaster is collected, all listeners registered for its events are cleaned up (they wouldn't fire anyway, since there's no broadcaster left to broadcast).

## No wildcards

Every `.listen_to` call names a specific event. There is no wildcard mechanism — no `'*'` event name that catches all events, no `.listen_to_all` variant. If a listener wants to react to multiple events on the same broadcaster, they register once per event name. Consistent with the "explicit, no magic" posture.

## Manual iteration — the return-value handling pattern

`.broadcast` is a convenience wrapper for the common "fire and forget every handler" case. When a broadcaster wants to do more with handler return values (e.g. the classic "before_save that returns false to cancel the save" pattern), it iterates the listeners manually:

~~~caspian
%self.obj.listeners('before_save').each do ($l)
	if $l.target.$l.method(%self, 'before_save')
		# do anything with the return value — cancel, log, aggregate, whatever
	end
end
~~~

`.listeners(event_name)` returns an array of listener descriptors. Each descriptor is a small object with two accessors:

- **`$l.target`** — the listener object that registered.
- **`$l.method`** — the string name of the method the listener registered.

The broadcaster calls `$l.target.$l.method(%self, event_name, ...args)` to invoke each handler, following the standard `($broadcaster, $event_name, ...args)` signature that handlers already expect. What the broadcaster does with return values, exception handling, ordering, and short-circuit behavior is entirely the broadcaster's code — no framework opinion.

**Why this eliminates the need for a separate veto API.** The classic "before_X" pattern (handlers return false to cancel; broadcaster aggregates and decides) is just:

~~~caspian
method &save()
	$approved = true

	%self.obj.listeners('before_save').each do ($l)
		if not $l.target.$l.method(%self, 'before_save')
			$approved = false
		end
	end

	if $approved
		# proceed with save
		%self.obj.broadcast 'after_save'
	end

	return $approved
end
~~~

No `.broadcast_veto`, no `.propose`, no special-cased return-value semantics baked into the framework. Broadcaster's own code decides what returned values mean. Short-circuit vs. all-run, all-truthy vs. count-based, exception-swallowing vs. propagating — all up to the loop.

Under the hood, `.broadcast` itself is roughly:

~~~caspian
method &broadcast($event_name, ...$args)
	$count = 0

	%self.obj.listeners($event_name).each do ($l)
		$l.target.$l.method(%self, $event_name, ...$args)
		$count += 1
	end

	return $count
end
~~~

Different loops for different intents; one primitive underneath.

## The `.any_listeners?` guard

Broadcasting when nothing is listening is nearly free — the engine looks up the registration table, finds no handlers, returns. But when the broadcast payload is expensive to compute, the developer can guard the broadcast:

~~~caspian
if %self.obj.any_listeners?('after_save')
	%self.obj.broadcast 'after_save', &expensive_operation
end
~~~

`.any_listeners?(event_name)` returns true if any listener is currently registered for that event on this object; false otherwise. O(1) engine-table lookup.

Skip the guard when the payload is cheap:

~~~caspian
%self.obj.broadcast 'after_save'
~~~

The guard exists for the "expensive payload" case only — it's not part of the standard broadcast flow. Matches the pattern in Rust logging (`log::log_enabled!`) and Python logging (`logger.isEnabledFor`): fire-and-forget is the norm; explicit guard is opt-in for hot paths.

**Naming rationale for `.any_listeners?`.** Reads unambiguously as "are any listeners registered for this event?" — vs. `.listeners?` which is shorter but slightly ambiguous ("listeners of what?"). The event-name argument narrows the check to a specific event on this specific object.

## Classes as broadcasters

Classes are objects like everything else in Caspian. A class has its own object methods; you can listen to events broadcast BY a class object using the ordinary `.listen_to`:

~~~caspian
$audit.obj.listen_to $foo, 'class_reloaded', 'on_foo_class_reloaded'
~~~

**Instances are not automatically tracked.** Listening on `$foo` (the class) does NOT subscribe you to events broadcast by every instance of `$foo`. That's the [listen-to-class](https://puck.uno/requirements/events/listen-to-class) feature.

**But composing existing pieces gets you close.** If you want to broadcast when any instance of a class is created, the class can override `.new`, super-call to create the instance, then broadcast a class-level event:

~~~caspian
class # foo
	method &new()
		$instance = super
		%self.obj.broadcast 'instantiated', $instance
		return $instance
	end
end

# Elsewhere:
$audit.obj.listen_to $foo, 'instantiated', 'on_foo_created'
~~~

The class object broadcasts; listeners registered on the class object receive. Same mechanism as any other event; no framework hooks. The pattern generalizes to any observable class-level behavior — `$foo.delete_all` could broadcast `'purged'`; `$foo.migrate` could broadcast `'schema_changed'`. Whenever a class does something worth telling listeners about, the class's own method can broadcast.

## Open decisions

- **Iteration snapshot vs. live view.** When `.listeners(event_name)` is called and a handler unregisters something during dispatch, does the iteration see the change or operate on a snapshot from the moment `.listeners` was called? Snapshot is simpler and safer; live view is more current but risks mid-iteration surprises. Decide before the first real broadcaster relies on either semantic.
- **Blocks / closures as a registration form.** The archive spec supported "closure directly on the broadcaster" as a third registration form (in addition to method-on-listener). This spec kept only method-on-listener. Whether the closure form should come back for one-off handlers remains open; current lean is against — method-name-only is the settled discipline.

## Testing

- **`.listen_to` returns true.** Assertion: `$l.obj.listen_to $b, 'e', 'm'` evaluates to `true`.
- **`.listen_to` is idempotent.** Register the same `(listener, broadcaster, event, method)` combo twice; broadcast the event once; handler fires exactly once.
- **`.listen_to` handlers fire in registration order.** Register three different listeners for the same event on the same broadcaster; broadcast; handlers fire in the order the `.listen_to` calls happened.
- **Block-form registration active inside the block.** `.listen_to $b, 'e', 'm' do &broadcast_e end` — the handler fires when `.broadcast 'e'` runs inside the block.
- **Block-form registration removed on block exit.** After the `do ... end` completes, calling `$b.obj.broadcast 'e'` does NOT fire the handler.
- **Block-form registration removed on exception unwind.** Same as above when the block exits via a raised exception rather than normal completion.
- **Block-form preserves pre-existing registration.** Register `(l, b, 'e', 'm')` plain; then enter a block-form `.listen_to $b, 'e', 'm' do ... end`; after the block exits, the original registration is still present and still fires on broadcast.
- **Block-form return value.** `.listen_to $b, 'e', 'm' do 42 end` evaluates to `42`.
- **`.unlisten_to` with three args removes the specific registration.** Register `(l, b, 'e', 'm')`; call `.unlisten_to $b, 'e', 'm'`; broadcast `'e'`; handler does NOT fire.
- **`.unlisten_to` with two args removes all methods for that event on that broadcaster.** Register `(l, b, 'e', 'm1')` and `(l, b, 'e', 'm2')`; call `.unlisten_to $b, 'e'`; broadcast `'e'`; neither handler fires.
- **`.unlisten_to` with one arg removes all events on that broadcaster.** Register `(l, b, 'e1', ...)` and `(l, b, 'e2', ...)`; call `.unlisten_to $b`; broadcast both events; no handlers fire.
- **`.unlisten_all` removes everything for the listener.** Register the listener against multiple broadcasters and events; call `.unlisten_all`; broadcast each; no handlers fire.
- **`.unlisten_all` covers class-listeners.** Register `.listen_to_class $c, 'e', 'm'` and `.listen_to $b, 'e', 'm'`; call `.unlisten_all`; both are gone.
- **`.unlisten_to` on a non-registered combo silently succeeds.** Never registered; call `.unlisten_to $b, 'e', 'm'`; returns `true`, does not raise.
- **`.broadcast` returns the receiver count.** Register two listeners for `'e'`; `.broadcast 'e'` returns `2`.
- **`.broadcast` with no listeners returns zero.** No registrations; `.broadcast 'e'` returns `0`.
- **`.broadcast` passes args to handlers.** Register a handler for `'update'`; `.broadcast 'update', 'x', 42`; handler receives `($broadcaster, 'update', 'x', 42)`.
- **Handler exception propagates and halts remaining dispatch.** Register two handlers; the first raises; the second does NOT fire; the raise propagates to `.broadcast`'s caller.
- **Missing handler method at broadcast time raises.** Register `'nonexistent_method'` on a listener; broadcast the event; the dispatch raises with a clear message identifying the missing method.
- **Registration is weak-ref on listener.** Register a listener; drop all references so it becomes GC-eligible; after collection, the broadcaster's registration row for that listener is gone.
- **Registration is weak-ref on broadcaster.** Register against a broadcaster; drop references to the broadcaster; after collection, the listener's registration row referencing that broadcaster is gone.
- **`.any_listeners?` returns true when a registration exists.** Register `(l, b, 'e', 'm')`; `b.obj.any_listeners?('e')` returns `true`.
- **`.any_listeners?` returns false when no registration exists.** Fresh broadcaster; `b.obj.any_listeners?('e')` returns `false`.
- **`.listeners` returns descriptors with `.target` and `.method`.** Register two listeners for `'e'`; `b.obj.listeners('e')` returns an array of two descriptors, each with `.target` == the listener and `.method` == the string method name.
- **`.listeners` returns empty array when no registrations.** Fresh broadcaster; `b.obj.listeners('e')` returns an empty array.
- **No wildcard event.** `.listen_to $b, '*', 'catch_all'` registers only for the literal event name `'*'`; broadcasting other events does NOT fire the handler.
- **Class-as-broadcaster works.** Register `$audit.obj.listen_to $foo, 'reloaded', 'handler'` against the class object `$foo`; `$foo.obj.broadcast 'reloaded'`; handler fires.
