# if and unless
<!--index: 7-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_if_and_unless",
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

`elsif` and `elseif` are both accepted. `unless` is the negation of `if` — its body runs when the condition is falsy. There is no `for X in Y` — iterate by calling `.each` on a collection; every loop construct (including `.each`, `while`, `until`) is spec'd in [loops](https://puck.uno/documentation/requirements/caspian/syntax/loops).

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
