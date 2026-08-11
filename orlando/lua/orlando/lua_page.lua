--[=[
{
	"module": "orlando.lua_page",
	"role": "Render a .lua source file as an annotated HTML body. Splits the source at every `--[[ ... ]]` block, classifies each block (JSON-parseable -> vibecode, `#`-prefixed content -> markdown, anything else -> plain Lua comment left in the code stream), and interleaves rendered vibecode blocks + rendered markdown + syntax-highlighted Lua code chunks. Rewrites `[ghi]` markers inside comments to `.ghi-btn` buttons when opts.doc_path is set — same treatment as sql_page. Every byte of the input source appears in the output; the difference is only visual treatment.",
	"exports": {
		"chunk": "source string -> array of {kind, body} chunks (kind = 'vibecode' | 'markdown' | 'code')",
		"render_body": "(source, opts?) -> HTML body string (no page shell, no <html>/<body>). opts.doc_path (optional): when set, `[ghi]` markers get replaced with .ghi-btn buttons carrying data-doc = doc_path, data-line = 1-indexed source line, data-context = trimmed comment text."
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

local function attr_escape(s)
	return (s:gsub("&", "&amp;"):gsub('"', "&quot;"))
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

-- [ghi] preprocessing — same shape as sql_page's. Walk the source
-- line by line, number every [ghi] occurrence as [ghi:N], and capture
-- (line, context) into a parallel table. Context is the marker line's
-- comment text with the marker itself stripped; standalone `-- [ghi]`
-- lines walk back to find the last content-carrying comment. Line
-- comment syntax is `--` (same as SQL — the character-class doesn't
-- change between the two languages).
local function preprocess_ghi(source)
	local lines = {}
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end
	if lines[#lines] == "" then table.remove(lines) end

	local function is_comment(l) return l and l:match("^%s*%-%-") ~= nil end
	local function comment_content(l)
		local body = l:match("^%s*%-%-%s*(.-)%s*$") or ""
		return (body:gsub("%[ghi%]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
	end

	local function context_for(i)
		local own = comment_content(lines[i])
		if own ~= "" then return own end

		local j = i - 1
		while j >= 1 and is_comment(lines[j]) do
			local c = comment_content(lines[j])
			if c ~= "" then return c end
			j = j - 1
		end

		return ""
	end

	local contexts = {}
	local next_idx = 1

	for i, line in ipairs(lines) do
		if line:find("%[ghi%]", 1) then
			local ctx = context_for(i)
			lines[i] = line:gsub("%[ghi%]", function()
				local idx = next_idx
				next_idx = next_idx + 1
				contexts[idx] = {line = i, text = ctx}
				return "[ghi:" .. idx .. "]"
			end)
		end
	end

	return table.concat(lines, "\n"), contexts
end

-- Post-process the concatenated HTML: replace every [ghi:N] with a
-- fully-annotated .ghi-btn. Contexts come from preprocess_ghi.
local function inject_ghi_buttons(html, contexts, doc_path)
	local doc = attr_escape(doc_path)
	return (html:gsub("%[ghi:(%d+)%]", function(n)
		local ctx = contexts[tonumber(n)] or {}
		local line = tostring(ctx.line or 0)
		local text = attr_escape(ctx.text or "")
		return '<button type="button" class="ghi-btn"'
			.. ' data-doc="' .. doc .. '"'
			.. ' data-line="' .. line .. '"'
			.. ' data-context="' .. text .. '"'
			.. '>ghi</button>'
	end))
end

--[[ {
	"in": {"source": "Lua source string", "opts": "optional table; opts.doc_path = repo-relative file path for the file-issue button's data-doc attribute"},
	"out": "HTML body string (no <html>/<body> shell) with vibecode / markdown / code chunks rendered in source order"
} ]]
function M.render_body(source, opts)
	opts = opts or {}

	local contexts
	local processed_source = source

	if opts.doc_path and opts.doc_path ~= "" then
		processed_source, contexts = preprocess_ghi(source)
	end

	local chunks = M.chunk(processed_source)
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

	local html = table.concat(parts, "\n")

	if contexts then
		html = inject_ghi_buttons(html, contexts, opts.doc_path)
	end

	return html
end

return M
