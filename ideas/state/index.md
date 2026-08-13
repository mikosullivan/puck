~~~vibecode
{"doc": "idea",
	"role": "state.lua — constructor for an in-memory Lua-side model of Caspian's execution state (roles as a Trivet tree, ID counter as a Sequence object, plus empty hashes/arrays for other fields). Was under src/engine/ but never consumed by shipping engine code — the runtime went through the CVM's SQLite schema instead of a parallel Lua-side hash. Moved back to ideas/ alongside Trivet (its only significant dependency) when Trivet was demoted.",
	"status": "demoted from shipping; revival contingent on a use case for the parallel Lua-side state model"}
~~~

# state.lua

**What it is.** Constructor for the CVM state hash — a Lua-side hash with all execution-state fields present at their empty representation. Roles as a Trivet tree with `engine` at the root and `user` as its child; an ID counter as a Sequence; empty hashes/arrays for other fields.

**Why it's here in ideas/.** state.lua was built as the Lua-side companion to the CVM. The idea was that some code paths would work against this in-memory model rather than SQLite directly. In practice, shipping went single-path through the CVM's SQLite schema — no consumer for the Lua-side model materialized. state.lua became a well-tested constructor whose output nobody used.

Its two dependencies (Trivet for the role tree, Sequence for the ID counter) tell part of the story. Trivet has been [demoted alongside state.lua](../trivet/). Sequence stays in shipping — used elsewhere.

**What's preserved.** The constructor at [`state.lua`](./state.lua) and its two test files under [`tests/`](./tests/) (`test_state.lua` and `test_roles.lua`). Running the tests would need a package.path setup that reaches [ideas/trivet/trivet.lua](../trivet/trivet.lua) and shipping's `src/engine/sequence.lua`. Not currently wired.

**When it comes back.** Alongside a use case for a Lua-side execution-state model that shipping code actually consumes. Not currently in view.
