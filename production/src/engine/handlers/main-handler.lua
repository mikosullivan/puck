--[[
{
	"module": "handlers.main-handler",
	"role": "The main row-handler for the CaspM dispatcher. Recognizes {cmd: 'mc'} method-call rows, extracts the envelope (fn, rcvr, args, kw?, blocks?), resolves the receiver, evaluates the args, and dispatches the named method. Receives a Frame object (not the engine) as the dispatch context — the frame IS the receiver for {sys: 'frame'} atoms and holds the pk / role_pk / engine reference the method implementations need. Currently understands: the '=' method on {sys: 'frame'} (assignment) with literal-value ({v: X}) args.",
	"exports": {
		"new":    "() -> MainHandler",
		"handle": "(frame, row, restart?) -> true when dispatched; false when the row isn't {cmd: 'mc'} or the mc envelope's shape isn't yet recognized. `restart` is accepted for signature parity with the base but currently ignored — the two-phase-dispatch logic that would read it lands separately"
	},
	"depends_on": ["handler"],
	"status": "V0.1 — assignment via {fn: '=', rcvr: {sys: 'frame'}, args: [name, {v: value}]}"
}
]]

--[[
# `handlers.main-handler`

The engine's main row-handler. Recognizes `{cmd: 'mc'}` method-call rows and dispatches them.

**Signature:** `handle(frame, row, restart)`. The dispatch context is a Frame object (a subclass of `object`) — the currently-walking frame. Handlers reach into `frame.object_pk`, `frame.owner_role`, `frame.engine` to do their work. No `engine.current_frame_pk` field to consult; the frame IS the context. The `restart` flag is currently ignored — the assign path is single-shot at present; when the two-phase (spawn-eval → bind-on-return) shape lands, `restart` becomes the switch that routes to phase 2.

**Row shape.** Two elements: a head atom `{cmd: 'mc'}` and an envelope `{fn, rcvr, args?, kw?, blocks?, l?}`. See [caspianj § Calls](https://puck.uno/production/requirements/caspianj#calls).

**Dispatch steps:**

1. **Match.** `row[1].cmd == 'mc'`. Any other shape returns false — the walker falls through to `unrecognized_caspm`.
2. **Read envelope.** Extract `fn`, `rcvr`, `args` from `row[2]`.
3. **Resolve receiver.** Currently only `{sys: 'frame'}` — resolves to the `frame` argument itself (the currently-walking frame IS the frame receiver). Additional receiver shapes (`{var: NAME}` variable reads, nested `[{cmd:'mc'}, ...]` method-call results, `{v: LITERAL}` literals) land as the sprint grows.
4. **Dispatch by (receiver, fn).** Currently only `'='` on the current frame — the assignment path. Other methods land as the sprint grows.
5. **Evaluate args.** Value atoms `{v: X}` yield the Lua literal `X`. Bareword strings pass through unchanged (name-position args, like the target of an assign).
6. **Invoke.** Run the method's implementation against the CVM.

**Currently supported:** `[{cmd:'mc'}, {fn:'=', rcvr:{sys:'frame'}, args:[NAME, {v: LITERAL}]}]` — the assignment shape the normalizer produces for `$x = 1`.

**Design intent.** The main handler is the general dispatcher for CaspM; specialized handlers (like a re-added `variable-scalar`) get slotted back in FRONT of it later as pure optimizations that short-circuit specific shapes without changing behavior.
]]
local Handler = require('handler')


local MainHandler = setmetatable({}, {__index = Handler})
MainHandler.__index = MainHandler


function MainHandler.new()
	return setmetatable(Handler.new(), MainHandler)
end


--[[
## `evaluate_value_atom` — resolve a value atom to a Lua value

Value atoms are the RHS of an assignment, an arg to a method call, etc. — anything that produces a value the dispatcher passes to a method.

Currently supported:

- `{v: X}` — a literal. Returns `X` verbatim.

Anything else raises `main_handler_unsupported_value_atom` — the atom shape hasn't been wired for dispatch yet.
]]
local function evaluate_value_atom(frame, atom)
	if type(atom) == 'table' and atom.v ~= nil then
		return atom.v
	end

	error("main_handler_unsupported_value_atom: don't know how to evaluate atom " .. tostring(atom))
end


--[[
## `is_current_frame_receiver` — recognize `{sys: 'frame'}`

Returns true if the rcvr atom names the currently-walking frame. Under the current design that's `{sys: 'frame'}`. Additional receiver shapes get added here as they land.
]]
local function is_current_frame_receiver(rcvr)
	return type(rcvr) == 'table' and rcvr.sys == 'frame'
end


--[[
## `assign_on_frame` — the `=` method on `{sys: 'frame'}`

Materialize the value as a scalar, ensure the frame's own_scope hash exists, bind name → scalar_pk, mark the frame's gc.

All four writes wrapped in a savepoint so a mid-write failure leaves no dangling scalar or half-bound scope.

Args:
- `frame` — the currently-walking Frame object
- `name` — a bareword string (the target variable name)
- `value` — a Lua value (already evaluated from its value atom)
]]
local function assign_on_frame(frame, name, value)
	local db   = frame.engine.cvm
	local data = frame.engine.data

	assert(db:exec('savepoint main_handler_assign;') == 0, db:errmsg())

	local ok, err = pcall(function()
		local scalar_pk    = data:add_scalar(value, frame.owner_role)
		local own_scope_pk = data:ensure_own_scope(frame.object_pk, frame.owner_role)
		data:upsert_ref(own_scope_pk, name, scalar_pk)
		data:mark_frame_gc(frame.object_pk)
	end)

	if not ok then
		db:exec('rollback to savepoint main_handler_assign;')
		db:exec('release savepoint main_handler_assign;')
		error(err, 0)
	end

	assert(db:exec('release savepoint main_handler_assign;') == 0, db:errmsg())
end


function MainHandler:handle(frame, row, restart)
	-- Only claim {cmd: 'mc'} rows. Anything else falls through.
	if type(row[1]) ~= 'table' or row[1].cmd ~= 'mc' then
		return false
	end

	local envelope = row[2]

	if type(envelope) ~= 'table' then
		error("main_handler_no_envelope: {cmd: 'mc'} row missing envelope at row[2]")
	end

	local fn   = envelope.fn
	local rcvr = envelope.rcvr
	local args = envelope.args or {}

	-- Currently supported method: '=' on the current frame.
	if fn == '=' and is_current_frame_receiver(rcvr) then
		local name = args[1]

		if type(name) ~= 'string' then
			error("main_handler_assign_name_not_bareword: assign target must be a bareword string, got " .. type(name))
		end

		local value = evaluate_value_atom(frame, args[2])
		assign_on_frame(frame, name, value)
		return true
	end

	error("main_handler_unsupported_method: don't know how to dispatch fn '"
		.. tostring(fn) .. "' on receiver <" .. tostring(rcvr) .. ">")
end


return MainHandler
