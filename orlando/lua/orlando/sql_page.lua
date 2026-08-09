--[=[
{
	"module": "orlando.sql_page",
	"role": "Render a .sql source file as a single syntax-highlighted HTML body. No markdown extraction, no chunking — the whole file goes through the SQL highlighter and is wrapped in one <pre><code> block. Comments (--, /* */) stay as SQL comments; the highlighter styles them.",
	"exports": {
		"render_body": "source string -> HTML body string (no page shell, no <html>/<body>); wraps the highlighted source in a single <pre class='highlight sql'><code>...</code></pre>"
	}
}
]=]

local sql_highlight = require("orlando.sql_highlight")

local M = {}

--[[ {
	"in": {"source": "SQL source string"},
	"out": "HTML body string (no <html>/<body> shell) with the whole source syntax-highlighted"
} ]]
function M.render_body(source)
	local highlighted = sql_highlight.highlight(source)
	return '<pre class="highlight sql"><code>' .. highlighted .. '</code></pre>'
end

return M
