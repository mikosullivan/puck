--[=[
{
	"module": "orlando.sql_page",
	"role": "Render a .sql source file as a single syntax-highlighted HTML body. No markdown extraction, no chunking — the whole file goes through the SQL highlighter and is wrapped in one <pre><code> block. Comments (--, /* */) stay as SQL comments; the highlighter styles them. Rewrites `[ghi]` markers inside comments to `.ghi-btn` buttons that open the file-issue popup with the source file + line + comment context prefilled — see orlando/client-assets/ghi.js. Buttons only appear where the author placed a `[ghi]` marker; no auto-injection.",
	"exports": {
		"render_body": "(source, opts?) -> HTML body string (no page shell, no <html>/<body>). opts.doc_path (optional): when set, `[ghi]` markers get replaced with .ghi-btn buttons carrying data-doc = doc_path, data-line = 1-indexed source line, data-context = trimmed comment text (marker + surrounding whitespace stripped). Wraps the highlighted source in a single <pre class='highlight sql'><code>...</code></pre>."
	}
}
]=]

local sql_highlight = require("orlando.sql_highlight")

local M = {}

local function attr_escape(s)
	return (s:gsub("&", "&amp;"):gsub('"', "&quot;"))
end

--[[ {
	"in":  {"source": "SQL source string", "opts": "optional table; opts.doc_path = repo-relative file path for the file-issue button's data-doc attribute"},
	"out": "HTML body string (no <html>/<body> shell) with the whole source syntax-highlighted"
} ]]
function M.render_body(source, opts)
	opts = opts or {}

	if not opts.doc_path or opts.doc_path == "" then
		-- No button injection — highlight and wrap, plain.
		local highlighted = sql_highlight.highlight(source)
		return '<pre class="highlight sql"><code>' .. highlighted .. '</code></pre>'
	end

	-- Preprocess: walk source line by line. For each `[ghi]` occurrence
	-- (there can be more than one per line, though rare), replace it
	-- with `[ghi:N]` where N is a running 1-based index — a
	-- per-occurrence sentinel the highlighter passes through unchanged
	-- (letters + digits + brackets are non-special text). Capture the
	-- context (line number + trimmed comment text) into a parallel
	-- table so the post-highlight pass can rebuild each button with
	-- data-line / data-context attributes.
	--
	-- Context extraction: the marker's own line is the natural source
	-- for most inline markers (`-- some text [ghi]`). Standalone
	-- markers (`-- [ghi]` on their own line) have empty own-line
	-- content, so we walk back through the containing comment block
	-- to find the last content-carrying line and use that instead.
	local lines = {}
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end
	-- Drop the trailing empty line the loop appended.
	if lines[#lines] == "" then table.remove(lines) end

	local function is_comment(l) return l and l:match("^%s*%-%-") ~= nil end
	local function comment_content(l)
		local body = l:match("^%s*%-%-%s*(.-)%s*$") or ""
		return (body:gsub("%[ghi%]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
	end

	-- Given a line index, find the best context text: the marker line's
	-- own content if non-empty; else walk back through contiguous
	-- comment lines to find the last non-empty content.
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

	local rewritten_source = table.concat(lines, "\n")

	local highlighted = sql_highlight.highlight(rewritten_source)

	-- Post-process: replace each `[ghi:N]` with a fully-annotated button.
	local doc = attr_escape(opts.doc_path)
	highlighted = highlighted:gsub("%[ghi:(%d+)%]", function(n)
		local ctx = contexts[tonumber(n)] or {}
		local line = tostring(ctx.line or 0)
		local text = attr_escape(ctx.text or "")
		return '<button type="button" class="ghi-btn"'
			.. ' data-doc="' .. doc .. '"'
			.. ' data-line="' .. line .. '"'
			.. ' data-context="' .. text .. '"'
			.. '>ghi</button>'
	end)

	return '<pre class="highlight sql"><code>' .. highlighted .. '</code></pre>'
end

return M
