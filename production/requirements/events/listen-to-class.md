# Listen to every instance of a class

~~~vibecode
{"vibecode": {
	"doc": "requirements_events_listen_to_class",
	"role": "spec for the class-listener companion to the base event system. Subscribes to events broadcast by ANY instance of a class, not just events broadcast by a specific object. Object-methods: .listen_to_class (mirrors .listen_to), .unlisten_to_class (arity cascade), .unlisten_all (from the base spec) sweeps both class and instance registrations. Dispatch keys off %call.method_class and walks that class's inheritance chain; per-broadcast dedup on (listener, method) pairs across instance and class sources. Cost when no class-listeners exist is one hash miss per ancestor.",
	"audience": "Caspian programmers subscribing to events across instance populations; engine implementers building the dispatch table",
	"key_concepts": ["defining_class_dispatch", "ancestor_walk", "cross_source_dedup",
		"visited_set_per_broadcast", "class_stack_vs_inheritance_chain",
		"weak_ref_lifetime", "no_cost_when_unused"]
}}
~~~

The [base event system](https://puck.uno/requirements/events/) handles per-object subscription. This companion feature adds per-class subscription: register once against a class, and every broadcast from any instance-of-that-class's own methods fires the handler.

## Why bother

The DB-record motivator:

~~~caspian
$listener = %(some_listening_class).new

# Without class-listeners — register per instance, deep inside code that creates records:
$db.query(...) do ($record)
	$listener.obj.listen_to $record, 'on_save', 'validate'
end

# With class-listeners — register once, at any point, regardless of where instances come from:
$listener.obj.listen_to_class $record_cls, 'on_save', 'validate'
&complicated_function()   # somewhere deep inside, records get created and broadcast; all reach the listener
~~~

Per-instance registration works fine when the code creating instances is easy to reach. When instances are created behind function calls, iterators, callbacks, or other indirection, threading a listener-registration into every creation site is painful. Class-listening moves the subscription up to "the class" — the one place that always exists — and lets everything downstream just work.

## Terminology: class stack vs. inheritance chain

Two separate concepts that are easy to conflate:

- **Class stack** — **per-instance** metadata. Which direct classes are composed on this particular instance. If `$file.new()` creates an instance, that instance's class stack is `[$file]`. If code later does `$instance.add_class $foo`, the stack becomes `[$file, $foo]`. Stack is a property of an object, not of a class.
- **Inheritance chain** — **per-class** metadata. What classes each class inherits from via its `inherits:` declaration. If `$file = class(inherits: $storable)`, then `$file` (the class) has `$storable` in its inheritance chain. Every instance of `$file` shares this — because inheritance is a class-level property, not per-instance.

The two compose: normal method dispatch on an instance first walks the instance's class stack (which of the composed classes defines this method?), then each of those classes' inheritance chains (does an inherited class define it?).

**Class-listener dispatch walks the inheritance chain of the defining class only.** The instance's class stack isn't consulted directly — the dispatch keys off `%call.method_class` (which is a specific class, not the whole stack) and walks that one class's inheritance ancestors.

## The API

Mirrors `.listen_to` / `.unlisten_to` from the [base event system](https://puck.uno/requirements/events/):

~~~caspian
$listener.obj.listen_to_class $class, 'event_name', 'method_name'
~~~

Reads: "when any method defined on `$class` broadcasts `'event_name'`, call `method_name` on `$listener`."

Same handler signature convention as per-instance: `method &handler($broadcaster, $event_name, ...args)`. The `$broadcaster` position holds the specific INSTANCE that broadcast (not the class) — the listener still knows which instance triggered the event.

**Unlisten mirrors the arity cascade:**

~~~caspian
$listener.obj.unlisten_to_class $class, 'event_name', 'method_name'
$listener.obj.unlisten_to_class $class, 'event_name'
$listener.obj.unlisten_to_class $class
~~~

`.unlisten_all` (from the base system) covers all registrations across per-instance AND per-class — one command wipes everything the listener has registered.

Same rules as the per-instance API:

- **Return values.** `.listen_to_class` and `.unlisten_to_class` return true always; failures raise.
- **Silent-succeed on missing.** Unregistering a class-listener that isn't registered succeeds silently.
- **Idempotent registration.** Registering the same `(listener, class, event, method)` combo twice stores one row.
- **Weak refs.** Class-listener rows don't pin the class or the listener; they drop automatically on GC.

## Block-form registration

`.listen_to_class` accepts a `do ... end` block that owns the registration's lifetime — same shape as the base [block-form registration](https://puck.uno/requirements/events/#block-form-registration):

~~~caspian
$listener.obj.listen_to_class $record_cls, 'on_save', 'validate' do
	&run_batch_of_saves
end
~~~

Registration is active for the duration of the block and removed when the block exits (normal completion, exception unwind, or early return). If the same `(listener, class, event, method)` combo is already registered when the block starts, the block-form leaves it alone on exit; only a registration created by this block entry is cleaned up. Block-form evaluates to whatever the block evaluates to.

## How dispatch works

When an instance broadcasts, the engine already knows what method it was called from — via `%call.method_class`, the class the method is defined on. The dispatch:

1. **Instance listeners.** Look up `instance_listener_registry[(instance, event_name)]` — O(1).
2. **Class listeners on the defining class.** Look up `class_listener_registry[(defining_class, event_name)]` — O(1).
3. **Class listeners on ancestor classes.** Walk the `inherits:` chain from `defining_class` upward. For each ancestor A, look up `class_listener_registry[(A, event_name)]` — O(1) per class.
4. **Dedup and fire.** Collect all matching handlers from steps 1-3, dedup by `(listener_object, method_name)` pair, then fire each unique handler once. Order: instance listeners first, then class listeners from most-specific (defining class) to most-general (root ancestor). Registration order within each class.

**Cost per broadcast:** O(inheritance depth) hash lookups + O(matching listeners) fires + O(unique-handlers) dedup set operations. Inheritance depth is typically 3-5 in real code; each lookup is a hash-table hit; the dedup set is small (usually 1-10 entries per broadcast). Small overhead.

**Cost when nothing uses class-listeners:** still O(inheritance depth) hash MISSES. Each lookup is fast and returns empty; the walk terminates naturally. **No cost if you don't use it** — nothing extra is paid unless class-listeners exist. See [concepts § Cost if you don't use it](https://puck.uno/requirements/concepts#cost-if-you-dont-use-it).

## Cross-source dedup

A listener can register for the same event on multiple classes in an inheritance hierarchy:

~~~caspian
$listener.obj.listen_to_class $file, 'before_save', 'validate'
$listener.obj.listen_to_class $storable, 'before_save', 'validate'
~~~

When a `$file` instance broadcasts `'before_save'`, both registrations match — the ancestor walk hits `$file` first (defining class), then `$storable` (its parent). Without dedup, `validate` would fire twice. That's almost never the intent; the listener wants the event ONCE, regardless of how many places in the class hierarchy they registered.

**Rule: each unique `(listener_object, method_name)` pair fires at most once per broadcast.** The engine maintains a per-broadcast visited set; before firing each handler, it checks the set; if the combo is already there, skip; otherwise add and fire.

**Dedup applies across ALL sources.** Instance listeners, class listeners on the defining class, and class listeners on ancestor classes are all deduped in one shared set for the broadcast. Listener registered as `.listen_to $some_file_instance, 'before_save', 'validate'` AND `.listen_to_class $file, 'before_save', 'validate'` — `validate` fires once when `$some_file_instance` broadcasts.

**Dedup key is the (listener, method) pair, not just the listener.** A single listener can genuinely want two different methods to fire for the same event — e.g. `validate` registered via `$file` and `log` registered via `$storable`. Different methods = two separate handlers; both fire. Only the exact-same-combo duplicate is dedup'd.

**Per-broadcast scope only.** Different broadcasts each start with a fresh visited set. There's no cross-broadcast dedup — every broadcast fires everyone once. Set is allocated when dispatch starts and discarded when dispatch completes.

**Cost:** per-broadcast set of `(listener_id, method_name)` pairs. O(1) membership check and add per handler. O(unique-handlers-fired) memory during dispatch. Very cheap.

## The key insight that makes this cheap

Class-listeners fire based on the **defining class of the currently-executing method**, not on the instance's whole class stack. When a method defined on class C broadcasts, the engine walks C's inheritance ancestors — not the instance's entire multi-class stack.

Concretely: if instance O has classes `[$widget, $serializable]` in its stack, and `$widget`'s `save()` method broadcasts, class-listeners on `$widget` (and `$widget`'s ancestors) fire. Class-listeners on `$serializable` do NOT fire — because `$serializable` didn't broadcast anything; `$widget` did.

If `$serializable` ALSO defines a `save()` method and it gets called (via a different code path, or explicit dispatch), THAT invocation fires `$serializable`'s class-listeners. Each broadcast fires listeners on the class chain of whichever method actually ran.

**Consequence:** dispatch is much cheaper than a full instance-class-stack walk, and semantically more precise. A class-listener on C hears about events from C's methods specifically, not accidentally from unrelated code that happens to run on an object that also has C in its stack.

## Multi-inheritance and ancestor walking

Under Caspian's `inherits:` mechanism, a class can inherit from multiple parents. When walking the ancestor chain:

- **The starting point is one class** (the defining class of the broadcasting method). Only that one class's ancestor chain matters. Even with multi-inheritance in the language, each individual broadcast walks a single well-defined chain.
- **Diamonds are handled with a visited set.** If class C inherits from both A and B, and both A and B inherit from Base, the walk visits Base only once (dedup by class identity).
- **Walk order.** Depth-first, in the order classes appear in the `inherits:` declaration. First-declared parent first, then its parents recursively, then next parent, etc.

## Open decisions

- **Interaction with dynamic class-stacking.** If a class is added to an existing instance via `$obj.add_class $extra` (post-instantiation), does the ancestor walk consult the instance's live class stack, or only the static inheritance chain of the defining class? Simpler answer: only the static inheritance chain — class-listener dispatch is a property of the class hierarchy, not of individual instances' current shape. Dynamic class-stacking would need to opt in some other way if it wants event participation. Decide before dynamic-stacking + class-listeners appears together in a real program.
- **Cross-ancestor listener ordering.** If listeners are registered on both `$widget` and its ancestor `$displayable` for the same event, in what order do the two classes' listeners fire? Options: specific-to-general (defining class first, then ancestors) matches how override-and-super feels; general-to-specific (ancestors first, then defining class) matches how `before_X`-style hooks often work in other frameworks; unspecified across classes documents "registration order within each class; don't rely on cross-class ordering." For V1, unspecified-across-classes is the simplest spec and covers most real needs. Formal ordering is a natural post-V1 addition if a real use case earns it.
- **Fast-path optimization.** Whether to short-circuit the ancestor walk when no class-listeners for the event exist anywhere. Optimization, not correctness. Decide based on measured cost when the mechanism is real.

## Testing

- **`.listen_to_class` returns true.** Assertion: `$l.obj.listen_to_class $c, 'e', 'm'` evaluates to `true`.
- **`.listen_to_class` is idempotent.** Register the same `(listener, class, event, method)` combo twice; broadcast from an instance; handler fires exactly once.
- **Class-listener fires on defining-class broadcast.** Register `.listen_to_class $c, 'e', 'm'`; a method defined on `$c` broadcasts `'e'` from an instance; handler fires with `$broadcaster` == the instance.
- **Class-listener fires on ancestor-class broadcast.** Register `.listen_to_class $parent, 'e', 'm'`; a subclass `$child` defines a method that broadcasts `'e'` from an instance; handler fires.
- **Ancestor walk terminates without class-listeners.** No class-listeners registered anywhere for `'e'`; broadcasting from a deeply-inheriting class incurs one hash miss per ancestor and then continues — no error, no exception.
- **Cross-source dedup: instance + class registrations fire once.** Register `.listen_to $instance, 'e', 'm'` AND `.listen_to_class $c, 'e', 'm'` (with `$instance` an instance of `$c`); broadcast `'e'`; handler fires once.
- **Cross-source dedup: multi-class registrations fire once.** Register `.listen_to_class $child, 'e', 'm'` AND `.listen_to_class $parent, 'e', 'm'`; broadcast from a `$child` instance; handler fires once.
- **Dedup key is `(listener, method)`.** Register `.listen_to_class $c, 'e', 'validate'` AND `.listen_to_class $c, 'e', 'log'`; broadcast `'e'`; both handlers fire.
- **Per-broadcast dedup scope.** Two separate broadcasts of `'e'` each fire the deduplicated handler once — the visited set does not persist across broadcasts.
- **Defining-class isolation across class stack.** Instance has classes `[$widget, $serializable]`; only `$widget` defines the broadcasting method; class-listeners on `$serializable` do NOT fire.
- **Diamond inheritance visits shared ancestor once.** Class C inherits from A and B; both A and B inherit from Base; class-listener registered on Base fires once when a C instance broadcasts.
- **`.unlisten_to_class` with three args removes the specific registration.** Register `(l, c, 'e', 'm')`; call `.unlisten_to_class $c, 'e', 'm'`; broadcast from an instance; handler does NOT fire.
- **`.unlisten_to_class` with two args removes all methods for that event on that class.** Register `(l, c, 'e', 'm1')` and `(l, c, 'e', 'm2')`; call `.unlisten_to_class $c, 'e'`; broadcast; neither handler fires.
- **`.unlisten_to_class` with one arg removes all events on that class.** Register `(l, c, 'e1', ...)` and `(l, c, 'e2', ...)`; call `.unlisten_to_class $c`; broadcast both events; no handlers fire.
- **`.unlisten_to_class` on non-registered combo silently succeeds.** Never registered; call returns `true`, does not raise.
- **`.unlisten_all` clears both instance and class registrations.** Listener has both `.listen_to` and `.listen_to_class` registrations; call `.unlisten_all`; broadcast in both dimensions; no handlers fire.
- **Class-listener registration is weak-ref on class.** Register against a class; drop all references to the class so it becomes GC-eligible; after collection, the listener's row referencing that class is gone.
- **Class-listener registration is weak-ref on listener.** Register a listener; drop references so it becomes GC-eligible; after collection, the class's registration row for that listener is gone.
- **Block-form class-listener registration removed on block exit.** `.listen_to_class $c, 'e', 'm' do ... end`; after the block completes, broadcasting `'e'` from a `$c` instance does NOT fire the handler.
- **Block-form preserves pre-existing class-listener.** Register `(l, c, 'e', 'm')` plain; enter a block-form `.listen_to_class $c, 'e', 'm' do ... end`; after the block exits, the original registration remains and still fires.
