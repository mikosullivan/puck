# `caspian.uno/helpers.casp`

<span class="tag">helpers</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_downloads_helpers",
	"role": "spec for `caspian.uno/helpers.casp` — a downloadable class any other class can inherit (via multiple inheritance) to gain a hash-like `.helpers` slot for attaching per-instance helper objects. Helpers get instantiated with the parent object as constructor argument (`Class.new(%self)`), stored in `%bucket['helpers'][name]`, and exposed as method-like accessors on the parent (`$parent.name` returns the helper instance). Access to the parent is through its PUBLIC method surface only — the helper class is a separate class with no special privilege into the parent's `%bucket` or private state. The parent decides what to do with its helpers at runtime by scanning them for convention methods (like `.set_header` in the case of `core:http/request`); helpers that don't implement the parent's convention are silently ignored. Name collisions with existing methods raise; helpers don't have to know about their parent (context-free helpers are valid). Downloadable at `caspian.uno/helpers.casp` — not bundled with the caspian binary, resolved via `%fetch` on first use and cached locally.",
	"status": "spec — add / direct-set / delete surface, name-collision-raises rule, context-free helpers, isolation-from-guts, and duck-typed convention model all settled; Drinian snapshot behavior and any standard hook-name conventions still pending",
	"audience": "Caspian class authors who want their classes to accept per-instance helpers; helper-class authors; anyone auditing the helpers surface"
}}
~~~

A downloadable class that any Caspian class can inherit (via multiple inheritance) to gain a hash-like `.helpers` slot for attaching per-instance helper objects. The canonical consumer is [`core:http/request`](tag:http-request), which uses this pattern to accept helpers for HTTP header composition (Accept, Cookie, etc.); other classes can inherit the same pattern for their own extension needs.

