~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "numbers",
	"role": "Step-by-step plan for landing the numbers sprint into production. Sequenced so intermediate states never break the production test suite: the schema copies first, the Lua code copies next, then production tests get their column-name sweep, then docs, then the sprint dir is torn down. Every step is a discrete commit so a bisect can pinpoint any regression to one change.",
	"status": "planned"}
~~~

# numbers-sprint integration plan

## What's being landed

Production baseline is schema 9.3 with the polymorphic `scalar_type` + `scalar_value` pair, single `primitive` column, unprefixed frame/role columns, and a `(scalar_type, scalar_value)` write API. The sprint replaces all of that. Full change list is in [sprints/numbers/index](https://puck.uno/sprints/numbers/); this doc is about how to land it.

## Preconditions

- Sprint tests green: `for f in sprints/numbers/tests/*.lua; do lua5.4 $f; done` — 57/57.
- Production tests green at HEAD before starting.
- Production locked. Unlock with `chmod -R u+w production/`.
- Working tree clean of anything unrelated.

## Ordering rationale

The sprint's schema and Lua code are internally consistent, but the production TEST SUITE isn't — it queries `scalar_value`, `primitive`, `parent_frame`, etc. If we land the schema without updating the tests, the whole production suite breaks in one step. If we land the tests first, they run against the OLD schema and stay green trivially — nothing enforces the correspondence.

The order below lands sprint changes in slices that each keep some subset of tests running. Total: 8 commits.

## Commit-by-commit plan

### Commit 1: schema + Lua code together

The atomic unit — schema and the Lua that talks to it can't be split without breaking `engine.new()`. Everything the runtime touches lands here.

- `production/src/engine/cvm/sqlite/schema.sql` — replaced by sprint's version (schema 12.0). Four typed scalar columns, base+control split, field renames, `scalars` view.
- `production/src/engine/cvm/sqlite/init.lua` — replaced with sprint's. Polymorphic `add_scalar`, four prepared statements per scalar type, wrapper dispatch on `control`.
- `production/src/engine/cvm/sqlite/frame.lua` — replaced. `set_local_to_scalar(name, value)` signature; `frame.new` guard on `row.control ~= 'f'`.
- `production/src/engine/cvm/sqlite/object.lua` — replaced. Wrapper dispatch on `row.control == 'f'`.
- `production/src/engine/engine.lua` — replaced. `insert_cap` / `insert_frame_0` prepared statements use the new columns.
- `production/src/engine/handlers/variable-scalar.lua` — replaced. Handler passes value directly to `set_local_to_scalar`; no scalar_type computation.

**State at end of commit 1:** every existing production test that touches the renamed columns is broken. Sprint tests can't run against production (they live in the sprint dir, which is still there). Nothing is production-usable end-to-end from a test-verification standpoint.

**Verification for this commit:** run `lua5.4 production/tests/main/lua/engine/run.lua` — expect failures (that's normal at this step); confirm failures are all "column doesn't exist" / "no such column" — not schema-apply errors or Lua parse errors.

### Commit 2: production test sweep — column-name migration

The mechanical follow-up to commit 1. Every SQL query in the production test suite that names a renamed column needs updating.

Files to touch (14 test files across the engine suite):

- `production/tests/main/lua/engine/sqlite/test_ast_shape.lua`
- `production/tests/main/lua/engine/sqlite/test_boot.lua`
- `production/tests/main/lua/engine/sqlite/test_cvm.lua`
- `production/tests/main/lua/engine/sqlite/test_current_process_pk.lua`
- `production/tests/main/lua/engine/sqlite/test_debug_log.lua`
- `production/tests/main/lua/engine/sqlite/test_end_to_end.lua`
- `production/tests/main/lua/engine/sqlite/test_end_to_end_state.lua`
- `production/tests/main/lua/engine/sqlite/test_needs_trace_lifecycle.lua`
- `production/tests/main/lua/engine/sqlite/test_process_stop.lua`
- `production/tests/main/lua/engine/sqlite/test_schema.lua`
- `production/tests/main/lua/engine/sqlite/test_second_assignment.lua`
- `production/tests/main/lua/engine/sqlite/test_view_indexes.lua`
- `production/tests/main/lua/engine/helpers.lua`
- `production/tests/main/lua/execution/helpers.lua`

Rewrites are word-boundary substitutions:

- `primitive` (as a column reference) → depends on the value it was checking: `primitive = 'X'` where X ∈ {f,r} → `control = 'X'`; where X ∈ {h,a,o} → `base = 'X'`; standalone `primitive` in a SELECT list → split into `base, control`.
- `scalar_value` → depends on scalar_type of the row being tested: `scalar_string` / `scalar_number` / `scalar_bool` (or `scalar_null` for the u case). Most tests that write a scalar know the type at write time; rewrite the INSERT to use the right column.
- `scalar_type` → gone entirely as a column. Tests that read `scalar_type` need to switch to the `scalars` view or derive from which scalar_* column is non-null.
- `ast` → `frame_ast`; `stmt_idx` → `frame_stmt_idx`; `process_cap` → `frame_process_cap`; `parent_frame` → `frame_parent`; `gc` → `frame_gc`; `core_role` → `role_core`; `parent_role` → `role_parent`.
- Insert statements creating frames or roles need to bind both `base` and `control` (`base='o', control='f'` for frames; `base='o', control='r'` for roles).

Some tests will need SEMANTIC rewrites too: `test_schema.lua`'s CHECK-constraint tests specifically test the OLD constraints. Those tests either delete (the constraint no longer exists) or update (to test the NEW constraint at its new name). Expect ≈10–20 tests that go beyond a mechanical rename.

**Verification for this commit:** `lua5.4 production/tests/main/lua/engine/run.lua` should now pass fully. If a test fails, either the sweep missed a column or the test's semantic depended on the old shape.

### Commit 3: copy the sprint's own test files into production

Four new test files that don't exist in production yet — they cover the new API directly rather than the old shape.

- `production/tests/main/lua/engine/sqlite/test_scalar_columns.lua` (from sprint).
- `production/tests/main/lua/engine/sqlite/test_add_scalar.lua` (from sprint).
- `production/tests/main/lua/engine/sqlite/test_variable_scalar.lua` (from sprint).
- `production/tests/main/lua/engine/sqlite/test_x_equals_1.lua` (from sprint).

Each file needs its `SPRINT_SCHEMA` path removed (it should use production's default schema resolution) and its `package.path` prepend cleaned up. Otherwise verbatim.

**Verification:** the four new files register with `run.lua`'s discover-then-execute pattern; expect +57 tests in the total.

### Commit 4: docs — Number spec and object/structure

Two production docs whose content the sprint changed.

- `production/requirements/built-in-classes/primitives/number/index.md` — replace the "implementation-detail hedge" paragraph and the `.integer?` test-row line with the sprint's versions. Drop the `.to_integer` / `.to_float` parenthetical from the "no int-vs-float promotion rules" sentence.
- `production/requirements/built-in-classes/object/structure/index.md` — the "Number — the raw integer or fractional bits" line becomes "Number — the raw float bits."

**Verification:** open both in Orlando (`http://127.0.0.1:8181/requirements/built-in-classes/primitives/number` etc.); confirm the hedge text is gone and the `.integer?` test row reads unambiguous.

### Commit 5: ER diagram

The sprint's own `schema.svg` is in [sprints/numbers/requirements/cvm/sqlite/schema.svg](https://puck.uno/sprints/numbers/requirements/cvm/sqlite/schema.svg) and is already schema-order-correct with `base` / `control` / `frame_process_cap` all rendered.

- Copy `sprints/numbers/requirements/cvm/sqlite/schema.svg` → `production/requirements/cvm/sqlite/schema.svg`.

Follows the SVG's own vibecode's sprint-integration rule (which was added to the schema.svg vibecode after the trace-tables sprint lost its diagram at assimilation).

**Verification:** `curl -sI http://127.0.0.1:8181/requirements/cvm/sqlite/schema.svg` returns 200; visual check in Orlando or Inkscape.

### Commit 6: syntax docs — float-variant tests

Two production docs picking up the float-variant test additions.

- `production/requirements/syntax/operators.md` — six new "Fractional X" test entries alongside the six "Integer X" entries; rename the existing "Float addition" to "Fractional addition"; rename "Mixed int + float returns float" to "Mixed whole-value and fractional operands."
- `production/requirements/syntax/variables-and-assignment.md` — six new fractional compound-assignment test entries.

**Verification:** grep confirms the added lines are present in both files.

### Commit 7: promote the walkthrough

`sprints/numbers/x-equals-1.md` is a useful reference for how the shape works end-to-end. Best home in production: alongside the CVM docs.

- Copy `sprints/numbers/x-equals-1.md` → `production/requirements/cvm/sqlite/x-equals-1.md`.
- Add a bullet link from `production/requirements/cvm/sqlite/index.md`'s per-doc list (alongside `frame-lifecycle`, `scopes`, `pause-resume`, etc.).

**Verification:** Orlando renders `http://127.0.0.1:8181/requirements/cvm/sqlite/x-equals-1` cleanly with the `tbl-cvm`-classed table rendering with the light-blue role rows and light-yellow frame rows.

### Commit 8: sprint teardown

Nothing else to do inside `sprints/numbers/`; every file has landed somewhere in production. Delete the sprint dir.

- `git rm -rf sprints/numbers/`.

**Verification:** `ls sprints/` — sprint gone; remaining sprints untouched.

## Post-integration

- Full test suite one more time: `lua5.4 production/tests/main/lua/engine/run.lua`. Expect the total count to be ≈ prior + 57 (sprint tests) − however many production tests were removed as obsolete (test_schema constraints for `primitive` column, etc.).
- Restart Orlando: `bash orlando/lua/stop.sh; bash orlando/lua/start.sh`. Picks up the new ER diagram and updated docs.
- Refresh Orlando's issue cache: `curl -s -X POST http://127.0.0.1:8181/api/refresh-issues`.
- Lock production: `chmod -R a-w production/`.
- `git push` — if committing in slices, push after the whole plan lands rather than per-commit (so origin never sees a partially-landed state).

## Rollback

Every commit in the plan is a single-file-set change; the whole plan is 8 commits. If any commit turns out wrong:

- **Between commits:** stop, `git reset --hard` to before the wrong commit, redo from that point.
- **After push:** revert commits in reverse order (`git revert HEAD~N..HEAD`). Since the plan is ordered so intermediate states break-then-fix (commit 1 breaks tests, commit 2 fixes them), reverting commit 2 without also reverting commit 1 leaves production broken — always revert as a group ending back at "before the plan started."
- **Data:** there's no persistent-state migration to unwind — the CVM is walking-skeleton, every test creates its own in-memory DB.

## Estimated effort

- Commit 1 (schema + Lua): ~20 min. Mechanical file replacement; the sprint dir has everything ready.
- Commit 2 (test sweep): ~90 min. The largest single-commit — 14 files, ≈159 grep hits, mix of mechanical renames and semantic rewrites. Some test cases will need real thought (schema CHECKs that tested the old constraint's rejection language).
- Commit 3 (sprint tests): ~15 min. Copy + path prep.
- Commit 4 (Number spec + structure doc): ~15 min. Small edits.
- Commit 5 (ER diagram): ~5 min. Single-file copy.
- Commit 6 (syntax docs): ~10 min. Two files, block additions.
- Commit 7 (walkthrough promote): ~10 min.
- Commit 8 (teardown): ~5 min.

Total: ~2h 45m for someone doing it in one session. Commit 2 dominates; if broken into per-file commits it'd stretch to more like 3h 30m but each intermediate state would be smaller.
