# Loops
<!--index: 8.5-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_loops",
	"role": "spec for every loop construct in Caspian in one place — the condition-driven `while` and `until` (both in the pre-body form and the post-body `begin ... while` / `begin ... until` loop-at-least-once form), block-driven `.each` on collections, and the numeric-helper trio `.times` / `.upto` / `.downto` on numbers. Also covers the loop-object binding via `as $loop`, its state and control methods, the prefix-free `break` / `break N` exit form, the four structural blocks (`before`, `between`, `after`, `noloop`), and the constructs that were considered and rejected (`for X in Y`, `redo`/`retry`, function-return-from-loop specials).",
	"status": "draft — main forms, loop-object binding, break with level count, and structural blocks spec'd; a couple of open questions noted (named-loop targeting for break, structural-block interactions)",
	"audience": "developers writing Caspian; parser implementers; anyone porting loop-heavy code from another language"
}}
~~~

Caspian has three ways to loop:

- **`while`** and **`until`** — repeat a body while (or until) a condition is truthy.
- **`.each`** — iterate over a collection's elements.
- **Numeric helpers** on Number — `.times`, `.upto`, `.downto`.

Any of them can be named with `as $loop` to bind a loop object that exposes iteration state and control (`$loop.count`, `$loop.index`, `$loop.break`, `$loop.next`).

## Condition-driven loops: `while` and `until`

`while` repeats its body while the condition is truthy. `until` is the negation — repeat while the condition is falsy. The condition is re-evaluated before each iteration.

~~~caspian
while $x < 10
	$x += 1
end

until $ready
	&poll
end
~~~

