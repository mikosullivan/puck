~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "trace-tables",
	"role": "Concrete steps to merge the trace-tables sprint into production. Enumerates the schema diff to apply (three new tables + preflight.sql + auto-delete removal + new gc-reset guard), the engine hooks to wire (current_process_pk UDF + explicit frame reap step), the tests to migrate, and the docs to update. Runs as a single sitting — the risk is in getting every rename and cap-exempt site right in one pass, not in figuring anything new out.",
	"status": "draft — awaiting go-ahead"}
~~~

# Integration plan — trace-tables

Merges the sprint into production. All the design and test work is done; this is a mechanical transposition.

Sprint scope has grown slightly beyond the trace-tables themselves. It now also carries:

- Removal of both auto-delete-at-terminal triggers from production. Terminal frames stay put; the engine reaps them explicitly.
- A new `frames_gc_reset_requires_empty_needs_trace` trigger that subsumes the old `process_cap_terminal_requires_no_traces` guard.
- A new [preflight.sql](https://puck.uno/sprints/trace-tables/src/preflight.sql) file that runs on every connection open (pragmas + temp tables + temp triggers), distinct from schema.sql which runs once at DB creation.

## Prerequisites

Before the merge sitting starts:

- Sprint tests pass on the sprint's own schema — verify with `for f in sprints/trace-tables/tests/test_*.lua; do lua5.4 $f; done`.
- Production tests pass on the current shipping schema — verify with `lua5.4 production/tests/main/lua/engine/run.lua`.
- Production is unlocked. `chmod -R u+w production/`.

## Step 1 — column rename in production, `process` → `process_cap`

Standalone rename, no behavior change. Do this first as its own commit so any regression here is trivially bisectable.

Sites in [production/src/engine/cvm/schema.sql](https://puck.uno/production/src/engine/cvm/schema.sql):

- The column definition on `objects`.
- The partial index `objects_process` (rename to `objects_process_cap` too).
- The `objects_process_immutable` trigger name and body.
- The mutual-exclusion CHECK in `parent_frame`: `(parent_frame is null and process is 1)` → `(parent_frame is null and process_cap is 1)`.
- The cap-exempt clauses I added recently in `frames_child_delete_sets_parent_gc` and `frames_no_child_under_terminal_parent` — both use `process is not 1`; both flip.
- The `insert_cap` prepared statement in [production/src/engine/engine.lua](https://puck.uno/production/src/engine/engine.lua) — column name in the INSERT.
- Any test under [production/tests/main/lua/engine/](https://puck.uno/production/tests/main/lua/engine/) that references the column or its immutability error id — grep `\bprocess\b` filtered to schema/test files.

Verify: full production test suite green.

## Step 2 — schema merge, the actual work

One commit that touches [production/src/engine/cvm/schema.sql](https://puck.uno/production/src/engine/cvm/schema.sql) and adds a new file [production/src/engine/cvm/preflight.sql](https://puck.uno/production/src/engine/cvm/preflight.sql). Apply in order:

### 2a. Remove the column form of `needs_trace` and `in_trace`

- Drop the two columns from `objects` (lines around 226 and 233).
- Drop the two partial indexes `objects_needs_trace` and `objects_in_trace`.
- Rewrite `refs_mark_needs_trace_after_delete` from `update objects set needs_trace = 1` to the sprint's `insert into needs_trace (object_pk) values (old.child) on conflict do nothing`.

### 2b. Remove the auto-delete-at-terminal triggers

Both are gone under the current design — terminal is a valid at-rest state, and the engine reaps explicitly (see Step 4).

- Drop `frames_auto_delete_at_terminal` (AFTER UPDATE OF stmt_idx).
- Drop `frames_auto_delete_at_terminal_on_insert` (AFTER INSERT). The sprint schema doesn't have this one because it was added to production after the sprint forked, but it needs to come out too.

### 2c. Add the persistent `needs_trace` table + its triggers

Copy from [sprints/trace-tables/src/schema.sql](https://puck.uno/sprints/trace-tables/src/schema.sql), keeping the same section header comment block:

- `create table needs_trace` (persistent, main schema, composite PK, real FKs).
- Trigger `needs_trace_process_pk_must_be_cap` — ensures process_pk references a row with `process_cap = 1`.
- Trigger `process_cap_terminal_requires_no_needs_trace` — cap can't advance to terminal while its needs_trace worklist is non-empty.
- **New trigger** `frames_gc_reset_requires_empty_needs_trace` — cannot flip gc from 1 back to null while the current process (`current_process_pk()`) has any outstanding needs_trace rows. Subsumes the old `process_cap_terminal_requires_no_traces` at the state-machine level.

### 2d. Create preflight.sql

New file at [production/src/engine/cvm/preflight.sql](https://puck.uno/production/src/engine/cvm/preflight.sql), copied verbatim from [sprints/trace-tables/src/preflight.sql](https://puck.uno/sprints/trace-tables/src/preflight.sql). Contains:

- Session pragmas: `foreign_keys = on`, `recursive_triggers = on`.
- Temp tables: `traces`, `in_trace`.
- Temp triggers: `objects_delete_cascades_scratch`, `traces_delete_cascades_in_trace`.

Preflight runs on every connection open; schema.sql only runs at DB creation. See Step 3 for the engine wiring.

### 2e. Sanity — load-and-list

Apply both files into an in-memory DB, list the tables in `main` and `temp`, confirm the layout matches the sprint:

~~~
main.objects (without needs_trace / in_trace columns)
main.needs_trace (composite PK)
temp.traces
temp.in_trace
~~~

## Step 3 — wire the UDF and preflight into `cvm.open`

[production/src/engine/cvm/open.lua](https://puck.uno/production/src/engine/cvm/open.lua) opens the connection and applies the schema. It now has two extra jobs:

1. Register the `current_process_pk` UDF on the connection BEFORE any schema/preflight run — several trigger WHEN clauses reference it at fire time.
2. Apply preflight.sql on every connection open (schema.sql applies once at DB creation).

Concretely:

- Copy [sprints/trace-tables/src/engine/cvm/udfs/current\_process\_pk.lua](https://puck.uno/sprints/trace-tables/src/engine/cvm/udfs/current_process_pk.lua) to [production/src/engine/cvm/udfs/current\_process\_pk.lua](https://puck.uno/production/src/engine/cvm/udfs/current_process_pk.lua).
- In `cvm.open`, right after opening the connection:

~~~lua
local current_process_pk = require('cvm.udfs.current_process_pk')
current_process_pk.register(db, function()
	return opts and opts.get_current_process_pk and opts.get_current_process_pk() or nil
end)
~~~

- Then schema.sql (only on fresh DB) and preflight.sql (always):

~~~lua
if is_fresh_db then
	assert(db:exec(slurp(SCHEMA_PATH)) == sqlite.OK, ...)
end
assert(db:exec(slurp(PREFLIGHT_PATH)) == sqlite.OK, ...)
~~~

- In [production/src/engine/engine.lua](https://puck.uno/production/src/engine/engine.lua), pass a getter into `cvm.open`:

~~~lua
local engine = {}
-- ... (declaration order matters — engine is the closure target)
local db = cvm_open.open({
	get_current_process_pk = function() return engine.cap_pk end,
})
~~~

The closure over `engine` means the getter always reflects the current `cap_pk`, no matter when the schema fires it.

## Step 4 — explicit frame reap in the engine

With auto-delete-at-terminal gone, frames stop at terminal and stay there until the engine explicitly deletes them. The engine gains a reap step.

- In [production/src/engine/engine.lua](https://puck.uno/production/src/engine/engine.lua), after a frame's ast is exhausted (or on entry if the frame was born terminal with an empty ast), the engine issues a `DELETE FROM objects WHERE object_pk = ?`. The `frames_child_delete_sets_parent_gc` cascade still fires (cap-exempt), so the parent's gc flips to 1 and the walker continues upward.
- The bare-`SET stmt_idx` advance path stays as-is; only what happens at terminal changes.
- The empty-program case (`caspm = {}`) currently relies on `frames_auto_delete_at_terminal_on_insert` to sweep frame 0. Under the new design, `run_frame` opens frame 0, sees `#ast == 0`, and falls through to reap. No special case in `run()`.

## Step 5 — update production tests that break

Two categories of breakage to expect and fix:

### Column-form needs_trace / in_trace reads

- [production/tests/main/lua/engine/test\_end\_to\_end.lua](https://puck.uno/production/tests/main/lua/engine/test_end_to_end.lua), test at line ≈96 currently reads:

~~~lua
local bucket = first(e.cvm,
	"select needs_trace from objects where primitive = 'h' and needs_trace = 1")
~~~

Becomes:

~~~lua
local bucket = first(e.cvm,
	"select object_pk from needs_trace "
	.. "where object_pk in (select object_pk from objects where primitive = 'h')")
~~~

- [production/tests/main/lua/engine/test\_schema.lua](https://puck.uno/production/tests/main/lua/engine/test_schema.lua) — the "frame delete cascades its refs" test does the same pattern; update to query the `needs_trace` table. Any other reference to `objects.needs_trace` or `objects.in_trace`: grep and fix.

### Auto-delete-at-terminal expectations

Tests that assumed the trigger fires now need updating. Grep [production/tests/main/lua/engine/](https://puck.uno/production/tests/main/lua/engine/) for `frames_auto_delete_at_terminal` and for state assertions of the shape "frame is gone after advance to terminal." Two patterns to expect:

- Tests asserting a frame auto-deletes on advance — rewrite to expect the frame stays alive at terminal, then explicitly delete it and assert what the cascade does.
- Tests asserting a born-terminal frame is gone at INSERT time — rewrite along the same lines.

The end-to-end tests (`test_end_to_end.lua`, `test_end_to_end_state.lua`) should keep working IF the engine reap step from Step 4 is in place — the observable outcome (frame 0 gone by the time `run()` returns) is unchanged; only the mechanism differs.

## Step 6 — move the sprint tests into production

Two files move:

- [sprints/trace-tables/tests/test\_current\_process\_pk.lua](https://puck.uno/sprints/trace-tables/tests/test_current_process_pk.lua) → [production/tests/main/lua/engine/test\_current\_process\_pk.lua](https://puck.uno/production/tests/main/lua/engine/test_current_process_pk.lua)
- [sprints/trace-tables/tests/test\_needs\_trace\_lifecycle.lua](https://puck.uno/sprints/trace-tables/tests/test_needs_trace_lifecycle.lua) → [production/tests/main/lua/engine/test\_needs\_trace\_lifecycle.lua](https://puck.uno/production/tests/main/lua/engine/test_needs_trace_lifecycle.lua)

Path fixups:

- `SCHEMA_PATH = 'sprints/trace-tables/src/schema.sql'` → `SCHEMA_PATH = 'production/src/engine/cvm/schema.sql'`.
- `PREFLIGHT_PATH = 'sprints/trace-tables/src/preflight.sql'` → `PREFLIGHT_PATH = 'production/src/engine/cvm/preflight.sql'`.
- `package.path` — the sprint tests hard-code `sprints/trace-tables/src/engine/cvm/udfs/?.lua`. Under production the UDF lands at [production/src/engine/cvm/udfs/](https://puck.uno/production/src/engine/cvm/udfs/); the `run.lua` runner's package.path is `../../../../src/engine/?.lua` which resolves to [production/src/engine/](https://puck.uno/production/src/engine/) from a test file. Requires become `require('cvm.udfs.current_process_pk')`.
- The tests use `sqlite = require('lsqlite3')` directly — that resolves via `package.cpath` which `run.lua` sets up already. No change.

Run `lua5.4 production/tests/main/lua/engine/run.lua` — expect 22 additional tests green (the 6 UDF + 16 lifecycle), for a total on the order of 267 shipping tests.

## Step 7 — docs pass

- [production/requirements/cvm/](https://puck.uno/production/requirements/cvm/) — the sidebar link labels in the index mention needs_trace / in_trace behavior; audit.
- [production/requirements/cvm/frame-lifecycle](https://puck.uno/production/requirements/cvm/frame-lifecycle) — search for `needs_trace = 1` phrasing; replace with "row lands in the needs_trace table."
- [production/requirements/cvm/garbage-collection/](https://puck.uno/production/requirements/cvm/garbage-collection/) — the whole subtree assumes column-form marking. Sweep for the marker pattern and update.
- Line ≈225 of [production/src/engine/engine.lua](https://puck.uno/production/src/engine/engine.lua) — module docstring mentions `needs_trace = 1 rows`; update to "rows in the needs_trace table."

Grep-and-review: `grep -rn 'needs_trace = 1\|needs_trace=1' production/ | grep -v test`.

## Step 8 — sprint teardown

After the merge is committed and the production suite is green:

- `git rm -r sprints/trace-tables/` — the sprint is done, everything of value lives in production now.
- The [schema.svg](https://puck.uno/sprints/trace-tables/schema.svg) under the sprint dir is the last thing you might want to keep or salvage into [production/requirements/cvm/](https://puck.uno/production/requirements/cvm/). Optional pre-teardown step: overwrite [production/requirements/cvm/schema.svg](https://puck.uno/production/requirements/cvm/schema.svg) with the sprint SVG's contents (which reflects the reworked layout the shipping schema now matches).

## Verification checklist

Run at the end, before the commit:

- `lua5.4 production/tests/main/lua/engine/run.lua` — all green, count on the order of 267.
- `grep -rn 'objects.needs_trace\|objects.in_trace\|needs_trace = 1\|needs_trace=1' production/` — returns nothing except in the sprint history if the sprint dir hasn't been removed yet.
- `grep -rn 'frames_auto_delete_at_terminal' production/` — returns nothing.
- Schema.sql + preflight.sql apply cleanly into a fresh in-memory DB; the table listing shows the expected main/temp layout.
- The engine starts and runs `$x = 1` end-to-end (`lua5.4 -e "..."`).

## Rollback

If anything breaks after the commit:

- Full revert is a single `git revert <sha>` — the commit is self-contained.
- The pre-merge column-rename commit from step 1 stays either way; it's independent and a strict improvement (better name).

## Estimated effort

Two to three hours of focused work — up from the original one-to-two estimate because the sprint now also carries the auto-delete removal (and its engine reap step) and the preflight.sql split. The risk sites are:

- Step 1 rename sweep — miss a `\bprocess\b` occurrence and something breaks silently.
- Step 4 engine reap — the empty-program path needs the reap to fire correctly, otherwise frame 0 lingers.
- Step 5 auto-delete test updates — production has several tests that assumed the trigger fires; each one needs a per-test decision on whether to keep it (rewritten against the new semantics) or drop it.
- Step 7 docs — the marker-pattern phrasing is scattered across the cvm/ subtree.

Every other step is straight copy-and-adapt from the sprint.
