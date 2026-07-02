--[[
{
  "module": "orlando.issues",
  "role": "Local persistent cache of open GitHub issues for the puck repo. The cache is the source of truth for page rendering — gh is only consulted on first run (to seed) or on explicit refresh. Mutations (add_issue, remove_issue, add_comment) keep the cache in sync as Orlando's own UI fires gh writes; external gh changes need a refresh via /api/refresh-issues.",
  "exports": {
    "fetch":         "md_path -> list of issues whose title starts with 'File: <md_path>'",
    "fetch_section": "md_path, anchor -> issues whose title also ends with '(#<anchor>)'",
    "fetch_all":     "() -> all cached open issues",
    "add_issue":     "{number, title, body, url} -> append to cache, persist",
    "remove_issue":  "number -> drop from cache, persist",
    "add_comment":   "number, {author, created_at, body} -> append to that issue's comments, persist",
    "refresh_from_gh": "() -> re-pull from gh, replace cache, persist; returns ok"
  },
  "storage": "~/.orlando/issues-cache.json — same parent dir as config.json. Atomic write via tmp file + rename.",
  "implementation": "Each issue is {number, title, body, url, comments=[{author, created_at, body}, ...], labels=[{name, color}, ...]}. Empty comments and labels arrays use cjson.empty_array_mt so they round-trip as [] not {}. The gh fetch uses --jq to emit one tsv line per issue, one per comment, and one per label, parsed in a single pass.",
  "first_run": "If the cache file is missing on first access, refresh_from_gh() runs automatically to seed. Empty seed (no issues / no gh) becomes an empty cache; subsequent fetches return []."
}
]]
local cjson = require("cjson")

local M = {}

local REPO = "mikosullivan/puck"

local function home()       return os.getenv("HOME") or "" end
local function cache_dir()  return home() .. "/.orlando" end
local function cache_path() return cache_dir() .. "/issues-cache.json" end

-- In-memory cache. nil until first access; an empty table after that
-- (even when no issues exist) so we know we've loaded.
local cache = nil

-- =====================================================================
-- gh-fetch — used only for the initial seed and explicit refresh.
-- =====================================================================

local function gh_command()
    local jq_filter = [[.[] | . as $i | (
        ["I", ($i.number|tostring), $i.title, $i.url, (($i.body // "") | gsub("\r"; ""))] | @tsv,
        ($i.comments[]? | ["C", ($i.number|tostring), (.author.login // ""), .createdAt, ((.body // "") | gsub("\r"; ""))] | @tsv),
        ($i.labels[]? | ["L", ($i.number|tostring), .name, (.color // "")] | @tsv)
    )]]
    return string.format(
        "gh issue list --repo %s --state open --limit 200 --json number,title,body,url,comments,labels --jq '%s' 2>/dev/null",
        REPO, jq_filter)
end

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

local function fresh_comments_array()
    return setmetatable({}, cjson.empty_array_mt)
end

local function fresh_labels_array()
    return setmetatable({}, cjson.empty_array_mt)
end

local function fetch_all_from_gh()
    local handle = io.popen(gh_command(), "r")
    if not handle then return nil end
    local out = handle:read("*a") or ""
    handle:close()
    if out == "" then return {} end

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
                comments = fresh_comments_array(),
                labels   = fresh_labels_array(),
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
        elseif kind == "L" and #f >= 3 then
            local parent = by_number[tonumber(f[2])]
            if parent then
                parent.labels[#parent.labels + 1] = {
                    name  = f[3] or "",
                    color = f[4] or "",
                }
            end
        end
    end
    return issues
end

-- =====================================================================
-- Disk I/O — load and persist the cache as JSON.
-- =====================================================================

local function ensure_cache_dir()
    os.execute("mkdir -p " .. cache_dir())
end

local function load_from_disk()
    local f = io.open(cache_path(), "rb")
    if not f then return nil end
    local raw = f:read("*a") or ""
    f:close()
    if raw == "" then return nil end

    local ok, parsed = pcall(cjson.decode, raw)
    if not ok or type(parsed) ~= "table" then return nil end

    for _, issue in ipairs(parsed) do
        if type(issue.comments) ~= "table" then
            issue.comments = fresh_comments_array()
        else
            setmetatable(issue.comments, cjson.empty_array_mt)
        end

        if type(issue.labels) ~= "table" then
            issue.labels = fresh_labels_array()
        else
            setmetatable(issue.labels, cjson.empty_array_mt)
        end
    end
    return parsed
end

local function save_to_disk()
    if not cache then return end
    ensure_cache_dir()
    local ok, encoded = pcall(cjson.encode, cache)
    if not ok then return end
    local tmp = cache_path() .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return end
    f:write(encoded)
    f:close()
    os.rename(tmp, cache_path())
end

local function ensure_loaded()
    if cache then return end
    local from_disk = load_from_disk()
    if from_disk then
        cache = from_disk
        return
    end
    -- First run (or wiped cache): seed from gh.
    local seeded = fetch_all_from_gh()
    cache = seeded or {}
    save_to_disk()
end

-- =====================================================================
-- Readers
-- =====================================================================

--[[ {
    "in":  {"md_path": "string"},
    "out": "list of issues whose title starts with 'File: <md_path>'"
} ]]
function M.fetch(md_path)
    if not md_path or md_path == "" then return {} end
    ensure_loaded()
    local prefix = "File: " .. md_path
    local matching = {}
    for _, issue in ipairs(cache) do
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
    "in":  {"md_path": "string", "anchor": "string"},
    "out": "list of issues whose title matches the page AND ends with ' (#<anchor>)'"
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
    "out": "list of all cached open issues"
} ]]
function M.fetch_all()
    ensure_loaded()
    return cache
end

-- =====================================================================
-- Mutators
-- =====================================================================

--[[ {
    "in":  {"issue": "{number, title, body, url}"},
    "note": "Appends with empty comments. No-op on duplicate number."
} ]]
function M.add_issue(issue)
    if type(issue) ~= "table" or type(issue.number) ~= "number" then return end
    ensure_loaded()
    for _, existing in ipairs(cache) do
        if existing.number == issue.number then return end
    end
    cache[#cache + 1] = {
        number   = issue.number,
        title    = issue.title or "",
        body     = issue.body or "",
        url      = issue.url or "",
        comments = fresh_comments_array(),
        labels   = fresh_labels_array(),
    }
    save_to_disk()
end

--[[ {
    "in":  {"number": "integer"},
    "note": "Drops by number; no-op if absent."
} ]]
function M.remove_issue(number)
    if type(number) ~= "number" then return end
    ensure_loaded()
    for i, issue in ipairs(cache) do
        if issue.number == number then
            table.remove(cache, i)
            save_to_disk()
            return
        end
    end
end

--[[ {
    "in":  {"number": "integer", "comment": "{author, created_at, body}"},
    "note": "Appends; no-op if the issue isn't in cache."
} ]]
function M.add_comment(number, comment)
    if type(number) ~= "number" or type(comment) ~= "table" then return end
    ensure_loaded()
    for _, issue in ipairs(cache) do
        if issue.number == number then
            issue.comments[#issue.comments + 1] = {
                author     = comment.author or "",
                created_at = comment.created_at or "",
                body       = comment.body or "",
            }
            save_to_disk()
            return
        end
    end
end

--[[ {
    "out": "bool — true if the gh fetch succeeded and the cache was replaced"
} ]]
function M.refresh_from_gh()
    local fresh = fetch_all_from_gh()
    if not fresh then return false end
    cache = fresh
    save_to_disk()
    return true
end

return M
