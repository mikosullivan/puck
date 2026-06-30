--[[
{
  "module": "orlando.issues_page",
  "role": "Render /issues — a single page listing every open GitHub issue in the repo. Uses orlando.issues for the cached fetch (one gh call per cache window covers all issues, no extra cost beyond what the per-doc panel already pays). Rendering is delegated to orlando.issue_panel so /issues and the doc-page panels share one format.",
  "exports": {
    "render": "(client_ip?) -> full HTML page (title + per-issue rows)",
    "handle": "{path, client_ip} -> {status, body, content_type} — server-facing entry"
  },
  "ordering": "issue number descending (newest first)"
}
]]
local issues       = require("orlando.issues")
local page         = require("orlando.page")
local config       = require("orlando.config")
local issue_panel  = require("orlando.issue_panel")

local M = {}

local function render_body(all_issues, can_edit)
    local count = #all_issues
    -- Sort by issue number descending (newest first).
    table.sort(all_issues, function(a, b)
        return (a.number or 0) > (b.number or 0)
    end)

    -- Styles for this page live in orlando/client-assets/style.css under
    -- the "/issues page" section. No inline styles — Orlando's CSP forbids them.
    local parts = {
        '<div class="issues-page">',
        '<div class="issues-summary">',
        tostring(count), ' open issue', (count == 1 and '' or 's'),
        ' — sorted by issue number, newest first',
        '</div>',
    }
    if can_edit then
        parts[#parts + 1] = '<div class="issues-toolbar">'
            .. '<button type="button" class="issues-refresh">Refresh from GitHub</button>'
            .. '</div>'
    end
    if count == 0 then
        parts[#parts + 1] = '<p>No open issues. Either the repo is in great shape, or <code>gh</code> is unavailable.</p>'
    else
        parts[#parts + 1] = issue_panel.render_list(all_issues, {
            can_edit      = can_edit,
            show_doc_chip = true,
        })
    end
    parts[#parts + 1] = '</div>'
    return table.concat(parts)
end

--[[ {
    "in":  {"client_ip": "string? — used to gate the comment-add UI per edit.allowed_ips"},
    "out": "string — full HTML page with site chrome (uses page.render_results_page)"
} ]]
function M.render(client_ip)
    local all = issues.fetch_all()
    local can_edit = client_ip ~= nil and config.ip_can_edit(client_ip)
    local body = render_body(all, can_edit)
    return page.render_results_page({
        title     = "Open Issues",
        body_html = body,
    })
end

--[[ {
    "in":  {"req": "{path, client_ip} — server-supplied"},
    "out": "{status, body, content_type}"
} ]]
function M.handle(req)
    req = req or {}
    return {
        status       = "200 OK",
        body         = M.render(req.client_ip),
        content_type = "text/html; charset=utf-8",
    }
end

return M
