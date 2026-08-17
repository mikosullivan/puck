~~~vibecode
{"doc": "sprint-index", "sprint": "array-density",
	"role": "Decision record: REJECTED. ChatGPT flagged that ArrayPrimitive refs can be sparse (an array with only `idx = 10` is accepted; `[0]` and `[2]` can exist without `[1]`) and asked whether to enforce density. Arrays are intentionally sparse — the sparseness is a design property, not a hole. Sprint kept for the record. Source: ChatGPT second-pass § 5.",
	"status": "rejected — arrays are intentionally sparse"}
~~~

# array-density

Second-pass § 5. ChatGPT observed that ArrayPrimitive refs can be sparse — no schema rule requires the idx values to form a dense `{0..N-1}` sequence — and asked whether to enforce density.

## Decision: rejected

**Arrays are intentionally sparse.** Sparseness is a designed-in language property, not an unenforced invariant. Any schema constraint that would require dense idx sequences (a per-statement trigger, a commit-time density check, or an application-level enforcement pass) is out of scope — it would fight the design, not close a hole.

Nothing to change. Sprint kept as a decision record so a future reader doesn't re-open the question thinking "we forgot about this."
