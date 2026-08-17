~~~vibecode
{"doc": "sprint-note", "sprint": "first-variable",
	"role": "Design captured 2026-08-16: two invariants that close the nested-child delete hole via `gc` itself, replacing the `dcok` mechanism. Works IFF the sprint also drops marker-child rows entirely — a Tuvix-style merge where the 'marker' concept collapses into 'frame with gc=1'. Package deal, not incremental.",
	"status": "design captured; not implemented"}
~~~

# Frames-only model

Two invariants that together close the nested-child delete hole through `gc` itself, no separate authorization column:

1. **A frame with `gc = 1` has no children.**
2. **A child cannot be deleted unless its parent has `gc = 1`.**

## Why this closes the hole

The legitimate delete path is a parent's gc transition:

- Walker: `UPDATE parent SET gc = 1`.
- AFTER-UPDATE trigger: DELETE children.
- Each child's BEFORE-DELETE: check parent.gc — it's 1 by now (the row updated before the AFTER trigger fired) — passes.
- Rule 1 satisfied post-cascade (children gone).
- Rule 2 satisfied because parent was gc=1 at the moment of each child's delete.

Direct user attempt to delete a child: parent.gc is null; BEFORE-DELETE aborts. No bypass path.

**No `dcok` column needed.** `gc` carries the authorization.

## The catch

Only works if there are no marker-child rows in the first place. Under the current schema, handlers push a marker child (gc=1) under a real frame R (R.gc=null) as the mid-dispatch signal, and the walker sweeps that marker between statements. Under Rule 2 the sweep breaks:

- Marker M exists as R's child. R.gc is null.
- Walker wants to delete M mid-execution. Rule 2 says parent.gc must be 1. R.gc is null. Abort.

Rule 2 forces marker-child rows to stay alive until R itself finishes — which defeats the point of sweeping them.

## Package deal

The rules only fit a fully-Tuvix'd model. To adopt:

- **Drop `frames_drop_and_replace`.** When a frame finishes, it stays as its own row and flips gc:null→1 in place. No new marker row inserted.
- **Drop the handler's `push_marker`.** No more marker-child rows.
- **Wire the in-place gc transition.** `UPDATE parent SET stmt_idx = past-max, gc = 1` — enforced by a check "advancing past ast max requires gc = 1 in the same UPDATE."
- **Drop the `dcok` column and its four triggers.** Replaced by Rule 1 + Rule 2.
- **Add Rule 1 enforcement.** AFTER UPDATE OF gc when new=1, delete children (Rule 1 satisfied at end of cascade).
- **Add Rule 2 enforcement.** BEFORE DELETE on any child frame, reject unless parent.gc = 1.
- **Handler-side: mid-dispatch atomicity moves to Lua.** Handler wraps writes + stmt_idx advance in one savepoint. No schema-level mid-dispatch signal.

## Tradeoffs

**Wins**

- One column (`gc`) does what two (`gc` + `dcok`) do today.
- Only one kind of row (frame) — the marker concept collapses into "frame with gc=1."
- No separate row for markers; no `frames_drop_and_replace` insert; no `push_marker` insert.
- Rule 1 + Rule 2 are shorter, more legible than the 5 triggers dcok needs.

**Loses**

- Mid-dispatch atomicity moves from schema to Lua savepoint. The current schema-enforced invariant "the frame with children = mid-execution" is what push_marker leverages; without it, handlers rely on savepoint rollback for crash-safety.
- Nested frames accumulate as children under their caller until the caller itself finishes. Under a deep call chain, all intermediate frames stay resident. Not a leak (they die when the caller does), but memory over a run scales with call depth, not just current stack height.

## Open

- Is the "no schema-enforced mid-dispatch" tradeoff acceptable? The current push_marker gives us a DB-level signal that survives across a crash-and-reopen; a Lua savepoint gives the same atomicity within a run but is invisible at rest.
- How does the "nested frames accumulate" property interact with GC? If a caller runs 1000 nested statements before finishing, all 1000 nested frames sit as its children. GC never visits them (they're reachable via parent_frame chains). They only die at the caller's gc transition.
