# Object methods
<!--index: 1-->

<span class="tag">obj-methods</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_object_methods",
	"role": "spec for the `obj` method namespace on every Caspian value — including how the namespace itself works (inherited automatically from Object, dispatched as normal methods on the receiver, not an isolation boundary, cannot be overridden — engine hardcodes the name; no user-facing final-method facility in V1) plus the full method catalog. Methods spec'd: `.id` (returns the receiver's identity as a string assigned by Drinian at construction; immutable; survives serialization; not cryptographic — see Drinian for the format and rationale), `.truthy?` (returns truthiness derived from the receiver's primitive field: false/null primitive → false; anything else or no primitive field → true; immutable per instance), `.isa?($class)` (class-hierarchy query), `.null?` and `.defined?` (paired predicates for the null-vs-not-null check; each is the opposite of the other), `.jail(...)` (constructs a narrowing wrapper that exposes only the named methods), `.tap` (Ruby-style chain-preserving side-effect helper — yields the receiver, runs the block, returns the receiver), `.classes` (returns an array of the receiver's stack classes in top-to-bottom order, with `.ensure($class)`, `.add_unconditionally($class)`, and `.shadow` sub-methods; `.ensure($class)` has a bare form (permanent add if missing) and a block form (temporary add-if-missing with identity-tracked cleanup at block exit); `.add_unconditionally($class)` always pushes a new platter regardless of existing membership — verbose name deliberately since the always-push case is rare — and has the same bare/block form pair with the block form always adding and always removing at exit; both add methods place the new platter on TOP of the stack (just below the shadow if one exists), so its methods win at dispatch — same shape as Ruby's `obj.extend(Module)`; the stack is walked top-to-bottom / first-to-last for method lookup; `.shadow` accepts `ensure: true` to create the shadow if missing), `.methods` (returns a lazy methods object that behaves like a Hash for all non-mutating operations — `[:name]`, `.keys`, `.values`, `.each`, `.length`, containment tests; per-lookup walk of the class graph so single-method access doesn't materialize the whole set; `.keys` returns a fresh array on each call and can differ between calls if the class was mutated; nested namespaces surface as single entries — `.methods.keys` includes `'obj'` and other nested-namespace names but not the nested members underneath; mutating operations like `[:name] = value` and `.delete` raise; access-scoped so private methods surface when called from inside the class body via %self.obj.methods but not from outside; composes with the caller pattern), `.warn($message)` (attaches a warning-only platter to the receiver; never raises, never propagates up the chain — observational only), `.stack` (returns the receiver's LIVE stack array — the returned reference IS the object's stack, not a snapshot, so pushing/splicing/reordering/deleting entries or editing platter fields mutates the object directly; `.classes.ensure` and `.classes.add_unconditionally` are convenience wrappers on top of this raw access; user- and owner-only; carries a `.shadow` sub-method that returns the shadow platter, with the same `ensure: true` kwarg; framing: stack is mutable from outside but bucket has no external-mutation surface at all, an intentional asymmetry treating bucket as encapsulated state and stack as extendable-behavior surface, gated to user + owning role), and the freeze surface (`.freeze_bucket`, `.freeze_stack`, `.freeze` — two independent object-level immutability axes plus a shortcut that locks both; each with permanent and block-scoped forms; `.freeze_bucket` is top-level-only on the receiver's own bucket, does not cascade into nested structures; freezing primitive-value contents like Hash keys or Array elements is NOT covered here — that's a direct `.freeze` method on the primitive itself) and the companion frozen-predicate surface (`.bucket_frozen?`, `.stack_frozen?`, `.frozen?` — each returns true iff the corresponding freeze method has been called; `.frozen?` returns true iff both axis predicates return true; reflect the CURRENT freeze state so block-form freezes return true DURING the block and false again after); all freeze methods are idempotent (freezing already-frozen axes is a no-op), `.destroy` (terminates the receiver: calls `.close` if defined, then clears the bucket AND drops every platter from the stack; result is a destroyed object whose only useful surface is `.obj.id` and `.obj.destroyed?`; every other dispatch raises; the engine special-cases those two on destroyed objects since there's no class stack left to dispatch through; `.close` failures do not stop the destroy; idempotent; holding-is-access), and `.destroyed?` (returns true iff `.destroy` has been called on the receiver; callable on destroyed objects; one of only two methods that remain usable after destroy). Rule: shadows are never created by magic through a query — a bare `.shadow` call always returns whatever exists; `ensure: true` is the explicit opt-in for create-if-missing. Defining a singleton method (`method $foo.bar() ... end`) is the other explicit path that creates a shadow — the definition itself does the ensuring. More methods to be added as they're identified.",
	"status": "stub — starter methods spec'd (id, truthy?, isa?, null?, defined?, jail, tap, classes/ensure/shadow, methods, warn, freeze_bucket/freeze_stack/freeze, bucket_frozen?/stack_frozen?/frozen?, destroy, destroyed?); more to come",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

Methods in the `obj` namespace apply to any value in Caspian, reached through the dotted path `$foo.obj.method`. Every class inherits the namespace automatically — user classes don't need to declare it themselves.

## Why the namespace exists

Cross-cutting methods don't belong at the top level of every class's method surface. A class definition should read as a description of what makes the class specific.

Putting `.truthy?`, `.isa?`, `.jail`, and future object-wide utilities behind `obj.` keeps the top-level surface (the methods the class author actually defined) uncluttered — a `Widget` class exposes `Widget`-specific behavior at `$widget.method_name`, and everything object-wide lives one level down at `$widget.obj.method_name`.

Class authors who want a method surface at `$foo.X` still put it there. The `obj` namespace is for the built-in cross-cutting layer, not the class-specific one.

## `obj` returns an agent

