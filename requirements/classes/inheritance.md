# Class inheritance

<span class="tag">class-inheritance</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_classes_inheritance",
	"role": "spec for the class-level inheritance surface — the live `.inherited` array on every class and the mutation methods on it (`.push`, `.ensure` bare and block forms, `.pop`). Two entry points to inheritance: the static `inherits` clause at class-definition time (spec'd on classes/definition § Inheritance) sets the initial parents; the `.inherited` accessor at runtime exposes the same array as a mutable value. Mutations propagate to method resolution immediately since there's no cache (see tag:method-resolution). Block-form `.ensure` scopes the change to a block's duration with identity-tracked cleanup — the primary idiom for temporarily extending a built-in class with additional methods.",
	"status": "spec — surface and semantics settled; Array's general `.ensure` method still needs its own dedicated spec entry",
	"audience": "developers who need to add or remove class parents at runtime; anyone reading a test case (like test-cases/colorize) that uses `.inherited.ensure`"
}}
~~~

Every class has an **inheritance array** — the classes it descends from. Set at class-definition time by the `inherits` clause ([classes/definition § Inheritance](https://puck.uno/requirements/classes/definition/#inheritance)); reachable at runtime through the `.inherited` accessor.

## The `.inherited` accessor

`$class.inherited` returns the class's **live** parent array. Mutations to this array modify the class's inheritance immediately — instances of the class see new parents' methods on the next dispatch, and lose access to removed parents just as immediately.

~~~caspian
class # widget
	inherits displayable, serializable
end

$widget.inherited            # [displayable, serializable]
$widget.inherited.push($extra_class)
$widget.inherited            # [displayable, serializable, $extra_class]
~~~

Because it's a live view (not a snapshot), holding `$arr = $widget.inherited` gives you a reference to the same underlying array — subsequent mutations show up when you read `$arr` again.

**Contrast with `$obj.object.classes`.** The per-instance surface at [object/methods § `.classes`](https://puck.uno/requirements/built-in-classes/object/methods/#classes--classesensureclass--classesaddunconditionallyclass--classesshadow) mutates the platter stack of a single instance. `.inherited` on the class mutates the class itself, affecting every instance. Pick the one that matches your scope.

## Mutation methods

`.inherited` is an ordinary array, so it supports Array's read and write surface. The mutation methods that matter for inheritance:

| Method | Effect |
|---|---|
| `.push($parent)` | Always add `$parent` as a new parent at the end of the array. |
| `.ensure($parent)` | Add `$parent` if not already present (identity match); no-op otherwise. |
| `.ensure($parent) do ... end` | **Block form.** Add `$parent` for the block's duration (only if not already present); remove exactly the platter this call added at block exit or on raise. |
| `.pop` | Remove the last parent. |
| `.delete($parent)` | Remove `$parent` from the array if present. |

`.ensure` is a general Array method — it works on any array, not just `.inherited`. See [array/](https://puck.uno/requirements/built-in-classes/primitives/array/) for the general spec (pending).

Order in the array matters for method resolution: earlier parents are searched before later ones (per [method resolution](tag:method-resolution)).

## Block-form `.ensure` — temporary inheritance

The block form is the canonical "add a class temporarily" idiom. If the parent isn't already in the array, `.ensure` adds it, runs the block, and removes exactly that entry at block exit. Cleanup is **identity-tracked**: the engine remembers which entry it added and removes only that one — user code inside the block that adds its own entry via a separate path is left alone.

~~~caspian
$widget.inherited.ensure($debug_mixin) do
	# $widget's instances now see $debug_mixin's methods
	$w.debug_dump
end

# $debug_mixin is no longer a parent of $widget; instances lose access to .debug_dump
~~~

If the parent **is** already in the array when the block starts, `.ensure` doesn't add anything, and nothing is removed at exit. The array ends the block exactly as it started. Same rule as [object/methods § `.classes.ensure` (block form)](https://puck.uno/requirements/built-in-classes/object/methods/#classes--classesensureclass--classesaddunconditionallyclass--classesshadow).

Cleanup runs on raise. If the block raises, the added parent is still removed on the way out.

**Nested composition.** An outer `.ensure($cls) do ... end` containing an inner `.ensure($cls) do ... end` composes cleanly: the inner sees the class already present, does nothing on entry, does nothing on exit; the outer removes its own added entry when it finishes. Both blocks end with the array in the state their opening frame observed.

## Immediate visibility

Mutations to `.inherited` show up on the next method dispatch. There is no dispatch cache to invalidate — method resolution walks the graph fresh on every call (per [method resolution](tag:method-resolution)), and it walks the current state of the inheritance graph, not a snapshot. Add a parent, call a method on any instance, the new parent is visible. Remove a parent, next call raises method-not-found for any method that lived only there.

All existing instances see the mutation, not just future ones. The inheritance array belongs to the class; instances refer to the class; the class's current state governs.

## The primary use case: temporarily extending a built-in

The most common `.inherited.ensure` pattern is scoped extension of a built-in class:

~~~caspian
$colorize = class # colorize
	method red()
		return "\e[31m" + %self + "\e[0m"
	end
end

%('core:string').inherited.ensure($colorize) do
	puts 'hello'.red    # works — every String has .red for the block's duration
end

puts 'hello'.red        # raises — Colorize is no longer a parent of String
~~~

Full worked example: [test-cases/colorize/](https://puck.uno/requirements/test-cases/colorize/).

## Consequences worth naming

- **Every instance sees the change.** Not just instances constructed after the mutation. Adding a parent to `%('core:string')` means every existing string carries the new methods.
- **Cross-fork behavior.** A fork sees a snapshot of the parent at fork time; mutations in one fork don't propagate to sibling forks. Class objects are per-process ([forks](https://puck.uno/requirements/chain/methods/forks) spec covers memory isolation).
- **Multi-inheritance ordering.** The parent array is order-sensitive. `.push` appends; `.ensure` appends when it adds. Insert-at-position (`.insert(idx, ...)`) is available as an Array method for cases where declaration-order placement matters.
- **Not restricted to built-ins.** Any class's `.inherited` is mutable. Adding a parent to a user class works identically.
- **Same class twice.** `.ensure` won't add a duplicate; `.push` will. Duplicate parents in the array are legal but usually a mistake — method resolution will find the class once (via the per-dispatch seen-set) and treat any extra copies as no-ops.

## Testing

- **`.inherited` returns the parent array** — `class # w inherits a, b end`; `$w.inherited` returns `[a, b]`.
- **`.inherited` is live** — after `$w.inherited.push($c)`, a second read of `$w.inherited` shows `$c` at the end.
- **`.push` always adds** — calling `.push($cls)` on an array that already contains `$cls` adds another copy at the end.
- **`.ensure` skips if present** — calling `.ensure($cls)` on an array that already contains `$cls` is a no-op; the array is unchanged.
- **`.ensure` adds if absent** — calling `.ensure($cls)` on an array without `$cls` appends `$cls`.
- **Block-form `.ensure` adds for the block only** — inside `$w.inherited.ensure($cls) do ... end` (where `$cls` was absent), `$w.inherited` contains `$cls`; after the block, `$cls` is gone.
- **Block-form no-ops when already present** — if `$cls` was already in the array, the block-form `.ensure` adds nothing on entry and removes nothing on exit; the array is unchanged.
- **Block-form cleanup runs on raise** — if the block raises, the added parent is still removed before the raise propagates.
- **Block-form is identity-tracked** — if user code inside the block adds its own entry of the same class via `.push`, only the outer `.ensure`'s added entry is removed on exit.
- **Nested block-forms compose** — an outer `ensure($cls) block containing an inner `ensure($cls)` block leaves the array exactly as it started after both exit.
- **Method resolution sees mutations immediately** — after `.push($extra)`, a call on any instance of the class dispatches to methods on `$extra`; before the push, the same call raises.
- **Mutations affect existing instances** — an instance constructed before `.push($extra)` sees `$extra`'s methods after the push.
- **Removing a parent removes access** — after `.delete($cls)`, calls to methods that lived only on `$cls` raise method-not-found.
- **Cross-fork isolation** — a fork mutating its parent's `.inherited` doesn't affect the parent process's classes; the parent sees no change.

## Related

- [classes/definition § Inheritance](https://puck.uno/requirements/classes/definition/#inheritance) — static declaration via `inherits`.
- [method resolution](tag:method-resolution) — how the parent array is walked at dispatch time; the no-cache rule that makes immediate visibility work.
- [object/methods § `.classes`](https://puck.uno/requirements/built-in-classes/object/methods/#classes--classesensureclass--classesaddunconditionallyclass--classesshadow) — the per-instance analog for adding classes to a single object's stack.
- [test-cases/colorize/](https://puck.uno/requirements/test-cases/colorize/) — worked test-case example using `.inherited.ensure`.
- [primitives/array/](https://puck.uno/requirements/built-in-classes/primitives/array/) — the general Array surface `.inherited` uses. `.ensure` in both bare and block forms is a general Array method (spec pending).
