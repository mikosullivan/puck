~~~vibecode
{"doc": "sprint-note", "sprint": "first-variable",
	"role": "Full integration plan: what gets promoted from sprints/first-variable/ into shipping, in what order, and what specs need to land in requirements/ first. Companion to integration-notes.md (which is the small-item running list); this doc is the ordered plan."}
~~~

# Integration plan

The sprint is in pre-integration mode. All design and code work is done in-tree under [sprints/first-variable/](./); 80 tests pass; `larry:load('$x = 1'); larry:run()` runs end-to-end through the dispatch chain up to the first-GC boundary. Nothing has been promoted to shipping yet.

This is the ordered plan to promote.

## Ground rule: spec before code

Per [CLAUDE.md](../../CLAUDE.md#L217): "Nothing implemented before its spec lands in `requirements/`." No `src/` edits until the corresponding `requirements/` doc lands.

## Phase 1 — Requirements specs

Six spec docs need to land under `requirements/` before any code moves. Each captures one load-bearing piece of the sprint's schema-level design.

### 1.1 Cap-as-frame

**Content:** A process is a `primitive='f'` cap row with `process = 1` and `ast = '[]'`, no parent. Its `object_pk` IS the process identity. Frame 0 sits under the cap as a nested frame. Cap advances 0→1 with gc=1 as its terminal transition — same gc-cycle machinery as every other frame. Terminal state signals "program is done."

**Source in sprint:** [frame-fields.md](./frame-fields.md), [schema.sql:56-110](./schema.sql), [walkthrough.md](./walkthrough.md) intro rules.

### 1.2 gc-cycle invariants

**Content:** The four rules that shape the walker's advance-and-cleanup:

1. Advancing `stmt_idx` requires setting `gc = 1` in the same UPDATE.
2. Setting `gc = 1` cascade-deletes child frames.
3. A child frame can only be deleted when its parent's `gc = 1`.
4. Resetting `gc = null` requires no child frames.

Plus: the delete rule (`gc must be null when deleting`) — narrower than "past-max terminal state" (early return is legal at any stmt_idx).

**Source in sprint:** [gc-fixed-point.md](./gc-fixed-point.md), [schema.sql:308-397](./schema.sql), [frame-fields.md](./frame-fields.md).

### 1.3 Refs-based ownership

**Content:** No dedicated `bucket_pk` / `stack_pk` / `bucket_for` / `stack_for` columns. Ownership of a bucket or stack is a normal `refs` row from the owner to the collection. Non-container parents (`primitive in ('o', 'f')`) are capped at one hash-child (their bucket) and one array-child (their stack). Containers (`'h'`, `'a'`) hold unlimited refs by native semantics. Buckets and stacks can be shared across multiple owners. Cascade cleanup runs through the existing `refs_mark_needs_trace_after_delete` — no bespoke per-column triggers.

**Source in sprint:** [schema.sql:190-227](./schema.sql), sprint tests around the one-hash-one-array cap.

### 1.4 Scopes convention

**Content:** A frame's bucket has a `scopes` key pointing at an ArrayPrimitive. Entries in that array are hash primitives — scope[0] is the frame's own locals; scope[1..] are captured scopes from enclosing closures. Plus the hash-key identifier rule (keys must match `[a-zA-Z_][a-zA-Z0-9_]*` — a regex-shaped GLOB via trigger).

**Source in sprint:** [closures.md](./closures.md), [schema.sql:283-341](./schema.sql), [cvm/frame.lua](./cvm/frame.lua) `ensure_own_scope`.

### 1.5 `frame_scoped_vars` view

**Content:** Flattened lookup view — `(frame_pk, scope_idx, var_name, value_pk)` for every visible binding on every frame. `ORDER BY scope_idx LIMIT 1` gives the effective binding (nearest scope wins). All joins indexed; graceful (empty result) when any link in the bucket → scopes → scope[N] → var chain is missing.

**Source in sprint:** [schema.sql:755-790](./schema.sql).

### 1.6 `object_bucket` / `object_stack` views

**Content:** Convenience views — `(object_pk, bucket_pk)` and `(object_pk, stack_pk)` for every non-container object. `bucket_pk` / `stack_pk` is the object's one hash-child (or array-child), or null. **Note in the spec that no shipping caller depends on these yet** — they're speculative-utility, kept because the underlying join is annoying to write by hand.

**Source in sprint:** [schema.sql:793-834](./schema.sql).

## Phase 2 — Shipping code

Once specs are in `requirements/`, code moves. Order matters — later steps depend on earlier ones.

### 2.1 Schema promotion

`sprints/first-variable/schema.sql` → `src/engine/cvm/schema.sql`. Big diff:

- Drop `processes` table + its triggers.
- Add `process` boolean column on `objects` (was `process_pk` FK).
- Drop `bucket_for` / `stack_for` / `bucket_pk` / `stack_pk` columns and every trigger / check that operated on them.
- Add `refs_owner_at_most_one_hash_and_one_array` trigger.
- Loosen (or drop) `refs_parent_must_be_primitive_container` — any primitive can be a ref parent now.
- Add the four gc-cycle triggers.
- Add scopes-convention triggers.
- Add hash-key identifier trigger.
- Add `frame_scoped_vars`, `object_bucket`, `object_stack` views.
- Move `cvm` marker table to top of file (already done in sprint schema).

### 2.2 `cvm/frame.lua` promotion

Sprint's [cvm/frame.lua](./cvm/frame.lua) → `src/engine/cvm/frame.lua`. Brings `set_local_to_scalar`, `own_scope`, `ensure_own_scope`. Also apply [integration-notes.md](./integration-notes.md) item — strip "popped-but-captured" language from the shipping module docstring.

### 2.3 `cvm/init.lua` rewrites

Rewrite `add_bucket` / `add_stack`. Shipping form uses `bucket_for` / `stack_for` at insert time; that column set is gone. New form (same shape as [larry.lua](./larry.lua)'s sprint overrides): check for an existing hash-child (or array-child) via refs; if none, insert the collection with inherited `owner_role` and call `add_ref(owner, nil, new_pk)` to link them.

### 2.4 `engine.lua` rewrites

Substantial. Shipping's `Engine:run` and `Engine:run_frame` reference the removed `processes` table + `process_pk` column and use the old advance-then-delete pattern. Rewrite along the lines of [larry.lua](./larry.lua)'s `Larry:run`:

- Seed cap (`primitive='f'`, `process=1`, `ast='[]'`) + frame 0 under it.
- Walk frame 0's ast — per statement: set `self.current_frame` (new), dispatch, advance with `stmt_idx += 1, gc = 1`, reset `gc = null`.
- After ast exhausts: advance cap 0→1 with gc=1 (cascades frame 0), reset cap gc. Cap is terminal.
- Return the completion signal derivable from cap state; no `processes` row to reap.

Also add `self.current_frame` to the engine's public field set, set before each dispatch so handlers can reach the frame. Update `create_frame_0` / `get_latest_frame` accordingly.

### 2.5 `handlers/variable-scalar.lua` real body

Replace the always-true stub with the sprint's [handler](./handlers/variable-scalar.lua). One method body — match `{in='as'}` head, unpack, call `frame:set_local_to_scalar`.

## Phase 3 — Tests & verification

### 3.1 Migrate sprint tests

Move (or rewrite for shipping) the sprint's [test_schema.lua](./test_schema.lua) and [test_larry.lua](./test_larry.lua) into the shipping test tree (`tests/`). 80 tests total. Some are Larry-specific (bypass the handler chain to isolate write mechanics); those become shipping-equivalent tests once Larry's overrides are subsumed by shipping.

### 3.2 Shipping end-to-end test

Add a shipping-side equivalent of Larry's `$x = 1 end-to-end through the dispatch chain` test: `engine:load('$x = 1'); engine:run()`, assert cap terminal + bucket needs_trace-marked.

### 3.3 Verify existing shipping tests still pass

Shipping's current test suite exists against the OLD schema shape (processes table, etc.). Most tests will need adjustment. Walk each; either update, delete (if it tested a removed rule), or migrate to the new shape.

## Phase 4 — Cleanup

### 4.1 Address deferred integration items

- [integration-notes.md](./integration-notes.md) — one item currently (strip "popped-but-captured" from shipping frame.lua). Handled as part of 2.2.
- **Issue #1569** — reminded via memory `project_install_infrastructure_rework_after_promotion`. `requirements/bootstrap/initialize-vm/install-infrastructure/index.md` needs rework because the promoted schema changes what DDL install does. Close after rework.

### 4.2 Archive sprint dir

Once everything's promoted, delete or archive `sprints/first-variable/`. Keep it in git history via the tag.

## Deferred / not blocking

- **GC substrate.** Mikobase-owned (per memory `project_gc_lives_in_mikobase`). The sprint (and integrated shipping) stop at "cap terminal, orphans marked `needs_trace = 1`." Full trace-and-sweep reap lives with GC-substrate work.
- **Q0 sidesprint** at [../q0-for-rules-enforcement/](../q0-for-rules-enforcement/) — paused CSS-analogy pattern discussion. Doesn't block integration.
- **every-statement-a-frame** at [../every-statement-a-frame/](../every-statement-a-frame/) — separate design, not being implemented. Doesn't block integration.

## Ordering summary

1. Phase 1: write specs (six docs in `requirements/`).
2. Phase 2.1: promote schema.
3. Phase 2.2–2.5: promote code files.
4. Phase 3.1–3.2: migrate/write tests, verify end-to-end.
5. Phase 3.3: fix existing shipping tests against new schema.
6. Phase 4.1: close deferred items.
7. Phase 4.2: archive sprint dir.
