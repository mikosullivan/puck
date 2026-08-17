~~~vibecode
{"doc": "sprint-index", "sprint": "in-trace-typeof-integer",
	"role": "Decision record: IMPLEMENTED. Closed a SQLite type-affinity hole on `objects.in_trace` — the column was declared `integer check (in_trace > 0)`, but SQLite's `integer` is affinity, not strict typing, so values like 1.5 (real) and 'abc' (text) satisfied the inequality. Now: `check (in_trace is null or (typeof(in_trace) = 'integer' and in_trace > 0))`. Source: ChatGPT second-pass § 4.",
	"status": "implemented"}
~~~

# in-trace-typeof-integer

Second-pass § 4. Closed.

## What landed

Column CHECK on `objects.in_trace` in [src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql):

~~~sql
in_trace integer check (
	in_trace is null
	or (typeof(in_trace) = 'integer' and in_trace > 0)
)
~~~

The `is null` disjunct preserves the "null in the common case" behavior; the `typeof` clause closes the affinity hole; the `> 0` regression stays.

Tests in [tests/main/lua/engine/test_schema.lua](https://puck.uno/tests/main/lua/engine/test_schema.lua) under "in_trace CHECK: typeof + positive":

- default null accepted
- positive integer accepted
- real (1.5) rejected
- text ('abc') rejected
- 0 rejected
- negative rejected

## Broader pattern (still open)

ChatGPT noted: "The same audit should be applied whenever a future column uses inequalities such as `x > 0` or `x >= 0` on an integer-affinity column." The other current instance is `refs.idx` — tracked separately in [refs-idx-typeof-integer](../refs-idx-typeof-integer/).

Sprint kept as a record.
