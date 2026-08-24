~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "object",
	"role": "Ordered plan for landing the object sprint into production. Two tracks: Track 1 is landable now — the b/p/s object-property shape (schema triggers + views + engine-code sweep from keyless bucket refs to key='b'/'p'/'s') and the dispatch design doc. Track 2 is deferred — the Lua-side object and obj class implementations, plus the `.obj` fast-path in the dispatcher, all of which need the (still-unwritten) method-call primitive to land first. Includes an outstanding-issues section for design gaps and cross-sprint dependencies.",
	"status": "planned — Track 1 concrete; Track 2 waits on the method-call sprint"}
~~~

# object-sprint integration plan

## What's landing

The sprint delivered, in decreasing readiness:

- **b/p/s object-property shape** (schema-level) — every base='o' object's structural properties live as keyed refs (`key='b'` → bucket, `key='p'` → platters, `key='s'` → shadow), with four schema triggers enforcing the invariant. Fully tested (`test_bps.lua`, 22 assertions).
- **Views** — `object_bucket`, `object_platters` (renamed from `object_stack`), and the new `object_shadow`. Simple view rewrites.
- **Dispatch design** — [sprints/object/dispatch.md](./dispatch) documents the walk order (shadow → platters → primitive class → engine class → miss raises), the `.obj` name-check fast-path, and the platter-participation rule (a platter must carry a `class` element to be considered during method search).
- **Concept: engine_class is implicit-at-bottom of the dispatch chain.** Same-shape argument as primitive-class-at-bottom. Zero enforcement work; the rule is how the dispatcher orders its lookups.
- **Lua-side Object + obj classes** (sprint-only for now) — [object.lua](./src/object.lua) provides the wrapper skeleton (pk + engine + db), [obj.lua](./src/obj.lua) provides the agent constructor + `.pk` catalog method. Not integrated with production — depend on the dispatcher and method-call primitive that don't exist yet.
- **MethodCall stub handler** (sprint-only) — [method_call.lua](./src/method_call.lua) recognizes fc-shape rows and dispatches via the `.obj` fast-path + the `engine_class='obj'` layer. Minimum needed to run `$foo = 'bar'; $foo.obj.pk` end-to-end for the sprint's proof. Gets superseded by the real method-call primitive when the [method-call sprint](https://puck.uno/sprints/method-call/) lands.

Not everything lands in a single integration pass. The schema + docs are ready; the Lua modules stage behind the method-call sprint moving off seed-only.

## Preconditions

- Sprint's own tests all green:
  - `lua5.4 sprints/object/src/test_bps.lua`         — 22/22
  - `lua5.4 sprints/object/src/test_object.lua`      —  6/6
  - `lua5.4 sprints/object/src/test_obj.lua`         — 13/13
  - `lua5.4 sprints/object/src/test_foo_dot_obj.lua` — 15/15
- Production tests green at HEAD before starting.
- Production locked. Unlock with `chmod -R u+w production/`.
- Working tree clean of anything unrelated.

## Ordering rationale

Two tracks, one landable now, one waiting on upstream:

- **Track 1 — schema + engine + docs.** The b/p/s shape is a schema migration that cascades into engine-code updates (every keyless bucket/stack insertion becomes a keyed one). Bigger than the expressions-sprint's Track 1 was, but self-contained. No cross-sprint dependencies.
- **Track 2 — Lua-side class implementations + `.obj` fast-path.** Depends on the method-call primitive being real. The current sprint's Lua modules (object.lua, obj.lua, obj.methods.pk) are dead code without a dispatcher to call them. They stage behind the [method-call sprint](https://puck.uno/sprints/method-call/) landing.

Track 1 can go first. Track 2 stages behind the method-call sprint.

## Track 1: schema + engine + docs

### Commit 1: schema b/p/s enforcement

Copy the four new triggers from [sprints/object/src/schema.sql](./src/schema.sql) into `production/src/engine/cvm/sqlite/schema.sql`:

- `refs_object_parent_key_must_be_bps` — refs from base='o' parents must have key in ('b','p','s'); null and other values rejected.
- `refs_key_b_target_must_be_hash` — key='b' → target base='h'.
- `refs_key_p_target_must_be_array` — key='p' → target base='a'.
- `refs_key_s_target_must_be_hash` — key='s' → target base='h'.

Remove the now-incompatible `refs_owner_at_most_one_hash_and_one_array` trigger (its cap-of-one-hash is wrong under b/p/s where bucket and shadow are both hashes; uniqueness `(parent, key)` gives us the per-key cap for free).

