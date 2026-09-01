--[[
{
	"module":  "caspj-caspm",
	"role":    "CaspJ -> CaspM. Rewrites the transpiler's self-documenting form into the compact shape the engine walks: EVERY command collapses to the method_call shape `[{cmd: 'mc'}, {fn, rcvr, args?, kw?, blocks?, syn?}]`. Assignment is a method_call with `fn: '='` and `rcvr: {sys: 'frame'}` (implicit receiver — the current frame); dot-method calls carry the source-level receiver; binops are `fn: OP, rcvr: left, args: [right]`; unary ops are `fn: OP, rcvr: operand`. The envelope's `syn: true` marker records that the mc came from syntactic sugar (operator forms, setvar, setat, amp / bwc, @-read) rather than a directly-written `.method()` call — readers use it for source-aware error messages and pretty-printing. Bareword-command atoms (`{bwc: name}`) collapse to `{fn:'call', rcvr:{var:name}, syn:true}`. Amp atoms (`{amp: X}`) do too; when the amp target is a dot chain, the sigil pushes down to the leftmost leaf so `&foo.bar` transpiles as `(&foo).bar`. Compact key rewrites (line -> l, value -> v, body -> bd, params -> pm, closure -> cl, fetch -> ft, array -> ar, varobj -> vo, begin_end -> be). Drops comment atoms, documentation / vibecode BWC rows, cosmetic `base` / `dq` flags, and trailing sole-`line` statement-position line metas. Pipe operators (`{op: '|'}` / `{op: '|&'}`) desugar to nested calls first.",
	"exports": {
		"transpile": "CaspM (Lua table) -> CaspM (Lua table) — CaspM variant. Input is not mutated; output is a fresh table."
	}
}
]]

--[[
# `transpile`

Second half of the CaspM pipeline: takes the self-documenting
CaspJ form the transpiler emits and rewrites it into the compact
CaspM form the engine walks. The two forms carry the same
information — CaspM is what you get after stripping every field the
runtime doesn't actually consume and collapsing the wordy
statement / call shapes into the terse ones dispatch uses.

The rewrite is a single recursive `transpile_atom` pass. Every
CaspJ value (row, atom, scalar) enters that function; it dispatches
on shape (row vs. object atom vs. scalar), applies the appropriate
rewrite, and recurses into any sub-values. `M.transpile` is a thin
wrapper that walks a full CaspJ program (a list of statement rows)
and filters out the `nil`s that transpile_atom returns for
drop-me values.

**Rewrites in play.**

- **Every command is a method_call.** The engine walks one row
  shape: `[{cmd: 'mc'}, {fn, rcvr, args?, kw?, blocks?, l?}]`.
  Assignment (`$x = 1`) becomes `[{cmd: 'mc'}, {fn: '=', rcvr: {sys:
  'frame'}, args: ['x', {v: 1}]}]` — the receiver is the current frame,
  named via the `sys` system-reference atom, resolved to
  `engine.current_frame_pk` at dispatch time. Amp-call rows,
  dot-method rows, and binops all collapse to the same shape.
  Sugared forms (`unless_end`, `until_end`, postinc,
  compound-assign, `@name`, `@name = X`) desugar to their
  standard counterparts here. Both statement-position and
  expression-position setvar produce the same method_call
  envelope — there's no "assignment as expression" vs
  "assignment as statement" distinction at the CaspM layer.
- **Compact-key rename.** `line` -> `l`, `value` -> `v`, `body` ->
  `bd`, `args` -> `a`, `params` -> `pm`, and so on (full map in
  `KEY_MAP`). Structural keys keep their names.
- **Drop cosmetic and metadata atoms.** Comment atoms, docs /
  vibecode BWC rows, `base` / `dq` flags, trailing sole-line metas
  on single-line statements — all vanish in CaspM.
- **Pipe desugaring.** `A | B` becomes a nested call with `A` as
  the first positional of `B`. `|&` (null-safe pipe) is currently
  deferred but the finder recognizes it so the shape doesn't
  regress silently.
- **Binops as calls.** `1 + 2` in full is `{op: '+', left, right}`;
  in CaspM it's a call row with `fn: '+'`, `rcvr: left`, `args: [right]`.
  Short-circuit ops (`and`, `or`, `&&`, `||`) stay in `{op, left,
  right}` shape because they need runtime short-circuit dispatch.

**Input is not mutated.** Every rewrite builds a fresh table.
Callers that want the CaspJ form after transpiling can hold onto
their original.
]]

