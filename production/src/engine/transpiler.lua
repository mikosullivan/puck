--[[
{
	"module":  "transpiler",
	"role":    "Caspian source -> CaspianJ. Standalone module. No knowledge of the engine.",
	"exports": {
		"transpile": "(source: string, opts?: {lines: bool}) -> CaspianJ. opts.lines = true opt-in mode: every statement row gets a trailing `{line: N}` meta-atom, and every value-atom object gets a `line: N` field. Default: no line annotations.",
		"null":      "sentinel for JSON null in CaspianJ output (matches dkjson.null so test assertions align)"
	}
}
]]

--[[
# `transpiler`

First half of the CaspianJ pipeline: turns Caspian source into the
self-documenting "full" CaspJ tree that `normalize.lua` compacts
before the engine walks it. Standalone module — no knowledge of the
engine, no shared state with the runtime, no round-trip contract
beyond the CaspJ shape.

**Two-mode output.** Default `transpile(source)` emits CaspJ with
no line annotations. `transpile(source, {lines = true})` opts in to
line-annotated output: every value-atom object carries a `line`
field and every statement row picks up a trailing `{line: N}`
meta-atom. The transpiler tests all run in `{lines = true}` mode
so fixtures pin the source line each construct lands on;
the engine reads either shape.

**Pipeline shape.** Source is pre-processed line-by-line
(heredocs are extracted and replaced by placeholder tokens so the
statement parser sees single-line expressions), then walked
statement-by-statement. Each statement dispatches through the
construct table (`if_end`, `while_end`, `function` -at-statement,
etc.) or falls through to `parse_expression`, which recursively
handles literals, variable atoms, method calls, operator
expressions, block-form constructs used as values, and everything
else. Per-function JSON docstrings sit above each helper so the
in-file navigation is greppable.

**`null` sentinel.** `M.null` is exposed as `dkjson.null` so test
assertions that decode expected CaspJ from JSON compare equal to
the transpiler's outputs. Every CaspJ null the transpiler emits
uses this same sentinel.
]]

local json = require("dkjson")

local M = {}

M.null = json.null

-- Heredoc substitution state. Populated by M.transpile's pre-processor when
-- it collects a heredoc body from following lines. parse_expression consults
-- this table when it sees a placeholder token of the form
-- `%__caspian_heredoc_N__` and returns the pre-built value-atom.
local active_heredocs = nil

-- Line-annotation state. Populated by M.transpile when opts.lines is truthy.
-- include_lines: whether to attach `line = N` fields; current_line: the source
-- line of the statement currently being parsed (atoms constructed while this
-- statement is in flight inherit its line — statement-level precision, not
-- sub-expression precision, which "as practical" trades away for simplicity).
local include_lines = false
local current_line = nil

-- Stamp `line = current_line` on an object-shape atom when line-annotation is
-- on. Safe no-op on non-tables and on array-shaped tables (like method-call
-- rows [recv, method, {args}]) — those get line info via their enclosing
-- statement's trailing meta-atom. Callers wrap their `return {shape}` sites
-- with attach_line(...) so every atom emitted from parse_expression carries
-- its source line.
local function attach_line(atom)
	if include_lines and current_line and type(atom) == "table"
			and atom[1] == nil and not atom.line then
		atom.line = current_line
	end

	return atom
end

--[[ { "in": "string", "out": "string with leading/trailing whitespace removed" } ]]
local function trim(s)
	return s:gsub("^%s+", ""):gsub("%s+$", "")
end

--[[
{
	"in":  "string — a number literal in Caspian syntax (decimal, hex 0x, octal 0o, binary 0b, optional underscore separators, optional leading -)",
	"out": "(Lua number, base?) — base is 'hex' / 'oct' / 'bin' for non-decimal notation, nil for plain decimal; returns nil when the string is not a number literal"
}
]]
local function parse_number(s)
	local sign, body

	sign, body = s:match("^(%-?)0x([0-9A-Fa-f_]+)$")

	if body then
		return (sign == "-" and -1 or 1) * tonumber(body:gsub("_", ""), 16), "hex"
	end

	sign, body = s:match("^(%-?)0o([0-7_]+)$")

	if body then
		return (sign == "-" and -1 or 1) * tonumber(body:gsub("_", ""), 8), "oct"
	end

	sign, body = s:match("^(%-?)0b([01_]+)$")

	if body then
		return (sign == "-" and -1 or 1) * tonumber(body:gsub("_", ""), 2), "bin"
	end

	local clean = s:gsub("_", "")
	return tonumber(clean)
end

--[[
{
	"in":  "string — a Caspian literal expression",
	"out": "the literal's Lua-representation value; raises via a second return value on unrecognized shape"
}
]]
local function parse_literal(rhs)
	if rhs == "true" then
		return true
	end

	if rhs == "false" then
		return false
	end

	if rhs == "null" then
		return M.null
	end

	local sym = rhs:match("^:([%w_]+)$")

	if sym then
		return sym
	end

	local sq = rhs:match("^'(.*)'$")

	if sq then
		return (sq:gsub("''", "'"))
	end

	local dq = rhs:match('^"(.*)"$')

	if dq then
		return dq
	end

	local n, base = parse_number(rhs)

	if n then
		return n, base, nil
	end

	return nil, nil, "cannot parse literal: " .. rhs
end

-- Words that should NOT match the bareword-command-as-expression pattern in
-- parse_expression. Construct keywords / clause words / logical connectives /
-- control-flow words all have their own atoms and never become `{bwc: name}`.
-- Kept as a plain table (not derived from CONSTRUCT_KEYWORDS) so it's
-- available before parse_expression is defined.
local RESERVED_FOR_BWC_EXPR = {
	["while"] = true, ["until"] = true,
	["begin"] = true, ["end"] = true,
	["if"] = true, ["unless"] = true,
	["elsif"] = true, ["elseif"] = true, ["else"] = true,
	["function"] = true, ["closure"] = true, ["method"] = true,
	["class"] = true, ["amend"] = true, ["instance"] = true,
	["do"] = true, ["dofunc"] = true,
	["before"] = true, ["between"] = true, ["after"] = true, ["noloop"] = true,
	["and"] = true, ["or"] = true, ["not"] = true,
	["return"] = true, ["break"] = true, ["next"] = true,
	["raise"] = true, ["yield"] = true,
}

-- Forward-declaration so parse_expression can call the compound-expression
-- helpers, and they can recursively call parse_expression.
local parse_expression
local parse_array
local parse_hash
local parse_call_args
local build_call_envelope
local desugar_pipe
local parse_construct_as_expression

--[[
{
	"in":  "string — semi-colon or expression-delimiter-free chunk, e.g. the inner content of an array or hash",
	"out": "list of top-level-comma-separated substrings",
	"note": "respects bracket nesting ([], {}, ()) and quoted-string boundaries (single or double quotes; no escape handling)"
}
]]
local function split_top_level(s, sep_char)
	local parts = {}
	local depth = 0
	local start = 1
	local in_str = nil

	for i = 1, #s do
		local c = s:sub(i, i)

		if in_str then
			if c == in_str then
				in_str = nil
			end

		elseif c == "'" or c == '"' then
			in_str = c

		elseif c == "[" or c == "{" or c == "(" then
			depth = depth + 1

		elseif c == "]" or c == "}" or c == ")" then
			depth = depth - 1

		elseif c == sep_char and depth == 0 then
			table.insert(parts, s:sub(start, i - 1))
			start = i + 1
		end
	end

	table.insert(parts, s:sub(start))
	return parts
end

--[[
{
	"in":  "string starting with '[' and ending with ']'",
	"out": "{array = [expr_table, ...]}",
	"raises": "when an element expression is unrecognized"
}
]]
parse_array = function(s)
	local inner = s:sub(2, -2):gsub("^%s+", ""):gsub("%s+$", "")

	if inner == "" then
		return attach_line({array = {}})
	end

	local elements = split_top_level(inner, ",")
	local exprs = {}

	for _, elem in ipairs(elements) do
		local et = elem:gsub("^%s+", ""):gsub("%s+$", "")

		if et ~= "" then
			table.insert(exprs, parse_expression(et))
		end
	end

	return attach_line({array = exprs})
end

--[[
{
	"in":  "string — a hash key as written in source (bareword identifier or single/double-quoted string)",
	"out": "the key as a plain string"
}
]]
local function parse_hash_key(k)
	local sq = k:match("^'(.*)'$")

	if sq then
		return (sq:gsub("''", "'"))
	end

	local dq = k:match('^"(.*)"$')

	if dq then
		return dq
	end

	if k:match("^[%w_]+$") then
		return k
	end

	error("transpile: bad hash key: " .. k)
end

--[[
{
	"in":  "string starting with '{' and ending with '}'",
	"out": "{hash = [[key_string, expr_table], ...]}",
	"raises": "on malformed key: value pairs or unrecognized value expression"
}
]]
parse_hash = function(s)
	local inner = s:sub(2, -2):gsub("^%s+", ""):gsub("%s+$", "")

	if inner == "" then
		return attach_line({hash = {}})
	end

	-- Walk `inner` splitting on top-level commas AND top-level `#…\n` comments
	-- in one pass so between-pair comments become `{comment}` entries in the
	-- pairs list. Comments inside a value's brackets stay inside the value
	-- chunk (they get processed by whatever parses that value).
	local items = {}  -- each: {kind = "content"|"comment", text = string}
	local buf = {}
	local in_str = nil
	local depth = 0
	local i = 1
	local len = #inner

	local function flush_buf()
		local t = trim(table.concat(buf))

		if t ~= "" then
			table.insert(items, {kind = "content", text = t})
		end

		buf = {}
	end

	while i <= len do
		local c = inner:sub(i, i)

		if in_str then
			table.insert(buf, c)

			if c == in_str then
				if in_str == "'"
					and i + 1 <= len
					and inner:sub(i + 1, i + 1) == "'"
				then
					table.insert(buf, "'")
					i = i + 2
				else
					in_str = nil
					i = i + 1
				end
			else
				i = i + 1
			end

		elseif c == "'" or c == '"' then
			in_str = c
			table.insert(buf, c)
			i = i + 1

		elseif c == "(" or c == "[" or c == "{" then
			depth = depth + 1
			table.insert(buf, c)
			i = i + 1

		elseif c == ")" or c == "]" or c == "}" then
			depth = depth - 1
			table.insert(buf, c)
			i = i + 1

		elseif c == "#" and depth == 0 then
			-- Only extract at pair boundaries (buffer empty / whitespace-only).
			-- A `#` mid-value is inside a construct like `function(...) end` —
			-- the `end` doesn't close a bracket, so depth stays 0, but the
			-- comment belongs to the value's own downstream parse. Keep it in
			-- the buffer so the whole value chunk (including the trailing
			-- comment) reaches parse_expression intact.
			if trim(table.concat(buf)) == "" then
				buf = {}
				local start = i + 1

				while i <= len and inner:sub(i, i) ~= "\n" do
					i = i + 1
				end

				table.insert(items, {
					kind = "comment",
					text = trim(inner:sub(start, i - 1)),
				})
			else
				table.insert(buf, c)
				i = i + 1
			end

		elseif c == "," and depth == 0 then
			flush_buf()
			i = i + 1

		else
			table.insert(buf, c)
			i = i + 1
		end
	end

	flush_buf()

	local out = {}

	for _, item in ipairs(items) do
		if item.kind == "comment" then
			table.insert(out, {comment = item.text})
		else
			local pair = item.text
			local key_and_value = split_top_level(pair, ":")

			if #key_and_value < 2 then
				error("transpile: bad hash pair: " .. pair)
			end

			local key_str = key_and_value[1]:gsub("^%s+", ""):gsub("%s+$", "")
			local value_str = table.concat(key_and_value, ":", 2)
				:gsub("^%s+", ""):gsub("%s+$", "")

			-- If the value is a block construct with a trailing comment
			-- (`default: function(...) end # trailing`), parse_construct_as_expression
			-- captures the trailing comment via the sink so we can emit it
			-- as a pair-list entry after the pair itself. Non-construct
			-- values leave the sink untouched.
			local trailing = {}
			local first_word = value_str:match("^([%w_]+)")
			local value_atom

			if first_word and (
				first_word == "function" or first_word == "closure"
				or first_word == "method" or first_word == "class"
				or first_word == "instance" or first_word == "amend"
				or first_word == "do" or first_word == "dofunc"
			) then
				value_atom = parse_construct_as_expression(value_str, trailing)

				if not value_atom then
					value_atom = parse_expression(value_str)
				end
			else
				value_atom = parse_expression(value_str)
			end

			table.insert(out, {parse_hash_key(key_str), value_atom})

			for _, tc in ipairs(trailing) do
				table.insert(out, tc)
			end
		end
	end

	return attach_line({hash = out})
end

--[[
{
	"in":  "string, string — haystack and needle",
	"out": "1-indexed position of the first top-level (not inside brackets/quotes) occurrence of needle in s, or nil",
	"note": "same string/bracket state machine as split_top_level, applied to a multi-char needle rather than a single char"
}
]]
--[[
{
	"in":  "string — a Caspian expression",
	"out": "1-indexed position of the LAST top-level pipe `|` in s that isn't part of `||` (logical OR) or `|&` (null-safe pipe, deferred). nil if none found.",
	"note": "left-to-right associativity means the rightmost pipe splits first: `A | B | C` → `((A|B) | C)` → `C(B(A))`. Same string/bracket state machine as find_top_level."
}
]]
local function find_last_top_level_pipe(s)
	local depth = 0
	local in_str = nil
	local last = nil
	local i = 1
	local len = #s

	while i <= len do
		local c = s:sub(i, i)

		if in_str then
			if c == in_str then
				in_str = nil
			end

			i = i + 1

		elseif c == "'" or c == '"' then
			in_str = c
			i = i + 1

		elseif c == "(" or c == "[" or c == "{" then
			depth = depth + 1
			i = i + 1

		elseif c == ")" or c == "]" or c == "}" then
			depth = depth - 1
			i = i + 1

		elseif depth == 0 and c == "|" then
			local nxt = s:sub(i + 1, i + 1)

			if nxt == "|" then
				-- `||` is logical OR, not a pipe. Skip both chars.
				i = i + 2
			elseif nxt == "&" then
				-- `|&` is the null-safe pipe — record its position and advance
				-- past both chars. Callers check s[pos+1] to distinguish `|`
				-- from `|&` and slice the RHS accordingly.
				last = i
				i = i + 2
			else
				last = i
				i = i + 1
			end

		else
			i = i + 1
		end
	end

	return last
end

local function find_top_level(s, needle)
	local depth = 0
	local in_str = nil
	local nlen = #needle
	local i = 1

	while i <= #s - nlen + 1 do
		local c = s:sub(i, i)

		if in_str then
			if c == in_str then
				in_str = nil
			end

			i = i + 1

		elseif c == "'" or c == '"' then
			in_str = c
			i = i + 1

		elseif c == "(" or c == "[" or c == "{" then
			depth = depth + 1
			i = i + 1

		elseif c == ")" or c == "]" or c == "}" then
			depth = depth - 1
			i = i + 1

		elseif depth == 0 and s:sub(i, i + nlen - 1) == needle then
			return i

		else
			i = i + 1
		end
	end

	return nil
end

