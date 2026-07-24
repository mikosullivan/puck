--[[
{
	"module":  "normalize",
	"role":    "full CaspianJ -> norm CaspianJ. Drops comment atoms; strips `base` (number-notation) and `dq` (string-quote-form) flags from value atoms; desugars `{op: '|', left, right}` pipe operators to their equivalent nested call shape; preserves line-number annotations everywhere. Bareword-command atoms (`{bwc: name}`) pass through unchanged in V1 — resolution comes later.",
	"exports": {
		"normalize": "CaspianJ (Lua table) -> CaspianJ (Lua table) — norm variant. Input is not mutated; output is a fresh table."
	}
}
]]

local M = {}

local normalize_atom
local desugar_pipe

--[[
{
	"in":  "left (already-normalized value-atom), right (yet-to-be-normalized RHS call atom)",
	"out": "the desugared call array — LHS becomes first positional arg for bareword-amp and dot-method calls; LHS becomes the receiver for receiver-only `.method` form",
	"raises": "when the RHS shape isn't recognized as a callable"
}
]]
desugar_pipe = function(left, right)
	if type(right) ~= "table" then
		error("normalize: pipe RHS must be a call — got " .. type(right))
	end

	-- Receiver-only form on the RHS: shape `{method: name, args?, line?}` —
	-- LHS becomes the receiver. `.name` (no parens, no args) produces the same
	-- `{method: name}` atom and desugars to a two-element attribute access.
	if right.method ~= nil and right[1] == nil then
		local out = {left, right.method}

		if right.args then
			local envelope = {args = {}}

			for _, a in ipairs(right.args) do
				table.insert(envelope.args, normalize_atom(a))
			end

			if right.line then envelope.line = right.line end
			table.insert(out, envelope)
		end

		return out
	end

	-- Bareword-callable call: `[{amp: name}, args...]` or `[{bwc: name}, args...]`
	-- — piped value slots in between the callable and any pre-existing args.
	-- Same rule for amp and bwc since both occupy the "callable at position 1"
	-- slot in a call array.
	if type(right[1]) == "table"
			and (right[1].amp ~= nil or right[1].bwc ~= nil) then
		local out = {normalize_atom(right[1]), left}

		for i = 2, #right do
			table.insert(out, normalize_atom(right[i]))
		end

		return out
	end

	-- Dot-method call: `[recv, "method", envelope?]` — piped value becomes the
	-- first positional arg. Existing envelope args shift right; no envelope
	-- means we synthesize one.
	if type(right[1]) == "table" and type(right[2]) == "string" then
		local out = {normalize_atom(right[1]), right[2]}
		local env = right[3]

		if env then
			local new_args = {left}

			for _, a in ipairs(env.args or {}) do
				table.insert(new_args, normalize_atom(a))
			end

			local new_env = {args = new_args}

			if env.line then new_env.line = env.line end
			table.insert(out, new_env)

		else
			table.insert(out, {args = {left}})
		end

		return out
	end

	error("normalize: unhandled pipe RHS shape")
end

--[[
{
	"in":  "any CaspianJ value — atom (object), row (array), scalar",
	"out": "the normalized value; comment single-object atoms return `nil` so parent lists filter them out; scalars pass through"
}
]]
normalize_atom = function(v)
	if type(v) ~= "table" then
		return v
	end

	-- Comment single-object atom — drop by returning nil. Parent lists filter.
	if v.comment ~= nil then
		return nil
	end

	-- `documentation` / `vibecode` BWC statement rows — parse-time metadata
	-- with no runtime effect. Same drop rule as comments: return nil so the
	-- parent list filters them out entirely (row disappears; no empty-array
	-- placeholder). Detects the statement-row shape `[{bwc: "documentation"},
	-- ...]` and `[{bwc: "vibecode"}, ...]`. Recurses into all body lists,
	-- so a `documentation <<EOF ... EOF` inside a class body also drops.
	if #v > 0 and type(v[1]) == "table"
			and (v[1].bwc == "documentation" or v[1].bwc == "vibecode") then
		return nil
	end

	-- Pipe operator — desugar to nested call. Both `|` and `|&` (null-safe)
	-- desugar to the same call shape; the null-safe distinction is a runtime
	-- concern that norm doesn't statically resolve here (spec says once you
	-- enter a `|&` chain, subsequent pipes stay null-safe — that's runtime).
	if (v.op == "|" or v.op == "|&") and v.left ~= nil and v.right ~= nil then
		return desugar_pipe(normalize_atom(v.left), v.right)
	end

	-- Array-shaped (statement row, method-call row, body list): recurse and
	-- filter nils (dropped comment atoms).
	if #v > 0 then
		local out = {}

		for _, elem in ipairs(v) do
			local n = normalize_atom(elem)

			if n ~= nil then
				table.insert(out, n)
			end
		end

		return out
	end

	-- Object-shaped: recurse into fields, drop cosmetic flags.
	local out = {}

	for k, val in pairs(v) do
		if k ~= "base" and k ~= "dq" then
			out[k] = normalize_atom(val)
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
