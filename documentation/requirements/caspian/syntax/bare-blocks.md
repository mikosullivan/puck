# Bare blocks
<!--index: 8.7-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_bare_blocks",
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

The `begin` keyword also opens the **loop-at-least-once** forms spec'd under [loops](https://puck.uno/documentation/requirements/caspian/syntax/loops#loop-at-least-once-form-begin-while-begin-until):

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

## Use cases

- **Bounded local scope.** Introduce a few temporary bindings, do some work, and let them fall out of scope cleanly — no need to structure that as a function.
- **Expression from multiple statements.** When a value needs to be built up over a few lines, the block acts as an expression whose value is the final computation.
- **Early exit from a scope.** With `as $block`, the body can `$block.return $value` from inside a nested condition or loop without unwinding through the enclosing function.
- **Grouping with a controller.** When a chunk of code needs its own exit path but doesn't fit as an `if`-chain or a loop, the bare block + controller is the general-purpose form.

## Related

- [Loops](https://puck.uno/documentation/requirements/caspian/syntax/loops) — the `begin ... while` and `begin ... until` loop forms, which reuse the `begin` keyword but close with a trailing condition.
- [if and unless](https://puck.uno/documentation/requirements/caspian/syntax/if-unless) — the conditional chains, which follow the same `as $conditional` / `.return` pattern.
