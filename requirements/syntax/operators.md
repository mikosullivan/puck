# Operators
<!--index: 5-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_operators",
	"role": "spec for Caspian's operator surface — arithmetic, comparison, logical, ternary; the no-precedence-table rule; short-circuit behavior of and/or",
	"audience": "parser implementers; developers writing Caspian; formatter authors handling operator lines"
}}
~~~

| Category | Operators |
|---|---|
| Arithmetic | `+`, `-`, `*`, `/`, `%`, `**` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Logical | `and` (aka `&&`), `or` (aka <code>&#124;&#124;</code>), `not` (aka `!`) |
| Ternary | `$cond ? $yes : $no` |
| Mutation | `<+` (append) |

**No precedence table.** Operators evaluate left to right. **Use parentheses** to control grouping — trying to remember a precedence chart is exactly the kind of thing Caspian's design avoids.

~~~caspian
$result = ($a and $b) or $c
~~~

Arithmetic and comparison operators dispatch as methods on the left-hand operand. `and`/`or` short-circuit; the right-hand side is only evaluated when needed.

## `<+` append

`$lhs <+ $value` appends `$value` to `$lhs`. The LHS is the receiver, the RHS is the arg — dispatch works like any other method call on the receiver's class. On arrays it pushes to the end; other classes can implement their own `<+` if the append semantic makes sense for them.

~~~caspian
$arr = []
$arr <+ 'first'
$arr <+ 'second'
$arr                       # ['first', 'second']

$obj.items <+ $new_item    # LHS can be a property chain
$hash['queue'] <+ 'task'   # or a subscript
~~~

The LHS is any expression that resolves to a receiver — a variable, a property chain, a subscript, or a `%(url)`-shaped fetch lookup. The RHS is any expression.

Whitespace on both sides is recommended for readability; `$x <+ 5` and `$x<+5` both parse. The tokenizer treats `<+` as a single two-char operator token wherever it appears — `$x <+ 5` is not `$x < (+5)`. Write `$x < (+5)` explicitly if that's what you mean.

**Related built-in method surface:** [`Array § .push` and `.import`](https://puck.uno/requirements/built-in-classes/primitives/array/#the-guaranteed-method-surface) — `<+` on an array is equivalent to `.push`.

## Testing

- **Integer addition** — `2 + 3` returns `5`.
- **Integer subtraction** — `5 - 3` returns `2`.
- **Integer multiplication** — `4 * 3` returns `12`.
- **Integer division of exact multiples** — `10 / 2` returns `5`.
- **Integer modulo** — `10 % 3` returns `1`.
- **Integer exponent** — `2 ** 8` returns `256`.
- **Float addition** — `1.5 + 2.25` returns `3.75`.
- **Mixed int + float returns float** — `1 + 2.5` returns `3.5`.
- **Negative number arithmetic** — `-5 + 3` returns `-2`.
- **Unary minus on variable** — `$x = 5; -$x` returns `-5`.
- **Division by zero raises** — `1 / 0` raises.
- **Modulo by zero raises** — `1 % 0` raises.
- **`==` on equal integers returns true** — `2 == 2` is `true`.
- **`==` on unequal integers returns false** — `2 == 3` is `false`.
- **`!=` complement of `==`** — `2 != 3` is `true`; `2 != 2` is `false`.
- **`<`, `<=`, `>`, `>=` on numbers** — each returns the expected boolean.
- **`==` on arrays recursively compares elements** — `[1,2,3] == [1,2,3]` is `true`; `[1,2,3] == [1,2,4]` is `false`.
- **`==` on hashes recursively compares entries** — matching hashes return `true`; differing hashes return `false`.
- **`==` on strings compares by value** — `'abc' == 'abc'` is `true`.
- **`and` returns first falsy operand** — `true and false` is `false`; `1 and 2` returns the truthy right side per short-circuit.
- **`or` returns first truthy operand** — `false or 5` returns `5`; `null or 'x'` returns `'x'`.
- **`&&` alias for `and`** — `true && false` behaves identically to `true and false`.
- **`||` alias for `or`** — `false || 5` behaves identically to `false or 5`.
- **`not` inverts truthy to false** — `not true` is `false`; `not 0` is `false` (per truthy-and-falsy).
- **`not` inverts falsy to true** — `not false` is `true`; `not null` is `true`.
- **`!` alias for `not`** — `!true` is `false`.
- **`and` short-circuits: right side not evaluated when left is falsy** — a side-effect counter in the right operand does not advance when left is `false`.
- **`or` short-circuits: right side not evaluated when left is truthy** — a side-effect counter in the right operand does not advance when left is `true`.
- **Ternary evaluates truthy branch when condition is truthy** — `true ? 'a' : 'b'` returns `'a'`.
- **Ternary evaluates falsy branch when condition is falsy** — `false ? 'a' : 'b'` returns `'b'`.
- **Ternary evaluates only the selected branch** — a side effect in the non-selected branch does not fire.
- **Left-to-right evaluation without parens** — `2 + 3 * 4` returns `20`, not `14` — no precedence table.
- **Parentheses control grouping** — `2 + (3 * 4)` returns `14`.
- **Arithmetic on non-numeric raises** — `'a' + 1` raises (numeric operator on string LHS).
- **Comparison on incompatible types raises** — `'a' < 1` raises.
- **Compound expression using parens for logical grouping** — `($a and $b) or $c` parses; evaluates left group, then `or`s with `$c`.
- **Unary `-` on non-numeric raises** — `-'x'` raises.
- **`**` right-associative or per-left-to-right rule** — `2 ** 3 ** 2` evaluates left-to-right per the no-precedence rule; parens required if a different grouping is intended.
- **`<+` appends to an array** — `$arr = []; $arr <+ 'a'; $arr <+ 'b'; $arr` returns `['a', 'b']`.
- **`<+` dispatches on the receiver** — `$arr <+ 'x'` calls the receiver's `<+` method; a class that doesn't implement it raises.
- **`<+` on a subscript LHS** — `$h = {items: []}; $h['items'] <+ 'x'; $h['items']` returns `['x']`.
- **`<+` on a property-chain LHS** — a chained-attribute expression on the LHS resolves and dispatches on the resulting receiver.
- **`<+` token is two chars, not `<` followed by unary `+`** — `$x <+ 5` parses as append, not `$x < (+5)`.
