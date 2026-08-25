--[[
{
	"module": "method_call",
	"role": "Sprint-scoped Handler that dispatches CaspM fc-shape rows (function calls). Matches the row shape the normalizer produces for `receiver.method` — a row containing one array-atom whose head is {in='mc'} and body is {fn=<method_name>, rc=<receiver_atom>}. Recursively evaluates receiver atoms (variables, literals, nested fc calls), dispatches methods via the .obj name-check fast-path and the engine_class='obj' layer, materializes the return value into the frame's rv slot. Not a full method-call primitive — no lazy args, no class-chain walk beyond engine_class, no support for methods on receivers that aren't agents. Enough to run `$foo = 'bar'; $foo.obj.pk` end-to-end.",
	"exports": {
		"new": "() -> MethodCall — Handler subclass instance; add to an engine via engine:add_handler(MethodCall.new())"
	},
	"depends_on": ["handler", "obj"],
	"status": "sprint — minimum dispatcher for .obj + engine_class='obj' methods; not a general primitive"
}
]]

--[=[
# `method_call`

A minimal method-call dispatcher for the object sprint.

**Row match.** The normalizer produces this shape for `$foo.obj.pk`:

    [[{in='mc'}, {fn='pk', rc=[{in='mc'}, {fn='obj', rc={var='foo'}}]}]]

One row, one atom (which is itself an array of a head atom and a call
atom). The handler matches when `row[1]` is a table whose first
element carries `in='mc'`.

**Evaluation.** `evaluate_atom` walks the atom tree recursively:

- `{var=<name>}` — look up the variable in the frame's scope chain
  via the `frame_scoped_vars` view.
- `{v=<literal>}` — materialize a scalar row via `engine.data:add_scalar`.
- `[{in='mc'}, {fn=..., rc=...}]` — evaluate the receiver, then
  dispatch the method.

**Dispatch.** Two paths, checked in order:

1. **`.obj` fast-path.** Method name `obj` → construct a fresh agent
   via `obj.new(engine, receiver_pk)` and return the agent's pk. Skips
   the engine_class check entirely — the whole point is that `.obj`
   is unshadowable.
2. **`engine_class='obj'` layer.** Look up the receiver's
   `engine_class`. If it's `'obj'`, dispatch to `obj.methods[fn]`
   with a wrapper around the receiver. Any other engine_class value
   raises method_not_found — this sprint only implements obj.

**rv wiring.** After evaluation, the top-level row's result gets
written into the frame's rv slot: materialize the frame's bucket if
missing, then UPSERT a ref keyed 'rv' pointing at the result. The
walker's next advance reaps the frame; the propagate-rv trigger
carries the rv up to the parent (or cap, if this was frame 0).

**What's NOT here.**

- No lazy args (every arg would be evaluated eagerly if we grew args).
- No class-chain walk beyond `engine_class='obj'`.
- No method-call frames — dispatch runs inline, like a leaf command.
- No `{op='.'}` dispatch (the transpiler produces this pre-normalize;
  normalize rewrites it to fc; we assume normalize has already run).
- No sub-expression frames per the walking-skeleton discipline — each
  fc happens inline in Lua, not as its own CVM frame.

Real method-call primitive lives in the method-call sprint. This
handler is the minimum needed to run the sprint's target expression
end-to-end.
]=]
local Handler = require('handler')
local obj_mod = require('obj')


-- Forward declarations so mutually-recursive locals resolve.
local evaluate_atom
local dispatch_method
local lookup_var
local set_frame_rv


local MethodCall = setmetatable({}, {__index = Handler})
MethodCall.__index = MethodCall


function MethodCall.new()
	return setmetatable(Handler.new(), MethodCall)
end


--[[
## `MethodCall:handle` — match + dispatch fc rows

Returns true iff the row is fc-shape. Non-fc rows fall through to
the next handler in the chain.
]]
function MethodCall:handle(engine, row)
	if type(row[1]) ~= 'table' then
		return false
	end

	if type(row[1][1]) ~= 'table' or row[1][1]['cmd'] ~= 'mc' then
		return false
	end

	local result_pk = evaluate_atom(engine, row[1])

	set_frame_rv(engine, engine.current_frame.object_pk, result_pk)

	engine.data:mark_frame_gc(engine.current_frame.object_pk)

	return true
end


--[[
## `evaluate_atom` — atom → object_pk

Recursively evaluate any atom the sprint knows about. Returns the
object_pk of the value the atom produces.
]]
function evaluate_atom(engine, atom)
	if type(atom) ~= 'table' then
		error("method_call_evaluate_atom_unrecognized: not a table: " .. type(atom))
	end

	-- Variable lookup: {var=<name>}
	if atom['var'] then
		return lookup_var(engine, atom['var'])
	end

	-- Literal value: {v=<literal>}
	if atom['v'] ~= nil then
		return engine.data:add_scalar(atom['v'], engine.current_frame.owner_role)
	end

	-- fc atom: [{in='mc'}, {fn=..., rc=...}]
	if type(atom[1]) == 'table' and atom[1]['cmd'] == 'mc' then
		local call = atom[2]
		local receiver_pk = evaluate_atom(engine, call.rc)
		return dispatch_method(engine, receiver_pk, call.fn)
	end

	error("method_call_evaluate_atom_unrecognized_shape: no var/v/fc match")
end


--[[
## `dispatch_method` — receiver + method name → object_pk

The two-path dispatcher: `.obj` fast-path first, engine_class layer
next. Nothing else is spec'd for this sprint; anything the two paths
don't handle raises.
]]
function dispatch_method(engine, receiver_pk, method_name)
	-- Fast-path: .obj → construct a fresh agent
	if method_name == 'obj' then
		local agent = obj_mod.new(engine, receiver_pk)
		return agent.pk
	end

	-- Look up receiver's engine_class
	local engine_class

	for row in engine.cvm:nrows(
		"select engine_class from objects where object_pk = '" .. receiver_pk .. "'"
	) do
		engine_class = row.engine_class
	end

	if engine_class == 'obj' then
		local method = obj_mod.methods[method_name]

		if not method then
			error("method_call_obj_method_not_found: no obj.methods." .. tostring(method_name))
		end

		local wrapper = setmetatable({
			pk     = receiver_pk,
			engine = engine,
			db     = engine.cvm,
		}, obj_mod)

		return method(wrapper)
	end

	error("method_call_no_dispatch_path: method='" .. tostring(method_name)
		.. "' engine_class=" .. tostring(engine_class)
		.. " (sprint only handles .obj fast-path + engine_class='obj')")
end


--[[
## `lookup_var` — variable name → object_pk

Walks the frame's scope chain via the `frame_scoped_vars` view.
Returns the value_pk of the first (innermost) matching binding.
Raises undeclared_variable if no binding exists — matches the
undeclared-read sprint's rule.
]]
function lookup_var(engine, name)
	for row in engine.cvm:nrows(
		"select value_pk from frame_scoped_vars "
		.. "where frame_pk = '" .. engine.current_frame.object_pk .. "' "
		.. "and var_name = '" .. name .. "' "
		.. "order by scope_idx limit 1"
	) do
		return row.value_pk
	end

	error("undeclared_variable: no binding for '" .. tostring(name) .. "' in scope")
end


--[[
## `set_frame_rv` — write a value into a frame's rv slot

Materializes the frame's bucket if missing, then UPSERTs a ref keyed
'rv' pointing at the value.
]]
function set_frame_rv(engine, frame_pk, value_pk)
	local bucket_pk = engine.data:add_bucket(frame_pk)

	engine.data:upsert_ref(bucket_pk, 'rv', value_pk)
end


return MethodCall
