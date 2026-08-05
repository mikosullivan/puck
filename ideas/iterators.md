# Iterators

~~~vibecode
{"vibecode": {
	"doc": "ideas_iterators",
	"role": "design for how iteration works in Caspian at the developer level. Iterators are not a first-class construct — no Iterator class, no standalone iterator objects, no generators. An iterator is a method that runs a primitive loop internally and forwards that loop's controller to the caller's block. Two sugars: `iterate` on the producer side (collapses the caller-build-and-call boilerplate into one line), and bare `break` / `next` on the consumer side (dispatch to the innermost enclosing loop's controller with an index-from-innermost numeric arg for outer loops). Coexists with `yield`, which invokes block[0] with args but doesn't pass a controller.",
	"status": "designed 2026-08-05 with Miko — controller-passing model + `iterate` sugar + break/next as sugar for controller-method dispatch. Depends on loop-controller support, which is currently deferred (see loops § Deliberately out of scope)."
}}
~~~

## The model

Iterators aren't a first-class construct in Caspian. A developer never builds an iterator "object" from scratch. Instead, iteration happens through methods that wrap a primitive loop (`while`, `until`, `.each`, `.times`, `.upto`, `.downto`, or the `begin ... while` / `begin ... until` forms) and forward that loop's controller through to the caller's block.

When user code writes `$foo.each_leaf do($leaf) as $loop`, the `$loop` bound inside the block IS the controller from a primitive loop running inside `each_leaf`. Calling `$loop.break` from the user's block breaks that internal primitive loop, which returns from `each_leaf`. Same controller object, two references.

## What's ruled out

- **No `Iterator` class to inherit from.** No such thing.
- **No standalone iterator objects.** What user code calls `.break` on is always some primitive loop's controller, currently live in a stack frame somewhere.
- **No lazy sequences.** Every iteration point has a live primitive loop running behind it.
- **No Python-style generators.** A generator that pauses execution between yields and resumes on demand isn't available under this model. If a use case surfaces for that, it's a separate primitive to add — not something that falls out of the current shape.

## The bare pattern

Without sugar, an iterator method looks like this:

~~~caspian
method &records
	$db = somedb

	while ($record = $db.next) as $loop
		$caller = %call.blocks.first.caller.new
		$caller.controller = $loop
		$caller.call $record
	end
end
~~~

Walk-through:

1. `while ($record = $db.next) as $loop` — a primitive `while` loop, bound to `$loop` as its controller.
2. `$caller = %call.blocks.first.caller.new` — build a caller for the block the user passed to `records`.
3. `$caller.controller = $loop` — wire the block's `as $loop` binding to point at the internal while's controller.
4. `$caller.call $record` — invoke the block with `$record` as its arg.

When user code writes `$my.records do($record) as $loop; $loop.break; end`, `$loop.break` in the block dispatches to the while's controller (same object). The while exits, `records` returns.

Note the caller-per-iteration allocation in the unsugared example. In real code the caller can be built once above the loop and reused — a caller is reusable across `.call` invocations per its own spec.

## `iterate` — the sugar

The `iterate` bwc collapses the caller-build-and-call boilerplate into one line:

~~~caspian
method &records
	$db = somedb

	while ($record = $db.next) as $loop
		iterate $loop, $record
	end
end
~~~

`iterate CTRL, ARGS...` expands to:

~~~caspian
$caller = %call.blocks[0].caller.new   # or cached across calls in the same method invocation
$caller.controller = CTRL
$caller.call ARGS...
~~~

The first arg is always the controller to wire; the remaining args pass through to the block's `.call`.

### Coexists with `yield`

`iterate` doesn't replace `yield`. Both are primitives, with distinct signatures:

- **`yield ARGS...`** — invoke block[0] with args. No controller involvement. Used when the block doesn't need `as $name` binding (no `.break`, no `.count`, no state exposed by the iterator).
- **`iterate CTRL, ARGS...`** — invoke block[0] with args AND wire its `as $name` binding to `CTRL`. Used when the iterator wants the caller to be able to name the controller and call methods on it.

An iterator that doesn't need to expose a controller can just use `yield`. One that does uses `iterate`.

