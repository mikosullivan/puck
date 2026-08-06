# The base Repeatable class

~~~vibecode
{"vibecode": {
	"doc": "ideas_controllers_iterators_repeatable",
	"role": "Lua-side design for the Repeatable base class every primitive loop shape (while, until, .each, .times, .upto, .downto, begin ... while) inherits from. Owns the shared looper machinery, the LoopBreak / LoopNext exception classes, and the get_next contract. Subclasses supply their own get_next; the looper handles interstitials, break/next, and the iterator lifecycle. Split out from ideas/controllers/iterators/interstitials on 2026-08-06 because the base-class content is more general than interstitials specifically.",
	"status": "spitballing 2026-08-06 — shape captured; not yet in requirements"
}}
~~~

**Soft design.** Everything on this page is a proposed Lua implementation, not a firm requirement. When the iterators docs move into `requirements/`, most content becomes real spec — this page stays as proposed design until the shape settles.

Minimal Lua shell for the base class every loop shape inherits from. Specific loop shapes (while, each, times, ...) supply their own `get_next` and inherit the shared `looper` machinery shown in § Core loop mechanism below.

~~~lua
Repeatable = {}
Repeatable.__index = Repeatable

function Repeatable.new()
	local self = setmetatable({}, Repeatable)
	return self
end

-- Subclasses override this. Return `sentinel, value` where sentinel is any
-- truthy value while iteration continues, and nil when iteration is done.
-- The value itself can be anything, including nil or false — the sentinel is
-- what signals termination, not the value.
function Repeatable:get_next()
	error('Repeatable subclass must implement get_next')
end
~~~

Loop-control exception classes — raised by the iterator's `.break` / `.next` methods, caught by the looper. `LoopBreak` carries an optional value so `break VALUE` can return that value from the loop:

~~~lua
LoopBreak = {}
LoopBreak.__index = LoopBreak

function LoopBreak.new(value)
	local self = setmetatable({value = value}, LoopBreak)
	return self
end

LoopNext = {}
LoopNext.__index = LoopNext

function LoopNext.new()
	local self = setmetatable({}, LoopNext)
	return self
end
~~~

## Core loop mechanism

There should be exactly one core loop function in Lua, shared by every primitive loop shape (`while`, `until`, `.each`, `.times`, `.upto`, `.downto`, `begin ... while`). They differ in their condition-checking and per-iteration mechanics; the interstitial handling and iterator lifecycle are shared machinery. Single source of truth — no competing custom loop implementations.

Each primitive loop shape provides its own `self.get_next()` — the piece that differs between `while`, `until`, `.each`, `.times`, and the rest. The looper structure around `get_next` is shared. The block receives both the current value (`result`) and the iterator in one call, so a user's `do($record) as $loop` binds `$record` to `result` and `$loop` to the iterator.

~~~lua
function looper(self, call)
	local first_loop_done = false
	local iterator = call.iterator or Iterator.new()

	while true do
		local more, result = self:get_next()
		if not more then break end

		if first_loop_done then
			if call.attached['between'] then
				call.attached['between']:call()
			end
		else
			if call.attached['before'] then
				call.attached['before']:call()
			end

			first_loop_done = true
		end

		-- fancy way of saying "yield":
		local ok, err = pcall(function()
			call.blocks[0]:call({iterator = iterator, result = result})
		end)

		if not ok then
			if getmetatable(err) == LoopNext then
				-- do nothing; continue to next iteration
			elseif getmetatable(err) == LoopBreak then
				return err.value           -- break's value becomes the loop's return
			else
				error(err)                  -- propagate other exceptions
			end
		end
	end

	if first_loop_done then
		if call.attached['after'] then
			call.attached['after']:call()
		end
	elseif call.attached['noloop'] then
		call.attached['noloop']:call()
	end
end
~~~

## Example: iterating an array

A concrete Repeatable subclass that walks through an array element by element. Snapshots the array length at construction so iteration count is deterministic even if the array is mutated mid-loop.

~~~lua
-- Repeatable for iterating an array in order.
ArrayRepeatable = setmetatable({}, {__index = Repeatable})
ArrayRepeatable.__index = ArrayRepeatable

function ArrayRepeatable.new(array)
	local self = setmetatable({}, ArrayRepeatable)
	self.array = array
	self.pos = 0
	self.max = #array
	return self
end

function ArrayRepeatable:get_next()
	self.pos = self.pos + 1

	if self.pos > self.max then
		return nil
	end

	return true, self.array[self.pos]
end
~~~

Deliberate half-measure: the SNAPSHOT is of the indexes, not the contents. If the array is mutated during iteration:

- **Length-changing mutations** don't change how many iterations happen — additions past the original end aren't visited; removals don't stop iteration early.
- **Element values are live** — if `array[3]` changes value mid-iteration, iteration at position 3 sees the new value. If elements are removed and the array shrinks, later positions index past the actual data and Lua returns `nil` for those slots. Under the sentinel-based `get_next`, that becomes `true, nil` — the block still runs, and gets nil as the value.

Mutating a collection while iterating over it is always a bad idea. This design just gives you deterministic index count regardless.

The looper handles everything else — creating the iterator, checking for interstitials, wrapping the yield in a pcall for break/next signals, firing `:after` or `:noloop` at the end. Each iteration calls `self:get_next()`; when it returns `nil` the loop exits and normal-completion handling runs.
