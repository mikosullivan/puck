--[[
{
	"module":  "postnormalize",
	"role":    "Sprint post-processing pass on top of the production normalizer's CaspM output. Rewrites four constructs into the sprint's target `fc`-call shapes: `||` / `&&` op atoms become `.obj.or` / `.obj.and` calls (left operand's `.obj` as receiver, right operand wrapped as a closure arg); the `{if: {conditions, else}}` atom becomes an `engine.if` call (conditions list as first arg, else closure as second, tests wrapped as closures); the `[scope, while_end, ...]` row becomes an `engine.while` call (test and body both wrapped as closures). Ternary flows through the `{if: ...}` rewrite because the production normalizer already collapses `{op: '?:'}` into that shape. Recursive walk over the whole CaspM; matches at any depth get rewritten in place.",
	"exports": {
		"process": "CaspM (Lua table) -> CaspM (fresh table) with the sprint's rewrites applied"
	}
}
]]

--[[
# `postnormalize`

Runs AFTER the production normalizer. Applies the expressions
sprint's rewrites to convert the remaining non-`fc` construct
shapes into `fc`-call shapes that go through `method_call`
uniformly.

**Rewrites in play:**

- `{op: "||"}` atom → `.obj.or` call on the left operand's `.obj`.
- `{op: "&&"}` atom → `.obj.and` call, same shape.
- `{if: {conditions, else}}` atom → `engine.if` call with a list
  of `[test_cl, action_cl]` pairs as the first arg and an optional
  else closure as the second. Tests get closure-wrapped by this
  pass (the production normalizer leaves them as raw expressions);
  actions and else are already closure atoms from the transpiler.
- `[scope, while_end, <test>, {bd: <body>}]` row → `engine.while`
  call with both test and body wrapped as closures.

Ternary `? :` doesn't need its own rewrite here — the production
normalizer at [production/src/engine/normalize.lua:657](../../../production/src/engine/normalize.lua)
already collapses `{op: "?:"}` op atoms into the same `{if: ...}`
atom shape used by the keyword `if`, so the ternary flows through
the `if`-rewrite path.

**Recursion.** Walks every value in the CaspM tree; matches at any
depth are substituted; non-matches recurse into their children.
Rows containing a rewritten if atom get hoisted (the wrapping
one-element row is replaced by the rewrite result) so the output
doesn't accumulate row-within-row scaffolding.

**Input is not mutated.** All output is fresh Lua tables.
]]

local M = {}

local process_atom

-- Wrap an expression in a `cl` closure atom whose body is exactly
-- that expression.
--
-- Rows (positional arrays like `[{in: "fc"}, envelope]`) become the
-- inner statement directly — the row IS the statement. Bare atoms
-- (hashes like `{var: "x"}`) become the sole atom of a one-atom
-- statement.
local function wrap_as_closure(expr)
	local body_stmt

	if type(expr) == 'table' and expr[1] ~= nil then
		body_stmt = expr
	else
		body_stmt = {expr}
	end

	return {cl = {pm = {}, bd = {body_stmt}}}
end

-- Build a two-element fc-call row: [{in: "fc"}, envelope].
local function fc_call(receiver, method_name, args)
	return {
		{['in'] = 'fc'},
		{
			rc = receiver,
			fn = method_name,
			a  = args,
		}
	}
end

-- Rewrite for `{op: "||", left, right}` and `{op: "&&", left, right}`.
--
-- Produces `[{in: "fc"}, {rc: <left.obj>, fn: <name>, a: [<right_cl>]}]`.
-- `<left.obj>` is itself an fc call that dispatches `.obj` on the
-- left value to get its .obj-namespace wrapper.
local function rewrite_short_circuit(v, fn_name)
	local left  = process_atom(v.left)
	local right = process_atom(v.right)

	local left_obj = fc_call(left, 'obj', {})

	return fc_call(left_obj, fn_name, {wrap_as_closure(right)})
end

