# Bare blocks
<!--index: 8.7-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_bare_blocks",
	"role": "spec for the `begin ... end` bare-block construct — a standalone scoping form that groups statements without invoking a method or a loop. Covers the base form, the `as $block` controller with `.return`, the block-local variable scoping rule, and the block's return value (last expression of the body). Also disambiguates against the `begin ... while` / `begin ... until` loop-at-least-once forms, which use the same `begin` keyword but close with a trailing condition.",
	"status": "draft — form, scoping, controller, and return semantics spec'd",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

A **bare block** groups statements into a self-contained scope. It runs once, top to bottom, and returns a value — same pattern as a loop or a conditional chain, without the condition or iteration machinery.

~~~caspian
begin
	# do stuff
end
~~~

## Return value

A bare block returns **the value of the last expression evaluated in its body**. Same rule as loops and conditional chains — the block acts like an anonymous expression whose value is the last thing computed.

~~~caspian
$foo = begin
	$x = 10
	$y = 20
	$x + $y
end

$foo    # 30
~~~

If the body ends with a statement that has no value, the block returns `null`. An empty body also returns `null`.

## Variable scoping

**Variables declared inside a bare block are scoped to the block.** They come into existence at their declaration and are unreachable outside the block. From the enclosing scope, they were never declared — a bare reference is an undeclared-variable error.

~~~caspian
begin
	$temp = compute_something()
	use($temp)
end

$temp    # error — $temp was never declared in this scope
~~~

The block still **captures its enclosing scope** — variables declared outside remain reachable and writable from inside:

~~~caspian
$outer = 5

begin
	$outer = 10       # writes to the enclosing $outer
	$inner = 100      # local to the block
end

$outer    # 10 — the block's write is visible
$inner    # error — $inner was never declared in this scope
~~~

This matches the scoping rule for loops and conditional chains: introductions are block-local; captures are transparent.

## Block controller via `as $block`

The bare block accepts an `as $name` binding that produces a **block controller** — an object that lets the body exit early and hand a value back to the caller:

~~~caspian
$result = begin as $block
	# do stuff
	$block.return 'whatever'
	# anything below here does not run
end

$result    # 'whatever'
~~~

The controller's methods:

- **`$block.return $value`** — exits the block immediately; the block's value is `$value`.
- **`$block.return`** (no argument) — exits with `null` as the block's value.

`.return` on the block controller is a block-scoped exit. A bare `return` inside the body still returns from the enclosing function; the two forms don't collide.

The `as $name` sits immediately after the `begin` keyword — same placement rule as everywhere else `as` appears (right after the block declaration).

## The block controller variable is scoped to the block

Same rule as loops and conditional chains. `$block` is reachable from the first line of the body through the closing `end`. Outside the block, `$block` was never declared in the enclosing scope — a bare reference to it is an undeclared-variable error.

To retain the controller after the block ends, pre-declare the variable in the outer scope.

## Not to be confused with `begin ... while` / `begin ... until`

The `begin` keyword also opens the **loop-at-least-once** forms spec'd under [loops](https://puck.uno/documentation/requirements/syntax/loops#loop-at-least-once-form-begin-while-begin-until):

~~~caspian
# Bare block — closes with `end`
begin
	# runs once
end

# Loop-at-least-once — closes with `while` or `until`
begin
	# runs at least once, then repeats
while $condition
~~~

The parser distinguishes the two by what terminates the block. If the `begin` closes with an `end`, it's a bare block. If it closes with a trailing `while` or `until` at the `begin`'s own nesting level, it's a loop-at-least-once form. The two forms don't mix — a block can be one or the other, never both.

Every construct inside a bare block (loops, conditionals, function calls, other bare blocks) closes with its own terminator as usual.

## Clause slots

A `begin ... end` can carry the same clause slots any other block-carrying construct supports — `body` plus optional `before`, `after`, and `ensure`:

~~~caspian
begin
	# ... body ...
before
	# runs once, before body
after
	# runs once, after body completes normally
ensure
	# always runs — normal completion, exception, controller `.return`
end
~~~

**`between` and `noloop` are not accepted on a bare `begin`.** Those clauses have no meaning on a single-shot block (no "between iterations", no "collection was empty" state); declaring them on a bare `begin` raises. They apply only to loops. The full clause vocabulary and rules — including scope semantics and the `after` vs `ensure` distinction — are spec'd once in [clause-slots](https://puck.uno/documentation/requirements/syntax/clause-slots).