local M = {}

local transpile_atom
local desugar_pipe

-- Compact-key rename map: CaspJ atom key -> CaspM atom key. Applied inside
-- object atoms by transpile_atom's generic-object branch. Structural keys
-- (`var`, `hash`, `kw`, `blocks`, `at`, `sys`, `fn`, `rcvr`, `pattern`,
-- `flags`, `rx`, `cond`, `meta`, `bwc`, ...) stay as-is because they're
-- already terse or too structurally load-bearing to rename.
local KEY_MAP = {
	value     = "v",
	body      = "bd",
	params    = "pm",
	closure   = "cl",
	fetch     = "ft",
	array     = "ar",
	varobj    = "vo",
	begin_end = "be",
	splat     = "sp",
	receiver  = "rcvr",
	["function"] = "fn",
}

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

-- Recurse through a value that will be embedded inside a CaspM structure.
-- Distinct from transpile_atom in one respect: sub-values that would
-- transpile to `nil` (comments etc.) are turned into nil here too, so
-- callers can guard against them.
local function transpile_sub(v)
	return transpile_atom(v)
end

-- Push an `amp` sigil down through a dot chain to the leftmost leaf.
-- The transpiler emits `&foo.bar.baz` as `{amp: {op:'.', left: {op:'.',
-- left: {bwc:'foo'}, right:'bar'}, right:'baz'}}` — amp wrapping the
-- whole chain (low-precedence parse). But `&` is a high-precedence
-- sigil binding to just the identifier it prefixes, so `&foo.bar.baz`
-- is semantically `(&foo).bar.baz`. Rewriting the dot expression to
-- move the amp inside gives us `{op:'.', left: {op:'.', left: LEAF',
-- right:'bar'}, right:'baz'}` where LEAF' is the leftmost leaf wrapped
-- as amp — which then transpiles as if the source had been `$foo.call().bar.baz`.
--
-- Leaf-collapse rule: if the leftmost leaf is `{bwc: NAME}` (itself a
-- bareword call), replace with `{amp: NAME}` (string form) rather than
-- `{amp: {bwc: NAME}}`. `bwc` and `amp` are both "call this"; wrapping
-- one in the other would produce a double-call. The string form of
-- amp resolves through the amp handler to `.call({var: NAME})` — a
-- single call, which is what the user wrote.
local function push_amp_down_through_dots(dot)
	local out = {}

	for k, val in pairs(dot) do
		out[k] = val
	end

	if type(dot.left) == "table" and dot.left.op == "."
			and dot.left.left ~= nil and dot.left.right ~= nil then
		out.left = push_amp_down_through_dots(dot.left)
	else
		-- Base case: wrap the leftmost leaf.
		local leaf = dot.left

		if type(leaf) == "table" and leaf.bwc ~= nil and leaf[1] == nil then
			out.left = {amp = leaf.bwc}
		else
			out.left = {amp = leaf}
		end
	end

	return out
end

-- Recurse through the elements of a `blocks: [...]` list, renaming inner
-- keys (`body` -> `bd`, `params` -> `pm`) via transpile_atom on each entry.
local function transpile_blocks(blocks)
	local out = {}

	for _, b in ipairs(blocks) do
		local n = transpile_atom(b)

		if n ~= nil then
			table.insert(out, n)
		end
	end

	return out
end