-- Rewrite for `{if: {conditions: [{test, action}], else?}}` atom.
--
-- Produces `[{in: "fc"}, {rc: {var: "engine"}, fn: "if", a: [<pairs>, <else?>]}]`.
--
-- Each condition's `test` gets closure-wrapped (raw in current CaspM).
-- Each condition's `action` is already a `cl` atom from the transpiler
-- and passes through. Pairs are represented as `{ar: [test_cl, action_cl]}`
-- entries in an outer `{ar: [pair, pair, ...]}`.
local function rewrite_if(if_atom)
	local pairs_list = {}

	for _, cond in ipairs(if_atom.conditions) do
		local test_cl   = wrap_as_closure(process_atom(cond.test))
		local action_cl = process_atom(cond.action)

		table.insert(pairs_list, {ar = {test_cl, action_cl}})
	end

	local args = {{ar = pairs_list}}

	if if_atom['else'] ~= nil then
		table.insert(args, process_atom(if_atom['else']))
	end

	return fc_call({var = 'engine'}, 'if', args)
end

-- Rewrite for `[scope, while_end, <test>, {bd: <body_stmts>}]` row.
--
-- Produces `[{in: "fc"}, {rc: {var: "engine"}, fn: "while", a: [<test_cl>, <body_cl>]}]`.
--
-- Test wraps as a closure. Body is `{bd: [stmts]}`; converts to
-- `{cl: {pm: [], bd: [processed_stmts]}}`.
local function rewrite_while(row)
	local test_expr    = process_atom(row[3])
	local body_wrapper = row[4]
	local body_stmts   = {}

	if type(body_wrapper) == 'table' and body_wrapper.bd then
		for _, stmt in ipairs(body_wrapper.bd) do
			table.insert(body_stmts, process_atom(stmt))
		end
	end

	local test_cl = wrap_as_closure(test_expr)
	local body_cl = {cl = {pm = {}, bd = body_stmts}}

	return fc_call({var = 'engine'}, 'while', {test_cl, body_cl})
end

-- Recursive walk. Detects rewrite-target shapes and substitutes;
-- otherwise recurses into children.
process_atom = function(v)
	if type(v) ~= 'table' then
		return v
	end

	-- Match the outermost `[scope, while_end, <test>, {bd: <body>}]`
	-- statement-row shape.
	if v[1] == 'scope' and v[2] == 'while_end' then
		return rewrite_while(v)
	end

	-- Hoist an `[{if: {...}}]` one-element row up to the rewrite
	-- result directly, so the output isn't a row-containing-a-row.
	if #v == 1 and type(v[1]) == 'table' and v[1]['if'] ~= nil
			and type(v[1]['if']) == 'table' and v[1]['if'].conditions ~= nil then
		return rewrite_if(v[1]['if'])
	end

	-- Match an if atom embedded elsewhere in the tree.
	if v['if'] ~= nil and type(v['if']) == 'table' and v['if'].conditions ~= nil then
		return rewrite_if(v['if'])
	end

	-- Match `||` and `&&` op atoms at any depth.
	if v.op == '||' and v.left ~= nil and v.right ~= nil then
		return rewrite_short_circuit(v, 'or')
	end

	if v.op == '&&' and v.left ~= nil and v.right ~= nil then
		return rewrite_short_circuit(v, 'and')
	end

	-- Generic recursion: build a fresh table, recurse into every
	-- value (both hash and array-position).
	local out = {}

	for k, val in pairs(v) do
		out[k] = process_atom(val)
	end

	return out
end

--[[
{
	"in":  "CaspM produced by the production normalizer (Lua table, list of statement rows)",
	"out": "CaspM with the sprint's rewrites applied (fresh Lua table)"
}
]]
function M.process(caspm)
	if type(caspm) ~= 'table' then
		return caspm
	end

	local out = {}

	for _, stmt in ipairs(caspm) do
		table.insert(out, process_atom(stmt))
	end

	return out
end

return M
