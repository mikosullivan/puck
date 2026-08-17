~~~vibecode
{"doc": "sprint-note", "sprint": "roles-as-primitives",
	"role": "Full integration plan: what gets promoted from sprints/roles-as-primitives/ into shipping, in what order, and what specs need to land in requirements/ first. Companion to the sprint index; this is the ordered plan for the promotion."}
~~~

# Integration plan

The sprint's schema at [sprints/roles-as-primitives/src/schema.sql](https://puck.uno/sprints/roles-as-primitives/src/schema.sql) and tests at [sprints/roles-as-primitives/tests/test_role_primitive.lua](https://puck.uno/sprints/roles-as-primitives/tests/test_role_primitive.lua) are ready. Shipping is untouched. This is the ordered plan to promote.

## Ground rule: spec before code

Per the project's CLAUDE.md rule ("Nothing implemented before its spec lands in `requirements/`"), all requirements-doc updates land first. No `src/` edits until the corresponding requirements docs are in.

## Phase 1 — Requirements

Three documents need updates. Nothing new to create — the roles-as-primitives change is a refinement of existing role machinery, not a new subsystem.

### 1.1 `requirements/cvm/index.md`

- Add `'r' → role` to the primitive discriminator description.
- Rework the paragraph that currently describes roles as HashPrimitives — "a role is an `objects` row with `primitive = 'r'`."
- Note the cross-column check ("only 'r' rows can carry `core_role` or `parent_role`") as the reason critique § 3 is closed.

### 1.2 `requirements/cvm/pre-run-state.md`

- Rewrite the three seeded rows to show `primitive = 'r'` instead of `'h'`.
- Update the surrounding prose ("all three are role primitives and pinned").

### 1.3 `requirements/cvm/garbage-collection/index.md`

- Update the FK-column inventory. The paragraph currently says "eight FK columns pointing at `objects(object_pk)` — two self-references on `objects` (`role_parent`, `owner_role` ...". Change `role_parent` → `parent_role`.
- Add a note that role rows (`primitive = 'r'`) can never be ref parents, so they never need needs_trace marking from the ref-delete trigger's normal path (roles being unable to hold children means they don't accumulate incoming ref-drops).

### 1.4 Optional: a small standalone spec

