--[=[
{
	"module": "orlando.lua_page",
	"role": "Render a .lua source file as an annotated HTML body. Splits the source at every `--[[ ... ]]` block, classifies each block (JSON-parseable -> vibecode, `#`-prefixed content -> markdown, anything else -> plain Lua comment left in the code stream), and interleaves rendered vibecode blocks + rendered markdown + syntax-highlighted Lua code chunks. Every byte of the input source appears in the output; the difference is only visual treatment.",
	"exports": {
		"chunk": "source string -> array of {kind, body} chunks (kind = 'vibecode' | 'markdown' | 'code')",
		"render_body": "source string -> HTML body string (no page shell, no <html>/<body>); combines chunk() with the per-kind renderers"
	}
}
]=]

local cjson         = require("cjson")
local lua_highlight = require("orlando.lua_highlight")
local json_highlight = require("orlando.json_highlight")

local M = {}

-- Strip leading and trailing whitespace (spaces + newlines).
local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Decide which flavor a --[[ ... ]] block is. Vibecode is anything
-- whose trimmed body parses as JSON. Markdown is anything else whose
-- trimmed body starts with `#`. Everything else stays as an ordinary
-- Lua block comment.
local function classify_block(body)
	local stripped = trim(body)

	-- JSON attempt. cjson.decode raises on failure; pcall catches it.
	local ok = pcall(cjson.decode, stripped)

	if ok then
		return 'vibecode'
	end

	if stripped:sub(1, 1) == '#' then
		return 'markdown'
	end

	-- Not JSON, not markdown -> ordinary Lua block comment.
	return 'code'
end

--[=[ {
	"in": {"source": "Lua source string"},
	"out": "array — sequence of {kind, body} chunks in source order. kind='vibecode' or 'markdown' chunks are extracted from --[[ ... ]] blocks; kind='code' chunks are the Lua text between them (which itself may contain non-classified --[[ ... ]] block comments, left in place for the Lua syntax highlighter)."
} ]=]
function M.chunk(source)
	local chunks = {}
	local code_start = 1
	local pos = 1

	while pos <= #source do
		local start, s_end = source:find("%-%-%[%[", pos)
		if not start then break end

		local body_start = s_end + 1
		local close_start, close_end = source:find("%]%]", body_start)

		if not close_start then break end

		local body = source:sub(body_start, close_start - 1)
		local kind = classify_block(body)

		if kind == 'code' then
			-- Non-classified block: leave inside the surrounding code
			-- stream so the Lua highlighter treats it as a comment.
			pos = close_end + 1
		else
			-- Emit any code that sat before this block.
			if start > code_start then
				local before = source:sub(code_start, start - 1)
				if trim(before) ~= "" then
					table.insert(chunks, {kind = 'code', body = before})
				end
			end

			table.insert(chunks, {kind = kind, body = body})
			code_start = close_end + 1
			pos = code_start
		end
	end

	-- Trailing code after the last classified block.
	if code_start <= #source then
		local trailing = source:sub(code_start)
		if trim(trailing) ~= "" then
			table.insert(chunks, {kind = 'code', body = trailing})
		end
	end

	return chunks
end

-- Render a vibecode block the same way markdown pages render their
-- `~~~vibecode` fences: collapsible <details> with JSON highlighted
-- inside via json_highlight (page.lua's highlight_json_blocks does
-- the same thing after unwrapping the fence).
local function render_vibecode(body)
	local highlighted = json_highlight.highlight(trim(body))
	return '<details class="vibecode"><summary>vibecode</summary>'
		.. '<div class="vibecode-code"><pre>' .. highlighted
		.. '</pre></div></details>'
end

-- Render a markdown chunk via lunamark. Deferred require so this
-- module only pulls in lunamark when it's actually asked to render
-- markdown (test harnesses that only exercise chunk() skip it).
local function render_markdown(body)
	local lunamark = require("lunamark")
	local writer = lunamark.writer.html5.new()
	local parse = lunamark.reader.markdown.new(writer, {
		fenced_code_blocks = true,
	})
	return (parse(trim(body)))
end

-- Render a Lua code chunk with syntax highlighting. Leading and
-- trailing whitespace is trimmed so back-to-back chunks don't get
-- an extra blank line pile-up in the page.
local function render_code(body)
	local trimmed = trim(body)

	if trimmed == "" then
		return ""
	end

	local highlighted = lua_highlight.highlight(trimmed)
	return '<pre class="highlight lua"><code>' .. highlighted .. '</code></pre>'
end

--[[ {
	"in": {"source": "Lua source string"},
	"out": "HTML body string (no <html>/<body> shell) with vibecode / markdown / code chunks rendered in source order"
} ]]
function M.render_body(source)
	local chunks = M.chunk(source)
	local parts = {}

	for _, chunk in ipairs(chunks) do
		if chunk.kind == 'vibecode' then
			table.insert(parts, render_vibecode(chunk.body))
		elseif chunk.kind == 'markdown' then
			table.insert(parts, render_markdown(chunk.body))
		else
			table.insert(parts, render_code(chunk.body))
		end
	end

	return table.concat(parts, "\n")
end

return M