## `break` and `next` — the consumer sugar

On the consumer side, user code that wants to break out of an iterator can call `.break` on the controller directly:

~~~caspian
$foo.records do($record) as $loop
	if $record.matches($target)
		$loop.break
	end
end
~~~

That works but requires the block to declare `as $loop` even when the user has no other need to name the controller. Bare `break` is sugar for the same operation with an implicit target — the innermost enclosing loop's controller. Same block, without the naming:

~~~caspian
$foo.records do($record)
	if $record.matches($target)
		break
	end
end
~~~

Every primitive loop unconditionally creates a controller, whether the user writes `as $loop` or not — the controller has to exist somewhere reachable so the sugar can dispatch to it. `as $loop` adds a name binding; omitting `as` leaves the controller unnamed but present.

`next` works the same way — sugar for `.next` on the innermost enclosing loop's controller.

### The numeric arg: index from the innermost

Both `break` and `next` accept an optional integer arg naming which enclosing loop to target, as an outward index from the innermost.

| Form | Target |
|---|---|
| `break` | innermost loop |
| `break 0` | innermost loop (redundant spelling of bare `break`) |
| `break 1` | one level up |
| `break 2` | two levels up |
| `break N` | N levels up |

`next 0` / `next 1` / `next N` follow the same numbering.

~~~caspian
while(&outer)
	while(&inner)
		break        # exits the inner while — implicit index 0
	end
end

while(&outer)
	while(&inner)
		break 1      # exits the outer while (which cascades to end the inner)
	end
end
~~~

Breaking an outer loop cascades — the inner loop is executing inside the outer, so ending the outer necessarily ends the inner. The engine implements the cascade through whatever mechanism the controller uses to signal exit.

`break N` where N ≥ the enclosing-loop count raises — there's no controller at that depth to call `.break` on. Same for `next N`.

### Named-loop targeting is still available

For nesting deeper than a couple of levels, or when refactoring might change nesting depth, calling `.break` on a named controller reads more clearly than counting:

~~~caspian
while(&outer) as $outer_loop
	while(&inner)
		if $condition
			$outer_loop.break
		end
	end
end
~~~

`$outer_loop.break` targets the outer loop by name, unambiguous regardless of nesting depth. Choose whichever form reads better at the call site — `break N` for shallow, stable nesting; `$loop_name.break` for deeper or evolving code.

## Naming precedent

`iterate` reads naturally at the call site — "iterate using this loop, with this value." Verb form matches what the bwc does; single word keeps every iterator method a line shorter than the unsugared form; no collision with any primitive already on the list.

## Dependencies and open items

**Loop controllers themselves are currently deferred** — see [loops § Deliberately out of scope](https://www.puck.uno/requirements/syntax/loops#deliberately-out-of-scope). The iterator model in this doc depends on the `as $loop` binding and `$loop.<method>` dispatch landing eventually. Everything here is aspirational until those come back.

### Multi-block methods

Every use of `iterate` and `yield` in this doc assumes `%call.blocks[0]` — the first (and usually only) block passed to the method. If a method takes multiple blocks (rare, but supported by the caller model), how does `iterate` designate which block it wants to invoke? Options: always block[0] with an escape hatch to the un-sugared form for other blocks; a form like `iterate[1] CTRL, ARGS...` that names the block by index; some third shape. Undecided.

### Caller reuse

The sugar's expansion builds a fresh caller each time `iterate` fires. For methods invoking many iterations, that's an allocation per iteration. The expansion could cache the caller for the current method invocation and reuse across iterate calls; performance win, but adds an implicit-caching rule the sugar's semantics have to carry. Undecided whether that optimization is part of the primitive or something the runtime does under the hood.

### Interaction with the deferred loop-controller design

The controller-passing shape assumes the answer to the loop-controller routing question that led to the deferral in [loops § Deliberately out of scope](https://www.puck.uno/requirements/syntax/loops#deliberately-out-of-scope) is "controllers are objects that a caller's `.controller` slot can hold, and the block's `as $name` binds to whatever's in that slot." If the loop-controller design lands differently, `iterate`'s expansion needs to change accordingly.