## Use cases

- **Bounded local scope.** Introduce a few temporary bindings, do some work, and let them fall out of scope cleanly — no need to structure that as a function.
- **Expression from multiple statements.** When a value needs to be built up over a few lines, the block acts as an expression whose value is the final computation.
- **Early exit from a scope.** With `as $block`, the body can `$block.return $value` from inside a nested condition or loop without unwinding through the enclosing function.
- **Grouping with a controller.** When a chunk of code needs its own exit path but doesn't fit as an `if`-chain or a loop, the bare block + controller is the general-purpose form.

## Testing

- **Empty bare block parses and returns null** — `begin; end` parses; evaluated value is `null`.
- **Single-statement bare block returns that statement's value** — `begin; 42; end` returns `42`.
- **Multi-statement bare block returns last expression** — `begin; 1; 2; 3; end` returns `3`.
- **Bare block usable as expression on right of `=`** — `$foo = begin; $x = 10; $y = 20; $x + $y; end` sets `$foo` to `30`.
- **Body ending in a valueless statement returns null** — a `begin` block whose last line is a bare `puts` (which returns `null`) evaluates to `null`.
- **Locally-declared variable does not leak out** — `begin; $temp = 1; end; $temp` raises undeclared-variable in the outer scope.
- **Enclosing variable is writable from inside** — `$outer = 5; begin; $outer = 10; end; $outer` returns `10`.
- **Enclosing variable is readable from inside** — `$outer = 7; $inner = begin; $outer + 1; end; $inner` returns `8`.
- **`as $block` binds a controller reachable in the body** — `begin as $block; $block.active?; end` (or equivalent state-reader call) does not raise.
- **`$block.return $value` exits the block with that value** — `begin as $block; $block.return 'foo'; 'never'; end` returns `'foo'`.
- **`$block.return` with no argument exits with null** — `begin as $block; $block.return; end` returns `null`.
- **Statements after `$block.return` do not run** — a side effect on the line after `$block.return` never fires.
- **Bare `return` inside a block returns from the enclosing function** — a bare `return 'fn'` inside a bare block causes the enclosing function to return `'fn'`, not just the block.
- **Controller name is scoped to the block** — reading `$block` after the `end` raises undeclared-variable.
- **Pre-declared controller survives block end** — `$block = null; begin as $block; end; $block` returns the controller object.
- **`as $name` is optional** — a plain `begin ... end` with no `as` parses and works.
- **`as` name must sit immediately after `begin`** — `begin` followed by a body line and then `as $block` on a later line is a parse error.
- **Nested bare blocks each carry their own controller** — inner and outer `as $b` bindings each refer to their own block; inner `.return` exits only the inner block.
- **Inner controller shadows outer with same name** — `begin as $b; begin as $b; $b.return 1; end; end` — inner `$b.return` exits only the inner block.
- **Nested block: outer block continues after inner ends** — statements after the inner `end` still execute in the outer block.
- **`begin ... end` with no trailing condition is a bare block, not a loop** — a `begin` closed by `end` (not by `while`/`until`) parses as bare-block.
- **`begin ... while $cond` is a loop, not a bare block** — a `begin` closed by trailing `while $cond` parses as loop-at-least-once, not bare block.
- **Trailing `while` inside a nested inner block does not terminate the outer `begin`** — a `while` at a deeper nesting level does not close the outer `begin` block.
- **Bare block value composes with arithmetic** — `1 + begin; 2; end` returns `3`.
- **Bare block value composes as function argument** — passing `begin; 5; end` as an argument passes `5`.

## Related

- [Loops](https://puck.uno/documentation/requirements/syntax/loops) — the `begin ... while` and `begin ... until` loop forms, which reuse the `begin` keyword but close with a trailing condition.
- [if and unless](https://puck.uno/documentation/requirements/syntax/if-unless) — the conditional chains, which follow the same `as $conditional` / `.return` pattern.
- [Clause slots](https://puck.uno/documentation/requirements/syntax/clause-slots) — the `body` / `before` / `between` / `after` / `noloop` / `ensure` vocabulary, applied uniformly to bare blocks, loops, and callables.
