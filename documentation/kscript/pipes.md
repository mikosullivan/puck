# KScript Pipe Operator Design

## Overview (T'Lar)

vibecode: {
	"section": "overview",
	"role": "introduces the KScript pipe operator for chaining in execution order",
	"key_concepts": ["pipe_operator", "execution_order", "chaining", "nested_call_alternative"]
}

KScript introduces a pipe operator to allow chaining operations in **execution order**, rather than nested call order.

This provides a more readable and intuitive alternative to deeply nested expressions.

---

## Basic Pipe Operator (T'Lar Vulcan)

vibecode: {
	"section": "basic_pipe_operator",
	"role": "defines the | operator: passes left result as first and only arg to right",
	"key_concepts": ["pipe_operator", "single_argument", "desugaring", "a_pipe_b"]
}

### Syntax

```kscript
a | b
```

### Semantics

The pipe operator passes the result of the left-hand expression as the **first positional argument** to the right-hand expression. The right-hand side may also accept additional positional or named arguments at the call site; the piped value occupies the first positional slot and the rest of the arguments are bound normally.

```kscript
a | b
```

desugars to:

```kscript
b(a)
```

With additional arguments at the call site:

```kscript
$list | sort('asc')
$list | filter(min: 5, max: 10)
```

desugar to:

```kscript
sort($list, 'asc')
filter($list, min: 5, max: 10)
```

Same shape as Elixir's `|>`, F#'s `|>`, R's `%>%`.

---

## Chaining Pipes (T'Lar Elder)

vibecode: {
	"section": "chaining_pipes",
	"role": "shows how multiple | operators desugar to nested function calls",
	"key_concepts": ["pipe_chain", "sequential_execution", "nested_call_desugaring"]
}

Multiple pipes can be chained to represent sequential execution:

```kscript
&a |
&b |
&c
```

desugars to:

```kscript
&c(&b(&a))
```

---

## Example: Method Calls (T'Pol Vulcan)

vibecode: {
	"section": "example_method_calls",
	"role": "illustrates pipe chaining with method calls on objects",
	"key_concepts": ["method_call_piping", "execution_order_readability"]
}

Pipes work naturally with object method calls:

```kscript
&baz |
&bear |
$bar.gup
```

desugars to:

```kscript
$bar.gup(&bear(&baz))
```

This allows writing code in the same order as execution.

---

## Design Principle (T'Pen)

vibecode: {
	"section": "design_principle",
	"role": "states the core design rule: pipes express data flow in execution order",
	"key_concepts": ["data_flow", "execution_order", "single_input_per_stage"]
}

> Pipes express **data flow in execution order**, not call nesting.

Each stage receives exactly one input: the result of the previous stage.

---

## Null-Safe Pipe Operator (`|&`) (Saavik II)

vibecode: {
	"section": "null_safe_pipe_operator",
	"role": "documents the |& operator for null propagation through a pipe chain",
	"key_concepts": ["|&_operator", "null_propagation_mode", "null_safe_chaining", "once_set_all_subsequent"]
}

### Motivation

KScript supports null-safe chaining in method calls:

```kscript
$foo.bar&.gup.bear
```

This stops evaluation if `bar` returns `null`.

The pipe system introduces a similar concept.

---

## Syntax (T'Pring II)

vibecode: {
	"section": "null_safe_syntax",
	"role": "shows the |& operator syntax",
	"key_concepts": ["|&_syntax", "null_safe_pipe_form"]
}

```kscript
a |& b
```

---

## Semantics (T'Pring SNW)

vibecode: {
	"section": "null_safe_semantics",
	"role": "explains that |& enables null propagation mode for all subsequent pipe stages",
	"key_concepts": ["null_propagation_mode", "remainder_of_chain", "sticky_null_safe"]
}

The `|&` operator enables **null propagation mode** for the remainder of the pipe chain.

Once `|&` is used, all subsequent pipe stages automatically become null-safe.

### Example

```kscript
&foo |&
&bar |
&gup
```

is equivalent to:

```kscript
&foo |&
&bar |&
&gup
```

---

## Execution Model (T'Vrana)

vibecode: {
	"section": "execution_model",
	"role": "shows the desugared if-null-return expansion for null-safe pipe chains",
	"key_concepts": ["null_check_expansion", "return_null_early", "desugared_form"]
}

```kscript
&foo |&
&bar |
&gup
```

desugars to:

```kscript
let x = &foo
if x == null
    return null

let y = &bar(x)
if y == null
    return null

return &gup(y)
```

---

## Design Rule (T'Marik)

vibecode: {
	"section": "null_safe_design_rule",
	"role": "states the rule that |& once used propagates null through all subsequent stages",
	"key_concepts": ["once_propagates_all", "no_repetition_needed", "clear_intent"]
}

> Once `|&` appears in a pipe chain, **all subsequent pipes propagate nulls**.

This avoids repetition while keeping intent clear.

---

## Summary (T'Mara)

vibecode: {
	"section": "summary",
	"role": "quick reference table for pipe operator meanings",
	"key_concepts": ["pipe_operator_table", "|", "|&"]
}

| Operator | Meaning |
|----------|--------|
| `|`      | Pass result to next stage |
| `|&`     | Enable null-propagating pipe mode |

---

## Future Considerations (Optional)

vibecode: {
	"section": "future_considerations",
	"role": "lists intentionally deferred pipe features for possible future design",
	"key_concepts": ["placeholder_arguments", "multi-argument_pipe", "pipe_grouping", "deferred_design"]
}

- Placeholder arguments (e.g. `_`) for more flexible piping
- Multi-argument pipe expansion
- Explicit pipe grouping or scoping

These are intentionally deferred to keep the initial design minimal and predictable.
