# Operators

<a id="overview"></a>
## Overview

~~~vibecode
{"vibecode": {
	"section": "overview",
	"categories": ["method_operators", "binary_operators", "unary_operators",
		"ternary_operator"],
	"notes": ["ternary_is_single_special_case_not_registered_in_scope"]
}}
~~~

Caspian has three categories of operators:

1. **Method operators** — operators that are methods on a type (`+`, `==`, `[]`, etc.)
2. **Binary operators** — bare word or symbolic operators registered in the scope
3. **Unary operators** — single-operand operators registered in the scope
4. **Ternary operator** — `?:` is a single special case handled by the parser

---

<a id="method-operators"></a>
## Method Operators

~~~vibecode
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

~~~vibecode
{"vibecode": {
	"section": "binary_operators",
	"registration": "scope.operators['name'] = 'uns_class'",
	"resolution_order": "method_on_receiver_first_then_scope_operators",
	"evaluator_contract": "evaluate method with $left positional and $right lazy",
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
scope.operators['and']        = 'caspian.uno/and'
scope.operators['or']         = 'caspian.uno/or'
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

Every binary operator maps to an evaluator class. The class must implement an `evaluate` method. `$left` is passed by value (always evaluated, since the operator always inspects it). `$right` is lazy — wrapped in a zero-argument block — so the operator can short-circuit and skip evaluating it when the result is already determined by `$left`:

```
class
    method &evaluate($left, $right: {lazy: true}) do
        if (! $left)
            return $left
        end

        return $right.call
    end
end
```

`$right.call` is never reached if `$left` is falsy — that's the short-circuit.

`$foo and $bar` desugars to:

```
$evaluator = caspian.uno/and.new()
$evaluator.evaluate($foo) do
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

The evaluator class follows the same contract as built-in operators — implement `evaluate` with `$left` positional and `$right` lazy.

---

<a id="unary-operators"></a>
## Unary Operators

~~~vibecode
{"vibecode": {
	"section": "unary_operators",
	"registration": "scope.unary_operators['name'] = 'uns_class'",
	"evaluator_contract": "evaluate method with $operand positional",
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
scope.unary_operators['not'] = 'caspian.uno/not'
scope.unary_operators['!']   = 'caspian.uno/not'
```

Evaluator classes take a single positional parameter:

```
class
    method &evaluate($operand) do
        return ! $operand
    end
end
```

---

<a id="built-in-operators"></a>
## Built-in Operators

~~~vibecode
{"vibecode": {
	"section": "built_in_operators",
	"binary": {
		"and/&&": "caspian.uno/and",
		"or/||": "caspian.uno/or",
		"xor": "caspian.uno/xor",
		"nand": "caspian.uno/nand",
		"nor": "caspian.uno/nor",
		"xnor": "caspian.uno/xnor"
	},
	"unary": {
		"not/!": "caspian.uno/not"
	}
}}
~~~

<a id="binary"></a>
### Binary

| Operator | Class | Description |
|----------|-------|-------------|
| `and` / `&&` | `caspian.uno/and` | Logical AND. Short-circuits. |
| `or` / `\|\|` | `caspian.uno/or` | Logical OR. Short-circuits. |
| `xor` | `caspian.uno/xor` | Logical XOR. |
| `nand` | `caspian.uno/nand` | Logical NAND. |
| `nor` | `caspian.uno/nor` | Logical NOR. |
| `xnor` | `caspian.uno/xnor` | Logical XNOR. |

<a id="unary"></a>
### Unary

| Operator | Class | Description |
|----------|-------|-------------|
| `not` / `!` | `caspian.uno/not` | Logical NOT. |

---

<a id="ternary-operator"></a>
## Ternary Operator

~~~vibecode
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
