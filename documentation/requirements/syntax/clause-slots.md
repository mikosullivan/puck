# Clause slots on block-carrying constructs

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_clause_slots",
	"role": "spec for the multi-clause structure any block-carrying construct in Caspian can have: `body` plus five optional lifecycle / structural / cleanup clauses (`before`, `between`, `after`, `noloop`, `ensure`). Applies uniformly to bare blocks (`begin`), loops (`while`, `until`, `.each`, `.times`, ...), and callables (`function`, `closure`, `method`, `do`). Callable objects expose the clauses as named methods (`.body`, `.before`, `.between`, `.after`, `.noloop`, `.ensure`), and iterator methods invoke them at the appropriate lifecycle points. Undeclared clauses are always safe to call — a no-op. Each clause runs in its own scope; cross-clause state lives in the enclosing scope via closure capture. CaspJ preserves only the declared clauses (Option B: no empty-slot padding).",
	"status": "spec — the six clause names and their runtime meaning are settled; the CaspJ shape (declared-only slots) is settled; iterator-convention interface (`.before` / `.between` / ... on the callable object) is settled; concrete no-op-sentinel implementation on the callable side is a runtime detail",
	"audience": "developers writing block-carrying code; developers writing iterator methods that need to invoke clauses; transpiler / engine implementers realizing the parse and dispatch shapes; anyone reasoning about scope semantics across clauses"
}}
~~~

Any block-carrying construct in Caspian — a bare `begin`, a loop, or a callable definition (`function`, `closure`, `method`, `do`) — can have up to six named clause slots. **`body`** is the main clause and is what runs by default; the other five are optional lifecycle, structural, and cleanup hooks.

## The six clauses

| Clause | When it runs |
|---|---|
| `body` | The main content — runs on invocation. Present on every block-carrying construct. |
| `before` | Once, before the first `body` invocation. |
| `between` | Between each pair of `body` invocations — N-1 times when body runs N times. Doesn't run when body runs 0 or 1 times. |
| `after` | Once, after the last `body` invocation, only on the normal-completion path. |
| `noloop` | Only when `body` never ran (e.g., iterating an empty collection). |
| `ensure` | Always runs, regardless of how the block exited — normal completion, exception, controller `.return`, `break`. Parallel to Ruby's `ensure` / Python's `finally`. |

**`after` vs `ensure`.** `after` is the normal-completion hook; `ensure` is the always-runs hook. On the happy path, the order is `body` → `after` → `ensure`. On an exceptional exit, `ensure` runs, `after` does not.

## Where clauses appear

