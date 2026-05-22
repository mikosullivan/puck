#!/usr/bin/env lua
--[[
{
  "file": "orlando/lua/check-links.lua",
  "role": "Standalone CLI: crawl a running Orlando instance over HTTP, collect every internal <a href>, and report broken links — pages that return non-2xx, and links whose #fragment doesn't match any id on the target page. Optionally files the results as a GitHub issue against mikosullivan/puck.",
  "usage": "lua orlando/lua/check-links.lua [--base URL] [--issue]",
  "defaults": {
    "base":  "http://127.0.0.1:8181",
    "issue": false
  },
  "scope": "Internal links only — anything starting with '/', or relative paths. http(s)://other.host links are reported as 'skipped (external)' and not fetched. Anchor existence is checked against id='...' attributes present in the rendered HTML.",
  "github_auth": "When --issue is given, shells out to `gh issue create`; relies on the gh CLI's stored credentials."
}
]]
package.path = "./orlando/lua/?.lua;./orlando/lua/?/init.lua;" .. package.path
local home = os.getenv("HOME")
if home then
    package.path  = home .. "/.luarocks/share/lua/5.1/?.lua;"
                 .. home .. "/.luarocks/share/lua/5.1/?/init.lua;"
                 .. package.path
    package.cpath = home .. "/.luarocks/lib/lua/5.1/?.so;" .. package.cpath
end

local http = require("socket.http")
http.TIMEOUT = 5

local GH_REPO = "mikosullivan/puck"

------------------------------------------------------------
-- CLI args
------------------------------------------------------------
local base_url    = "http://127.0.0.1:8181"
local file_issue  = false
local start_path  = "/documentation/"
local i = 1
while arg and arg[i] do
    if arg[i] == "--base" then
        base_url = arg[i + 1]; i = i + 2
    elseif arg[i] == "--issue" then
        file_issue = true; i = i + 1
    elseif arg[i] == "--start" then
        start_path = arg[i + 1]; i = i + 2
    elseif arg[i] == "-h" or arg[i] == "--help" then
        print("usage: lua orlando/lua/check-links.lua [--base URL] [--start PATH] [--issue]")
        os.exit(0)
    else
        io.stderr:write("unknown arg: " .. arg[i] .. "\n"); os.exit(2)
    end
end
base_url = base_url:gsub("/+$", "")

------------------------------------------------------------
-- URL utilities
------------------------------------------------------------
local function split_url(url)
    local path, frag = url:match("^([^#]*)(#.*)$")
    if not path then path, frag = url, "" end
    return path, frag
end

local function is_external(href)
    return href:match("^https?://") ~= nil
end

local function is_skippable(href)
    if href == "" then return true end
    if href:sub(1, 7) == "mailto:" then return true end
    if href:sub(1, 11) == "javascript:" then return true end
    if href:sub(1, 5) == "data:" then return true end
    if href:sub(1, 4) == "tel:" then return true end
    return false
end

