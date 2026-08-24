~~~vibecode
{"doc": "sprint-index", "sprint": "remove-debug-column",
	"role": "Drop the `debug` column from `objects` and `refs` and every trace of it — comments, mutable-columns list, tests, docstrings. No engine code reads or writes either column today; they were seeded as a general-purpose 'human-readable label' facility that has never been wired up. Removing them tightens the schema surface, drops two of the three mutable columns on `refs`, and simplifies the immutability story on `objects` (which currently calls out `debug` alongside `frame_gc` / `frame_stmt_idx` as the only writable columns).",
	"status": "seed — no work done. Not being sprinted right now."}
~~~

# remove-debug-column

Drop the free-form `debug` column from both `objects` and `refs`. No engine code references it; nothing populates it; no query path reads it. It was reserved as a hook for future "human-readable label" tooling that never landed.

## What's there today

**`objects.debug`** — `text`, nullable, freely editable ([production/src/engine/cvm/sqlite/schema.sql:180](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — "Human-readable label. Informational; no query path reads it").

**`refs.debug`** — `text`, nullable, freely editable ([production/src/engine/cvm/sqlite/schema.sql:484](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — "Human-readable label. Informational").

Neither is read or written by:

- Any Lua module under [production/src/engine/](https://puck.uno/production/src/engine/) (grep-verified — no matches for `\.debug` or `debug\s*=` outside `debug_log`, which is a distinct table).
- Any handler, dispatcher, or CVM helper.
- Any tests except the ones directly exercising the column's mutability (see below).

## What the removal touches

**Schema:**

- Drop `debug text,` from `create table objects` (around line 180 of schema.sql).
- Drop `debug text,` from `create table refs` (around line 484).
- Update the `refs_no_update` trigger — its WHEN clause guards `parent`, `key`, `idx`; removing `debug` from the "editable columns" narrative means the trigger comment can shed the "only child and debug are editable" note. `debug` isn't in the WHEN clause today (it's implicitly editable because it's not guarded), so the trigger itself likely needs no code change, only a comment sweep.
- Update the "unprefixed columns" vibecode line at the top of schema.sql — drop `debug` from the list.
- Update the "immutability" vibecode paragraph — drop `debug` from the "columns that permit updates" list; `frame_gc` and `frame_stmt_idx` remain.
- Bump schema version.

**Tests:**

- Roughly 10 assertions in [production/tests/main/lua/engine/sqlite/test_schema.lua](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) reference `debug` — the block starting around line 2053 exercises the "refs.debug is mutable" invariant. Delete the whole block.
- Verify no other test suite mentions the column.

**Requirements docs:**

- Sweep [production/requirements/cvm/](https://puck.uno/production/requirements/cvm/) for mentions of the `debug` column. Any that name it explicitly as part of the row shape get dropped or reworded.

## Why remove

- **Nothing uses it.** The whole point of a schema column is to store data the system reads. This one hasn't earned a query path in the two-plus years it's existed.
- **Simplifies the mutable-columns narrative.** The `objects` immutability paragraph currently lists `frame_gc`, `frame_stmt_idx`, and `debug` as the three writable columns. Drop `debug` and the story is "only the two frame-lifecycle columns move." That's easier to say and easier to remember.
- **Two of `refs`'s three "mutable via UPDATE" columns evaporate.** Only `child` (for the UPSERT-rebind path) remains editable.
- **Prevents accidental future use.** A field that's been sitting around unused for a long time invites developers to reach for it as an escape hatch. Removing it forces the "should this data really live here?" conversation.

## What removal doesn't touch

- **`debug_log` table.** Distinct concept — per-process free-form diagnostic log. Actively used by the sprint's obj tests and by future observability tooling. Stays.
- **`.debug` fields on Lua wrapper classes.** Some Lua modules carry a `.debug` field for their own state (nothing loaded currently; grep-verify before removing anything). Different concern.

## Integration approach

Standard schema-change flow:

1. Sprint work under `sprints/remove-debug-column/src/` — copy production schema, apply the column drops + comment sweep, add or update a test file demonstrating the columns are gone.
2. Land into production: drop the columns, sweep tests, sweep any requirements docs that name them.
3. Version bump; audit; refresh Orlando cache.

Low risk — no code paths to update, no in-flight data to migrate (nothing was ever written to these columns).

## Related

- [production/src/engine/cvm/sqlite/schema.sql](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — where both columns live.
- [production/tests/main/lua/engine/sqlite/test_schema.lua](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — the block around line 2053 to delete.