If a dedicated page reads better than folding into `cvm/index.md`, add `requirements/cvm/roles.md` — one-section explainer of the roles-as-primitives design (what a role IS, the single-root guarantee, the cycle-free-by-construction property, roles can't carry state). Format mirrors [requirements/cvm/ownership.md](https://puck.uno/requirements/cvm/ownership) or [requirements/cvm/scopes.md](https://puck.uno/requirements/cvm/scopes).

## Phase 2 — Shipping code

Once specs land:

### 2.1 Schema promotion

[sprints/roles-as-primitives/src/schema.sql](https://puck.uno/sprints/roles-as-primitives/src/schema.sql) → [src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql). Diff summary:

- `primitive` CHECK domain gains `'r'`; row-kind comment updated.
- `core_role` and `parent_role` gain cross-column checks (only on `'r'` rows).
- `persistent` gains a cross-column check: `check (core_role is null or persistent is 1)`. Core-role rows must be pinned at INSERT. Uses `is 1` not `= 1` because SQL three-valued logic makes `null = 1` yield NULL (which doesn't fire a CHECK); `null is 1` yields false (which does). Comment on the column expanded to spell out both sides — core rows must be pinned, non-core rows default to unpinned.
- Column rename: `role_parent` → `parent_role` (35 occurrences in the sprint schema, all mechanical).
- Trigger renames: `objects_role_parent_immutable` → `objects_parent_role_immutable`, `objects_role_parent_not_self` → `objects_parent_role_not_self`, `objects_role_parent_must_be_role` → `objects_parent_role_must_be_role`.
- Index rename: `objects_role_parent` → `objects_parent_role`.
- `roles` view collapses from UNION-of-two to `select object_pk from objects where primitive = 'r'`.
- New trigger `refs_role_cannot_be_parent`.
- Trigger rewrites: `objects_owner_role_required_on_non_roles` (WHEN clause), `objects_parent_role_must_be_role` (direct primitive check), `objects_owner_role_must_be_role` (direct primitive check).
- New trigger `objects_only_engine_can_be_role_root`.
- Seed inserts: `primitive = 'h'` → `'r'` for engine/cache/user.
- `parent_role` FK: `on delete cascade` removed → NO ACTION (RESTRICT) — deleting a role is blocked while any other role references it.

### 2.2 Rename sweep in Lua + tests

The `role_parent` → `parent_role` rename touches sources beyond the schema. Search-and-replace targets:

- Any Lua that references the column name in SQL strings (search: `role_parent`).
- Existing shipping tests that create role-shaped rows using the old column name.

### 2.3 Shipping test updates

Shipping's [tests/main/lua/engine/test_schema.lua](https://puck.uno/tests/main/lua/engine/test_schema.lua) currently has role-related tests that assume the old shape (seeded rows are `primitive='h'`, `role_parent` column name). Fold the sprint tests in and update the existing ones:

- Seeded-row tests: assert `primitive = 'r'` for engine/cache/user, `persistent = 1` for all three.
- Any test creating a role: use `primitive = 'r'`, `parent_role` (renamed).
- Add the sprint's coverage: `'r'` cannot be a ref parent, single-root guarantee, roles view = `'r'` rows, delete-with-children blocked, cycle-free-by-construction note.
- Core-role persistent coverage: INSERT with null-persistent rejected (uses a scratch schema with seeds stripped so the core_role unique index doesn't intercept), UPDATE that clears persistent rejected on all three seeded roles.
- Non-core persistent coverage: default (no `persistent` in the INSERT) yields null, opt-in with `persistent = 1` accepted, `persistent = 0` rejected by the existing `check (persistent = 1)`.

### 2.4 schema.svg regeneration

[requirements/cvm/schema.svg](https://puck.uno/requirements/cvm/schema.svg) shows the schema pictorially. `role_parent` appears in the diagram; needs regenerating with the new column name and (ideally) the new primitive kind.

## Phase 3 — Cleanup

### 3.1 Sprint archive

Once everything's promoted, delete `sprints/roles-as-primitives/`. Git history preserves it.

### 3.2 Scrub sprint-tagged doc language

The sprint schema comment above the roles view reads "Under the roles-as-primitives design a role is `primitive = 'r'`" — on promotion, drop the sprint tag: "A role is `primitive = 'r'`."

### 3.3 Consider dropping `objects_no_update_root_role` entirely

Under the promoted schema, every column the trigger guards is already blocked by another rule:

- `object_pk`, `primitive`, `scalar_type`, `scalar_value`, `ast`, `stmt_idx`, `process`, `parent_frame`, `core_role`, `parent_role`, `owner_role` — all covered by their own dedicated immutability triggers (`objects_pk_immutable`, `objects_primitive_immutable`, etc.) or by cross-column CHECKs that reject the change.
- `persistent` — covered by the new `check (core_role is null or persistent is 1)`. Verified: CHECK constraints fire on UPDATE too — an UPDATE that clears persistent on a core-role row raises `CHECK constraint failed: core_role is null or persistent is 1`.
- `gc` — restricted to `primitive = 'f'` rows by the column-level CHECK, so a core-role row (`primitive = 'r'`) can't hold a non-null gc in the first place. UPDATE to gc on a core-role row would need to leave gc null; setting it to 1 fails the frame-only CHECK.

If dropping the trigger, the failing error strings change from `root_role_cannot_be_updated: ...` to whatever the underlying rule raises (a specific immutability trigger name, or `CHECK constraint failed: ...`). Tests that assert the specific `root_role_cannot_be_updated` string will need updating. Alternative: keep the trigger as defense-in-depth and a stable failure identifier for callers. Decide at promotion time.

## Ordering summary

1. Phase 1: update the three (or four) requirements docs.
2. Phase 2.1: promote schema.
3. Phase 2.2: rename sweep across the tree.
4. Phase 2.3: update / extend shipping test_schema.lua.
5. Phase 2.4: regenerate schema.svg.
6. Phase 3.1: archive sprint dir.
7. Phase 3.2–3.3: comment scrubs + optional trigger simplification.
