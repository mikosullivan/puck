--[[
{
  "module": "orlando.api",
  "role": "Tiny dispatch table for /api/* endpoints. Each handler returns a response table consumed by orlando.server; the server doesn't need to know the endpoint shape.",
  "endpoints": {
    "POST /api/quick-add-issue": "Form-encoded { title, body } -> shells out to `gh issue create` against mikosullivan/puck and returns a confirmation page with the issue URL."
  },
  "auth": "Open. No authentication; anyone reaching the endpoint can file issues against the repo. Tightening is deferred per Miko's V0.01 'just make it work' note.",
  "github_auth": "Inherited from the `gh` CLI's stored credentials (~/.config/gh/hosts.yml). No tokens stored in this codebase.",
  "exports": {
    "dispatch": "req { method, path, body } -> response { status, body, content_type }"
  }
}
]]
local issues_fetcher = require("orlando.issues")

local M = {}

local GH_REPO = "mikosullivan/puck"

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
    return {
        status = "404 Not Found",
        body = "API endpoint not found\n",
        content_type = "text/plain; charset=utf-8",
    }
end

return M