--[[
{
	"in":  "string — a Caspian expression",
	"out": "receiver_expr, s_after — consuming a leading $$name, $name, @name, or %name receiver-atom. nil, nil if no such prefix.",
	"shapes": {
		"$$name": "{varobj = name} — the variable-object of `name`, not its value",
		"$name":  "{var = name} — the variable's value",
		"@name":  "{at = name} — an at-sigil field on the current object (sugar for %bucket[name]); norm expands the sugar",
		"%name":  "{sys = name} — the system-method sigil"
	},
	"note": "$$ is tried FIRST so it wins over $name against a `$$foo` input"
}
]]
local function consume_receiver(s)
	local dd = s:match("^%$%$([%w_]+)")

	if dd then
		return attach_line({varobj = dd}), s:sub(3 + #dd)
	end

	local d = s:match("^%$([%w_]+)")

	if d then
		return attach_line({var = d}), s:sub(2 + #d)
	end

	local a = s:match("^@([%w_]+)")

	if a then
		return attach_line({at = a}), s:sub(2 + #a)
	end

	-- Fetch lookup — two source forms, one atom.
	--   Short: `%(url, kw: v)`  — bareword-less sigil-call, parens.
	--   Long:  `%fetch(url, kw: v)` — sigil-with-name-called-as-if-callable.
	-- Both produce `{fetch: {args, kw?}}`. Detected BEFORE the `%name` case
	-- so `%fetch(` is consumed as fetch, not as a `{sys: fetch}` sys atom.
	local fetch_after
	if s:sub(1, 2) == "%(" then
		fetch_after = 2
	elseif s:sub(1, 7) == "%fetch(" then
		fetch_after = 7
	end

	if fetch_after then
		local paren = s:sub(fetch_after):match("^(%b())")

		if paren then
			local content = trim(paren:sub(2, -2))

			if content == "" then
				error("transpile: `%()` / `%fetch()` needs a URL: " .. s)
			end

			local positionals, kwargs = parse_call_args(content, "fetch", true)
			local fetch_body = {args = positionals}

			if #kwargs > 0 then
				fetch_body.kw = kwargs
			end

			return attach_line({fetch = fetch_body}), s:sub(fetch_after + #paren)
		end
	end

	local p = s:match("^%%([%w_]+)")

	if p then
		return attach_line({sys = p}), s:sub(2 + #p)
	end

	return nil, nil
end

--[[
{
	"in":  "string that MAY start with a series of `.name` or `.$name` segments",
	"out": "list-of-segments, rest_string — or nil, s if the string doesn't start with a valid segment",
	"note": "each segment is either a string (bareword `.name`) or a value-atom table (sigiled `.$name` -> {var = name}). empty-name segments (`..name`, `. name`, `.`) aren't matched"
}
]]
local function consume_dot_segments(s)
	local segments = {}
	local rest = s

	while true do
		local svar, sr = rest:match("^%.%$([%w_]+)(.*)")

		if svar then
			table.insert(segments, attach_line({var = svar}))
			rest = sr
		else
			local name, r = rest:match("^%.([%w_]+%??)(.*)")

			if not name then
				break
			end

			table.insert(segments, name)
			rest = r
		end
	end

	if #segments == 0 then
		return nil, s
	end

	return segments, rest
end

--[[
{
	"in":  "recv (receiver value-atom or nested atom), method (bareword string or an atom for dynamic / quoted-string dispatch), envelope (optional {args?, kw?, blocks?, line?})",
	"out": "a `{op: \".\", left: recv, right: method, args?, kw?, blocks?, line?}` binop atom — the CaspianJ form of every dot-method call. `right` is a bare string when the source used a bareword method name (`.foo`), a value atom `{v: X}` when the source used a string literal (`.'foo'` / `.\"foo\"`), or a var / at / other atom when the source used dynamic dispatch (`.$var`, `.@field`)."
}
]]
local function dot_atom(recv, method, envelope)
	local atom = {op = ".", left = recv, right = method}

	if envelope then
		if envelope.args ~= nil then atom.args = envelope.args end
		if envelope.kw ~= nil then atom.kw = envelope.kw end
		if envelope.blocks ~= nil then atom.blocks = envelope.blocks end
		if envelope.line ~= nil then atom.line = envelope.line end
	end

	return atom
end

--[[
{
	"in":  "string starting with '(' and ending with ')'",
	"out": "true iff the leading '(' and trailing ')' are a matched outer pair (nothing after the closing paren, and depth doesn't reach zero mid-string)"
}
]]
local function has_matched_outer_parens(s)
	if s:sub(1, 1) ~= "(" or s:sub(-1) ~= ")" then
		return false
	end

	local depth = 0
	local in_str = nil

	for i = 1, #s do
		local c = s:sub(i, i)

		if in_str then
			if c == in_str then
				in_str = nil
			end

		elseif c == "'" or c == '"' then
			in_str = c

		elseif c == "(" then
			depth = depth + 1

		elseif c == ")" then
			depth = depth - 1

			if depth == 0 and i < #s then
				return false
			end
		end
	end

	return depth == 0
end

-- Binary operators in split-first order. Two constraints:
--
--   1. Weakest precedence first (leftmost split becomes the outer op).
--   2. Within a precedence tier, longer ops before shorter ops that share a prefix
--      (so `2 ** 8` doesn't get sliced by `*` first). Applies to **/*, <=/<, >=/>.
--
-- Multi-op expressions currently follow leftmost-split (right-associative for the
-- outer op). Precedence-and-associativity-aware parsing is deferred until multi-op
-- expressions are added to the test bed.
local BIN_OPS = {
	" or ",
	" and ",
	"||",
	"&&",
	"==",
	"!=",
	"<=",
	">=",
	"<",
	">",
	"+",
	"-",
	"**",
	"*",
	"/",
	"%",
}

--[[
{
	"in":  "string — a Caspian expression",
	"out": "operator-shape expression table, or nil if no operator matched",
	"shapes": [
		"binary op   -> {op = <op>, left = <expr>, right = <expr>}",
		"unary not/! -> {op = <op>, operand = <expr>}",
		"ternary     -> {op = '?:', cond = C, ['then'] = T, ['else'] = F}"
	]
}
]]
local function try_operator_expression(s)
	local q_pos = find_top_level(s, "?")

	if q_pos then
		local cond_str = trim(s:sub(1, q_pos - 1))
		local rest = s:sub(q_pos + 1)
		local c_pos = find_top_level(rest, ":")

		if c_pos and cond_str ~= "" then
			local then_str = trim(rest:sub(1, c_pos - 1))
			local else_str = trim(rest:sub(c_pos + 1))

			if then_str ~= "" and else_str ~= "" then
				return attach_line({
					op = "?:",
					cond = parse_expression(cond_str),
					["then"] = parse_expression(then_str),
					["else"] = parse_expression(else_str),
				})
			end
		end
	end

	for _, op in ipairs(BIN_OPS) do
		local pos = find_top_level(s, op)

		if pos then
			local left = trim(s:sub(1, pos - 1))
			local right = trim(s:sub(pos + #op))

			if left ~= "" and right ~= "" then
				return attach_line({
					op = trim(op),
					left = parse_expression(left),
					right = parse_expression(right),
				})
			end
		end
	end

	if s:sub(1, 4) == "not " then
		return attach_line({op = "not", operand = parse_expression(trim(s:sub(5)))})
	end

	if s:sub(1, 1) == "!" and s:sub(2, 2) ~= "=" then
		return attach_line({op = "!", operand = parse_expression(trim(s:sub(2)))})
	end

	return nil
end

--[[
{
	"in":  "string — a Caspian expression",
	"out": "expression-shape Lua table: {value = literal}, {var = name}, {sys = name}, {array = [...]}, {hash = [[k,v],...]}, a method-call list ([recv, method, {args=[...]}]), or an operator shape",
	"raises": "when the expression shape isn't recognized; error message preserves 'cannot parse literal' for simple-literal failures"
}
]]
parse_expression = function(s)
	if active_heredocs then
		local hd_id = trim(s):match("^%%__caspian_heredoc_(%d+)__$")

		if hd_id then
			local atom = active_heredocs[tonumber(hd_id)]

			if atom then
				return atom
			end
		end
	end

	-- Assignment as expression. LOWEST precedence — tried FIRST so it splits
	-- before any operator. Right-associative (`$a = $b = $c` = `$a = ($b = $c)`).
	--   `$name++` / `$name--` → {postinc: name} / {postdec: name} — postfix
	--       increment/decrement, sugar for `$name += 1` / `$name -= 1`
	--   `$name OP= EXPR`      → {setvar_op: {op, name, value}} — compound-assign
	--       as expression, sugar for `$name = $name OP EXPR`
	--   `$name = EXPR`        → {setvar: {name, value}} — plain assignment
	--       as expression; yields the assigned value
	-- Full CaspJ preserves each source form as a distinct atom; norm collapses
	-- postinc/postdec/setvar_op down to plain setvar (with the layered
	-- desugaring applied). Only variable targets (`$name`) are handled here;
	-- property / subscript / class-field targets stay at statement position.
	do
		local pi_name = s:match("^%$([%w_]+)%s*%+%+$")

		if pi_name then
			return attach_line({postinc = pi_name})
		end

		local pd_name = s:match("^%$([%w_]+)%s*%-%-$")

		if pd_name then
			return attach_line({postdec = pd_name})
		end

		-- Compound-assign forms (longest op first so `**=` beats `*=`).
		local compound_ops = {
			{op = "**", pat = "%*%*"},
			{op = "||", pat = "||"},
			{op = "&&", pat = "&&"},
			{op = "+",  pat = "%+"},
			{op = "-",  pat = "%-"},
			{op = "*",  pat = "%*"},
			{op = "/",  pat = "/"},
			{op = "%",  pat = "%%"},
		}

		for _, entry in ipairs(compound_ops) do
			local name, rhs = s:match("^%$([%w_]+)%s*" .. entry.pat .. "=%s*(.+)$")

			if name and rhs and rhs ~= "" then
				return attach_line({
					setvar_op = {
						op = entry.op,
						name = name,
						value = parse_expression(rhs),
					},
				})
			end
		end

		-- Plain `$name = EXPR`. The `=` must NOT be part of `==`, `!=`, `<=`,
		-- `>=` — those fail the `^%$name%s*=` prefix (chars intervening between
		-- the name and `=`). Also skip `==` by checking the char AFTER `=`.
		local sv_name, sv_rhs = s:match("^%$([%w_]+)%s*=%s*(.+)$")

		if sv_name and sv_rhs and sv_rhs ~= "" and sv_rhs:sub(1, 1) ~= "=" then
			return attach_line({
				setvar = {
					name = sv_name,
					value = parse_expression(sv_rhs),
				},
			})
		end
	end

	-- Logical connectives (`or`, `and`, `||`, `&&`) bind LOOSER than the pipe.
	-- Handled here at the top of parse_expression so they split before the pipe
	-- does — `A | B || C` groups as `(A | B) || C` (fallback pattern), not as
	-- `A | (B || C)` (which would be an invalid pipe RHS).
	do
		local LOOSER_THAN_PIPE = {" or ", " and ", "||", "&&"}

		for _, op in ipairs(LOOSER_THAN_PIPE) do
			local pos = find_top_level(s, op)

			if pos then
				local left_str = trim(s:sub(1, pos - 1))
				local right_str = trim(s:sub(pos + #op))

				if left_str ~= "" and right_str ~= "" then
					return {
						op = trim(op),
						left = parse_expression(left_str),
						right = parse_expression(right_str),
					}
				end
			end
		end
	end

	-- Pipe operator `|` (basic) or `|&` (null-safe) — looser than every other
	-- operator except the logical connectives above; left-to-right associative.
	-- The rightmost top-level pipe splits first. `||` is skipped by the finder.
	do
		local pipe_pos = find_last_top_level_pipe(s)

		if pipe_pos then
			local is_null_safe = s:sub(pipe_pos + 1, pipe_pos + 1) == "&"
			local op_len = is_null_safe and 2 or 1
			local lhs_str = trim(s:sub(1, pipe_pos - 1))
			local rhs_str = trim(s:sub(pipe_pos + op_len))

			if lhs_str ~= "" and rhs_str ~= "" then
				return desugar_pipe(parse_expression(lhs_str), rhs_str,
					is_null_safe and "|&" or "|")
			end
		end
	end

	-- Double-quoted string: record the dq flag so the runtime knows to do
	-- interpolation (`#{expr}`) and escape processing. Value bytes are stored
	-- verbatim from source — CaspJ sees a dq string as a normal string plus
	-- the flag; runtime handles the rest.
	local dq = s:match('^"(.*)"$')

	if dq then
		local atom = {value = dq, dq = true}

		if include_lines and current_line then
			atom.line = current_line
		end

		return atom
	end

	-- parse_literal returns (value, base?, err?) — base is 'hex'/'oct'/'bin'
	-- for non-decimal number literals; err is set only when value is nil and
	-- the string didn't match any literal shape.
	local value, base, lit_err = parse_literal(s)

	if value ~= nil then
		local atom

		-- Preserve `-0` as a distinct atom: the source wrote `-0` (in any base)
		-- and got numeric zero. Caspian keeps the negation for last-element
		-- array-index dispatch; every other consumer treats the value as 0.
		-- See number spec § Negative zero for the runtime rules.
		if value == 0 and type(value) == "number" then
			local ts = trim(s)

			if ts:sub(1, 1) == "-" then
				atom = {value = 0, neg_zero = true}
			end
		end

		if not atom then
			atom = {value = value}
		end

		if base then
			atom.base = base
		end

		if include_lines and current_line then
			atom.line = current_line
		end

		return atom
	end

	-- Block-construct value-atom: `function(...) ... end`, `closure(...) ... end`,
	-- `class ... end`, `instance ... end`, `amend $x ... end`, `do ... end`,
	-- `dofunc ... end`. When any of these appear as an expression (RHS of a
	-- setvar, arg to a call, value in a hash metadata block), the whole
	-- construct becomes a single value-atom. Delegates to the construct
	-- pipeline; it returns nil for anything that doesn't parse cleanly as
	-- a single value-atom, so this fallthrough is safe for non-construct
	-- expressions that happen to start with these keywords.
	do
		local first_word = s:match("^([%w_]+)")

		if first_word and (
			first_word == "function" or first_word == "closure"
			or first_word == "method" or first_word == "class"
			or first_word == "instance" or first_word == "amend"
			or first_word == "do" or first_word == "dofunc"
			or first_word == "begin"
		) then
			local atom = parse_construct_as_expression(s)

			if atom then
				return atom
			end
		end
	end

	-- Regex literal: rx(/PATTERN/FLAGS) — a special-cased expression form.
	-- The `rx(...)` wrapper delimits a regex-literal payload; inside, `/`
	-- delimits the pattern and a trailing `[%w]*` run is the flags string
	-- (empty when no flags). The pattern is captured verbatim: backslash
	-- escapes are preserved as source characters, not decoded. Escaped-slash
	-- handling in the pattern is deferred — a first-pass scans greedily for
	-- the last `/` before the closing paren, so an unescaped inner `/` is
	-- treated as pattern/flag separator.
	local rx_inner = s:match("^rx%((.+)%)$")

	if rx_inner then
		local rx_pat, rx_flags = rx_inner:match("^/(.*)/%s*([%w]*)%s*$")

		if rx_pat then
			return attach_line({rx = {pattern = rx_pat, flags = rx_flags}})
		end
	end

	local var_name = s:match("^%$([%w_]+)$")

	if var_name then
		return attach_line({var = var_name})
	end

	local sys_name = s:match("^%%([%w_]+)$")

	if sys_name then
		return attach_line({sys = sys_name})
	end

	-- Varobj atom: $$name is the variable-object (the meta-object representing
	-- the variable itself), distinct from $name (its value).
	local varobj_name = s:match("^%$%$([%w_]+)$")

	if varobj_name then
		return attach_line({varobj = varobj_name})
	end

	-- At-sigil atom: @name is a class-field reference, similar to a variable
	-- (transpiles as a sigil-family atom `{at: name}`).
	local at_name = s:match("^@([%w_]+)$")

	if at_name then
		return attach_line({at = at_name})
	end

	-- Bare-word command as expression atom. An undecorated identifier at
	-- expression position (`$j = foo + bar`, `$x = maybe`) transpiles to a
	-- `{bwc: name}` atom — same shape as bareword commands at statement
	-- position (`foo 'bar'`). Bareword commands are DSL entries (see docs);
	-- what they mean is a runtime concern.
	--
	-- Reserved words don't match: construct keywords (if / while / function /
	-- end / ...), begin-clause words (before / between / after / noloop),
	-- logical connectives (and / or / not), and control-flow words (return /
	-- break / next / raise / yield) all have their own handling and never
	-- become bareword atoms. List inlined here — CONSTRUCT_KEYWORDS is
	-- declared later in the module.
	local bare_ident = s:match("^([%w_]+)$")

	if bare_ident and not RESERVED_FOR_BWC_EXPR[bare_ident] then
		return attach_line({bwc = bare_ident})
	end

	-- Bare-word call as expression, parens form: `name(args)`. Nested BWC
	-- calls like `private(method &foo() end)` land here. Statement position
	-- handles the same shape via the bareword-BWC path in transpile_statement;
	-- this is the expression-position equivalent.
	local bare_call_name, bare_call_paren =
		s:match("^([%w_]+)%s*(%b())$")

	if bare_call_name and not RESERVED_FOR_BWC_EXPR[bare_call_name] then
		local args_str = trim(bare_call_paren:sub(2, -2))
		local out = {{bwc = bare_call_name}}

		if args_str ~= "" then
			local positionals, kwargs = parse_call_args(args_str, bare_call_name, true)

			for _, p in ipairs(positionals) do
				table.insert(out, p)
			end

			if #kwargs > 0 then
				table.insert(out, {kw = kwargs})
			end
		end

		return out
	end

	-- Generalized `&(EXPR)` — the ampersand invokes any expression that produces
	-- a callable. Atom-shape variants:
	--   * bareword name (`&foo`) — `{amp: "foo"}` (existing sugar shape, handled below)
	--   * `&(EXPR)` — `{amp: <expr-atom>}` — arbitrary expression as callable
	--   * `&$var` — sugar for `&($var)`, same `{amp: {var}}`
	--   * `&@field` — sugar for `&(@field)`, same `{amp: {at}}`
	--
	-- After the atom, chain segments (`.method`, `.'name'`, `[key]`) extend the
	-- callable target under the dot-binds-tighter rule: `&$var.method` means
	-- `&($var.method)` — take .method of $var, call the result. To insulate
	-- the amp-call from a following dot chain, wrap the target in parens:
	-- `(&$var).method` calls $var first, then dots the result.
	do
		local callable_atom, amp_rest

		local paren_inner, paren_rest = s:match("^&(%b())(.*)$")

		if paren_inner then
			local inner = trim(paren_inner:sub(2, -2))

			if inner == "" then
				error("transpile: `&(...)` needs an expression: " .. s)
			end

			callable_atom = parse_expression(inner)
			amp_rest = paren_rest
		else
			-- `&$name` or `&@name` — sigil-atom callables.
			local var_name, var_rest = s:match("^&%$([%w_]+)(.*)$")

			if var_name then
				callable_atom = attach_line({var = var_name})
				amp_rest = var_rest
			else
				local at_name, at_rest = s:match("^&@([%w_]+)(.*)$")

				if at_name then
					callable_atom = attach_line({at = at_name})
					amp_rest = at_rest
				else
					-- `&foo.chain` — bareword amp with chain. Only fires when
					-- a chain (`.` or `[`) actually follows. Plain `&foo`
					-- (no chain) falls through to the bareword-amp path
					-- below, which emits the string-amp shape `{amp: "foo"}`.
					local bw_name, bw_rest = s:match("^&([%a_][%w_]*)(.*)$")

					if bw_name then
						local first = bw_rest:sub(1, 1)

						if first == "." or first == "[" then
							callable_atom = attach_line({bwc = bw_name})
							amp_rest = bw_rest
						end
					end
				end
			end
		end

		-- Extend the callable target with chain segments (dot access, subscript)
		-- if any follow. Under dot-binds-tighter, these bind to the target
		-- expression, not to the outer amp-call.
		if callable_atom and amp_rest then
			local extended_atom, extended_rest = callable_atom, amp_rest
			local walked = false

			while extended_rest ~= "" do
				local trimmed = extended_rest
				-- `.name(args)` — dot-method call with envelope.
				local m_name, m_paren, m_rest =
					trimmed:match("^%.([%w_]+%??)%s*(%b())(.*)$")

				if m_name then
					local envelope = build_call_envelope(
						trim(m_paren:sub(2, -2)), m_name, true)
					extended_atom = attach_line(dot_atom(
						extended_atom, m_name, envelope))
					extended_rest = m_rest
					walked = true
					goto continue_amp_chain
				end

				-- `.'name'(args)` — quoted-string method name with envelope.
				local qm_open, qm_body, qm_close, qm_paren, qm_rest =
					trimmed:match("^%.(['\"])(.-)(['\"])%s*(%b())(.*)$")

				if qm_open and qm_open == qm_close then
					local envelope = build_call_envelope(
						trim(qm_paren:sub(2, -2)), qm_body, true)
					extended_atom = attach_line(dot_atom(
						extended_atom, attach_line({v = qm_body}), envelope))
					extended_rest = qm_rest
					walked = true
					goto continue_amp_chain
				end

				-- `.'name'` — bare quoted-string method access.
				local qb_open, qb_body, qb_close, qb_rest =
					trimmed:match("^%.(['\"])(.-)(['\"])(.*)$")

				if qb_open and qb_open == qb_close then
					extended_atom = attach_line(dot_atom(
						extended_atom, attach_line({v = qb_body})))
					extended_rest = qb_rest
					walked = true
					goto continue_amp_chain
				end

				-- `[key]` or `[key]?` — subscript. Stays row form.
				local sub_b, sub_q, sub_rest =
					trimmed:match("^(%b[])(%??)(.*)$")

				if sub_b then
					local inner = trim(sub_b:sub(2, -2))
					local method = (sub_q == "?") and "[]?" or "[]"
					local args_ast = {}

					if inner ~= "" then
						for _, arg in ipairs(split_top_level(inner, ",")) do
							local at = trim(arg)

							if at ~= "" then
								table.insert(args_ast, parse_expression(at))
							end
						end
					end

					extended_atom = {extended_atom, method,
						attach_line({args = args_ast})}
					extended_rest = sub_rest
					walked = true
					goto continue_amp_chain
				end

				-- `.name` — bare dot-method access.
				local a_name, a_rest =
					trimmed:match("^%.([%w_]+%??)(.*)$")

				if a_name then
					extended_atom = attach_line(dot_atom(extended_atom, a_name))
					extended_rest = a_rest
					walked = true
					goto continue_amp_chain
				end

				break

				::continue_amp_chain::
			end

			if walked then
				callable_atom = extended_atom
				amp_rest = extended_rest
			end
		end

		if callable_atom then
			local rest = trim(amp_rest)
			local out = {attach_line({amp = callable_atom})}

			if rest == "" then
				return out

			elseif rest:sub(1, 1) == "(" and rest:sub(-1) == ")" then
				local args_str = trim(rest:sub(2, -2))

				if args_str ~= "" then
					local positionals, kwargs = parse_call_args(args_str, "&(...)", true)

					for _, p in ipairs(positionals) do
						table.insert(out, p)
					end

					if #kwargs > 0 then
						table.insert(out, {kw = kwargs})
					end
				end

				return out

			elseif type(callable_atom) == "table" and callable_atom.var
				and rest ~= "" and rest:sub(1, 1) ~= "("
			then
				-- Paren-less args on `&$var` shorthand only (not on `&(EXPR)` —
				-- that keeps its parens-only args rule since the inner expr can
				-- itself contain commas).
				local positionals, kwargs = parse_call_args(rest, "&$var", false)

				for _, p in ipairs(positionals) do
					table.insert(out, p)
				end

				if #kwargs > 0 then
					table.insert(out, {kw = kwargs})
				end

				return out
			end
		end
	end

	-- Bare-word call as expression. Three forms — same shape as bwc-as-statement,
	-- a list containing the amp atom followed by any args. `&name` alone is a
	-- zero-args call; `&name(args)` is the parens form; `&name arg1, arg2` is
	-- the paren-less form (allowed at expression position ONLY when the args
	-- don't start with `&` — that constraint keeps `if &ok &yay end` from
	-- misparsing the condition as `&ok(&yay)`). To hold a reference to the
	-- callable, the caller uses `$name` (the variable slot storing it).
	local bwc_name = s:match("^&([%w_]+)$")

	if bwc_name then
		return {attach_line({amp = bwc_name})}
	end

	local bwc_p_name, bwc_p_paren = s:match("^&([%w_]+)%s*(%b())$")

	if bwc_p_name then
		local args_str = trim(bwc_p_paren:sub(2, -2))

		if args_str == "" then
			return {attach_line({amp = bwc_p_name})}
		end

		local positionals, kwargs = parse_call_args(args_str, bwc_p_name, true)
		local out = {attach_line({amp = bwc_p_name})}

		for _, p in ipairs(positionals) do
			table.insert(out, p)
		end

		if #kwargs > 0 then
			table.insert(out, {kw = kwargs})
		end

		return out
	end

	local bwc_pl_name, bwc_pl_tail = s:match("^&([%w_]+)%s+(.+)$")

	if bwc_pl_name and bwc_pl_tail and bwc_pl_tail:sub(1, 1) ~= "&" then
		-- Guard against greedy matches: `&foo == true` matches this pattern
		-- but the tail isn't an arg list. pcall lets a failed args-parse fall
		-- through to the operator parser below — EXCEPT when the failure is a
		-- trailing-comma syntax error, which must surface to the caller instead
		-- of being swallowed as "maybe this isn't an arg list after all".
		local ok, positionals, kwargs = pcall(parse_call_args, bwc_pl_tail, bwc_pl_name, false)

		if not ok and type(positionals) == "string"
			and positionals:find("trailing comma allowed only inside", 1, true)
		then
			error(positionals)
		end

		if ok then
			local out = {attach_line({amp = bwc_pl_name})}

			for _, p in ipairs(positionals) do
				table.insert(out, p)
			end

			if #kwargs > 0 then
				table.insert(out, {kw = kwargs})
			end

			return out
		end
	end

	-- Method call as expression: recv.method(args) — via consume_receiver so the
	-- receiver can be a $var, a %sys, or a $$varobj.
	local ec_recv, ec_after = consume_receiver(s)

	if ec_recv then
		local ec_method, ec_paren = ec_after:match("^%.([%w_]+%??)%s*(%b())$")

		if ec_method then
			local args_str = trim(ec_paren:sub(2, -2))
			local envelope = build_call_envelope(args_str, ec_method, true)

			if envelope then
				return {ec_recv, ec_method, attach_line(envelope)}
			end

			return {ec_recv, ec_method}
		end
	end

	-- Method call as expression, paren-less: `recv.method arg1, arg2`. Mirrors
	-- the parens form above. pcall guards a failed args-parse (e.g. the tail is
	-- actually an operator continuation like `$foo.bar > 5`) so we fall through
	-- to the attribute-access / operator-parser paths. Trailing-comma errors
	-- re-raise instead of falling through — same pattern as the expression-
	-- position `&fn args` handler further up. The separator is space-or-tab
	-- ONLY (not `%s+` which would swallow newlines) — an `if <cond>\n<body>`
	-- construct whose cond ends in a `.method?` must NOT eat body content.
	if ec_recv then
		local ec_pl_method, ec_pl_tail = ec_after:match("^%.([%w_]+%??)[ \t]+(.+)$")

		if ec_pl_method and ec_pl_tail:sub(1, 1) ~= "."
			and ec_pl_tail:sub(1, 1) ~= "["
		then
			local ok, positionals, kwargs =
				pcall(parse_call_args, ec_pl_tail, ec_pl_method, false)

			if not ok and type(positionals) == "string"
				and positionals:find("trailing comma allowed only inside", 1, true)
			then
				error(positionals)
			end

			if ok then
				local envelope = attach_line({args = positionals})

				if #kwargs > 0 then
					envelope.kw = kwargs
				end

				return attach_line(dot_atom(ec_recv, ec_pl_method, envelope))
			end
		end
	end

	-- Object-as-method call as expression: recv.$callable_var(args). Same shape
	-- as a named method call, but position [2] is a value-atom (the callable
	-- expression) instead of a bareword string.
	if ec_recv then
		local ec_svar, ec_svar_paren = ec_after:match("^%.%$([%w_]+)%s*(%b())$")

		if ec_svar then
			local args_str = trim(ec_svar_paren:sub(2, -2))
			local envelope = build_call_envelope(args_str, ec_svar, true)

			return attach_line(dot_atom(
				ec_recv, attach_line({var = ec_svar}), envelope))
		end
	end

	-- Chained attribute access as expression: recv(.name)+ with any number of
	-- segments. Single-segment ($obj.name) and multi-segment ($obj.a.b.c) both
	-- lower to a nested `.` binop-atom chain. No args form; parens fall
	-- through to the method-call-as-expression path above.
	if ec_recv then
		local segments, after = consume_dot_segments(ec_after)

		if segments and after == "" then
			local chain = ec_recv

			for _, name in ipairs(segments) do
				chain = attach_line(dot_atom(chain, name))
			end

			return chain
		end
	end

	-- Subscript as expression: recv[key] or recv[key]? (null-safe).
	if ec_recv then
		local esub_bracket, esub_q = ec_after:match("^(%b[])(%??)$")

		if esub_bracket then
			local key_str = trim(esub_bracket:sub(2, -2))
			local method = (esub_q == "?") and "[]?" or "[]"
			local args_ast = {}

			for _, arg in ipairs(split_top_level(key_str, ",")) do
				local at = trim(arg)

				if at ~= "" then
					table.insert(args_ast, parse_expression(at))
				end
			end

			return {ec_recv, method, attach_line({args = args_ast})}
		end
	end

	-- If nothing else matched a sigil-based receiver, try a bareword receiver
	-- for the chain fallback below. `foo.bar` — `foo` is a bwc atom (a DSL may
	-- have defined `foo` as a method resolved at runtime); `.bar` chains on the
	-- returned value. Same rule for `foo['key']` and every other segment shape.
	-- Only kicks in when the tail actually starts a chain (`.` or `[`) — bare
	-- `foo` alone still goes through the plain-bareword atom path above.
	if not ec_recv then
		-- Match a proper identifier (first char letter or underscore, not a
		-- digit) so `3.14.15` doesn't get read as a bwc chain of `3`.
		local bw_name, bw_rest = s:match("^([%a_][%w_]*)(.*)$")

		if bw_name and not RESERVED_FOR_BWC_EXPR[bw_name] then
			local first = bw_rest:sub(1, 1)

			if first == "." or first == "[" then
				ec_recv = attach_line({bwc = bw_name})
				ec_after = bw_rest
			end
		end
	end

	-- Receiver-tail fallback for expressions: mixed `.name`, `.name(args)`,
	-- `.'name'`, `."name"`, and `[key]` segments after a receiver. Handles
	-- forms the specific patterns above don't cover (e.g. `@foo['bar'].length`
	-- — subscript followed by dot-method).
	if ec_recv then
		local current = ec_recv
		local tail = trim(ec_after)
		local walked = false

		while tail ~= "" do
			-- `.name(args)` — dot-method call with envelope.
			local m_name, m_paren, m_rest =
				tail:match("^%.([%w_]+%??)%s*(%b())(.*)$")

			if m_name then
				local envelope = build_call_envelope(
					trim(m_paren:sub(2, -2)), m_name, true)

				current = attach_line(dot_atom(current, m_name, envelope))
				tail = trim(m_rest)
				walked = true
				goto continue_expr_chain
			end

			-- `.'name'(args)` — string-literal method name with envelope.
			local qm_open, qm_body, qm_close, qm_paren, qm_rest =
				tail:match("^%.(['\"])(.-)(['\"])%s*(%b())(.*)$")

			if qm_open and qm_open == qm_close then
				local envelope = build_call_envelope(
					trim(qm_paren:sub(2, -2)), qm_body, true)

				current = attach_line(dot_atom(current,
					attach_line({v = qm_body}), envelope))
				tail = trim(qm_rest)
				walked = true
				goto continue_expr_chain
			end

			-- `.'name'` — bare string-literal method access.
			local qb_open, qb_body, qb_close, qb_rest =
				tail:match("^%.(['\"])(.-)(['\"])(.*)$")

			if qb_open and qb_open == qb_close then
				current = attach_line(dot_atom(current,
					attach_line({v = qb_body})))
				tail = trim(qb_rest)
				walked = true
				goto continue_expr_chain
			end

			-- `[key]` or `[key]?` — subscript.
			local sub_b, sub_q, sub_rest = tail:match("^(%b[])(%??)(.*)$")

			if sub_b then
				local inner = trim(sub_b:sub(2, -2))
				local method = (sub_q == "?") and "[]?" or "[]"
				local args_ast = {}

				if inner ~= "" then
					for _, arg in ipairs(split_top_level(inner, ",")) do
						local at = trim(arg)

						if at ~= "" then
							table.insert(args_ast, parse_expression(at))
						end
					end
				end

				current = {current, method, attach_line({args = args_ast})}
				tail = trim(sub_rest)
				walked = true
				goto continue_expr_chain
			end

			-- `.name` — bare dot-method access.
			local a_name, a_rest = tail:match("^%.([%w_]+%??)(.*)$")

			if a_name then
				current = attach_line(dot_atom(current, a_name))
				tail = trim(a_rest)
				walked = true
				goto continue_expr_chain
			end

			break

			::continue_expr_chain::
		end

		if walked and tail == "" then
			return current
		end
	end

	-- Receiver-alone fallback: `%[url]` returns its puck atom directly when
	-- nothing else follows the bracket. Other receiver atoms (`$var`, `%name`,
	-- `$$name`, `@name`) are matched by the earlier direct-atom checks and
	-- don't fall through here.
	if ec_recv and ec_after == "" then
		return ec_recv
	end

	if s:sub(1, 1) == "[" and s:sub(-1) == "]" then
		return parse_array(s)
	end

	if s:sub(1, 1) == "{" and s:sub(-1) == "}" then
		return parse_hash(s)
	end

	if has_matched_outer_parens(s) then
		return parse_expression(trim(s:sub(2, -2)))
	end

	local op_expr = try_operator_expression(s)

	if op_expr then
		return op_expr
	end

	error("transpile: " .. (lit_err or ("cannot parse expression: " .. s)))
end

--[[
{
	"in":  "remainder (string — the comma-separated arg list of a call), ctx_name (string — the callable's name, used only for error messages)",
	"out": "positionals (list of value-atoms), kwargs (list of [key, value_atom] entries or {kwsplat = expr} entries)",
	"shapes": [
		"*expr           -> {splat = parse_expression(expr)}       (positional entry)",
		"**expr          -> {kwsplat = parse_expression(expr)}     (kwargs entry)",
		"key: value      -> [key_string, parse_expression(value)]  (kwargs entry)",
		"anything else   -> parse_expression(arg)                  (positional entry)"
	],
	"note": "enforces 'no positional after kwarg' — a bare positional or a `*splat` after a kwarg/kwsplat raises. kwargs and kwsplats can interleave freely within the kwargs section."
}
]]
--[[
{
	"in":  "args_str (string — the arg-list source between call parens or after a paren-less callable), ctx_name (string — used only in error messages)",
	"out": "the third-element envelope for a method-call shape: `{args = [...]}`, plus `kw` when kwargs are present. Returns nil when args_str is empty — caller emits the 2-element method-call shape.",
	"note": "wraps parse_call_args so every method-call and object-as-method site uses the same shape decision. Splats and kwsplats route through the same helper."
}
]]
build_call_envelope = function(args_str, ctx_name, in_brackets)
	if args_str == "" then
		return nil
	end

	local positionals, kwargs = parse_call_args(args_str, ctx_name, in_brackets)
	local envelope = {args = positionals}

	if #kwargs > 0 then
		envelope.kw = kwargs
	end

	return envelope
end

parse_call_args = function(remainder, ctx_name, in_brackets)
	-- `in_brackets` = true when the arg list is enclosed in `[]`, `{}`, or `()`
	-- (or when calling from a context that has already established a delimited
	-- envelope). Only bracketed lists tolerate a trailing comma. Paren-less
	-- call arg lists (`&foo 1, 2, 3,` / `field :name, class: :string,`) reject
	-- one — the comma is a syntax error, not a permissive-formatting nicety.
	if not in_brackets then
		local trimmed = trim(remainder or "")

		if trimmed:sub(-1) == "," then
			error("transpile: trailing comma allowed only inside `[]`, `{}`,"
				.. " or `()` — in `" .. ctx_name .. "` call")
		end
	end

	local positionals = {}
	local kwargs = {}
	local seen_kwarg = false

	for _, arg in ipairs(split_top_level(remainder, ",")) do
		local at = trim(arg)

		if at ~= "" then
			-- `**expr` — kwargs-list entry, matched BEFORE `*` since it's longer.
			if at:sub(1, 2) == "**" then
				local rest = trim(at:sub(3))

				if rest == "" then
					error("transpile: `**` kwarg-splat needs an expression in `"
						.. ctx_name .. "` call")
				end

				seen_kwarg = true
				table.insert(kwargs, {kwsplat = parse_expression(rest)})

			-- `*expr` — positional-list entry.
			elseif at:sub(1, 1) == "*" and at:sub(1, 2) ~= "**" then
				if seen_kwarg then
					error("transpile: positional splat `" .. at
						.. "` after named args in `" .. ctx_name .. "` call")
				end

				local rest = trim(at:sub(2))

				if rest == "" then
					error("transpile: `*` positional-splat needs an expression in `"
						.. ctx_name .. "` call")
				end

				table.insert(positionals, {splat = parse_expression(rest)})

			else
				-- `key: value` — kwarg. Key can be a bareword identifier
				-- (`name: 'x'`), a single-quoted string (`'name': 'x'`), or
				-- a double-quoted string (`"name": 'x'`). All three produce
				-- the same kwarg-key string; source form isn't preserved.
				-- `:sym` (leading colon) is a symbol literal, not a kwarg.
				local kw_key, kw_val = at:match("^([%w_]+)%s*:%s*(.+)$")

				if not kw_key then
					local sq_key, sq_rest = at:match("^'([^']*)'%s*:%s*(.+)$")

					if sq_key and sq_rest and sq_rest ~= "" then
						kw_key = sq_key
						kw_val = sq_rest
					end
				end

				if not kw_key then
					local dq_key, dq_rest = at:match('^"([^"]*)"%s*:%s*(.+)$')

					if dq_key and dq_rest and dq_rest ~= "" then
						kw_key = dq_key
						kw_val = dq_rest
					end
				end

				if kw_key and kw_val and kw_val ~= "" then
					seen_kwarg = true
					table.insert(kwargs, {kw_key, parse_expression(trim(kw_val))})
				else
					if seen_kwarg then
						error("transpile: positional arg `" .. at
							.. "` after named args in `" .. ctx_name .. "` call")
					end

					table.insert(positionals, parse_expression(at))
				end
			end
		end
	end

	return positionals, kwargs
end

-- Compound assignment operators, longest first. Each entry is {op_text, lua_pattern}.
local COMPOUND_OPS = {
	{"**", "%*%*"},
	{"||", "||"},
	{"&&", "&&"},
	{"+",  "%+"},
	{"-",  "%-"},
	{"*",  "%*"},
	{"/",  "/"},
	{"%",  "%%"},
}

--[[
{
	"in":  "lhs_atom (a value-atom — the piped-in value), rhs_str (the source text of the pipe's RHS, which must be a call)",
	"out": "a preserved pipe atom `{op: \"|\", left: LHS, right: RHS}` — CaspianJ keeps the pipe visible; the runtime routes the piped value into the RHS at execution time (matches pipes-spec desugaring rule but preserved rather than expanded).",
	"rhs_forms_and_shapes": [
		"LHS | &fn                  -> right: [{amp: fn}]                          — bwc call, LHS prepends as first positional",
		"LHS | &fn(args)            -> right: [{amp: fn}, arg1, ..., {kw?}]        — bwc call with extras, LHS prepends",
		"LHS | $obj.method          -> right: [{var: obj}, method]                 — method call, LHS prepends as first positional",
		"LHS | $obj.method(args)    -> right: [{var: obj}, method, envelope]       — method call with args, LHS prepends"
	],
	"runtime_rule": "LHS prepends as the first positional arg of the call in right.",
	"note": "only expression-level pipes come through here — statement-leading `| bwc` is handled separately in Section 17."
}
]]
desugar_pipe = function(lhs_atom, rhs_str, op)
	op = op or "|"
	-- LHS | &fn(args) — bwc call. Runtime prepends LHS as first positional.
	local bwc_p_name, bwc_p_paren = rhs_str:match("^&([%w_]+)%s*(%b())$")

	if bwc_p_name then
		local rhs_call = {{amp = bwc_p_name}}
		local args_str = trim(bwc_p_paren:sub(2, -2))

		if args_str ~= "" then
			local positionals, kwargs = parse_call_args(args_str, bwc_p_name, true)

			for _, p in ipairs(positionals) do
				table.insert(rhs_call, p)
			end

			if #kwargs > 0 then
				table.insert(rhs_call, {kw = kwargs})
			end
		end

		return {op = op, left = lhs_atom, right = rhs_call}
	end

	-- LHS | &fn arg1, arg2 — paren-less bwc call with args. Same shape as the
	-- parens form. Matched BEFORE the bare form so `&fn arg` isn't misread as
	-- `&fn` + `arg`.
	local bwc_pl_name, bwc_pl_tail = rhs_str:match("^&([%w_]+)%s+(.+)$")

	if bwc_pl_name and bwc_pl_tail ~= "" then
		local rhs_call = {{amp = bwc_pl_name}}
		local positionals, kwargs = parse_call_args(bwc_pl_tail, bwc_pl_name, false)

		for _, p in ipairs(positionals) do
			table.insert(rhs_call, p)
		end

		if #kwargs > 0 then
			table.insert(rhs_call, {kw = kwargs})
		end

		return {op = op, left = lhs_atom, right = rhs_call}
	end

	-- LHS | &fn (bare) — bwc call, no extras.
	local bwc_bare = rhs_str:match("^&([%w_]+)$")

	if bwc_bare then
		return {op = op, left = lhs_atom, right = {{amp = bwc_bare}}}
	end

	-- LHS | &(EXPR) or LHS | &$var — generalized ampersand: invoke the callable
	-- produced by the parenthesized expression (or by the variable slot for the
	-- shorthand form). Trailing args (parens or paren-less) allowed; the piped
	-- LHS routes into first-positional at normalize time.
	do
		local callable_atom, amp_rest

		local paren_inner, paren_rest = rhs_str:match("^&(%b())(.*)$")

		if paren_inner then
			local inner = trim(paren_inner:sub(2, -2))

			if inner ~= "" then
				callable_atom = parse_expression(inner)
				amp_rest = paren_rest
			end
		else
			local var_name, var_rest = rhs_str:match("^&%$([%w_]+)(.*)$")

			if var_name then
				callable_atom = attach_line({var = var_name})
				amp_rest = var_rest
			end
		end

		if callable_atom then
			local rhs_call = {attach_line({amp = callable_atom})}
			local rest = trim(amp_rest)

			if rest == "" then
				return {op = op, left = lhs_atom, right = rhs_call}

			elseif rest:sub(1, 1) == "(" and rest:sub(-1) == ")" then
				local args_str = trim(rest:sub(2, -2))

				if args_str ~= "" then
					local positionals, kwargs = parse_call_args(args_str, "&(...)", true)

					for _, p in ipairs(positionals) do
						table.insert(rhs_call, p)
					end

					if #kwargs > 0 then
						table.insert(rhs_call, {kw = kwargs})
					end
				end

				return {op = op, left = lhs_atom, right = rhs_call}

			elseif type(callable_atom) == "table" and callable_atom.var then
				local positionals, kwargs = parse_call_args(rest, "&$var", false)

				for _, p in ipairs(positionals) do
					table.insert(rhs_call, p)
				end

				if #kwargs > 0 then
					table.insert(rhs_call, {kw = kwargs})
				end

				return {op = op, left = lhs_atom, right = rhs_call}
			end
		end
	end

	-- LHS | $obj.method(args) — method call with args. LHS prepends.
	local recv_sig, recv_name, recv_meth, recv_paren = rhs_str:match(
		"^([%$%%])([%w_]+)%.([%w_]+%??)%s*(%b())$")

	if recv_sig then
		local recv_atom = (recv_sig == "$") and {var = recv_name}
			or {sys = recv_name}
		local envelope = build_call_envelope(trim(recv_paren:sub(2, -2)), recv_meth, true)

		return {op = op, left = lhs_atom,
			right = dot_atom(recv_atom, recv_meth, envelope)}
	end

	-- LHS | $obj.method (bare) — bare method access.
	local recv_sig2, recv_name2, recv_meth2 = rhs_str:match(
		"^([%$%%])([%w_]+)%.([%w_]+%??)$")

	if recv_sig2 then
		local recv_atom2 = (recv_sig2 == "$") and {var = recv_name2}
			or {sys = recv_name2}
		return {op = op, left = lhs_atom,
			right = dot_atom(recv_atom2, recv_meth2)}
	end

	error("transpile: pipe RHS must be a call — got: " .. rhs_str)
end

--[[
{
	"in":  "string — a single Caspian statement, already trimmed and comment-stripped",
	"out": "one CaspianJ statement row",
	"shapes": [
		"$name = <literal>              -> ['scope', 'setvar', name, expr]",
		"$name OP= <expr>               -> ['scope', 'setvar_op', op, name, expr]",
		"$recv[key] = <expr>            -> [{var = recv}, '[]=', {args = [key_expr, value_expr]}]",
		"$recv.attr = <expr>            -> [{var = recv}, 'attr=', {args = [value_expr]}]",
		"&name                          -> [{amp = name}]",
		"&name arg [, arg ...]          -> [{amp = name}, arg_expr, ...]",
		"&name(arg [, arg...])          -> [{amp = name}, arg_expr, ...]",
		"$recv[key] / %recv[key]        -> [recv_expr, '[]', {args = [key_expr]}]",
		"$recv.method(args) / %recv...  -> [recv_expr, method, {args = [...]}]",
		"$recv.method args / %recv...   -> [recv_expr, method, {args = [...]}]",
		"$recv.method / %recv.method    -> [recv_expr, method]"
	],
	"note": "recv_expr is {var = name} for the $ sigil and {sys = name} for the % sigil"
}
]]
local function transpile_statement(stmt)
	-- Assignment has the LOWEST precedence. If the statement is a
	-- `$name [OP]= EXPR` / `$name++` / `$name--` form, the outermost shape
	-- is the assignment — any operator split must happen INSIDE the RHS. So
	-- we detect the assignment-head and skip the LOOSER_THAN_PIPE / pipe
	-- splits in that case; the assignment matchers further down produce the
	-- correct statement row with the RHS parsed as an expression.
	local looks_like_assignment =
		stmt:match("^%$[%w_]+%s*%+%+$")
		or stmt:match("^%$[%w_]+%s*%-%-$")
		or stmt:match("^%$[%w_]+%s*[%+%-%*%/%%|&]*=[^=]")

	-- Statement-level: logical connectives (`or`, `and`, `||`, `&&`) bind LOOSER
	-- than the pipe. Handled here so `&foo | &bar || &gup` groups as
	-- `(&foo | &bar) || &gup` (fallback pattern), not as `&foo | (&bar || &gup)`
	-- (which would be an invalid pipe RHS). Guarded by pcall: if the LHS
	-- doesn't parse as an expression (because the statement is actually a
	-- non-expression form), fall through to the other statement patterns.
	if not looks_like_assignment then
		local LOOSER_THAN_PIPE = {" or ", " and ", "||", "&&"}

		for _, op in ipairs(LOOSER_THAN_PIPE) do
			local pos = find_top_level(stmt, op)

			if pos then
				local left_str = trim(stmt:sub(1, pos - 1))
				local right_str = trim(stmt:sub(pos + #op))

				if left_str ~= "" and right_str ~= "" then
					local ok_l, left = pcall(parse_expression, left_str)
					local ok_r, right = pcall(parse_expression, right_str)

					if ok_l and ok_r then
						return {{op = trim(op), left = left, right = right}}
					end
				end
			end
		end
	end

	-- Statement-level pipe: same guard as LOOSER_THAN_PIPE above.
	if not looks_like_assignment then
		local pipe_pos = find_last_top_level_pipe(stmt)

		if pipe_pos then
			local is_null_safe = stmt:sub(pipe_pos + 1, pipe_pos + 1) == "&"
			local op_len = is_null_safe and 2 or 1
			local lhs_str = trim(stmt:sub(1, pipe_pos - 1))
			local rhs_str = trim(stmt:sub(pipe_pos + op_len))

			if lhs_str ~= "" and rhs_str ~= "" then
				local ok, atom = pcall(function()
					return desugar_pipe(parse_expression(lhs_str), rhs_str,
						is_null_safe and "|&" or "|")
				end)

				if ok then
					return {atom}
				end
			end
		end
	end

	-- Return statement — bare `return` or `return EXPR`. Distinct from
	-- `%call.return X` (which is preserved as an ordinary method-call shape by
	-- the method-call patterns further down). Two forms:
	--   `return`         -> ["scope", "return"]                (2 elements)
	--   `return EXPR`    -> ["scope", "return", expr]          (3 elements)
	-- The two-element form preserves the "no value" case as distinct from
	-- `return null` (which is 3 elements with an explicit {value: null}).
	if stmt == "return" then
		return {"scope", "return"}
	end

	local ret_val = stmt:match("^return%s+(.+)$")

	if ret_val then
		return {"scope", "return", parse_expression(trim(ret_val))}
	end

	-- Chained attribute assignment: recv(.name)+ = RHS
	--
	-- Handles single-segment ($obj.name = X) and multi-segment
	-- ($obj.a.b.c = X). The receiver of the setter is the get-chain of all
	-- segments except the last; the setter is `LAST=` applied to that chain.
	do
		local caa_recv, caa_after = consume_receiver(stmt)

		if caa_recv then
			local caa_segments, caa_tail = consume_dot_segments(caa_after)

			if caa_segments then
				local caa_rhs = caa_tail:match("^%s*=%s*(.-)$")

				if caa_rhs and caa_rhs ~= "" then
					local last = caa_segments[#caa_segments]
					local chain = caa_recv

					for i = 1, #caa_segments - 1 do
						chain = attach_line(dot_atom(chain, caa_segments[i]))
					end

					local last_name
					if type(last) == "string" then
						last_name = last .. "="
					else
						-- last is an atom (from `.$var`) — the setter method
						-- name lives inside its value. Attribute assignment
						-- via dynamic dispatch is rare; use the atom as-is.
						last_name = last
					end

					return {attach_line(dot_atom(chain, last_name,
						attach_line({args = {parse_expression(caa_rhs)}})))}
				end
			end
		end
	end

	local idx_sig, idx_recv, idx_key, idx_q, idx_val = stmt:match(
		"^([%$%%@])([%w_]+)%[(.-)%](%??)%s*=%s*(.-)$")

	if idx_sig and idx_recv and idx_val and idx_val ~= "" then
		-- Multi-key subscript: `$foo['a', 2, $x] = value` or `%bucket['k'] = v`
		-- or `@field['k'] = v` — all key expressions come first, value last.
		-- All go into one args list. A trailing `?` on the closing bracket
		-- switches to the null-safe method name. Receiver sigil dispatches:
		-- `$` → var atom, `%` → sys atom, `@` → at atom.
		local args_ast = {}
		local key_trimmed = trim(idx_key)

		if key_trimmed ~= "" then
			for _, arg in ipairs(split_top_level(key_trimmed, ",")) do
				local at = trim(arg)

				if at ~= "" then
					table.insert(args_ast, parse_expression(at))
				end
			end
		end

		table.insert(args_ast, parse_expression(idx_val))

		local method = (idx_q == "?") and "[]?=" or "[]="
		local recv
		if idx_sig == "$" then
			recv = {var = idx_recv}
		elseif idx_sig == "%" then
			recv = {sys = idx_recv}
		else
			recv = {at = idx_recv}
		end

		return {recv, method, {args = args_ast}}
	end

	-- `LHS <+ RHS` — append operator. Dispatches on the LHS's class. LHS can
	-- be any expression that resolves to a receiver (variable, subscript,
	-- property chain, etc.); RHS is any expression. The two-char `<+` token
	-- is treated atomically — `$x <+ 5` is append, not `$x < (+5)`.
	local ap_lhs, ap_rhs = stmt:match("^(.-)%s*<%+%s*(.+)$")

	if ap_lhs and ap_rhs and trim(ap_lhs) ~= "" and trim(ap_rhs) ~= "" then
		return {
			parse_expression(trim(ap_lhs)),
			"<+",
			{args = {parse_expression(trim(ap_rhs))}},
		}
	end

	-- `$name++` / `$name--` at statement position — emit value-atom-row
	-- `[{postinc: name}]` / `[{postdec: name}]`; row value discarded at
	-- statement position. Full CaspJ preserves source; norm may collapse
	-- to `setvar_op` (which itself collapses to plain `setvar`).
	local pi_name = stmt:match("^%$([%w_]+)%s*%+%+$")

	if pi_name then
		return {attach_line({postinc = pi_name})}
	end

	local pd_name = stmt:match("^%$([%w_]+)%s*%-%-$")

	if pd_name then
		return {attach_line({postdec = pd_name})}
	end

	for _, pair in ipairs(COMPOUND_OPS) do
		local op = pair[1]
		local pat = pair[2]
		local cn, cv = stmt:match("^%$([%w_]+)%s*" .. pat .. "=%s*(.-)$")

		if cn and cv and cv ~= "" then
			return {"scope", "setvar_op", op, cn, parse_expression(cv)}
		end
	end

	-- `$$foo = value` — varobj-slot reassignment. NOT a valid Caspian
	-- operation: a varobj IS the slot; there's no "replace the slot with
	-- a different varobj" semantics. Raise a specific error steering the
	-- author toward `$foo = value` (which reassigns the value the slot
	-- holds) instead of the generic `cannot parse` fallthrough.
	local dd_reassign = stmt:match("^%$%$([%w_]+)%s*=")

	if dd_reassign then
		error("transpile: cannot reassign varobj slot `$$" .. dd_reassign
			.. "` — use `$" .. dd_reassign
			.. " = ...` to reassign the value it holds")
	end

	local name, rhs = stmt:match("^%$([%w_]+)%s*=%s*(.-)$")

	if name and rhs and rhs ~= "" then
		return {"scope", "setvar", name, parse_expression(rhs)}
	end

	-- `@name = value` — class-field assignment. Parallel to setvar, distinct
	-- verb because the sigil is the LHS distinguisher.
	local at_assign_name, at_assign_rhs = stmt:match("^@([%w_]+)%s*=%s*(.-)$")

	if at_assign_name and at_assign_rhs and at_assign_rhs ~= "" then
		return {"scope", "setat", at_assign_name, parse_expression(at_assign_rhs)}
	end

	-- Generalized `&(EXPR)` at statement position — call the callable produced
	-- by EXPR. Mirrors the parse_expression branch. Args (parens or paren-less)
	-- may follow. Also handles `&$var args` and `&@field args`. Chain segments
	-- (`.method`, `[key]`, etc.) after the atom bind to the target under the
	-- dot-binds-tighter rule.
	do
		local callable_atom, amp_rest

		local paren_inner_stmt, paren_rest_stmt = stmt:match("^&(%b())(.*)$")

		if paren_inner_stmt then
			local inner = trim(paren_inner_stmt:sub(2, -2))

			if inner ~= "" then
				callable_atom = parse_expression(inner)
				amp_rest = paren_rest_stmt
			end
		else
			local var_name, var_rest = stmt:match("^&%$([%w_]+)(.*)$")

			if var_name then
				callable_atom = attach_line({var = var_name})
				amp_rest = var_rest
			else
				local at_name, at_rest = stmt:match("^&@([%w_]+)(.*)$")

				if at_name then
					callable_atom = attach_line({at = at_name})
					amp_rest = at_rest
				else
					-- `&foo.chain` at statement position — bareword amp with
					-- chain. Only fires when a chain follows; plain `&foo`
					-- (no chain) falls through to the bareword-amp path
					-- below.
					local bw_name, bw_rest = stmt:match("^&([%a_][%w_]*)(.*)$")

					if bw_name then
						local first = bw_rest:sub(1, 1)

						if first == "." or first == "[" then
							callable_atom = attach_line({bwc = bw_name})
							amp_rest = bw_rest
						end
					end
				end
			end
		end

		-- Extend the callable target with chain segments (dot access, subscript)
		-- if any follow. Under dot-binds-tighter, these bind to the target
		-- expression, not to the outer amp-call.
		if callable_atom and amp_rest and amp_rest ~= "" then
			local extended_atom, extended_rest = callable_atom, amp_rest
			local walked = false

			while extended_rest ~= "" do
				local m_name, m_paren, m_rest =
					extended_rest:match("^%.([%w_]+%??)%s*(%b())(.*)$")

				if m_name then
					local envelope = build_call_envelope(
						trim(m_paren:sub(2, -2)), m_name, true)
					extended_atom = attach_line(dot_atom(
						extended_atom, m_name, envelope))
					extended_rest = m_rest
					walked = true
					goto continue_amp_stmt_chain
				end

				local qm_open, qm_body, qm_close, qm_paren, qm_rest =
					extended_rest:match("^%.(['\"])(.-)(['\"])%s*(%b())(.*)$")

				if qm_open and qm_open == qm_close then
					local envelope = build_call_envelope(
						trim(qm_paren:sub(2, -2)), qm_body, true)
					extended_atom = attach_line(dot_atom(
						extended_atom, attach_line({v = qm_body}), envelope))
					extended_rest = qm_rest
					walked = true
					goto continue_amp_stmt_chain
				end

				local qb_open, qb_body, qb_close, qb_rest =
					extended_rest:match("^%.(['\"])(.-)(['\"])(.*)$")

				if qb_open and qb_open == qb_close then
					extended_atom = attach_line(dot_atom(
						extended_atom, attach_line({v = qb_body})))
					extended_rest = qb_rest
					walked = true
					goto continue_amp_stmt_chain
				end

				local sub_b, sub_q, sub_rest =
					extended_rest:match("^(%b[])(%??)(.*)$")

				if sub_b then
					local inner = trim(sub_b:sub(2, -2))
					local method = (sub_q == "?") and "[]?" or "[]"
					local args_ast = {}

					if inner ~= "" then
						for _, arg in ipairs(split_top_level(inner, ",")) do
							local at = trim(arg)

							if at ~= "" then
								table.insert(args_ast, parse_expression(at))
							end
						end
					end

					extended_atom = {extended_atom, method,
						attach_line({args = args_ast})}
					extended_rest = sub_rest
					walked = true
					goto continue_amp_stmt_chain
				end

				local a_name, a_rest =
					extended_rest:match("^%.([%w_]+%??)(.*)$")

				if a_name then
					extended_atom = attach_line(dot_atom(extended_atom, a_name))
					extended_rest = a_rest
					walked = true
					goto continue_amp_stmt_chain
				end

				break

				::continue_amp_stmt_chain::
			end

			if walked then
				callable_atom = extended_atom
				amp_rest = extended_rest
			end
		end

		if callable_atom then
			local stmt_ast = {{amp = callable_atom}}
			local rest = trim(amp_rest)
			local rest_bracketed = false

			if rest:sub(1, 1) == "(" and rest:sub(-1) == ")" then
				rest = trim(rest:sub(2, -2))
				rest_bracketed = true
			end

			if rest ~= "" then
				local ctx = (type(callable_atom) == "table" and callable_atom.var
					and not rest_bracketed) and "&$var" or "&(...)"
				local positionals, kwargs = parse_call_args(rest, ctx, rest_bracketed)

				for _, p in ipairs(positionals) do
					table.insert(stmt_ast, p)
				end

				if #kwargs > 0 then
					table.insert(stmt_ast, {kw = kwargs})
				end
			end

			return stmt_ast
		end
	end

	local bwc_name, tail = stmt:match("^&([%w_]+)%s*(.-)$")

	if bwc_name then
		local stmt_ast = {{amp = bwc_name}}
		local remainder = trim(tail)
		local remainder_bracketed = false

		if remainder:sub(1, 1) == "(" and remainder:sub(-1) == ")" then
			remainder = trim(remainder:sub(2, -2))
			remainder_bracketed = true
		end

		if remainder ~= "" then
			local positionals, kwargs = parse_call_args(remainder, bwc_name, remainder_bracketed)

			for _, p in ipairs(positionals) do
				table.insert(stmt_ast, p)
			end

			if #kwargs > 0 then
				table.insert(stmt_ast, {kw = kwargs})
			end
		end

		return stmt_ast
	end

	-- Subscript-get statement: $recv[key] or %recv[key] (bare, no assignment).
	-- Optional trailing `?` switches to the null-safe method name.
	-- Uses %b[] so the pattern anchors correctly and doesn't need to guard
	-- against embedded ']' inside the key expression.
	local sub_sig, sub_recv, sub_bracket, sub_q = stmt:match(
		"^([%$%%])([%w_]+)(%b[])(%??)$")

	if sub_sig and sub_recv and sub_bracket then
		local inner = trim(sub_bracket:sub(2, -2))

		if inner == "" then
			error("transpile: cannot parse subscript with empty key: " .. stmt)
		end

		local recv_expr = (sub_sig == "$") and {var = sub_recv} or {sys = sub_recv}
		local args_ast = {}

		for _, arg in ipairs(split_top_level(inner, ",")) do
			local at = trim(arg)

			if at ~= "" then
				table.insert(args_ast, parse_expression(at))
			end
		end

		local method = (sub_q == "?") and "[]?" or "[]"

		return {recv_expr, method, {args = args_ast}}
	end

	-- Method-call receiver patterns accept both `$var` and `%sys` receivers via
	-- the [%$%%] character class. Dispatch on the captured sigil to build the
	-- receiver expression ({var} vs {sys}). Kwargs / splats route through the
	-- shared parse_call_args helper via build_call_envelope.
	local mc_sig, mc_recv, mc_method, mc_paren = stmt:match(
		"^([%$%%])([%w_]+)%.([%w_]+%??)%s*(%b())$")

	if mc_sig and mc_recv then
		local recv_expr = (mc_sig == "$") and {var = mc_recv} or {sys = mc_recv}
		local envelope = build_call_envelope(trim(mc_paren:sub(2, -2)), mc_method, true)

		return {attach_line(dot_atom(recv_expr, mc_method, envelope))}
	end

	-- Object-as-method call, parens form: recv.$callable_var(args). Method
	-- position holds a value-atom instead of a bareword string.
	local sv_sig, sv_recv, sv_var, sv_paren = stmt:match(
		"^([%$%%])([%w_]+)%.%$([%w_]+)%s*(%b())$")

	if sv_sig and sv_recv then
		local recv_expr = (sv_sig == "$") and {var = sv_recv} or {sys = sv_recv}
		local envelope = build_call_envelope(trim(sv_paren:sub(2, -2)), sv_var, true)

		return {attach_line(dot_atom(recv_expr,
			attach_line({var = sv_var}), envelope))}
	end

	local mc2_sig, mc2_recv, mc2_method, mc2_tail = stmt:match(
		"^([%$%%])([%w_]+)%.([%w_]+%??)%s+(.-)$")

	if mc2_sig and mc2_recv and mc2_tail and mc2_tail ~= "" then
		local recv_expr = (mc2_sig == "$") and {var = mc2_recv} or {sys = mc2_recv}
		local envelope = build_call_envelope(trim(mc2_tail), mc2_method, false)

		return {attach_line(dot_atom(recv_expr, mc2_method, envelope))}
	end

	-- Object-as-method call, paren-less form: recv.$callable_var arg1, arg2.
	local sv2_sig, sv2_recv, sv2_var, sv2_tail = stmt:match(
		"^([%$%%])([%w_]+)%.%$([%w_]+)%s+(.-)$")

	if sv2_sig and sv2_recv and sv2_tail and sv2_tail ~= "" then
		local recv_expr = (sv2_sig == "$") and {var = sv2_recv} or {sys = sv2_recv}
		local envelope = build_call_envelope(trim(sv2_tail), sv2_var, false)

		return {attach_line(dot_atom(recv_expr,
			attach_line({var = sv2_var}), envelope))}
	end

	-- Chained attribute access / bare method access as statement:
	-- recv(.name)+ with no args, no parens, no assignment. Handles
	-- single-segment ($obj.name) and multi-segment ($obj.a.b.c). Also
	-- allows $$foo.value as a statement (a chain rooted at a varobj
	-- receiver). Emits a nested `.` binop-atom chain wrapped in a
	-- statement row.
	do
		local cba_recv, cba_after = consume_receiver(stmt)

		if cba_recv then
			local cba_segments, cba_tail = consume_dot_segments(cba_after)

			if cba_segments and cba_tail == "" then
				local chain = cba_recv

				for _, name in ipairs(cba_segments) do
					chain = attach_line(dot_atom(chain, name))
				end

				if chain == cba_recv then
					return chain
				end

				return {chain}
			end
		end
	end

	-- Bare varobj as statement: $$name
	local bare_vo = stmt:match("^%$%$([%w_]+)$")

	if bare_vo then
		return {{varobj = bare_vo}}
	end

	-- BWC-call statement (fallback). Bareword identifier at statement start,
	-- optionally followed by args. Covers class-body DSL commands (field,
	-- private, inherits, abstract) and any user-defined DSL BWC. Placed near
	-- the end so specific patterns (return, sigiled assigns, method calls,
	-- etc.) get first crack.
	-- Bareword name pattern requires letter/underscore start — a leading
	-- digit means this isn't a bareword-command call. Numeric expressions
	-- like `1(2)` fall through to the expression fallback at the end
	-- of transpile_statement.
	local bwc_paren_name, bwc_paren = stmt:match("^([%a_][%w_]*)%s*(%b())$")

	if bwc_paren_name then
		local inner = trim(bwc_paren:sub(2, -2))
		local stmt_ast = {{bwc = bwc_paren_name}}

		if inner ~= "" then
			for _, arg in ipairs(split_top_level(inner, ",")) do
				local at = trim(arg)

				if at ~= "" then
					table.insert(stmt_ast, parse_expression(at))
				end
			end
		end

		return stmt_ast
	end

	-- Bareword setter call: `foo = 'bar'` is a BWC named `foo=` with one arg.
	-- Symmetric with `.name = X` becoming a `.name=` method call. What the DSL
	-- does with it (attribute set, config binding, etc.) is a runtime concern;
	-- the parser just records the BWC. `==` in the tail does NOT match (that's
	-- the equality operator).
	local bwc_set_name, bwc_set_rhs = stmt:match("^([%a_][%w_]*)%s*=%s*([^=].*)$")

	if bwc_set_name and not RESERVED_FOR_BWC_EXPR[bwc_set_name] then
		local rhs_atom = parse_expression(trim(bwc_set_rhs))
		return {attach_line({bwc = bwc_set_name .. "="}), rhs_atom}
	end

	-- Bareword name pattern requires letter/underscore start — same reason
	-- as bwc_paren_name above. `1 + 2` would otherwise match with
	-- name="1", tail="+ 2" and fail trying to parse "+ 2" as call args.
	local bwc_stmt_name, bwc_stmt_tail = stmt:match("^([%a_][%w_]*)%s+(.+)$")

	if bwc_stmt_name and bwc_stmt_tail and not bwc_stmt_tail:match("^=[^=]") then
		local stmt_ast = {{bwc = bwc_stmt_name}}
		local positionals, kwargs = parse_call_args(bwc_stmt_tail, bwc_stmt_name, false)

		for _, p in ipairs(positionals) do
			table.insert(stmt_ast, p)
		end

		if #kwargs > 0 then
			table.insert(stmt_ast, {kw = kwargs})
		end

		return stmt_ast
	end

	-- Bare-identifier statements now fall through to the expression
	-- fallback at the end. A previous `bwc_bare = stmt:match("^([%w_]+)$")`
	-- pattern here matched a bare identifier or number and produced
	-- `{bwc: name}` — but that pattern also matched pure-digit tokens
	-- (`1`, `42`) and boolean-word tokens (`true`, `false`), classifying
	-- them as bareword commands instead of value literals. Removing the
	-- pattern lets parse_expression handle them uniformly via
	-- parse_literal (value literals → `{value: X}`) or its own bare-ident
	-- path (real bareword commands like `puts` → `{bwc: name}`).

	-- Receiver-tail fallback: handles receivers that the earlier sigil+identifier
	-- patterns don't match — chiefly the `%[url]` puck atom, subscript-then-
	-- method chains like `%puck[url].method()`, and multi-step method chains
	-- like `$foo.bar().gup('baz').baz`. Walks the tail left-to-right, wrapping
	-- one segment at a time. Segment types: `.name(args)` (method call with
	-- envelope), `.name` (bare attribute), `[key]` (subscript). Leading
	-- whitespace between segments is trimmed, so multi-line chains
	-- (`.gup()` on a fresh line) work the same as single-line.
	--
	-- Bareword-then-chain (`foo.bar`, `foo['k']`, ...) also enters here: `foo`
	-- is a bwc atom (a DSL may resolve it at runtime); the chain segments then
	-- act on the returned value. Only kicks in when the tail actually starts a
	-- chain — bare `foo` alone stays a plain bwc call handled above.
	do
		local rt_recv, rt_after = consume_receiver(stmt)

		if not rt_recv then
			local bw_name, bw_rest = stmt:match("^([%a_][%w_]*)(.*)$")

			if bw_name and not RESERVED_FOR_BWC_EXPR[bw_name] then
				local first = bw_rest:sub(1, 1)

				if first == "." or first == "[" then
					rt_recv = attach_line({bwc = bw_name})
					rt_after = bw_rest
				end
			end
		end

		if rt_recv then
			local current = rt_recv
			local tail = trim(rt_after)
			local parsed_ok = true

			while tail ~= "" do
				-- Method-position amp-call: `.&NAME(inner_args) [outer_args?]`.
				-- The amp-call row becomes `right:` of the dot binop; any args
				-- after become the outer dot's `args:` — parens form
				-- `.&NAME(inner)(outer)` or paren-less `.&NAME(inner) outer`.
				local dot_amp_name, dot_amp_paren, dot_amp_rest =
					tail:match("^%.&([%a_][%w_]*)%s*(%b())(.*)$")

				if dot_amp_name then
					local amp_row = {attach_line({amp = dot_amp_name})}
					local inner = trim(dot_amp_paren:sub(2, -2))

					if inner ~= "" then
						local positionals, kwargs = parse_call_args(
							inner, dot_amp_name, true)

						for _, p in ipairs(positionals) do
							table.insert(amp_row, p)
						end

						if #kwargs > 0 then
							table.insert(amp_row, {kw = kwargs})
						end
					end

					-- Peek for outer args after the amp-call.
					local outer_env, outer_rest = nil, dot_amp_rest
					local outer_trim = trim(dot_amp_rest)
					local outer_paren, outer_paren_rest =
						outer_trim:match("^(%b())(.*)$")

					if outer_paren then
						local outer_inner = trim(outer_paren:sub(2, -2))

						if outer_inner == "" then
							outer_env = attach_line({args = {}})
						else
							local positionals, kwargs = parse_call_args(
								outer_inner, "outer", true)
							outer_env = attach_line({args = positionals})

							if #kwargs > 0 then
								outer_env.kw = kwargs
							end
						end

						outer_rest = outer_paren_rest
					elseif outer_trim ~= "" and outer_trim:sub(1, 1) ~= "."
							and outer_trim:sub(1, 1) ~= "[" then
						-- Paren-less outer args: `.&NAME(inner) 1, 2, 3` at
						-- statement position. pcall to fall through if the
						-- tail isn't actually args.
						local ok, positionals, kwargs = pcall(parse_call_args,
							outer_trim, "outer", false)

						if ok then
							outer_env = attach_line({args = positionals})

							if #kwargs > 0 then
								outer_env.kw = kwargs
							end

							outer_rest = ""
						end
					end

					current = attach_line(dot_atom(current, amp_row, outer_env))
					tail = trim(outer_rest)
					goto continue_chain
				end

				-- Method-position parenthesized expression:
				-- `.(EXPR) [outer_args?]`. Same shape as `.&NAME(inner)` but
				-- with an arbitrary expression as `right:`. Distinguished
				-- from subscript (`[key]`) by matching `.(` first.
				local dot_paren_expr, dot_paren_rest =
					tail:match("^%.(%b())(.*)$")

				if dot_paren_expr then
					local inner = trim(dot_paren_expr:sub(2, -2))

					if inner ~= "" then
						local right_expr = parse_expression(inner)
						local outer_env, outer_rest = nil, dot_paren_rest
						local outer_trim = trim(dot_paren_rest)
						local outer_paren, outer_paren_rest =
							outer_trim:match("^(%b())(.*)$")

						if outer_paren then
							local outer_inner = trim(outer_paren:sub(2, -2))

							if outer_inner == "" then
								outer_env = attach_line({args = {}})
							else
								local positionals, kwargs = parse_call_args(
									outer_inner, "outer", true)
								outer_env = attach_line({args = positionals})

								if #kwargs > 0 then
									outer_env.kw = kwargs
								end
							end

							outer_rest = outer_paren_rest
						elseif outer_trim ~= "" and outer_trim:sub(1, 1) ~= "."
								and outer_trim:sub(1, 1) ~= "[" then
							local ok, positionals, kwargs = pcall(parse_call_args,
								outer_trim, "outer", false)

							if ok then
								outer_env = attach_line({args = positionals})

								if #kwargs > 0 then
									outer_env.kw = kwargs
								end

								outer_rest = ""
							end
						end

						current = attach_line(dot_atom(current, right_expr, outer_env))
						tail = trim(outer_rest)
						goto continue_chain
					end
				end

				-- Method call: `.name(args)` — envelope carries kwargs /
				-- splats. Emits a `.` binop atom.
				local m_name, m_paren, m_rest =
					tail:match("^%.([%w_]+%??)%s*(%b())(.*)$")

				if m_name then
					local envelope = build_call_envelope(
						trim(m_paren:sub(2, -2)), m_name, true)

					current = attach_line(dot_atom(current, m_name, envelope))
					tail = trim(m_rest)
					goto continue_chain
				end

				-- Method call with quoted-string method name: `.'name'(args)`
				-- or `."name"(args)`. `right` is a `{v: NAME}` value atom.
				-- Bareword-after-dot and quoted-string-after-dot normalize
				-- to the same shape.
				local qm_open, qm_body, qm_close, qm_paren, qm_rest =
					tail:match("^%.(['\"])(.-)(['\"])%s*(%b())(.*)$")

				if qm_open and qm_open == qm_close then
					local envelope = build_call_envelope(
						trim(qm_paren:sub(2, -2)), qm_body, true)
					local right_atom = attach_line({v = qm_body})

					current = attach_line(dot_atom(current, right_atom, envelope))
					tail = trim(qm_rest)
					goto continue_chain
				end

				-- Bare quoted-string method access: `.'name'` (no parens).
				local qb_open, qb_body, qb_close, qb_rest =
					tail:match("^%.(['\"])(.-)(['\"])(.*)$")

				if qb_open and qb_open == qb_close then
					local right_atom = attach_line({v = qb_body})

					current = attach_line(dot_atom(current, right_atom))
					tail = trim(qb_rest)
					goto continue_chain
				end

				-- Subscript: `[key]` — positional-only (data-access shape,
				-- not a call). Kept in row form because the source doesn't
				-- use dot syntax.
				local sub_b, sub_rest = tail:match("^(%b[])(.*)$")

				if sub_b then
					local inner = trim(sub_b:sub(2, -2))
					local args_ast = {}

					if inner ~= "" then
						for _, arg in ipairs(split_top_level(inner, ",")) do
							local at = trim(arg)

							if at ~= "" then
								table.insert(args_ast, parse_expression(at))
							end
						end
					end

					current = {current, "[]", {args = args_ast}}
					tail = trim(sub_rest)
					goto continue_chain
				end

				-- Bare attribute: `.name` (no parens).
				local a_name, a_rest = tail:match("^%.([%w_]+%??)(.*)$")

				if a_name then
					current = attach_line(dot_atom(current, a_name))
					tail = trim(a_rest)
					goto continue_chain
				end

				-- Nothing matched — leave the chain fallback and let the
				-- outer error fire.
				parsed_ok = false
				break

				::continue_chain::
			end

			if parsed_ok then
				if current == rt_recv then
					return {rt_recv}
				end

				-- The chain became a `.` binop atom (or a row-form
				-- subscript). If it's an atom, wrap in a statement row.
				if type(current) == "table" and current[1] == nil then
					return {current}
				end

				return current
			end
		end
	end

	-- Expression fallback. If no statement-shape pattern matched, try
	-- parsing the whole thing as an expression. If it parses, wrap the
	-- resulting atom as a one-atom statement row. Under the "every
	-- command produces an rv" model, any parseable expression is a
	-- legal command (its rv is the expression's value).
	--
	-- Covers `'foo'` (bare string literal), `1` / `true` / `false` (value
	-- literals — previously misclassified as `{bwc: X}` by the removed
	-- bwc_bare pattern), and anything else parse_expression can parse
	-- that no earlier statement-shape pattern claimed.
	local ok, atom = pcall(parse_expression, stmt)

	if ok and atom ~= nil then
		-- parse_expression may return a table shaped either as a value
		-- atom (hash) or as a row (positional array). Wrap atoms in a
		-- row; leave rows as-is.
		if type(atom) == "table" and atom[1] ~= nil then
			return atom
		end

		return {atom}
	end

	error("transpile: cannot parse: " .. stmt)
end

--[[
{
	"in":  "string (a single Caspian chunk that may or may not be a chained assignment), table (result accumulator)",
	"out": "true if the chunk was a chained assignment (rows already appended to result); false otherwise",
	"note": "$x = $y = $z = $j — rightmost is the source; each target gets the previous target's value. Emits setvars from rightmost target to leftmost so runtime evaluation order matches the right-associative reading."
}
]]
local function try_chained_assignment(chunk, result)
	local names = {}

	for name in chunk:gmatch("%$([%w_]+)") do
		table.insert(names, name)
	end

	if #names < 2 then
		return false
	end

	-- Build a canonical pattern: %$name1 %s*=%s* %$name2 %s*=%s* ... %$nameN
	-- and verify the chunk matches it exactly (aside from whitespace). This
	-- rejects juxtapositions like "$a = 1 $b = 2" because non-$ content
	-- (the "1", "2") won't fit the interleaved-equals shape.
	local parts = {"^%s*%$" .. names[1]}

	for i = 2, #names do
		table.insert(parts, "%s*=%s*%$" .. names[i])
	end

	table.insert(parts, "%s*$")

	local canonical = table.concat(parts, "")

	if not chunk:match(canonical) then
		return false
	end

	local n = #names

	for i = n - 1, 1, -1 do
		table.insert(result, {"scope", "setvar", names[i], {var = names[i + 1]}})
	end

	return true
end

--[[
{
	"in":  "string (code portion of a source line — comment already stripped), table (result accumulator)",
	"out": "nothing; appends CaspianJ statement rows onto result",
	"handles": [
		"semicolons within the chunk separate statements",
		"chained assignment ($x = $y = $z = $j) — rightmost is source, chain-through targets",
		"juxtaposition ($a = 1 $b = 2) — recognized for assignment chunks",
		"leading/trailing/collapsed semicolons are silently ignored"
	]
}
]]
local function process_code_chunk(code, result)
	local trimmed_code = trim(code)

	if trimmed_code == "" then
		return
	end

	for chunk in trimmed_code:gmatch("[^;]+") do
		local chunk_trimmed = trim(chunk)

		if chunk_trimmed ~= "" then
			if try_chained_assignment(chunk_trimmed, result) then
				-- handled

			else
				-- Try the whole chunk as one statement first. When the chunk is a
				-- valid single assignment (even with $names on the RHS, as in
				-- "$eq = ($a == $b)"), this succeeds and we're done. The juxtaposition
				-- splitter only fires when this fails — that keeps the naive
				-- "split at $name =" regex from misfiring on nested $-references.
				local ok, stmt_ast = pcall(transpile_statement, chunk_trimmed)

				if ok then
					table.insert(result, stmt_ast)

				elseif chunk_trimmed:match("^%$[%w_]+%s*=") then
					for stmt in chunk_trimmed:gmatch("%$[%w_]+%s*=%s*[^%$]*") do
						local stmt_trimmed = trim(stmt)

						if stmt_trimmed ~= "" then
							table.insert(result, transpile_statement(stmt_trimmed))
						end
					end

				else
					table.insert(result, transpile_statement(chunk_trimmed))
				end
			end
		end
	end
end

--[==[
{
	"in":   {"source": "string"},
	"out":  "Lua table (CaspianJ)",
	"handles": [
		"empty / whitespace-only source -> []",
		"whole-line and end-of-line # comments -> {comment = text}",
		"%documentation <<EOF ... EOF -> {documentation = body}",
		"%vibecode <<EOF ... EOF -> {vibecode = body}",
		"assignment, bare-word call (with or without args, with or without parens), method call",
		"semicolons, newlines, and juxtaposition as statement separators"
	],
	"note": "line-by-line state machine. Naive # detection — does not respect # inside string literals. Only <<EOF terminators recognized; typed / quoted heredoc variants deferred."
}
]==]
-- Construct tokenizer + stack-based parser.
--
-- Handles `while`, `until`, `begin`, `end` as block keywords and `before`,
-- `between`, `after`, `noloop` as begin-clause markers. Everything else is
-- content that transpiles as a regular statement via process_code_chunk.
--
-- Indent has no effect. Disambiguation of `while COND` (opener vs do-while
-- closer for a preceding begin) is stack-based: if the stack top is a `begin`,
-- the incoming `while COND` closes it; otherwise it opens a new while-end.
--
-- Respects single-/double-quoted strings and bracket nesting so keyword
-- lookups don't fire inside string literals or expression groups.

local CONSTRUCT_KEYWORDS = {
	["while"]    = true, ["until"]   = true,
	["begin"]    = true, ["end"]     = true,
	["if"]       = true, ["unless"]  = true,
	["elsif"]    = true, ["elseif"]  = true, ["else"] = true,
	["function"] = true, ["closure"] = true, ["method"] = true,
	["class"]    = true, ["amend"]   = true, ["instance"] = true,
	["do"]       = true, ["dofunc"]  = true,
}
local CONSTRUCT_CLAUSES  = {["before"] = true, ["between"] = true, ["after"] = true, ["noloop"] = true, ["ensure"] = true}

-- Keywords that require an expression after them (cond for while/if/etc.,
-- target for amend).
local COND_KEYWORDS = {
	["while"] = true, ["until"] = true,
	["if"] = true, ["unless"] = true,
	["elsif"] = true, ["elseif"] = true,
	["amend"] = true,
}

-- Keywords that require a signature (`&name(params)` or `(params)`) after them.
local SIG_KEYWORDS = {
	["function"] = true, ["closure"] = true, ["method"] = true,
}

-- Scan `s` starting at position `start_i` and return the end position of the
-- content run — everything up to the next keyword, clause marker, or `#`
-- comment (respecting quotes and bracket nesting), or #s + 1 if none is found.
local function scan_content_end(s, start_i)
	local i = start_i
	local len = #s

	while i <= len do
		local c = s:sub(i, i)

		if c == "#" then
			return i

		elseif c == "'" or c == '"' then
			local q = c
			i = i + 1

			while i <= len do
				local d = s:sub(i, i)

				if d == q then
					if q == "'" and i + 1 <= len and s:sub(i + 1, i + 1) == "'" then
						i = i + 2
					else
						i = i + 1
						break
					end
				else
					i = i + 1
				end
			end

		elseif c == "(" or c == "[" or c == "{" then
			local depth = 1
			i = i + 1

			while i <= len and depth > 0 do
				local d = s:sub(i, i)

				if d == "'" or d == '"' then
					local q = d
					i = i + 1

					while i <= len and s:sub(i, i) ~= q do
						i = i + 1
					end

					if i <= len then
						i = i + 1
					end

				elseif d == "(" or d == "[" or d == "{" then
					depth = depth + 1
					i = i + 1

				elseif d == ")" or d == "]" or d == "}" then
					depth = depth - 1
					i = i + 1

				else
					i = i + 1
				end
			end

		elseif c:match("%s") then
			local save = i
			local has_newline = c == "\n"
			local j = i + 1

			while j <= len and s:sub(j, j):match("%s") do
				if s:sub(j, j) == "\n" then
					has_newline = true
				end

				j = j + 1
			end

			if j > len then
				return save
			end

			local next_c = s:sub(j, j)

			if next_c == "#" then
				return save
			end

			-- Trailing-pipe / trailing-comma continuation: if the content just
			-- before the whitespace run ends with `|`, `|&`, or `,`, the
			-- statement continues on the next line and we don't split. Covers
			-- `$r = &foo |\n\t&bar`, `$s = &foo |&\n\t&bar`, and paren-less
			-- multi-line arg lists like `&foo 'x',\n\t&bar`. `||` and `&&`
			-- are logical connectives, not pipes — those don't continue lines
			-- this way, so we exclude by checking the char two positions back.
			-- A bare trailing comma at end-of-input (nothing to continue into)
			-- is left for parse_call_args to reject as a syntax error.
			if has_newline and i > 1 then
				local prev = s:sub(i - 1, i - 1)

				if prev == "|" then
					local prev2 = i > 2 and s:sub(i - 2, i - 2) or ""

					if prev2 ~= "|" then
						goto continue_scan_no_split
					end

				elseif prev == "&" and i > 2 and s:sub(i - 2, i - 2) == "|" then
					goto continue_scan_no_split

				elseif prev == "," then
					goto continue_scan_no_split
				end
			end

			-- `|` at the start of a new line begins a pipe statement — split here.
			if next_c == "|" and has_newline then
				return save
			end

			-- A sigil (`$`, `%`, `&`, `@`) at the start of a new line starts a
			-- new statement — split here. Newlines within a single statement's
			-- expression (like `$x + \n1`) don't have a sigil at line start so
			-- they aren't split.
			if has_newline and
				(next_c == "$" or next_c == "%" or next_c == "&" or next_c == "@")
			then
				return save
			end

			::continue_scan_no_split::

			if next_c:match("[%w_]") then
				local wstart = j
				local wend = j

				while wend <= len and s:sub(wend, wend):match("[%w_]") do
					wend = wend + 1
				end

				local w = s:sub(wstart, wend - 1)

				-- Word IMMEDIATELY followed by `:` is a kwarg key, not a
				-- keyword usage. E.g., `class: 'string'` inside a BWC arg
				-- list. The `:` must be adjacent to the word (no space) to
				-- avoid misreading `field :age` (a bareword call with a
				-- symbol arg) as a kwarg key.
				local is_kwarg_key = wend <= len and s:sub(wend, wend) == ":"
					and s:sub(wend + 1, wend + 1) ~= ":"

				if (CONSTRUCT_KEYWORDS[w] or CONSTRUCT_CLAUSES[w]) and not is_kwarg_key then
					return save
				end

				-- Bareword-BWC at newline boundary starts a new statement.
				-- Covers class-body DSL commands (`field :x` on a line, then
				-- `field :y` on the next), any user-defined DSL BWC, and
				-- undecorated identifiers at expression position. Not split
				-- when the word is a kwarg key (`class:`) since that's part
				-- of an ongoing arg list. Not split absent a newline — same
				-- line `foo bar` is a bareword call with `bar` as arg.
				if has_newline and not is_kwarg_key then
					return save
				end

				i = wend
			else
				i = j
			end

		else
			i = i + 1
		end
	end

	return len + 1
end

-- Like scan_content_end, but for cond scanning: SKIPS `#…\n` comments (as
-- whitespace) instead of stopping at them. Still stops at keywords/clause
-- markers and respects strings/bracket nesting. Bounds a cond-reading pass
-- so it doesn't reach into subsequent constructs and drag in their comments.
local function scan_cond_end(s, start_i)
	local i = start_i
	local len = #s

	while i <= len do
		local c = s:sub(i, i)

		if c == "'" or c == '"' then
			local q = c
			i = i + 1

			while i <= len do
				local d = s:sub(i, i)

				if d == q then
					if q == "'" and i + 1 <= len and s:sub(i + 1, i + 1) == "'" then
						i = i + 2
					else
						i = i + 1
						break
					end
				else
					i = i + 1
				end
			end

		elseif c == "(" or c == "[" or c == "{" then
			local depth = 1
			i = i + 1

			while i <= len and depth > 0 do
				local d = s:sub(i, i)

				if d == "'" or d == '"' then
					local q = d
					i = i + 1

					while i <= len and s:sub(i, i) ~= q do
						i = i + 1
					end

					if i <= len then
						i = i + 1
					end

				elseif d == "(" or d == "[" or d == "{" then
					depth = depth + 1
					i = i + 1

				elseif d == ")" or d == "]" or d == "}" then
					depth = depth - 1
					i = i + 1

				else
					i = i + 1
				end
			end

		elseif c == "#" then
			while i <= len and s:sub(i, i) ~= "\n" do
				i = i + 1
			end

			if i <= len then
				i = i + 1
			end

		elseif c:match("%s") then
			local save = i
			local j = i + 1

			while j <= len and s:sub(j, j):match("%s") do
				j = j + 1
			end

			if j > len then
				return save
			end

			local next_c = s:sub(j, j)

			if next_c == "#" then
				i = j
			elseif next_c:match("[%w_]") then
				local wstart = j
				local wend = j

				while wend <= len and s:sub(wend, wend):match("[%w_]") do
					wend = wend + 1
				end

				local w = s:sub(wstart, wend - 1)

				-- Word followed by `:` (with optional whitespace) is a kwarg
				-- key, not a keyword usage. E.g., `class: 'string'` inside a
				-- BWC arg list — `class` there is a kwarg key, not the class
				-- block opener.
				local after_w = wend
				while after_w <= len and s:sub(after_w, after_w):match(" ") do
					after_w = after_w + 1
				end
				local is_kwarg_key = after_w <= len and s:sub(after_w, after_w) == ":"
					and s:sub(after_w + 1, after_w + 1) ~= ":"

				if (CONSTRUCT_KEYWORDS[w] or CONSTRUCT_CLAUSES[w]) and not is_kwarg_key then
					return save
				end

				i = wend
			else
				i = j
			end

		else
			i = i + 1
		end
	end

	return len + 1
end

-- Read the cond after a cond keyword (if / while / until / elsif / …). Uses
-- longest-valid-parseable-prefix — advance through the source char by char,
-- building a comment-stripped candidate, and after each advance try to parse
-- the candidate. The longest one that succeeds is the cond. Comments (`#…\n`)
-- within the cond are stripped from the candidate (replaced by a space) and
-- returned as separate comment tokens for the caller to emit around the cond
-- token — this way comments preserved but the cond expression itself remains
-- a clean expression parse_expression can handle.
--
-- Newline-agnostic, indent-agnostic. Bound only by end-of-source; the O(N²)
-- cost is a nonissue for cond sizes we see in practice.
--
-- Returns:
--   cond_string             — the comment-stripped best prefix, trimmed
--   position_after_cond     — 1-based index in source right after the cond
--   comments                — list of {type="comment", text=...} tokens
--                             encountered while scanning past the cond
-- or nil, nil, {} if no valid prefix parses.
local function read_cond_prefix(source, start_i)
	local search_end = scan_cond_end(source, start_i)
	local cleaned_parts = {}
	local pending_comments = {}
	local best_cleaned_len = 0
	local best_orig_end = nil
	local cleaned_len = 0
	local i = start_i
	local in_str = nil
	local len = search_end - 1

	while i <= len do
		local c = source:sub(i, i)

		if in_str then
			cleaned_parts[#cleaned_parts + 1] = c
			cleaned_len = cleaned_len + 1

			if c == in_str then
				if in_str == "'" and i + 1 <= len and source:sub(i + 1, i + 1) == "'" then
					cleaned_parts[#cleaned_parts + 1] = "'"
					cleaned_len = cleaned_len + 1
					i = i + 2
				else
					in_str = nil
					i = i + 1
				end
			else
				i = i + 1
			end

		elseif c == "'" or c == '"' then
			in_str = c
			cleaned_parts[#cleaned_parts + 1] = c
			cleaned_len = cleaned_len + 1
			i = i + 1

		elseif c == "#" then
			local start = i + 1

			while i <= len and source:sub(i, i) ~= "\n" do
				i = i + 1
			end

			table.insert(pending_comments,
				{type = "comment", text = trim(source:sub(start, i - 1))})

			if i <= len then
				i = i + 1
			end

			cleaned_parts[#cleaned_parts + 1] = " "
			cleaned_len = cleaned_len + 1

		else
			cleaned_parts[#cleaned_parts + 1] = c
			cleaned_len = cleaned_len + 1
			i = i + 1
		end

		local candidate = trim(table.concat(cleaned_parts))

		if candidate ~= "" then
			local ok = pcall(parse_expression, candidate)

			if ok then
				best_cleaned_len = cleaned_len
				best_orig_end = i
			end
		end
	end

	if not best_orig_end then
		return nil, nil, {}
	end

	local cond_str = trim(table.concat(cleaned_parts, "", 1, best_cleaned_len))
	return cond_str, best_orig_end, pending_comments
end

-- Skip whitespace, and while at a `#` comment, consume it and emit a comment
-- token into `tokens`. Advances i past all consecutive whitespace and comments.
local function skip_ws_and_collect_comments(source, i, tokens, base_line)
	local len = #source

	while true do
		while i <= len and source:sub(i, i):match("%s") do
			i = i + 1
		end

		if i > len or source:sub(i, i) ~= "#" then
			return i
		end

		local comment_start = i
		local start = i + 1

		while i <= len and source:sub(i, i) ~= "\n" do
			i = i + 1
		end

		local tok = {type = "comment", text = trim(source:sub(start, i - 1))}

		if base_line then
			local nl = 0

			for _ in source:sub(1, comment_start - 1):gmatch("\n") do
				nl = nl + 1
			end

			tok.line = base_line + nl
		end

		table.insert(tokens, tok)

		if i <= len then
			i = i + 1
		end
	end
end

-- Read a signature after `function` / `closure` / `method`:
--   sugar form:      `&name(params)` — records name, returns params list
--   anonymous form:  `(params)`       — no name, records params
-- Params are comma-separated `$name` tokens inside the parens; V1 supports
-- simple positional names only. Rich param decls (defaults, optional, splat,
-- hash_splat) are deferred.
--
-- Returns: name (string or nil), params (list of strings), position after `)`.
--[[
{
	"in":  "source (whole program), start_i (position immediately after a header — e.g. after a callable's `)` or after `begin` / a while-cond)",
	"out": "(as_name?, new_i) — as_name is the bareword captured after `as $` when present, nil otherwise; new_i skips past the binding when found, otherwise equals start_i",
	"note": "shared helper for `as $name` post-header bindings on callables (function / closure / method / do / dofunc), bare `begin`, `while` / `until` loops, and any future construct that accepts a controller slot. Only consumes when the next non-whitespace token is exactly `as $<word>`; anything else leaves start_i unchanged."
}
]]
local function read_optional_as_binding(source, start_i)
	local len = #source
	local i = start_i

	while i <= len and source:sub(i, i):match("[ \t]") do
		i = i + 1
	end

	local rest = source:sub(i)
	local prefix, name = rest:match("^(as%s+%$([%w_]+))")

	if prefix then
		return name, i + #prefix
	end

	return nil, start_i
end

local function read_signature(source, start_i, keyword_name)
	local len = #source
	local i = start_i

	while i <= len and source:sub(i, i):match("%s") do
		i = i + 1
	end

	local name = nil
	local receiver = nil

	if i <= len and source:sub(i, i) == "&" then
		local amp = source:sub(i + 1):match("^([%w_]+)")

		if not amp then
			error("transpile: `" .. keyword_name .. " &` with no name")
		end

		name = amp
		i = i + 1 + #amp

		while i <= len and source:sub(i, i):match("%s") do
			i = i + 1
		end

	elseif keyword_name == "method" and i <= len
		and (source:sub(i, i) == "$" or source:sub(i, i) == "%") then
		-- Singleton method: `method <receiver-expr>.name(...) ... end`. Receiver
		-- is a variable / sys / dot-chain; name is the last dot-segment.
		local sig_prefix = source:sub(i):match("^([%$%%][%w_]+[%w_%.]*)")

		if not sig_prefix then
			error("transpile: `" .. keyword_name .. "` with malformed receiver")
		end

		local recv_str, name_str = sig_prefix:match("^(.-)%.([%w_]+%??)$")

		if not recv_str or recv_str == "" or name_str == "" then
			error("transpile: `" .. keyword_name .. " " .. sig_prefix
				.. "` — expected `<receiver>.<name>` singleton form")
		end

		receiver = parse_expression(recv_str)
		name = name_str
		i = i + #sig_prefix

		while i <= len and source:sub(i, i):match("%s") do
			i = i + 1
		end

	elseif keyword_name == "method" and i <= len and source:sub(i, i):match("[%w_]") then
		-- `method` accepts a bareword name (no `&` sigil) as an alternative to
		-- `method &name`. `function` and `closure` still require the `&` sigil.
		local bareword = source:sub(i):match("^([%w_]+)")

		name = bareword
		i = i + #bareword

		while i <= len and source:sub(i, i):match("%s") do
			i = i + 1
		end
	end

	if i > len or source:sub(i, i) ~= "(" then
		error("transpile: expected `(` after `" .. keyword_name .. "`" ..
			(name and (" &" .. name) or "") .. " signature")
	end

	local depth = 1
	local paren_start = i + 1
	i = i + 1

	while i <= len and depth > 0 do
		local c = source:sub(i, i)

		if c == "(" then
			depth = depth + 1
		elseif c == ")" then
			depth = depth - 1
		end

		i = i + 1
	end

	if depth ~= 0 then
		error("transpile: unclosed `(` in `" .. keyword_name .. "` signature")
	end

	local params_str = source:sub(paren_start, i - 2)

	-- Walk `params_str` in one pass, splitting on top-level commas AND
	-- top-level `#…\n` comments so signature-level comments become `{comment}`
	-- entries interleaved in the params list. Comments inside a param's
	-- metadata hash (depth > 0) stay inside the metadata chunk — parse_hash
	-- handles those.
	local items = {}
	local buf = {}
	local pstr_in_str = nil
	local pstr_depth = 0
	local ci = 1
	local clen = #params_str

	local function flush_buf()
		local t = trim(table.concat(buf))

		if t ~= "" then
			table.insert(items, {kind = "content", text = t})
		end

		buf = {}
	end

	while ci <= clen do
		local c = params_str:sub(ci, ci)

		if pstr_in_str then
			table.insert(buf, c)

			if c == pstr_in_str then
				if pstr_in_str == "'"
					and ci + 1 <= clen
					and params_str:sub(ci + 1, ci + 1) == "'"
				then
					table.insert(buf, "'")
					ci = ci + 2
				else
					pstr_in_str = nil
					ci = ci + 1
				end
			else
				ci = ci + 1
			end

		elseif c == "'" or c == '"' then
			pstr_in_str = c
			table.insert(buf, c)
			ci = ci + 1

		elseif c == "(" or c == "[" or c == "{" then
			pstr_depth = pstr_depth + 1
			table.insert(buf, c)
			ci = ci + 1

		elseif c == ")" or c == "]" or c == "}" then
			pstr_depth = pstr_depth - 1
			table.insert(buf, c)
			ci = ci + 1

		elseif c == "#" and pstr_depth == 0 then
			flush_buf()
			local start = ci + 1

			while ci <= clen and params_str:sub(ci, ci) ~= "\n" do
				ci = ci + 1
			end

			table.insert(items, {
				kind = "comment",
				text = trim(params_str:sub(start, ci - 1)),
			})

		elseif c == "," and pstr_depth == 0 then
			flush_buf()
			ci = ci + 1

		else
			table.insert(buf, c)
			ci = ci + 1
		end
	end

	flush_buf()

	local params = {}

	for _, item in ipairs(items) do
		if item.kind == "comment" then
			table.insert(params, {comment = item.text})
		else
			local pt = item.text

			-- **$name — collect extra kwargs into this param. Optional
			-- metadata: `**$opts: {...}`. Checked BEFORE `*` since `**` is
			-- longer and would otherwise be partially consumed.
			local kw_name, kw_meta = pt:match("^%*%*%$([%w_]+):%s*(%b{})$")

			if not kw_name then
				kw_name = pt:match("^%*%*%$([%w_]+)$")
			end

			if kw_name then
				local entry = {name = kw_name, kwsplat = true}

				if kw_meta then
					entry.meta = parse_hash(kw_meta).hash
				end

				table.insert(params, entry)

			else
				-- *$name — collect extra positional args into this param.
				-- Optional metadata: `*$args: {...}`.
				local sp_name, sp_meta = pt:match("^%*%$([%w_]+):%s*(%b{})$")

				if not sp_name then
					sp_name = pt:match("^%*%$([%w_]+)$")
				end

				if sp_name then
					local entry = {name = sp_name, splat = true}

					if sp_meta then
						entry.meta = parse_hash(sp_meta).hash
					end

					table.insert(params, entry)

				elseif pt:sub(1, 1) == "@" then
					-- `@name` — auto-assign form. The `@` sigil in a param
					-- signals `method &init(@name)` — the method body gets
					-- an implicit `@name = $name` prepended. Bare `@name`,
					-- rich-metadata `@name: {meta}`, and default-shortcut
					-- `@name: value` (= `@name: {default: value}`) all
					-- supported. The `at_assign: true` flag lets
					-- parse_construct know to prepend the setat statement
					-- when the method closes.
					local at_bare = pt:match("^@([%w_]+)$")

					if at_bare then
						table.insert(params, {name = at_bare, at_assign = true})
					else
						local at_m_name, at_m_hash =
							pt:match("^@([%w_]+):%s*(%b{})$")

						if at_m_name and at_m_hash then
							local at_meta = parse_hash(at_m_hash).hash
							table.insert(params, {
								name = at_m_name,
								at_assign = true,
								meta = at_meta,
							})
						else
							local at_d_name, at_d_val =
								pt:match("^@([%w_]+):%s*(.+)$")

							if at_d_name and at_d_val then
								table.insert(params, {
									name = at_d_name,
									at_assign = true,
									meta = {{
										"default",
										parse_expression(trim(at_d_val)),
									}},
								})
							else
								error("transpile: bad `" .. keyword_name
									.. "` @-param `" .. pt .. "`")
							end
						end
					end

				else
					local pname = pt:match("^%$([%w_]+)$")

					if pname then
						table.insert(params, pname)
					else
						-- Rich metadata: `$name: {hash}` — colon after the param name,
						-- then a hash literal with class/default/etc. constraints.
						-- Values in the hash are parsed as value-atoms; the runtime
						-- interprets them at call time (e.g., `default:` re-runs per
						-- call, same rule as parameter-defaults).
						local m_name, m_hash = pt:match("^%$([%w_]+):%s*(%b{})$")

						if m_name and m_hash then
							local meta_atom = parse_hash(m_hash)
							table.insert(params, {name = m_name, meta = meta_atom.hash})
						elseif pt ~= "" then
							error("transpile: bad `" .. keyword_name .. "` param `" .. pt .. "`")
						end
					end
				end
			end
		end
	end

	-- Optional `as $name` binding after the params paren — the controller
	-- slot the caller-machinery fills in at invocation time. Not runtime
	-- code; lifted onto the callable atom as an `as: NAME` field.
	local as_binding, i_after_as = read_optional_as_binding(source, i)
	i = i_after_as

	return name, params, i, receiver, as_binding
end

local function tokenize_construct(source, start_line)
	local tokens = {}
	local i = 1
	local len = #source
	local base_line = start_line or 1

	-- Count newlines in source[1..pos-1] to derive the 1-based line offset
	-- from the base. Called once per emitted token — the source strings
	-- passed to tokenize_construct are one flushed code buffer at a time,
	-- typically under a hundred lines, so recounting per token is fine.
	local function line_at(pos)
		local nl = 0

		for _ in source:sub(1, pos - 1):gmatch("\n") do
			nl = nl + 1
		end

		return base_line + nl
	end

	while i <= len do
		while i <= len and source:sub(i, i):match("%s") do
			i = i + 1
		end

		if i > len then
			break
		end

		if source:sub(i, i) == "#" then
			local tok_line = line_at(i)
			local start = i + 1

			while i <= len and source:sub(i, i) ~= "\n" do
				i = i + 1
			end

			table.insert(tokens, {
				type = "comment",
				text = trim(source:sub(start, i - 1)),
				line = tok_line,
			})

			if i <= len then
				i = i + 1
			end

		else
			local save_i = i
			local tok_line = line_at(i)
			local word = nil

			if source:sub(i, i):match("[%w_]") then
				local wstart = i

				while i <= len and source:sub(i, i):match("[%w_]") do
					i = i + 1
				end

				word = source:sub(wstart, i - 1)
			end

			if word and CONSTRUCT_KEYWORDS[word] then
				if SIG_KEYWORDS[word] then
					local sig_name, sig_params, new_i, sig_receiver, sig_as =
						read_signature(source, i, word)
					table.insert(tokens, {
						type = word,
						name = sig_name,
						params = sig_params,
						receiver = sig_receiver,
						as_binding = sig_as,
						line = tok_line,
					})
					i = new_i

				elseif word == "do" or word == "dofunc" then
					-- Optional `(params)`. Blocks are anonymous — no name.
					while i <= len and source:sub(i, i):match("%s") do
						i = i + 1
					end

					local params = {}

					if i <= len and source:sub(i, i) == "(" then
						local depth = 1
						local params_start = i + 1
						i = i + 1

						while i <= len and depth > 0 do
							local c = source:sub(i, i)

							if c == "(" then
								depth = depth + 1
							elseif c == ")" then
								depth = depth - 1
							end

							i = i + 1
						end

						if depth ~= 0 then
							error("transpile: unclosed `(` in `" .. word .. "` params")
						end

						local params_str = source:sub(params_start, i - 2)

						if trim(params_str) ~= "" then
							for p in params_str:gmatch("[^,]+") do
								local pt = trim(p)
								local pname = pt:match("^%$([%w_]+)$")

								if pname then
									table.insert(params, pname)
								elseif pt ~= "" then
									error("transpile: bad `" .. word
										.. "` param `" .. pt .. "`")
								end
							end
						end
					end

					local do_as, i_after = read_optional_as_binding(source, i)
					i = i_after

					table.insert(tokens, {
						type = word,
						params = params,
						as_binding = do_as,
						line = tok_line,
					})

				elseif word == "instance" then
					-- Optional `(args)` for construction. Args are call-args,
					-- parsed as expressions.
					while i <= len and source:sub(i, i):match("%s") do
						i = i + 1
					end

					local inst_args = nil

					if i <= len and source:sub(i, i) == "(" then
						local depth = 1
						local args_start = i + 1
						i = i + 1

						while i <= len and depth > 0 do
							local c = source:sub(i, i)

							if c == "(" then
								depth = depth + 1
							elseif c == ")" then
								depth = depth - 1
							end

							i = i + 1
						end

						if depth ~= 0 then
							error("transpile: unclosed `(` in `instance` args")
						end

						local args_str = source:sub(args_start, i - 2)
						inst_args = {}

						if trim(args_str) ~= "" then
							for _, arg in ipairs(split_top_level(args_str, ",")) do
								local at = trim(arg)

								if at ~= "" then
									table.insert(inst_args, parse_expression(at))
								end
							end
						end
					end

					table.insert(tokens, {type = "instance", args = inst_args, line = tok_line})

				elseif COND_KEYWORDS[word] then
					i = skip_ws_and_collect_comments(source, i, tokens, base_line)

					local cond, new_i, cond_comments = read_cond_prefix(source, i)

					if not cond then
						error("transpile: `" .. word .. "` with no condition")
					end

					-- Emit comments encountered mid-cond BEFORE the keyword token,
					-- so they land next to the enclosing construct in CaspianJ rather
					-- than getting swallowed by the cond expression.
					for _, ct in ipairs(cond_comments) do
						table.insert(tokens, ct)
					end

					local cond_as, i_after = read_optional_as_binding(source, new_i)

					table.insert(tokens, {
						type = word,
						cond = cond,
						as_binding = cond_as,
						line = tok_line,
					})
					i = i_after
				else
					local kw_as, i_after = read_optional_as_binding(source, i)

					table.insert(tokens, {
						type = word,
						as_binding = kw_as,
						line = tok_line,
					})
					i = i_after
				end

			elseif word and CONSTRUCT_CLAUSES[word] then
				table.insert(tokens, {type = "clause", name = word, line = tok_line})

			else
				i = save_i
				local end_i = scan_content_end(source, i)
				local text = trim(source:sub(i, end_i - 1))

				if text ~= "" then
					table.insert(tokens, {type = "statement", text = text, line = tok_line})
				end

				i = end_i
			end
		end
	end

	return tokens
end

-- Clause-set-per-construct policy. `begin ... end` (bare block) admits
-- ONLY `ensure` — the cleanup hook. Everything else that carries a body —
-- functions/closures/methods/do blocks AND loops — is "callable-shaped"
-- from the parser's perspective (the engine may realize loop bodies as
-- closures), so they admit the iteration-lifecycle clauses (before /
-- between / after / noloop) but NOT `ensure`. `begin ... while COND` /
-- `begin ... until COND` transition from a begin frame into a loop
-- construct at close-time, so they follow the loop set — the begin
-- frame accepts any clause during parse and validates at close.
local BEGIN_END_CLAUSES  = {ensure = true}
local CALLABLE_CLAUSES   = {before = true, between = true, after = true, noloop = true}

local function empty_clauses()
	return {body = {}}
end

local function parse_construct(tokens, result)
	local stack = {}

	-- Extract the value from a value-atom statement row.
	-- Value-atom statements have the form `[{kind: {...}}]` — a one-element list
	-- wrapping an expression atom. Returns the wrapped value if so, else nil.
	local function unwrap_value_atom(stmt)
		if type(stmt) == "table" and #stmt == 1 and type(stmt[1]) == "table"
			and stmt[1][1] == nil then
			return stmt[1]
		end

		return nil
	end

	-- If line annotation is on, tag stmt with the current statement's line
	-- just before it lands in its destination. Three shapes:
	--   - value-atom row `[{atom}]` (one non-comment atom): put `line` on the
	--     atom itself, preserving the #stmt == 1 shape parse_construct_as_
	--     expression relies on.
	--   - multi-atom statement row: append `{line: N}` as a trailing meta-atom.
	--   - single-object atom (like a bare `{comment:}`): set `line` as a field.
	-- Called at every insertion site so the tag never lands on intermediate
	-- stmt values that get unwrapped (e.g. the value-atom the pending-setvar
	-- branch consumes).
	local function annotate(stmt)
		if include_lines and current_line and type(stmt) == "table" then
			if #stmt == 1 and type(stmt[1]) == "table" and not stmt[1].comment
					and stmt[1][1] == nil then
				if not stmt[1].line then
					stmt[1].line = current_line
				end
			elseif #stmt > 0 then
				table.insert(stmt, {line = current_line})
			else
				stmt.line = current_line
			end
		end

		return stmt
	end

	local add_stmt

	add_stmt = function(stmt)
		if #stack > 0 and stack[#stack].type == "pending_setvar" then
			-- Only consume value-atom statements (block emissions like class or
			-- function). Comments, plain statements, etc. bypass the pending
			-- marker and land at their normal destination.
			local value = unwrap_value_atom(stmt)

			if value then
				local pending = table.remove(stack)

				add_stmt({"scope", "setvar", pending.name, value})
				return
			end

			-- Non-value stmt while pending: add to result, keep pending in place.
			table.insert(result, annotate(stmt))
			return
		end

		if #stack == 0 then
			table.insert(result, annotate(stmt))
			return
		end

		local top = stack[#stack]

		if top.clauses then
			table.insert(top.clauses[top.cur], annotate(stmt))
		elseif top.type == "if" or top.type == "unless" then
			table.insert(top.branches[top.cur_branch].body, annotate(stmt))
		else
			table.insert(top.body, annotate(stmt))
		end
	end

	for _, tok in ipairs(tokens) do
		-- Update the current-line tracker so atoms and statement rows produced
		-- while dispatching this token inherit the token's source line.
		if tok.line then
			current_line = tok.line
		end

		if tok.type == "while" or tok.type == "until" then
			local verb = tok.type == "while" and "begin_while" or "begin_until"

			if #stack > 0 and stack[#stack].type == "begin" then
				local blk = table.remove(stack)

				-- `begin ... while COND` / `begin ... until COND` is a loop, so
				-- the iteration-lifecycle rule applies — `ensure` is only for
				-- the bare `begin ... end` form. Also `noloop` is dead code
				-- here: begin-while / begin-until always runs the body at
				-- least once (that's the whole point of the trailing-cond
				-- form), so the "body-never-ran" hook can never fire — reject
				-- with a specific error rather than let the developer wonder
				-- why their `noloop` block never runs.
				for cname in pairs(blk.clauses) do
					if cname == "body" or cname == "as" then
						-- fine
					elseif cname == "noloop" then
						error("transpile: `noloop` is not valid on a"
							.. " `begin ... " .. tok.type .. "` loop — the"
							.. " body always runs at least once, so `noloop`"
							.. " would be dead code. Use a leading-cond loop"
							.. " (`" .. tok.type .. " COND ... noloop ... end`)"
							.. " if you need it.")
					elseif not CALLABLE_CLAUSES[cname] then
						error("transpile: `" .. cname .. "` is not valid on a"
							.. " `begin ... " .. tok.type .. "` loop;"
							.. " `ensure` is only for the bare `begin ... end`"
							.. " form")
					end
				end

				if tok.as_binding then
					blk.clauses.as = tok.as_binding
				end

				add_stmt({"scope", verb, parse_expression(tok.cond), blk.clauses})
			else
				local end_verb = tok.type == "while" and "while_end" or "until_end"
				table.insert(stack, {
					type = tok.type,
					cond = tok.cond,
					clauses = empty_clauses(),
					cur = "body",
					close_verb = end_verb,
					as_binding = tok.as_binding,
				})
			end

		elseif tok.type == "begin" then
			table.insert(stack, {
				type = "begin",
				clauses = empty_clauses(),
				cur = "body",
				as_binding = tok.as_binding,
			})

		elseif tok.type == "function" or tok.type == "closure" or tok.type == "method" then
			table.insert(stack, {
				type = tok.type,
				name = tok.name,
				receiver = tok.receiver,
				params = tok.params,
				clauses = empty_clauses(),
				cur = "body",
				as_binding = tok.as_binding,
			})

		elseif tok.type == "class" then
			table.insert(stack, {type = "class", body = {}})

		elseif tok.type == "amend" then
			table.insert(stack, {
				type = "amend",
				target = parse_expression(tok.cond),
				body = {},
			})

		elseif tok.type == "instance" then
			table.insert(stack, {type = "instance", args = tok.args, body = {}})

		elseif tok.type == "do" or tok.type == "dofunc" then
			table.insert(stack, {
				type = tok.type,
				params = tok.params,
				clauses = empty_clauses(),
				cur = "body",
				as_binding = tok.as_binding,
			})

		elseif tok.type == "if" or tok.type == "unless" then
			table.insert(stack, {
				type = tok.type,
				branches = {{cond = parse_expression(tok.cond), body = {}}},
				cur_branch = 1,
				has_else = false,
			})

		elseif tok.type == "elsif" or tok.type == "elseif" then
			if #stack == 0 or (stack[#stack].type ~= "if" and stack[#stack].type ~= "unless") then
				error("transpile: `" .. tok.type .. "` outside of an if/unless block")
			end

			local top = stack[#stack]

			if top.has_else then
				error("transpile: `" .. tok.type .. "` after `else`")
			end

			table.insert(top.branches, {cond = parse_expression(tok.cond), body = {}})
			top.cur_branch = #top.branches

		elseif tok.type == "else" then
			if #stack == 0 or (stack[#stack].type ~= "if" and stack[#stack].type ~= "unless") then
				error("transpile: `else` outside of an if/unless block")
			end

			local top = stack[#stack]

			if top.has_else then
				error("transpile: duplicate `else` in if/unless block")
			end

			table.insert(top.branches, {cond = M.null, body = {}})
			top.cur_branch = #top.branches
			top.has_else = true

		elseif tok.type == "end" then
			if #stack == 0 then
				error("transpile: `end` with no matching opener")
			end

			local blk = table.remove(stack)

			if blk.type == "while" or blk.type == "until" then
				local clauses = blk.clauses

				if blk.as_binding then
					clauses.as = blk.as_binding
				end

				add_stmt({"scope", blk.close_verb, parse_expression(blk.cond), clauses})
			elseif blk.type == "begin" then
				-- Bare `begin ... end` only accepts `ensure`. Any other clause
				-- (before / between / after / noloop) is a parser error steering
				-- the author to a loop or callable body. Validation deferred
				-- until close because at clause-marker time we don't yet know
				-- whether this begin will close as bare (`end`) or as a loop
				-- (`begin ... while COND` / `begin ... until COND`).
				for cname in pairs(blk.clauses) do
					if cname ~= "body" and not BEGIN_END_CLAUSES[cname] then
						error("transpile: `" .. cname .. "` is not valid inside"
							.. " a bare `begin ... end`; use it on a loop"
							.. " (`while` / `until` / `.each` / ...) or a"
							.. " callable body (function / closure / method / do)."
							.. " `begin ... end` only accepts `ensure`.")
					end
				end

				-- Emit as value-atom row `[{begin_end: clauses}]` so it works
				-- both at statement position (value discarded) and at expression
				-- position (unwraps to the atom via parse_construct_as_expression).
				if blk.as_binding then
					blk.clauses.as = blk.as_binding
				end

				add_stmt({{begin_end = blk.clauses}})
			elseif blk.type == "if" or blk.type == "unless" then
				-- Wrap each branch's body in a zero-param closure atom so the
				-- engine's dispatch model stays uniform — "invoke this body"
				-- is always "invoke a closure". Runtime doesn't need a special
				-- branch-body primitive. Parser-level clause validation
				-- already ran (the clause-marker handler rejects iteration
				-- clauses on if / unless frames), so the emitted closures
				-- never carry `before` / `between` / `after` / `noloop`.
				local wrapped_branches = {}

				for _, br in ipairs(blk.branches) do
					table.insert(wrapped_branches, {
						cond = br.cond,
						body = {closure = {params = {}, body = br.body}},
					})
				end

				local verb = (blk.type == "if") and "if_end" or "unless_end"
				add_stmt({"scope", verb, {branches = wrapped_branches}})
			elseif blk.type == "function" or blk.type == "closure" or blk.type == "method" then
				-- Auto-assign for `@name` params (method-only): each `@name`
				-- entry in the params list gets its `at_assign` flag stripped
				-- and an `["scope", "setat", name, {var: name}]` statement
				-- prepended to the body, in source order. Fully desugared at
				-- CaspianJ level so the runtime doesn't need to know about
				-- the `@` sigil on params.
				local final_params = {}
				local at_prefix = {}

				for _, p in ipairs(blk.params) do
					if type(p) == "table" and p.at_assign then
						table.insert(at_prefix, {
							"scope", "setat", p.name, {var = p.name},
						})

						local cleaned = {name = p.name}

						if p.meta then
							cleaned.meta = p.meta
						end

						if p.splat then
							cleaned.splat = true
						end

						if p.kwsplat then
							cleaned.kwsplat = true
						end

						table.insert(final_params, cleaned)
					else
						table.insert(final_params, p)
					end
				end

				local final_body = blk.clauses.body

				if #at_prefix > 0 then
					final_body = {}

					for _, s in ipairs(at_prefix) do
						table.insert(final_body, s)
					end

					for _, s in ipairs(blk.clauses.body) do
						table.insert(final_body, s)
					end
				end

				local inner = {params = final_params, body = final_body}

				-- Attach any declared iteration-lifecycle clauses. Option B:
				-- absent slots don't appear at all.
				for _, cname in ipairs({"before", "between", "after", "noloop"}) do
					if blk.clauses[cname] then
						inner[cname] = blk.clauses[cname]
					end
				end

				if blk.name then
					inner.name = blk.name
				end

				if blk.receiver then
					inner.receiver = blk.receiver
				end

				if blk.as_binding then
					inner.as = blk.as_binding
				end

				local value = {[blk.type] = inner}

				-- Emit as a one-element value-atom statement in both cases. When
				-- there's a pending_setvar on the stack, add_stmt binds the
				-- atom into a `setvar` shape (long-form `$foo = function(...) end`);
				-- otherwise it lands as a bare value-atom statement.
				if blk.type == "method" and not blk.name then
					error("transpile: `method` requires a name; anonymous `method(...) end` is not supported")
				end

				add_stmt({value})
			elseif blk.type == "class" then
				add_stmt({{class = {body = blk.body}}})
			elseif blk.type == "amend" then
				add_stmt({{amend = {target = blk.target, body = blk.body}}})
			elseif blk.type == "instance" then
				local inner = {body = blk.body}

				if blk.args then
					inner.args = blk.args
				end

				add_stmt({{instance = inner}})

			elseif blk.type == "do" or blk.type == "dofunc" then
				-- Attach block to the immediately-preceding call statement in
				-- the current scope. Blocks live in a trailing `{blocks: [...]}`
				-- wrapper (parallel to how kwargs use `{kw: [...]}`).
				local target_list

				if #stack == 0 then
					target_list = result
				else
					local top = stack[#stack]

					if top.clauses then
						target_list = top.clauses[top.cur]
					elseif top.type == "if" or top.type == "unless" then
						target_list = top.branches[top.cur_branch].body
					else
						target_list = top.body
					end
				end

				local idx = #target_list

				while idx > 0 and type(target_list[idx]) == "table"
					and target_list[idx].comment ~= nil do
					idx = idx - 1
				end

				if idx == 0 then
					error("transpile: `" .. blk.type
						.. "` block has no preceding call to attach to")
				end

				local prev = target_list[idx]

				if type(prev) ~= "table" or #prev == 0 then
					error("transpile: `" .. blk.type
						.. "` block after non-call statement")
				end

				local do_inner = {params = blk.params, body = blk.clauses.body}

				if blk.as_binding then
					do_inner.as = blk.as_binding
				end

				for _, cname in ipairs({"before", "between", "after", "noloop"}) do
					if blk.clauses[cname] then
						do_inner[cname] = blk.clauses[cname]
					end
				end

				-- Translate parser frame type to canonical CaspJ atom key:
				-- `do` (captures outer scope) -> `closure`; `dofunc` (sealed
				-- scope) -> `function`. The parser tracks the source keyword;
				-- the atom vocabulary uses the semantic name.
				local atom_key = blk.type == "do" and "closure" or "function"
				local block_value = {[atom_key] = do_inner}
				local last = prev[#prev]

				if type(last) == "table" and last.blocks ~= nil then
					table.insert(last.blocks, block_value)
				else
					table.insert(prev, {blocks = {block_value}})
				end
			end

		elseif tok.type == "clause" then
			if #stack == 0 then
				error("transpile: clause marker `" .. tok.name
					.. "` outside of any block")
			end

			local top = stack[#stack]
			local frame_type = top.type

			-- `begin` frames accept ANY clause during parse — we don't yet know
			-- if the block will close as bare `end` (only `ensure` allowed) or
			-- as a loop (`while` / `until`, iteration-clauses allowed). The
			-- end / while-conversion handler does the final validation.
			--
			-- Callable-shaped frames (function / closure / method / do / dofunc
			-- / while / until) enforce the iteration-lifecycle set here so the
			-- error points at the clause line, not the far-away `end`.
			if frame_type == "begin" then
				-- deferred
			elseif frame_type == "function" or frame_type == "closure"
				or frame_type == "method" or frame_type == "do"
				or frame_type == "dofunc" or frame_type == "while"
				or frame_type == "until"
			then
				if not CALLABLE_CLAUSES[tok.name] then
					error("transpile: `" .. tok.name .. "` is only valid inside"
						.. " a bare `begin ... end`; " .. frame_type
						.. " bodies use `before` / `between` / `after` / `noloop`")
				end
			elseif frame_type == "if" or frame_type == "unless" then
				-- `if` / `unless` branch bodies are one-shot closures — no
				-- iterator ever invokes their lifecycle hooks, so declaring
				-- a clause slot on an if branch would be dead code. Reject
				-- at parse time with the same steering as the callable case.
				error("transpile: `" .. tok.name .. "` is not valid inside an"
					.. " `" .. frame_type .. "` branch; clause markers are"
					.. " only for callable bodies (function / closure / method"
					.. " / do) and loops (while / until / .each / .times / ...)")
			else
				error("transpile: clause marker `" .. tok.name
					.. "` not allowed inside a `" .. frame_type .. "` block")
			end

			if top.clauses[tok.name] == nil then
				top.clauses[tok.name] = {}
			end

			top.cur = tok.name

		elseif tok.type == "comment" then
			add_stmt({comment = tok.text})

		elseif tok.type == "statement" then
			-- Detect `$name = ` (assignment head with the RHS coming from a
			-- following block construct — `class ... end`, `function ... end`,
			-- etc.). Push a pending-setvar marker; the next block's value gets
			-- wrapped in `setvar` when its `end` closes.
			local pending_name = tok.text:match("^%$([%w_]+)%s*=%s*$")

			-- Statement-leading pipe: `| bwc [args]`. Same semantics as writing
			-- `bwc previous_value [args]` inline. Rewrites the immediately
			-- preceding statement in the current scope by wrapping it in a bwc
			-- call.
			local pipe_rhs = tok.text:match("^|%s*(.+)$")

			if pending_name then
				table.insert(stack, {type = "pending_setvar", name = pending_name})

			elseif pipe_rhs then
				local pipe_bwc, pipe_tail = pipe_rhs:match("^([%w_]+)%s*(.*)$")

				if not pipe_bwc then
					error("transpile: `|` with malformed right-hand side: " .. pipe_rhs)
				end

				local target_list

				if #stack == 0 then
					target_list = result
				else
					local top = stack[#stack]

					if top.clauses then
						target_list = top.clauses[top.cur]
					elseif top.type == "if" or top.type == "unless" then
						target_list = top.branches[top.cur_branch].body
					else
						target_list = top.body
					end
				end

				local idx = #target_list

				while idx > 0 and type(target_list[idx]) == "table"
					and target_list[idx].comment ~= nil do
					idx = idx - 1
				end

				if idx == 0 then
					error("transpile: `| " .. pipe_bwc
						.. "` has no preceding value to pipe from")
				end

				local prev = target_list[idx]
				local prev_value = unwrap_value_atom(prev) or prev

				-- Build the RHS call — `[{bwc: name}, args...]` — without
				-- injecting the LHS. Full CaspJ keeps the pipe as a
				-- `{op: "|", left, right}` atom; normalize desugars later
				-- by slotting `prev_value` in between the callable and
				-- its args.
				local rhs_call = {attach_line({bwc = pipe_bwc})}

				if pipe_tail and trim(pipe_tail) ~= "" then
					for _, arg in ipairs(split_top_level(trim(pipe_tail), ",")) do
						local at = trim(arg)

						if at ~= "" then
							table.insert(rhs_call, parse_expression(at))
						end
					end
				end

				local pipe_atom = attach_line({
					op = "|",
					left = prev_value,
					right = rhs_call,
				})

				target_list[idx] = annotate({pipe_atom})

			else
				local tmp = {}
				process_code_chunk(tok.text, tmp)

				for _, s in ipairs(tmp) do
					add_stmt(s)
				end
			end
		end
	end

	if #stack > 0 then
		local top = stack[#stack]

		if top.type == "pending_setvar" then
			error("transpile: cannot parse: `$" .. top.name
				.. " =` with no right-hand side")
		end

		error("transpile: unclosed " .. top.type .. " block")
	end
end

--[[
{
	"in":  "string — a Caspian source snippet that begins with a construct keyword (function/closure/method/class/instance/amend/do/dofunc) and ends with `end`",
	"out": "the value-atom the construct evaluates to (e.g. `{function: {params, body}}` for a function definition), or nil if the pipeline doesn't produce exactly one value-atom statement",
	"note": "used by parse_expression to accept block constructs as expression values — hash metadata like `default: function(...) end`, or setvar RHS like `$x = class ... end`. Delegates to tokenize_construct + parse_construct then unwraps the single one-element statement."
}
]]
parse_construct_as_expression = function(s, trailing_sink)
	local tokens = tokenize_construct(s)
	local tmp = {}
	local ok = pcall(parse_construct, tokens, tmp)

	if not ok then
		return nil
	end

	-- Filter comment atoms — a construct may emit inline-comment statements
	-- alongside the value-atom. The value-atom statement is a one-element
	-- list whose sole entry is a value atom (a table without a `comment` key).
	-- Sibling comment atoms after the value are collected into `trailing_sink`
	-- when the caller provides one; otherwise dropped.
	local value = nil

	for _, stmt in ipairs(tmp) do
		if type(stmt) == "table" then
			if stmt.comment then
				if value and trailing_sink then
					table.insert(trailing_sink, stmt)
				end
			elseif #stmt == 1 and type(stmt[1]) == "table" and not stmt[1].comment then
				if value then
					return nil
				end

				value = stmt[1]
			else
				return nil
			end
		end
	end

	return value
end

--[[
{
	"in":  "one physical source line",
	"out": "list of heredoc-opener records found in left-to-right order. Each: {start_pos, end_pos, terminator, quote, content_type, kwargs, literal}. start_pos is the position of the first `<` of `<<`; end_pos is the position of the last char of the opener (post-terminator, including a closing quote if present).",
	"note": "detects `<<IDENT`, `<<'IDENT'`, `<<\"IDENT\"`, and any of those preceded by `(ARGS)`. The paren-arg block parses like a regular function-call arg list: at most one positional (the content_type, must be a string literal) plus any number of `key: value` kwargs (each value must be a scalar literal). `<<` inside string literals is a known false-positive; add string-tracking when a test needs it."
}
]]
local function scan_heredoc_openers(line)
	local openers = {}
	local pos = 1
	local len = #line

	while pos <= len do
		local s, e = line:find("<<", pos, true)

		if not s then
			break
		end

		local at = e + 1
		local content_type = nil
		local kwargs = nil

		-- Optional (ARGS) annotation after `<<`. Parses like a regular
		-- function-call arg list: at most one positional (bound to
		-- content_type, must be a quoted string) plus any number of
		-- `key: value` kwargs (each value must be a scalar literal).
		if line:sub(at, at) == "(" then
			local depth = 1
			local close_at = at + 1

			while close_at <= len do
				local c = line:sub(close_at, close_at)

				if c == "(" then
					depth = depth + 1
				elseif c == ")" then
					depth = depth - 1

					if depth == 0 then
						break
					end
				end

				close_at = close_at + 1
			end

			if depth ~= 0 then
				pos = e + 1
			else
				local inner = trim(line:sub(at + 1, close_at - 1))
				local seen_positional = false

				if inner ~= "" then
					for _, arg in ipairs(split_top_level(inner, ",")) do
						local arg_t = trim(arg)

						if arg_t ~= "" then
							local kw_key, kw_val = arg_t:match(
								"^([%w_]+)%s*:%s*(.+)$")

							if kw_key and kw_val and kw_val ~= "" then
								local v = parse_literal(trim(kw_val))

								if v == nil then
									error("transpile: heredoc kwarg `"
										.. kw_key .. ":` value must be a scalar literal; got: "
										.. kw_val)
								end

								kwargs = kwargs or {}
								table.insert(kwargs, {kw_key, v})
							else
								if seen_positional then
									error("transpile: heredoc paren block accepts at most one positional (the content type); extra positional: "
										.. arg_t)
								end

								local q = arg_t:sub(1, 1)

								if #arg_t < 2
									or not (q == "'" or q == '"')
									or arg_t:sub(-1) ~= q
								then
									error("transpile: heredoc content type must be a quoted string, e.g. `<<('text/markdown')EOF`; got: "
										.. arg_t)
								end

								content_type = arg_t:sub(2, -2)
								seen_positional = true
							end
						end
					end
				end

				at = close_at + 1
			end
		end

		-- Terminator: bare | 'IDENT' | "IDENT"
		local quote = nil
		local first = line:sub(at, at)
		local ident_start = at

		if first == "'" or first == '"' then
			quote = first
			ident_start = at + 1
		end

		local ident = line:sub(ident_start):match("^([%w_]+)")

		if not ident then
			pos = e + 1
		else
			local ident_end = ident_start + #ident - 1
			local opener_end = ident_end
			local ok = true

			if quote then
				local close_char = line:sub(ident_end + 1, ident_end + 1)

				if close_char ~= quote then
					ok = false
				else
					opener_end = ident_end + 1
				end
			end

			if ok then
				table.insert(openers, {
					start_pos = s,
					end_pos = opener_end,
					terminator = ident,
					quote = quote,
					content_type = content_type,
					kwargs = kwargs,
					literal = (quote ~= '"'),
				})
				pos = opener_end + 1
			else
				pos = e + 1
			end
		end
	end

	return openers
end

--[[
{
	"in":  "body_lines (list), term_line (string)",
	"out": "list of body lines with the least-indented-line-sets-the-base rule applied. Only whitespace is stripped; a line whose leading whitespace is shorter than the base has stripping cut short at its first non-whitespace char. Blank body lines don't participate in base computation; the terminator does.",
	"note": "tabs and spaces both count as ONE char (per spec — mixed usage would produce a compile-time warning; not implemented yet)"
}
]]
local function strip_heredoc_indent(body_lines, term_line)
	local function count_leading_ws(l)
		local ws = l:match("^(%s*)") or ""
		return #ws
	end

	local base = math.huge

	for _, l in ipairs(body_lines) do
		if l:match("%S") then
			local ws = count_leading_ws(l)

			if ws < base then
				base = ws
			end
		end
	end

	local term_ws = count_leading_ws(term_line)

	if term_ws < base then
		base = term_ws
	end

	if base == math.huge then
		base = 0
	end

	local stripped = {}

	for _, l in ipairs(body_lines) do
		local ws = count_leading_ws(l)
		local n = math.min(ws, base)
		table.insert(stripped, l:sub(n + 1))
	end

	return stripped
end

function M.transpile(source, opts)
	include_lines = opts and opts.lines == true or false
	current_line = nil

	if trim(source) == "" then
		return {}
	end

	local result = {}
	local state = "NORMAL"
	local heredoc_kind = nil
	local heredoc_body = {}
	local code_buffer = {}
	local code_buffer_start_line = nil
	local heredoc_counter = 0

	active_heredocs = {}

	local function flush_code_buffer()
		if #code_buffer == 0 then
			return
		end

		local code_source = table.concat(code_buffer, "\n")

		if trim(code_source) ~= "" then
			local tokens = tokenize_construct(code_source, code_buffer_start_line)
			parse_construct(tokens, result)
		end

		code_buffer = {}
		code_buffer_start_line = nil
	end

	if source:sub(-1) ~= "\n" then
		source = source .. "\n"
	end

	local lines = {}

	for raw_line in source:gmatch("([^\n]*)\n") do
		table.insert(lines, raw_line)
	end

	local i = 1

	while i <= #lines do
		local raw_line = lines[i]

		if state == "IN_HEREDOC" then
			if raw_line:match("^%s*EOF%s*$") then
				table.insert(result, {[heredoc_kind] = table.concat(heredoc_body, "\n")})
				state = "NORMAL"
				heredoc_kind = nil
				heredoc_body = {}
			else
				table.insert(heredoc_body, raw_line)
			end

			i = i + 1
		else
			local trimmed = trim(raw_line)

			if trimmed == "" then
				-- Blank line — newlines aren't significant to the parser, but
				-- push into code_buffer when the buffer is non-empty so the
				-- assembled source string preserves \n positions and line-num
				-- annotations track absolute source lines instead of losing
				-- blanks between statements.
				if #code_buffer > 0 then
					table.insert(code_buffer, raw_line)
				end

				i = i + 1

			elseif trimmed:match("^%%documentation%s+<<EOF%s*$") then
				flush_code_buffer()
				state = "IN_HEREDOC"
				heredoc_kind = "documentation"
				heredoc_body = {}
				i = i + 1

			elseif trimmed:match("^%%vibecode%s+<<EOF%s*$") then
				flush_code_buffer()
				state = "IN_HEREDOC"
				heredoc_kind = "vibecode"
				heredoc_body = {}
				i = i + 1

			else
				local openers = scan_heredoc_openers(raw_line)

				if #openers == 0 then
					if #code_buffer == 0 then
						code_buffer_start_line = i
					end
					table.insert(code_buffer, raw_line)
					i = i + 1
				else
					local next_i = i + 1

					for _, opener in ipairs(openers) do
						local body_lines = {}
						local term_line = nil
						local term_pattern = "^%s*"
							.. opener.terminator:gsub("[%.%+%-%*%?%^%$%(%)%%%[%]]", "%%%0")
							.. "%s*$"

						while next_i <= #lines do
							local body_line = lines[next_i]

							if body_line:match(term_pattern) then
								term_line = body_line
								next_i = next_i + 1
								break
							end

							table.insert(body_lines, body_line)
							next_i = next_i + 1
						end

						if not term_line then
							error("transpile: unterminated heredoc `"
								.. opener.terminator .. "`")
						end

						local stripped = strip_heredoc_indent(body_lines, term_line)
						local body = table.concat(stripped, "\n")
						local atom = {value = body}

						if opener.content_type then
							atom.content_type = opener.content_type
						end

						-- `<<"EOF"` gets the same dq: true flag double-quoted
						-- strings do; runtime handles interp + escapes.
						if opener.quote == '"' then
							atom.dq = true
						end

						-- Flatten paren-block kwargs onto the atom next to
						-- content_type. Order-preserving via the two-element
						-- entries the scanner captured.
						if opener.kwargs then
							for _, kv in ipairs(opener.kwargs) do
								atom[kv[1]] = kv[2]
							end
						end

						local id = heredoc_counter
						heredoc_counter = heredoc_counter + 1
						active_heredocs[id] = atom
						opener.id = id
					end

					local line_to_emit = raw_line

					for j = #openers, 1, -1 do
						local opener = openers[j]
						local placeholder = "%__caspian_heredoc_" .. opener.id .. "__"
						line_to_emit = line_to_emit:sub(1, opener.start_pos - 1)
							.. placeholder
							.. line_to_emit:sub(opener.end_pos + 1)
					end

					if #code_buffer == 0 then
						code_buffer_start_line = i
					end
					table.insert(code_buffer, line_to_emit)
					i = next_i
				end
			end
		end
	end

	flush_code_buffer()

	if state == "IN_HEREDOC" then
		error("transpile: unclosed heredoc")
	end

	active_heredocs = nil

	return result
end

return M
