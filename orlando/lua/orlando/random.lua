--[[
{
  "module": "orlando.random",
  "role": "Random-page endpoint. Picks a uniformly random markdown source (README.md + documentation/**/*.md) and 302-redirects to its canonical URL. Uses Lua's standard math.random — the server (orlando.server) seeds it once at startup with os.time().",
  "exports": {
    "pick":   "() -> md_path string, or nil if the doc tree is empty",
    "handle": "request_path (unused) -> { status, body, content_type, headers[] } — server-facing entry"
  },
  "redirect": "302 Found with Location header and Cache-Control: no-store so refresh re-rolls"
}
]]
local page   = require("orlando.page")
local search = require("orlando.search")

local M = {}

--[[ {
    "in":  {},
    "out": "string (md path) | nil"
} ]]
function M.pick()
    local files = search.list_md_files()
    if #files == 0 then return nil end
    return files[math.random(#files)]
end

--[[ {
    "in":  {"_": "request path (unused)"},
    "out": "{status, body, content_type, headers[]}"
} ]]
function M.handle(_)
    local md_path = M.pick()

    if not md_path then
        return {
            status       = "503 Service Unavailable",
            body         = "No pages available\n",
            content_type = "text/plain; charset=utf-8",
        }
    end

    local url = page.md_path_to_url(md_path)
    local body = '<!DOCTYPE html><html><body>Random page: <a href="'
              .. url .. '">' .. url .. '</a></body></html>\n'
    return {
        status       = "302 Found",
        body         = body,
        content_type = "text/html; charset=utf-8",
        headers      = { "Location: " .. url, "Cache-Control: no-store" },
    }
end

return M
