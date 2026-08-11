--[[
{
	"module": "frame",
	"role": "Class representing a call frame under the frames-as-objects design. Inherits from `object` — picks up the `bucket` accessor for free. Adds `locals`, which returns the frame's locals hash: a HashPrimitive stored inside the frame's bucket under the key `locals`. Every local variable in the frame is a key in that hash.",
	"inherits_from": "object",
	"exports": {
		"new":    "(engine, row) -> frame — constructor",
		"locals": "() -> object — the frame's locals hash; nil if it hasn't been created yet (read-only)"
	},
	"status": "sketch — walking-skeleton, first pass at Lua-native class file"
}
]]

--[[
# Frame

A class representing a call frame under the frames-as-objects design.
Inherits from `object`, so it picks up the `bucket` accessor for free.
Adds one method — `locals` — that returns the frame's locals hash: a
HashPrimitive stored inside the frame's bucket under the key `locals`.
Every local variable in the frame is a key in that hash.
]]

local object = require("object")

-- Single inheritance via metatable chain: frame inherits object's
-- methods (bucket, ...); frame's own methods override or extend.
local frame = setmetatable({}, {__index = object})
frame.__index = frame

--[[
## Constructing a frame

`frame.new(engine, row)` builds an ordinary object first (so column
fields get lifted onto self by the inherited constructor), then
re-parents `self`'s metatable to `frame` so frame's own methods
(`locals`, ...) resolve on lookup.
]]
function frame.new(engine, row)
	local self = object.new(engine, row)
	return setmetatable(self, frame)
end

--[[
## `locals` — the frame's locals hash

Returns the frame's locals hash — a HashPrimitive stored inside the
frame's bucket under the key `locals`. `nil` if it hasn't been created
yet.

Composes on the inherited `bucket` accessor: get the bucket (which
materializes it on first access), then look up the entry stored under
`locals`.

**Read-only.** `locals` doesn't create the locals hash — it only
returns whatever's stored under `bucket['locals']`. On a fresh frame,
before anything has been assigned, that entry doesn't exist yet and
this returns `nil`. Creating the locals hash on demand happens in the
assignment path, not here — see the
[first-variable walkthrough](https://www.puck.uno/ideas/frames-as-objects/examples/first-variable/#set-framelocalsx-)
for how `frame.locals['x'] = <pk>` composes.
]]
function frame:locals()
	local bucket = self:bucket()
	return bucket['locals']
end

return frame