Rewrite the top-of-file comment paragraph explaining the b/p/s shape (see the sprint schema's version for the model).

**Verification for this commit alone:** schema loads without errors. Production tests will FAIL at this point because production engine code still uses the keyless-ref pattern — that gets fixed in the next commit.

### Commit 2: engine-code sweep — keyless bucket refs → key='b'

Every place production engine code inserts a ref linking an owner ('o'-row) to its bucket ('h'-row) with `key = null` becomes `key = 'b'`. Same for platters (`key = 'p'`, array target) and shadow (`key = 's'`, hash target) if any exist. Sites include:

- `production/src/engine/cvm/sqlite/init.lua` — `stmt_add_bucket_insert`, `stmt_add_stack_insert`, `stmt_find_hash_child`, `stmt_find_array_child`. Rename `add_stack` → `add_platters` and `stmt_find_hash_child` / `stmt_find_array_child` to key-based lookups. Add `add_shadow` if this pass wants to grow the surface; otherwise defer.
- `production/src/engine/cvm/sqlite/object.lua` — `bucket()`, `stack()` accessors. Rename `stack` → `platters`; add `shadow()`.
- `production/src/engine/cvm/sqlite/frame.lua` — `own_scope`, `ensure_own_scope`. The frame's bucket lookup changes from base-filter to `key='b'` filter.
- `production/src/engine/cvm/sqlite/schema.sql` — bucket-related subqueries in `frames_child_delete_propagates_rv` trigger, `frame_scoped_vars` view, `object_bucket` view. All need `refs.key = 'b'` filters instead of base-of-child filters. Rename view `object_stack` → `object_platters`; add new `object_shadow`.
- Any other Lua module that does `select ... from refs where parent = <o-row> and key is null` (grep for the pattern).

**Verification:** all existing production tests pass again. The keyless-ref pattern is fully migrated.

### Commit 3: test sweep

Update the tests that check the keyless pattern to use the new keyed pattern. `production/tests/main/lua/engine/sqlite/test_schema.lua` has the biggest surface — the block asserting `refs_owner_at_most_one_hash_and_one_array` invariants should be replaced with tests for the four new b/p/s triggers. The b/p/s tests already exist in [sprints/object/src/test_bps.lua](./src/test_bps.lua); port them into production's test tree.

**Verification:** full production test suite green.

### Commit 4: version bump + vibecode sweep

- Bump schema version from `12.1` → `13.0-object-sprint`.
- Update the top-of-file vibecode: `refs` role paragraph rewritten around b/p/s; new `object_properties_shape` field naming the four enforcement triggers; `immutability` paragraph updated (bucket, platters, shadow ownership are refs rows); views section mentions `object_platters` and `object_shadow`.

### Commit 5: promote dispatch design docs + spec sweeps

- Promote [sprints/object/dispatch.md](./dispatch) to `production/requirements/objects/dispatch.md` (or similar — pick the right home under existing requirements/ layout).
- Promote the "four object properties" section from [sprints/object/index.md](./) — either inline into an existing objects doc or new `production/requirements/objects/anatomy.md`.
- Update `production/requirements/cvm/sqlite/frame-lifecycle.md` and `production/requirements/expressions/frame-advancement.md` to reference the new `b/p/s` refs shape (they currently name buckets by base-filter).
- **`.id` → `.pk` sweep.** Rename every `.obj.id` mention to `.obj.pk` across `production/requirements/`. The bulk lives in [built-in-classes/object/methods/index.md](https://puck.uno/production/requirements/built-in-classes/object/methods/) (~10 mentions); the section header for `.id` becomes `.pk`; scattered references (the vibecode role paragraph, the destroy/destroyed docs' "callable after destroy" note, the identity-comparison example) all follow. Spec-only change; no code touched here since `.pk`'s implementation is Track 2.

### Commit 6: teardown of the sprint's now-promoted content

- Delete `sprints/object/src/schema.sql` (landed).
- Delete `sprints/object/src/test_bps.lua` (equivalent tests now live in production tests).
- Delete `sprints/object/dispatch.md` (promoted).
- Keep in `sprints/object/` (until Track 2 lands):
  - `src/object.lua`, `src/obj.lua`, `src/test_object.lua`, `src/test_obj.lua`, `src/test_foo_dot_obj.lua` — Track 2 depends on these.
  - `index.md`, `integration.md` — sprint-internal.

## Track 2: Lua-side class implementations + real method-call

**Prereq:** Track 1 landed; [method-call sprint](https://puck.uno/sprints/method-call/) has landed the real dispatcher + method-call primitive. The sprint's [MethodCall stub](./src/method_call.lua) covers the object sprint's needs but isn't a general primitive — Track 2 replaces it with the real thing and inherits the sprint's Lua modules alongside.

### Commit 7: `.obj` fast-path in the dispatcher

Once the dispatcher exists (in the method-call sprint), extend it with the name-check fast-path: any method call whose name is `obj` skips shadow, platters, primitive class, and engine class, and returns a fresh agent via `obj.new(engine, receiver_pk)`.

Sits at the top of the dispatcher's `dispatch(receiver, method_name, args)` function — one string comparison before any class-walk step.

### Commit 8: land the Lua modules

- `production/src/engine/classes/object.lua` — from [sprints/object/src/object.lua](./src/object.lua).
- `production/src/engine/classes/obj.lua` — from [sprints/object/src/obj.lua](./src/obj.lua).
- Registration hook: at bootstrap, register these modules under the engine_class names 'object' and 'obj' respectively.

Naming resolution: production's existing `production/src/engine/cvm/sqlite/object.lua` (the row wrapper) is a different concept from the sprint's object.lua (the Caspian class implementation). Prefix or relocate one to avoid the name collision. Suggested: keep the row wrapper where it is; land the Caspian class implementation under `production/src/engine/classes/`.

### Commit 9: end-to-end integration test

Port `test_foo_dot_obj.lua` into production tests. The sprint's version already runs end-to-end (Larry + the `MethodCall` stub + real transpile+normalize); the production port swaps in the real method-call primitive from the method-call sprint. The test's assertions stay the same — `$foo = 'bar'; $foo.obj.pk` sets the cap's rv to a fresh scalar_string carrying `$foo`'s UUID.

### Commit 10: teardown of Track 2 sprint content

Delete the whole `sprints/object/` dir once Track 2 lands, mirroring the expressions-sprint teardown pattern.

## Post-integration

- Full test suite green.
- Restart Orlando: `bash orlando/lua/stop.sh; bash orlando/lua/start.sh`.
- Refresh Orlando's issue cache: `curl -s -X POST http://127.0.0.1:8181/api/refresh-issues`.
- Lock production: `chmod -R a-w production/`.
- `git push` after each track lands — origin only sees fully-landed states.

## Rollback

Each Track-1 commit is discrete and revertable. The schema-and-engine coupling (Commits 1 and 2) is tight — if Commit 2 has a problem post-land, revert both together; a schema on the b/p/s shape with engine code still using the keyless pattern is not a valid state.

Track 2 commits (7-10) have staged dependencies — revert as a group.

## Outstanding issues

### Cross-sprint dependencies

- **[method-call sprint](https://puck.uno/sprints/method-call/)** — Track 2 hard-blocks on this. Currently seed-only.
- **[lazy-params sprint](https://puck.uno/sprints/lazy-params/)** — the agent's future `.tap` and short-circuit methods need lazy args. Not a Track 1 blocker.
- **[undeclared-read sprint](https://puck.uno/sprints/undeclared-read/)** — parallel; no blocking relation.
- **[remove-debug-column sprint](https://puck.uno/sprints/remove-debug-column/)** — cleanup; can land in either order.

### Follow-on work

- **Schema-doc sweep.** Any `requirements/` doc that names buckets or platters by their old base-filter needs updating. Grep for `bucket_ref` and `base = 'h'` usages that presume the keyless pattern.
- **`object_stack` → `object_platters` view rename** may need callers in production code that read from the old view. Grep-verify; update in Commit 2 or 3.
- **Migration test for existing DBs.** If any production DBs on-disk are `schema 12.1`, a migration path from keyless-refs to keyed-refs is needed. If all in-progress DBs are ephemeral (:memory: for tests only), no migration needed. Confirm which case applies.

## Estimated effort

- **Commit 1** (schema triggers): ~30 min. Copy the four triggers + drop the old one; comment sweep.
- **Commit 2** (engine sweep): ~2-3h. Every keyless-bucket-ref pattern in engine code becomes keyed. Bigger than a numbers-sprint commit; touches init.lua + object.lua + frame.lua + schema.sql triggers + views.
- **Commit 3** (test sweep): ~1h. Update test_schema.lua's ref-invariant block; port test_bps assertions into production.
- **Commit 4** (version + vibecode): ~15 min. Straight edits.
- **Commit 5** (doc promotion): ~1h. Move dispatch.md; update frame-lifecycle and frame-advancement docs; ensure links resolve.
- **Commit 6** (Track-1 teardown): ~15 min. Straight deletes.
- **Commit 7** (dispatcher fast-path): ~30 min. One code path.
- **Commit 8** (Lua modules): ~1h. Relocate + register hook.
- **Commit 9** (integration test): ~1h. Adapt test_foo_dot_obj to production.
- **Commit 10** (Track-2 teardown): ~15 min. Delete sprint dir.

Track 1 total: ~5-6h. Track 2 total: ~3h — but staged behind the method-call sprint, so real elapsed time depends on that.
