--[[
{
	"module":  "normalize",
	"role":    "full CaspianJ -> norm CaspianJ. Rewrites the transpiler's self-documenting form into the compact shape the engine walks: statement-prefix collapse (`[scope, setvar, ...]` -> `[{in: 'as'}, ...]`, function-call rows -> `[{in: 'fc'}, ...]`), single call-atom shape `{fn, rc, a?, kw?, blocks?}` for amp / dot-method / binop calls, compact key rewrites (line -> l, value -> v, body -> bd, args -> a, params -> pm, closure -> cl, fetch -> ft, array -> ar, varobj -> vo, begin_end -> be), drops comment atoms, documentation / vibecode BWC rows, cosmetic `base` / `dq` flags, and trailing sole-`line` statement-position line metas. Pipe operators (`{op: '|'}` / `{op: '|&'}`) desugar to nested calls first; general binops (`{op: '+'}` etc.) rewrite to a two-element call row. Bareword-command atoms (`{bwc: name}`) pass through unchanged in V1.",
	"exports": {
		"normalize": "CaspianJ (Lua table) -> CaspianJ (Lua table) — norm variant. Input is not mutated; output is a fresh table."
	}
}
]]

local M = {}

local normalize_atom
local desugar_pipe

-- Compact-key rename map: full atom key -> norm atom key. Applied inside
-- object atoms by normalize_atom's generic-object branch. Structural keys
-- (`var`, `hash`, `kw`, `blocks`, `at`, `sys`, `fn`, `rc`, `pattern`,
-- `flags`, `rx`, `cond`, `meta`, `bwc`, ...) stay as-is because they're
-- already terse or too structurally load-bearing to rename.
local KEY_MAP = {
	line      = "l",
	value     = "v",
	body      = "bd",
	args      = "a",
	params    = "pm",
	closure   = "cl",
	fetch     = "ft",
	array     = "ar",
	varobj    = "vo",
	begin_end = "be",
	splat     = "sp",
	receiver  = "rc",
	["function"] = "fn",
}

-- An object atom is considered a "line meta" (statement-level line annotation
-- with no runtime effect) when its sole key is `line`. Kwargs / envelopes /
-- other atoms may also carry a `line` field but always have additional keys.
local function is_line_meta(v)
	if type(v) ~= "table" or v.line == nil then
		return false
	end

	for k in pairs(v) do
		if k ~= "line" then
			return false
		end
	end

	return true
end

-- Drop `documentation` / `vibecode` bwc row? (parse-time metadata, no runtime
-- effect — same drop rule as comments).
local function is_dropped_bwc_row(v)
	return type(v) == "table" and #v > 0 and type(v[1]) == "table"
			and (v[1].bwc == "documentation" or v[1].bwc == "vibecode")
end

-- Envelope atom carrying `args` and/or `kw` (call-args envelope).
-- Detected by having `args` or `kw` key, no positional [1], and no
-- competing structural keys.
local function is_envelope_atom(a)
	if type(a) ~= "table" or a[1] ~= nil then return false end
	return a.args ~= nil or a.kw ~= nil
end

-- Trailing `{blocks: [...]}` atom.
local function is_blocks_atom(a)
	return type(a) == "table" and a[1] == nil and a.blocks ~= nil
end

-- Recurse through a value that will be embedded inside a norm structure.
-- Distinct from normalize_atom in one respect: sub-values that would
-- normalize to `nil` (comments etc.) are turned into nil here too, so
-- callers can guard against them.
local function norm_sub(v)
	return normalize_atom(v)
end

-- Recurse through the elements of a `blocks: [...]` list, renaming inner
-- keys (`body` -> `bd`, `params` -> `pm`) via normalize_atom on each entry.
local function normalize_blocks(blocks)
	local out = {}

	for _, b in ipairs(blocks) do
		local n = normalize_atom(b)

		if n ~= nil then
			table.insert(out, n)
		end
	end

	return out
