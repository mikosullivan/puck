--[=[
{
  "module": "orlando.cheatsheet",
  "role": "Dynamic cheatsheet page. Walks src/ and build/ on every request and renders them as text-drawn trees with per-file sizes. Regenerated per hit (Cache-Control: no-store).",
  "exports": {
    "handle": "request_path (unused) -> {status, body, content_type, headers} — server-facing entry"
  }
}
]=]
local page = require("orlando.page")

local M = {}

-- Uniform KB format with 2 decimal places, right-aligned in an 8-char field.
-- Keeps decimal points and digits column-aligned regardless of magnitude.
local function format_size(bytes)
	return string.format("%8.2f KB", bytes / 1024)
end

local function file_size(path)
	local f = io.open(path, "rb")

	if not f then
		return 0
	end

	local sz = f:seek("end")
	f:close()
	return sz or 0
end

local function list_entries(dir)
	local files, dirs = {}, {}
	local h = io.popen('ls -1aF "' .. dir .. '" 2>/dev/null')

	if not h then
		return files, dirs
	end

	for entry in h:lines() do
		if entry ~= "./" and entry ~= "../" then
			if entry:sub(-1) == "/" then
				local name = entry:sub(1, -2)

				if name:sub(1, 1) ~= "." then
					dirs[#dirs + 1] = name
				end
			else
				local name = entry:gsub("[%*%@%|%=]$", "")

				if name:sub(1, 1) ~= "." then
					files[#files + 1] = name
				end
			end
		end
	end

	h:close()
	table.sort(files)
	table.sort(dirs)
	return files, dirs
end

local function total_size(dir)
	local total = 0
	local files, dirs = list_entries(dir)

	for _, name in ipairs(files) do
		total = total + file_size(dir .. "/" .. name)
	end

	for _, name in ipairs(dirs) do
		total = total + total_size(dir .. "/" .. name)
	end

	return total
end

-- Count UTF-8 codepoints (not bytes) so alignment works when the tree
-- includes multi-byte box-drawing chars. Written by hand since Orlando
-- runs on Lua 5.1, which has no `utf8` module.
local function display_len(s)
	local n = 0

	for i = 1, #s do
		local b = s:byte(i)

		if b < 0x80 or b >= 0xC0 then
			n = n + 1
		end
	end

	return n
end

local function walk(dir, prefix, out)
	local files, dirs = list_entries(dir)
	local entries = {}

	for _, name in ipairs(dirs) do
		entries[#entries + 1] = {name = name, is_dir = true}
	end

	for _, name in ipairs(files) do
		entries[#entries + 1] = {name = name, is_dir = false}
	end

	for i, e in ipairs(entries) do
		local is_last = (i == #entries)
		local connector = is_last and "└─ " or "├─ "
		local subprefix = is_last and "   " or "│  "
		local subpath = dir .. "/" .. e.name
		local label = e.name .. (e.is_dir and "/" or "")

		if e.is_dir then
			table.insert(out, {label = prefix .. connector .. label})
			walk(subpath, prefix .. subprefix, out)
		else
			table.insert(out, {
				label = prefix .. connector .. label,
				size  = file_size(subpath),
			})
		end
	end
end

local function render_tree(root)
	local rows = {}
	table.insert(rows, {label = root .. "/"})
	walk(root, "", rows)
	table.insert(rows, {label = "Total", size = total_size(root)})

	local max_label = 0

	for _, row in ipairs(rows) do
		local n = display_len(row.label)

		if n > max_label then
			max_label = n
		end
	end

	local lines = {}

	for _, row in ipairs(rows) do
		if row.size then
			local pad = max_label - display_len(row.label) + 2
			table.insert(lines, row.label .. string.rep(" ", pad) .. format_size(row.size))
		else
			table.insert(lines, row.label)
		end
	end

	return table.concat(lines, "\n")
end

local function html_escape(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function M.handle(_)
	local body_parts = {
		'<h1>Cheat sheet</h1>',
		'<p>Regenerated on every request. Sizes reflect the working tree right now.</p>',
		'<h2>Sources — <code>src/</code></h2>',
		'<pre>' .. html_escape(render_tree("src")) .. '</pre>',
		'<h2>Build artifacts — <code>build/</code></h2>',
		'<pre>' .. html_escape(render_tree("build")) .. '</pre>',
	}

	local body = table.concat(body_parts, "\n")

	local html = page.render_results_page({
		title     = "Cheat sheet",
		body_html = body,
	})

	return {
		status       = "200 OK",
		body         = html,
		content_type = "text/html; charset=utf-8",
		headers      = {"Cache-Control: no-store"},
	}
end

return M
