# Clause slots on block-carrying constructs

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_clause_slots",
	"role": "spec for the multi-clause structure block-carrying constructs can have in Caspian. Two disjoint sets: `ensure` is exclusively for bare `begin ... end` (single-shot cleanup); the iteration-lifecycle set `before / between / after / noloop` applies to callable-shaped constructs (function / closure / method / do / dofunc) and to loops (while / until / begin-while / begin-until / .each / .times / .upto / .downto). Loop bodies are conceptually closures — the engine may realize them as closures — so they share the callable-clause set. Wrong-context clause markers raise at parse time with a specific error steering to the right construct. Undeclared clauses do not appear in the atom (Option B — no empty-slot padding).",
	"status": "spec — the two clause sets and their runtime meaning are settled; the CaspJ shape (declared-only slots) is settled; parser rejects wrong-clause-in-wrong-construct at transpile time",
	"audience": "developers writing block-carrying code; developers writing iterator methods that need to invoke clauses; transpiler / engine implementers realizing the parse and dispatch shapes; anyone reasoning about scope semantics across clauses"
}}
~~~

Caspian has **five reserved clause markers** — `before`, `between`, `after`, `noloop`, `ensure`. They split into two disjoint sets based on which construct owns them:

| Clause set | Belongs to | Constructs |
|---|---|---|
| `ensure` | single-shot cleanup | bare `begin ... end` |
| `before` / `between` / `after` / `noloop` | iteration lifecycle | functions, closures, methods, `do` / `dofunc` blocks, `while` / `until`, `begin ... while` / `begin ... until`, `.each` / `.times` / `.upto` / `.downto` |

`body` is the main clause and is present on every block-carrying construct. It's not a marker keyword — it's implicit (everything before the first clause marker).

## Why the split

**`begin ... end` is a single-shot block.** It runs once. `before` / `between` / `after` / `noloop` are lifecycle hooks that only make sense across multiple invocations, so they'd be dead weight there. What `begin ... end` genuinely needs is a **cleanup hook that always runs** — that's `ensure`, paralleling Ruby's `ensure` / Python's `finally`.

**Loop bodies and callable bodies are the same thing** from the parser's perspective — a body invoked N times. The engine may in fact realize a loop body as a closure. That's why the iteration-lifecycle set is shared between them.

**`ensure` on a callable would be ambiguous** — callables aren't tied to a single invocation the way `begin` is, so "always runs" has no clear anchor. Reach for `begin ... ensure ... end` inside the callable if you need that semantic.

## What each clause means

| Clause | Runs when |
|---|---|
| `body` | The main content. Runs on invocation. |
| `before` | Once, before the first `body` invocation. |
| `between` | Between each pair of `body` invocations — N-1 times when body runs N times. Skipped when body runs 0 or 1 times. |
| `after` | Once, after the last `body` invocation, on the normal-completion path only. |
| `noloop` | When `body` never ran (empty iteration source). |
| `ensure` | Always — normal completion, exception, controller `.return`, `break`. Parallel to Ruby's `ensure` / Python's `finally`. |

## Callable bodies

Any `function`, `closure`, `method`, `do`, or `dofunc` can declare `before` / `between` / `after` / `noloop`:

~~~caspian
$foo = closure($idx)
	puts $idx
before
	puts '--- START ---'
between
	puts '---'
after
	puts '--- END ---'
noloop
	puts '--- (nothing to iterate) ---'
end
~~~

The clauses become accessible as methods on the callable object: `$foo.body`, `$foo.before`, `$foo.between`, `$foo.after`, `$foo.noloop`. `$foo.call($arg)` remains the invocation shortcut — equivalent to `$foo.body($arg)`.

## Loop bodies

`while`, `until`, `.each`, `.times`, `.upto`, `.downto`, and the `begin ... while` / `begin ... until` post-loop forms all accept the same four clauses:

~~~caspian
while $x < 100
	$x = $x + 1
before
	$started_at = %now
after
	puts "elapsed: #{%now - $started_at}"
noloop
	puts "already >= 100 at entry"
end
~~~

## Bare `begin ... end` and `ensure`

`begin ... end` accepts only `ensure`:

~~~caspian
begin
	$fh = %fs.open('data.csv')
	do_something $fh
ensure
	$fh.close
end
~~~

## How iterator methods use the clauses

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

`$block.body.caller.new` builds a fresh caller for the body clause; `.wants_controller?` skips controller construction for blocks that didn't declare `as $name`; `.controller = ...` sets the object that binds to the target's `$name`.

The `noloop` clause runs only when `body` was never invoked — the iterator method decides that condition based on its own knowledge (e.g., empty collection).

## Where clause validation happens: parse time vs. runtime

