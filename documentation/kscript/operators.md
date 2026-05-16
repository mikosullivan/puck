# Operators

## Overview (Tora Ziyal II)

```
vibecode: {
	"section": "overview",
	"categories": ["method_operators", "binary_operators", "unary_operators",
		"ternary_operator"],
	"notes": ["ternary_is_single_special_case_not_registered_in_scope"]
}
```

KScript has three categories of operators:

1. **Method operators** — operators that are methods on a type (`+`, `==`, `[]`, etc.)
2. **Binary operators** — bare word or symbolic operators registered in the scope
3. **Unary operators** — single-operand operators registered in the scope
4. **Ternary operator** — `?:` is a single special case handled by the parser

---

## Method Operators (Pa'Dar)

```
vibecode: {
	"section": "method_operators",
	"examples": ["+", "-", "==", "[]"],
	"resolution": "through_receiver_type_method_table",
	"form": "$foo + $bar == $foo.+($bar)"
}
```

Operators like `+`, `-`, `==`, and `[]` are methods on specific types. `$foo + $bar`
is a method call on `$foo` with `$bar` as the argument. The interpreter resolves these
through the receiver's type method table.

See the individual type docs for the operators each type supports.

---

## Binary Operators (Pa'Dar Cardassian)

```
vibecode: {
	"section": "binary_operators",
	"registration": "scope.operators['name'] = 'uns_class'",
	"resolution_order": "method_on_receiver_first_then_scope_operators",
	"evaluator_contract": "evaluate method with two lazy params",
	"precedence": "left_to_right_no_precedence_table_use_parens",
	"short_circuit": "via_lazy_params_caller_controls_evaluation"
}
```

A binary operator sits between two expressions:

```
$foo and $bar
$foo assimilates $bar
$foo && $bar
```

Binary operators are registered in the scope's operator table:

```
scope.operators['and']        = 'kscript.uno/and'
scope.operators['or']         = 'kscript.uno/or'
scope.operators['assimilates'] = 'borg.com/assimilates'
```

### Resolution

When the interpreter encounters `$foo OP $bar`, it first checks whether `OP` is a method
on `$foo`'s type. If it is, it calls the method. If not, it looks up `OP` in
`scope.operators` and treats it as a binary operator.

This means method operators take precedence over binary operators. If a developer defines
a method named `&&` on a custom class, `$foo && $bar` will call that method rather than
the binary operator. This is intentional — developers who do this can deal with the
consequences.

### Evaluator Classes

Every binary operator maps to an evaluator class. The class must implement an `evaluate`
method that takes two lazy parameters — one for each operand:

```
class 'kscript.uno/and'
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
$evaluator = kscript.uno/and.new()
$evaluator.evaluate() do
    $foo
end do
    $bar
end
```

### Precedence

Binary operators are evaluated left to right. There is no precedence table. Use
parentheses to control evaluation order:

```
$foo and ($bar or $gup)
```

### Custom Binary Operators

Any developer can register a custom binary operator in the current scope:

```
scope.operators['assimilates'] = 'borg.com/assimilates'
```

The evaluator class follows the same contract as built-in operators — implement
`evaluate` with two lazy parameters.

---

## Unary Operators (Pa'Dar Jasad)

```
vibecode: {
	"section": "unary_operators",
	"registration": "scope.unary_operators['name'] = 'uns_class'",
	"evaluator_contract": "evaluate method with one lazy param",
	"built_in": ["not", "!"]
}
```

A unary operator sits before a single expression:

```
not $foo
! $bar
```

Unary operators are registered in the scope's unary operator table:

```
scope.unary_operators['not'] = 'kscript.uno/not'
scope.unary_operators['!']   = 'kscript.uno/not'
```

Evaluator classes take a single lazy parameter:

```
class 'kscript.uno/not'
    function &evaluate($operand: {lazy: true}) do
        return ! $operand.call
    end
end
```

---

## Built-in Operators (Jasad)

```
vibecode: {
	"section": "built_in_operators",
	"binary": {
		"and/&&": "kscript.uno/and",
		"or/||": "kscript.uno/or",
		"xor": "kscript.uno/xor",
		"nand": "kscript.uno/nand",
		"nor": "kscript.uno/nor",
		"xnor": "kscript.uno/xnor"
	},
	"unary": {
		"not/!": "kscript.uno/not"
	}
}
```

### Binary

| Operator | Class | Description |
|----------|-------|-------------|
| `and` / `&&` | `kscript.uno/and` | Logical AND. Short-circuits. |
| `or` / `\|\|` | `kscript.uno/or` | Logical OR. Short-circuits. |
| `xor` | `kscript.uno/xor` | Logical XOR. |
| `nand` | `kscript.uno/nand` | Logical NAND. |
| `nor` | `kscript.uno/nor` | Logical NOR. |
| `xnor` | `kscript.uno/xnor` | Logical XNOR. |

### Unary

| Operator | Class | Description |
|----------|-------|-------------|
| `not` / `!` | `kscript.uno/not` | Logical NOT. |

---

## Ternary Operator (Tret)

```
vibecode: {
	"section": "ternary_operator",
	"operator": "?:",
	"implementation": "handled_by_parser_not_scope_operator_tables",
	"overrideable": false,
	"desugars_to": "if_expression"
}
```

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

## Open Questions (Voval)

- Should `scope.operators` be inheritable — i.e. does a child scope see parent scope
  operators automatically?
- Can operators be removed from a scope, or only added?