-- Resolve `href` against `source_path` (the URL path of the page that
-- contained it). source_path is always Orlando-internal (starts with /).
local function resolve(href, source_path)
    if href:sub(1, 1) == "#" then
        return source_path .. href
    end
    if href:sub(1, 1) == "/" then
        return href
    end
    -- Relative: join with directory of source_path, then normalize ./ and
    -- ../ by walking segments (regex collapsing is brittle when '..' itself
    -- appears as a segment name).
    local dir = source_path:match("^(.*/)") or "/"
    local joined = dir .. href
    local path, frag = split_url(joined)
    local trailing = path:sub(-1) == "/" and "/" or ""
    local segs = {}
    for seg in path:gmatch("[^/]+") do segs[#segs + 1] = seg end
    local out = {}
    for _, seg in ipairs(segs) do
        if seg == "." then
            -- drop
        elseif seg == ".." then
            if #out > 0 then table.remove(out) end
        else
            out[#out + 1] = seg
        end
    end
    return "/" .. table.concat(out, "/") .. trailing .. frag
end

-- GitHub-style line references (#L42, #L42-L50) are not expected to be
-- present on Orlando-rendered pages — they only resolve on github.com.
-- Filter them out of the broken-link report.
local function is_line_ref_fragment(frag)
    if frag == "" then return false end
    return frag:match("^#L%d+$") ~= nil
        or frag:match("^#L%d+%-L%d+$") ~= nil
end

------------------------------------------------------------
-- HTTP
------------------------------------------------------------
-- Fetch with explicit redirect handling. Returns body, status, redirect_to.
-- We disable luasocket's auto-follow so a 301 doesn't masquerade as a 200
-- with relative links resolving against the wrong base. When we see a
-- redirect we return its Location so the caller can enqueue the canonical
-- form (and skip processing the bare-URL body).
local function fetch(path)
    local url = base_url .. path
    local sink_chunks = {}
    local ok, status, headers = http.request{
        url = url,
        redirect = false,
        sink = function(chunk, err)
            if chunk then sink_chunks[#sink_chunks + 1] = chunk end
            return 1
        end,
    }
    if not ok then
        return nil, tostring(status)
    end
    local body = table.concat(sink_chunks)
    if status == 301 or status == 302 or status == 307 or status == 308 then
        local loc = headers and (headers.location or headers["Location"])
        return body, status, loc
    end
    return body, status
end

------------------------------------------------------------
-- HTML extraction (regex-grade — Orlando output is predictable)
------------------------------------------------------------
local function extract_anchors(html)
    local ids = {}
    for id in html:gmatch('id="([^"]+)"') do ids[id] = true end
    for name in html:gmatch('name="([^"]+)"') do ids[name] = true end
    return ids
end

local function extract_hrefs(html)
    local out = {}
    -- href="..." inside <a ...> tags only — skip <link href> in <head>.
    for tag in html:gmatch("<a%s[^>]+>") do
        local href = tag:match('href="([^"]+)"')
        if href then out[#out + 1] = href end
    end
    return out
end

------------------------------------------------------------
-- Crawl
------------------------------------------------------------
local pages    = {}   -- url_path -> { ok, status, anchors, hrefs }
local queue    = {}
local enqueued = {}

local function enqueue(path)
    if not enqueued[path] then
        enqueued[path] = true
        queue[#queue + 1] = path
    end
end
enqueue(start_path)
enqueue("/")  -- the hand-edited landing page

-- Mark a path as a redirect so the verification pass treats links to it
-- as valid (the canonical target is also enqueued and verified separately).
local redirects = {}  -- path -> Location

-- Sanity check: if Orlando isn't reachable at all, abort early. A daily
-- cron shouldn't file "every link broken" because the server happened to
-- be down at 00:40.
io.stderr:write("crawling " .. base_url .. " ...\n")
do
    local body, status = fetch(start_path)
    if not body and not status then
        io.stderr:write("ABORT: " .. base_url .. start_path
            .. " unreachable; not filing issue.\n")
        os.exit(2)
    end
    if status and type(status) == "number" and status >= 500 then
        io.stderr:write("ABORT: " .. base_url .. start_path
            .. " returned " .. status .. "; not filing issue.\n")
        os.exit(2)
    end
end

while #queue > 0 do
    local path = table.remove(queue, 1)
    local body, status, redirect_to = fetch(path)
    local entry = { ok = false, status = tostring(status), anchors = {}, hrefs = {} }
    if redirect_to then
        -- Don't parse the redirect-response body — its relative links
        -- would resolve against this URL's dir, not the canonical
        -- target's. Mark as redirect; enqueue the target for crawling.
        entry.ok = true  -- the URL itself is reachable
        entry.redirect = redirect_to
        redirects[path] = redirect_to
        if redirect_to:sub(1, 1) == "/" then
            enqueue(redirect_to)
        end
    elseif not body then
        entry.error = status
    elseif status >= 200 and status < 300 then
        entry.ok = true
        entry.anchors = extract_anchors(body)
        entry.hrefs   = extract_hrefs(body)
    end
    pages[path] = entry
    io.stderr:write(("  [%s] %s\n"):format(entry.status, path))

    -- Queue internal links we haven't seen yet (skipping redirect responses).
    for _, href in ipairs(entry.hrefs) do
        if not is_skippable(href) and not is_external(href) then
            local target_path, _ = split_url(resolve(href, path))
            if target_path and target_path:sub(1, 1) == "/" then
                enqueue(target_path)
            end
        end
    end
end

------------------------------------------------------------
-- Verify every link
------------------------------------------------------------
-- broken[source_path] = list of { href, reason }
local broken = {}
local function add_broken(source, href, reason)
    if not broken[source] then broken[source] = {} end
    table.insert(broken[source], { href = href, reason = reason })
end

local external_count, skipped_count, line_ref_count = 0, 0, 0

for source_path, entry in pairs(pages) do
    if entry.ok then
        for _, href in ipairs(entry.hrefs) do
            if is_skippable(href) then
                skipped_count = skipped_count + 1
            elseif is_external(href) then
                external_count = external_count + 1
            else
                local resolved = resolve(href, source_path)
                local target_path, frag = split_url(resolved)
                if is_line_ref_fragment(frag) then
                    line_ref_count = line_ref_count + 1
                else
                    local target = pages[target_path]
                    -- Follow redirects (one hop) for anchor lookups so a
                    -- link to /foo/bar#anchor finds anchors on the final
                    -- /foo/bar/ page that bar 301s to.
                    local anchor_target = target
                    local anchor_target_path = target_path
                    if target and target.redirect then
                        local redir = redirects[target_path]
                        local hop = redir and pages[redir]
                        if hop then
                            anchor_target = hop
                            anchor_target_path = redir
                        end
                    end
                    if not target or not target.ok then
                        local status = target and target.status or "not fetched"
                        add_broken(source_path, href, "target " .. target_path
                            .. " returned " .. status)
                    elseif frag and frag ~= "" then
                        local id = frag:sub(2)  -- strip leading '#'
                        if not anchor_target.anchors[id] then
                            add_broken(source_path, href,
                                "anchor #" .. id .. " not present on " .. anchor_target_path)
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Report
------------------------------------------------------------
local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local total_broken = 0
for _, list in pairs(broken) do total_broken = total_broken + #list end

local lines = {}
local function emit(s) lines[#lines + 1] = s end

local pages_crawled = 0
for _ in pairs(pages) do pages_crawled = pages_crawled + 1 end

emit("Dead-link report — " .. os.date("%Y-%m-%d %H:%M"))
emit("")
emit(("Crawled %d pages from %s starting at %s."):format(
    pages_crawled, base_url, start_path))
emit(("External links not fetched: %d. Skipped (mailto/etc): %d. GitHub line-refs ignored: %d.")
    :format(external_count, skipped_count, line_ref_count))
emit("")
if total_broken == 0 then
    emit("No broken internal links found.")
else
    emit("**" .. total_broken .. " broken internal link(s) across "
        .. (function() local n=0; for _ in pairs(broken) do n=n+1 end; return n end)()
        .. " page(s):**")
    emit("")
    for _, source in ipairs(sorted_keys(broken)) do
        emit("### `" .. source .. "`")
        emit("")
        for _, item in ipairs(broken[source]) do
            emit("- `" .. item.href .. "` — " .. item.reason)
        end
        emit("")
    end
end

local report = table.concat(lines, "\n")
io.write(report, "\n")

------------------------------------------------------------
-- Optionally file as a GitHub issue
------------------------------------------------------------
if file_issue then
    local date = os.date("%Y-%m-%d")
    local title = total_broken == 0
        and ("Daily link check — " .. date .. " — all clear")
        or  ("Daily link check — " .. date .. " — " .. total_broken .. " broken")
    -- Write body to a temp file to avoid shell quoting on multi-line content.
    local tmp = os.tmpname()
    local f = assert(io.open(tmp, "w"))
    f:write(report)
    f:close()
    local cmd = "gh issue create --repo " .. GH_REPO
        .. " --title " .. ("'" .. title:gsub("'", "'\\''") .. "'")
        .. " --label link-check"
        .. " --body-file " .. tmp
        .. " 2>&1"
    local handle = io.popen(cmd, "r")
    local out = handle:read("*a") or ""
    handle:close()
    os.remove(tmp)
    io.stderr:write("\n--- gh issue create ---\n" .. out)
end

os.exit(total_broken == 0 and 0 or 1)
