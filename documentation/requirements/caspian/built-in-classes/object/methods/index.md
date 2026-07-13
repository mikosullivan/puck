# Object methods
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_object_methods",
	"role": "spec for the methods in the `object` method namespace — cross-cutting methods available on every Caspian value via `$foo.object.X`. Currently spec'd: `.truthy?` (returns the immutable truthy bit set at construction), `.isa?($class)` (class-hierarchy query), `.null?` and `.defined?` (paired predicates for the null-vs-not-null check; each is the opposite of the other), `.jail(...)` (constructs a narrowing wrapper that exposes only the named methods), `.tap` (Ruby-style chain-preserving side-effect helper — yields the receiver, runs the block, returns the receiver), `.classes` (returns an array of the receiver's stack classes, with `.ensure($class)` and `.shadow` sub-methods; `.ensure($class)` has a bare form (permanent add if missing) and a block form (temporary add-if-missing with identity-tracked cleanup at block exit); `.shadow` accepts `ensure: true` to create the shadow if missing), `.warn($message)` (attaches a warning-only platter to the receiver; never raises, never propagates up the chain — observational only), `.stack` (returns the receiver's stack array; user- and owner-only; carries a `.shadow` sub-method that returns the shadow platter, with the same `ensure: true` kwarg), and the freeze surface (`.freeze_bucket`, `.freeze_stack`, `.freeze` — each with permanent and block-scoped forms, denying writes to the named axis or both axes). Rule: shadows are never created by magic through a query — a bare `.shadow` call always returns whatever exists; `ensure: true` is the explicit opt-in for create-if-missing. Defining a singleton method (`method $foo.bar() ... end`) is the other explicit path that creates a shadow — the definition itself does the ensuring. More methods to be added as they're identified.",
	"status": "stub — starter methods spec'd (truthy?, isa?, null?, defined?, jail, tap, classes/ensure/shadow, warn, stack/shadow, freeze_bucket/freeze_stack/freeze); more to come",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

