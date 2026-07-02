# `%chain.steps`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_steps",
	"role": "spec for %chain.steps — count Caspian-level evaluation steps inside a block. Deterministic across runs, engine-independent across implementations. Off (zero overhead) when no call is active.",
	"unit": "one_step_per_eval_or_exec_stmt_call",
	"engine_independent": true,
	"default_grant": "yes — same posture as %chain.timer"
}}
~~~

**Default-granted across role boundaries:** yes.  

`%chain.steps` counts Caspian-level operations inside a block. Each statement, expression, method call, operator evaluation, block entry, and object-lifecycle event is one step — see [What a step is](#what-a-step-is). The count is **deterministic** (same program + same input → same count) and **engine-independent** (any conforming engine produces the same number for acyclic programs), which makes it the right tool for benchmarking and regression detection where `%chain.timer`'s wall-clock numbers would be too noisy.

~~~caspian
$count = %chain.steps do
	# ... work whose steps you want to count ...
end
~~~

The block runs normally; the return value of `%chain.steps` is the step count, not the block's return value. If you need both, capture the block's return inside and read it outside.

## What a step is

A **step** is a single Caspian-level operation — one observable advance of the program at the language layer. Steps include:

- Every statement executed.
- Every expression evaluated.
- Every nested function or method call.
- Every operator evaluation.
- Every block body entered.
- **Every Caspian-level lifecycle event.** An object becoming unreachable (scope exit, reference overwrite, container element removed) is one step. A finalizer running is one step plus whatever its body costs in normal steps. These events are defined by the language spec at deterministic moments, independent of how a particular engine actually manages memory underneath — so they count.

User-level constructs cost multiple steps each: a loop iteration is several steps; a method call is several plus whatever the body costs; an arithmetic expression with two operands is at least three (the two operand reads and the operation itself); a function return that releases ten locals is roughly ten cleanup steps on top of the return itself. The metric is for **comparison** ("operation X takes ~3× as many steps as Y"), not for absolute capacity planning.

## What steps don't count

The boundary is the Caspian language layer. Time and work below that layer are invisible to the counter:

- **Wall-clock time spent in host code the engine isn't driving** — host library calls, syscalls, sleeps, network I/O wait. A program that spends 90% of its life blocked on the network has a step count reflecting only the 10% it spent advancing Caspian code.
- **The host VM's memory mechanics.** When the host (Lua, in the reference implementation) physically allocates memory, copies blocks, reorganizes its heap, or runs its own GC pass to actually reclaim the bytes — none of that counts. Those timings vary wildly between engines and would break the engine-independence guarantee. *Caspian-level* lifecycle events (object becoming unreachable, finalizer running) ARE counted — see [What a step is](#what-a-step-is) above. The exclusion here is specifically the host VM's plumbing, not the language-level lifecycle.
- **Host-language interpretation overhead.** In the Lua reference implementation, the Lua VM's per-instruction cost is not part of the count — that's an implementation detail, not a Caspian-level event.

This is what makes the metric portable across engines: only the language-level events count, and every conforming engine produces them at the same granularity.

### Note on cycles

Acyclic lifecycle is deterministic: a Caspian object becomes unreachable at a moment the spec defines, and that's when the lifecycle step fires. Cyclic structures — objects that mutually refer to each other — are different. Whether and when a cycle gets cleaned depends on the engine's strategy (refcount-only engines might never clean cycles without an explicit pass; mark-sweep engines clean them when sweep runs). Cycle cleanup is **still counted** when it happens, but the moment at which it happens isn't deterministic across engines. Programs that lean heavily on cyclic references will see step counts that match in total only after the cycle resolution strategy is the same — for cross-engine determinism, design to avoid cycles or break them explicitly.

## Engine independence

Steps are a **Caspian language-level concept**, not an implementation concept. The unit is defined at the language layer — see [What a step is](#what-a-step-is) — independent of how a particular engine implements evaluation or memory management. Any conforming engine — the Lua reference implementation today, hypothetical future implementations tomorrow — produces identical step counts for the same acyclic program with the same input.

If engine A and engine B produce different step counts for the same program, one of them is non-conforming. Step counts are portable: the same number means the same amount of work on every engine.

## What it's useful for

- **Benchmarking algorithm choice.** "Implementation X takes 1,800 steps; implementation Y takes 6,200 steps for the same workload." The ratio is meaningful and stable — it doesn't change with CPU speed, cache state, or background load.
- **Regression detection in tests.** A test asserting "this routine completes in fewer than N steps" stays accurate when CI moves to a faster or slower runner. The same assertion with a wall-clock bound would have to be retuned every time the infrastructure changes.
- **Profiling and hot-path analysis.** Steps say which routines do more *language-level work*. They don't say which routines spend more wall-clock time — that's a separate concern (use `%chain.timer` for that).
- **Debug provenance.** "How far along was the program when X happened?" can be answered in steps — useful when reproducing a state, comparing two runs, or pinpointing where a divergence began.

`%chain.steps` and `%chain.timer` are complements: the former for engine-independent work measurement, the latter for actual elapsed time. Code being characterized usually wants both.

## Overhead

**Zero** unless a `%chain.steps` call is active. The instrumentation is conditional on at least one open `%chain.steps` frame; with no active call, the interpreter takes its regular path with no per-step counter bump.

When a call is active, the cost is one integer increment per step. The interpreter maintains a stack of counters; each `eval` / `exec_stmt` increments every counter on the stack.

## Nesting

`%chain.steps` calls nest naturally. Each call gets its own counter, and inner steps count toward both the inner and the outer total — so each call reports an accurate count of its own scope:

~~~caspian
$outer_count = %chain.steps do
	&foo

	$inner_count = %chain.steps do
		&bar
	end

	&gup
end

# $inner_count: steps for &bar only.
# $outer_count: steps for &foo + &bar + &gup combined.
~~~

The mechanism is the counter stack from [Overhead](#overhead) above: a new counter pushes on entry, pops on exit. Every interpreter step increments every active counter, so each one ends up with the right answer for its own scope.