-- Reshape a call row (amp-call `[{amp: X}, ...]` or dot-method
-- `[recv, "method", envelope?, {line}?]` or a `{blocks: [...]}` trailing
-- atom variant) into the CaspM call form:
--
--   [{cmd: "mc"}, {fn: METHOD, rcvr: RECV, args?, kw?, blocks?, l?}]
--
-- `fn`   — method name string. `"call"` for amp-calls (both `&name` and
--          `&(expr)` route through `.call`).
-- `rcvr` — receiver value. For amp-calls: `{var: X, l: N}` when the amp
--          target is a bareword; the target atom itself for `&(EXPR)`.
--          For dot-method: the (recursively transpiled) recv.
-- `args` — positional args, present iff non-empty.
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
			-- that CaspM drops.
			if atom.args then
				for _, a in ipairs(atom.args) do
					local n = transpile_sub(a)
					if n ~= nil then table.insert(positionals, n) end
				end
			end

			if atom.kw then
				local nkw = {}
				for _, entry in ipairs(atom.kw) do
					table.insert(nkw, transpile_sub(entry))
				end
				kw_val = nkw
			end

		elseif is_blocks_atom(atom) then
			blocks_val = transpile_blocks(atom.blocks)

		else
			local n = transpile_sub(atom)
			if n ~= nil then
				table.insert(positionals, n)
			end
		end
	end

	local call = {fn = fn, rcvr = recv}

	if #positionals > 0 then call.args = positionals end
	if kw_val ~= nil then call.kw = kw_val end
	if blocks_val ~= nil then call.blocks = blocks_val end

	return {{["cmd"] = "mc"}, call}
end

--[[
{
	"in":  "left (already-transpiled), right (yet-to-be-transpiled RHS call atom)",
	"out": "the desugared call array — LHS prepends as first positional arg of the RHS call",
	"raises": "when the RHS shape isn't recognized as a callable"
}
]]
desugar_pipe = function(left, right)
	if type(right) ~= "table" then
		error("transpile: pipe RHS must be a call — got " .. type(right))
	end

	-- Dot-method call atom `{op: ".", left: recv, right: method, args?, kw?,
	-- blocks?}`. Piped LHS becomes the first positional arg; existing args
	-- shift right. Then re-transpile through the standard `.`-op handler.
	if right.op == "." and right.left ~= nil and right.right ~= nil then
		local new_args = {left}

		for _, a in ipairs(right.args or {}) do
			table.insert(new_args, a)
		end

		local rebuilt = {op = ".", left = right.left, right = right.right,
			args = new_args}

		if right.kw ~= nil then rebuilt.kw = right.kw end
		if right.blocks ~= nil then rebuilt.blocks = right.blocks end

		return transpile_atom(rebuilt)
	end

	-- Bareword-callable: `[{amp: name}, args...]` or `[{bwc: name}, args...]`
	-- Piped value slots between the callable and any pre-existing args.
	if type(right[1]) == "table"
			and (right[1].amp ~= nil or right[1].bwc ~= nil) then
		local out = {right[1], left}

		for i = 2, #right do
			table.insert(out, right[i])
		end

		return transpile_atom(out)
	end

	error("transpile: unhandled pipe RHS shape")
end

