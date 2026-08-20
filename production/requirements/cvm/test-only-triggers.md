# Test-only triggers

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm_test_only_triggers",
	"role": "The strategy for observing CVM state as it changes during a run. Tests install SQLite triggers at runtime (via `engine.cvm:exec`) that mirror in-flight schema events into `debug_log`; after the run the test suite reads `debug_log` to check that events happened in the expected order and shape. The triggers live in test code only — not in schema.sql or preflight.sql. Rationale: SQL-level probes see every write ordered exactly as the engine issued it, no Lua-side polling, no engine hooks to add.",
	"status": "V1 strategy"
}}
~~~

Some assertions about CVM behavior need to see events **as they happen** — not just the end-state of the DB after the run. Example: `$x = 2` on top of `$x = 1` marks scalar_1 in `needs_trace`, but the between-statement drain reaps scalar_1 the instant it's marked, so the row is gone before `run()` returns. Reading `needs_trace` at end-of-run tells you nothing about whether the mark ever fired.

The strategy: **install a SQLite trigger from test code at runtime**, before running the program. The trigger fires on the schema event you want to observe, and its body writes an entry into `debug_log` (see [debug_log](https://puck.uno/production/src/engine/cvm/schema.sql), search for `create table debug_log`). After the run, the test reads `debug_log` and asserts on what it finds.

## The pattern

1. Construct the engine (`engine.new()`).
2. Immediately install the trigger via `engine.cvm:exec("create trigger ...")`.
3. Load and run the program.
4. Query `debug_log` at end-of-run and assert.

Example from [test_second_assignment.lua](https://puck.uno/production/tests/main/lua/engine/test_second_assignment.lua):

~~~lua
local NEEDS_TRACE_DEBUG_TRIGGER = [[
    create trigger sprint_needs_trace_write_debug_log
    after insert on needs_trace
    begin
        insert into debug_log (object_pk, note)
        values (
            new.process_pk,
            'mark ' || new.object_pk || ' ' || (
                select case
                    when scalar_value is null then 'null'
                    else format('%g', scalar_value)
                end
                from objects where object_pk = new.object_pk
            )
        );
    end;
]]

local function new_engine()
    local e = engine.new()
    assert(e.cvm:exec(NEEDS_TRACE_DEBUG_TRIGGER) == 0, e.cvm:errmsg())
    return e
end
~~~

Every `new_engine()` call returns an engine with the trigger already in place. Tests use `new_engine()` in place of `engine.new()` and don't have to think about the probe further.

## Rules

- **The trigger lives in test code, never in `schema.sql` or `preflight.sql`.** Production databases never get the trigger. If a probe survives integration into the shipping schema, it's no longer a test probe — it's a feature, and it needs a design and a rationale.
- **Read `new.<column>` in trigger bodies.** SQLite exposes the incoming row via `new.*` in AFTER-INSERT triggers; write it into `debug_log` verbatim rather than re-querying.
- **Scope entries to the current process cap.** `debug_log.object_pk` FKs to a process cap and cascades on cap-delete. Writing `new.process_pk` when the source table is `needs_trace` satisfies the FK for free; other source tables need to pick out the right cap themselves.
- **Format numbers deliberately.** `cast(x as text)` on a REAL produces `1.0`; use `format('%g', x)` to render `1`. `format('%g', NULL)` returns the string `'0'`, not NULL — so a `coalesce(format(...), 'null')` never falls through; check `x is null` explicitly first.
- **Assert on order when order matters.** `debug_log` has an autoincrementing `entry_pk`; ordering by it recovers the sequence the trigger fired in. If a test expects a specific traversal order (a GC drain's walk, a cascade's iteration), assert the full sequence — the exact match doubles as a diagnostic when the traversal changes.

## When NOT to use this

- **End-state assertions.** If you only need to check the DB state after the run, query the tables directly. The trigger adds noise for no signal.
- **Behavior spec'd by the schema.** If the schema itself has a trigger that fires on the event, prefer to assert against its observable output (a row somewhere, an error id raised) rather than adding a parallel probe.
- **Anything a production-shipped feature needs to see.** Test-only triggers are for *tests*; if the engine needs to observe the same event at runtime, add it to `schema.sql` (or `preflight.sql` for per-connection scratch) with a proper design.

## Related

- [debug_log](https://puck.uno/production/src/engine/cvm/schema.sql) — the target table for probe entries. Cap-scoped, cascades on cap-delete.
- [garbage-collection](https://puck.uno/production/requirements/cvm/garbage-collection/) — the drain routine whose behavior the second-assignment tests use this pattern to observe.
- [test_second_assignment.lua](https://puck.uno/production/tests/main/lua/engine/test_second_assignment.lua) — first use of the pattern in the test suite.