end

-- Reshape a call row (amp-call `[{amp: X}, ...]` or dot-method
-- `[recv, "method", envelope?, {line}?]` or a `{blocks: [...]}` trailing
-- atom variant) into the norm call form:
--
--   [{in: "fc"}, {fn: METHOD, rc: RECV, a?, kw?, blocks?, l?}]
--
-- `fn`   — method name string. `"call"` for amp-calls (both `&name` and
--          `&(expr)` route through `.call`).
-- `rc`   — receiver value. For amp-calls: `{var: X, l: N}` when the amp
--          target is a bareword; the target atom itself for `&(EXPR)`.
--          For dot-method: the (recursively normalized) recv.
-- `a`    — positional args, present iff non-empty.
-- `kw`   — kwargs list, present iff a `{kw: [...]}` envelope atom was seen.
-- `blocks` — closure list, present iff a `{blocks: [...]}` envelope was seen.
-- `l`    — line of the call site, from a sole-line meta between the method
--          name and any envelope atoms, if present.
local function collapse_call_row(v, fn, recv)
	local positionals = {}
	local kw_val
	local blocks_val

	for i = 3, #v do
		local atom = v[i]

		if is_envelope_atom(atom) then
			-- Envelope atom `{args?, kw?, line?}` — extract fields into
			-- the call. args become positional list; kw entries become the
			-- kw list. `line` on the envelope is a call-site annotation
			-- that norm drops.
			if atom.args then
				for _, a in ipairs(atom.args) do
					local n = norm_sub(a)
					if n ~= nil then table.insert(positionals, n) end
				end
			end

			if atom.kw then
				local nkw = {}
				for _, entry in ipairs(atom.kw) do
					table.insert(nkw, norm_sub(entry))
				end
				kw_val = nkw
			end

		elseif is_blocks_atom(atom) then
			blocks_val = normalize_blocks(atom.blocks)

		elseif is_line_meta(atom) then
			-- Sole-line metas on call rows drop entirely — line info lives
			-- on the receiver and arg atoms, not repeated at call level.

		else
			local n = norm_sub(atom)
			if n ~= nil then
				table.insert(positionals, n)
			end
		end
	end

	local call = {fn = fn, rc = recv}

	if #positionals > 0 then call.a = positionals end
	if kw_val ~= nil then call.kw = kw_val end
	if blocks_val ~= nil then call.blocks = blocks_val end

	return {{["in"] = "fc"}, call}
end

--[[
{
	"in":  "left (already-normalized), right (yet-to-be-normalized RHS call atom)",
	"out": "the desugared call array — LHS prepends as first positional arg of the RHS call",
	"raises": "when the RHS shape isn't recognized as a callable"
}
]]
desugar_pipe = function(left, right)
	if type(right) ~= "table" then
		error("normalize: pipe RHS must be a call — got " .. type(right))
	end

	-- Dot-method call atom `{op: ".", left: recv, right: method, args?, kw?,
	-- blocks?}`. Piped LHS becomes the first positional arg; existing args
	-- shift right. Then re-normalize through the standard `.`-op handler.
	if right.op == "." and right.left ~= nil and right.right ~= nil then
		local new_args = {left}

		for _, a in ipairs(right.args or {}) do
			table.insert(new_args, a)
		end

		local rebuilt = {op = ".", left = right.left, right = right.right,
			args = new_args}

		if right.kw ~= nil then rebuilt.kw = right.kw end
		if right.blocks ~= nil then rebuilt.blocks = right.blocks end
		if right.line ~= nil then rebuilt.line = right.line end

		return normalize_atom(rebuilt)
	end

	-- Bareword-callable: `[{amp: name}, args...]` or `[{bwc: name}, args...]`
	-- Piped value slots between the callable and any pre-existing args.
	if type(right[1]) == "table"
			and (right[1].amp ~= nil or right[1].bwc ~= nil) then
		local out = {right[1], left}

		for i = 2, #right do
			table.insert(out, right[i])
		end

		return normalize_atom(out)
	end

	error("normalize: unhandled pipe RHS shape")