Two layers of validation, chosen by what each layer can see:

**Parse time** handles cases where the parser has enough context to decide. That covers:

- **Wrong construct entirely** (e.g., `ensure` inside a function body, `before` inside a bare `begin ... end`). The parser knows the enclosing frame type and the accepted set per type; wrong-set is caught at the clause line.
- **Dead-code cases on trailing-cond loops** (e.g., `noloop` inside `begin ... while COND` — the body runs at least once by construction, so `noloop` could never fire). Rejected at the `while` / `until` transition.
- **`if` / `unless` branches.** The parser knows statically that the branch-body closure has exactly one invocation site — the `if` construct itself — and no iterator will ever call `.before` / `.after` / etc. on it. So iteration clauses on an `if` branch are dead code and get rejected at the clause line.

**Runtime** handles callable-shaped constructs where the parser CAN'T predict who will invoke the callable or how. When a user writes:

~~~caspian
$foo = closure($idx)
	puts $idx
before
	puts '---'
end
~~~

the callable atom just carries `before: [...]` as a field on the closure. Whoever eventually calls `$foo` — an iterator like `.each` that invokes `.before` at the right time, a plain `$foo.call()` that doesn't, some third-party class that inspects `$foo.before` and does its own thing — decides what the slot means. The parser can't reject "unused `before`" because it can't see the future call sites.

The general rule: **push the check as early as possible.** When the parser has enough context (`if` branches, wrong-construct, dead-code loop hooks), reject there. Otherwise, the callable carries its slots and the runtime caller does whatever validation it needs.

## Wrong-context clause markers raise at parse time

Every clause marker is a reserved word tied to a specific construct set. Using one in the wrong place is a parser error, not a runtime "no such command":

~~~caspian
$foo = closure($idx)          # RAISES:
	puts $idx                     # `ensure` is only valid inside a bare
ensure                            # `begin ... end`; closure bodies use
	puts 'done'                   # `before` / `between` / `after` / `noloop`
end
~~~

~~~caspian
begin                         # RAISES:
	puts 1                        # `before` is not valid inside a bare
before                            # `begin ... end`; use it on a loop
	puts '---'                    # (`while` / `until` / `.each` / ...) or a
end                               # callable body (function / closure / method / do)
~~~

`begin ... while COND` (a begin-while loop) is a loop, so it follows the iteration-clause rule — `ensure` there raises `\`ensure\` is not valid on a \`begin ... while\` loop`. Additionally, `noloop` on `begin ... while` or `begin ... until` raises — those trailing-cond forms run the body at least once by construction, so a "body-never-ran" hook would be dead code. Use the leading-cond `while COND ... noloop ... end` if you genuinely need it.

## Always safe to call — undeclared clauses are no-ops

**A callable's clause methods are always safe to invoke, whether or not the source declared that clause.** Calling `$foo.before` on a plain-body closure does nothing and raises nothing — the runtime treats an undeclared clause as a no-op.

This lets iterator methods stay branch-free: they can invoke `$block.before` unconditionally, and it will only produce visible behavior when the caller declared a `before` clause.

## Scope: each clause is its own scope

**Each clause runs in its own fresh frame.** Variables declared inside `body` are not visible in `before`, `between`, `after`, or `noloop`, and vice versa. Every `body` invocation gets a fresh frame too — iteration locals re-init each time.

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

## `before` / `after` vs the `body` param

Structural clauses **do not receive the iteration variable.** In an iterator like `.each do ($item)`, `$item` binds inside `body` only; `before`, `between`, `after`, and `noloop` don't have access to it.

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
		"noloop":  [ /* declared */ ]
	}
}
~~~

A closure with only a body (the common case) transpiles to `{closure: {params, body}}` — no empty-slot padding. Same rule applies to `function`, `method`, `do`, `dofunc`, `while_end`, `until_end`, `begin_while`, `begin_until`, and `begin_end` atoms.

`begin_end` uses the same shape for its (sole) `ensure` slot:

~~~json
{
	"begin_end": {
		"body":   [ /* main clause */ ],
		"ensure": [ /* declared — the only clause bare begin admits */ ]
	}
}
~~~

Norm preserves the same shape — the runtime handles the "missing slot = no-op" dispatch, so the CaspJ layer stays source-fidelity.

## Related

- [bare-blocks](https://puck.uno/documentation/requirements/syntax/bare-blocks) — the `begin ... end` construct and its `as $block` controller.
- [loops](https://puck.uno/documentation/requirements/syntax/loops) — where the iteration-clause set originated.
- [functions](https://puck.uno/documentation/requirements/functions/) — the `function`, `closure`, `method` constructs and their runtime surface.
