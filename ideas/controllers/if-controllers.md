# If controllers

~~~vibecode
{"vibecode": {
	"doc": "ideas_controllers_if_controllers",
	"role": "design for if-controllers — the controller type produced by `if` / `unless` chains via the `as $name` binding. Enables an if chain to explicitly return a value via `$if.return VALUE`. Peer to iterators (which come from loops). See requirements/controllers for the general controller concept.",
	"status": "spitballing 2026-08-06 — basic behavior captured; details pending"
}}
~~~

An if-controller lets an `if` (or `unless`) chain explicitly return a value:

~~~caspian
$val = if $foo as $if
	$if.return 'foo'
else
	$if.return 'bar'
end
~~~

Two rules:

- **Explicit `.return VALUE`** — the value becomes the if's return value; `$val` receives it.
- **No explicit `.return`** — the if returns `null`, regardless of what expressions ran inside any branch.

This differs from the current spec, which returns the value of the last expression in the executed branch (Ruby-style implicit return). Under this proposal, `if` returns `null` by default; a value comes back only when the code explicitly requests it via the controller.

## Lua implementation

**Soft design.** Rough draft of the if-controller machinery, matching the shape of `Repeatable` / `Iterator` / `LoopBreak` in [ideas/controllers/iterators/interstitials](https://www.puck.uno/ideas/controllers/iterators/interstitials). Three classes: `Conditions` (the runtime representation of an if-atom), `IfController` (what `$if` binds to), `IfReturn` (the exception carrying the return value).

### The Conditions class

Represents a CaspM if-atom (`{if: {conditions, else}}`) at runtime. Constructed from the atom; `evaluate` walks the conditions and returns the value.

~~~lua
Conditions = {}
Conditions.__index = Conditions

function Conditions.new(conditions_atom)
	local self = setmetatable({}, Conditions)
	self.conditions = conditions_atom.conditions
	self.else_body = conditions_atom['else']  -- 'else' is reserved in Lua; subscript to access
	return self
end

function Conditions:evaluate(call)
	local controller = call.controller or IfController.new()

	for _, cond in ipairs(self.conditions) do
		if evaluate_test(cond.test) then
			local ok, err = pcall(function()
				execute_action(cond.action, controller)
			end)

			if not ok then
				if getmetatable(err) == IfReturn then
					return err.value
				else
					error(err)  -- propagate other exceptions
				end
			end

			return nil  -- action ran to completion; no explicit .return
		end
	end

	-- No test matched — try else
	if self.else_body then
		local ok, err = pcall(function()
			execute_action(self.else_body, controller)
		end)

		if not ok then
			if getmetatable(err) == IfReturn then
				return err.value
			else
				error(err)
			end
		end
	end

	return nil  -- no test matched, no else, no explicit return
end
~~~

`evaluate_test` and `execute_action` are placeholders for engine-level helpers that evaluate a test atom and run a body of statement atoms with the controller in the current call's controller slot.

### The If and Unless subclasses

`If` and `Unless` are both subclasses of `Conditions`. `If` uses tests as-is; `Unless` negates the first test and uses subsequent tests as-is.

~~~lua
-- If: standard interpretation; use each test as-is.
If = setmetatable({}, {__index = Conditions})
If.__index = If

function If.new(conditions_atom)
	local self = Conditions.new(conditions_atom)
	setmetatable(self, If)
	return self
end
~~~

`If` adds nothing over `Conditions` — the subclass exists as a type marker (an `if` atom in CaspM constructs an `If`, not a bare `Conditions`).

~~~lua
-- Unless: negate the first test, use subsequent tests as-is.
Unless = setmetatable({}, {__index = Conditions})
Unless.__index = Unless

function Unless.new(conditions_atom)
	local self = Conditions.new(conditions_atom)
	setmetatable(self, Unless)
	-- Wrap the first test in a negation.
	if self.conditions[1] then
		self.conditions[1].test = {op = '!', operand = self.conditions[1].test}
	end
	return self
end
~~~

Once the first test is negated at construction, the inherited `Conditions:evaluate` runs the standard walk — no override needed. The `unless` semantics fall out of the negation plus the standard interpretation.

**Note on the CaspM spec.** [caspianj § if-atom](https://www.puck.uno/requirements/caspianj#if-atom) currently says `unless` is normalized to `if` with the first test wrapped in `!` at normalize time. Under this Lua design, that collapse would move to runtime (in `Unless.new`) instead — CaspM keeps its own `unless: {...}` atom variant distinct from `if: {...}`. Choice worth pinning: keep normalize-time collapse and drop the `Unless` class, or move the collapse to runtime via the subclass.

### The IfController class

What `$if` binds to inside an if body. Provides `.return` to hand back a value from any branch.

~~~lua
IfController = {}
IfController.__index = IfController

function IfController.new()
	local self = setmetatable({}, IfController)
	return self
end

-- Caspian's $if.return dispatches to this method.
-- (Lua's 'return' is reserved, so the Lua method uses a trailing underscore.)
function IfController:return_(value)
	error(IfReturn.new(value))
end
~~~

### The IfReturn exception class

Carries the value from `$if.return` up to the Conditions evaluator, which catches it and returns.

~~~lua
IfReturn = {}
IfReturn.__index = IfReturn

function IfReturn.new(value)
	local self = setmetatable({value = value}, IfReturn)
	return self
end
~~~
