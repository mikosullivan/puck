~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "expressions",
	"role": "Step-by-step plan for landing the expressions sprint into production. Sequenced so intermediate states never break the production test suite. Broader in scope than the numbers-sprint integration — this sprint touches the transpiler, the schema, adds primitives that don't exist in production yet, and depends on design decisions in three related sprints. Some pieces of the sprint (BareLiteralHandler, IfHandler-shortcut) are prototypes that land as reference, not as production code.",
	"status": "track 1 landed 2026-08-24 (commits 1-4: transpiler fallback, schema trigger, docs promotion, teardown). Track 2 remains planned; stages behind method-call and lazy-params sprints."}
~~~

# expressions-sprint integration plan

## What's being landed

Production baseline is schema 12.0 with the current transpiler + normalizer. The sprint delivers, in decreasing readiness:

- **Transpiler fixes** (localized, testable, ready to land).
- **Sprint-schema trigger** (`frames_child_delete_propagates_rv`, tested via 5 scenarios, ready to land as a schema bump).
- **Design docs** (evaluation-model, eval-algorithm, primitives specs, frame-advancement summary — settled enough to promote as requirements).
- **Normalizer extensions** (postnormalize pass — designed and demoed but not integrated with the production normalizer).
- **Engine primitives** (assign / if / while / or / and / method-call — spec'd as Lua pseudocode in the primitives docs, not yet implemented in production).
- **Engine rv-slot mechanism** (design settled; no production implementation).
- **Handler upgrades** (real handlers replacing the sprint's walking-skeleton prototypes).

Not everything in the sprint lands in a single integration pass. The transpiler + schema pieces are ready; the primitives + rv-slot work is bigger and stages behind their supporting sprints ([method-call](https://puck.uno/sprints/method-call/), [lazy-params](https://puck.uno/sprints/lazy-params/)) landing.

## Preconditions

- Sprint's own demos all green: `lua5.4 sprints/expressions/src/{demo,propagate-rv-demo,foo-to-cap,build-frames}.lua` all pass.
- Production tests green at HEAD before starting.
- Production locked. Unlock with `chmod -R u+w production/`.
- Working tree clean of anything unrelated.

## Ordering rationale

Two independent tracks that don't need to happen together:

- **Track 1 — parser + trigger.** Small, self-contained: transpiler fixes, schema trigger, related design docs. Lands cleanly without any primitives work.
- **Track 2 — evaluation-model machinery.** Bigger: rv slot in frames, real primitive implementations, real handlers. Depends on the method-call and lazy-params sprints having their design settled first.

Track 1 can go first. Track 2 stages behind it (and behind the related sprints).

## Track 1: transpiler + trigger + docs

**Landed 2026-08-24** — commits 1-4 below all applied. Section retained for reference; commit hashes are on `master`.

### Commit 1: transpiler fixes

Four surgical changes to `production/src/engine/transpiler.lua`, mirroring the four made in [sprints/expressions/src/transpiler.lua](sprints/expressions/src/transpiler.lua):

- **Remove the `bwc_bare = stmt:match("^([%w_]+)$")` pattern** (around line 2531 in current production). Kills the numeric-literal-as-bareword misclassification.
- **Narrow `bwc_paren_name`** — `^([%w_]+)%s*(%b())$` → `^([%a_][%w_]*)%s*(%b())$`. Prevents `1(2)` from matching as bareword-call.
- **Narrow `bwc_stmt_name`** — `^([%w_]+)%s+(.+)$` → `^([%a_][%w_]*)%s+(.+)$`. Prevents `1 + 2` from matching as bareword-with-args and choking on "+ 2" as args.
- **Add expression fallback** at the end of `transpile_statement`, right before the "cannot parse" error. `pcall(parse_expression, stmt)`; wrap the resulting atom (or row) if it succeeded.

**Verification for this commit:**

- Run production test suite: `lua5.4 production/tests/main/lua/engine/run.lua`. All existing tests pass.
- Add new test cases for the fixed shapes: `'foo'` → `[[{value: "foo"}]]`, `1` → `[[{value: 1}]]`, `true` → `[[{value: true}]]`, `1 + 2` → `[[{op:"+", ...}]]`, `[1,2,3]` → array atom, `{a:1}` → hash atom, `$foo ? 1 : 0` → ternary op atom.
- Confirm existing bwc shapes unchanged: `puts` still `[[{bwc:"puts"}]]`, `puts 1` still `[[{bwc:"puts"},{value:1}]]`.

**Closes GitHub issues [#1736](https://github.com/mikosullivan/puck/issues/1736) and [#1737](https://github.com/mikosullivan/puck/issues/1737)** — both are covered by this single fix.

### Commit 2: sprint schema → production (rv-propagation trigger)

The `frames_child_delete_propagates_rv` trigger from [sprints/expressions/src/schema.sql](sprints/expressions/src/schema.sql) lands in `production/src/engine/cvm/sqlite/schema.sql`. Placement: right after `frames_child_delete_sets_parent_gc`, matching the sprint's placement.

**Schema version bump.** Sprint has `12.0-expressions-sprint`; production would go to `12.1` (or whatever's next in the versioning scheme). Update the version marker at both the vibecode `version` field and the `cvm` marker table INSERT.

**Vibecode grep list update.** Add `frames_child_delete_propagates_rv` to the `gc_cycle_state_machine` field's names-to-grep list (in the top-of-file vibecode block).

**Verification for this commit:**

- Run production tests. All still pass (the new trigger only fires on child-frame delete with a parent; existing tests don't exercise that path).
- Add new tests exercising the trigger via the demo scenarios: child-has-rv, child-no-rv, child-no-bucket, UPDATE-in-place (ref_pk preserved), multi-hop chain to cap.

### Commit 3: promote design docs to requirements

Selected sprint docs move to `production/requirements/expressions/` or similar. Which specifically:

- `evaluation-model.md` — the sprint's overall design.
- `eval-algorithm.md` — dispatch mechanism spec.
- `frame-advancement.md` — the three-state-variable / nine-rule reference (useful independent of the rest).
- `primitives/method-call.md`, `assign.md`, `if.md`, `while.md`, `or.md`, `and.md` — primitive specs.

**Not promoted yet:**

- `index.md` — sprint-scoped framing; the equivalent would be a docs-level overview page that combines it with related sprints' context.
- `report.md`, `caspm-status.md` — sprint-internal analysis, not stable spec.
- `src/` — code, tracked below.

**Cross-links** — update any `[[tag:name]]` refs to survive the promotion; add `[caspianj](https://puck.uno/requirements/caspianj)` back-links from the new pages.

**Verification:** Orlando renders each new page cleanly at `http://127.0.0.1:8181/production/requirements/expressions/…`.

### Commit 4: teardown of the sprint's now-promoted content

Track-1 side of the sprint's teardown. Delete only the files that landed in commits 1-3:

- Delete `sprints/expressions/src/transpiler.lua` (landed in production/src/engine/transpiler.lua).
- Delete `sprints/expressions/src/schema.sql` (landed in production/src/engine/cvm/sqlite/schema.sql).
- Delete `sprints/expressions/src/propagate-rv-trigger.lua` and `propagate-rv-demo.lua` (trigger now in production schema; demo obsolete under production).
- Delete the promoted docs (moved to `production/requirements/expressions/`).

Keep in sprints/expressions/ (until track 2 lands):

- `src/postnormalize.lua`, `src/build-frames.lua`, `src/foo-to-cap.lua`, `src/demo.lua` — track-2 depends on these.
- `report.md`, `caspm-status.md`, `index.md` — sprint-internal, updates track-2.

## Track 2: evaluation-model machinery

**Prereq:** track 1 has landed; [method-call sprint](https://puck.uno/sprints/method-call/) and [lazy-params sprint](https://puck.uno/sprints/lazy-params/) have their design pinned. Both are currently seed-only.

### Commit 5: rv slot mechanism in frames

Extend `production/src/engine/cvm/sqlite/frame.lua` (Frame class) with:

- **`frame:set_rv(value_pk)`** — inserts (or updates via UPSERT) a ref from the frame's bucket → value_pk, key='rv'. Materializes the bucket on demand if missing (same pattern as `ensure_own_scope`).
- **`frame:get_rv()`** — reads the rv ref's child pk (or nil if unset).

**Verification:** unit tests exercising the two methods against a fresh frame; verify rv survives across method calls; verify UPSERT preserves ref_pk.

### Commit 6: primitive implementations

For each spec'd primitive under `sprints/expressions/primitives/`, land a Lua implementation under `production/src/engine/primitives/`:

- `assign.lua` — variable binding per assign.md's pseudocode (walk scope chain innermost-first, rebind or create-at-outermost).
- `method_call.lua` — the dispatcher per method-call.md (name vs callable branch, signature-driven eager/lazy).
- `if_.lua` — engine.if per if.md's variadic pairs shape.
- `while_.lua` — engine.while per while.md.
- `or_.lua`, `and_.lua` — .obj.or / .obj.and per or.md / and.md.

**Bareword-command primitives** — one per bwc form the transpiler emits, called via `engine.<name>` per commit 8's normalizer rewrite:

- `engine.puts(x)` — write to stdout.
- `engine.return(x)` — early-return from the enclosing function (may need engine-context access to unwind).
- `engine.raise(e)` — raise an error.
- `engine.field(name, ...)` / `engine.private(...)` / other class-body DSL commands.
- Any other bareword-command names the transpiler currently recognizes.

Migration path from the existing production bwc handlers: each handler's body becomes the corresponding `engine.<name>` primitive body; the bwc-atom dispatch path is retired (the normalizer's rewrite means the engine only ever sees fc atoms at dispatch).

**Scalar materialization** — under the sprint's walking-skeleton demo (see [foo-to-cap.lua](sprints/expressions/src/foo-to-cap.lua)'s BareLiteralHandler), scalar objects are materialized directly via `engine.data:add_scalar(value, owner_role_pk)` — no class lookup, no `.new` dispatch through method_call. **Land the same shortcut for integration**: a small `materialize_scalar` engine helper (or reuse the existing `add_scalar`) that the handlers call directly.

The design docs describe the aspirational form (`Number.new(1)` dispatched via method_call), but implementing that requires the Number / String / Boolean classes to exist as first-class objects with their own class stacks and a `.new` method — which they don't yet. **Class-based dispatch for constructors is deferred** to a follow-on sprint that sets up classes properly.

**Comparison primitives** (`.==`, `.<`, `.<=`, etc.) — same story. The aspirational form is method dispatch on Number's class; for this sprint, land as engine-side Lua that reads both operands' scalar columns and produces a Boolean scalar. No class lookup.

**Verification:** unit tests per primitive; integration tests through the full pipeline.

### Commit 7: real handlers replacing prototypes

Replace [sprints/expressions/src/build-frames.lua](sprints/expressions/src/build-frames.lua)'s IfHandler-shortcut and BareLiteralHandler with production-quality handlers:

- **New BareValueHandler** in `production/src/engine/handlers/` — matches `[{v: X}]`-shape rows; dispatches via method_call to the appropriate `.new` constructor per the value's type; sets frame's rv from the returned pk.
- **New IfHandler** — matches the `[{in:"fc"}, {rc:{var:"engine"}, fn:"if", ...}]` fc shape (post-normalizer); dispatches via method_call to engine.if primitive. Not the prototype's `{if: {...}}` shape — that's the pre-normalizer atom which the normalizer promotes to fc form.
- **New WhileHandler**, **short-circuit handlers**, etc. — same pattern per primitive.

**Verification:** end-to-end programs that exercise each handler.

### Commit 8: normalizer extensions

Land the [postnormalize](sprints/expressions/src/postnormalize.lua) rewrites inline into `production/src/engine/normalize.lua` — extend `normalize_atom`'s dispatch table rather than running as a separate pass. Five rewrite categories:

- `{op: "||"}` → `.obj.or` fc call.
- `{op: "&&"}` → `.obj.and` fc call.
- `{if: {conditions, else}}` → `engine.if` fc call.
- `[scope, while_end, ...]` → `engine.while` fc call.
- **`{bwc: name}` atoms → `engine.<name>` fc calls** (`puts` → `engine.puts`, `return X` → `engine.return(X)`, `raise E` → `engine.raise(E)`, `field name` → `engine.field(name)`, etc.). Same rewrite shape as the standalone-command constructs; bareword commands unify under `engine.<name>` per the "every command is a method call" model.

The sprint's postnormalize.lua is the reference implementation for the first four categories; the bwc rewrite is new and follows the same pattern (wrap args as needed, emit `[{in:"fc"}, {rc:{var:"engine"}, fn:name, a:[...]}]`).

**Verification:** every construct produces the expected fc shape after normalization. Existing tests that inspect CaspM shapes need updating.

### Commit 9: sprint teardown (track 2)

Delete the remaining sprints/expressions/ content once track 2 has landed:

- `src/postnormalize.lua`, `src/build-frames.lua`, `src/foo-to-cap.lua`, `src/demo.lua`.
- `index.md`, `report.md`, `caspm-status.md`, `evaluation-model.md`, `eval-algorithm.md`, `frame-advancement.md`.
- `primitives/*.md`.
- The whole `sprints/expressions/` dir.

## Post-integration

- Full test suite one more time.
- Restart Orlando: `bash orlando/lua/stop.sh; bash orlando/lua/start.sh`.
- Refresh Orlando's issue cache: `curl -s -X POST http://127.0.0.1:8181/api/refresh-issues`.
- Lock production: `chmod -R a-w production/`.
- `git push` after both tracks land — origin only sees fully-landed states.

## Rollback

Each commit is a discrete, revertable change. Track 1 commits (1-4) are self-contained; each can revert independently. Track 2 commits (5-9) have dependencies:

- Reverting commit 5 (rv slot) requires reverting 6+ (primitives depend on set_rv).
- Reverting commit 6 (primitives) requires reverting 7+ (handlers dispatch to primitives).
- Reverting commit 8 (normalizer extensions) requires the handlers to fall back to the pre-normalized shapes — probably means reverting 7 too.

Safest rollback: revert as a group.

## Open issues to resolve before / during integration

Some are decisions; some are gaps in current design; some are known parser limitations.

**Decisions needed:**

None outstanding.

**Design gaps (not blocking track 1; block later track-2 commits):**

- **Real if-handler needs comparison-operator support.** Any test like `$x == $y` needs `.==` dispatched as an fc. The BareLiteralHandler + IfHandler prototypes don't currently do this — the demo simplified to var-truthiness tests. Real production handler needs the full dispatch.
- **rv reads from Caspian source.** No syntax yet for reading rv (the `$_` idea from the sprint's original framing was left open). Decide before implementing user-facing rv access.
- **Host-side cap.rv access.** After `engine:run()` returns, the host has the `cap_pk` but no method to query cap's rv. Add `engine:cap_rv()` or similar.
- **Every-frame-is-a-call discipline.** The sprint spec'd it; the current handlers still work at command-granularity, not per-sub-expression. Real implementation needs the sub-expression frames plus leaf-inline optimization to keep performance reasonable.

**Parser gaps (transpiler-side, out of scope for track 1's fixes):**

- **Same-line multiple bare-expressions** — `'foo' 'bar'` on one line doesn't parse. Chunker doesn't recognize quote-prefixed tokens as implicit boundaries. Newline-separated works fine.
- **`until` keyword** — `until X do Y end` doesn't parse (`do`-block issue). Parallel to `while`; needs its own transpiler pattern.
- **Bare `puts` alone** — parses correctly to `{bwc: "puts"}`, but there's no handler yet to dispatch bareword commands as rv-setters. Track 2's real handlers need to cover this.

**Cross-sprint dependencies:**

- **[method-call sprint](https://puck.uno/sprints/method-call/)** currently seed-only. Track 2 commits 6+ require its design to be pinned first.
- **[lazy-params sprint](https://puck.uno/sprints/lazy-params/)** currently seed-only. The signature-marker `&` needs implementation for lazy args to work; block commit 6 on this.
- **[bootstrap-atomicity sprint](https://puck.uno/sprints/bootstrap-atomicity/)** independent. Can land in either order relative to this sprint.

**Follow-on work (deferred, not in this sprint):**

- **Class system for Number / String / Boolean and their methods.** The design docs' aspirational form is `Number.new(1)` and `.+` / `.<` dispatched via method_call on the value's class. The sprint's actual integration bypasses that with direct scalar materialization + engine-side comparison Lua. Full class-based dispatch requires classes as first-class objects with class stacks and a `.new` method — a whole sprint of its own after this integration lands.

## Estimated effort

- **Commit 1** (transpiler fixes): ~30 min. Four small edits; regression tests to run.
- **Commit 2** (schema trigger): ~30 min. Copy the trigger; version bump; test scenarios port.
- **Commit 3** (docs promotion): ~1h. Move + link-sweep + Orlando checks.
- **Commit 4** (track-1 teardown): ~15 min. Straight deletes.
- **Commit 5** (rv slot in Frame): ~1h. Two methods; unit tests.
- **Commit 6** (primitive implementations): ~4-6h. Six primitives + constructors + comparisons. Big commit.
- **Commit 7** (real handlers): ~2-3h. Replace prototypes with production-quality dispatch.
- **Commit 8** (normalizer extensions): ~1-2h. Four rewrites + testing.
- **Commit 9** (track-2 teardown): ~15 min. Straight deletes.

Track 1 total: ~2-2.5h. Track 2 total: ~8-12h — but staged behind supporting sprints, so real elapsed time depends on those.
