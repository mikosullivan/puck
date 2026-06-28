# Steps

## Overview

~~~vibecode
{"vibecode": {
	"section": "overview",
	"method": "%utils.steps",
	"purpose": "count_caspian_level_steps_for_a_block",
	"unit": "one_step_per_eval_or_exec_stmt_call",
	"default": "off_zero_overhead_unless_call_is_active",
	"nesting": "each_call_gets_accurate_count_of_its_own_scope"
}}
~~~

`%utils.steps` wraps a block and counts every Caspian-level evaluation step inside it,
including all nested function calls. It is off by default — zero overhead unless a
`%utils.steps` call is active.

The step unit is one call to `eval` or `exec_stmt` in the interpreter. This is
deterministic (same program always gives the same count), engine-independent (any
compliant engine implements the same unit), and meaningful at the language level rather
than the hardware level.

---

## Syntax

~~~vibecode
{"vibecode": {
	"section": "syntax",
	"form": "%utils.steps do ... end",
	"returns": "result_object",
	"result_methods": ["steps", "value"]
}}
~~~

```
$result = %utils.steps do
    &some_routine
end

$result.steps    # total steps executed inside the block (including nested calls)
$result.value    # return value of the block
```

The `%utils.steps` call returns a result object with two fields:

| Field | Type | Description |
|-------|------|-------------|
| `steps` | Number | Total Caspian-level steps executed inside the block |
| `value` | Any | The return value of the last statement in the block |

---

## Nested Steps

~~~vibecode
{"vibecode": {
	"section": "nested_steps",
	"behavior": "each_call_counts_its_own_scope_independently",
	"mechanism": "interpreter_maintains_stack_of_active_step_counters",
	"note": "inner_steps_count_toward_both_inner_and_outer_totals"
}}
~~~

`%utils.steps` calls can be nested. Each call maintains its own counter. Inner steps count
toward both the inner and outer totals, giving each call an accurate picture of its
own scope:

```
$outer = %utils.steps do
    &foo

    $inner = %utils.steps do
        &bar
    end

    &gup
end

$inner.steps    # steps for &bar only
$outer.steps    # steps for &foo + &bar + &gup combined
```

The interpreter maintains a stack of active step counters. Every `eval` and `exec_stmt`
call increments all counters currently on the stack.

---

## Counting Rules

~~~vibecode
{"vibecode": {
	"section": "counting_rules",
	"unit": "one_step_per_eval_or_exec_stmt_call",
	"includes": ["nested_function_calls", "method_calls", "operator_evaluations",
		"block_bodies"],
	"deterministic": true,
	"hardware_independent": true
}}
~~~

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

~~~vibecode
{"vibecode": {
	"section": "implementation_note",
	"lua_reference": "counter_stack_in_interpreter_incremented_at_eval_and_exec_stmt",
	"overhead": "one_integer_increment_per_step_when_active",
	"compliant_engine_requirement": "must_implement_same_step_unit_and_nesting_semantics"
}}
~~~

In the Lua reference implementation, the interpreter maintains a stack of integer
counters. When a `%utils.steps` call is entered, a new counter is pushed. Every `eval` and
`exec_stmt` call increments all counters on the stack. When the call's block exits, the top
counter is popped and wrapped in the result object.

When no `%utils.steps` call is active the stack is empty and no incrementing occurs — zero
overhead.

A compliant engine must implement the same step unit and nesting semantics so that step
counts are comparable across engines.

---

## Technical details

~~~vibecode
{"vibecode": {
	"section": "technical_details",
	"covers": ["purpose", "calculation", "engine_independence", "where_steps_surface"],
	"unit": "one_step_per_eval_or_exec_stmt_call",
	"deterministic": true,
	"engine_independent": true
}}
~~~

A **step** is a single unit of work at the Caspian language level. Steps are how Caspian programs and tooling answer the question *"how much work did this process do?"*. They provide a simple way to compare the efficiency of different algorithms — run the processes and compare the step counts.

### Purpose

Steps exist as a **deterministic, engine-independent measurement** of Caspian-level work. The same program with the same input always produces the same step count, regardless of which engine ran it or which machine it ran on.

This makes steps the right tool for several jobs that wall-clock time handles poorly:

- **Timeouts.** Set a step-budget cap on a region of code; the cap holds no matter how fast or slow the host machine is. Wall-clock timeouts depend on CPU speed, system load, and contention; step budgets don't.
- **Regression detection.** A test asserting "this routine completes in fewer than N steps" stays accurate when CI moves to faster or slower runners. The same assertion with a wall-clock bound would have to be retuned every infrastructure change.
- **Profiling and hot-path analysis.** Steps say which routines do more *language-level work*. They don't say which routines spend more wall-clock time — that's a separate concern with different tools.
- **Debug provenance.** "How far along was the program when X happened?" can be answered in steps — useful when reproducing a state or comparing two runs.

Steps are not a wall-clock substitute. They count interpreter advances; they don't count seconds spent in host I/O, sleeping, blocking on the network, or anything else outside the Caspian interpreter loop.

### How they're calculated

One step is counted for each call to `eval` or `exec_stmt` in the engine — the two interpreter primitives that advance a Caspian program by one observable language-level step. This includes:

- Every statement executed.
- Every expression evaluated.
- Every nested function or method call.
- Every operator evaluation.
- Every block body entered.

It does NOT include:

- Wall-clock time spent inside host-language code that the engine doesn't drive (host library calls, system calls, sleeps).
- Bytes of memory allocated, garbage collected, or transferred.
- Host-level interpretation overhead (the Lua interpreter's own per-instruction cost in the reference implementation, for example).

The count is **monotonic** — it only goes up over the life of a counter. It's **stable across runs** — same program, same input, same number. And it's **hardware-independent** — CPU speed, cache behavior, and system load don't affect it.

### Engine independence

Steps are a **Caspian language-level concept**, not a Lua concept. The unit is defined at the language layer: one call to `eval` or `exec_stmt` is one step. Any compliant engine — the Lua reference implementation today, hypothetical future implementations in other host languages tomorrow — must produce identical step counts for the same Caspian program with the same input.

This is what makes steps useful for cross-engine comparison: if engine A and engine B produce different step counts for the same program, one of them is non-compliant. Step counts are portable: the same number means the same amount of work on every engine.

The Lua reference implementation happens to be the first place steps are implemented; see the [Implementation Note](#implementation-note) section above for the specific Lua-side mechanism. That's an implementation detail. The language-level semantics — what counts as a step, when it's incremented, what stays stable — are spec-level and bind every engine equally.

### Where steps surface

Two places in the language and runtime today:

- **[`%engine.manifest`](../../engine/manifest.md)** reports `process.steps` — the total step count for the process since it started. Used by the debug-and-introspection tool for after-the-fact "how much did this process do?" questions.
- **`%utils.steps`** (this doc) wraps a region of code (block form) and reports the step count for just that region. Used for scoped measurement of a specific routine, with nesting support so each call gets an accurate count of its own scope.

Both produce the same unit. A region measured with `%utils.steps` is directly comparable to the process-level count from the manifest, because there's only one definition of "a step" in the language.