end

--[[
{
	"in":  "any CaspianJ value — atom (object), row (array), scalar",
	"out": "the normalized value; comment single-object atoms and dropped-BWC rows return nil so parent lists filter them out; scalars pass through"
}
]]
normalize_atom = function(v)
	if type(v) ~= "table" then
		return v
	end

	-- JSON null sentinel (dkjson.null): empty table with a metatable.
	-- Pass through unchanged — recursing would rebuild a plain `{}` and
	-- lose the sentinel identity that round-trips to JSON `null`.
	if next(v) == nil and getmetatable(v) ~= nil then
		return v
	end

	-- Comment single-object atom — drop.
	if v.comment ~= nil then
		return nil
	end

	-- `documentation` / `vibecode` BWC statement row — drop.
	if is_dropped_bwc_row(v) then
		return nil
	end

	-- Row-shaped (positional [1] present) — check for statement / call
	-- shapes before falling through to generic-array recursion.
	if #v > 0 then
		-- Amp-call row: `[{amp: X}, ...args..., {kw:...}?, {blocks:...}?, {line:N}?]`
		if type(v[1]) == "table" and v[1].amp ~= nil then
			local amp = v[1]
			local recv

			if type(amp.amp) == "string" then
				recv = {var = amp.amp}
				if amp.line ~= nil then recv.l = amp.line end
			else
				recv = norm_sub(amp.amp)
			end

			-- Reuse collapse_call_row by pretending pos [2] is the method
			-- name — write a shim row [recv, "call", ...rest_of_v...].
			local shim = {recv, "call"}
			for i = 2, #v do
				table.insert(shim, v[i])
			end

			return collapse_call_row(shim, "call", recv)
		end

		-- Statement prefix collapse — setvar / setvar_op / setat.
		if v[1] == "scope" then
			if v[2] == "setvar" and type(v[3]) == "string" then
				-- [scope, setvar, name, RHS, ...trailing metas]. Keep a
				-- trailing sole-line meta iff the RHS's interior mentions
				-- a different line (multi-line RHS like `$x = begin ...
				-- end`); drop it for single-line RHS.
				local rhs = norm_sub(v[4])
				local out = {{["in"] = "as"}, v[3], rhs}
				local trailing = v[#v]

				if #v >= 5 and is_line_meta(trailing) then
					local tline = trailing.line
					local saw_other = false

					local function scan(x)
						if saw_other then return end
						if type(x) ~= "table" then return end
						if type(x.line) == "number" and x.line ~= tline then
							saw_other = true
							return
						end
						for _, sub in pairs(x) do scan(sub) end
					end

					scan(v[4])

					if saw_other then
						table.insert(out, {["l"] = tline})
					end
				end

				return out
			end

			if v[2] == "setvar_op" and type(v[3]) == "string"
					and type(v[4]) == "string" then
				-- [scope, setvar_op, OP, name, RHS, ...trailing metas]
				-- Desugars to `name = OP(name, RHS)`.
				local op = v[3]
				local name = v[4]
				local rhs = norm_sub(v[5])
				local call = {
					fn = op,
					rc = {var = name},
					a = {rhs},
				}
				return {
					{["in"] = "as"}, name,
					{{["in"] = "fc"}, call},
				}
			end

			if v[2] == "setat" and type(v[3]) == "string" then
				-- [scope, setat, name, RHS, ...trailing metas]. `@name = X`
				-- is sugar for `%bucket[name] = X`; norm rewrites to the
				-- corresponding `[]=` call on the sys bucket.
				local name = v[3]
				local rhs = norm_sub(v[4])
				local line

				if type(v[4]) == "table" and type(v[4].line) == "number" then
					line = v[4].line
				elseif is_line_meta(v[#v]) then
					line = v[#v].line
				end

				local name_atom = {v = name}
				if line then name_atom.l = line end

				return {
					{["in"] = "fc"},
					{
						fn = "[]=",
						rc = {sys = "bucket"},
						a = {name_atom, rhs},
					},
				}
			end

			-- if / elsif / else collapse from the transpiler's
			-- `["scope", "if_end", {branches: [{cond, body}, ...]}, {line}?]`
			-- into the spec's `[{if: {conditions: [{test, action}], else}}, {l}?]`
			-- shape (caspianj § If). Each branch with a non-null `cond` becomes
			-- a `{test, action}` entry in `conditions`; the null-cond branch
			-- (at most one, the trailing else clause) becomes the top-level
			-- `else` field, omitted when absent. Each branch's body is a
			-- closure envelope in the transpiler output; we unwrap and use
			-- the statement list directly as `action` / `else` — the spec's
			-- shape is a plain body, not a closure.
			--
			-- Unless flows through here after unless_end's cond-negation
			-- rewrite below, so both if and unless emit the same shape.
			-- Matches ternary's `{if: {conditions, else}}` output — one atom
			-- for all three source forms.
			if v[2] == "if_end" then
				local wrapper = v[3]
				if type(wrapper) == "table" and type(wrapper.branches) == "table" then
					local conditions = {}
					local else_stmts = nil

					for _, br in ipairs(wrapper.branches) do
						local action_stmts = {}
						if type(br.body) == "table"
								and type(br.body.closure) == "table"
								and type(br.body.closure.body) == "table" then
							for _, s in ipairs(br.body.closure.body) do
								table.insert(action_stmts, norm_sub(s))
							end
						end

						-- br.cond is `nil` (Lua-level nil) or the dkjson.null
						-- sentinel (empty table with metatable) for the else
						-- branch. Both mean "no condition — this is the else."
						local is_else = br.cond == nil
								or (type(br.cond) == "table"
									and next(br.cond) == nil
									and getmetatable(br.cond) ~= nil)

						if is_else then
							else_stmts = action_stmts
						else
							table.insert(conditions, {
								test = norm_sub(br.cond),
								action = action_stmts,
							})
						end
					end

					local if_atom = {conditions = conditions}
					if else_stmts ~= nil then
						if_atom["else"] = else_stmts
					end

					local out = {{["if"] = if_atom}}

					-- Preserve trailing line meta if present (multi-line if
					-- statements carry it; the rewrite keeps it on the outer
					-- row for stack-frame reporting).
					local trailing = v[#v]
					if #v >= 4 and is_line_meta(trailing) then
						table.insert(out, {["l"] = trailing.line})
					end

					return out
				end
			end

			-- unless / until desugar to negated-condition if / while.
			if v[2] == "unless_end" then
				local rewritten = {"scope", "if_end"}
				for i = 3, #v do
					table.insert(rewritten, v[i])
				end
				-- Wrap each branch's `cond` with `!`. Branches live at
				-- position [3] under `.branches`. Fresh table so we
				-- don't mutate the input.
				if type(rewritten[3]) == "table" and rewritten[3].branches then
					local new_branches = {}
					for _, br in ipairs(rewritten[3].branches) do
						local nb = {}
						for k, val in pairs(br) do nb[k] = val end
						if nb.cond ~= nil then
							nb.cond = {["op"] = "!", operand = nb.cond}
						end
						table.insert(new_branches, nb)
					end
					local new_head = {}
					for k, val in pairs(rewritten[3]) do new_head[k] = val end
					new_head.branches = new_branches
					rewritten[3] = new_head
				end
				return normalize_atom(rewritten)
			end

			if v[2] == "until_end" then
				local rewritten = {"scope", "while_end"}
				local cond = v[3]
				table.insert(rewritten, {["op"] = "!", operand = cond})
				for i = 4, #v do
					table.insert(rewritten, v[i])
				end
				return normalize_atom(rewritten)
			end
		end

		-- Ternary atom `{op: "?:", cond, then, else, line}` — the top level
		-- of the row isn't itself the ternary; it's the enclosing statement.
		-- The ternary lives as an object atom. Handled in the object-atom
		-- branch below.

		-- Dot-method call row: `[recv, method, envelope?, ...]`. Method
		-- name is either a bareword string (static dispatch: `$obj.foo`)
		-- or a value atom (dynamic dispatch: `$obj.$fname` -> position [2]
		-- is `{var: "fname"}`). Both fold into the same `{in: "fc"}` call
		-- shape with `fn` carrying the method name / atom.
		--
		-- Excludes param-list arrays. A `params: [...]` field can contain
		-- an atom-string-atom sequence (e.g. `[{name: "x"}, "config",
		-- {name: "y"}]` for `(@x, $config, @y)`); the middle bare-string
		-- param is not a method name. Param-spec atoms have a `name` key
		-- and no receiver-shaped keys, so v[1] being one signals we're
		-- inside a param list, not a call row.
		local function is_param_spec_atom(a)
			if type(a) ~= "table" or a[1] ~= nil or a.name == nil then
				return false
			end
			for k in pairs(a) do
				if k ~= "name" and k ~= "meta" and k ~= "sp"
						and k ~= "splat" and k ~= "kwsplat" then
					return false
				end
			end
			return true
		end

		if type(v[1]) == "table" and type(v[2]) == "string"
				and not is_param_spec_atom(v[1]) then
			local recv = norm_sub(v[1])
			return collapse_call_row(v, v[2], recv)
		end


		-- Generic array (statement row that isn't call- or prefix-collapsable,
		-- body list, etc.): recurse and filter nils.
		--
		-- Rows peel a trailing sole-line meta when the row's interior only
		-- ever mentions that same line — single-line construct, the meta
		-- duplicates info already recorded on interior atoms. Multi-line
		-- constructs keep the trailing meta because it points at the
		-- `end` / final source line, distinct from the interior.
		local last = #v

		if last >= 2 and is_line_meta(v[last]) then
			local trailing_line = v[last].line
			local saw_different_line = false

			local function scan(x)
				if saw_different_line then return end
				if type(x) ~= "table" then return end
				if type(x.line) == "number" and x.line ~= trailing_line then
					saw_different_line = true
					return
				end
				for _, sub in pairs(x) do scan(sub) end
			end

			for i = 2, last - 1 do
				scan(v[i])

				if saw_different_line then break end
			end

			if not saw_different_line then
				last = last - 1
			end
		end

		local out = {}

		for i = 1, last do
			local n = normalize_atom(v[i])

			if n ~= nil then
				table.insert(out, n)
			end
		end

		return out
	end

	-- Object atom.

	-- At-sigil atom `{at: NAME, line?: N}` — `@name` is sugar for
	-- `%bucket['name']`; norm rewrites to the corresponding `[]` (get)
	-- call on the sys bucket. Fires for read positions; the write case
	-- (`@name = X`) is handled at the row-level setat collapse.
	if v.at ~= nil and v[1] == nil then
		local name_atom = {v = v.at}
		if type(v.line) == "number" then name_atom.l = v.line end

		return {
			{["in"] = "fc"},
			{
				fn = "[]",
				rc = {sys = "bucket"},
				a = {name_atom},
			},
		}
	end

	-- Pipe operator — desugar to nested call, then re-normalize so the
	-- result flows through the call-row reshape.
	if (v.op == "|" or v.op == "|&") and v.left ~= nil and v.right ~= nil then
		return desugar_pipe(norm_sub(v.left), v.right)
	end

	-- Dot-operator atom `{op: ".", left, right, args?, kw?, blocks?, line?}` —
	-- the CaspianJ shape of every dot-method call. Rewrites to
	-- `[{in: "fc"}, {fn, rc: NORM(left), a?, kw?, blocks?}]` — the standard
	-- norm call shape. `fn` is the bare string method name for bareword and
	-- string-literal forms (`$foo.bar` and `$foo.'bar'` both collapse to
	-- `fn: "bar"`); an atom for dynamic dispatch (`$foo.$var` -> `fn: {var:
	-- "var"}`). The distinction between the syntactic forms disappears at
	-- norm time.
	if v.op == "." and v.left ~= nil and v.right ~= nil then
		local fn
		if type(v.right) == "string" then
			fn = v.right
		elseif type(v.right) == "table" and v.right[1] == nil
				and v.right.v ~= nil then
			fn = v.right.v
		else
			fn = norm_sub(v.right)
		end

		local call = {fn = fn, rc = norm_sub(v.left)}

		if v.args then
			local a = {}
			for _, arg in ipairs(v.args) do
				local n = norm_sub(arg)
				if n ~= nil then table.insert(a, n) end
			end
			if #a > 0 then call.a = a end
		end

		if v.kw then
			local kw = {}
			for _, entry in ipairs(v.kw) do
				table.insert(kw, norm_sub(entry))
			end
			call.kw = kw
		end

		if v.blocks then
			call.blocks = normalize_blocks(v.blocks)
		end

		return {{["in"] = "fc"}, call}
	end

	-- Ternary atom `{op: "?:", cond, then, else, line?}` → rewrites to
	-- an `{if: {conditions: [{test, action}], else: [...]}}` shape. Puts
	-- ternary and if / elsif / else on one runtime construct.
	if v.op == "?:" and v.cond ~= nil and v["then"] ~= nil and v["else"] ~= nil then
		return {
			["if"] = {
				conditions = {
					{
						test   = norm_sub(v.cond),
						action = {norm_sub(v["then"])},
					},
				},
				["else"] = {norm_sub(v["else"])},
			},
		}
	end

	-- Short-circuit binop atoms (`and`, `or`, `&&`, `||`) stay in
	-- `{op, left, right}` shape — they need runtime short-circuit dispatch
	-- and can't be modeled as ordinary calls. Fall through to generic
	-- object recursion so keys inside `left` / `right` still get renamed.
	if (v.op == "and" or v.op == "or" or v.op == "&&" or v.op == "||")
			and v.left ~= nil and v.right ~= nil then
		-- fall through
	elseif v.op ~= nil and v.left ~= nil and v.right ~= nil and v.op ~= "." then
		-- General binop atom — rewrite as a call row. `1 + 2` becomes
		-- `[{in: "fc"}, {fn: "+", rc: NORM(left), a: [NORM(right)]}]`. Line
		-- info on the binop atom itself is dropped; the operands keep their
		-- own `l:` fields.
		local call = {
			fn = v.op,
			rc = norm_sub(v.left),
			a = {norm_sub(v.right)},
		}
		return {{["in"] = "fc"}, call}
	end

	-- Generic object atom: recurse into fields, drop cosmetic flags, rename
	-- keys per KEY_MAP.
	local out = {}

	for k, val in pairs(v) do
		if k ~= "base" and k ~= "dq" then
			local new_key = KEY_MAP[k] or k
			out[new_key] = normalize_atom(val)
		end
	end

	return out
end

--[[
{
	"in":  "full CaspianJ (Lua table, typically a list of statement rows)",
	"out": "norm CaspianJ (fresh Lua table)"
}
]]
function M.normalize(caspj)
	if type(caspj) ~= "table" then
		return caspj
	end

	local out = {}

	for _, stmt in ipairs(caspj) do
		local n = normalize_atom(stmt)

		if n ~= nil then
			table.insert(out, n)
		end
	end

	return out
end

return M
