~~~vibecode
{"doc": "sprint-note", "sprint": "first-variable",
	"role": "Every column in the objects table, with a comment that captures its role on a frame — especially how it relates to stmt_idx and gc under the sprint schema's gc-cycle design. Single-table reference."}
~~~

# Frame fields

Every column in `objects`, with a comment focused on what it does on a frame and how (if at all) it participates in the stmt_idx / gc cycle.

| Field | Comment |
|---|---|
| `object_pk` | UUID. Immutable. |
| `primitive` | `'f'` on any frame. Immutable. |
| `scalar_type` | Null on frames. |
| `scalar_value` | Null on frames. |
| `core_role` | Null on frames. |
| `role_parent` | Null on frames. |
| `owner_role` | Required at INSERT; references a role. Immutable. |
| `ast` | JSON array of the frame's statements. Biconditional with `primitive = 'f'`: frames must have `ast` set, non-frame rows must have it null. Cap frames (`process = 1`) must have `ast = '[]'` — the cap dispatches nothing. Immutable once set. Not touched by the gc cycle — persists as-is while stmt_idx advances through it. |
| `stmt_idx` | Position in the ast. Starts at 0 (enforced at INSERT). Advances by exactly +1 per statement dispatched (never skips, never rewinds). **Must advance in the same UPDATE that sets `gc = 1`** — advancing alone is rejected. On a cap, stmt_idx is a lifecycle phase (0=live, 1=terminal) rather than an ast position. |
| `process` | `1` on a cap frame (the top of a call stack — its `object_pk` IS the process identity); null on every other frame. Immutable. XOR with `parent_frame`. A cap has `ast = '[]'`, no parent, and no bucket/stack is required by rule (design leaves it free). |
| `parent_frame` | Set on nested frames; null on caps. Immutable. XOR with `process = 1`. |
| `bucket_pk` | Null until the frame gets a bucket, then holds that bucket's `object_pk`. **Mutable** — the owner can swap buckets at any time. Target must be `primitive = 'h'` (checked by trigger). On change: the OLD target is marked `needs_trace = 1`. On owner delete: a BEFORE-DELETE trigger marks the current target `needs_trace = 1` (bucket survives; GC decides). No `UNIQUE` — a bucket can be shared across multiple owners. |
| `stack_pk` | Same shape as `bucket_pk`, target must be `primitive = 'a'`. |
| `persistent` | Optional. Freely mutable. Frames aren't typically persistent. |
| `gc` | Bidirectional cycle state: null (frame is executing normally) ↔ 1 (post-dispatch cleanup phase). Set to 1 as part of the walker's advance UPDATE — cannot be set alone. Setting to 1 fires an AFTER-UPDATE cascade that unconditionally deletes child frames (any active child is swept, not rejected). Resetting to null is only allowed once no children remain (the engine loops sweeps until this holds). **Delete rule:** a frame can only be deleted when `gc is null` — mid-cleanup deletes are rejected. Any stmt_idx is fine at delete time; early return via `return X` legitimately leaves a frame at mid-ast position with gc=null. |
| `needs_trace` | GC scratch column. Freely mutable. |
| `in_trace` | GC scratch column. Freely mutable. |
| `debug` | Informational label. Freely mutable. |
