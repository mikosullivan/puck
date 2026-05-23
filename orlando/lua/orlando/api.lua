--[[
{
  "module": "orlando.api",
  "role": "Tiny dispatch table for /api/* endpoints. Each handler returns a response table consumed by orlando.server; the server doesn't need to know the endpoint shape.",
  "endpoints": {
    "POST /api/quick-add-issue":  "Form-encoded { title, body } -> shells out to `gh issue create` against mikosullivan/puck and returns a confirmation page with the issue URL.",
    "POST /api/close-issue":      "Form-encoded { number } -> shells out to `gh issue close` and returns JSON ok/error.",
    "GET  /api/section-markdown": "?path=<md_path>&anchor=<id> -> raw markdown for the section (or whole file if anchor omitted). Used to pre-populate the Edit form's textarea.",
    "POST /api/edit-suggestion":  "Form-encoded { path, anchor?, markdown } -> writes the edited section back to the file in place. Gated by edit.allowed_ips; non-allow-listed IPs get 403. No git commit; maintainer manages version control themselves."
  },
  "auth": "Open. No authentication; anyone reaching the endpoint can file issues against the repo. Tightening is deferred per Miko's V0.01 'just make it work' note.",
  "github_auth": "Inherited from the `gh` CLI's stored credentials (~/.config/gh/hosts.yml). No tokens stored in this codebase.",
  "exports": {
    "dispatch": "req { method, path, body } -> response { status, body, content_type }"
  }
}
]]
local issues_fetcher = require("orlando.issues")
local sections       = require("orlando.sections")
local config         = require("orlando.config")
local page_render    = require("orlando.page")

local M = {}

local GH_REPO = "mikosullivan/puck"

