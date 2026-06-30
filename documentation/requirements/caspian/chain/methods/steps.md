# `%chain.steps`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_steps",
	"role": "spec for %chain.steps — count Caspian-level evaluation steps inside a block. Off when no active call; engine-independent step count.",
	"overhead": "zero unless a %chain.steps call is active"
}}
~~~

**Default-granted across role boundaries:** TBD (see issue #834).  

`%chain.steps` counts Caspian-level evaluation steps inside a block — one step per call to the interpreter's `eval` or `exec_stmt` primitive. The count is **engine-independent**: the same program produces the same step count on any conforming Caspian engine, which makes the metric usable for deterministic benchmarking.

~~~caspian
$count = %chain.steps do
    # ... work whose steps you want to count ...
end
~~~

The block runs normally; the return value of `%chain.steps` is the step count, not the block's return value. If you need both, capture the block's return inside and read it outside.

## Overhead

**Zero** unless a `%chain.steps` call is active. The instrumentation is conditional on at least one open `%chain.steps` frame; with no active call, the interpreter takes the regular path with no per-step counter bump.

## What counts as a step

Each evaluation of a CaspianJ node — whether expression evaluation or statement execution — is one step. The granularity is the interpreter's internal one; user-level constructs like loops, method calls, and arithmetic each take multiple steps.

The metric is for **comparing** runs, not for absolute capacity planning. "Operation X takes ~3× as many steps as operation Y" is the kind of question `%chain.steps` answers reliably; "operation X takes N microseconds" is what `%chain.timer` answers instead.
