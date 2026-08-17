# Loops
<!--index: 8.5-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_loops",
	"role": "spec for every loop construct in Caspian in one place — the condition-driven `while` and `until` (both in the pre-body form and the post-body `begin ... while` / `begin ... until` loop-at-least-once form), block-driven `.each` on collections, and the numeric-helper trio `.times` / `.upto` / `.downto` on numbers. Iterator objects, `break`, `next`, `break N`, and the `as $loop` binding are spec'd in [iterators](tag:iterators).",
	"status": "draft — main forms spec'd; iterator surface (break / next / break N / as $loop) lives in the iterators doc",
	"audience": "developers writing Caspian; parser implementers; anyone porting loop-heavy code from another language"
}}
~~~

Caspian has three ways to loop:

- **`while`** and **`until`** — repeat a body while (or until) a condition is truthy.
- **`.each`** — iterate over a collection's elements.
- **Numeric helpers** on Number — `.times`, `.upto`, `.downto`.

Every primitive loop produces an iterator. Early exit (`break`, `break N`, break-with-value), iteration-skipping (`next`, `next N`), and binding the iterator to a name via `as $loop` are spec'd in [iterators](tag:iterators); this doc covers the surface loop constructs themselves.

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

The block runs once per element; iteration continues until the collection is exhausted.

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

These are sugar over the underlying iteration machinery — internally they behave the same as `.each` over the corresponding range.

## Deliberately out of scope

Considered and permanently excluded from Caspian's loop syntax:

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
- **Loop return value is last expression of last iteration** — `[1,2,3].each do ($v); $v * 10; end` returns `30`.
- **Zero-iteration loop returns null** — `[].each do ($v); $v; end` returns `null`.
- **Loop ending with valueless statement returns null** — an `.each` whose body's last line is `puts $v` returns `null`.
- **Bare `return` inside a loop returns from enclosing function** — a bare `return 'fn'` inside a loop body returns from the enclosing function.
- **Loop condition side effects run before each iteration check** — a counter in the `while` condition advances the expected number of times.

## Related

- [iterators](tag:iterators) — the iterator surface produced by every primitive loop: `break`, `next`, `break N`, break-with-value, the `as $loop` binding, `iterate` and `yield`, and passing iterators to other functions.
- [if-unless](https://puck.uno/requirements/syntax/if-unless) — the sibling conditional keywords `if`/`elsif`/`else` and `unless`, plus the `as $conditional` chain-exit binding.
- [bare-blocks](https://puck.uno/requirements/syntax/bare-blocks) — the `begin ... end` bare-block construct, which reuses the `begin` keyword this doc's loop-at-least-once forms also use.
- [array § method surface](https://puck.uno/requirements/built-in-classes/primitives/array/#method-surface) — `.each` and the other array methods that take blocks.
- [number](https://puck.uno/requirements/built-in-classes/primitives/number/) — the class carrying `.times`, `.upto`, `.downto`.
