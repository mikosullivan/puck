~~~vibecode
{"doc": "idea",
	"role": "Trivet — an n-ary tree library. Was under src/engine/ during an earlier phase when it was going to be a foundational tool (execution state modeled as a tree; roles as a Trivet tree; scope chains as a tree walk). Moved back to ideas/ when it turned out shipping code didn't consume it — everything went through the CVM's SQLite schema instead. Preserved here (code + full test suite) because Trivet will be back, just not as such a fundamental tool.",
	"status": "demoted from shipping; revival deferred"}
~~~

# Trivet

**What it is.** N-ary tree library for Lua. Wraps arbitrary values in Node objects with single-parent and no-cycle invariants enforced at every mutation. A tree is defined by its root node — no container class.

**Why it's here in ideas/.** Trivet was originally under `src/engine/` as a foundational tool. The design premise was that a lot of Caspian's execution state would be tree-shaped and would benefit from a well-typed tree library — role hierarchies, scope chains, frame stacks. In practice, shipping code went a different way: SQLite tables and refs handle the tree-shaped state directly. Trivet ended up as a well-tested library with no shipping consumer.

**What's preserved.** The full library at [`trivet.lua`](./trivet.lua) and its 93-test suite under [`tests/`](./tests/). Run standalone from the repo root with:

~~~
lua5.4 ideas/trivet/tests/run.lua
~~~

Path setup inside the runner reaches `ideas/trivet/trivet.lua` — self-contained.

**V1 status.** Trivet is **not technically on the V1 requirements list**, but it's a **really want** feature. Won't block V1 shipping if it doesn't return by then; if it fits, it lands.

**When it comes back.** Miko has flagged that Trivet will return, but not as a foundational tool — probably as a supporting library for a specific use case where a real n-ary tree is the right abstraction. The revival point is TBD.

**Companion:** [ideas/state/](../state/) held the in-memory execution state model that used Trivet for its role tree. Moved out at the same time for the same reason.
