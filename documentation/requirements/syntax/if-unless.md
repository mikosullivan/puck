# if and unless
<!--index: 7-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_if_and_unless",
	"role": "spec for Caspian's conditional keywords `if` (with `elsif`/`elseif`/`else`) and `unless` — including the conditional-object binding via `as $name` that lets any branch of an if-chain (or unless-block) exit the chain and hand a value back to the caller. Loop-control constructs (`while`, `until`, `break`, `next`) live in the loops doc, not here.",
	"audience": "parser implementers; developers writing Caspian"
}}
~~~

~~~caspian
if $age < 13
	puts 'child'
elsif $age < 18
	puts 'teen'
else
	puts 'adult'
end

unless $authorized
	puts 'access denied'
end
~~~

`elsif` and `elseif` are both accepted. `unless` is the negation of `if` — its body runs when the condition is falsy. There is no `for X in Y` — iterate by calling `.each` on a collection; every loop construct (including `.each`, `while`, `until`) is spec'd in [loops](https://puck.uno/documentation/requirements/syntax/loops).

## Conditional object via `as`

`if` and `unless` blocks can be named with `as $name` to bind a **conditional object** for the duration of the whole if-chain. The binding sits on the opening `if` (or `unless`); it cannot be attached to an `elsif` or `else`. The object gives every branch a way to exit the chain and optionally hand a value back to the caller.

~~~caspian
$foo = if $bar as $conditional
	$conditional.return 'whatever'
end

$foo == 'whatever'    # true
~~~

The primary method is `$conditional.return`:

- `$conditional.return $value` — exits the entire if-chain immediately; the chain's value is `$value`.
- `$conditional.return` (no argument) — exits with `null` as the chain's value.

`.return` on the conditional object is a chain-scoped exit, not a function return. A bare `return` inside a conditional body still returns from the enclosing function.

The conditional binding is available in every branch of the same chain — the `if`, every `elsif`, and the `else`:

~~~caspian
$label = if $age < 13 as $tier
	$tier.return 'child'
elsif $age < 18
	$tier.return 'teen'
else
	$tier.return 'adult'
end
~~~

The `as $name` cannot be placed on `elsif` or `else`; only the opening `if` (or `unless`) accepts it. All branches share the one conditional object.

Explicit `.return` is optional — when a branch doesn't call `.return`, the branch's last-expression value becomes the chain's value in the usual way. Explicit `.return` is useful when the exit needs to happen from inside a nested expression, when the chain sits inside a larger expression whose value depends on which branch ran, or when a branch has multiple statements and the "return this value" intent should be explicit rather than implicit-last-expression.

Scoping follows the same rule as `as` on loops: the conditional variable is declared inside the chain's body and unreachable outside. A bare reference to it in the enclosing scope is an undeclared-variable error — the name was never introduced there. Pre-declare in the outer scope if you need to inspect the object afterward.

## Testing

- **`if` runs body when condition is truthy** — `if true; 1; else; 2; end` returns `1`.
- **`if` runs `else` when condition is falsy** — `if false; 1; else; 2; end` returns `2`.
- **`if` with no `else` and false condition returns null** — `if false; 1; end` returns `null`.
- **`if` with no `else` and true condition returns body value** — `if true; 1; end` returns `1`.
- **`elsif` runs when its condition is truthy and prior branches were falsy** — `if false; 1; elsif true; 2; else; 3; end` returns `2`.
- **`elsif` is skipped when a prior branch already ran** — `if true; 1; elsif true; 2; end` returns `1` and the second condition is not evaluated.
- **`elsif` short-circuits later conditions once one matches** — the condition of a later `elsif` is not evaluated after an earlier branch matches.
- **`elseif` is a synonym for `elsif`** — `if false; 1; elseif true; 2; end` returns `2` and produces identical CaspianJ to the `elsif` form.
- **Chain of multiple `elsif` branches evaluates in order** — first truthy branch runs.
- **`else` runs when every prior branch was falsy** — `if false; 1; elsif false; 2; else; 3; end` returns `3`.
- **`unless` runs body when condition is falsy** — `unless false; 1; end` returns `1`.
- **`unless` skips body when condition is truthy** — `unless true; 1; end` returns `null`.
- **`unless` with `else`** — `unless true; 1; else; 2; end` returns `2`.
- **Condition side effects run exactly once per branch check** — a counter incremented inside the `if` condition increments once per evaluation, not more.
- **Non-boolean truthy value triggers `if` body** — `if 0; 'ran'; end` returns `'ran'` (per the truthy-and-falsy rule).
- **`null` condition triggers `else`** — `if null; 1; else; 2; end` returns `2`.
- **`as $conditional` binds a controller in every branch** — `if $x as $c; $c.return 'a'; elsif $y; $c.return 'b'; else; $c.return 'c'; end` — the branch that runs exits with its value.
- **`$conditional.return $value` exits the chain with that value** — `if true as $c; $c.return 'x'; 'never'; end` returns `'x'`.
- **`$conditional.return` with no argument exits with null** — `if true as $c; $c.return; end` returns `null`.
- **Statements after `$conditional.return` do not run** — a side effect after `$c.return` never fires.
- **Bare `return` inside a conditional body returns from the enclosing function** — a plain `return 'x'` inside an `if` returns from the function, not the chain.
- **`as` on `elsif` is a parse error** — `if $x; ... elsif $y as $c` fails to parse.
- **`as` on `else` is a parse error** — `if $x; ... else as $c` fails to parse.
- **`as` binding scoped to the chain** — `if true as $c; end; $c` raises undeclared-variable outside.
- **Pre-declared `$c` survives the chain** — `$c = null; if true as $c; end; $c` returns the conditional-controller object.
- **Implicit last-expression return works without `.return`** — `if true; 42; end` returns `42` without any `.return` call.
- **`unless` with `as $conditional` binding** — `unless false as $c; $c.return 'ran'; end` returns `'ran'`.
- **Unterminated `if` raises at parse time** — `if $x; 1` with no matching `end` fails to parse.
- **`if` with unparseable condition raises at parse time** — `if )` fails to parse.
- **Empty `if` body returns null** — `if true; end` returns `null`.
- **`if` chain nested inside a body** — an inner `if ... end` inside an outer `if` body evaluates independently; its `end` closes only the inner chain.
