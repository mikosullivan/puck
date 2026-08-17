~~~vibecode
{"doc": "sprint-index", "sprint": "refs-idx-typeof-integer",
	"role": "Decision record: IMPLEMENTED. Closed a SQLite type-affinity hole on `refs.idx` — the column was declared `integer not null check (idx >= 0)`, but SQLite's `integer` is affinity, not strict typing, so values like 1.5 (real) and 'abc' (text) satisfied the inequality. Now: `check (typeof(idx) = 'integer' and idx >= 0)`. Source: ChatGPT second-pass § 3.",
	"status": "implemented"}
~~~

# refs-idx-typeof-integer

Second-pass § 3. Closed.

## What landed

Column CHECK on `refs.idx` in [src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql):

~~~sql
idx integer not null check (typeof(idx) = 'integer' and idx >= 0)
~~~

The `not null` stays for clarity; the `typeof` clause closes the affinity hole; the `>= 0` regression stays.

Tests in [tests/main/lua/engine/test_schema.lua](https://puck.uno/tests/main/lua/engine/test_schema.lua) under "refs.idx CHECK: typeof + non-negative":

- non-negative integer accepted
- real (1.5) rejected
- text ('abc') rejected
- negative rejected

## Broader pattern

Sibling sprint [in-trace-typeof-integer](../in-trace-typeof-integer/) closed the same affinity hole on `objects.in_trace`. Those are the two current instances the second-pass review found. ChatGPT flagged this as a pattern to watch: any future column using inequalities (`> 0`, `>= 0`) on an integer-affinity column should apply the same audit.

Sprint kept as a record.
