--[[
{
  "module": "orlando.issues",
  "role": "Fetch open GitHub issues (with their comments) for a documentation page via the gh CLI, with simple in-memory TTL caching. Issues are matched by title prefix 'File: <md_path>' — the convention the per-section 'Quick add' panel uses.",
  "exports": {
    "fetch": "md_path -> list of {number, title, body, url, comments}; [] on failure, no issues, or no gh. Each comment is {author, created_at, body}."
  },
  "implementation": "single `gh issue list ... --jq` shell-out per cache window covers the whole repo. jq emits two record types per issue, one per line: 'I' lines for the issue itself, 'C' lines for each of its comments (with the parent issue number as the second field). gh bundles jq, so no Lua-side JSON parser is needed. The body field has its newlines pre-escaped via @tsv; we unescape after splitting.",
  "caching": "module-local table; CACHE_TTL_SECONDS controls staleness. Fetch failures don't poison the cache — they return [] (or the previous cached value) and the next request retries."
}
]]
local M = {}

local CACHE_TTL_SECONDS = 600  -- 10 minutes
local REPO = "mikosullivan/puck"

local cache_fetched_at = 0
local cache_issues = nil  -- nil = never fetched; {} = fetched, empty

local function now() return os.time() end

-- Build the gh command. --jq emits two record types, one per line:
--   I<TAB>number<TAB>title<TAB>url<TAB>body
--   C<TAB>parent_number<TAB>author<TAB>created_at<TAB>body
-- @tsv escapes \n, \t, and \\ in each field automatically, so the only
-- preprocessing we do is strip \r (GitHub serves CRLF bodies). Lua
-- long-bracket string keeps the jq escapes literal.
local function gh_command()
    local jq_filter = [[.[] | . as $i | (
        ["I", ($i.number|tostring), $i.title, $i.url, (($i.body // "") | gsub("\r"; ""))] | @tsv,
        ($i.comments[]? | ["C", ($i.number|tostring), (.author.login // ""), .createdAt, ((.body // "") | gsub("\r"; ""))] | @tsv)
    )]]
    return string.format(
        "gh issue list --repo %s --state open --limit 200 --json number,title,body,url,comments --jq '%s' 2>/dev/null",
        REPO, jq_filter)
end

-- Reverse @tsv's escaping: \n -> newline, \t -> tab, \r -> CR, \\ -> \.
-- Single-pass so escape sequences in adjacent positions don't interfere.
local function unescape_body(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == "\\" and i < n then
            local nx = s:sub(i + 1, i + 1)
            if nx == "n" then out[#out + 1] = "\n"
            elseif nx == "t" then out[#out + 1] = "\t"
            elseif nx == "r" then out[#out + 1] = "\r"
            elseif nx == "\\" then out[#out + 1] = "\\"
            else out[#out + 1] = c .. nx end
            i = i + 2
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

local function split_tsv(line)
    local fields = {}
    local start = 1
    for sep in line:gmatch("\t()") do
        fields[#fields + 1] = line:sub(start, sep - 2)
        start = sep
    end
    fields[#fields + 1] = line:sub(start)
    return fields
end

local function fetch_all_from_gh()
    local handle = io.popen(gh_command(), "r")
    if not handle then return nil end
    local out = handle:read("*a") or ""
    handle:close()
    if out == "" then return nil end

    local issues = {}
    local by_number = {}
    for line in out:gmatch("([^\n]+)") do
        local f = split_tsv(line)
        local kind = f[1] or ""
        if kind == "I" and #f >= 4 then
            local issue = {
                number   = tonumber(f[2]),
                title    = f[3] or "",
                url      = f[4] or "",
                body     = unescape_body(f[5] or ""),
                comments = {},
            }
            issues[#issues + 1] = issue
            if issue.number then by_number[issue.number] = issue end
        elseif kind == "C" and #f >= 5 then
            local parent = by_number[tonumber(f[2])]
            if parent then
                parent.comments[#parent.comments + 1] = {
                    author     = f[3] or "",
                    created_at = f[4] or "",
                    body       = unescape_body(f[5] or ""),
                }
            end
        end
    end
    return issues
end

local function all_open_issues()
    if cache_issues and (now() - cache_fetched_at) < CACHE_TTL_SECONDS then
        return cache_issues
    end
    local fresh = fetch_all_from_gh()
    if fresh then
        cache_issues = fresh
        cache_fetched_at = now()
        return fresh
    end
    return cache_issues or {}
end

--[[ {
    "in":  {"md_path": "string — e.g. 'documentation/ideas/github/puck-site/gitter.md'"},
    "out": "list of {number, title, body, url} — open issues whose title starts with 'File: <md_path>'",
    "note": "Match is anchored at the path; the title may continue with ' § Section …' or end there. Pages with no matches, gh unavailable, or any failure all yield {}."
} ]]
function M.fetch(md_path)
    if not md_path or md_path == "" then return {} end
    local prefix = "File: " .. md_path
    local matching = {}
    for _, issue in ipairs(all_open_issues()) do
        local title = issue.title or ""
        if title:sub(1, #prefix) == prefix then
            local rest = title:sub(#prefix + 1)
            if rest == "" or rest:sub(1, 1) == " " then
                matching[#matching + 1] = issue
            end
        end
    end
    return matching
end

--[[ {
    "in":  {"md_path": "string", "anchor": "string — heading id, e.g. 'open-questions'"},
    "out": "list of {number, title, body, url} — open issues whose title matches the page AND ends with ' (#<anchor>)'",
    "note": "Subset of M.fetch's result; same cache, different filter. Returns {} for missing md_path or anchor."
} ]]
function M.fetch_section(md_path, anchor)
    if not md_path or md_path == "" then return {} end
    if not anchor or anchor == "" then return {} end
    local suffix = "(#" .. anchor .. ")"
    local matching = {}
    for _, issue in ipairs(M.fetch(md_path)) do
        local title = issue.title or ""
        if title:sub(-#suffix) == suffix then
            matching[#matching + 1] = issue
        end
    end
    return matching
end

--[[ {
    "in":  {},
    "out": "list of all open issues, same shape as M.fetch returns. Used by /issues to render the full list — bypasses the per-doc filter.",
    "note": "Same cache as M.fetch; one shared in-memory copy of the gh result."
} ]]
function M.fetch_all()
    return all_open_issues()
end

--[[ {
    "out": "nothing",
    "note": "Drop the cached issue list so the next call refetches. Used after writes (close, reopen, comment) so the panel reflects the change."
} ]]
function M.invalidate()
    cache_issues = nil
    cache_fetched_at = 0
end

return M