local function is_safe_md_path(path)
    if not path or path == "" then return false end
    if path:find("%.%.") then return false end
    if path:find("\\")   then return false end
    if path:sub(1, 1) == "/" then return false end

    if path ~= "README.md" and path:sub(1, #"documentation/") ~= "documentation/" then
        return false
    end

    return path:match("%.md$") ~= nil
end

local function url_decode(s)
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

local function parse_form(body)
    local out = {}
    for kv in (body or ""):gmatch("[^&]+") do
        local k, v = kv:match("^([^=]+)=(.*)$")
        if k then out[url_decode(k)] = url_decode(v) end
    end
    return out
end

-- Wrap a string in single quotes for /bin/sh, escaping any inner '.
local function sh_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function html_escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Returns ok, issue_url_or_error_text.
local function create_issue(title, body)
    local cmd = "gh issue create --repo " .. GH_REPO
        .. " --title " .. sh_quote(title)
        .. " --body "  .. sh_quote(body)
        .. " 2>&1"
    local handle, popen_err = io.popen(cmd, "r")
    if not handle then return false, "io.popen failed: " .. tostring(popen_err) end
    local out = handle:read("*a") or ""
    local ok = handle:close()
    local url = out:match("(https://github%.com/[^%s]+)")
    if ok and url then return true, url end
    return false, out
end

local function page(title, body_html)
    return table.concat({
        '<!DOCTYPE html>\n<html lang="en"><head>',
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        '<title>', title, '</title>',
        '<link rel="stylesheet" href="/client-assets/style.css">',
        '</head><body><main class="content">',
        body_html,
        '</main></body></html>\n',
    })
end

local function handle_quick_add(req)
    if req.method ~= "POST" then
        return {
            status = "405 Method Not Allowed",
            body = "POST required\n",
            content_type = "text/plain; charset=utf-8",
        }
    end
    local form = parse_form(req.body)
    local title, body = form.title or "", form.body or ""
    if title == "" then
        return {
            status = "400 Bad Request",
            body = page("Missing title", "<h1>Missing title</h1>"),
            content_type = "text/html; charset=utf-8",
        }
    end
    local ok, result = create_issue(title, body)
    if ok then
        issues_fetcher.invalidate()
        local html = "<h1>Issue created</h1>"
            .. '<p><a href="' .. result .. '">' .. result .. '</a></p>'
            .. '<p><small>You can close this tab.</small></p>'
        return {
            status = "200 OK",
            body = page("Issue created", html),
            content_type = "text/html; charset=utf-8",
        }
    end
    local html = "<h1>Issue creation failed</h1><pre>"
        .. html_escape(result) .. "</pre>"
    return {
        status = "502 Bad Gateway",
        body = page("Issue creation failed", html),
        content_type = "text/html; charset=utf-8",
    }
end

-- Returns ok, stdout_or_error.
-- Appends `; echo "ORLANDO_EXIT:$?"` so we can read the command's exit code
-- under Lua 5.1, whose io.popen handle :close() doesn't expose it.
local function close_issue(number)
    local cmd = "gh issue close " .. tostring(number)
        .. " --repo " .. GH_REPO
        .. " 2>&1; echo \"ORLANDO_EXIT:$?\""
    local handle, popen_err = io.popen(cmd, "r")
    if not handle then return false, "io.popen failed: " .. tostring(popen_err) end
    local out = handle:read("*a") or ""
    handle:close()
    local exit = out:match("ORLANDO_EXIT:(%d+)%s*$")
    out = out:gsub("ORLANDO_EXIT:%d+%s*$", "")
    if exit == "0" then return true, out end
    return false, out
end

local function json_response(status, ok, payload)
    local body
    if ok then
        body = '{"ok":true}'
    else
        local err = (payload or ""):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
        body = '{"ok":false,"error":"' .. err .. '"}'
    end
    return {
        status = status,
        body = body,
        content_type = "application/json; charset=utf-8",
    }
end

local function handle_close_issue(req)
    if req.method ~= "POST" then
        return json_response("405 Method Not Allowed", false, "POST required")
    end
    local form = parse_form(req.body)
    local number = tonumber(form.number)
    if not number then
        return json_response("400 Bad Request", false, "missing or invalid 'number'")
    end
    local ok, result = close_issue(number)
    if ok then
        issues_fetcher.invalidate()
        return json_response("200 OK", true)
    end
    return json_response("502 Bad Gateway", false, result)
end

-- GET /api/section-markdown?path=<md_path>&anchor=<id>
-- Returns the raw markdown source for a section so the Edit form can
-- pre-populate its textarea. anchor= is optional; omitted/empty returns
-- the whole file (used for the H1 / whole-file edit case).
--
-- Gated by edit.allowed_ips — same allow-list as /api/edit-suggestion.
-- Read-only, but there's no point letting a non-editor fetch section
-- source through this endpoint; the UI doesn't expose it for them and
-- it would otherwise be a section-extraction reconnaissance tool.
local function handle_section_markdown(req)
    if not config.ip_can_edit(req.client_ip) then
        return {
            status = "403 Forbidden",
            body = "edit features are restricted to allow-listed IPs\n",
            content_type = "text/plain; charset=utf-8",
        }
    end

    if req.method ~= "GET" then
        return {
            status = "405 Method Not Allowed",
            body = "GET required\n",
            content_type = "text/plain; charset=utf-8",
        }
    end

    local qs = (req.path or ""):match("%?(.*)$") or ""
    local form = parse_form(qs)
    local md_path = form.path or ""
    local anchor  = form.anchor or ""

    if not is_safe_md_path(md_path) then
        return {
            status = "400 Bad Request",
            body = "missing or unsafe 'path'\n",
            content_type = "text/plain; charset=utf-8",
        }
    end

    local body = sections.section_for(md_path, anchor)

    if not body then
        return {
            status = "404 Not Found",
            body = "section not found\n",
            content_type = "text/plain; charset=utf-8",
        }
    end

    return {
        status = "200 OK",
        body = body,
        content_type = "text/plain; charset=utf-8",
    }
end

-- Replace one section's text in a markdown file. Anchor "" means
-- "whole file" — overwrite the entire file with new_markdown. For a
-- named section, find the section's current text (per orlando.sections)
-- and substitute the new text in its place. Returns ok, err_message.
--
-- Browsers send textarea data with CRLF line endings (per the HTML
-- form-encoding spec); the rest of the doc tree uses LF. Mixed
-- line endings make lunamark fail to parse the file at all, so
-- normalize \r\n → \n (and stray \r → \n) before writing.
--
-- Refuses to write if:
--   - the section's current text isn't found (caller's view is stale)
--   - the section's current text appears more than once in the file
--     (ambiguous match — wrong section could get edited)
local function save_section(md_path, anchor, new_markdown)
    new_markdown = new_markdown:gsub("\r\n", "\n"):gsub("\r", "\n")

    if anchor == "" then
        local f, err = io.open(md_path, "wb")
        if not f then return false, "cannot open " .. md_path .. " for writing: " .. tostring(err) end
        f:write(new_markdown)
        f:close()
        return true
    end

    local old_section = sections.section_for(md_path, anchor)
    if not old_section then
        return false, "section '" .. anchor .. "' not found in " .. md_path
    end

    local rf, rerr = io.open(md_path, "rb")
    if not rf then return false, "cannot read " .. md_path .. ": " .. tostring(rerr) end
    local content = rf:read("*a")
    rf:close()

    local start_idx = content:find(old_section, 1, true)
    if not start_idx then
        return false, "section text no longer matches the file — page may be stale, please reload"
    end

    local second_idx = content:find(old_section, start_idx + 1, true)
    if second_idx then
        return false, "section text appears more than once in the file — refusing to edit (ambiguous)"
    end

    local before = content:sub(1, start_idx - 1)
    local after  = content:sub(start_idx + #old_section)
    local new_content = before .. new_markdown .. after

    local wf, werr = io.open(md_path, "wb")
    if not wf then return false, "cannot open " .. md_path .. " for writing: " .. tostring(werr) end
    wf:write(new_content)
    wf:close()
    return true
end

-- POST /api/edit-suggestion
-- Form fields: path, anchor (optional), markdown, section_title (optional)
-- Writes the edited section back to the file in place. Gated by
-- edit.allowed_ips — the Edit UI is hidden in page chrome for
-- non-allow-listed IPs, but this server-side check is the
-- authoritative gate.
--
-- No git commit, no backup file, no diff snapshot. The maintainer is
-- expected to manage version control themselves (the docs live in a
-- git repo; revert via `git checkout` if a save was wrong).
local function handle_edit_suggestion(req)
    if not config.ip_can_edit(req.client_ip) then
        return {
            status = "403 Forbidden",
            body = page("Forbidden", "<h1>403 Forbidden</h1>"
                .. "<p>Edit features are restricted to allow-listed IPs.</p>"),
            content_type = "text/html; charset=utf-8",
        }
    end

    if req.method ~= "POST" then
        return {
            status = "405 Method Not Allowed",
            body = "POST required\n",
            content_type = "text/plain; charset=utf-8",
        }
    end

    local form = parse_form(req.body)
    local md_path = form.path or ""
    local anchor   = form.anchor or ""
    local markdown = form.markdown or ""

    if not is_safe_md_path(md_path) then
        return {
            status = "400 Bad Request",
            body = page("Bad request", "<h1>Missing or unsafe 'path'</h1>"),
            content_type = "text/html; charset=utf-8",
        }
    end

    if markdown == "" then
        return {
            status = "400 Bad Request",
            body = page("Empty edit", "<h1>Empty edit body</h1>"
                .. "<p>To delete a section, clear it from the source file directly.</p>"),
            content_type = "text/html; charset=utf-8",
        }
    end

    local ok, err = save_section(md_path, anchor, markdown)

    if not ok then
        return {
            status = "409 Conflict",
            body = page("Edit failed", "<h1>Edit failed</h1><pre>"
                .. html_escape(err or "") .. "</pre>"),
            content_type = "text/html; charset=utf-8",
        }
    end

    -- Re-render the page from scratch using the same pipeline as a
    -- normal GET. The client (edit.js) reads <main class="content">
    -- out of this response and swaps it into the live page, so the
    -- user sees the rendered edit immediately without reloading.
    --
    -- A meta marker in <head> tells edit.js this iframe response is a
    -- successful save (vs an unrelated page load); the anchor of the
    -- edited section is included so the client could scroll to it
    -- later if desired.
    local title = md_path == "README.md" and "Puck"
        or (md_path:match("([^/]+)%.md$") or md_path)
    local rendered = page_render.render_request({
        md_path   = md_path,
        title     = title,
        client_ip = req.client_ip,
    })

    local marker = '<meta name="orlando-edit-saved" content="'
        .. html_escape(anchor) .. '">'
    rendered = rendered:gsub("(<head>)", "%1" .. marker, 1)

    return {
        status = "200 OK",
        body = rendered,
        content_type = "text/html; charset=utf-8",
    }
end

--[[ {
    "in":  {"req": "{method=string, path=string, body=string?}"},
    "out": "{status=string, body=string, content_type=string} | nil (nil = not an /api/ path)"
} ]]
function M.dispatch(req)
    if req.path == "/api/quick-add-issue" then
        return handle_quick_add(req)
    end

    if req.path == "/api/close-issue" then
        return handle_close_issue(req)
    end

    if req.path == "/api/edit-suggestion" then
        return handle_edit_suggestion(req)
    end

    -- section-markdown is GET with query string; match on the path prefix.
    if req.path and req.path:sub(1, #"/api/section-markdown") == "/api/section-markdown" then
        return handle_section_markdown(req)
    end

    return {
        status = "404 Not Found",
        body = "API endpoint not found\n",
        content_type = "text/plain; charset=utf-8",
    }
end

return M
