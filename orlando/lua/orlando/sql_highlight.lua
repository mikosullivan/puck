--[=[
{
  "module": "orlando.sql_highlight",
  "role": "Tokenize SQL source and emit HTML with pygments-compatible span classes so the pygments CSS in style.css colours it. Sibling of orlando.lua_highlight and orlando.caspian_highlight; same span-class conventions. Targets a broad SQLite dialect since that's Caspian's bundled DBMS, but the keyword set covers standard SQL usage generally.",
  "exports": {
    "highlight": "sql source -> HTML string of <span class=\"...\">...</span> pieces; whitespace and unrecognized characters pass through escaped"
  },
  "classes": {
    "c1": "-- line comment",
    "cm": "/* block comment */",
    "kd": "CREATE / TABLE / INDEX / VIEW / TRIGGER / ALTER / DROP / PRAGMA / etc — data-definition keywords",
    "kr": "SELECT / INSERT / UPDATE / DELETE / FROM / WHERE / etc — data-manipulation and control keywords",
    "kt": "INTEGER / TEXT / BLOB / REAL / NUMERIC / etc — type names",
    "kc": "TRUE / FALSE / NULL",
    "kp": "AND / OR / NOT / IN / IS / LIKE / etc — logical operators as words",
    "s1": "'single-quoted' string",
    "s2": "\"double-quoted\" identifier (quoted-identifier form)",
    "mi": "integer literal",
    "mf": "float literal",
    "o":  "operator"
  }
}
]=]
local M = {}

local KEYWORDS_DDL = {
	["CREATE"]=1, ["TABLE"]=1, ["INDEX"]=1, ["VIEW"]=1, ["TRIGGER"]=1,
	["ALTER"]=1, ["DROP"]=1, ["PRAGMA"]=1, ["IF"]=1, ["EXISTS"]=1,
	["PRIMARY"]=1, ["KEY"]=1, ["FOREIGN"]=1, ["REFERENCES"]=1,
	["UNIQUE"]=1, ["CHECK"]=1, ["DEFAULT"]=1, ["CONSTRAINT"]=1,
	["AUTOINCREMENT"]=1, ["WITHOUT"]=1, ["ROWID"]=1, ["STRICT"]=1,
	["TEMPORARY"]=1, ["TEMP"]=1, ["COLLATE"]=1, ["USING"]=1,
	["BEGIN"]=1, ["COMMIT"]=1, ["ROLLBACK"]=1, ["TRANSACTION"]=1,
	["SAVEPOINT"]=1, ["RELEASE"]=1,
}
local KEYWORDS_DML = {
	["SELECT"]=1, ["INSERT"]=1, ["UPDATE"]=1, ["DELETE"]=1,
	["FROM"]=1, ["INTO"]=1, ["VALUES"]=1, ["SET"]=1,
	["WHERE"]=1, ["ORDER"]=1, ["BY"]=1, ["GROUP"]=1, ["HAVING"]=1,
	["LIMIT"]=1, ["OFFSET"]=1, ["JOIN"]=1, ["LEFT"]=1, ["RIGHT"]=1,
	["INNER"]=1, ["OUTER"]=1, ["FULL"]=1, ["CROSS"]=1, ["NATURAL"]=1,
	["ON"]=1, ["AS"]=1, ["DISTINCT"]=1, ["ALL"]=1, ["UNION"]=1,
	["INTERSECT"]=1, ["EXCEPT"]=1, ["RETURNING"]=1, ["WITH"]=1,
	["RECURSIVE"]=1, ["CASE"]=1, ["WHEN"]=1, ["THEN"]=1, ["ELSE"]=1,
	["END"]=1, ["CASCADE"]=1, ["RESTRICT"]=1, ["ACTION"]=1,
	["EACH"]=1, ["ROW"]=1, ["FOR"]=1, ["BEFORE"]=1, ["AFTER"]=1,
	["OF"]=1, ["INSTEAD"]=1, ["REPLACE"]=1, ["CONFLICT"]=1,
	["ABORT"]=1, ["FAIL"]=1, ["IGNORE"]=1,
}
local KEYWORDS_TYPE = {
	["INTEGER"]=1, ["INT"]=1, ["BIGINT"]=1, ["SMALLINT"]=1,
	["TEXT"]=1, ["VARCHAR"]=1, ["CHAR"]=1, ["CHARACTER"]=1,
	["BLOB"]=1, ["REAL"]=1, ["DOUBLE"]=1, ["FLOAT"]=1,
	["NUMERIC"]=1, ["DECIMAL"]=1, ["BOOLEAN"]=1, ["BOOL"]=1,
	["DATE"]=1, ["DATETIME"]=1, ["TIMESTAMP"]=1, ["TIME"]=1,
	["ANY"]=1,
}
local KEYWORDS_LOGIC = {
	["AND"]=1, ["OR"]=1, ["NOT"]=1, ["IN"]=1, ["IS"]=1,
	["LIKE"]=1, ["GLOB"]=1, ["MATCH"]=1, ["REGEXP"]=1,
	["BETWEEN"]=1, ["EXISTS"]=1,
}
local CONSTANTS = {
	["TRUE"]=1, ["FALSE"]=1, ["NULL"]=1, ["CURRENT_DATE"]=1,
	["CURRENT_TIME"]=1, ["CURRENT_TIMESTAMP"]=1,
}

