--[[
{
  "module": "orlando.issue_panel",
  "role":   "Shared issue-card renderer. Used by /issues, the per-doc top-of-page panel, the per-section panels under each H2-H6, AND the github-issues-against directive on audit.md. One format everywhere — bordered card; 'Issue NNN' click-to-copy badge in the heading; full issue body rendered as HTML; inline-toggleable Comment form with resolve checkbox; Close + Comment chips on allow-listed IPs.",
  "exports": {
    "render": "(issue, ctx?) -> HTML string for a single issue card",
    "render_list": "(issues, ctx?) -> concatenated cards"
  },
  "ctx_fields": {
    "can_edit": "boolean — show Comment chip + Close chip + Comment form. Caller sets per ip_can_edit(client_ip)."
  },
  "rendering_pipeline": "issue body is GitHub-flavored markdown; renders inline to HTML via orlando.page.render (lazy-required to avoid module-load cycle). Body headings are first demoted so the shallowest is H4 (one below the card's own H3). Stray tag-shaped text like '<h3>' without backticks is escaped before the markdown render so it doesn't parse as a real tag."
}
]]
local M = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function esc_attr_text(s)
    return ((s or ""):gsub("&", "&amp;")
                     :gsub("<", "&lt;")
                     :gsub(">", "&gt;")
                     :gsub('"', "&quot;"))
end

-- Drop the boilerplate "File: documentation/" prefix from the
-- per-section chip-style issue title so the rendered heading focuses
-- on the path+section. Other titles pass through unchanged.
local function short_title(title)
    title = title or "(no title)"
    return (title:gsub("^File:%s+documentation/", ""))
end

