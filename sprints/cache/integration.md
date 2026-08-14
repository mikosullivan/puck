~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "cache",
	"role": "Plan for promoting the cache sprint's schema changes into shipping. Sprint scope: three core-role setup (engine/cache/user), the `user` → `core_role` column shift, the `process` → `process_pk` column rename, dissolution of ALTER TABLE into CREATE TABLE, and a broad prose trim.",
	"trigger": "requires 'proceed with the integration' / 'proceed with the assimilation'"}
~~~

# Integration plan — cache sprint (schema reformat + role restructure)

## Overview

Two semantic changes and two structural cleanups:

**Semantic:**

- **`user` column → `core_role` column.** Where the old column carried a single truthy marker (`user = 1`) for the one root role, `core_role` is a one-character discriminator: `'e'` (engine), `'c'` (cache), `'u'` (user). Nullable — most rows aren't core roles. Unique per value via a partial index.
- **Three core-role seeds** replace the single user seed: engine (root of the core-role tree), cache and user (both children of engine via `role_parent`, both owned by engine via `owner_role`).

**Structural:**

- **`process` column → `process_pk`.** Cross-table FKs get the `_pk` suffix under the sharpened naming convention; unsuffixed FK names remain reserved for self-referencing FKs within `objects`.
- **ALTER TABLE dissolution.** Every `alter table objects add column ...` from shipping is folded into the initial `create table objects (...)`. The Mikobase-vs-CVM section headers go with them — one CVM story, one table definition.
- **Processes moved to top** so the FK on `objects.process_pk` resolves at row-insert time (SQLite with `foreign_keys = on` validates the FK target's existence even when the FK value is null).
- **Comments trimmed** (930 → 570 lines): single-line comments where the thing isn't subtle, load-bearing prose preserved (union-not-or rationale, per-column docstrings, code-change markers).

## Concrete changes

### 1. Column: `user` → `core_role`

Replace this in shipping [src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql):

~~~sql
alter table objects add column user integer check (user = 1);
~~~

with (folded into the CREATE TABLE per step 5 below, but for reference):

~~~sql
core_role text check (core_role in ('e', 'c', 'u'))
~~~

### 2. Partial unique index: `objects_user` → `objects_core_role`

~~~sql
-- Was:
create unique index objects_user on objects(user) where user = 1;

-- Becomes:
create unique index objects_core_role on objects(core_role)
	where core_role is not null;
~~~

### 3. `roles` view first branch

~~~sql
create view roles as
	select object_pk from objects where core_role = 'e'
	union
	select object_pk from objects where role_parent is not null;
~~~

Only engine matches the first branch (root of the core-role tree). Cache, user, and every runtime-added role reach the view via `role_parent`.

### 4. Trigger renames

- `objects_user_immutable` → `objects_core_role_immutable` (body updated to check `new.core_role is not old.core_role`).
- `objects_role_or_owner_role` → `objects_owner_role_required_on_non_roles`. XOR clause dropped — roles can now carry `owner_role` too (cache and user are both roles AND owned by engine).
- `objects_no_delete_root_role` / `objects_no_update_root_role`: WHEN clause changes from `when old.user` to `when old.core_role is not null` — guards any core-role row, not just user.

### 5. Column: `process` → `process_pk`

Renames in shipping:

- The column definition on `objects`.
- The partial index: `create index objects_frame_on_stack on objects(process_pk) where primitive = 'f' and process_pk is not null;`
- The uspace view's frame-anchor branch: `where primitive = 'f' and process_pk is not null`.
- The `processes_complete_after_frame_0_delete` trigger body: `when old.primitive = 'f' and old.process_pk is not null` + `where process_pk = old.process_pk`.

### 6. Seed: one user row → three core-role rows

~~~sql
-- Engine — root of the core-role tree.
insert into objects (primitive, core_role, persistent)
	values ('h', 'e', 1);

-- Cache — child of engine, owned by engine.
insert into objects (primitive, core_role, role_parent, owner_role, persistent)
	values ('h', 'c',
		(select object_pk from objects where core_role = 'e'),
		(select object_pk from objects where core_role = 'e'),
		1);

-- User — child of engine, owned by engine.
insert into objects (primitive, core_role, role_parent, owner_role, persistent)
	values ('h', 'u',
		(select object_pk from objects where core_role = 'e'),
		(select object_pk from objects where core_role = 'e'),
		1);
~~~

### 7. Dissolve ALTER TABLE into CREATE TABLE objects

Every `alter table objects add column ...` in shipping goes away. The columns fold into a single `create table objects (...)` block with logical grouping: identity → discriminator → scalars → role/ownership → frame state → collection back-refs → GC/scratch → debug label. Drop the `-- ############ Mikobase ############` and `-- ############ CVM ############` bands and any prose that speaks of the two concepts as separate.

### 8. Reorder: `create table processes` moves before `create table objects`

Required because `objects.process_pk` has an FK to `processes(process_pk)`, and SQLite with `foreign_keys = on` validates the target table's existence at row-insert time (even when the FK value is null). Move the `create table processes (...)` block and its `processes_no_update` trigger to the top of the file, before `create table objects`.

### 9. Tone down four error messages

~~~
objects_role_or_owner_role: a role cannot have owner_role  (was: … — roles have role_parent, other objects have owner_role, never both)
objects_role_or_owner_role: a non-role must have owner_role set  (was: … — every non-role object must reference the role that created it)
role_parent_must_be_role: role_parent must reference a role  (was: … a row that is itself a role (root user row or a row with role_parent set))
owner_role_must_be_role: owner_role must reference a role  (was: same shape as role_parent_must_be_role)
~~~

### 10. Comment trim

Sweep prose comments down to single-line notes where the thing isn't complicated. Preserve `[ghi]` markers and code-change flags. Keep multi-line explanations only where the design is genuinely non-obvious (the union-not-or rationale on the roles view is the main survivor).

## Shipping-code updates required

The column renames ripple into shipping Lua:

### `src/engine/cvm/init.lua`

- `stmt_add_frame` SQL uses `process` column name — change to `process_pk`:

~~~lua
self.stmt_add_frame = db:prepare(
	"insert into objects (primitive, ast, process_pk, stmt_idx, owner_role) " ..
	"values ('f', ?, ?, 0, ?) returning object_pk"
)
~~~

### `src/engine/cvm/get_latest_frame.lua`

- Docstring line 25 and the prepare on line 68 use `process = ?` — change to `process_pk = ?`.

### `src/engine/cvm/create_frame_0.lua`

- Looks up the user pk with `select object_pk from objects where user` — change to `where core_role = 'u'`.

### `src/engine/engine.lua`

- `stmts.get_process = engine.cvm:prepare('select process from objects where object_pk = ?')` — change SELECT column to `process_pk`.
- `run_frame` reads `row.process` from that result — change to `row.process_pk`.

## Test surgery

Multiple shipping tests still reference the old column names:

- **[test_create_frame_0.lua](https://puck.uno/tests/main/lua/engine/test_create_frame_0.lua)** — `select object_pk from objects where user` (line 134) → `where core_role = 'u'`. `frame_process = row.process` (line 104) and its surrounding SELECT → `row.process_pk`.
- **[test_get_latest_frame.lua](https://puck.uno/tests/main/lua/engine/test_get_latest_frame.lua)** — same shape: `where user` (line 20) → `where core_role = 'u'`; `and process = '%s'` (line 67) → `and process_pk = '%s'`.
- **[test_cvm_engine.lua](https://puck.uno/tests/main/lua/engine/test_cvm_engine.lua)** — `where user` on line 51 → `where core_role = 'u'`. `stmt_idx / idx / process rejected` test at line 1072 and the `process` column INSERT it does on line 1086 → `process_pk`. Also the frame-null-process test at line 1138 → `process_pk`. Also `add_frame inserts a primitive='f' row with ast, process, stmt_idx=0` at line 925 → `process_pk`.
- **[test_end_to_end_state.lua](https://puck.uno/tests/main/lua/engine/test_end_to_end_state.lua)** — `where user = 1` (line 78) → `where core_role = 'u'`.
- **[test_view_indexes.lua](https://puck.uno/tests/main/lua/engine/test_view_indexes.lua)** — the entire "`where user = 1` uses the objects_user partial unique index" test (line 176) needs a rewrite for the new index name and predicate: "`where core_role = 'e'` uses the `objects_core_role` partial unique index" (or similar) with the plan-checking updated.

The test-count baseline of **183 passing** (from the end-to-end integration) must still land at 183 after all updates.

## Docs

- **[sprints/cache/pre-run.md](https://puck.uno/sprints/cache/pre-run)** — the "Pre-run state" page has value as reference material. Promote to `requirements/cvm/pre-run-state.md` (or fold into an existing page). Drop the sprint reference in the vibecode.

## Post-integration cleanup

- Delete `sprints/cache/`.
- No open issues to close for this sprint (nothing filed against the schema in a way that survived).

## Verification

After the moves, both suites must pass with no regressions:

~~~
lua5.4 tests/main/lua/engine/run.lua
~~~

Then re-run the end-to-end sanity check from a fresh Lua process:

~~~lua
local engine = require('engine').new()
engine:load('')
local returned = engine:run()
assert(returned.complete == 1)
assert(returned.message == nil)
~~~

Then inspect a freshly-opened CVM to confirm the three seed rows appear:

~~~lua
local cvm = require('cvm.open')
local cjson = require('cjson')
local db = cvm.open()
for row in db:nrows("select core_role from objects where core_role is not null order by core_role") do
	print(cjson.encode(row))
end
-- expected: {"core_role":"c"}, {"core_role":"e"}, {"core_role":"u"}
~~~

## Sprint boundary

Every step above touches shipping — schema, engine.lua, cvm/*.lua, tests. Requires the explicit trigger — "proceed with the integration" or "proceed with the assimilation" — before any of it lands outside the sprint dir.

## Deferred (out of scope for this integration)

- **Actual cache-role usage.** The `'c'` value is now in the schema and its row is seeded, but no shipping code interacts with the cache role yet. The "Caspian works with objects downloaded from the network" design that motivated this sprint didn't land — the schema is the substrate; the caching behavior itself is a later sprint.
- **owner_role for engine.** Under the new relaxed rule, roles CAN carry `owner_role`. Cache and user do (owned by engine). Engine itself doesn't (root role, no owner). If we later decide engine should own itself or something, that lands separately.
- **Comment sweep in other files.** The trim in this sprint only touched `schema.sql`. Other files in the codebase (engine.lua's docstrings, cvm/*.lua docstrings) still have long prose. If a "trim comments everywhere" sprint is worth its own scope, it goes separately.
- **`process` → `process_pk` mentions in prose.** Some docstrings and doc pages talk about "the process column" — those references become "the process_pk column" wherever they exist. Sweep at integration or leave as follow-up per taste.
