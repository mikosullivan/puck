--[[
{
	"module": "frame",
	"role": "Class attached to `objects` rows with `control = 'f'`. Currently an empty subclass of `object` — behavior that used to live here (own_scope / ensure_own_scope / set_local_to_scalar) moved to CVM as plain functions taking pks, so handlers can work in pks instead of wrapper instances. The class survives only so `object.new` has something to dispatch to when it sees `control='f'`. Frame-specific behavior lands here again if it turns out something genuinely needs wrapper-instance state (memoization on the frame's identity, say).",
	"inherits_from": "object",
	"exports": {
		"new": "(engine, row) -> frame — constructor; asserts control='f' and wraps the row via object._wrap"
	},
	"depends_on": ["cvm.object"],
	"status": "V0.1"
}
]]

--[[
# Frame

The class attached to every `objects` row with `control = 'f'` — a frame, an instance of a call. Distinct from a function or closure: those are plain `base = 'o'` objects that store their CaspM in a bucket entry. When one is called, the engine creates a fresh `control = 'f'` row and copies the CaspM into its `frame_ast` column. The function object stays where it is; the frame is a separate row with the code it's actually running.

Frames are destroyed when finished — the walker's advance-with-frame_gc UPDATE cascade-sweeps any child (marker or completed nested call); when a frame's own frame_ast is exhausted its parent's next advance cascade-sweeps it in turn. See [frame-lifecycle](https://puck.uno/requirements/cvm/sqlite/frame-lifecycle) for the full walkthrough. Closures capture the locals hash directly (not the frame).

**Scopes.** The frame's bucket holds a `scopes` key pointing at an ArrayPrimitive:

- `scopes[0]` — this frame's OWN scope hash. Where the assignment handlers write via `cvm:ensure_own_scope(frame_pk, owner_role_pk)`.
- `scopes[1]`, `scopes[2]`, ... — captured scopes from an enclosing closure, if any.

The scope-chain machinery lives on the CVM (`ensure_own_scope`, `get_ref_child`, `get_ref_child_at_idx`); handlers call it directly with the frame's pk and owner_role_pk. Multi-scope lookup (walk from scopes[0] outward for variable resolution) lands with the closure work.

Inherits from `object` — picks up the `bucket` accessor for free.
]]
local object = require("cvm.sqlite.object")


local frame = setmetatable({}, {__index = object})
frame.__index = frame

--[[
## Constructing a frame

`frame.new(engine, row)` uses `object._wrap` — the shared row-as-instance helper — with `frame` as the metatable. Going through `_wrap` (rather than calling `object.new`) skips `object.new`'s control-based dispatch, so a frame row loaded via `engine:object_by_pk` doesn't recurse into `object.new → frame.new → object.new → …`.
]]
function frame.new(engine, row)
	if row.control ~= 'f' then
		error(
			"frame_new_not_a_frame_row: expected control='f', got '" ..
			tostring(row.control) .. "' (pk " ..
			tostring(row.object_pk) .. ")"
		)
	end

	return object._wrap(frame, engine, row)
end

return frame