`.obj` is an [agent](https://puck.uno/ideas/helpers/agents), not a nested namespace. Reading `$foo.obj` returns a fresh agent instance whose `@target` is `$foo`'s public surface and whose `@internals` is `$foo`'s private surface (bucket, private methods, stack, freeze state). The methods listed below are declared on the agent's class; the agent reaches into `$foo` via the two auto-fields when it needs to.

**Fresh per access, no caching.** Each `$foo.obj` access constructs a new agent — so an object that never touches `.obj` pays nothing (see [cost if you don't use it](https://puck.uno/requirements/concepts#cost-if-you-dont-use-it)). Two consecutive `$foo.obj` reads produce two distinct agent instances; neither reference is retained on `$foo`.

The agent construction is cheap — `@target` and `@internals` are just references to `$foo`, not copies. A `.obj.X` call is one agent construction plus one method dispatch, which the engine can be expected to optimize as a single logical operation once the interpreter is stable.

**Sweep pending.** The rest of this doc still carries phrasing left over from an earlier "nested namespace" framing where `%self` inside `obj.X` was the receiver. Under the agent model, `%self` inside those methods is the agent; the target is reached via `@target` and `@internals`. The method-by-method rewordings will land as the agent implementation is spec'd out; the shape here is what governs.

## `obj` cannot be overridden

`obj` is reserved. A class that tries to define its own `obj` — as a top-level method, as a nested namespace, as a field, or by any other means that would shadow the inherited namespace — is rejected at class-definition time with a raise.

The rule holds across every mechanism a class can extend its surface: user-declared methods, `nested :obj`, `field :obj`, singleton methods on an instance, delegation entries — none of them can install anything named `obj`. There is no opt-out.

Every value in the language exposes `.obj.X` uniformly; polymorphic code (`isa?`, `truthy?`, `jail`, everything the namespace grows over time) relies on that invariant. Any exception, however narrow, breaks the guarantee for every call site elsewhere in the codebase. The block is load-bearing, not paternalism.

**Not a general feature.** V1 has no user-facing "final method" facility (Java's `final`, Kotlin's non-`open`, etc.). `obj` is the sole hardcoded exception; the engine special-cases the name. If enough other cross-cutting names accumulate that need the same guarantee, a general mechanism can be considered post-V1.

## Methods

Every method below carries an explicit **Access** paragraph. "Untrusted" throughout means a role that is neither `user` nor the receiver's owning role — a downloaded library, a foreign-role callback, anything holding the object across a role boundary. The general principle: untrusted code can use the object's public interface but cannot mutate its structure (stack, bucket) or terminate it. A few methods split on form (bare vs block) — the block form is often safe from untrusted roles because it's self-releasing.

### `.bucket_frozen?`

Returns `true` if `.freeze_bucket` (or `.freeze`) has been called on the receiver. Reflects the CURRENT freeze state — for a block-form freeze, the predicate returns `true` DURING the block and `false` again after the block exits.

~~~caspian
$foo = {a: 1}
$foo.obj.bucket_frozen?          # false initially
$foo.obj.freeze_bucket
$foo.obj.bucket_frozen?          # true
~~~

**See also:** [`.stack_frozen?`](#stack-frozen) — the stack-axis predicate. [`.frozen?`](#frozen) — the combined predicate for both axes.

**Access.** Callable from any role.

### `.classes`

Returns an array of the classes currently in the receiver's stack, in stack order (top to bottom).

- **Freshly built per call.** Successive calls produce independent arrays; a reference held to a prior result is a snapshot of that moment, not a live view of the stack.
- **Not mutable as an array.** Pushing or splicing the returned array does nothing to the source object; the stack is the source of truth. The array itself is a plain read-only snapshot of class identities. The stack-mutation methods below operate on the underlying stack, not on the returned array — the array just carries them as an ergonomic launch pad.

~~~caspian
$widget = Widget.new()
$widget.obj.classes                          # e.g. [Widget]
~~~

**Access.** Callable from any role. (Mutation of the stack via `.ensure`, `.add_unconditionally`, or `.stack` has its own role restrictions — see those sections.)

#### `.classes.ensure($class)`

Guarantees at least one platter in the stack carries `$class` exactly. Two forms:

- **Bare call** — permanent. If the class is already in the stack, no-op. If not, a new platter with the class is inserted at the **top** of the stack (just below the shadow platter if one exists) and stays there.
- **Block call** — the class is present for the block's duration. Behavior at call time depends on whether the class was already in the stack:
  - **Already present** — nothing is added; the block runs; **nothing is removed at block exit.** The stack ends the block exactly as it started. The engine only removes what it added, and it added nothing.
  - **Not present** — a new platter is added at the top (just below the shadow if one exists), the block runs, and that specific platter is removed at block exit (or if the block raises).

**New platters go on top so their methods win.** The stack is walked top-to-bottom (first-to-last in the `.classes` array) for method lookup, so a platter added by `.ensure` overrides any same-named method on classes already in the stack — same shape as Ruby's `obj.extend(Module)`. The shadow platter, when present, always stays at position 0; `.ensure`'d platters land at position 1 in that case, ahead of the original class platters but below the singleton-method holder.

**Access is restricted to `user` and the receiver's owning role** — same rule as [`.stack`](#stack). Adding a class to another object's stack is a stack mutation, and stack mutations are gated. Other roles that hold a reference to the object can call its class-defined methods but cannot bolt on new classes.

**Exact-class match, not `.isa?`.** Subclasses in the stack do NOT count as "the class is there." If the stack has `Hex` and you call `.classes.ensure(Number)`, a new `Number` platter is still added — even though `Hex` extends `Number`. Class-hierarchy queries walk inheritance; stack membership is class-identity equality only.

~~~caspian
$widget = Widget.new()
$widget.obj.classes                          # e.g. [Widget]

# Bare form — new platter lands on top:
$widget.obj.classes.ensure(Serializable)     # Serializable goes to the top
$widget.obj.classes                          # [Serializable, Widget]

$widget.obj.classes.ensure(Widget)           # no-op, already present
$widget.obj.classes.ensure(Serializable)     # no-op, already present

# Block form — temporary if needed:
$widget.obj.classes.ensure(Renderer) do
	# Renderer is in $widget's stack for the block's duration
	$widget.render()
end
# Renderer platter removed on block exit; $widget's stack is back to what it was

# Subclass caveat:
$hex = 0xff                                  # Hex instance; stack has Hex
$hex.obj.classes.ensure(Number)              # adds Number on top, even though Hex extends Number
$hex.obj.classes                             # [Number, Hex]
~~~

**Cleanup is identity-tracked, not class-name-tracked.** The engine remembers the specific platter it created for a block-form `.ensure` call and removes exactly that platter at block exit. It doesn't scan the stack for "any platter carrying this class" and remove the first match — user code inside the block might have added its own platter with the same class through a different path, and that platter must be left alone. Two consequences fall out:

- **Nested calls compose cleanly.** An outer block-`.ensure($class) do ... end` can contain an inner bare-`.ensure($class)`. The inner sees the class present (added by the outer) and is a no-op; when the outer exits, it removes exactly its own platter.
- **Concurrent structural writes are safe.** If the block does something like `$widget.obj.classes.ensure($other_class)` or any other stack modification, those platters aren't candidates for the outer's cleanup — the outer only removes its own.

The block form's return value is the block's value (matching Ruby-style use-block semantics):

~~~caspian
$xml = $widget.obj.classes.ensure(XmlSerializer) do
	return $widget.to_xml()
end
# $xml holds whatever the block returned; the XmlSerializer platter is already gone
~~~

Removing the ensured platter explicitly from inside the block (e.g. via a hypothetical `.classes.remove(...)`) breaks the outer's cleanup contract; that case raises when the outer tries to remove its now-missing platter.

**Access.** Restricted to `user` and the receiver's owning role. Untrusted callers raise. Stack mutation is not part of the public interface exposed to arbitrary holders.

#### `.classes.add_unconditionally($class)`

Always pushes a new platter carrying `$class` at the top of the stack (just below the shadow platter if one exists), regardless of whether the class is already present. Unlike `.ensure`, this is not idempotent — calling it twice adds two platters. Two forms:

- **Bare call** — permanent. A new platter is pushed at the top and stays there.
- **Block call** — scoped. A new platter is pushed for the block's duration, then removed at block exit (or on raise). Same identity-tracked cleanup as `.ensure`'s block form — the engine removes the specific platter it added, not just "any platter carrying this class."

Same top-of-stack placement as `.ensure` — new platters win at method lookup because the stack is walked top-to-bottom. Same access rule too: **`user` and the receiver's owning role only**; other roles raise.

~~~caspian
$widget = Widget.new()
$widget.obj.classes                                     # [Widget]

# Bare form — permanent, always adds on top:
$widget.obj.classes.add_unconditionally(Widget)         # adds another Widget platter on top
$widget.obj.classes                                     # [Widget, Widget]

$widget.obj.classes.add_unconditionally(Serializable)
$widget.obj.classes                                     # [Serializable, Widget, Widget]

# Block form — scoped, always adds during the block:
$widget.obj.classes.add_unconditionally(Renderer) do
	# a new Renderer platter is in $widget's stack for the block's duration
	$widget.render()
end
# the Renderer platter added by this call is removed on block exit
~~~

**The verbose name is deliberate.** `.ensure` is what code should reach for by default; adding a duplicate platter is rare and usually a mistake. The long name is a speed bump that makes the reader (and reviewer) pause on the unusual choice. See [long descriptive names for rarely-used methods](https://puck.uno/requirements/concepts) — same rationale.

**Legitimate use cases** are rare but exist: classes that carry per-platter state (`bucket` per platter, see [object structure § bucket (per-platter)](https://puck.uno/requirements/built-in-classes/object/structure/#bucket-per-platter)) may want multiple independent platters of the same class on one object. Most classes don't; hence the speed bump.

**Access.** Same as `.classes.ensure` — restricted to `user` and the receiver's owning role. Untrusted callers raise.

#### `.classes.shadow`

Returns the shadow platter's class (the per-instance class populated with singleton methods), or `null` if the object has no shadow platter yet. This is a **query only** — calling it doesn't create a shadow.

Pass `ensure: true` to get the shadow class AND create the shadow if it doesn't already exist:

~~~caspian
$widget = Widget.new()
$widget.obj.classes.shadow                  # null — no shadow yet
$widget.obj.classes.shadow(ensure: true)    # creates the shadow, returns the shadow class

# Once the shadow exists, either form returns the class:
$widget.obj.classes.shadow                  # the shadow class
~~~

The `ensure:` kwarg matches the pattern used by `.classes.ensure($class)`: whenever an `obj`-namespace method might need to create structure that wasn't there, `ensure: true` is the switch that opts in. Shadows never appear by magic through a query — a bare `.shadow` call always returns whatever exists.

**One implicit path creates the shadow too:** defining a singleton method on the object. `method $foo.bar() ... end` is an explicit "I want a method on this specific object" — the shadow has to exist to hold the method, so the engine creates it as part of processing the definition. Callers who define singleton methods don't need to call `.shadow(ensure: true)` first; the definition itself does the ensuring.

~~~caspian
$widget = Widget.new()
$widget.obj.classes.shadow      # null — no shadow yet

method $widget.greet()
	puts 'hi'
end

$widget.obj.classes.shadow      # the shadow class — implicitly created by the definition
~~~

**Access.** Bare query form callable from any role — untrusted holders can inspect whether the receiver has a shadow. `ensure: true` restricted to `user` and the receiver's owning role, since it mutates the stack. The returned shadow itself is a class object, and untrusted callers cannot mutate it (adding methods to a shadow class follows class-mutation rules, which do not permit untrusted mutation of a class the caller does not own).

### `.destroy`

Terminates the receiver: calls its `.close` method if one exists, then clears every entry in its bucket AND drops every platter from its stack. The object holds no references to anything else once destroy returns. The result is a **destroyed** object — a shell whose only useful surface is `.obj.id` (still its original identity) and `.obj.destroyed?` (returns `true`). Every other dispatch on the destroyed object raises.

Use when code needs to guarantee that an object doesn't survive past a certain point — a session that must not leak beyond its scope, a file handle that must not stay open, a credential that must not linger in memory. Destroy is stronger than letting the object go out of scope, which leaves the object alive until Drinian's next GC pass; `.destroy` runs synchronously and leaves the observable behavior right there.

~~~caspian
$session = Session.new(user: $user)
$session.execute($request)
$session.obj.destroy         # .close is called (if it exists), then the bucket is cleared

$session.obj.destroyed?      # true
$session.obj.id              # still the original id — identity is preserved
$session.execute($other)     # raises — the session is destroyed
~~~

**Three-step process:**

1. **Close call.** If the receiver has a `.close` method (defined on its class or reachable through its stack), `.destroy` calls it. `.close` is the object's chance to run any orderly-shutdown logic — flush a buffer, release a lock, unregister from an event source, etc. If the object has no `.close`, this step is skipped.
2. **Bucket clear.** Every entry in `%bucket` is removed.
3. **Stack clear.** Every platter is dropped from the stack — class platters, the shadow (if any), nested-link platters, warning platters. The object's class stack ends up empty. Anything the stack was holding onto — singleton-method closures, warnings, nested-object markers — is released with it.

Nested objects that were reachable only through the destroyed receiver (via its bucket entries, shadow closures, or nested-link platters) lose their last root and become eligible for cleanup on Drinian's next pass.

**Post-destroy behavior — only two methods remain usable:**

- `.obj.id` — still returns the original identity. IDs are Drinian-level state, kept separately from the object's stack, and don't disappear.
- `.obj.destroyed?` — returns `true`. Also Drinian-level.

Every other dispatch raises with a "destroyed object" error. This includes class-defined methods, other `.obj.X` methods, freeze operations, downloaded methods, and bucket reads. With the stack cleared there's no class to dispatch through; the engine special-cases `.obj.id` and `.obj.destroyed?` on destroyed objects.

**`.close` failures do not stop the destroy.** If `.close` raises during step 1, `.destroy` catches the raise and proceeds to step 2. The point of `.destroy` is a guarantee — the object will be destroyed by the time this call returns. A `.close` that fails still leaves the object destroyed. Callers who need to know about a `.close` failure can invoke `.close` themselves first, handle the raise, then call `.destroy`.

**Idempotent.** Calling `.destroy` on an already-destroyed object is a no-op that returns cleanly. The `.close` step is skipped (the bucket is empty; there's nothing to close a second time).

**Any holder can destroy.** Follows the general holding-is-access rule: anyone with a reference to the object can call `.destroy`. That does mean untrusted code holding an object can destroy it out from under the owner. Callers who don't want that surface reachable pass a [jail](#jail) that omits `.destroy` rather than the raw object.

**Access.** Restricted to `user` and the receiver's owning role. Untrusted callers raise. If a class wants callers to trigger cleanup, it exposes `.close` on its own public surface; `.close` is a class-defined method and is reachable from any role. `.destroy`'s bucket-clear + stack-clear + destroyed-flag steps are framework-level termination and belong with user + owner.

### `.destroyed?`

Returns `true` iff `.destroy` has been called on the receiver, `false` otherwise.

~~~caspian
$foo = Widget.new()
$foo.obj.destroyed?          # false — freshly constructed

$foo.obj.destroy
$foo.obj.destroyed?          # true
~~~

Along with `.obj.id`, one of the only two methods that remain callable after `.destroy`.

**Access.** Callable from any role.

### `.freeze`

Locks BOTH the receiver's bucket and its stack — the shortcut for "make this object fully immutable." Equivalent to calling `.freeze_bucket` and `.freeze_stack` in sequence, or nesting the two block forms.

Caspian splits object-level immutability into two independent axes — bucket (data) and stack (class shape) — with individual methods for each; `.freeze` is the both-at-once form for the common case, and is what most developers reach for. Primitive-value contents (Hash keys, Array elements) are NOT part of the `.obj` freeze surface — those are frozen via a direct `.freeze` method on the primitive itself (`$hsh.freeze` and friends). See [Hash § Freezing](https://puck.uno/requirements/built-in-classes/primitives/hash#freezing) and the corresponding primitive-instance pages.

**Two forms:**

- **Bare call** — locks **permanently**. There is no `unfreeze`; once frozen the object stays frozen for its lifetime.

  ~~~caspian
  $foo.obj.freeze()  # $foo is now permanently frozen
  ~~~

- **Block call** — locks for the block's duration and releases when the block exits. Exception-safe: the release runs even if the block raises.

  ~~~caspian
  $foo.obj.freeze() do
    # $foo is frozen inside this block
  end

  # $foo is mutable again out here
  ~~~

**Idempotent.** Freezing an already-frozen object is a no-op — no raise, no change. Re-freezing at a finer level (e.g., `.freeze_bucket` after `.freeze` has already run) is also harmless — the axis is already locked; the second call does nothing.


~~~caspian
# Permanent full freeze:
$config.obj.freeze

# Temporary freeze during an untrusted call:
$widget.obj.freeze do
	$library.render($widget)  # both axes locked here
end
# Both axes writable again after the block exits.

# Nested block forms compose:
$widget.obj.freeze_stack do
	$widget.obj.freeze_bucket do
		# Both locked here (stack first, then bucket)
	end
	# Only stack locked here
end
# Both writable again
~~~

**See also:** [`.freeze_bucket`](#freeze-bucket) — lock the bucket axis only. [`.freeze_stack`](#freeze-stack) — lock the stack axis only. [`.frozen?`](#frozen), [`.bucket_frozen?`](#bucket-frozen), [`.stack_frozen?`](#stack-frozen) — the frozen-predicate surface.

**Access.** Bare form restricted to `user` and the receiver's owning role — a permanent freeze is a permanent commitment and belongs with the roles that own the object. Block form callable from any role — the freeze self-releases at block exit, so worst case the owner sees the object frozen during some call and then not, which is harmless. Block form supports the legitimate defensive-callee pattern of freezing an argument while working with it.

### `.freeze_bucket`

Locks the receiver's bucket against writes. The bucket hash itself becomes read-only: `@field = ...` and `%bucket['key'] = ...` raise. Reads still work.

**Two forms:**

- **Bare call** — permanent.
- **Block call** — scoped to the block; the release runs on block exit (or raise).

~~~caspian
$foo.obj.freeze_bucket             # permanent
$foo.obj.freeze_bucket do
	# bucket locked here
end
# bucket writable again
~~~

**Idempotent.** Calling `.freeze_bucket` on an already-frozen bucket is a no-op.

**Top-level only.** The freeze applies to the bucket's own top-level entries, not to what those entries point at. A nested Hash, Array, or user-class instance stored in the bucket can still be mutated through its own surface — `@config['theme'] = 'light'`, `@config.items.push(x)`, and `@inner.rename('renamed')` all still work after `.freeze_bucket`. For deeper immutability, freeze the nested structures separately (each nested Hash and Array has its own `.obj.freeze_bucket`; each user-class instance has its own freeze surface).

~~~caspian
$widget.@config = {theme: 'dark', items: [1, 2, 3]}
$widget.@inner = Widget.new(name: 'nested')

$widget.obj.freeze_bucket

$widget.@config = {}                # raises — top-level bucket write
$widget.@config['theme'] = 'light'  # works — nested Hash, freeze doesn't cascade
$widget.@config.items.push(4)       # works — nested Array, freeze doesn't cascade
$widget.@inner.rename('renamed')    # works — nested Widget, freeze doesn't cascade

# For deeper immutability, freeze each reachable structure yourself:
$widget.@config.obj.freeze_bucket
$widget.@config.items.obj.freeze_bucket
~~~

Design rationale for top-level-only: bucket freeze is a single-object statement — "no more writes to THIS bucket." Auto-cascading would silently freeze things the developer may not own or expect frozen; making each freeze explicit keeps the surface predictable and the developer in control of what actually locks down.

**See also:** [`.freeze`](#freeze) — lock both axes at once. [`.freeze_stack`](#freeze-stack) — lock the stack axis. [`.bucket_frozen?`](#bucket-frozen) — the corresponding predicate.

**Access.** Same as `.freeze` — bare form restricted to `user` and the receiver's owning role; block form callable from any role.

### `.freeze_stack`

Locks the receiver's stack against modification. No platter can be added, removed, or reordered. Defining a singleton method (which would grow the shadow) is blocked; adding a class via `.classes.ensure(...)` or `.classes.add_unconditionally(...)` is blocked; nothing about the stack shape can change. The methods the object has at freeze time are the methods it will always have.

**Two forms:**

- **Bare call** — permanent.
- **Block call** — scoped to the block; the release runs on block exit (or raise).

~~~caspian
$foo.obj.freeze_stack              # permanent
$foo.obj.freeze_stack do
	# stack locked here
end
# stack modifiable again
~~~

**Idempotent.** Calling `.freeze_stack` on an already-frozen stack is a no-op. Bucket writes are unaffected — `.freeze_stack` doesn't lock data, only the class shape.

**See also:** [`.freeze`](#freeze) — lock both axes at once. [`.freeze_bucket`](#freeze-bucket) — lock the bucket axis. [`.stack_frozen?`](#stack-frozen) — the corresponding predicate.

**Access.** Same as `.freeze` — bare form restricted to `user` and the receiver's owning role; block form callable from any role.

### `.frozen?`

Returns `true` if BOTH `.bucket_frozen?` and `.stack_frozen?` are `true` — that is, `.freeze` has been called, or both `.freeze_bucket` and `.freeze_stack` have been called individually. Reflects the CURRENT freeze state — for block-form freezes, the predicate returns `true` DURING the block and `false` again after the block exits.

~~~caspian
$foo = {a: 1}
$foo.obj.frozen?                 # false initially — no axis frozen

$foo.obj.freeze_bucket
$foo.obj.frozen?                 # false — only bucket is frozen

$foo.obj.freeze                  # locks both axes
$foo.obj.frozen?                 # true
~~~

The frozen-predicate surface parallels the fine-grained `.frozen?` on variable-objects and `.field_frozen?(key)` on hashes — one naming convention across the freeze surfaces.

**See also:** [`.bucket_frozen?`](#bucket-frozen) — the bucket-axis predicate alone. [`.stack_frozen?`](#stack-frozen) — the stack-axis predicate alone.

**Access.** Callable from any role.

### `.id`

Returns the receiver's identity as a **string**. IDs look like integers (`'1'`, `'42'`, `'1000'`) but the runtime never coerces them to numeric type. Assigned by [Drinian](https://puck.uno/requirements/drinian) at construction; immutable for the object's lifetime; treat the value as opaque. See the Drinian page for how IDs are generated, why they're strings, and why they're not UUIDs.

~~~caspian
$widget = Widget.new()
$widget.obj.id                     # e.g. '42'
~~~

**Identity comparison.** The easiest way to check that two references point at the same object is `$foo.obj == $bar.obj` — two `.obj` agents compare equal iff they wrap the same target. Comparing `.obj.id` strings works too and is what the agent's `==` reduces to under the hood, but the agent-level form reads more naturally at the call site.

~~~caspian
$w1 = Widget.new()
$w2 = Widget.new()
$w3 = $w1                          # same reference, same object

$w1.obj == $w3.obj                 # true — one object
$w1.obj == $w2.obj                 # false — two objects

# The .id comparison works too:
$w1.obj.id == $w3.obj.id           # true
$w1.obj.id == $w2.obj.id           # false
~~~

**Survives serialization.** An object serialized to JSON (via a worldlet, Mikobase record, or Puck message) carries its ID along with its bucket and stack. A rehydrated instance reports the same ID it had before the round-trip — which is what makes cross-boundary object identity meaningful.

**Unique for the process lifetime; never reused.** Every ID assigned during a Caspian process is unique for that process's whole run. An ID belonging to an object that has been destroyed (or dropped and garbage-collected) is never handed out to a subsequently-constructed object — Drinian's counter only ever moves forward. Two objects that existed at different times during the same process cannot collide on `.id`.

**Not cryptographic.** IDs are unique within a Drinian instance's lifetime; they are not random, not unpredictable, and not intended to be secret. Anything security-sensitive should carry its own token, not lean on `.id`.

**Never null, never raises.** Every value in the language has an ID. Even a bare object (`%('puck.uno/object').new()`) gets one at construction.

**Access.** Callable from any role.

### `.isa?($class)`

Class-hierarchy query. Returns `true` if the receiver is an instance of `$class` or any subclass of `$class`; returns `false` otherwise. The check is subclass-inclusive at every level of the inheritance chain — an instance of a class N steps deep in the hierarchy returns `true` for `.isa?` against any of its N ancestors.

~~~caspian
$hex = 0xff
$hex.obj.isa?(Hex)         # true
$hex.obj.isa?(Number)      # true — Hex extends Number
$hex.obj.isa?(Object)      # true — every class extends Object
$hex.obj.isa?(String)      # false

$flavored = null.with_flavor(:pending)
$flavored.obj.isa?(Null)   # true — flavored nulls remain Null instances
~~~

**Access.** Callable from any role.

### `.jail(...)`

Constructs a **jail** — a separate helper object that holds a private reference to the receiver (the *prisoner*) and exposes ONLY the named methods, forwarding calls to those methods through to the prisoner. Every other method dispatch through the jail raises.

The jail is not the prisoner: it has its own class, its own identity, and no access to the prisoner's internals — no bucket reads, no methods outside the exposed list, no way to hand out the prisoner. Used to narrow what a role hands across a boundary; see [object-access § Narrowing: pass a jail, not the raw object](https://puck.uno/requirements/roles/object-access#narrowing-pass-a-jail-not-the-raw-object).

~~~caspian
$widget = Widget.new(name: 'primary', internal_state: 'sekrit')
$narrowed = $widget.obj.jail(:name, :label)

$narrowed.name              # forwards to $widget.name — works
$narrowed.label             # forwards to $widget.label — works
$narrowed.internal_state    # raises — the jail doesn't expose this method
~~~

The jail is a **separate object**, not `$widget` in disguise. It holds a private reference to the prisoner and mediates calls; nothing in the jail's implementation can read the prisoner's bucket, invoke methods outside the exposed list, or hand the prisoner reference back out. Callers holding the jail have no path to the prisoner's internals.

Because the jail is its own object:

- **It has its own `.obj.X` surface.** `$narrowed.obj.truthy?` returns `true` (the jail is a truthy value, being neither `false` nor `null`); `$narrowed.obj.isa?(Jail)` returns true; `$narrowed.obj.isa?(Widget)` returns false. None of these queries reveal anything about the prisoner.
- **`.obj.jail(...)` on the jail doesn't re-open access to the prisoner.** Calling `$narrowed.obj.jail(:foo)` returns a new jail wrapping THE JAIL, not the prisoner. Method names in that new jail resolve against the jail's own surface, not `$widget`'s.
- **The jail has no way to re-expose the prisoner.** There is no `.unjail`, no `.prisoner`, no reflection method that returns the wrapped object. Handing across a jail is one-way narrowing.

Common pattern: user code holding a private-state-bearing instance passes only the safe surface to untrusted code:

~~~caspian
$library.render($widget.obj.jail(:name, :label, :bounding_box))
~~~

The library sees a value that responds to the three named methods and fails hard for anything else. It cannot read `$widget`'s bucket, call `$widget`'s other methods, or hand the underlying widget to a third party — the jail doesn't give it any of those.

**Access.** Callable from any role. Untrusted callers only ever narrow their own view of the receiver; no capability is transferred and no side effect touches the prisoner.

### `.methods`

Returns a **lazy methods object** that behaves like a [Hash](https://puck.uno/requirements/built-in-classes/primitives/hash) for all **non-mutating** operations. Method lookup walks the class graph on demand; the full set of methods is never eagerly materialized.

**Non-mutating hash surface.** Everything a Hash supports for reading — `[:name]`, `.keys`, `.values`, `.each`, `.length`, containment tests, iteration — works identically on the methods object. Mutating operations (`[:name] = value`, `.delete`, etc.) are not part of the surface; the class is the source of truth, and the methods object never modifies it.

~~~caspian
class # widget
	method greet()
		return 'hi from ' + @name
	end

	method describe()
		return @name + ': widget'
	end
end

$w = $widget_class.new(name: 'primary')
$w.obj.methods[:greet].call         # 'hi from primary'

$w.obj.methods.keys.each do ($name)
	puts $name
end

$w.obj.methods.each do ($name, $value)
	puts $name + ': ' + $value.call.to_string
end
~~~

`.each` yields `(name, value)` pairs — a two-arg block. A one-arg block raises for wrong param count; Caspian does not auto-collapse the pair into an array. To iterate names alone, use `.keys.each do ($name) ... end`.

**Lazy lookup via `[:name]`.** Each subscript access walks the receiver's class graph for that specific method — same walk that a normal method dispatch would do. If the method exists (and is visible from the call site), the value is a first-class **bound method-callable** with `%self` bound to the receiver. If it doesn't exist, the value is null — subscript on a missing name never raises:

~~~caspian
$foo.obj.methods['not_a_key']   # null
~~~

Common case: code fetches one method (`$w.obj.methods[:greet]`) and never asks about the others. The engine does one graph walk. No hash of every method the class carries gets built.

**`.keys`, `.values`, `.each` walk the graph on demand.** `.keys` walks the class graph, collects the visible method names, and returns a fresh array. `.values` does the same and returns bound callables. `.each` yields `(name, value)` pairs.

Successive calls re-walk the graph. If the class was mutated between two `.keys` calls (a method added, an `amend` applied, a singleton method attached), the two arrays can differ. The methods object doesn't cache a snapshot; each enumeration reflects the class state at call time.

**Not mutable.** Attempting a write on the methods object — `$w.obj.methods[:foo] = ...` — raises. Same for `.delete` or any other mutating operation. The methods object exists to read the class's method surface, not to modify it.

**Downloaded methods excluded.** Ad-hoc method application via `$foo.$fn` ([downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods)) is a call-site application, not a class-level attachment. Such applications do not appear in `.methods` — the class is the source of truth, and downloaded methods never modify the class.

**All visible top-level methods.** Every method reachable through the receiver's platter stack and inheritance graph is a candidate. Includes inherited methods, methods added via amendments, and shadow methods (singleton methods on this specific object). Method-resolution rules from [method resolution](tag:method-resolution) determine which class's version wins on collision — the methods object reflects what would be dispatched, not every candidate.

**Nested namespaces surface as single entries.** A nested method namespace (defined via [nested](https://puck.uno/requirements/classes/nested), including the cross-cutting `obj` namespace every value carries) appears as one entry keyed by the namespace name. Its members do not get flattened into the top-level methods list. To enumerate a nested namespace's methods, access the namespace and query its own `.methods`:

~~~caspian
$w.obj.methods.keys           # includes 'greet', 'describe', 'obj', and any other nested namespace names — NOT 'truthy?', 'isa?', etc.
$w.obj.methods[:obj]          # the obj namespace itself
$w.obj.methods[:obj].methods.keys   # 'truthy?', 'isa?', 'methods', 'classes', 'warn', ...
~~~

**Access-context aware.** Visibility depends on where the call is made from:

- **From inside the class body** — `%self.obj.methods` returns a methods object that surfaces all methods, including ones marked `.private = true`. The class has full visibility into its own surface.
- **From outside the class body** — `$foo.obj.methods` surfaces only public methods. Private methods do not appear via `[:name]`, `.keys`, or iteration. Same rule as calling a private method directly from outside: the surface is hidden, not just gated.

~~~caspian
class # widget
	method public_op()
		return %self.obj.methods    # surfaces :helper — inside the class body
	end

	private method helper()
		return @count * 2
	end
end

$w.public_op                           # methods object that surfaces :helper
$w.obj.methods                      # methods object that does NOT surface :helper (called from outside)
~~~

Access checking happens at each lookup — the methods object always exposes "what you can actually call **from where you're asking now.**"

**No bearer-token semantics.** Capturing a callable for a private method from inside the class body (`$m = %self.obj.methods[:helper]`) does NOT let outside code invoke it. Access is checked at each `.call` (not at capture) against the current frame's [`%call.method_class`](https://puck.uno/requirements/global-methods/call/#call-method-class). Once `$m` is handed to code outside the class body, invoking `$m.call` from that outside frame raises — the frame's `%call.method_class` doesn't match the class that carries the private method.

The reference doesn't carry access; the calling context always governs. Same rule as calling the method through `%self` vs. through a captured `$obj`.

**On a jail — only the jailed methods appear.** When `.methods` is called on a jail, it reflects the jail's own surface, not the wrapped prisoner's. Method calls on a jail dispatch through the jail (methods not in the allowed list raise), so introspection matches the callable surface — the jail never leaks knowledge of what the prisoner would otherwise expose:

~~~caspian
$foo.obj.jail(:bar, :gup) do ($jail)
	$jail.methods.keys.each do ($key)
		puts $key    # outputs 'bar' then 'gup'
	end
end
~~~

**Iteration is over a snapshot from `.keys`.** `.keys.each do ($name) ... end` iterates the array `.keys` returned. Class mutations inside the loop don't retroactively appear in the current iteration — the array was materialized before the loop began. A subsequent `.keys` call re-walks and could return a different set.

**Composes with the caller pattern.** Because each looked-up value is a bound callable, you can build a caller for it:

~~~caspian
$caller = $w.obj.methods[:greet].caller.new
$caller.call                           # runs $w.greet() with %self = $w
~~~

For V1, that's the whole story — lazy lookup, no cache across calls, access-scoped by call context.

**Access.** Callable from any role. Private-method visibility still follows the call-site rule (from inside the class body, private methods surface; from outside, they don't) — that rule is orthogonal to the untrusted-role question.

### `.null?` / `.defined?`

Convenience predicates for the null-vs-not-null check, which is common enough in real code to earn its own short names. Both are strictly booleans.

- `.null?` returns `true` if the receiver is a Null instance (including any subclass of Null — flavored nulls satisfy the check). Equivalent to `.isa?(Null)`.
- `.defined?` returns the opposite — `true` if the receiver is not a Null instance. Equivalent to `not .isa?(Null)`.

`.defined?` reads better than `not .null?` when the surrounding phrasing is affirmative (`if $x.obj.defined? ...` vs `if not $x.obj.null? ...`), which is the reason for pairing both.

~~~caspian
null.obj.null?             # true
null.with_flavor(:pending).obj.null?   # true — flavored nulls are still Null
false.obj.null?            # false — false is not null
0.obj.null?                # false
''.obj.null?               # false
[].obj.null?               # false

null.obj.defined?          # false
'hello'.obj.defined?       # true
0.obj.defined?             # true
false.obj.defined?         # true — false is a defined value, just falsy
~~~

Note the distinction from `.truthy?`: `false.obj.truthy?` is `false`, but `false.obj.null?` is also `false` — a defined-but-falsy value is not null. The three predicates answer three different questions:

- `.truthy?` — how does this evaluate in a condition?
- `.null?` — is this specifically a Null instance?
- `.defined?` — is this anything OTHER than a Null instance?

**Access.** Callable from any role.

### `.stack`

Returns the **live** stack array — the ordered sequence of platters described in [object structure § Stack](../structure/#stack). The array returned IS the object's stack, not a snapshot: pushing, splicing, reordering, or deleting entries mutates the object directly. The full serialized shape is available on every platter — `class`, `shadow` flag, `nested` UUID link, `warning`, per-platter `bucket`, and per-platter `vibecode` all show through, and any of them can be edited in place.

`.classes.ensure` and `.classes.add_unconditionally` are convenience wrappers on top of this raw access; anything they can't express (reorder existing platters, remove a specific class, splice a platter into a specific position, patch a platter's `vibecode`, etc.) is available by manipulating the array directly:

~~~caspian
$widget.obj.stack.push {class: %('caspian.uno/renderer')}
$widget.obj.stack.reverse                  # invert dispatch precedence
$widget.obj.stack.delete_at(2)             # remove the third platter
~~~

**Access is restricted to `user` and the receiver's owning role.** Every other role gets a raised error on the call. This is a departure from the general holding-is-access rule; class-defined dispatch on the receiver still follows holding-is-access, but `.stack` is gated because reading it exposes every object nested inside AND lets the caller rewrite the object's dispatch surface — each nested object could carry credentials, tokens, or other state its owner would not want handed to arbitrary callers, and untrusted stack rewrites could silently hijack every subsequent method call.

~~~caspian
# From user code:
$widget.obj.stack        # works — user is user

# From a downloaded method running as some other role:
function &introspect()
	return %self.obj.stack
end

$widget.$introspect      # raises — the current role is not user and not $widget's owner
~~~

If a class wants to expose limited structural information across role boundaries, it can define its own methods that return the specific pieces it considers safe (`.class_list`, `.has_warnings?`, etc.). `.stack` itself stays gated.

**You can mutate the stack from outside; you cannot mutate the bucket from outside.** The stack is the surface where other code extends an object's behavior (mixing in classes via `.classes.ensure`, adding singleton methods, and so on) — same shape as Ruby's `obj.extend(Module)`. That mutation is intentional but role-restricted: only `user` and the object's owning role can call the stack-mutating methods (`.classes.ensure`, `.classes.add_unconditionally`, direct writes through `.stack`). The bucket has NO external-mutation surface at all — there is no `.obj.bucket=`, no `.obj.bucket.set(...)`, no accessor at any role. Bucket state is the object's own story about itself and can only be written by its own methods. The asymmetry treats bucket as encapsulated state (owned by the class) and stack as an extendable-behavior surface (open to the world, gated to trusted roles).

**Access.** Restricted to `user` and the receiver's owning role. Untrusted callers raise. Both reading (leaks every nested object) and writing (silently hijacks all subsequent dispatch) are gated together.

#### `.stack.shadow`

Returns the shadow **platter** if one exists (or `null` if the object has no shadow yet).

Where [`.classes.shadow`](#classes-shadow) returns the shadow's class object, `.stack.shadow` returns the whole shadow platter — the hash that carries `shadow: true`, its `class` field, and any `bucket` / `vibecode` fields the shadow platter happens to have.

Bare call is **query only** — never creates a shadow. Pass `ensure: true` to get the shadow platter AND create it if needed, matching the pattern used by `.classes.shadow(ensure: true)` and `.classes.ensure($class)`.

~~~caspian
$widget.obj.stack.shadow                  # null — no shadow yet
$widget.obj.stack.shadow(ensure: true)    # creates the shadow, returns the platter

# Once the shadow exists:
$widget.obj.stack.shadow                  # the shadow platter hash
~~~

**Access.** Same as `.stack` — restricted to `user` and the receiver's owning role. Untrusted callers raise.

### `.stack_frozen?`

Returns `true` if `.freeze_stack` (or `.freeze`) has been called on the receiver. Reflects the CURRENT freeze state — for a block-form freeze, the predicate returns `true` DURING the block and `false` again after the block exits.

~~~caspian
$bar = {a: 1}
$bar.obj.freeze_stack do
	$bar.obj.stack_frozen?       # true here
end
$bar.obj.stack_frozen?           # false again after the block
~~~

**See also:** [`.bucket_frozen?`](#bucket-frozen) — the bucket-axis predicate. [`.frozen?`](#frozen) — the combined predicate for both axes.

**Access.** Callable from any role.

### `.tap`

Yields the receiver to a block, runs the block for its side effect, then returns the receiver so the chain continues. Useful for slotting a logging call, an assertion, a debug print, or any other side-effecting step into the middle of a chained expression without breaking the chain and without introducing a throwaway variable.

The block receives the **underlying value** — the same value the chain will continue on — not the `.obj` helper. `.obj.tap` itself returns that underlying value, so a method call after `.tap`'s block resolves against the receiver, not against the helper.

~~~caspian
$result = build_widget()
	.obj.tap do ($w)
		puts 'built: ' + $w.name
	end
	.render()

# Equivalent to:
$w = build_widget()
puts 'built: ' + $w.name
$result = $w.render()
~~~

The two are behaviorally identical; `.tap` just avoids the intermediate variable and keeps the chain readable when the side effect is a one-liner. If the side effect grows past that, breaking the chain and using a real variable name is fine — `.tap` is a chain-preservation tool, not a mandate.

The block's return value is **ignored**. Only side effects (writes, log calls, mutations) matter; whatever the block evaluates to is dropped, and `.tap` returns the receiver regardless.

~~~caspian
5.obj.tap do ($n)
	$n * 100        # ignored
end                  # returns 5, not 500
~~~

**Access.** Callable from any role. `.tap` runs the block with the receiver — if the caller already holds the receiver, `.tap` adds no capability.

### `.truthy?`

Returns the receiver's truthiness as a boolean (`true` or `false`). Equivalent to how the receiver evaluates in an `if` or `while` condition.

The engine reads the receiver's [primitive field](https://puck.uno/requirements/built-in-classes/object/structure/#primitive-field) and applies the rule:

- Primitive field is `false` → returns `false`.
- Primitive field is `null` → returns `false`.
- Primitive field holds any other JSON value (number, string, array, hash, `true`) → returns `true`.
- No primitive field at all (user class with no primitive-bearing ancestor) → returns `true`.

Consequence: `False` and `Null` instances (and their subclasses, which inherit the constructor path that sets the primitive field) return `false`; every other value returns `true`. The primitive field is set by the class's constructor at instantiation and cannot be changed thereafter — no method, no bucket write, no downloaded-method application can flip it, so truthiness is stable for the object's lifetime.

~~~caspian
5.obj.truthy?          # true
''.obj.truthy?         # true — empty string is truthy
[].obj.truthy?         # true — empty array is truthy
false.obj.truthy?      # false
null.obj.truthy?       # false
~~~

The value follows the general [truthy/falsy rule](https://puck.uno/requirements/syntax/truthy-and-falsy): only `null` and `false` are falsy; everything else is truthy. `.truthy?` returns the same value the language uses when the receiver is evaluated as a condition.

**Access.** Callable from any role.

### `.warn($message)`

Attaches a warning to the receiver by pushing a new **warning-only platter** onto the stack. The platter carries `warning: <the created warning object>` — a Warning-class instance wrapping `$message`. The warning-platter form is spec'd in [object/structure § warning](../structure/#warning).

**Never raises.** `.warn` is purely observational — nothing about control flow changes. The receiver keeps running as it was; the warning just sits attached to it for whoever cares to inspect the stack later.

**Never propagates up the chain.** The warning is local to the receiver. Callers, the current frame, the enclosing chain, and any handler up the stack are unaffected — no notification, no unwind, no propagation of any kind. If you want the caller to know something is off, use an explicit return value, an event, or a raised error; `.warn` is not that.

Returns the receiver, so it chains cleanly:

~~~caspian
$parsed_date.obj.warn('parsed leniently; source string was ambiguous')
             .obj.warn('century inferred from context')
~~~

Both warnings land as separate warning-only platters on `$parsed_date`. The stack after the two calls has two warning platters; neither affects dispatch (no `class` field) and both travel with the value as it's passed, stored, or serialized.

Typical use cases:

- A parser that accepted a value with a caveat: "century inferred," "trailing whitespace dropped," "encoding fell back to UTF-8."
- A validator that noticed something suspicious but didn't want to reject: "this user record's timezone is unusual for their region."
- An engine-internal signal about a stored value whose class disagrees with its declared schema at deserialization time.

Any code — engine, library, or application — can call `.warn`. The inspection API (walking warning platters, reading their `warning` field) is spec'd elsewhere as it grows.


**Access.** Callable from any role. Warnings are observational metadata; attaching one doesn't grant any capability.

## Testing

### Namespace mechanics

- **`obj` namespace exists on every value without declaration** — a user-defined class that does not mention `obj` still has `$instance.obj.truthy?` etc. reachable on its instances.
- **`obj` namespace method binds `%self` to the receiver** — inside `obj.truthy?` (and any other `obj.` method), `%self` is the receiver, not a helper or proxy.
- **`obj.` dispatch is not a wrapper** — the receiver returned to a subsequent chain step is the original object; chaining `$foo.obj.tap { }.some_method` calls `some_method` on `$foo` itself.
- **`obj` cannot be overridden** — defining `method obj() ... end`, `nested :obj ... end`, `field :obj`, or a singleton method named `obj` on any class raises at class-definition time.

### `.id`

- **Returns a string** — `Widget.new().obj.id.obj.isa?(String)` is `true`.
- **String looks like an integer** — the returned value matches an integer-shaped pattern (`^[0-9]+$`) under the default Drinian.
- **Not coerced to a number** — `.obj.id` never returns a Number instance, even when the string is a valid integer literal.
- **Stable for the object's lifetime** — two `.obj.id` calls on the same reference return the same string.
- **Same object → same ID** — after `$b = $a`, `$a.obj.id == $b.obj.id` is `true`.
- **Different objects → different IDs** — two separate `Widget.new()` calls produce two different `.obj.id` values.
- **Agent-level `==` matches ID equality** — for any `$a`, `$b`: `$a.obj == $b.obj` returns the same boolean as `$a.obj.id == $b.obj.id`.
- **Bare object has an ID** — `%('puck.uno/object').new().obj.id` returns a string (not null).
- **Every primitive has an ID** — each of `42`, `'hi'`, `true`, `[]`, `{}` reports a string from `.obj.id`. (Shared instances — like the singleton `true` — return the same ID from every reference to them.)
- **ID survives serialization round-trip** — an object serialized to JSON and rehydrated reports the same `.obj.id` before and after.
- **ID of a destroyed object is not reused** — after `$a.obj.destroy`, subsequently constructed objects in the same process never receive `$a.obj.id` as their ID.
- **ID of a garbage-collected object is not reused** — after an object goes out of scope and Drinian reclaims it, no later-constructed object receives its former ID.
- **Never raises** — `.obj.id` is always callable, on any value, without error.

### `.truthy?`

- **Returns `true` for a truthy value** — `5.obj.truthy?` is `true`.
- **Returns `false` for `false`** — `false.obj.truthy?` is `false`.
- **Returns `false` for `null`** — `null.obj.truthy?` is `false`.
- **Empty string is truthy** — `''.obj.truthy?` is `true`.
- **Empty array is truthy** — `[].obj.truthy?` is `true`.
- **Empty hash is truthy** — `{}.obj.truthy?` is `true`.
- **Zero is truthy** — `0.obj.truthy?` is `true`.
- **Return type is always Boolean** — `.obj.truthy?` on any value returns `true` or `false`, never any other type.
- **Truthiness is immutable** — after `$w = Widget.new()`, no bucket write, no class add, no downloaded-method application on `$w` changes `$w.obj.truthy?`. The primitive field is set at construction and never mutated.
- **Subclass of Null inherits falsy** — an instance of a class extending Null reports `.obj.truthy?` as `false`.
- **Subclass of False inherits falsy** — same for a subclass of False.

### `.isa?`

- **Direct class match returns `true`** — `5.obj.isa?(Number)` is `true`.
- **Ancestor class match returns `true`** — an instance of a subclass of Number reports `.obj.isa?(Number)` as `true`.
- **Object is always in the chain** — for any value, `.obj.isa?(Object)` is `true`.
- **Non-ancestor class returns `false`** — `5.obj.isa?(String)` is `false`.
- **Flavored null remains a Null instance** — `null.with_flavor(:pending).obj.isa?(Null)` is `true`.
- **Return type is always Boolean** — `.obj.isa?($cls)` on any value returns `true` or `false`.

### `.null?` and `.defined?`

- **`null.obj.null?`** is `true`.
- **`null.with_flavor(:pending).obj.null?`** is `true` — flavored nulls are still Null instances.
- **`false.obj.null?`** is `false`.
- **`0.obj.null?`** is `false`.
- **`''.obj.null?`** is `false`.
- **`[].obj.null?`** is `false`.
- **`null.obj.defined?`** is `false`.
- **`'hello'.obj.defined?`** is `true`.
- **`0.obj.defined?`** is `true`.
- **`false.obj.defined?`** is `true` — false is defined but falsy.
- **`.null?` and `.defined?` are always opposites** — for any value, `.obj.null?` and `.obj.defined?` return different booleans.
- **Return type is always Boolean** — both methods return `true` or `false`, never any other type.

### `.jail`

- **Named methods forward to prisoner** — `$w = Widget.new(name: 'x'); $w.obj.jail(:name).name` is `'x'`.
- **Unlisted methods raise** — calling a method NOT in the jail's exposure list raises.
- **Jail has its own class identity** — `$narrowed.obj.isa?(Jail)` is `true`.
- **Jail is not the prisoner's class** — `$w.obj.jail(:name).obj.isa?(Widget)` is `false`.
- **Jail is truthy** — `$w.obj.jail(:name).obj.truthy?` is `true`.
- **No `.unjail` method exists on the jail** — calling `.unjail` on the jail raises.
- **No `.prisoner` method exists on the jail** — calling `.prisoner` on the jail raises.
- **Re-jailing the jail wraps the jail, not the prisoner** — `$jail.obj.jail(:name)` produces a jail whose named-method resolution runs against the outer jail's own surface, not against the original prisoner.
- **Bucket reads on jail don't reach prisoner** — attempts to read `%bucket` fields from inside the jail do not return prisoner state.
- **Jail exposes only the exact methods listed** — passing `:name` and `:label` exposes those two and no others, even if the prisoner has closely-named methods.

### `.tap`

- **Returns the receiver** — `5.obj.tap { }` is `5`.
- **Block receives the receiver** — inside `5.obj.tap do ($n) ... end`, `$n` is `5`.
- **Block return value is ignored** — `5.obj.tap { $n * 100 }` is `5`, not `500`.
- **Side effects run** — a `.tap` block that mutates a captured variable observes the mutation afterward.
- **Chain continues after `.tap`** — `[1, 2].obj.tap { }.length` is `2`.
- **Works on falsy values** — `false.obj.tap { }` returns `false`; `null.obj.tap { }` returns null.
- **Block runs exactly once** — a counter incremented inside a `.tap` block increases by 1 per `.tap` call, not zero or more.

### `.classes`

- **Returns the stack classes in order** — for `$w = Widget.new()`, `$w.obj.classes` returns an array beginning with Widget.
- **Freshly built per call** — two successive calls to `.obj.classes` return distinct arrays (not the same identity).
- **Prior snapshot not affected by later stack changes** — a reference to an earlier `.classes` result does not update after `.classes.ensure` adds a new class.
- **Snapshot mutation does not affect the stack** — pushing or splicing the returned array does not change the object's actual stack.

### `.classes.ensure` (bare form)

- **Adds class when absent** — after `$w.obj.classes.ensure(Some_class)`, `$w.obj.isa?(Some_class)` is `true`.
- **New platter goes on top** — the newly added class appears at the front of `.obj.classes` (position 0 when no shadow, position 1 when a shadow exists).
- **Methods on the new platter win over existing same-named methods** — because the stack is walked top-to-bottom, `.ensure`'ing a class that defines `.foo` makes `.foo` on the receiver dispatch to the new class's version.
- **No-op when class already present** — after two successive `.ensure(Some_class)` calls, only one Some_class platter exists.
- **Exact-class match, not `.isa?`** — with `$hex = 0xff` (Hex extends Number), `$hex.obj.classes.ensure(Number)` adds a Number platter even though Hex is in the stack.
- **Bare form is permanent** — a class added by bare `.ensure` stays after the enclosing block/method exits.

### `.classes.ensure` (block form)

- **Class present for block duration** — inside `$w.obj.classes.ensure(Serializable) do ... end`, `$w.obj.isa?(Serializable)` is `true`.
- **Not present after block exit when added** — after the block exits (class was not there before), the added platter is gone.
- **Not removed after block exit when already present** — if Serializable was already in the stack before the block, it is still there after the block exits.
- **Cleanup runs on raise** — if the block raises, the platter added by this call is still removed.
- **Cleanup is identity-tracked** — if user code inside the block adds its own platter of the same class through a separate path, only the outer's added platter is removed on exit.
- **Nested block-forms compose** — an outer `ensure($cls)` block containing an inner `ensure($cls)` block leaves the object exactly as it started after both exit.
- **Block's return value is the block's return** — `$x = $w.obj.classes.ensure(Cls) do 42 end` sets `$x` to `42`.

### `.classes.add_unconditionally` (bare form)

- **Adds a platter carrying the class** — after `$w.obj.classes.add_unconditionally(Serializable)`, `$w.obj.classes` includes `Serializable`.
- **Duplicates when class already present** — calling `.add_unconditionally(Widget)` on an object whose stack already has Widget results in two Widget entries in `$w.obj.classes`.
- **Multiple calls add multiple platters** — calling `.add_unconditionally(Cls)` twice adds two platters, both carrying `Cls`.
- **New platter lands on top of stack** — a fresh `.add_unconditionally(Cls)` platter appears at the front of `.obj.classes` (position 0 when no shadow, position 1 when a shadow exists), same as `.ensure`.

### `.classes.add_unconditionally` (block form)

- **Platter present for block duration** — inside `$w.obj.classes.add_unconditionally(Cls) do ... end`, `$w.obj.classes` has a platter carrying `Cls`.
- **Platter removed at block exit** — after the block exits, the added platter is gone.
- **Cleanup runs on raise** — if the block raises, the added platter is still removed.
- **Cleanup is identity-tracked** — if user code inside the block adds its own platter through a separate call, only the outer's added platter is removed on exit.
- **Always adds regardless of existing membership** — even when `Cls` is already in the stack before the block, a new platter is still added for the block's duration and removed on exit.
- **Nested block-forms compose** — two nested `.add_unconditionally(Cls) do ... end` calls each add and remove their own platter; the stack ends both blocks exactly as it started.
- **Block's return value is the block's return** — `$x = $w.obj.classes.add_unconditionally(Cls) do 42 end` sets `$x` to `42`.

### `.classes.shadow`

- **Bare call returns null when no shadow exists** — a freshly constructed object with no singleton methods has `.obj.classes.shadow` equal to null.
- **Bare call returns the shadow class when it exists** — after `.classes.shadow(ensure: true)`, a subsequent bare `.classes.shadow` returns the shadow class.
- **`ensure: true` creates the shadow if missing** — the shadow platter exists after `.classes.shadow(ensure: true)` even though the object had none before.
- **`ensure: true` returns the shadow class** — always returns a class value, never null.
- **Defining a singleton method implicitly creates the shadow** — after `method $o.foo() ... end` on a bare object, `.classes.shadow` (bare form) returns a non-null class.

### `.methods`

- **Returns a methods object** — `$w.obj.methods` returns a value supporting `[:name]`, `.keys`, `.values`, `.each`.
- **`[:name]` returns a bound callable** — `$w.obj.methods[:greet]` returns a callable whose `.call` runs `$w.greet()` with `%self = $w`.
- **`[:missing]` returns null** — `$w.obj.methods[:no_such_method]` is null when no such method exists (or none visible from the call site).
- **Composes with caller** — `$w.obj.methods[:greet].caller.new` returns a caller for the bound method; setting params and invoking `.call` on it runs the method with those params and `%self = $w`.
- **Contains all visible methods via `.keys`** — `.keys` on `$w.obj.methods` for an instance of a class defining `.greet` and inheriting `.describe` from a parent returns an array containing both `'greet'` and `'describe'`.
- **`.keys` returns a fresh array** — two successive `.keys` calls return two distinct arrays.
- **`.keys` reflects current class state** — mutating the class between two `.keys` calls (adding, removing, or amending a method) can produce different arrays on the two calls.
- **Iteration is over a snapshot from `.keys`** — inside `.keys.each do ... end`, a method added to the class mid-loop does not retroactively appear in the current iteration.
- **Mutating writes raise** — `$w.obj.methods[:foo] = closure ... end` raises; the methods object is not mutable.
- **`.delete` raises** — mutating removal methods are not part of the surface.
- **All non-mutating hash methods work** — `.keys`, `.values`, `.each`, `.length`, and containment tests behave identically to their Hash counterparts.
- **Downloaded methods do not appear** — an ad-hoc `$w.$fn` application does not add `$fn` to `$w.obj.methods.keys`; the class is the source of truth.
- **Private methods hidden from outside** — `$w.obj.methods[:private_name]` from outside the class body returns null; the entry doesn't appear in `.keys` either.
- **Private methods visible from inside** — `%self.obj.methods` inside a method body surfaces private methods via `[:name]` and `.keys`.
- **Captured private-method callables do NOT retain access** — a callable captured via `$m = %self.obj.methods[:helper]` inside the class body and handed to outside code raises when the outside code invokes `$m.call`. Access is checked at each `.call` against the current frame's `%call.method_class`, not at capture.
- **Shadow methods included** — a singleton method defined via `method $w.foo() ... end` appears in `$w.obj.methods.keys` as `'foo'`.
- **Inherited methods included** — a method defined on a parent class of `$w`'s class appears in `$w.obj.methods.keys`.
- **Method-resolution winner is what's returned** — when both a class and a parent define the same-named method, `$w.obj.methods[:name]` returns the version that would dispatch under [method resolution](tag:method-resolution).
- **Nested namespaces appear as single entries** — `.keys` includes `'obj'` (and any other nested namespace name) but does NOT include nested members like `'truthy?'` or `'isa?'`.
- **Drilling into a namespace** — `$w.obj.methods[:obj].methods.keys` returns the nested `obj` namespace's own method names.
- **`.each` yields `(name, value)`** — `$w.obj.methods.each do ($name, $value) ... end` binds each pair to the block's two params.
- **`.each` with wrong param count raises** — a one-arg block passed to `.each` raises for incorrect param count; no auto-collapse into an array.
- **Jail limits methods to the jailed set** — `$foo.obj.jail(:bar, :gup) do ($jail); $jail.methods.keys ...` yields `['bar', 'gup']` regardless of what other methods `$foo` carries.
- **Jail methods hides non-jailed entries from lookup too** — `$jail.methods[:not_jailed]` returns null even if the underlying `$foo` has a `:not_jailed` method.
- **Lazy lookup does not materialize the full set** — `$w.obj.methods[:greet]` walks the class graph for `greet` alone; enumerating every method is not required and does not happen.

### `.warn`

- **Returns the receiver** — `$w.obj.warn('msg')` returns `$w`.
- **Never raises** — calling `.warn` with any string message does not raise.
- **Never propagates up the chain** — a `.warn` call in a called method does not affect the caller's control flow.
- **Adds a warning-only platter** — after `.warn('msg')`, the receiver's stack has an added platter carrying `warning` and no `class`.
- **Multiple warnings stack independently** — `$w.obj.warn('a').obj.warn('b')` results in two warning platters on the stack; both messages are recoverable via stack inspection.
- **Warnings don't affect dispatch** — a method call on the receiver after `.warn` resolves against the same class it would have without the warning.
- **Any role can call `.warn`** — code holding the object under a role other than the owner can call `.warn` without raising.

### `.stack`

- **User role can read the stack** — `.obj.stack` returns the stack array when called from user code.
- **Owning role can read the stack** — code running as the receiver's owning role can call `.stack`.
- **Non-owner non-user role raises** — a downloaded method running as a foreign role raises when calling `.stack` on a receiver it doesn't own.
- **Serialized shape preserved** — the returned platters carry the same `class`, `shadow`, `nested`, `warning`, `bucket`, and `vibecode` fields the object's stack has.
- **Returned array IS the live stack** — mutations to the returned array (push, splice, reverse, delete, direct field edits on a platter) modify the object's actual stack; subsequent method dispatch on the object reflects the changes.
- **Push affects dispatch** — appending a platter carrying a class that defines `.foo` via `$w.obj.stack.push(...)` makes `$w.foo` dispatch to that class's version on the next call.
- **Delete affects dispatch** — removing a platter that carried the class defining `.foo` makes `$w.foo` raise (or fall through to a lower-precedence class) on the next call.
- **Reorder affects dispatch precedence** — since the stack is walked top-to-bottom, mutating the order via `$w.obj.stack.reverse` (or any positional edit) reorders which same-named method wins.
- **Two `.stack` calls return the same array identity** — the returned reference is the object's stack; two successive `.stack` calls return arrays that compare identity-equal.

### `.stack.shadow`

- **Bare call returns null when no shadow exists** — same access rules apply as `.stack`.
- **Bare call returns the shadow platter when it exists** — the returned value is a platter hash with `shadow: true`.
- **`ensure: true` creates the shadow if missing** — the shadow platter exists after `.stack.shadow(ensure: true)`.
- **Non-owner non-user role raises** — same access restriction as `.stack`.

### `.classes.ensure` (access)

- **User role can call** — `$w.obj.classes.ensure($cls)` works when the current role is `user`.
- **Owning role can call** — code running as the receiver's owning role can call `.classes.ensure`.
- **Non-owner non-user role raises** — a downloaded method running as a foreign role raises when calling `.classes.ensure` on a receiver it doesn't own. Same rule for `.classes.add_unconditionally`.

### `.freeze_bucket`

- **Bare form is permanent** — after `.freeze_bucket`, top-level bucket writes still raise long after the calling scope exits.
- **Block form scopes to the block** — after a `.freeze_bucket do ... end` block exits, bucket writes succeed again.
- **Block form releases on raise** — if the block raises, subsequent bucket writes on the receiver still succeed (the freeze is released).
- **Blocks top-level bucket writes** — `$w.@name = 'x'` raises after `$w.obj.freeze_bucket`.
- **Blocks nested Hash writes (deep freeze)** — `$w.@config['theme'] = 'light'` raises when `$w.@config` is a Hash and the bucket has been frozen.
- **Blocks nested Array writes** — `$w.@items.push(4)` raises after the bucket has been frozen.
- **Reads still work** — `.freeze_bucket` doesn't block reads at any depth.
- **Does not freeze inner user-class objects** — if `$w.@inner` is a user-class instance, mutating that inner object's state via its own methods still works.
- **Does not affect the stack** — after `.freeze_bucket`, singleton method definitions and class-add operations still succeed.
- **Anyone holding the object can freeze it** — freeze follows holding-is-access.

### `.freeze_stack`

- **Bare form is permanent** — stack cannot be modified after `.freeze_stack`.
- **Block form scopes to the block** — after a `.freeze_stack do ... end` block exits, stack modifications succeed again.
- **Block form releases on raise** — same exception-safe release as `.freeze_bucket`.
- **Blocks singleton method definition** — `method $w.foo() ... end` raises after `.freeze_stack`.
- **Blocks class adds** — `.classes.ensure(Some_class)` raises after `.freeze_stack`.
- **Bucket writes still work** — `.freeze_stack` doesn't block bucket writes.

### `.freeze`

- **Bare form locks both axes permanently** — bucket and stack are both locked after `.freeze`.
- **Block form scopes both axes to the block** — after the block exits, both axes are writable again.
- **Block form releases on raise** — same release behavior as the single-axis freezes.
- **Equivalent to nested single-axis freezes** — behavior is the same as `.freeze_bucket` composed with `.freeze_stack`.

### `.destroy`

- **Calls `.close` when defined** — if the receiver's class provides a `.close` method, `.destroy` invokes it before clearing the bucket.
- **Skips `.close` when not defined** — an object with no `.close` still destroys cleanly.
- **Clears the bucket** — after `.destroy`, `%bucket` on the receiver is empty.
- **Clears the stack** — after `.destroy`, every platter is gone from the receiver's stack (class platters, shadow, warning platters, nested-link platters).
- **`.obj.id` still works post-destroy** — returns the same id the object had before destroy, even though the class stack is empty.
- **`.obj.destroyed?` returns `true` post-destroy**.
- **Other method calls raise post-destroy** — class-defined methods, other `.obj.X` methods, freeze operations, and downloaded methods all raise "destroyed object" on the destroyed receiver.
- **Bucket reads raise post-destroy** — `$foo.@field` on a destroyed object raises.
- **Singleton methods gone post-destroy** — a method defined via `method $foo.bar() ... end` no longer dispatches after `$foo.obj.destroy` (the shadow platter carrying it is gone).
- **`.close` raise does not stop destroy** — if `.close` raises during the destroy, the bucket AND stack are still cleared and the object is still destroyed.
- **Idempotent** — a second `.destroy` call is a no-op that returns cleanly.
- **Anyone holding can destroy** — follows holding-is-access; no role restriction.
- **Nested objects reachable only through this become collectible** — after destroy, an object that was reachable ONLY via the destroyed receiver's bucket or shadow closures has no roots into it via that path.

### `.destroyed?`

- **`false` before destroy** — a fresh instance returns `false`.
- **`true` after destroy** — `$foo.obj.destroy; $foo.obj.destroyed?` is `true`.
- **`true` after repeated destroys** — remains `true` after multiple `.destroy` calls.
- **Callable on a destroyed object** — `.obj.destroyed?` works even after destroy.
- **Return type is always Boolean** — `true` or `false`, never any other type.

## Related

- [Object](../) — the parent Object class doc.
- [syntax § truthy and falsy](https://puck.uno/requirements/syntax/truthy-and-falsy) — the language-level rule that `.truthy?` reports.
- [roles § object-access § Narrowing](https://puck.uno/requirements/roles/object-access#narrowing-pass-a-jail-not-the-raw-object) — how jail wrappers are used across role boundaries.