-- Render an issue's labels as a small chip strip. Returns "" when the
-- issue has no labels. Colors come from the GitHub label metadata via
-- a data-attribute so CSS can pick a foreground that reads on light
-- and dark backgrounds; the label chip itself has a shared shape rule.
local function render_labels(labels)
    if type(labels) ~= "table" or #labels == 0 then return "" end
    local parts = { '<span class="issue-labels">' }
    for _, lbl in ipairs(labels) do
        local name  = lbl.name  or ""
        local color = lbl.color or ""
        if name ~= "" then
            parts[#parts + 1] = '<span class="issue-label"'
                .. ' data-color="' .. esc_attr_text(color) .. '">'
                .. esc_attr_text(name)
                .. '</span>'
        end
    end
    parts[#parts + 1] = '</span>'
    return table.concat(parts)
end

-- Shift ATX headings so the shallowest body heading becomes H4 (one
-- level below the issue's own H3). Skips fenced code blocks.
local function shift_body_headings(body)
    if not body or body == "" then return body end

    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    local function walk(cb)
        local in_fence = false
        for i, line in ipairs(lines) do
            if line:match("^```") or line:match("^~~~") then
                in_fence = not in_fence
            elseif not in_fence then
                cb(i, line)
            end
        end
    end

    local min_level
    walk(function(_, line)
        local hashes = line:match("^(#+)%s")
        if hashes and (not min_level or #hashes < min_level) then
            min_level = #hashes
        end
    end)

    if not min_level then return body end
    local delta = math.max(0, 4 - min_level)
    if delta == 0 then return body end

    walk(function(i, line)
        local hashes = line:match("^(#+)%s")
        if hashes then
            local new_n = math.min(6, #hashes + delta)
            lines[i] = string.rep("#", new_n) .. line:sub(#hashes + 1)
        end
    end)

    return table.concat(lines, "\n")
end

-- Escape stray tag-shaped text ("<h3>" / "<div>" without backticks)
-- outside code regions so lunamark doesn't parse it as real HTML.
local function escape_loose_html_in_md(md)
    local out_lines = {}
    local in_fence = false
    for line in (md .. "\n"):gmatch("([^\n]*)\n") do
        local fence = line:match("^```+") or line:match("^~~~+")
        if fence then
            in_fence = not in_fence
            out_lines[#out_lines + 1] = line
        elseif in_fence then
            out_lines[#out_lines + 1] = line
        else
            local buf = {}
            local in_code = false
            local i = 1
            local n = #line
            while i <= n do
                local c = line:sub(i, i)
                if c == "`" then
                    in_code = not in_code
                    buf[#buf + 1] = c
                    i = i + 1
                elseif (not in_code) and c == "<"
                    and line:sub(i + 1, i + 1):match("[/%w]")
                then
                    buf[#buf + 1] = "&lt;"
                    i = i + 1
                else
                    buf[#buf + 1] = c
                    i = i + 1
                end
            end
            out_lines[#out_lines + 1] = table.concat(buf)
        end
    end
    if out_lines[#out_lines] == "" then table.remove(out_lines) end
    return table.concat(out_lines, "\n")
end

-- Lazy-resolve the markdown renderer to break the issue_panel<->page
-- require cycle (page.lua requires issue_panel.lua at module load).
-- Wrap the call in pcall so a malformed issue body (e.g., one that
-- starts with a stray ': ' that lunamark mis-parses as a definition
-- list) doesn't 500 the whole doc page. On failure we fall back to a
-- plaintext <pre> render so the body is at least visible.
local function render_md(md)
    local ok, html = pcall(require("orlando.page").render, md)
    if ok then return html end
    local escaped = (md or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    return '<pre class="issue-body-fallback">' .. escaped .. '</pre>'
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

--[[ {
    "in":  {"issue": "{number, title, body, url}", "ctx": "table? — { can_edit }"},
    "out": "string — HTML for one bordered issue card"
} ]]
function M.render(issue, ctx)
    ctx = ctx or {}
    local can_edit = ctx.can_edit and true or false

    local n = issue.number or 0
    local label = "Issue " .. tostring(n)

    -- Heading: copy badge + short title + chip group (Comment + Close
    -- when allowed). Self-contained — does not rely on inject_issue_links
    -- to attach chips; the page-level chip injector explicitly skips
    -- headings that carry data-issue-number for this reason.
    local chips = ""
    if can_edit then
        chips = ' <span class="nowrap">'
            .. '<button type="button" class="issue-comment section-issue"'
            .. ' data-issue-number="' .. tostring(n) .. '">Comment</button>'
            .. ' <button type="button" class="issue-close section-issue"'
            .. ' data-issue-number="' .. tostring(n) .. '">Close</button>'
            .. '</span>'
    end

    local heading_html = string.format(
        '<h3 id="issue-%d" data-issue-number="%d">'
        .. '<button type="button" class="issue-num-badge"'
        .. ' data-copy="%s" title="Click to copy">%s</button>'
        .. ' — %s'
        .. '%s'
        .. '%s'
        .. '</h3>',
        n, n,
        esc_attr_text(label), esc_attr_text(label),
        esc_attr_text(short_title(issue.title or "(no title)")),
        render_labels(issue.labels),
        chips
    )

    -- Comment form, hidden by default. Toggled by the Comment chip via
    -- the click handler in client-assets/issue-actions.js.
    local comment_form = ""
    if can_edit then
        comment_form = string.format(
            '<form class="issue-comment-form issue-card-comment-form"'
            .. ' data-issue-number="%d" hidden>'
            .. '<textarea name="body" rows="4" required'
            .. ' placeholder="Comment to post to GitHub…"></textarea>'
            .. '<label class="issue-resolve-label">'
            .. '<input type="checkbox" name="resolve">'
            .. ' Mark as resolution — Claude should fix accordingly.'
            .. '</label>'
            .. '<div class="issue-comment-actions">'
            .. '<button type="submit">Post comment</button>'
            .. ' <button type="button" class="issue-comment-cancel">Cancel</button>'
            .. ' <span class="issue-comment-status"></span>'
            .. '</div>'
            .. '</form>',
            n
        )
    end

    -- Render the body markdown to HTML in-card.
    local body_md = issue.body or ""
    local body_html
    if body_md == "" then
        body_html = "<p><em>(no description)</em></p>"
    else
        local prepped = escape_loose_html_in_md(shift_body_headings(body_md))
        body_html = render_md(prepped)
    end

    -- One Type-6 HTML block per card. The opening <div> starts the
    -- block; blank lines around each contained element keep the markdown
    -- pipeline from re-parsing them as inline content.
    return table.concat({
        '<div class="issue-card">',
        '',
        heading_html,
        '',
        comment_form,
        '',
        body_html,
        '',
        '</div>',
    }, "\n")
end

--[[ {
    "in":  {"issues": "array", "ctx": "table?"},
    "out": "string — concatenated cards"
} ]]
function M.render_list(issues, ctx)
    if not issues or #issues == 0 then return "" end
    local parts = {}
    for _, issue in ipairs(issues) do
        parts[#parts + 1] = M.render(issue, ctx)
    end
    return table.concat(parts, "\n")
end

return M