No `do` keyword between the condition and the body — control-flow structures own their body directly. This doc has the full `while`/`until` spec; [if-unless](https://puck.uno/requirements/syntax/if-unless) covers the sibling conditional keywords.

### Loop-at-least-once form: `begin ... while` / `begin ... until`

Both `while` and `until` also have a **loop-at-least-once** form that puts the condition after the body instead of before it. The body always runs once; the condition is checked after each iteration to decide whether to run again.

~~~caspian
begin
	$x = get_next()
	process($x)
while $x != null

begin
	$x = read_input()
	process($x)
until $x == 'quit'
~~~

- **`begin ... while $bool`** — body runs at least once, then repeats while `$bool` is truthy.
- **`begin ... until $bool`** — body runs at least once, then repeats while `$bool` is falsy.

The `begin` block has no explicit `end` — its body is terminated by the `while` or `until` clause at its own nesting level. Every construct inside (nested loops, if-chains, function calls, etc.) closes with its own `end` as usual; only the outer `begin` gets the trailing-condition terminator instead.

The `as $loop` binding works on this form too, but goes on the **`begin`** line — not on the trailing `while` or `until`. The general rule holds: `as $name` sits immediately after the block declaration, and for `begin ... while` / `begin ... until` the block is opened by `begin`.

~~~caspian
begin as $loop
	$attempt += 1
	try_connect()
while $attempt < 5
~~~

The loop controller is reachable from the first line of the body, matching where the binding is written.

Nested loops parse cleanly because the inner `while`/`until` has its own `end`. The parser only accepts a trailing `while` or `until` as the `begin` block's terminator when it appears at the `begin`'s own nesting level:

~~~caspian
begin
	while $foo
		# this inner loop closes with its own `end` below
	end
while $bool
# the trailing `while $bool` here terminates the outer `begin` block
~~~

If a `begin` block reaches the enclosing scope's end without a matching trailing `while` or `until`, that's a parse error — a `begin` block must have exactly one trailing condition clause.

## Collection iteration: `.each`

Collections provide `.each` for element-by-element iteration. `.each` is a method call with a block argument, so it uses `do (...)`:

~~~caspian
$items.each do ($item)
	puts $item
end
~~~

This doc focuses on the loop-specific behavior — the `as $loop` binding, break, structural blocks — and the block-parameter syntax the iteration methods use.

## Numeric helpers: `.times`, `.upto`, `.downto`

Numbers expose three iteration helpers. None returns a useful value; their purpose is the side effect of running the block.

| Method | Description |
|---|---|
| `.times` | Execute the block N times. The block parameter is the 0-based index. |
| `.upto($n)` | Iterate from the receiver up to `$n` inclusive. |
| `.downto($n)` | Iterate from the receiver down to `$n` inclusive. |

~~~caspian
5.times do ($i)
	puts $i        # 0 1 2 3 4 (one per line)
end

1.upto(3) do ($n)
	puts $n        # 1 2 3 (one per line)
end

10.downto(1) do ($n)
	puts $n        # 10 9 8 ... 1 (one per line)
end
~~~

These are sugar over the underlying iteration machinery — internally they behave the same as `.each` over the corresponding range and accept `as $loop` the same way.

## Naming a loop with `as`

Any loop form can be named with `as $name` to bind a **loop object** for the duration of the loop. `as $name` always appears immediately after the block declaration:

~~~caspian
$items.each do ($item) as $loop
	puts $loop.count + ': ' + $item
end
~~~

For `while` and `until`, `as` follows the condition (there's no explicit `do (...)` block to attach to):

~~~caspian
while $foo as $loop
	# $loop available inside the body
end
~~~

For numeric helpers, `as` follows the `do (...)` — the block declaration — not the receiver:

~~~caspian
5.times do ($i) as $loop
	# both $i (index from times) and $loop (loop object) available
end
~~~

The placement rule is consistent: **`as $name` sits immediately after the block declaration.** For loops with a `do (...)` block that's after the `do (...)`; for `while`/`until` where the body opens implicitly, it sits after the condition. `as` doesn't modify anything — it just binds `$name` to the loop-inspection-and-control object the loop machinery produces, so that name is reachable inside the body.

**The `as` variable is scoped to the loop.** The binding exists only inside the loop's body. Outside the loop, the name was never declared in the enclosing scope — so a reference to it there is an undeclared variable, no different from any other name that was never introduced.

~~~caspian
while ($x < 10) as $loop
	# $loop is declared here — $loop.count, $loop.break, everything works
end

# $loop is not declared in this scope — bare reference is an undeclared variable
~~~

To retain the loop object after the loop ends (e.g., to inspect the final `$loop.count` after the fact), pre-declare the variable in the outer scope:

~~~caspian
$loop = null

while ($x < 10) as $loop
	# inside the loop $loop is the loop object
end

# $loop is still in scope out here (declared above); its final iteration count
# and other end-state are accessible
puts $loop.count
~~~

### Nested loops with the same name

If an outer and inner loop are both named `as $name` with the **same** name, the inner `as` **overwrites the variable** — permanently. The compiler emits a **warning** so the overwrite is visible.

The distinction matters: it's the **variable** that's overwritten, not the outer loop object. The outer loop object still exists and keeps running; it just has no name binding pointing to it anymore.

~~~caspian
$outer_list.each do ($x) as $loop     # $loop bound to the outer loop object
	$inner_list.each do ($y) as $loop # $loop is REBOUND to the inner loop object
		puts $loop.count             # refers to the INNER loop's count
	end
	# After the inner loop ends, $loop STILL refers to the (now-finished) inner
	# loop object — not to the outer. The outer loop is still running (it has
	# more iterations to go), but $loop no longer names it.
	puts $loop.count                 # inner loop's final count (loop already ended)
	puts $loop.active?               # false — that's the INNER loop
end
~~~

To keep both loop objects reachable inside the inner body, give each a distinct name:

~~~caspian
$outer_list.each do ($x) as $outer_loop
	$inner_list.each do ($y) as $inner_loop
		puts $outer_loop.count       # outer's count
		puts $inner_loop.count       # inner's count
	end
	puts $outer_loop.count           # still the outer — no overwrite happened
end
~~~

This is the recommended pattern for any nested loops that both need loop-object access. The same-name form is legal (with a warning), but distinct names are cleaner and don't quietly lose the outer binding.

## Loop object methods

The loop object exposes state and control:

| Method | Description |
|---|---|
| `$loop.count` | Current iteration number (1-based) while the loop is running; total iteration count after the loop ends. |
| `$loop.index` | Current iteration index (0-based). |
| `$loop.active?` | `true` while the loop is running; `false` after it ends. |
| `$loop.next` | Skip to the next iteration. |
| `$loop.break` | Exit the loop. Accepts an optional value: `$loop.break $value`. |
| `$loop.return` | Alias for `$loop.break` — same behavior, same optional value form. Pick whichever name reads better in context. |

`$loop.break` and `$loop.return` are two names for the same operation — exit this loop. Both leave `$loop.active?` false and `$loop.count` equal to the iterations that ran.

### Control methods raise after the loop ends

Once the loop has ended (`$loop.active?` returns `false`), calling any of the control methods raises an error:

- `$loop.next` — no next iteration to skip to.
- `$loop.break` — nothing to exit.
- `$loop.return` — nothing to exit; nothing to return to.

The state readers (`$loop.count`, `$loop.index`, `$loop.active?`) still work on a finished loop — they report the state as of loop end (final iteration count, last index, `active?` returns `false`). Only the control methods raise, because there's no live loop for them to control.

This matters mainly when a caller retained the loop object via a pre-declared outer-scope binding and tries to reach for a control method after the loop finished:

~~~caspian
$loop = null
while ($x < 10) as $loop
	$x += 1
end

$loop.count      # fine — reports the total iterations
$loop.active?    # fine — returns false
$loop.break      # raises — the loop is not running
~~~

### The controller is a first-class object

The loop controller can be passed around like any other object — stored in a variable, handed to a function, captured in a closure. Calling `.break` or `.return $value` on it works from anywhere as long as the loop is still running.

~~~caspian
$myfunc = function ($controller)
	$controller.return 'foo'
end

$bar = while $blah as $loop
	&myfunc $loop
end

$bar    # 'foo'
~~~

Inside `$myfunc`, `$controller` is `$loop`. Calling `.return 'foo'` on it triggers a **non-local exit** — control unwinds through however many stack frames sit between the call and the loop, then resumes after the loop with `'foo'` as the loop's value. That's the same "the callee can jump" property as exceptions, except the target is a specific loop instead of the nearest matching rescue.

This composes cleanly with the raise-after-loop-ends rule: if a captured controller has `.return` (or `.break` or `.next`) invoked after the loop is over, the call raises. A controller that outlives its loop can still be inspected via the state readers (`.count`, `.index`, `.active?`) but can no longer trigger control.

### Cross-role: passing a controller across a role boundary

Passing a controller to code running in an untrusted role is a **security concern worth flagging** — but it's not an error. The recipient can call `.break` or `.return $value` on the controller and force the caller's loop to exit. That may be exactly what the developer intended (the whole point of handing the controller over might be to let the callee decide when to exit), but it might not be. Callers passing controllers across role boundaries own that decision.

**If you want to hand across a controller without granting exit capability**, wrap it in a [jail](https://puck.uno/requirements/built-in-classes/object/methods/#jail) that exposes only the state readers:

~~~caspian
&untrusted_helper $loop.obj.jail(:index, :count)
~~~

The recipient can read `.index` and `.count` (and any other state-reader you list) but can't reach `.break`, `.return`, or `.next` — the jail forwards only the named methods to the underlying controller. This is the standard [object-capability](https://puck.uno/requirements/roles/object-access) pattern applied to controllers.

**`$loop.return $value` propagates to the loop's containing call.** When the block was invoked by a method like `.each`, `.map`, `.times`, etc., the loop-controller's value becomes that method's return value. This is how a caller uses `.each` as a search:

~~~caspian
$found = $arr.each do ($val) as $loop
	if $val.matches($predicate)
		$loop.return $val
	end
end
# $found is the first matching $val, or the default result if nothing matched
~~~

### Default return: last expression of the last iteration

**When no `$loop.return` fires, a loop returns the value of the last expression evaluated in the last iteration's body.**

~~~caspian
$foo = $arr.each do ($val)
	1 + 1
end

$foo    # 2
~~~

Same rule for `while`, `until`, and the numeric helpers (`.times`, `.upto`, `.downto`) — the loop's return value is the last expression from the last iteration:

~~~caspian
$result = while $x < 10
	$x += 1
end

$result   # whatever $x += 1 evaluated to on the final iteration
~~~

Two situations follow directly from the rule:

- **A loop that runs zero iterations** returns `null` — there was no "last iteration," so there's no last expression. This includes an empty collection passed to `.each`, a `while` whose condition is false on entry, and `.times(0)`.
- **A loop whose body ends with a statement that has no value** returns `null` for that iteration. If that iteration was the last one, the loop returns `null`.

Methods that accumulate a per-iteration result (`.map` returns an array of block returns; `.keep` and `.reject` return arrays of matching elements; `.sum`, `.min_by`, etc. return their aggregated result) apply this rule per-iteration: the block's last expression IS its per-iteration return. Those methods then do their own thing with the accumulated per-iteration values — they don't fall through to "return the last iteration's block value."

**`return` (without `$loop.`) is a function exit, not a loop exit.** A bare `return` inside a loop body returns from the enclosing function. There's no special mechanism — `return` works the same inside or outside a loop. Use `$loop.break` (or `$loop.return`) when you want to exit just the loop; use bare `return` when you want to return from the enclosing function.

## `break` and `break N`

`break` exits a loop **without** needing a `$loop` reference. The bare form exits the innermost enclosing loop; `break N` exits N enclosing loops at once.

~~~caspian
$people.each do ($person)
	if $person.suspicious?
		break
	end
end
~~~

`break 2` walks out of two loops:

~~~caspian
$people.each do ($person)
	$person.addresses.each do ($address)
		if $address.matches($target)
			break 2
		end
	end
end
~~~

After `break N`, control resumes after the N-th enclosing loop. The intervening loop objects' `$loop.active?` becomes `false` and their `$loop.count` reflects the iterations that actually ran.

### Named loop objects: `$outer_loop.break`

When you name outer and inner loops with distinct `as` bindings, you can call `.break` on the specific loop object you want to exit — no need to count levels:

~~~caspian
$people.each do ($person) as $person_loop
	$person.addresses.each do ($address) as $address_loop
		if $address.matches($target)
			$person_loop.break     # exits the outer $people.each loop
		end
	end
end
~~~

This is just the `.break` method on the [loop object](#loop-object-methods) — same operation as `$loop.break`, but the receiver names which loop to exit. Advantages over `break N`:

- **Survives refactoring that changes nesting depth.** Adding or removing a wrapping loop doesn't invalidate `$person_loop.break` the way it would `break 2`.
- **Reads more directly.** `$person_loop.break` names its target; `break 2` requires the reader to count.
- **Works from arbitrary depth.** `$person_loop.break` from three or four levels in still targets `$person_loop` unambiguously.

Use whichever form reads better. `break` / `break N` is terser for shallow, stable nesting; `$loop_name.break` is safer for deeper or evolving code.

### Function boundary

`break` does **not** escape function boundaries. If a function definition encloses a loop and contains `break`, that `break` exits the loop inside the function; it does not affect any loop in the caller.

~~~caspian
function &process_each($list)
	$list.each do ($item)
		break          # exits the .each inside process_each
	end
end

$outer.each do ($x)
	&process_each($outer)   # break inside process_each does NOT
	                        # exit this .each
end
~~~

`break` **does** flow through `do ... end` blocks passed as arguments to methods like `.each`, `.times`, `.upto`. Those are blocks, not function definitions — they execute in the caller's lexical context, and `break` inside them targets the caller's loops. The first example on this page relies on this.

### Argument validation

- `break 1` is equivalent to bare `break`.
- `break 0` raises an `invalid_argument` error — breaking by zero levels is nonsense and almost always a bug.
- `break N` where N exceeds the number of enclosing loops raises `invalid_argument`. Use [named-loop targeting](#named-loop-objects-outer_loopbreak) when the depth might vary.
- The level argument is evaluated as a normal integer expression; `break $depth` works with a variable. If the runtime value is not a positive integer, the same `invalid_argument` is raised.

### Interaction with structural blocks

If `break` (or `break N`) exits a loop, the loop's `after` structural block does **not** run — `after` only runs after a complete iteration sweep. The `between` block does not run on the iteration that breaks. The `noloop` block remains a no-op (it only runs when the loop body didn't run at all).

## Structural clauses

Loops support optional structural clauses: `before`, `between`, `after`, `noloop`, and `ensure`. None of them have access to the iteration variable — they run at the loop's structural phases, not inside the iteration:

~~~caspian
$people.each do ($person)
	puts $person.name

before
	puts '--- START ---'

between
	puts '-------------'

after
	puts '--- END -----'

noloop
	puts '--- NO PEOPLE ---'

ensure
	puts '(always runs, even on exception or break)'
end
~~~

| Clause | When it runs |
|---|---|
| `before` | Once before the first iteration. |
| `between` | Between each pair of iterations — runs N-1 times when the body runs N times. Doesn't run when the body runs zero or one time. |
| `after` | Once after the last iteration, only on the normal-completion path. |
| `noloop` | Only when the collection is empty (no iterations ran). |
| `ensure` | Always runs — normal completion, exception, `break`, controller `.return`. Parallel to Ruby's `ensure` / Python's `finally`. |

`before` and `after` run whenever the body would run at least once. **`between` runs between iterations**, so it needs at least two iterations to run at all — one iteration produces zero betweens; two iterations produce one; three iterations produce two; and so on. `noloop` runs exactly when the loop body would not run at all — useful for "nothing matched" messages without an extra emptiness check around the loop. `ensure` runs on every exit path, guaranteed — use it for cleanup that must not be skipped (releasing a resource, closing a handle) whether the loop finished normally or raised.

**Scope.** Each clause runs in its own fresh scope. Variables set inside `body` are not visible in `before` / `between` / `after` / `noloop` / `ensure`. To share state across clauses, use a variable declared in the enclosing scope. Full rules in [clause-slots § Scope](https://puck.uno/requirements/syntax/clause-slots#scope-each-clause-is-its-own-scope).

**These clauses are not loop-specific.** Same set applies to `begin ... end` (single-shot forms), `function` / `closure` / `method` / `do` (any callable can carry them), spec'd once in [clause-slots](https://puck.uno/requirements/syntax/clause-slots).

## Deliberately out of scope

These were considered and explicitly excluded:

- **`for X in Y` form.** Caspian uses `.each` for iteration. No parallel `for ... in ...` block form. Every iteration is a method call on the receiver, which keeps the parser rules uniform and makes the receiver explicit at the call site.
- **`redo` / `retry`.** Ruby-style restart of the current iteration is not part of Caspian.
- **A special "return from the enclosing function" inside a loop.** Not needed — a bare `return` does exactly that, whether inside or outside a loop.

## Testing

- **`while` with truthy condition runs body** — `$i = 0; while $i < 3; $i += 1; end; $i` returns `3`.
- **`while` with false-on-entry condition never runs body** — `while false; $x = 1; end; $x` raises undeclared-variable.
- **`while` re-evaluates condition before each iteration** — a mutation inside the body that flips the condition ends the loop next check.
- **`until` runs while condition is falsy** — `$i = 0; until $i == 2; $i += 1; end; $i` returns `2`.
- **`until` with truthy-on-entry condition never runs body** — `until true; $x = 1; end; $x` raises undeclared-variable.
- **`begin ... while` runs body at least once even when condition false** — `$i = 0; begin; $i += 1 while false` — `$i` is `1`.
- **`begin ... until` runs body at least once even when condition true** — `$i = 0; begin; $i += 1 until true` — `$i` is `1`.
- **`begin` with no trailing `while`/`until` at its nesting level is a parse error for loop form** — a `begin` block terminated only by `end` is not a loop, it's a bare block.
- **`.each` on an array visits each element in order** — `[1,2,3].each do ($v); $sum += $v; end` — after seeding `$sum = 0`, `$sum` is `6`.
- **`.each` on empty array does not run body** — `[].each do ($v); $ran = true; end; $ran` raises undeclared-variable.
- **`.each` on empty array returns null** — `[].each do ($v); end` returns `null`.
- **`.each` on hash iterates entries** — the standard hash-entry iteration form covers every entry.
- **`5.times` runs body five times** — `$i = 0; 5.times do; $i += 1; end; $i` returns `5`.
- **`0.times` does not run body** — `$ran = false; 0.times do; $ran = true; end; $ran` returns `false`.
- **`.times` block param is 0-based index** — `5.times do ($i); puts $i; end` prints `0 1 2 3 4`.
- **`.upto` iterates inclusive of upper bound** — `1.upto(3) do ($n); $arr << $n; end` yields `[1, 2, 3]`.
- **`.upto` with upper less than receiver runs zero times** — `5.upto(1) do; $ran = true; end; $ran` raises undeclared-variable.
- **`.downto` iterates inclusive of lower bound** — `3.downto(1) do ($n); $arr << $n; end` yields `[3, 2, 1]`.
- **`as $loop` binds a controller inside the body** — `while true as $loop; $loop.break; end` exits cleanly.
- **`$loop.count` is 1-based during iteration** — first iteration `$loop.count` is `1`.
- **`$loop.index` is 0-based during iteration** — first iteration `$loop.index` is `0`.
- **`$loop.active?` is true during iteration and false after** — checked mid-loop returns `true`; checked from a pre-declared outer binding after the loop returns `false`.
- **`$loop.count` after loop end reports total iterations** — a pre-declared `$loop` reports the ran count after end.
- **`$loop.next` skips to next iteration** — a marker after `$loop.next` inside the body is unreached that iteration.
- **`$loop.break` exits the loop** — the statement after `$loop.break` in that iteration does not run, and no further iterations run.
- **`$loop.break $value` exits with that value** — `while true as $loop; $loop.break 'x'; end` returns `'x'`.
- **`$loop.return` is an alias for `$loop.break`** — `while true as $loop; $loop.return 'x'; end` returns `'x'`.
- **`$loop.break` on ended loop raises** — a pre-declared `$loop` called `.break` after the loop ends raises.
- **`$loop.next` on ended loop raises** — same.
- **`$loop.return` on ended loop raises** — same.
- **State readers on ended loop still work** — `$loop.count`, `$loop.index`, `$loop.active?` all succeed after loop end.
- **Bare `break` exits innermost loop** — inside a nested loop, `break` exits only the innermost.
- **`break N` exits N loops** — `break 2` inside a double-nested loop exits both.
- **`break 0` raises `invalid_argument`** — literal or dynamic.
- **`break N` where N exceeds nesting raises `invalid_argument`** — e.g. `break 3` inside a two-loop nest.
- **Bare `next` skips to next iteration of innermost loop** — statements after `next` do not run that iteration.
- **`break` does not cross function boundaries** — a `break` inside a function called from a loop does not exit the caller's loop; instead it exits or raises depending on inner scope.
- **`break` flows through `do ... end` blocks passed as arguments** — a `break` inside `.each`'s block exits the loop that owns `.each`.
- **`before` structural block runs once before first iteration** — with three iterations, `before` runs once.
- **`after` structural block runs once after last iteration** — with three iterations, `after` runs once.
- **`after` does not run when loop is exited by `break`** — a `break` mid-iteration causes `after` to be skipped.
- **`between` runs N-1 times when body runs N times** — three iterations produce two `between` runs.
- **`between` runs zero times when body runs once** — a single-iteration loop produces no `between`.
- **`noloop` runs only when body would not run at all** — `.each` on an empty array runs `noloop` once.
- **`noloop` does not run when at least one iteration ran** — a loop with one iteration does not run `noloop`.
- **Loop return value is last expression of last iteration** — `[1,2,3].each do ($v); $v * 10; end` returns `30`.
- **Zero-iteration loop returns null** — `[].each do ($v); $v; end` returns `null`.
- **Loop ending with valueless statement returns null** — an `.each` whose body's last line is `puts $v` returns `null`.
- **Bare `return` inside a loop returns from enclosing function, not the loop** — a bare `return 'fn'` inside a loop body returns from the enclosing function.
- **Nested loops with same `as` name warns and rebinds** — inner `as $loop` rebinds `$loop` to the inner controller; compiler emits a warning; outer loop keeps running.
- **Nested loops with distinct `as` names keep both bindings** — inner body can read `$outer_loop.count` and `$inner_loop.count`.
- **Named-loop `.break` exits the named loop from any depth** — `$outer_loop.break` inside two-level nest exits the outer loop.
- **Loop controller passed to another function can trigger non-local exit** — a function that receives the loop controller and calls `.return 'x'` unwinds to the loop with `'x'` as the loop's value.
- **`as $loop` variable scoped to the loop** — reading `$loop` after `end` raises undeclared-variable when not pre-declared.
- **Pre-declared `$loop` retains final state** — `$loop = null; while $x < 10 as $loop; $x += 1; end; $loop.count` returns the number of iterations.
- **Loop condition side effects run before each iteration check** — a counter in the `while` condition advances the expected number of times.

## Related

- [if-unless](https://puck.uno/requirements/syntax/if-unless) — the sibling conditional keywords `if`/`elsif`/`else` and `unless`, plus the `as $conditional` chain-exit binding.
- [bare-blocks](https://puck.uno/requirements/syntax/bare-blocks) — the `begin ... end` bare-block construct, which reuses the `begin` keyword this doc's loop-at-least-once forms also use.
- [array § method surface](https://puck.uno/requirements/built-in-classes/primitives/array/#method-surface) — `.each` and the other array methods that take blocks.
- [number](https://puck.uno/requirements/built-in-classes/primitives/number/) — the class carrying `.times`, `.upto`, `.downto`.
