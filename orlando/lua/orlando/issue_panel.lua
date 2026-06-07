--[[
{
  "module": "orlando.issue_panel",
  "role":   "Shared issue-panel renderer. Used by /issues, the per-doc top-of-page panel, and the per-section panels under each H2-H6. One format everywhere — 'Issue NNN' copy badge in the head, title, optional doc-link chip, body preview, optional comment-add form and close button (IP-gated), GitHub link in the footer.",
  "exports": {
    "render": "(issue, ctx?) -> HTML string for a single issue panel — see ctx fields below",
    "render_list": "(issues, ctx?) -> HTML string wrapping multiple panels"
  },
  "ctx_fields": {
    "can_edit":           "boolean — show comment-add form + close button. Set by callers per ip_can_edit(client_ip).",
    "show_doc_chip":      "boolean — extract md path from title prefix 'File: <path>' and render as a chip (used on /issues).",
    "show_section_chip":  "boolean — extract section name from title suffix '§ Section' and render as a chip (used on per-doc top-of-page panel).",
    "body_preview_chars": "number — max chars for body preview; 0 means full body. Default 280."
  }
}
]]
local M = {}

local DEFAULT_PREVIEW = 280

local function html_escape(s)
    return (s or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&#39;")
end

-- Collapse internal whitespace and trim — body bodies have newlines that
-- would render with ugly gaps in the preview line.
local function single_line(s)
    s = (s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function truncate(s, max)
    if max <= 0 or #s <= max then return s, false end
    return s:sub(1, max), true
end

-- If the title starts with "File: <path>", extract the path (everything
-- after "File: " up to " §" or end-of-string). Returns the md_path or nil.
local function file_path_from_title(title)
    local body = title:match("^File:%s+(.*)$")
    if not body then return nil end
    local path = body:match("^(.-)%s*§") or body
    path = (path:gsub("%s+$", ""))
    if path == "" then return nil end
    return path
end

-- Extract '§ Section' suffix from the title and return the section name
-- (without the '§'). Returns nil if the title doesn't have a § suffix.
local function section_from_title(title)
    local sect = title:match("§%s*(.-)%s*%(")
    if not sect then sect = title:match("§%s*(.+)$") end
    return sect
end

-- Convert a documentation md_path to its puck.uno-style URL.
local function md_path_to_url(md_path)
    local p = md_path:gsub("^documentation/", "/documentation/")
    p = p:gsub("/index%.md$", "/")
    p = p:gsub("%.md$", "")
    return p
end

--[[ {
    "in":  {"issue": "{number, title, body, url, comments?}", "ctx": "table? — see ctx_fields"},
    "out": "string — HTML for the single issue panel"
} ]]
function M.render(issue, ctx)
    ctx = ctx or {}
    local preview_chars = ctx.body_preview_chars or DEFAULT_PREVIEW

    local n         = issue.number or 0
    local title     = single_line(issue.title or "(no title)")
    local body      = single_line(issue.body or "")
    local body_trim, was_truncated = truncate(body, preview_chars)
    local comment_n = #(issue.comments or {})

    local label = 'Issue ' .. tostring(n)
    local parts = {
        '<article class="issue-panel">',
        '<header class="issue-panel-head">',
        '<button type="button" class="issue-num-badge" data-copy="', html_escape(label),
            '" title="Click to copy">', html_escape(label), '</button>',
        '<h2 class="issue-panel-title">', html_escape(title), '</h2>',
        '</header>',
    }

    if ctx.show_doc_chip then
        local md_path = file_path_from_title(title)
        if md_path then
            local url = md_path_to_url(md_path)
            parts[#parts + 1] = '<div class="issue-panel-doc">↳ '
                .. '<a class="issue-doc-chip" href="' .. html_escape(url) .. '">'
                .. html_escape(md_path) .. '</a></div>'
        end
    end

    if ctx.show_section_chip then
        local sect = section_from_title(title)
        if sect then
            parts[#parts + 1] = '<div class="issue-panel-section">§ '
                .. html_escape(sect) .. '</div>'
        end
    end

    if body_trim ~= "" then
        parts[#parts + 1] = '<div class="issue-panel-body">'
        parts[#parts + 1] = html_escape(body_trim)
        if was_truncated then parts[#parts + 1] = '…' end
        parts[#parts + 1] = '</div>'
    end

    -- Comment-add UI is only rendered when can_edit is set.
    -- /api/comment-issue also 403s non-allow-listed IPs (defense in depth).
    if ctx.can_edit then
        parts[#parts + 1] = table.concat({
            '<details class="issue-comment-add">',
            '<summary>+ Comment</summary>',
            '<form class="issue-comment-form" data-issue-number="', tostring(n), '">',
            '<textarea name="body" rows="3" required ',
                'placeholder="Comment to post to GitHub…"></textarea>',
            '<div class="issue-comment-actions">',
            '<button type="submit">Post comment</button>',
            '<span class="issue-comment-status"></span>',
            '</div>',
            '</form>',
            '</details>',
        })
    end

    parts[#parts + 1] = '<footer class="issue-panel-foot">'
    if comment_n > 0 then
        parts[#parts + 1] = '<span class="issue-panel-comments">'
                         .. tostring(comment_n) .. ' comment'
                         .. (comment_n == 1 and '' or 's')
                         .. '</span>'
    end
    if ctx.can_edit then
        parts[#parts + 1] = '<button type="button" class="issue-close issue-panel-close" '
                         .. 'data-issue-number="' .. tostring(n) .. '">Close</button>'
    end
    parts[#parts + 1] = '<a class="issue-panel-github" href="' .. html_escape(issue.url or "#")
                     .. '" target="_blank" rel="noopener noreferrer">GitHub →</a>'
    parts[#parts + 1] = '</footer>'
    parts[#parts + 1] = '</article>'
    return table.concat(parts)
end

--[[ {
    "in":  {"issues": "array of issue objects", "ctx": "table?"},
    "out": "string — concatenation of issue panels"
} ]]
function M.render_list(issues, ctx)
    if not issues or #issues == 0 then return "" end
    local parts = {}
    for _, issue in ipairs(issues) do
        parts[#parts + 1] = M.render(issue, ctx)
    end
    return table.concat(parts)
end

return M