--[[
{
	"in":  "any CaspJ value — atom (object), row (array), scalar",
	"out": "the transpiled value; comment single-object atoms and dropped-BWC rows return nil so parent lists filter them out; scalars pass through"
}
]]
transpile_atom = function(v)
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

			-- `&` is a high-precedence sigil binding to its immediate
			-- operand, so `&foo.bar.baz` is semantically `(&foo).bar.baz`,
			-- not `&(foo.bar.baz)`. The transpiler emits the low-
			-- precedence CaspJ (`{amp: <whole_dot_chain>}`); push the
			-- amp down to the leftmost leaf of the dot chain and
			-- re-transpile so `&foo.bar()` and `$foo.call().bar()`
			-- produce identical CaspM.
			if type(amp.amp) == "table" and amp.amp.op == "."
					and amp.amp.left ~= nil and amp.amp.right ~= nil then
				local rewritten_row = {push_amp_down_through_dots(amp.amp)}

				for i = 2, #v do
					table.insert(rewritten_row, v[i])
				end

				return transpile_atom(rewritten_row)
			end

			local recv

			if type(amp.amp) == "string" then
				recv = {var = amp.amp}
			else
				recv = transpile_sub(amp.amp)
			end

			-- Reuse collapse_call_row by pretending pos [2] is the method
			-- name — write a shim row [recv, "call", ...rest_of_v...].
			-- Stamp `syn=true` on the resulting envelope: the user wrote
			-- `&NAME`, not a literal `.call()`; the `.call()` was added
			-- by transpilation.
			local shim = {recv, "call"}
			for i = 2, #v do
				table.insert(shim, v[i])
			end

			local mc = collapse_call_row(shim, "call", recv)
			mc[2].syn = true
			return mc
		end

		-- Bwc-call row: `[{bwc: NAME}, ...args..., {kw:...}?, {blocks:...}?, {line:N}?]`
		-- Bareword calls (`foo`, `foo 1`, `foo(1, 2)`) and amp-calls
		-- (`&foo`, `&foo()`) mean the same thing — both invoke the
		-- callable named NAME. Collapse to the same method_call shape
		-- so the engine sees one canonical form. `syn=true` because the
		-- user wrote a bareword, not `.call()`.
		--
		-- `documentation` / `vibecode` BWC rows were dropped earlier
		-- via `is_dropped_bwc_row`, so anything reaching here is a
		-- real bareword call.
		if type(v[1]) == "table" and v[1].bwc ~= nil then
			local bwc = v[1]
			local recv = {var = bwc.bwc}

			local shim = {recv, "call"}
			for i = 2, #v do
				table.insert(shim, v[i])
			end

			local mc = collapse_call_row(shim, "call", recv)
			mc[2].syn = true
			return mc
		end

		-- Statement prefix collapse — setvar / setvar_op / setat.
		if v[1] == "scope" then
			if v[2] == "setvar" and type(v[3]) == "string" then
				-- [scope, setvar, name, RHS, ...trailing metas]. Collapses
				-- to a method_call on the current frame: fn='=', rc=current
				-- frame (named via {sys: 'frame'}), args = [name, RHS].
				-- Keep a trailing sole-line meta iff the RHS's interior
				-- mentions a different line (multi-line RHS like `$x =
				-- begin ... end`); drop it for single-line RHS. `syn=true`
				-- because `$x = 1` is sugar for the mc; the user didn't
				-- write `.=('x', 1)` literally.
				local rhs = transpile_sub(v[4])
				local envelope = {
					fn = "=",
					rcvr = {sys = "frame"},
					args = {v[3], rhs},
					syn = true,
				}

				return {{["cmd"] = "mc"}, envelope}
			end

			if v[2] == "setvar_op" and type(v[3]) == "string"
					and type(v[4]) == "string" then
				-- [scope, setvar_op, OP, name, RHS, ...trailing metas]
				-- Desugars to `name = OP(name, RHS)` — an outer assignment
				-- method_call whose value slot is the inner OP method_call.
				-- Both mc rows carry `syn=true`; the outer `=` is
				-- setvar-sugar, the inner OP is binop-sugar.
				local op = v[3]
				local name = v[4]
				local rhs = transpile_sub(v[5])
				local op_call = {
					fn = op,
					rcvr = {var = name},
					args = {rhs},
					syn = true,
				}
				return {
					{["cmd"] = "mc"},
					{
						fn = "=",
						rcvr = {sys = "frame"},
						args = {name, {{["cmd"] = "mc"}, op_call}},
						syn = true,
					},
				}
			end

			if v[2] == "setat" and type(v[3]) == "string" then
				-- [scope, setat, name, RHS]. `@name = X` is sugar for
				-- `%bucket[name] = X`; CaspM rewrites to the corresponding
				-- `[]=` call on the sys bucket. `syn=true` records the
				-- setat-sugar origin.
				local name = v[3]
				local rhs = transpile_sub(v[4])

				return {
					{["cmd"] = "mc"},
					{
						fn = "[]=",
						rcvr = {sys = "bucket"},
						args = {{v = name}, rhs},
						syn = true,
					},
				}
			end

			-- if / elsif / else collapse from the transpiler's
			-- `["scope", "if_end", {branches: [{cond, body}, ...]}, {line}?]`
			-- into `[{if: {conditions: [{test, action}], else}}, {l}?]`.
			-- Each branch with a non-null `cond` becomes a `{test, action}`
			-- entry in `conditions`; the null-cond branch (at most one, the
			-- trailing else clause) becomes the top-level `else` field,
			-- omitted when absent.
			--
			-- `action` and `else` carry the branch's closure envelope
			-- `{cl: {pm, bd}}` (params + body). Blocks are closures — at
			-- execution time the engine invokes the closure with a fresh
			-- frame whose `lexical_parent` is the enclosing frame, so
			-- variables assigned inside the block don't leak into the
			-- enclosing scope. Structural closure envelope stays intact;
			-- transpile just recurses inside it.
			--
			-- Unless flows through here after unless_end's cond-negation
			-- rewrite below, so both if and unless emit the same shape.
			if v[2] == "if_end" then
				local wrapper = v[3]
				if type(wrapper) == "table" and type(wrapper.branches) == "table" then
					local conditions = {}
					local else_action = nil

					for _, br in ipairs(wrapper.branches) do
						-- br.body is a `{closure: {params, body}}` envelope.
						-- Transpile it (produces `{cl: {pm, bd}}` after
						-- key-shortening) and use the whole envelope as the
						-- action — engine treats it as a callable.
						local action_atom = transpile_sub(br.body)

						-- br.cond is `nil` (Lua-level nil) or the dkjson.null
						-- sentinel (empty table with metatable) for the else
						-- branch. Both mean "no condition — this is the else."
						local is_else = br.cond == nil
								or (type(br.cond) == "table"
									and next(br.cond) == nil
									and getmetatable(br.cond) ~= nil)

						if is_else then
							else_action = action_atom
						else
							table.insert(conditions, {
								test = transpile_sub(br.cond),
								action = action_atom,
							})
						end
					end

					local if_atom = {conditions = conditions}
					if else_action ~= nil then
						if_atom["else"] = else_action
					end

					return {{["if"] = if_atom}}
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
				return transpile_atom(rewritten)
			end

			if v[2] == "until_end" then
				local rewritten = {"scope", "while_end"}
				local cond = v[3]
				table.insert(rewritten, {["op"] = "!", operand = cond})
				for i = 4, #v do
					table.insert(rewritten, v[i])
				end
				return transpile_atom(rewritten)
			end
		end

		-- Ternary atom `{op: "?:", cond, then, else, line}` — the top level
		-- of the row isn't itself the ternary; it's the enclosing statement.
		-- The ternary lives as an object atom. Handled in the object-atom
		-- branch below.

		-- Dot-method call row: `[recv, method, envelope?, ...]`. Method
		-- name is either a bareword string (static dispatch: `$obj.foo`)
		-- or a value atom (dynamic dispatch: `$obj.$fname` -> position [2]
		-- is `{var: "fname"}`). Both fold into the same `{cmd: "mc"}` call
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
			local recv = transpile_sub(v[1])
			return collapse_call_row(v, v[2], recv)
		end


		-- Generic array (statement row that isn't call- or prefix-collapsable,
		-- body list, etc.): recurse and filter nils.
		local out = {}

		for i = 1, #v do
			local n = transpile_atom(v[i])

			if n ~= nil then
				table.insert(out, n)
			end
		end

		return out
	end

	-- Object atom.

	-- At-sigil atom `{at: NAME}` — `@name` is sugar for `%bucket['name']`;
	-- CaspM rewrites to the corresponding `[]` (get) call on the sys
	-- bucket. Fires for read positions; the write case (`@name = X`)
	-- is handled at the row-level setat collapse. `syn=true` on the
	-- envelope (@-sigil is sugar for the `[]` call).
	if v.at ~= nil and v[1] == nil then
		return {
			{["cmd"] = "mc"},
			{
				fn = "[]",
				rcvr = {sys = "bucket"},
				args = {{v = v.at}},
				syn = true,
			},
		}
	end

	-- Object-atom amp: `{amp: X}` in an operand position (not as a row
	-- head). Same "call this" semantics as the amp-call row — collapse
	-- to `[{cmd:'mc'}, {fn:'call', rcvr: <resolved>}]`. `syn=true`
	-- records the amp-sigil sugar.
	--
	-- When the target is a dot expression, push amp down to the leftmost
	-- leaf and let the dot handler take it from there (same rule as the
	-- amp-row handler, needed here because a pushed-down amp can end up
	-- as an operand atom during recursive transpilation).
	if v.amp ~= nil and v[1] == nil then
		if type(v.amp) == "table" and v.amp.op == "."
				and v.amp.left ~= nil and v.amp.right ~= nil then
			return transpile_atom(push_amp_down_through_dots(v.amp))
		end

		local recv

		if type(v.amp) == "string" then
			recv = {var = v.amp}
		else
			recv = transpile_sub(v.amp)
		end

		return {{["cmd"] = "mc"}, {fn = "call", rcvr = recv, syn = true}}
	end

	-- Object-atom bwc: `{bwc: NAME}` in an operand position (not as a
	-- row head). Same "call NAME" semantics as the bwc-call row —
	-- collapse to `[{cmd:'mc'}, {fn:'call', rcvr:{var: NAME}}]`.
	-- `syn=true` records the bareword-sugar origin.
	if v.bwc ~= nil and v[1] == nil then
		return {{["cmd"] = "mc"}, {fn = "call", rcvr = {var = v.bwc}, syn = true}}
	end

	-- Expression-position setvar `{setvar: {name, value}}` —
	-- assign-as-value, e.g. `$y = 2` inside `($y = 2) + 3`. Same
	-- collapse as statement-position setvar: method_call on the
	-- current frame with fn='=', args=[name, value]. `syn=true` — the
	-- `=` symbol is sugar, not a literal `.=(...)` call.
	if v.setvar ~= nil and v[1] == nil then
		local inner = v.setvar
		return {
			{["cmd"] = "mc"},
			{
				fn = "=",
				rcvr = {sys = "frame"},
				args = {inner.name, transpile_sub(inner.value)},
				syn = true,
			},
		}
	end

	-- Pipe operator — desugar to nested call, then re-transpile so the
	-- result flows through the call-row reshape.
	if (v.op == "|" or v.op == "|&") and v.left ~= nil and v.right ~= nil then
		return desugar_pipe(transpile_sub(v.left), v.right)
	end

	-- Dot-operator atom `{op: ".", left, right, args?, kw?, blocks?, line?}` —
	-- the CaspJ shape of every dot-method call. Rewrites to
	-- `[{cmd: "mc"}, {fn, rcvr: NORM(left), args?, kw?, blocks?}]` — the standard
	-- CaspM call shape. `fn` is the bare string method name for bareword and
	-- string-literal forms (`$foo.bar` and `$foo.'bar'` both collapse to
	-- `fn: "bar"`); an atom for dynamic dispatch (`$foo.$var` -> `fn: {var:
	-- "var"}`). The distinction between the syntactic forms disappears at
	-- CaspM time.
	if v.op == "." and v.left ~= nil and v.right ~= nil then
		local fn
		if type(v.right) == "string" then
			fn = v.right
		elseif type(v.right) == "table" and v.right[1] == nil
				and v.right.v ~= nil then
			fn = v.right.v
		else
			fn = transpile_sub(v.right)
		end

		local call = {fn = fn, rcvr = transpile_sub(v.left)}

		if v.args then
			local args = {}
			for _, arg in ipairs(v.args) do
				local n = transpile_sub(arg)
				if n ~= nil then table.insert(args, n) end
			end
			if #args > 0 then call.args = args end
		end

		if v.kw then
			local kw = {}
			for _, entry in ipairs(v.kw) do
				table.insert(kw, transpile_sub(entry))
			end
			call.kw = kw
		end

		if v.blocks then
			call.blocks = transpile_blocks(v.blocks)
		end

		return {{["cmd"] = "mc"}, call}
	end

	-- Ternary atom `{op: "?:", cond, then, else, line?}` → rewrites to
	-- an `{if: {conditions: [{test, action}], else: [...]}}` shape. Puts
	-- ternary and if / elsif / else on one runtime construct.
	if v.op == "?:" and v.cond ~= nil and v["then"] ~= nil and v["else"] ~= nil then
		return {
			["if"] = {
				conditions = {
					{
						test   = transpile_sub(v.cond),
						action = {transpile_sub(v["then"])},
					},
				},
				["else"] = {transpile_sub(v["else"])},
			},
		}
	end

	-- Binop atom `{op: OP, left, right}` — rewrite as a method_call row.
	-- Under Caspian's semantic model the only binary operator is `.`;
	-- every other operator symbol (`+`, `-`, `*`, `/`, `%`, `**`,
	-- `||`, `&&`, `and`, `or`, `==`, `<`, etc.) is a method NAME
	-- dispatched on the left operand with the right operand as the
	-- single arg. Short-circuit operators like `||` and `&&` are no
	-- different at the CaspM layer — they're methods whose Lua
	-- implementation happens to defer evaluating its arg; that laziness
	-- is the method's concern, not the engine's dispatch shape.
	-- Line info on the binop atom itself is dropped; the operands keep
	-- their own `l:` fields. The envelope's `syn = true` marker records
	-- that this mc came from syntactic sugar (an operator form), not
	-- from a user-written `.method()` call.
	if v.op ~= nil and v.left ~= nil and v.right ~= nil and v.op ~= "." then
		local call = {
			fn = v.op,
			rcvr = transpile_sub(v.left),
			args = {transpile_sub(v.right)},
			syn = true,
		}
		return {{["cmd"] = "mc"}, call}
	end

	-- Unary op atom `{op: OP, operand: X}` — rewrite as a receiver-only
	-- method_call. Same semantic model as binops: `!X` is a method call
	-- with fn `!` on receiver X, no args. `syn = true` records the
	-- syntactic origin.
	if v.op ~= nil and v.operand ~= nil
			and v.left == nil and v.right == nil then
		return {{["cmd"] = "mc"}, {fn = v.op, rcvr = transpile_sub(v.operand), syn = true}}
	end

	-- Generic object atom: recurse into fields, drop cosmetic flags, rename
	-- keys per KEY_MAP.
	local out = {}

	for k, val in pairs(v) do
		if k ~= "base" and k ~= "dq" then
			local new_key = KEY_MAP[k] or k
			out[new_key] = transpile_atom(val)
		end
	end

	return out