Methods in the `object` namespace apply to any value in Caspian. They inherit the [nested method namespace semantics](https://puck.uno/documentation/requirements/caspian/classes/nested): each is a normal method on the receiver with full instance access, dispatched through the dotted path `$foo.object.method`.

## Method surface

| Method | Description |
|---|---|
| `.truthy?` | Returns the immutable truthy value the receiver was constructed with, always as a boolean. |
| `.isa?($class)` | Returns whether the receiver is an instance of `$class` or any subclass of `$class`. |
| `.null?` | Returns whether the receiver is a `Null` instance. |
| `.defined?` | Returns the opposite of `.null?` — whether the receiver is not a `Null` instance. |
| `.jail($method_1, ...)` | Returns a separate helper object that forwards only the named methods to the receiver and blocks everything else. |
| `.tap` | Yields the receiver to a block, runs the block for its side effect, then returns the receiver unchanged so the chain continues. |
| `.classes` | Returns an array of the classes in the receiver's stack, freshly built per call and not mutable as an array; carries `.ensure($class)` (bare form permanent, block form temporary) and `.shadow` sub-methods that operate on the underlying stack. |
| `.warn($message)` | Attaches a warning to the receiver as a new platter carrying the given message. Observational only — never raises, never propagates up the chain. Returns the receiver. |
| `.stack` | Returns the receiver's stack array; restricted to user and the receiver's owning role; carries a `.shadow` sub-method that returns the shadow platter (with `ensure: true` to create). |
| `.freeze_bucket` | Locks the receiver's bucket against writes; permanent, or scoped to a block if one is passed. |
| `.freeze_stack` | Locks the receiver's stack against modification; permanent, or scoped to a block if one is passed. |
| `.freeze` | Locks both the bucket and the stack; permanent, or scoped to a block if one is passed. |

## Worked examples

### `.truthy?`

Returns the immutable truthy value the receiver was constructed with. Always a boolean (`true` or `false`). Equivalent to how the receiver evaluates in an `if` or `while` condition.

`False` and `Null` instances (and their subclasses) return `false`; every other value returns `true`. The bit is set by the class's constructor at instantiation and cannot be changed thereafter — no method, no bucket write, no downloaded-method application can flip it.

~~~caspian
5.object.truthy?          # true
''.object.truthy?         # true — empty string is truthy
[].object.truthy?         # true — empty array is truthy
false.object.truthy?      # false
null.object.truthy?       # false
~~~

The value follows the general [truthy/falsy rule](https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy): only `null` and `false` are falsy; everything else is truthy. `.truthy?` returns the same value the language uses when the receiver is evaluated as a condition.

### `.isa?($class)`

Class-hierarchy query. Returns `true` if the receiver is an instance of `$class` or any subclass of `$class`; returns `false` otherwise. The check is subclass-inclusive at every level of the inheritance chain — an instance of a class N steps deep in the hierarchy returns `true` for `.isa?` against any of its N ancestors.

~~~caspian
$hex = 0xff
$hex.object.isa?(Hex)         # true
$hex.object.isa?(Number)      # true — Hex extends Number
$hex.object.isa?(Object)      # true — every class extends Object
$hex.object.isa?(String)      # false

$flavored = null.with_flavor(:pending)
$flavored.object.isa?(Null)   # true — flavored nulls remain Null instances
~~~

### `.null?` / `.defined?`

Convenience predicates for the null-vs-not-null check, which is common enough in real code to earn its own short names. Both are strictly booleans.

- `.null?` returns `true` if the receiver is a Null instance (including any subclass of Null — flavored nulls satisfy the check). Equivalent to `.isa?(Null)`.
- `.defined?` returns the opposite — `true` if the receiver is not a Null instance. Equivalent to `not .isa?(Null)`.

`.defined?` reads better than `not .null?` when the surrounding phrasing is affirmative (`if $x.object.defined? ...` vs `if not $x.object.null? ...`), which is the reason for pairing both.

~~~caspian
null.object.null?             # true
null.with_flavor(:pending).object.null?   # true — flavored nulls are still Null
false.object.null?            # false — false is not null
0.object.null?                # false
''.object.null?               # false
[].object.null?               # false

null.object.defined?          # false
'hello'.object.defined?       # true
0.object.defined?             # true
false.object.defined?         # true — false is a defined value, just falsy
~~~

Note the distinction from `.truthy?`: `false.object.truthy?` is `false`, but `false.object.null?` is also `false` — a defined-but-falsy value is not null. The three predicates answer three different questions:

- `.truthy?` — how does this evaluate in a condition?
- `.null?` — is this specifically a Null instance?
- `.defined?` — is this anything OTHER than a Null instance?

### `.jail(...)`

Constructs a **jail** — a separate helper object that holds a private reference to the receiver (the *prisoner*) and exposes ONLY the named methods, forwarding calls to those methods through to the prisoner. Every other method dispatch through the jail raises.

The jail is not the prisoner: it has its own class, its own identity, and no access to the prisoner's internals — no bucket reads, no methods outside the exposed list, no way to hand out the prisoner. Used to narrow what a role hands across a boundary; see [object-access § Narrowing: pass a jail, not the raw object](https://puck.uno/documentation/requirements/caspian/roles/object-access#narrowing-pass-a-jail-not-the-raw-object).

~~~caspian
$widget = Widget.new(name: 'primary', internal_state: 'sekrit')
$narrowed = $widget.object.jail(:name, :label)

$narrowed.name              # forwards to $widget.name — works
$narrowed.label             # forwards to $widget.label — works
$narrowed.internal_state    # raises — the jail doesn't expose this method
~~~

The jail is a **separate object**, not `$widget` in disguise. It holds a private reference to the prisoner and mediates calls; nothing in the jail's implementation can read the prisoner's bucket, invoke methods outside the exposed list, or hand the prisoner reference back out. Callers holding the jail have no path to the prisoner's internals.

Because the jail is its own object:

- **It has its own `.object.X` surface.** `$narrowed.object.truthy?` returns `true` (the jail is a truthy value, being neither `false` nor `null`); `$narrowed.object.isa?(Jail)` returns true; `$narrowed.object.isa?(Widget)` returns false. None of these queries reveal anything about the prisoner.
- **`.object.jail(...)` on the jail doesn't re-open access to the prisoner.** Calling `$narrowed.object.jail(:foo)` returns a new jail wrapping THE JAIL, not the prisoner. Method names in that new jail resolve against the jail's own surface, not `$widget`'s.
- **The jail has no way to re-expose the prisoner.** There is no `.unjail`, no `.prisoner`, no reflection method that returns the wrapped object. Handing across a jail is one-way narrowing.

Common pattern: user code holding a private-state-bearing instance passes only the safe surface to untrusted code:

~~~caspian
%chain.puck.grant do
	$library.render($widget.object.jail(:name, :label, :bounding_box))
end
~~~

The library sees a value that responds to the three named methods and fails hard for anything else. It cannot read `$widget`'s bucket, call `$widget`'s other methods, or hand the underlying widget to a third party — the jail doesn't give it any of those.

### `.tap`

Yields the receiver to a block, runs the block for its side effect, then returns the receiver so the chain continues. Useful for slotting a logging call, an assertion, a debug print, or any other side-effecting step into the middle of a chained expression without breaking the chain and without introducing a throwaway variable.

The block receives the **underlying value** — the same value the chain will continue on — not the `.object` helper. `.object.tap` itself returns that underlying value, so a method call after `.tap`'s block resolves against the receiver, not against the helper.

~~~caspian
$result = build_widget()
	.object.tap do ($w)
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
5.object.tap do ($n)
	$n * 100        # ignored
end                  # returns 5, not 500
~~~

### `.classes` / `.classes.ensure($class)` / `.classes.shadow`

**`.classes`** returns an array of the classes currently in the receiver's stack, in stack order (top to bottom). Two properties matter:

- **Freshly built per call.** Successive calls produce independent arrays; a reference held to a prior result is a snapshot of that moment, not a live view of the stack.
- **Not mutable as an array.** Pushing or splicing the returned array does nothing to the source object; the stack is the source of truth. The array itself is a plain read-only snapshot of class identities. The methods below operate on the stack, not on the returned array — the array just carries them as an ergonomic launch pad.

**`.classes.ensure($class)`** guarantees at least one platter in the stack carries `$class` exactly. Two forms:

- **Bare call** — permanent. If the class is already in the stack, no-op. If not, a new platter with the class is inserted at the **bottom** of the stack and stays there.
- **Block call** — the class is present for the block's duration. Behavior at call time depends on whether the class was already in the stack:
  - **Already present** — nothing is added; the block runs; **nothing is removed at block exit.** The stack ends the block exactly as it started. The engine only removes what it added, and it added nothing.
  - **Not present** — a new platter is added at the bottom, the block runs, and that specific platter is removed at block exit (or if the block raises).

Subclasses in the stack do **not** count as "the class is there." The check is **exact-class match**, not `.isa?`. If the stack has `Hex` and you call `.classes.ensure(Number)`, a new `Number` platter is still added — even though `Hex` extends `Number`. Class-hierarchy queries (`.isa?`) walk inheritance; stack membership (`.classes`) is class-identity equality only.

~~~caspian
$widget = Widget.new()
$widget.object.classes                          # e.g. [Widget]

# Bare form:
$widget.object.classes.ensure(Serializable)     # adds Serializable at bottom
$widget.object.classes                          # [Widget, Serializable]

$widget.object.classes.ensure(Widget)           # no-op, already present
$widget.object.classes.ensure(Serializable)     # no-op, already present

# Block form — temporary if needed:
$widget.object.classes.ensure(Renderer) do
	# Renderer is in $widget's stack for the block's duration
	$widget.render()
end
# Renderer platter removed on block exit; $widget's stack is back to what it was

# Subclass caveat:
$hex = 0xff                                     # Hex instance; stack has Hex
$hex.object.classes.ensure(Number)              # adds Number at bottom, even though Hex extends Number
$hex.object.classes                             # [Hex, Number]
~~~

**Cleanup is identity-tracked, not class-name-tracked.** The engine remembers the specific platter it created for a block-form `.ensure` call and removes exactly that platter at block exit. It doesn't scan the stack for "any platter carrying this class" and remove the first match — user code inside the block might have added its own platter with the same class through a different path, and that platter must be left alone.

Two consequences worth naming:

- **Nested calls compose cleanly.** An outer block-`.ensure($class) do ... end` can contain an inner bare-`.ensure($class)`. The inner sees the class present (added by the outer) and is a no-op; when the outer exits, it removes exactly its own platter. The pattern is valid.
- **Concurrent structural writes are safe.** If the block does something like `$widget.object.classes.ensure($other_class)` or any other stack modification, those platters aren't candidates for the outer's cleanup — the outer only removes its own.

The block form's return value is the block's value (matching Ruby-style use-block semantics):

~~~caspian
$xml = $widget.object.classes.ensure(XmlSerializer) do
	return $widget.to_xml()
end
# $xml holds whatever the block returned; the XmlSerializer platter is already gone
~~~

Removing the ensured platter explicitly from inside the block (e.g. via a hypothetical `.classes.remove(...)`) breaks the outer's cleanup contract; that case raises when the outer tries to remove its now-missing platter.

**`.classes.shadow`** returns the shadow platter's class (the per-instance class populated with singleton methods), or `null` if the object has no shadow platter yet. This is a **query only** — calling it doesn't create a shadow.

Pass `ensure: true` to get the shadow class AND create the shadow if it doesn't already exist:

~~~caspian
$widget = Widget.new()
$widget.object.classes.shadow                  # null — no shadow yet
$widget.object.classes.shadow(ensure: true)    # creates the shadow, returns the shadow class

# Once the shadow exists, either form returns the class:
$widget.object.classes.shadow                  # the shadow class
~~~

The `ensure:` kwarg matches the pattern used by `.classes.ensure($class)`: whenever an `object`-namespace method might need to create structure that wasn't there, `ensure: true` is the switch that opts in. Shadows never appear by magic through a query — a bare `.shadow` call always returns whatever exists.

**One implicit path creates the shadow too:** defining a singleton method on the object. `method $foo.bar() ... end` is an explicit "I want a method on this specific object" — the shadow has to exist to hold the method, so the engine creates it as part of processing the definition. Callers who define singleton methods don't need to call `.shadow(ensure: true)` first; the definition itself does the ensuring.

~~~caspian
$widget = Widget.new()
$widget.object.classes.shadow      # null — no shadow yet

method $widget.greet()
	puts 'hi'
end

$widget.object.classes.shadow      # the shadow class — implicitly created by the definition
~~~

Whether a `.classes.add($class)` companion exists — one that always pushes a new platter regardless of existing membership — is still open. Every current use case is covered by `.ensure`; the always-push variant is deferred until a concrete need surfaces.

### `.warn($message)`

Attaches a warning to the receiver by pushing a new **warning-only platter** onto the stack. The platter carries `warning: <the created warning object>` — a Warning-class instance wrapping `$message`. The warning-platter form is spec'd in [object/structure § warning](../../structure/#warning).

**Never raises.** `.warn` is purely observational — nothing about control flow changes. The receiver keeps running as it was; the warning just sits attached to it for whoever cares to inspect the stack later.

**Never propagates up the chain.** The warning is local to the receiver. Callers, the current frame, the enclosing chain, and any handler up the stack are unaffected — no notification, no unwind, no propagation of any kind. If you want the caller to know something is off, use an explicit return value, an event, or a raised error; `.warn` is not that.

Returns the receiver, so it chains cleanly:

~~~caspian
$parsed_date.object.warn('parsed leniently; source string was ambiguous')
             .object.warn('century inferred from context')
~~~

Both warnings land as separate warning-only platters on `$parsed_date`. The stack after the two calls has two warning platters; neither affects dispatch (no `class` field) and both travel with the value as it's passed, stored, or serialized.

Typical use cases:

- A parser that accepted a value with a caveat: "century inferred," "trailing whitespace dropped," "encoding fell back to UTF-8."
- A validator that noticed something suspicious but didn't want to reject: "this user record's timezone is unusual for their region."
- An engine-internal signal about a stored value whose class disagrees with its declared schema at deserialization time.

Any code — engine, library, or application — can call `.warn`. Inspecting warnings is done by walking the stack (via `.object.stack` if the caller has access) and reading the `warning` field of each warning-carrying platter; the concrete inspection API is spec'd elsewhere as it grows.

**Access follows holding-is-access.** Any role holding the receiver can call `.warn`. Warnings don't grant privileges — they just add observational metadata — so no restriction is warranted. Untrusted code that annotates an object it holds is fine; the annotation travels with the object but doesn't do anything on its own.

### `.stack`

Returns the receiver's stack array — the ordered sequence of platters described in [object/structure § Stack](../../structure/#stack). The full serialized shape is available: each platter's `class`, `shadow` flag, `nested` UUID link, `warning`, per-platter `bucket`, and per-platter `vibecode` all show through.

**Access is restricted.** Only two roles can call `.stack`:

- **`user`** — the program author, who has ambient inspection authority over every value in the runtime.
- **The receiver's owning role** — the role that constructed the object.

Every other role gets a raised error on the call. This is a departure from the general holding-is-access rule; class-defined dispatch still follows holding-is-access, but `.stack` is gated because reading it exposes every object nested inside — each nested object could carry credentials, tokens, or other state its owner would not want handed to arbitrary callers.

~~~caspian
# From user code:
$widget.object.stack        # works — user is user

# From a downloaded method, applied while running as the puck faucet role:
function &introspect()
	return %self.object.stack
end

$widget.$introspect         # raises — the current role is not user and not
                            # $widget's owner
~~~

**Why the restriction is tight, not just gated by holding.** Nested objects live inside the stack (via `nested: <UUID>` platters linked to bucket entries). Handing out the stack effectively hands out every object nested at any depth. Even if the top-level receiver was passed across a role boundary deliberately, the caller almost certainly didn't intend to hand out its constituent state. The safe default is to only let user and the owner see the full shape.

If a class wants to expose limited structural information across role boundaries, it can define its own methods that return the specific pieces it considers safe (`.class_list`, `.has_warnings?`, etc.). `.stack` itself stays gated.

**This may be revisited.** If the community identifies patterns where a broader access rule would be safe and useful, the restriction can loosen. For now the conservative rule holds — closed by default, open on request.

#### `.stack.shadow`

Returns the shadow **platter** if one exists (or `null` if the object has no shadow yet). Same access rule as `.stack` — user and the receiver's owning role only.

Where `.classes.shadow` returns the shadow's class object, `.stack.shadow` returns the whole shadow platter — the platter hash that carries `shadow: true`, its `class` field, and any `bucket` / `vibecode` fields the shadow platter happens to have.

Bare call is **query only** — never creates a shadow. Pass `ensure: true` to get the shadow platter AND create it if needed, matching the pattern used by `.classes.shadow(ensure: true)` and `.classes.ensure($class)`:

~~~caspian
$widget.object.stack.shadow                  # null — no shadow yet
$widget.object.stack.shadow(ensure: true)    # creates the shadow, returns the platter

# Once the shadow exists:
$widget.object.stack.shadow                  # the shadow platter hash
~~~

### `.freeze_bucket` / `.freeze_stack` / `.freeze`

Caspian splits object immutability into two independent axes — the bucket and the stack — plus a shortcut that locks both at once. Every freeze method has two forms:

- **Bare call** — locks the axis (or axes) **permanently**. There is no `unfreeze`; once the axis is frozen it stays frozen for the lifetime of the object.
- **Block call** — locks the axis for the block's duration and releases when the block exits. Exception-safe: the release runs even if the block raises.

What each method locks:

| Method | Bucket | Stack |
|---|---|---|
| `.freeze_bucket` | locked | (unchanged) |
| `.freeze_stack` | (unchanged) | locked |
| `.freeze` | locked | locked |

**Bucket freeze** — a **deep freeze** on the receiver's bucket. The bucket hash itself becomes read-only, and so does every Hash and Array reachable through it at any depth. Writes via `@field = ...`, `%bucket['key'] = ...`, or a nested write like `@config['theme'] = 'light'` or `@config.items.push(x)` all raise. Reads still work.

**Objects stored in the bucket keep their own methods and mutability.** If a bucket entry is a user-class instance (a `Widget`, a `Session`, anything with its own class), that inner object's methods still work and can still mutate its own state. Bucket freeze deep-freezes reachable Hashes and Arrays; it does not freeze the inner objects those references point to.

~~~caspian
$widget.@config = {theme: 'dark', items: [1, 2, 3]}
$widget.@inner = Widget.new(name: 'nested')

$widget.object.freeze_bucket

$widget.@config = {}                # raises — top-level bucket write
$widget.@config['theme'] = 'light'  # raises — nested Hash, deep-frozen
$widget.@config.items.push(4)       # raises — nested Array, deep-frozen

$widget.@inner.rename('renamed')    # works — the inner Widget has its own state
                                    # and its own methods; the outer freeze doesn't
                                    # touch it. If you want the inner widget frozen
                                    # too, freeze it separately.
~~~

Freeze depth applies specifically to structural primitives (Hash, Array) because they're the shapes whose "contents" ARE their state. Objects with their own classes get to decide their own mutation rules through their own methods.

**Stack freeze** — no platter can be added, removed, or reordered. `object.method` (defining a singleton method, which would grow the shadow) is blocked; adding a class via `%foo.object.classes.add ...` (when that surface is spec'd) is blocked; nothing about the stack shape can change. The methods the object has at freeze time are the methods it will always have.

**`.freeze` locks both.** Equivalent to calling `.freeze_bucket` and `.freeze_stack` in sequence, or nesting the two block forms.

~~~caspian
# Permanent freeze on the bucket only:
$config.object.freeze_bucket

# Temporary freeze during an untrusted call:
$widget.object.freeze do
	$library.render($widget)  # $widget's bucket and stack are both locked here
end
# Both axes are writable again after the block exits.

# Nested block forms compose:
$widget.object.freeze_stack do
	$widget.object.freeze_bucket do
		# Both locked here (stack first, then bucket)
	end
	# Only stack locked here
end
# Both writable again
~~~

**Any holder can call.** Freezing follows the general holding-is-access rule — anyone with a reference to the object can freeze any of its axes. Freezing denies future writes; it doesn't grant any capability the caller didn't already have.

This does mean untrusted code that holds an object can freeze it out from under the owner. Callers who don't want that surface reachable pass a [jail](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/methods/#jail) that doesn't expose the freeze methods rather than the raw object.

## Testing

### `.truthy?`

- **Returns `true` for a truthy value** — `5.object.truthy?` is `true`.
- **Returns `false` for `false`** — `false.object.truthy?` is `false`.
- **Returns `false` for `null`** — `null.object.truthy?` is `false`.
- **Empty string is truthy** — `''.object.truthy?` is `true`.
- **Empty array is truthy** — `[].object.truthy?` is `true`.
- **Empty hash is truthy** — `{}.object.truthy?` is `true`.
- **Zero is truthy** — `0.object.truthy?` is `true`.
- **Return type is always Boolean** — `.object.truthy?` on any value returns `true` or `false`, never any other type.
- **Truthy bit is immutable** — after `$w = Widget.new()`, no bucket write, no class add, no downloaded-method application on `$w` changes `$w.object.truthy?`.
- **Subclass of Null inherits falsy** — an instance of a class extending Null reports `.object.truthy?` as `false`.
- **Subclass of False inherits falsy** — same for a subclass of False.

### `.isa?`

- **Direct class match returns `true`** — `5.object.isa?(Number)` is `true`.
- **Ancestor class match returns `true`** — an instance of a subclass of Number reports `.object.isa?(Number)` as `true`.
- **Object is always in the chain** — for any value, `.object.isa?(Object)` is `true`.
- **Non-ancestor class returns `false`** — `5.object.isa?(String)` is `false`.
- **Flavored null remains a Null instance** — `null.with_flavor(:pending).object.isa?(Null)` is `true`.
- **Return type is always Boolean** — `.object.isa?($cls)` on any value returns `true` or `false`.

### `.null?` and `.defined?`

- **`null.object.null?`** is `true`.
- **`null.with_flavor(:pending).object.null?`** is `true` — flavored nulls are still Null instances.
- **`false.object.null?`** is `false`.
- **`0.object.null?`** is `false`.
- **`''.object.null?`** is `false`.
- **`[].object.null?`** is `false`.
- **`null.object.defined?`** is `false`.
- **`'hello'.object.defined?`** is `true`.
- **`0.object.defined?`** is `true`.
- **`false.object.defined?`** is `true` — false is defined but falsy.
- **`.null?` and `.defined?` are always opposites** — for any value, `.object.null?` and `.object.defined?` return different booleans.
- **Return type is always Boolean** — both methods return `true` or `false`, never any other type.

### `.jail`

- **Named methods forward to prisoner** — `$w = Widget.new(name: 'x'); $w.object.jail(:name).name` is `'x'`.
- **Unlisted methods raise** — calling a method NOT in the jail's exposure list raises.
- **Jail has its own class identity** — `$narrowed.object.isa?(Jail)` is `true`.
- **Jail is not the prisoner's class** — `$w.object.jail(:name).object.isa?(Widget)` is `false`.
- **Jail is truthy** — `$w.object.jail(:name).object.truthy?` is `true`.
- **No `.unjail` method exists on the jail** — calling `.unjail` on the jail raises.
- **No `.prisoner` method exists on the jail** — calling `.prisoner` on the jail raises.
- **Re-jailing the jail wraps the jail, not the prisoner** — `$jail.object.jail(:name)` produces a jail whose named-method resolution runs against the outer jail's own surface, not against the original prisoner.
- **Bucket reads on jail don't reach prisoner** — attempts to read `%bucket` fields from inside the jail do not return prisoner state.
- **Jail exposes only the exact methods listed** — passing `:name` and `:label` exposes those two and no others, even if the prisoner has closely-named methods.

### `.tap`

- **Returns the receiver** — `5.object.tap { }` is `5`.
- **Block receives the receiver** — inside `5.object.tap do ($n) ... end`, `$n` is `5`.
- **Block return value is ignored** — `5.object.tap { $n * 100 }` is `5`, not `500`.
- **Side effects run** — a `.tap` block that mutates a captured variable observes the mutation afterward.
- **Chain continues after `.tap`** — `[1, 2].object.tap { }.length` is `2`.
- **Works on falsy values** — `false.object.tap { }` returns `false`; `null.object.tap { }` returns null.
- **Block runs exactly once** — a counter incremented inside a `.tap` block increases by 1 per `.tap` call, not zero or more.

### `.classes`

- **Returns the stack classes in order** — for `$w = Widget.new()`, `$w.object.classes` returns an array beginning with Widget.
- **Freshly built per call** — two successive calls to `.object.classes` return distinct arrays (not the same identity).
- **Prior snapshot not affected by later stack changes** — a reference to an earlier `.classes` result does not update after `.classes.ensure` adds a new class.
- **Snapshot mutation does not affect the stack** — pushing or splicing the returned array does not change the object's actual stack.

### `.classes.ensure` (bare form)

- **Adds class when absent** — after `$w.object.classes.ensure(Some_class)`, `$w.object.isa?(Some_class)` is `true`.
- **New platter goes at the bottom** — the newly added class appears at the end of `.object.classes`.
- **No-op when class already present** — after two successive `.ensure(Some_class)` calls, only one Some_class platter exists.
- **Exact-class match, not `.isa?`** — with `$hex = 0xff` (Hex extends Number), `$hex.object.classes.ensure(Number)` adds a Number platter even though Hex is in the stack.
- **Bare form is permanent** — a class added by bare `.ensure` stays after the enclosing block/method exits.

### `.classes.ensure` (block form)

- **Class present for block duration** — inside `$w.object.classes.ensure(Serializable) do ... end`, `$w.object.isa?(Serializable)` is `true`.
- **Not present after block exit when added** — after the block exits (class was not there before), the added platter is gone.
- **Not removed after block exit when already present** — if Serializable was already in the stack before the block, it is still there after the block exits.
- **Cleanup runs on raise** — if the block raises, the platter added by this call is still removed.
- **Cleanup is identity-tracked** — if user code inside the block adds its own platter of the same class through a separate path, only the outer's added platter is removed on exit.
- **Nested block-forms compose** — an outer `ensure($cls)` block containing an inner `ensure($cls)` block leaves the object exactly as it started after both exit.
- **Block's return value is the block's return** — `$x = $w.object.classes.ensure(Cls) do 42 end` sets `$x` to `42`.

### `.classes.shadow`

- **Bare call returns null when no shadow exists** — a freshly constructed object with no singleton methods has `.object.classes.shadow` equal to null.
- **Bare call returns the shadow class when it exists** — after `.classes.shadow(ensure: true)`, a subsequent bare `.classes.shadow` returns the shadow class.
- **`ensure: true` creates the shadow if missing** — the shadow platter exists after `.classes.shadow(ensure: true)` even though the object had none before.
- **`ensure: true` returns the shadow class** — always returns a class value, never null.
- **Defining a singleton method implicitly creates the shadow** — after `method $o.foo() ... end` on a bare object, `.classes.shadow` (bare form) returns a non-null class.

### `.warn`

- **Returns the receiver** — `$w.object.warn('msg')` returns `$w`.
- **Never raises** — calling `.warn` with any string message does not raise.
- **Never propagates up the chain** — a `.warn` call in a called method does not affect the caller's control flow.
- **Adds a warning-only platter** — after `.warn('msg')`, the receiver's stack has an added platter carrying `warning` and no `class`.
- **Multiple warnings stack independently** — `$w.object.warn('a').object.warn('b')` results in two warning platters on the stack; both messages are recoverable via stack inspection.
- **Warnings don't affect dispatch** — a method call on the receiver after `.warn` resolves against the same class it would have without the warning.
- **Any role can call `.warn`** — code holding the object under a role other than the owner can call `.warn` without raising.

### `.stack`

- **User role can read the stack** — `.object.stack` returns the stack array when called from user code.
- **Owning role can read the stack** — code running as the receiver's owning role can call `.stack`.
- **Non-owner non-user role raises** — a downloaded method running as a foreign role raises when calling `.stack` on a receiver it doesn't own.
- **Returned array is not the live stack** — mutating the returned array doesn't modify the object's actual stack.
- **Serialized shape preserved** — the returned platters carry the same `class`, `shadow`, `nested`, `warning`, `bucket`, and `vibecode` fields the object's stack has.

### `.stack.shadow`

- **Bare call returns null when no shadow exists** — same access rules apply as `.stack`.
- **Bare call returns the shadow platter when it exists** — the returned value is a platter hash with `shadow: true`.
- **`ensure: true` creates the shadow if missing** — the shadow platter exists after `.stack.shadow(ensure: true)`.
- **Non-owner non-user role raises** — same access restriction as `.stack`.

### `.freeze_bucket`

- **Bare form is permanent** — after `.freeze_bucket`, top-level bucket writes still raise long after the calling scope exits.
- **Block form scopes to the block** — after a `.freeze_bucket do ... end` block exits, bucket writes succeed again.
- **Block form releases on raise** — if the block raises, subsequent bucket writes on the receiver still succeed (the freeze is released).
- **Blocks top-level bucket writes** — `$w.@name = 'x'` raises after `$w.object.freeze_bucket`.
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

## Related

- [Object](../) — the parent Object class doc.
- [syntax § truthy and falsy](https://puck.uno/documentation/requirements/caspian/syntax/truthy-and-falsy) — the language-level rule that `.truthy?` reports.
- [roles § object-access § Narrowing](https://puck.uno/documentation/requirements/caspian/roles/object-access#narrowing-pass-a-jail-not-the-raw-object) — how jail wrappers are used across role boundaries.
