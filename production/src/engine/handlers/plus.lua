--[[
{
	"module": "handlers.plus",
	"role": "Core handler for arithmetic `+` on numbers. Matches CaspM rows of shape `[{cmd:'mc'}, {fn:'+', rcvr:<operand>, args:[<operand>]}]`. Orchestrates receiver + arg_0 evaluation through spawned child frames — one eval frame per operand — then computes the sum and sets it as the walking frame's rv. Multi-phase: uses bucket refs (`receiver`, `arg_0`) to track which operands have been evaluated so far, picks up state on walker re-dispatch after each child reap.",
	"exports": {
		"new":    "() -> Plus",
		"handle": "(frame, row, restart?) -> true when the row is a `+` method_call; false otherwise"
	},
	"depends_on": ["handler", "cjson"],
	"status": "V0.1 — number + number"
}
]]

--[=[
# `handlers.plus`

Core handler for arithmetic `+`. Currently supports number + number; other type combinations raise `plus_non_numeric_*` errors.

**Shape matched.** `[{cmd:'mc'}, {fn:'+', rcvr:<operand>, args:[<operand>]}]`. Any other row shape (or an `mc` row with `fn ~= '+'`) declines back to the chain.

**Semantic model.** Every operand is evaluated in its own child frame. The handler spawns those frames one at a time, letting the walker recurse in and out, and picks up the produced values via bucket state. Between operand evaluations, the handler moves the just-arrived `rv` into a named bucket slot (`receiver`, then `arg_0`) so the next child's reap-propagate doesn't overwrite it. When all operands are in place, the handler reads their numeric payloads, computes the sum, materializes it as a new scalar, upserts `rv` to point at that scalar, and marks the frame's gc so the walker can advance.

**Multi-phase state machine.** State lives in the frame's bucket. Each entry into `:handle` reads three refs — `receiver`, `arg_0`, `rv` — and decides the next action:

| `receiver` | `arg_0` | `rv` | action |
|---|---|---|---|
| nil | nil | nil | fresh — spawn receiver eval, return |
| nil | nil | set | receiver eval reaped — upsert `receiver` = rv_pk, spawn arg_0 eval, return |
| set | nil | nil | resume after arg_0 eval halted without an rv — respawn arg_0 eval, return |
| set | nil | set | arg_0 eval reaped — upsert `arg_0` = rv_pk, fall through to compute |
| set | set | * | recompute idempotently (halt after phase 3 before advance) |

The last row is what makes the handler halt-safe: on any re-entry with both operands in place, the compute step reproduces the same result (scalars interned by value) and the same gc mark, so a halt anywhere in the third phase re-runs cleanly on restart.

**Operand shape wrapping.** An operand is either an atom (`{v: X}`, `{var: NAME}`, etc. — a hash) or a nested method_call (`[{cmd:'mc'}, envelope]` — an array). To spawn an eval frame for it, wrap it as a one-statement ast:

- Atom → `[[operand]]` (list of one statement; statement is a one-atom array).
- Method_call → `[operand]` (list of one statement; operand IS already a statement-shaped array).

**Why bucket-slot presence, not PK equality.** Scalars are interned by value, so `1 + 1` produces identical PKs for receiver and arg_0. Gating each phase on the PRESENCE of the `receiver` / `arg_0` slots (rather than comparing `rv_pk` to a previous value) works regardless of value coincidences.

**Savepoint wrapping.** The whole state-machine body sits inside a `plus_handle` savepoint so a raise mid-body (e.g. a non-numeric operand) rolls back the partial state — the frame stays in a shape the next re-dispatch (or a subsequent halt-restart) can pick up from cleanly.
]=]

local cjson   = require('cjson')
local Handler = require('handler')


local Plus = setmetatable({}, {__index = Handler})
Plus.__index = Plus


function Plus.new()
	return setmetatable(Handler.new(), Plus)
end