end

--[[
Recursively delete every `line` key from every hash in `v`, walking
through nested hashes and arrays. Called just before `M.transpile`
returns so no `line` field survives into CaspM — the CaspM shape
holds no source-line info of its own; that'll be reintroduced at the
command level in a separate sprint.

Mutates in place; the caller doesn't need the return value.
]]
local function strip_line_keys(v)
	if type(v) ~= "table" then return end

	v.line = nil

	for _, child in pairs(v) do
		strip_line_keys(child)
	end
end

--[[
{
	"in":  "CaspJ (Lua table, typically a list of statement rows)",
	"out": "CaspM (fresh Lua table)"
}
]]
function M.transpile(caspj)
	if type(caspj) ~= "table" then
		return caspj
	end

	local out = {}

	for _, stmt in ipairs(caspj) do
		local n = transpile_atom(stmt)

		if n ~= nil then
			-- Unwrap `[[{cmd:"mc"}, envelope]]` → `[{cmd:"mc"}, envelope]`.
			-- Statement rows that contain a single method_call
			-- expression (dot-method calls, binops, pipes) come out
			-- of transpile_atom's array-recursion wrapped in an extra
			-- outer array — a leftover of the source-position wrap.
			-- Setvar rows already come out unwrapped because they
			-- intercept at row level. Unwrap here so every statement
			-- row has the same shape: `[HEAD, ENVELOPE]` with no
			-- extra nesting. The walker and handlers then don't need
			-- to case-split on shape.
			if type(n) == 'table' and #n == 1
				and type(n[1]) == 'table' and #n[1] >= 1
				and type(n[1][1]) == 'table' and n[1][1].cmd == 'mc'
			then
				n = n[1]
			end

			table.insert(out, n)
		end
	end

	strip_line_keys(out)

	return out
end

return M