local function escape(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function span(cls, text)
	return '<span class="' .. cls .. '">' .. escape(text) .. '</span>'
end

-- -- line comment
local function scan_line_comment(s, i)
	if s:sub(i, i + 1) ~= "--" then
		return nil
	end

	local j = s:find("\n", i, true) or (#s + 1)
	return s:sub(i, j - 1), j
end

-- /* block comment */
local function scan_block_comment(s, i)
	if s:sub(i, i + 1) ~= "/*" then
		return nil
	end

	local close = s:find("*/", i + 2, true)

	if close then
		return s:sub(i, close + 1), close + 2
	end

	return s:sub(i), #s + 1
end

-- 'single quoted' — SQL escapes '' as a literal apostrophe.
local function scan_squote(s, i)
	if s:sub(i, i) ~= "'" then
		return nil
	end

	local j, n = i + 1, #s

	while j <= n do
		local c = s:sub(j, j)

		if c == "'" then
			if s:sub(j + 1, j + 1) == "'" then
				j = j + 2
			else
				return s:sub(i, j), j + 1
			end
		else
			j = j + 1
		end
	end

	return s:sub(i, n), n + 1
end

-- "double quoted" — SQL identifier quoting; content is an identifier, not a string.
local function scan_dquote(s, i)
	if s:sub(i, i) ~= '"' then
		return nil
	end

	local j, n = i + 1, #s

	while j <= n do
		local c = s:sub(j, j)

		if c == '"' then
			if s:sub(j + 1, j + 1) == '"' then
				j = j + 2
			else
				return s:sub(i, j), j + 1
			end
		else
			j = j + 1
		end
	end

	return s:sub(i, n), n + 1
end

local function scan_ident(s, i)
	local c = s:sub(i, i)

	if not c:match("[%a_]") then
		return nil
	end

	local j = i

	while j <= #s and s:sub(j, j):match("[%w_]") do
		j = j + 1
	end

	return s:sub(i, j - 1), j
end

local function scan_number(s, i)
	local c = s:sub(i, i)

	if not c:match("%d") then
		return nil
	end

	local j = i

	while j <= #s and s:sub(j, j):match("%d") do
		j = j + 1
	end

	local is_float = false

	if s:sub(j, j) == "." then
		is_float = true
		j = j + 1

		while j <= #s and s:sub(j, j):match("%d") do
			j = j + 1
		end
	end

	if s:sub(j, j) == "e" or s:sub(j, j) == "E" then
		is_float = true
		j = j + 1

		if s:sub(j, j) == "+" or s:sub(j, j) == "-" then
			j = j + 1
		end

		while j <= #s and s:sub(j, j):match("%d") do
			j = j + 1
		end
	end

	return s:sub(i, j - 1), j, is_float
end

local OPS_LONG = {"<=", ">=", "<>", "!=", "||"}
local OPS_SINGLE = {
	["="]=1, ["<"]=1, [">"]=1, ["+"]=1, ["-"]=1, ["*"]=1, ["/"]=1,
	["%"]=1,
}
local function scan_op(s, i)
	for _, op in ipairs(OPS_LONG) do
		if s:sub(i, i + #op - 1) == op then
			return op, i + #op
		end
	end

	local c = s:sub(i, i)

	if OPS_SINGLE[c] then
		return c, i + 1
	end

	return nil
end

local function classify_ident(name)
	local upper = name:upper()

	if CONSTANTS[upper]     then return "kc" end
	if KEYWORDS_DDL[upper]  then return "kd" end
	if KEYWORDS_DML[upper]  then return "kr" end
	if KEYWORDS_TYPE[upper] then return "kt" end
	if KEYWORDS_LOGIC[upper] then return "kp" end

	return nil
end

local function next_token(source, i)
	local c = source:sub(i, i)

	if c == "\n" or c == " " or c == "\t" then
		local n, j = #source, i

		while j <= n and (source:sub(j, j) == "\n"
					or source:sub(j, j) == " "
					or source:sub(j, j) == "\t") do
			j = j + 1
		end

		return escape(source:sub(i, j - 1)), j
	end

	local tok, ni, extra

	tok, ni = scan_line_comment(source, i)
	if tok then return span("c1", tok), ni end

	tok, ni = scan_block_comment(source, i)
	if tok then return span("cm", tok), ni end

	tok, ni = scan_squote(source, i)
	if tok then return span("s1", tok), ni end

	tok, ni = scan_dquote(source, i)
	if tok then return span("s2", tok), ni end

	tok, ni, extra = scan_number(source, i)
	if tok then return span(extra and "mf" or "mi", tok), ni end

	tok, ni = scan_ident(source, i)

	if tok then
		local cls = classify_ident(tok)

		if cls then
			return span(cls, tok), ni
		end

		return escape(tok), ni
	end

	tok, ni = scan_op(source, i)
	if tok then return span("o", tok), ni end

	return escape(c), i + 1
end

--[[ { "in": {"source": "string (SQL source)"}, "out": "string (HTML with span markup)" } ]]
function M.highlight(source)
	local out, i, n = {}, 1, #source

	while i <= n do
		local frag, ni = next_token(source, i)
		out[#out + 1] = frag
		i = ni
	end

	return table.concat(out)
end

return M
