~~~vibecode
{"doc": "sprint-index", "sprint": "first-variable",
	"role": "Implementation sprint: add the one dispatch function that recognizes the CaspM assignment pattern (`{in: 'as'}` row head) and implements it, so `$x = 1` runs end-to-end. The concept was captured in the (now-deleted) understanding-frame-rows sprint doc; this sprint executes it.",
	"status": "kicked off",
	"trigger_word": "integration"}
~~~

# first-variable

Close the end-to-end walkthrough for `$x = 1`. Today the runtime bootstraps, loads, pushes frame 0, enters dispatch — and dies on `unrecognized_row_head` because no handler is registered for `{in: 'as'}` (the CaspM assignment head). This sprint adds that one handler.

**Depends on [dispatch](../dispatch/)** — the row-head dispatch table + registration mechanism has to exist before this sprint can register anything into it. This sprint executes after that one.

## The pattern being matched

The concrete CaspM for `$x = 1` (verified live earlier this session):

~~~lua
{{in = "as"}, "x", {v = 1}}
~~~

- Head atom: `{in = "as"}` — the assignment statement prefix.
- Second element: `"x"` — bare string, the target variable name (post-normalize the var-atom collapses to a string).
- Third element: `{v = 1}` — value atom, using the short key `v`.

## The one function

**`dispatch_as(row)`** — a single function that recognizes this row shape and implements it. Registered as the handler for `{in: 'as'}` row heads in whatever dispatch table `M:run_row` reads. Body:

1. Extract the target name (row's second element).
2. Evaluate the value atom (row's third element) — for a `{v = N}` shape, produce a scalar object via `self.cvm:add_scalar('n', N, owner_role)`.
3. Ensure frame 0's locals bucket exists (`frame:ensure_locals`).
4. Bind the name to the scalar (`frame:set_local_to_scalar(...)`).

Every building block called above already exists in the CVM data-access layer. Missing piece is just this one function that unpacks the row and orchestrates the calls.

## Deliverables

1. **Dispatch registration** — some mechanism (a table lookup, a switch, whatever fits `M:run_row`'s current shape) that maps `{in: 'as'}` heads to `dispatch_as`.
2. **`dispatch_as` function** — as described above.
3. **End-to-end test** — load `$x = 1`, run it, assert frame 0's locals bucket has `x` pointing at a scalar whose value is 1.

## Non-goals

- Value atoms other than `{v = N}` (the number case). Vars, calls, hash literals — later sprints.
- Assignment target shapes other than a bare local name. Subscript assign, compound assign — later sprints.
- Any other row-head shape. Function calls, if/else, bareword commands — later sprints.

## Status

**Sprint kicked off.** No code yet.
