~~~vibecode
{"doc": "sprint-index", "sprint": "frames-gc-starts-null",
	"role": "Decision record: REJECTED. ChatGPT flagged that a frame can be INSERTed with `gc = 1`, bypassing the UPDATE-side lifecycle machinery. That INSERT path is intentional — dispatch handlers like variable-scalar can create a frame already in the terminal cleanup state and skip the advance-couples-with-gc step for simple assignments. Sprint kept for the record. Source: ChatGPT second-pass § 1.",
	"status": "rejected — INSERT with gc=1 is a deliberate optimization path"}
~~~

# frames-gc-starts-null

Second-pass § 1. ChatGPT observed that a new frame row can be INSERTed with `gc = 1` — sidestepping the UPDATE-side triggers (`frames_advance_requires_gc`, `frames_gc_set_requires_advance`) that couple gc-set with stmt_idx-advance. Proposed a BEFORE INSERT guard that requires fresh frames to be born with `gc is null`.

## Decision: rejected

Handlers like variable-scalar can INSERT a frame already in the terminal cleanup state — the frame is born, does its one thing, and is ready for the cascade cleanup all in one row. Forcing every new frame through the two-step `INSERT(gc=null) → UPDATE(gc=1)` cycle would cost an extra write on the hottest paths (simple assignment being the canonical example) to satisfy a state-machine invariant the caller has already satisfied by construction.

The rejected constraint would say: "every frame must pass through gc=null before reaching gc=1." What the design says: "the walker cycle passes through gc=null, but the INSERT path is an equally-legal way to reach any consistent frame state."

Sprint kept as a decision record so a future reader doesn't re-open the question thinking we missed it.
