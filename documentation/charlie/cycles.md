# Cycles

## Overview

```
vibecode: {
	"section": "overview",
	"sigil": "#cycles",
	"purpose": "count_charlie_level_steps_for_a_block",
	"unit": "one_step_per_eval_or_exec_stmt_call",
	"default": "off_zero_overhead_unless_block_is_open",
	"nesting": "each_block_gets_accurate_count_of_its_own_scope"
}
```

`#cycles` wraps a block and counts every Charlie-level evaluation step inside it,
including all nested function calls. It is off by default — zero overhead unless a
`#cycles` block is open.

The step unit is one call to `eval` or `exec_stmt` in the interpreter. This is
deterministic (same program always gives the same count), engine-independent (any
compliant engine implements the same unit), and meaningful at the language level rather
than the hardware level.

---

## Syntax

```
vibecode: {
	"section": "syntax",
	"form": "#cycles ... end",
	"returns": "cycles_object",
	"result_methods": ["steps", "value"]
}
```

```
$result = #cycles
    &some_routine
end

$result.steps    # total steps executed inside the block (including nested calls)
$result.value    # return value of the block
```

The `#cycles` block returns a cycles object with two fields:

| Field | Type | Description |
|-------|------|-------------|
| `steps` | Number | Total Charlie-level steps executed inside the block |
| `value` | Any | The return value of the last statement in the block |

---

## Nested Cycles

```
vibecode: {
	"section": "nested_cycles",
	"behavior": "each_block_counts_its_own_scope_independently",
	"mechanism": "interpreter_maintains_stack_of_active_cycle_counters",
	"note": "inner_steps_count_toward_both_inner_and_outer_totals"
}
```

`#cycles` blocks can be nested. Each block maintains its own counter. Inner steps count
toward both the inner and outer totals, giving each block an accurate picture of its
own scope:

```
$outer = #cycles
    &foo

    $inner = #cycles
        &bar
    end

    &gup
end

$inner.steps    # steps for &bar only
$outer.steps    # steps for &foo + &bar + &gup combined
```

The interpreter maintains a stack of active cycle counters. Every `eval` and `exec_stmt`
call increments all counters currently on the stack.

---

## Counting Rules

```
vibecode: {
	"section": "counting_rules",
	"unit": "one_step_per_eval_or_exec_stmt_call",
	"includes": ["nested_function_calls", "method_calls", "operator_evaluations",
		"block_bodies"],
	"deterministic": true,
	"hardware_independent": true
}
```

One step is counted for each call to `eval` or `exec_stmt`, including:

- Every statement executed
- Every expression evaluated
- Every nested function or method call
- Every operator evaluation
- Every block body entered

The count is deterministic — the same program with the same input always produces the
same step count. It is not a wall-clock measurement and is not affected by CPU load,
caching, or context switching.

---

## Implementation Note

```
vibecode: {
	"section": "implementation_note",
	"lua_reference": "counter_stack_in_interpreter_incremented_at_eval_and_exec_stmt",
	"overhead": "one_integer_increment_per_step_when_active",
	"compliant_engine_requirement": "must_implement_same_step_unit_and_nesting_semantics"
}
```

In the Lua reference implementation, the interpreter maintains a stack of integer
counters. When a `#cycles` block is entered, a new counter is pushed. Every `eval` and
`exec_stmt` call increments all counters on the stack. When the block exits, the top
counter is popped and wrapped in a cycles object.

When no `#cycles` block is active the stack is empty and no incrementing occurs — zero
overhead.

A compliant engine must implement the same step unit and nesting semantics so that step
counts are comparable across engines.
