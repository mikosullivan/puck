# Method resolution

<span class="tag">method-resolution</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_classes_method_resolution",
	"role": "spec for how Caspian resolves a method call at runtime. Two distinct mechanisms: (1) instance dispatch walks the stack stack top-to-bottom, and for each class-carrying stack walks that class's inheritance graph depth-first with a per-dispatch seen-set; (2) super() is class-level — it walks the current class's inherits array (the classes named in the defining class's `inherits` clause), using the class of the defining method as context, not the object. Search happens fresh on every call — no cache, no pre-linearization. Classes and objects are mutable in V1, so a resolution cache would need invalidation logic that's more costly than the walk it replaces.",
	"status": "spec — runtime graph search and super() semantics settled; no-cache decision locked",
	"audience": "engine implementers building the dispatcher; developers reasoning about MI and super()",
	"related": []
}}
~~~

Caspian resolves a method call by **searching the class graph at call time.** There is no pre-computed dispatch table, no linearization pass, and no cache. Every call walks the graph fresh. See [§ No cache](#no-cache) for the rationale.

Two mechanisms cooperate:

- **Instance dispatch** — the normal `$obj.method()` case. Walks the stack stack, and inside each class-carrying stack, walks the class's inheritance graph.
- **`super()`** — invoked from inside a method body. A class-level lookup that walks the defining class's inherits array. Ignores the stack stack.

Both are spec'd below.

## Instance dispatch

The stack stack, and the "top is index 0, dispatch walks top-to-bottom" ordering, are spec'd on [object structure § Stack](https://puck.uno/requirements/built-in-classes/object/structure/#stack). This page adds the rule for what happens inside each stack.

**The algorithm:**

1. Start at the top stack (index 0).
2. If the stack carries no `class` (warning-only, nested-link, standalone-vibecode), skip it.
3. Otherwise, search that class's inheritance graph depth-first:
	- Check the class itself for the method name.
	- If not found, walk into each class in the `inherits` array, in declaration order.
	- Recurse the same rule on each parent.
4. If nothing matches, move to the next stack down and repeat.
5. If the bottom of the stack is reached with no match, raise method-not-found.

**Seen-set.** During a single dispatch, a class visited once is not visited again. This handles diamond inheritance and any accidental cycles without special-casing either.

## Multiple inheritance

A class may name any number of parents in its `inherits` clause. The declaration order matters — earlier parents are searched before later ones.

~~~caspian
class # device
	method &describe()
		return 'a device'
	end
end

class # camera
	inherits device

	method &capture()
		return 'photo taken'
	end
end

class # phone
	inherits device

	method &call($number)
		return 'calling ' + $number
	end
end

class # camera_phone
	inherits camera, phone

	method &share()
		return 'shared'
	end
end
~~~

For `$cp.describe()`:

1. `camera_phone` doesn't have `describe`.
2. Enter first parent `camera`. Not there.
3. Enter `camera`'s parent `device`. **Found.** Dispatch.

For `$cp.call('555-1234')`:

1. `camera_phone` doesn't have `call`.
2. Enter `camera`. Not there.
3. Enter `device`. Not there.
4. Back up to `camera_phone`. Enter second parent `phone`. **Found.** Dispatch.

For `$cp.capture()`: found on `camera` at step 2.

## Diamond inheritance

The seen-set from [§ Instance dispatch](#instance-dispatch) handles diamonds automatically. In the example above, `device` is an ancestor of both `camera` and `phone`. When the walk of `camera`'s chain visits `device`, `device` is marked seen. If the walk later enters `phone`'s chain and would revisit `device`, it's skipped.

<div>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 250" width="460" role="img" aria-label="Diamond inheritance: camera_phone inherits camera and phone, both of which inherit device. Search order for describe(): camera_phone, camera, device (found).">
	<title>Diamond inheritance and depth-first search</title>
	<g font-family="sans-serif" font-size="13" stroke="currentColor" fill="currentColor" stroke-width="1.2">
		<text x="115" y="16" text-anchor="middle" font-weight="bold" stroke="none">Inheritance</text>
		<rect x="75" y="30" width="80" height="36" rx="6" fill="rgba(255, 183, 77, 0.25)"/>
		<text x="115" y="53" text-anchor="middle" stroke="none">device</text>
		<rect x="25" y="110" width="80" height="36" rx="6" fill="rgba(255, 183, 77, 0.25)"/>
		<text x="65" y="133" text-anchor="middle" stroke="none">camera</text>
		<rect x="135" y="110" width="80" height="36" rx="6" fill="rgba(255, 183, 77, 0.25)"/>
		<text x="175" y="133" text-anchor="middle" stroke="none">phone</text>
		<rect x="60" y="190" width="110" height="36" rx="6" fill="rgba(255, 183, 77, 0.25)"/>
		<text x="115" y="213" text-anchor="middle" stroke="none">camera_phone</text>
		<line x1="85" y1="190" x2="70" y2="146" fill="none"/>
		<line x1="145" y1="190" x2="170" y2="146" fill="none"/>
		<line x1="80" y1="110" x2="105" y2="66" fill="none"/>
		<line x1="160" y1="110" x2="125" y2="66" fill="none"/>
	</g>
	<g font-family="sans-serif" font-size="13" stroke="currentColor" fill="currentColor" stroke-width="1.2">
		<text x="340" y="16" text-anchor="middle" font-weight="bold" stroke="none">Search order</text>
		<text x="340" y="32" text-anchor="middle" font-size="11" stroke="none" opacity="0.7">for describe()</text>
		<text x="264" y="65" font-size="11" stroke="none" opacity="0.7">1</text>
		<rect x="280" y="50" width="120" height="30" rx="4" fill="rgba(129, 212, 250, 0.25)"/>
		<text x="340" y="70" text-anchor="middle" stroke="none">camera_phone</text>
		<text x="264" y="105" font-size="11" stroke="none" opacity="0.7">2</text>
		<rect x="280" y="90" width="120" height="30" rx="4" fill="rgba(129, 212, 250, 0.25)"/>
		<text x="340" y="110" text-anchor="middle" stroke="none">camera</text>
		<text x="264" y="145" font-size="11" stroke="none" opacity="0.7">3</text>
		<rect x="280" y="130" width="120" height="30" rx="4" fill="rgba(129, 212, 250, 0.25)"/>
		<text x="340" y="150" text-anchor="middle" stroke="none">device ✓</text>
		<text x="264" y="185" font-size="11" stroke="none" opacity="0.7">—</text>
		<rect x="280" y="170" width="120" height="30" rx="4" fill="rgba(129, 212, 250, 0.25)" opacity="0.4"/>
		<text x="340" y="190" text-anchor="middle" stroke="none" opacity="0.5">phone (skipped: found)</text>
	</g>
</svg>
</div>

Consequences worth calling out:

- **The first-declared parent's chain wins the "position" of shared ancestors.** In the example, `device` is reached through `camera` because `camera` is declared first. If `camera_phone` were declared `inherits phone, camera`, then `device` would be reached through `phone`'s chain — `phone` is searched, then `device`.
- **Methods on shared ancestors resolve consistently.** Any method on `device` resolves to `device`'s version, regardless of which path reaches it. There's no "which `device`" ambiguity.
- **Shadow overrides work naturally.** If `camera` overrides `describe` and `phone` doesn't, `$cp.describe()` finds `camera`'s version early in the walk — before ever reaching `device`.

## super()

`super()` is a **class-level** lookup, entirely separate from the stack stack.

Every class carries an **inherits array** — the classes named in its `inherits` clause when the class was defined. Plain declaration-order list; not a stack, not a stack.

When a method body invokes `super()`:

- The "current class" is the class that **defined the method being executed** — not `%self`'s class, not the top of the stack stack.
- `super()` walks the current class's inherits array top-to-bottom, looking for the same method name.
- Each parent is searched depth-first through its own inherits array, same shape as instance dispatch.
- The first match is called.

The class-not-object framing matters: `super()` doesn't care what instance `%self` is. The lookup starts from the class of the defining method and consults that class's declared parents.

~~~caspian
class # camera
	inherits device

	method &describe()
		return 'a camera — specifically ' + super()
	end
end
~~~

Inside `camera.describe`, `super()` looks in `camera`'s inherits array (`[device]`), finds `describe` on `device`, and calls it. Whether `%self` is a `camera` or a `camera_phone` doesn't change the lookup.

**Diamond consequence.** In the camera_phone example, if `camera_phone` defines its own `describe` that calls `super()`, the lookup consults `camera_phone`'s inherits array (`[camera, phone]`), searches `camera` first, then `phone`. It does not fall through to `device` next just because `device` follows `phone` in some flattened order — `super()` sees `camera_phone`'s declared parents and only that.

**Empty inherits array.** A class with no declared parents that calls `super()` raises method-not-found. `super()` has nowhere to look.

## No cache

Method resolution happens **fresh on every call.** The engine does not cache resolved-method-per-class-per-name, does not pre-compute a linearization at class-definition time, and does not memoize dispatch outcomes.

**Why.** Classes and objects are mutable in Caspian. A cache would need invalidation whenever:

- A method is added to or removed from any class.
- A class's `inherits` array is altered.
- A stack is added to, removed from, or reordered in an instance's stack.
- The shadow gains a new singleton method.
- An `amend` block adds a method to a class.

Tracking every event that could invalidate a cache entry is more work than the walk it saves. And a bug in any of those tracking paths shows up as stale dispatch — a class of bug that's very hard to debug because the observable symptom (wrong method called) looks nothing like the actual cause.

**Why the walk is cheap.** In the common case the search finds the method on the immediate class or one step up — a hash lookup or two. Even the deep case is a small handful of hash lookups. Method-call overhead in an interpreted language is dominated by frame setup, argument binding, and closure creation; the dispatch walk is a fraction of that total.

Adding a cache later is a strictly local optimization if actual profiling ever demands it. Committing to a cache now would bake complexity in permanently.

## Interactions worth noting

- **Shadow stack.** Spec'd on [object structure § shadow](https://puck.uno/requirements/built-in-classes/object/structure/#shadow). The shadow sits at position 0 by convention and participates in dispatch like any other class-carrying stack — no MI-specific rule.
- **`%self`.** Binds to the instance receiving the call, regardless of which class defines the method that runs. Not affected by MI.
- **Field storage.** This page specs method dispatch only. Bucket and field storage are spec'd on [object structure](https://puck.uno/requirements/built-in-classes/object/structure/); field-name ownership across MI is a separate concern.

## Testing

- **Simple inheritance dispatches to nearest.** `B inherits A`, both define `.foo` — `$b.foo` dispatches to `B`.
- **Single-inheritance fallthrough.** `B inherits A`, only `A` defines `.foo` — `$b.foo` dispatches to `A`.
- **MI depth-first: first-declared parent's chain resolves first.** `C inherits A, B`, both `A.foo` and `B.foo` defined — `$c.foo` dispatches to `A`.
- **MI diamond: shared ancestor reached via first-declared path.** With the camera_phone example above: `$cp.capture()` → `camera`; `$cp.call('555-1234')` → `phone`; `$cp.describe()` → `device`, reached through `camera`.
- **Seen-set prevents revisit.** A class with instrumented method lookup (counter incremented on every `has-method` check) reports one visit per dispatch even in a diamond.
- **`super()` walks the current class's inherits array.** From a method defined on class C, `super()` looks in C's declared parents, not in `%self`'s stack stack. The instance's actual class doesn't affect the lookup.
- **`super()` uses the defining class as context.** For a method inherited by many subclasses, calling `super()` inside that method always consults the SAME class's inherits array — the one that defined the method — regardless of `%self`'s class.
- **`super()` on a class with no parents raises.** Calling `super()` from a class whose inherits array is empty raises method-not-found.
- **No cache.** Add a method to a class after an instance was constructed; a call on that instance sees the new method immediately.
