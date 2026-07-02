# Operators
<!--index: 5-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_operators",
	"role": "spec for Caspian's operator surface — arithmetic, comparison, logical, ternary; the no-precedence-table rule; short-circuit behavior of and/or",
	"audience": "parser implementers; developers writing Caspian; formatter authors handling operator lines"
}}
~~~

| Category | Operators |
|---|---|
| Arithmetic | `+`, `-`, `*`, `/`, `%`, `**` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Logical | `and` (aka `&&`), `or` (aka `\|\|`), `not` (aka `!`) |
| Ternary | `$cond ? $yes : $no` |

**No precedence table.** Operators evaluate left to right. **Use parentheses** to control grouping — trying to remember a precedence chart is exactly the kind of thing Caspian's design avoids.

~~~caspian
$result = ($a and $b) or $c
~~~

Arithmetic and comparison operators dispatch as methods on the left-hand operand. `and`/`or` short-circuit; the right-hand side is only evaluated when needed.