The helper attaches to the parent through the parent's PUBLIC method surface only. The helper class is a separate class with no special access to the parent's `%bucket` or private state — the isolation companion to the [`$obj.$fn` downloaded-methods](https://puck.uno/documentation/requirements/classes/downloaded-methods) pattern, which binds a function to the full receiver surface including bucket. Both patterns are useful; this one is for cases where isolation is the design goal.

Accessed via `%('caspian.uno/helpers.casp')`. Not bundled with the caspian binary; fetched on demand and cached locally.

## Adding a helper

Two paths.

### `.helpers.add(name, class)`

Instantiates a helper class with the parent object and registers it under `name`:

~~~caspian
$request.helpers.add 'accept', %('caspian.uno/http/accept.casp')
~~~

Three things happen:

1. Lazily creates `%bucket['helpers']` on first use.
2. Instantiates the helper — `%('caspian.uno/http/accept.casp').new(%self)`, passing the parent as the constructor argument — and stores the instance under the given name.
3. Registers `name` as a method-like accessor on the parent — `$request.accept` returns the stored helper instance.

Conceptually equivalent to:

~~~caspian
%bucket['helpers'] ||= {}
%bucket['helpers']['accept'] = %('caspian.uno/http/accept.casp').new(%self)
~~~

### `.helpers[name] = $obj`

Direct assignment. `$obj` must be pre-instantiated; no `.new(%self)` call happens on this path:

~~~caspian
$my_helper = %('some.uno/helper.casp').new $some_config
$request.helpers['my_key'] = $my_helper
~~~

Useful when the developer wants to construct the helper with custom arguments, or reuse an existing helper across scopes.

## Name collisions raise

If `name` already resolves to a method on the parent — a native method, an inherited method, or a previously-registered helper — both `.helpers.add(name, class)` and `.helpers[name] = obj` raise immediately with a specific error naming the collision. No shadowing, no silent overwrite. Fail-loud-early.

To rotate a helper on the same name, delete first, then set:

~~~caspian
$request.helpers.delete 'accept'
$request.helpers['accept'] = $new_helper
~~~

The two-step spelling is explicit (the developer sees both operations happen) and stays no-nanny (no silent overwrite). No `.replace` shortcut.

## Hash-like interface

`.helpers` returns a hash-like object with standard hash idioms:

- `.helpers[name]` — get the helper stored under that name.
- `.helpers[name] = obj` — direct assignment (see above).
- `.helpers.delete(name)` — remove a helper by name, freeing its accessor.
- `.helpers.keys` — array of registered helper names.
- `.helpers.each` — iterate over `(name, helper)` pairs.
- `.helpers.length` — count of registered helpers.
- `.helpers.has?(name)` — presence check.

## Helpers don't have to know their parent

The framework doesn't require a helper class to know about its parent object. `.helpers.add(name, class)` is a convenience that instantiates via `Class.new(%self)` — passing the parent — for helpers that want the reference. `.helpers[name] = $obj` skips that step entirely; if `$obj` was never told about `%self`, that's fine.

A context-free helper is valid — a class whose `.set_header` returns a static `('X-Client', 'MyApp/1.0')` doesn't need any parent reference at all; it just contributes something. The helper class decides for itself whether it needs a parent reference and stashes one during construction if so. The framework never checks.

## What the parent class does with its helpers

`caspian.uno/helpers.casp` provides the add / lookup / delete machinery only. What the PARENT class does with its helpers at runtime is entirely up to the parent — the helpers spec doesn't dictate hooks, calling conventions, or execution order.

Parents typically walk `%bucket['helpers']` at some meaningful moment (send time, render time, on-close, etc.) and call a convention method on each helper if it implements one. Convention methods are duck-typed — helpers that don't implement the parent's expected method are silently ignored (they might exist for other conventions the same parent honors, or for a different parent class entirely).

Example: `core:http/request` walks its helpers at send time and calls `.set_header()` on each helper that implements it. Helpers that don't implement `.set_header()` are ignored by the request; they might still be doing useful work through some other convention.

Different parent classes define different conventions. The convention is documented on each parent class, not on `caspian.uno/helpers.casp`.

## Isolation from the parent's guts

The helper holds a reference to `%self` (passed via `.new(%self)` when the framework registers it) and can call whatever PUBLIC methods that reference exposes. It has no access to the parent's `%bucket` or private state — Caspian's normal class-visibility rules apply, and the helper is a separate class with no special privilege.

This is deliberate: helpers may come from downloaded third-party classes with different trust levels than the parent. The parent's private state stays private; helpers work through the parent's public API just like any other outside caller.

Trade-off: if a parent class deliberately exposes a broad public API, its helpers effectively get that whole surface. Narrow public surface → narrow helper reach.

## Testing

- **`.helpers.add(name, class)`** creates the underlying `%bucket['helpers']` hash on first use, instantiates the class via `.new(%self)`, and stores under `name`.
- **`.helpers[name]`** returns the stored helper instance.
- **`.helpers[name] = obj`** stores `obj` directly; no `.new(%self)` call.
- **`.helpers.delete(name)`** removes the helper and its accessor.
- **`$parent.name`** returns the helper stored under `name` (method-like accessor).
- **Name collision on `.add` raises** — `.helpers.add 'foo', X; .helpers.add 'foo', Y` raises on the second call.
- **Name collision on `[]=` raises** — same behavior.
- **Collision with a native method raises** — if the parent has a `.foo` method, `.helpers.add 'foo', X` raises.
- **Collision with an inherited method raises** — if a parent inherits `.bar` from another class, `.helpers.add 'bar', X` raises.
- **Delete-then-set succeeds** — `.helpers.delete('foo'); .helpers['foo'] = $new` does not raise; the new helper is stored.
- **`.helpers.keys`, `.helpers.each`, `.helpers.length`, `.helpers.has?`** all work like standard hash operations.
- **Context-free helper accepted** — `.helpers[name] = $obj_that_never_knew_the_parent` succeeds; the framework doesn't verify parent-awareness.
- **Multiple inheritance** — a class that inherits from both `caspian.uno/helpers.casp` and another class gets `.helpers` alongside whatever else it inherited.
- **Helper cannot access `%bucket`** — the helper's methods, from inside the helper's class body, have no access to the parent's bucket or private methods; only the parent's public method surface is reachable via the passed-in reference.
- **Unrecognized convention method silently ignored** — a helper that lacks the method the parent scans for is not called; no error either way.

## Related

- [`core:http/request`](https://puck.uno/documentation/requirements/http/request) — the canonical consumer; uses `.helpers` to accept HTTP-header helpers like Accept, Cookie, Cache-Control.
- [downloaded-methods](https://puck.uno/documentation/requirements/classes/downloaded-methods) — the `$obj.$fn` pattern that binds a function to the full receiver surface (including `%bucket`). Helpers are the isolation companion — same "attach behavior to an object" goal, opposite privilege posture.
- [class inheritance](tag:class-inheritance) — the multiple-inheritance model that lets any class pick up the helpers machinery by adding this class to its `inherits` list.