**Loops.** The four structural clauses (`before`, `between`, `after`, `noloop`) plus `ensure` all apply to `while`, `until`, `begin ... while`, `begin ... until`, `.each`, `.times`, `.upto`, and `.downto`. See [loops](https://puck.uno/documentation/requirements/syntax/loops).

**Bare blocks.** `begin ... end` accepts `before`, `after`, and `ensure` (the iteration-oriented ones — `between` and `noloop` — have no meaning on a single-shot block and are rejected there). See [bare-blocks](https://puck.uno/documentation/requirements/syntax/bare-blocks).

**Callables.** Any `function`, `closure`, `method`, or `do` block-value can carry all six clauses:

~~~caspian
$foo = closure($idx)
	puts $idx
before
	puts '--- numbers ------'
between
	puts '---'
after
	puts '------------------'
noloop
	puts '--- no numbers ---'
ensure
	puts '(always runs)'
end
~~~

The callable's clauses become accessible as methods on the callable object: `$foo.body`, `$foo.before`, `$foo.between`, `$foo.after`, `$foo.noloop`, `$foo.ensure`. `$foo.call($arg)` remains the invocation shortcut — equivalent to `$foo.body($arg)`.

## How iterator methods use them

Iterator methods (`.each`, `.times`, `.upto`, `.downto`, and any user-written iterator that opts in) invoke the clause slots at the right times. A minimal skeleton:

~~~caspian
method &times($block)
	$block.before        # once, before any body call

	$count.iterate do ($i)
		$block.body $i   # each iteration

		# between runs N-1 times — after every body call except the last
		$block.between if not_last_iteration
	end

	$block.after         # once, after normal completion
	$block.ensure        # always runs (would also run on exceptional exit)
end
~~~

### Providing a loop controller (`as $name` targets)

When the block's `body` was declared with an `as $name` binding — e.g. `do($idx) as $loop` — the iterator method uses a [caller object](https://puck.uno/documentation/requirements/functions/caller/) to inject the loop-controller object into `$name`:

~~~caspian
method &times($block)
	$count.iterate do ($i)
		$caller = $block.body.caller.new

		if $caller.wants_controller?
			$caller.controller = LoopController.new(index: $i, count: $count)
		end

		$caller.call $i
	end
end
~~~

`$block.body.caller.new` builds a fresh caller for the body clause; `.wants_controller?` skips controller construction for blocks that didn't declare `as $name`; `.controller = ...` sets the object that binds to the target's `$name`. Blocks without `as` see nothing; blocks with `as` see either the supplied controller or `null` when the iterator opted out.

The `noloop` clause runs only when `body` was never invoked — the iterator method decides that condition based on its own knowledge (e.g., empty collection).

## Always safe to call — undeclared clauses are no-ops

**A callable's clause methods are always safe to invoke, whether or not the source declared that clause.** Calling `$foo.before` on a plain-body closure does nothing and raises nothing — the runtime treats an undeclared clause as a no-op.

This lets iterator methods stay branch-free: they can invoke `$block.before` unconditionally, and it will only produce visible behavior when the caller declared a `before` clause.

## Scope: each clause is its own scope

**Each clause runs in its own fresh frame.** Variables declared inside `body` are not visible in `before`, `between`, `after`, `noloop`, or `ensure`, and vice versa. Every `body` invocation gets a fresh frame too — iteration locals re-init each time.

To share state across clauses, declare it in the **enclosing scope** — the scope where the closure / function / block was defined. The closure captures the enclosing scope; every clause has read/write access to it through the capture:

~~~caspian
$sum = 0

$foo = closure($idx)
	puts $idx
	$sum += $idx        # writes the enclosing-scope $sum
after
	puts "sum: #{$sum}" # reads the enclosing-scope $sum
end
~~~

The `body` clause's local `$idx` is invisible to `after`; both clauses see `$sum` because it lives in the enclosing scope.

Same rule for bare blocks: a `begin` block's clauses each run in their own scope, sharing only what's captured from outside.

## `before` / `after` vs the `body` param

Structural clauses **do not receive the iteration variable.** In an iterator like `.each do ($item)`, `$item` binds inside `body` only; `before`, `between`, `after`, `noloop`, and `ensure` don't have access to it.

The distinction is deliberate: structural clauses are lifecycle hooks, not per-iteration work. If a structural clause needs to reference iteration state, the block should capture from the enclosing scope (as with `$sum` above).

## CaspJ shape (Option B — declared-only)

Full CaspJ preserves ONLY the clauses that the source declared. Undeclared slots do not appear in the atom.

~~~json
{
	"closure": {
		"params": ["idx"],
		"body":    [ /* main clause */ ],
		"before":  [ /* declared */ ],
		"between": [ /* declared */ ],
		"after":   [ /* declared */ ],
		"noloop":  [ /* declared */ ],
		"ensure":  [ /* declared */ ]
	}
}
~~~

A closure with only a body (the common case) transpiles to `{closure: {params, body}}` — same shape as before the clause generalization, no empty-slot padding. Same rule applies to `function`, `method`, `do`, `begin_end`, `while_end`, `until_end`, `begin_while`, and `begin_until` atoms.

Norm preserves the same shape — the runtime is what handles the "missing slot = no-op" dispatch, so the CaspJ layer stays source-fidelity.

## Related

- [bare-blocks](https://puck.uno/documentation/requirements/syntax/bare-blocks) — the `begin ... end` construct and its `as $block` controller.
- [loops](https://puck.uno/documentation/requirements/syntax/loops) — where `before` / `between` / `after` / `noloop` originated.
- [functions](https://puck.uno/documentation/requirements/functions/) — the `function`, `closure`, `method` constructs and their runtime surface.
