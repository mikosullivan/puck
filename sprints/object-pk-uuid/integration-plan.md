~~~vibecode
{"doc": "sprint-note", "sprint": "object-pk-uuid",
	"role": "Full integration plan: what gets promoted from sprints/object-pk-uuid/ into shipping, in what order, and what specs need updating first. Small sprint — one column-definition swap plus new tests."}
~~~

# Integration plan

Sprint schema at [sprints/object-pk-uuid/src/schema.sql](https://puck.uno/sprints/object-pk-uuid/src/schema.sql) and tests at [sprints/object-pk-uuid/tests/test_object_pk_uuid.lua](https://puck.uno/sprints/object-pk-uuid/tests/test_object_pk_uuid.lua) (12 passing) are ready. Shipping untouched.

## Phase 1 — Requirements

No new spec doc needed — existing CVM docs treat `object_pk` as "an identity string" and don't claim a specific shape. The new CHECK is a refinement, not a contradiction.

Optional one-line addition: [requirements/cvm/index.md](https://puck.uno/requirements/cvm/index.md) — mention that `object_pk` is enforced as a lowercase-hex UUID shape (8-4-4-4-12), with the DEFAULT producing full v4 UUIDs. Fold into the paragraph that already discusses the `objects` row shape.

## Phase 2 — Shipping code

### 2.1 Schema promotion

Column-definition swap in [src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql). Diff summary:

- **DEFAULT** — two extra sub-expressions to force position 15 = `'4'` (v4 version bit) and position 20 ∈ `{8,9,a,b}` (variant bit). Existing DEFAULT already lowercase via wrapping `lower()`; no case change.
- **CHECK** — new two-clause constraint on the column: `check (object_pk like '________-____-____-____-____________' and object_pk not glob '*[^0-9a-f-]*')`. Enforces 36-char length + hyphen positions (via `like`) and lowercase-hex-or-hyphen only (via negated GLOB character class).
- **Column comment** — expanded to describe the shape + case rule + why (SQLite's binary TEXT collation would let uppercase and lowercase live as two distinct PKs).

### 2.2 Merge sprint tests into shipping test_schema.lua

All 12 sprint tests fold into [tests/main/lua/engine/test_schema.lua](https://puck.uno/tests/main/lua/engine/test_schema.lua) as a new section — "Object pk shape and DEFAULT" or similar. Coverage:

- Seeded core-role rows have compliant `object_pk`s.
- DEFAULT produces v4-shaped pks across 100 inserts (version bit at position 15, variant bit at position 20).
- CHECK accepts lowercase v4, accepts loose non-v4 (v1/v3/v7 shapes).
- CHECK rejects uppercase, mixed-case, `'banana'`, wrong-hyphen-positions, non-hex char, historical `'no-such-uuid-...'` sentinel, too-short, too-long.

## Phase 3 — Cleanup

Delete `sprints/object-pk-uuid/`. Git history preserves it.

## Ordering summary

1. Phase 1 (optional doc note).
2. Phase 2.1: promote schema column.
3. Phase 2.2: merge sprint tests into `test_schema.lua`.
4. Phase 3: archive sprint dir.
