# Integration plan

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_integration",
	"role": "Concrete step-by-step plan for promoting frames-as-objects from ideas/ into requirements/ + shipping src/. Enumerates every ordered piece of work, calls out the name-conflict decision that must be made before Phase 2, names deferred slices, and gives the verification checklist. Read all of it before starting; execute the phases in order."
}}
~~~

Promotion of [ideas/frames-as-objects/](.) into `requirements/` and shipping `src/engine/`. The general order was set in [index.md § Promotion coordination](index.md#promotion-coordination) — docs before code, code before tests. This page expands that into concrete file-level steps.

## Scope

**In scope:**

- **Schema shift.** The `frames` table is removed; each frame becomes an `objects` row with `primitive = 'f'`. `ast` is biconditional with that primitive.
- **Shipping code.** Replace `src/engine/cvm.sql`; add the CVM data-access layer (`engine.lua`) and the `object` / `frame` wrapper classes.
- **Test suite.** Promote `ideas/frames-as-objects/tests/*` into `tests/main/lua/engine/`; update existing tests that reference the old schema.
- **Requirements docs.** Rewrite `requirements/cvm/`, the four Stage sub-step pages under `requirements/bootstrap/stage/`, and any other page that references the removed tables.

**Out of scope (deferred slices — do NOT attempt during this promotion):**

- **Closure capture mechanism.** `lexical_parent` was removed from this design pass; the column that eventually carries the capture link returns with a dedicated closure design slice, which also has to reconcile with `requirements/lua/scope.md`'s scope-agg proposal.
- **Frame-caller pointer.** `frame_parent` was implemented and pulled back as premature optimization; returns with the closure design.
- **Runtime dispatch loop.** `frame:run`, the engine main loop, and shutdown are named in `engine.lua`'s "Open questions" block but not built. The engine at promotion time is a data-access layer only.
- **Full bootstrap flow beyond schema install + process record.** Existing `src/engine/cvm.lua` opens the DB, applies the schema (gated on the mvm marker), and inserts the process record. That's it.

## Naming resolution

Shipping `src/engine/engine.lua` already exists — it's Caspian's runtime engine (267 lines, entry point for the whole language). The ideas-tree `engine.lua` (423 lines) is a completely different thing — the CVM data-access facade. Both export `engine.new`. Landing the ideas-tree file at `src/engine/engine.lua` would silently overwrite Caspian's runtime engine.

**Decision:** collect all CVM code into `src/engine/cvm/`, one subdirectory. Everything CVM-related — schema, open path, data-access, wrapper classes — moves there together. Caspian's runtime keeps `src/engine/engine.lua`.

Layout after Phase 2:

~~~
src/engine/
├── engine.lua           # Caspian runtime — unchanged
├── normalize.lua        # unchanged
├── roles.lua            # unchanged
├── sequence.lua         # unchanged
├── state.lua            # unchanged
├── transpiler.lua       # unchanged
├── trivet.lua           # unchanged
└── cvm/
    ├── schema.sql       # was src/engine/cvm.sql
    ├── open.lua         # was src/engine/cvm.lua
    ├── engine.lua       # from ideas/frames-as-objects/src/engine.lua — the CVM's data-access engine
    ├── object.lua       # from ideas/frames-as-objects/src/object.lua
    └── frame.lua        # from ideas/frames-as-objects/src/frame.lua
~~~

Require namespace: `cvm.open`, `cvm.engine`, `cvm.object`, `cvm.frame`. Inside the subdirectory, sibling requires read as `require("cvm.object")` etc. — always fully-qualified, always self-describing.

Both `engine.lua` files coexist because they're at different paths in the require namespace: `require("engine")` for Caspian's runtime, `require("cvm.engine")` for the CVM's data-access.

**Required migration touches** (small):

- `src/engine/engine.lua:42` — `local cvm = require('cvm')` → `require('cvm.open')`.
- `tests/main/lua/engine/test_cvm.lua:9` — same rename.

Why this layout:

- **Clean separation.** All CVM code in one subdirectory. If more CVM-related wrappers land later (per-primitive classes, GC drivers, whatever), they slot in naturally.
- **Matches the ideas-tree layout.** The five files under `ideas/frames-as-objects/src/` map directly to five files under `src/engine/cvm/`.
- **No name collisions.** `src/engine/engine.lua` and `src/engine/cvm/engine.lua` live at distinct require paths. Reading either one, "engine" means the right thing in context.
- **Minimal call-site churn.** Only two `require('cvm')` sites need updating (the runtime engine and its test file).

## Ordered steps

### Phase 1 — Requirements docs

Follow "docs before code" from index.md's Promotion coordination.

**1. Rewrite `requirements/cvm/`.**
   - `requirements/cvm/index.md` — replace the frames-table description with the primitive='f' folding.
   - `requirements/cvm/sql.md` — swap in the new SQL (or update the file: directive that pulls from `src/engine/cvm.sql`).
   - `requirements/cvm/schema.svg` — regenerate or edit; 5 old-design references currently.
   - `requirements/cvm/ast-storage.md` — verify still accurate; ast now lives on the frame row itself.
   - `requirements/cvm/garbage-collection/index.md` — 4 old-design references; update to the new uspace frame-anchor branch.
   - `requirements/cvm/pause-resume/index.md` — verify still accurate; pause is still "close the connection," resume is still "reopen from persistent state," but the frame model shifted.

**2. Rewrite the four Stage sub-step pages** (three already marked "Overwrite pending"; verify).
   - `requirements/bootstrap/stage/index.md` — sub-step count drops from three to two.
   - `requirements/bootstrap/stage/transpile/index.md` — probably survives unchanged.
   - `requirements/bootstrap/stage/install-caspm/index.md` — this step DISAPPEARS as a standalone sub-step; its work (writing CaspM into the CVM) is absorbed into set-up-frame-0 (one INSERT lands both frame 0 and its ast).
   - `requirements/bootstrap/stage/set-up-frame-0/index.md` — rewrite from scratch: frame 0 lands as an `objects` row with `primitive = 'f'`, `ast` holds the CaspM directly, `stmt_idx = 0`, `idx = 0`, `process = <bootstrap process pk>`, `owner_role = user`.

**3. Update `requirements/execution/`** if it references frames as a table.

**4. Flag reconciliation with `requirements/lua/scope.md`.** Its "scope agg" closure-capture model conflicts with what frames-as-objects will eventually need (an object-graph reference from closure to captured frame). Add a note to both docs cross-referencing the other as an open cross-model item to resolve when the closure slice lands.

**5. Sweep other requirements/ pages** for lingering references to `frames`, `frame_locals`, `frame_delegations`, `frame_ambers`, `lexical_parent`. `current_process` was already swept in a prior pass.

### Phase 2 — Shipping code

Land the layout resolved above.

**6. Create `src/engine/cvm/`** as an empty directory.

**7. Move `src/engine/cvm.sql`** → `src/engine/cvm/schema.sql`. Overwrite the file's contents with the schema from `ideas/frames-as-objects/src/cvm.sql`.

**8. Move `src/engine/cvm.lua`** → `src/engine/cvm/open.lua`. Verify the new schema applies cleanly on install-gated open; `open()` already returns `(db, process_pk)` — that survives.

**9. Add** `src/engine/cvm/engine.lua` (from `ideas/frames-as-objects/src/engine.lua`) — the CVM's data-access engine.

**10. Add** `src/engine/cvm/object.lua` (from `ideas/frames-as-objects/src/object.lua`) and `src/engine/cvm/frame.lua` (from `ideas/frames-as-objects/src/frame.lua`) — wrapper classes.

**11. Update require paths** in the two call sites:
   - `src/engine/engine.lua:42` — `require('cvm')` → `require('cvm.open')`.
   - `tests/main/lua/engine/test_cvm.lua:9` — same rename.

**12. Update the internal require in `src/engine/cvm/engine.lua`** — currently `require("object")`; becomes `require("cvm.object")`. Same for `src/engine/cvm/frame.lua`'s `require("object")`.

**13. Verify Caspian's runtime engine** (`src/engine/engine.lua`) still works against the new CVM data-access layer. Its `engine.cvm` field currently holds the SQLite handle; the runtime can either keep that shape (open returns `(db, process_pk)`, engine.cvm = db) or start holding the CVM engine facade instead. Probably yes to the facade eventually, but not required for this promotion — leave as-is unless a downstream dispatch call needs the facade.

### Phase 3 — Tests

**14. Promote the ideas-tree tests** into `tests/main/lua/engine/`:
   - `ideas/frames-as-objects/tests/test_engine.lua` → `tests/main/lua/engine/test_cvm_engine.lua` (or split by class: `test_object.lua`, `test_frame.lua`, `test_engine.lua`).
   - `ideas/frames-as-objects/tests/view-indexes.lua` → `tests/main/lua/engine/test_view_indexes.lua`.

**15. Update the promoted tests' require paths** — `require("engine")` → `require("cvm.engine")`; `require("frame")` → `require("cvm.frame")`; and their `SCHEMA_PATH` constant to point at `src/engine/cvm/schema.sql`.

**16. Update `tests/main/lua/engine/test_cvm.lua`** — remove tests referencing removed tables; keep tests that still apply. The current test_cvm.lua tests `cvm.open()` shape (pragmas, install gate, process record) — those should survive under the new `cvm.open` require path.

**17. Update the test runner** at `tests/main/lua/engine/run.lua` if it needs to pick up new test files.

**18. Run all tests** — `lua5.4 tests/main/lua/engine/run.lua` plus the trivet suite. Zero failures required.

### Phase 4 — Cleanup of the ideas tree

**19. Delete `ideas/frames-as-objects/src/`** — the code lives in `src/engine/cvm/` (per Phase 2) now.

**20. Delete `ideas/frames-as-objects/tests/`** — the tests live in `tests/main/lua/engine/` (per Phase 3) now.

**21. Migrate `ideas/frames-as-objects/benchmarks/`** to a permanent home. Options: `benchmarks/` at the repo root, or keep in the ideas tree as historical measurement records. Bench header comments carry the "before/after optimization pass" story that's useful reference material.

**22. Keep `ideas/frames-as-objects/examples/`.** The walkthroughs (`end-of-bootstrap`, `first-variable`, and the placeholder `closure`) are useful reference material for the design's motivation. Either leave them in place or move to `documentation/`.

**23. Rewrite or delete `ideas/frames-as-objects/index.md`.** Either turn it into a stub pointing at where the work landed (`requirements/cvm/`, `src/engine/cvm/`), or delete the whole `ideas/frames-as-objects/` tree and let git history be the record.

## Verification

Before declaring the promotion done:

- **All existing Lua tests pass** — `tests/main/lua/engine/run.lua` and any others.
- **No lingering references** — `grep -rn 'frame_locals\|frame_delegations\|frame_ambers\|lexical_parent' requirements/ src/ tests/` returns nothing. `grep -rn '\bframes\b' requirements/` returns only intentional prose mentions (e.g., "the call stack has frames," not references to a `frames` table).
- **No `frames-as-objects` cross-refs from `requirements/`** — the promotion should mean requirements is self-contained. `grep -rn 'frames-as-objects' requirements/` returns nothing (or only intentional history notes).
- **Orlando renders every promoted page** without 404s. Restart Orlando after doc changes; walk the affected pages.
- **CVM schema installs cleanly** — running `cvm.open()` on a fresh in-memory DB completes without error.
- **`add_frame`, `object_by_pk`, `frame_by_pk` all work** — spot-check with a hand-run.

## After landing

- Close any open GitHub issues that this promotion resolves.
- Update `requirements/audit.md` if it tracks the frames-as-objects promotion.
- File follow-on slices in issue tracker:
  - **Closure design.** `lexical_parent` (or equivalent) + reconciliation with `requirements/lua/scope.md`.
  - **Frame-caller pointer.** `frame_parent` returns with the closure design.
  - **Runtime dispatch loop.** `frame:run`, engine main loop, shutdown.
  - **Pop semantics.** How a frame's stack coordinates go null; what happens if nothing captured it.
