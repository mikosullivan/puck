# Operators

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"categories": ["method_operators", "binary_operators", "unary_operators",
		"ternary_operator"],
	"notes": ["ternary_is_single_special_case_not_registered_in_scope"]
}}
~~~

Charlie has three categories of operators:

1. **Method operators** — operators that are methods on a type (`+`, `==`, `[]`, etc.)
2. **Binary operators** — bare word or symbolic operators registered in the scope
3. **Unary operators** — single-operand operators registered in the scope
4. **Ternary operator** — `?:` is a single special case handled by the parser

---

<a id="method-operators"></a>
## Method Operators

~~~json
{"vibecode": {
	"section": "method_operators",
	"examples": ["+", "-", "==", "[]"],
	"resolution": "through_receiver_type_method_table",
	"form": "$foo + $bar == $foo.+($bar)"
}}
~~~

Operators like `+`, `-`, `==`, and `[]` are methods on specific types. `$foo + $bar`
is a method call on `$foo` with `$bar` as the argument. The interpreter resolves these
through the receiver's type method table.

See the individual type docs for the operators each type supports.

---

<a id="binary-operators"></a>
## Binary Operators

~~~json
{"vibecode": {
	"section": "binary_operators",
	"registration": "scope.operators['name'] = 'uns_class'",
	"resolution_order": "method_on_receiver_first_then_scope_operators",
	"evaluator_contract": "evaluate method with two lazy params",
	"precedence": "left_to_right_no_precedence_table_use_parens",
	"short_circuit": "via_lazy_params_caller_controls_evaluation"
}}
~~~

A binary operator sits between two expressions:

```
$foo and $bar
$foo assimilates $bar
$foo && $bar
```

Binary operators are registered in the scope's operator table:

```
scope.operators['and']        = 'charlie.uno/and'
scope.operators['or']         = 'charlie.uno/or'
scope.operators['assimilates'] = 'borg.com/assimilates'
```

<a id="resolution"></a>
### Resolution

When the interpreter encounters `$foo OP $bar`, it first checks whether `OP` is a method
on `$foo`'s type. If it is, it calls the method. If not, it looks up `OP` in
`scope.operators` and treats it as a binary operator.

This means method operators take precedence over binary operators. If a developer defines
a method named `&&` on a custom class, `$foo && $bar` will call that method rather than
the binary operator. This is intentional — developers who do this can deal with the
consequences.

<a id="evaluator-classes"></a>
### Evaluator Classes

Every binary operator maps to an evaluator class. The class must implement an `evaluate`
method that takes two lazy parameters — one for each operand:

```
class 'charlie.uno/and'
    function &evaluate($left: {lazy: true}, $right: {lazy: true}) do
        if (! $left.call)
            return false
        end

        return $right.call
    end
end
```

Both operands are wrapped in zero-argument blocks before the call. The evaluator calls
them selectively, enabling short-circuit evaluation — `$right.call` is never reached if
`$left.call` returns false.

`$foo and $bar` desugars to:

```
$evaluator = charlie.uno/and.new()
$evaluator.evaluate() do
    $foo
end do
    $bar
end
```

<a id="precedence"></a>
### Precedence

Binary operators are evaluated left to right. There is no precedence table. Use
parentheses to control evaluation order:

```
$foo and ($bar or $gup)
```

<a id="custom-binary-operators"></a>
### Custom Binary Operators

Any developer can register a custom binary operator in the current scope:

```
scope.operators['assimilates'] = 'borg.com/assimilates'
```

The evaluator class follows the same contract as built-in operators — implement
`evaluate` with two lazy parameters.

---

<a id="unary-operators"></a>
## Unary Operators

~~~json
{"vibecode": {
	"section": "unary_operators",
	"registration": "scope.unary_operators['name'] = 'uns_class'",
	"evaluator_contract": "evaluate method with one lazy param",
	"built_in": ["not", "!"]
}}
~~~

A unary operator sits before a single expression:

```
not $foo
! $bar
```

Unary operators are registered in the scope's unary operator table:

```
scope.unary_operators['not'] = 'charlie.uno/not'
scope.unary_operators['!']   = 'charlie.uno/not'
```

Evaluator classes take a single lazy parameter:

```
class 'charlie.uno/not'
    function &evaluate($operand: {lazy: true}) do
        return ! $operand.call
    end
end
```

---

<a id="built-in-operators"></a>
## Built-in Operators

~~~json
{"vibecode": {
	"section": "built_in_operators",
	"binary": {
		"and/&&": "charlie.uno/and",
		"or/||": "charlie.uno/or",
		"xor": "charlie.uno/xor",
		"nand": "charlie.uno/nand",
		"nor": "charlie.uno/nor",
		"xnor": "charlie.uno/xnor"
	},
	"unary": {
		"not/!": "charlie.uno/not"
	}
}}
~~~

<a id="binary"></a>
### Binary

| Operator | Class | Description |
|----------|-------|-------------|
| `and` / `&&` | `charlie.uno/and` | Logical AND. Short-circuits. |
| `or` / `\|\|` | `charlie.uno/or` | Logical OR. Short-circuits. |
| `xor` | `charlie.uno/xor` | Logical XOR. |
| `nand` | `charlie.uno/nand` | Logical NAND. |
| `nor` | `charlie.uno/nor` | Logical NOR. |
| `xnor` | `charlie.uno/xnor` | Logical XNOR. |

<a id="unary"></a>
### Unary

| Operator | Class | Description |
|----------|-------|-------------|
| `not` / `!` | `charlie.uno/not` | Logical NOT. |

---

<a id="ternary-operator"></a>
## Ternary Operator

~~~json
{"vibecode": {
	"section": "ternary_operator",
	"operator": "?:",
	"implementation": "handled_by_parser_not_scope_operator_tables",
	"overrideable": false,
	"desugars_to": "if_expression"
}}
~~~

`?:` is a single special case handled directly by the parser. It is not registered in
the scope operator tables and cannot be overridden.

```
$result = $condition ? 'yes' : 'no'
```

The parser desugars this to an if-expression:

```
$result = if ($condition)
    'yes'
else
    'no'
end
```

---

<a id="open-questions"></a>
## Open Questions

- Should `scope.operators` be inheritable — i.e. does a child scope see parent scope
  operators automatically?
- Can operators be removed from a scope, or only added?