--[=[
## `operand_to_frame_ast_json` — wrap an operand as a one-statement frame ast

Atoms (hashes) get wrapped `[[atom]]`; method_calls (arrays) get wrapped `[method_call]`. The distinction: atoms don't have a numeric index 1 (Lua hash-table with only string keys); method_calls do (Lua array-table starting at index 1).
]=]
local function operand_to_frame_ast_json(operand)
	local stmt

	if type(operand) == 'table' and operand[1] ~= nil then
		-- Array-shape: method_call. The operand IS a statement.
		stmt = operand
	else
		-- Hash-shape: atom. Wrap it as a one-atom statement.
		stmt = {operand}
	end

	return cjson.encode({stmt})
end


--[[
## `spawn_eval_child` — insert a child eval frame for one operand

Uses `data:add_child_frame` (which sets `frame_parent` atomically at INSERT — `frame_parent` is immutable so we can't do it via a follow-up UPDATE).
]]
local function spawn_eval_child(frame, operand)
	local ast_json = operand_to_frame_ast_json(operand)
	return frame.engine.data:add_child_frame(ast_json, frame.object_pk, frame.owner_role)
end


function Plus:handle(frame, row, restart)
	-- Shape match runs outside the savepoint — no state to protect if
	-- we decline.
	local head = row[1]

	if type(head) ~= 'table' or head.cmd ~= 'mc' then
		return false
	end

	local envelope = row[2]

	if type(envelope) ~= 'table' or envelope.fn ~= '+' then
		return false
	end

	local db = frame.engine.cvm

	assert(db:exec('savepoint plus_handle;') == 0, db:errmsg())

	local ok, err = pcall(function()
		local data      = frame.engine.data
		local bucket_pk = data:add_bucket(frame.object_pk)

		local receiver_pk = data:get_ref_child(bucket_pk, 'receiver')
		local arg_0_pk    = data:get_ref_child(bucket_pk, 'arg_0')
		local rv_pk       = data:get_ref_child(bucket_pk, 'rv')

		-- Phase 1: receiver not yet in the bucket.
		if receiver_pk == nil then
			if rv_pk == nil then
				-- Fresh (or halt-restart with no receiver value): spawn
				-- receiver eval and return; walker will recurse into it,
				-- its reap will propagate rv up here.
				spawn_eval_child(frame, envelope.rcvr)
				return
			end

			-- Receiver eval reaped with a value. Move rv into the
			-- `receiver` slot so the next child's reap-propagate can
			-- overwrite rv without losing the receiver.
			data:upsert_ref(bucket_pk, 'receiver', rv_pk)

			-- Spawn arg_0 eval next. Return; walker recurses.
			spawn_eval_child(frame, envelope.args[1])
			return
		end

		-- Phase 2: receiver is in the bucket; arg_0 not yet.
		if arg_0_pk == nil then
			if rv_pk == nil then
				-- Resume after an arg_0 eval that produced no rv (halted
				-- and restarted without a value). Respawn arg_0 eval.
				spawn_eval_child(frame, envelope.args[1])
				return
			end

			-- Arg_0 eval reaped with a value. Move rv into `arg_0`.
			data:upsert_ref(bucket_pk, 'arg_0', rv_pk)
			arg_0_pk = rv_pk
		end

		-- Phase 3: both operands in place. Compute.
		local receiver_val = data:get_scalar_number(receiver_pk)
		local arg_0_val    = data:get_scalar_number(arg_0_pk)

		if receiver_val == nil then
			error("plus_non_numeric_receiver: cannot add — receiver's scalar is not a number")
		end

		if arg_0_val == nil then
			error("plus_non_numeric_arg_0: cannot add — arg_0's scalar is not a number")
		end

		local result_pk = data:add_scalar(receiver_val + arg_0_val, frame.owner_role)

		data:upsert_ref(bucket_pk, 'rv', result_pk)
		data:mark_frame_gc(frame.object_pk)
	end)

	if not ok then
		db:exec('rollback to savepoint plus_handle;')
		db:exec('release savepoint plus_handle;')
		error(err, 0)
	end

	assert(db:exec('release savepoint plus_handle;') == 0, db:errmsg())

	return true
end


return Plus
