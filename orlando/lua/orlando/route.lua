--[[
{
  "module": "orlando.route",
  "role": "Resolve an incoming URL path to either a markdown file (to be rendered), a static file (to be served verbatim), or a 301 redirect target. No caching, no I/O retries; one lookup per call.",
  "exports": {
    "resolve": "url_path -> { kind = 'home'|'markdown'|'static'|'redirect'|'not_found', path? = '...', location? = '...' }"
  },
  "rules": {
    "home":      "an empty path maps to README.md at the project root, rendered",
    "dir_index": "if documentation/<path>/<lastpart>.md exists, that file is the index for the directory; /foo/ and /foo both serve it",
    "redirect":  "/foo/foo (and /foo/foo.html) collapses to /foo/ via 301 — a markdown file whose name matches its parent directory is reachable by the directory URL only",
    "markdown":  "for '/foo/bar' or '/foo/bar.html', look for documentation/foo/bar.md; render if found",
    "static":    "for any path that didn't hit a markdown file, try the static mount table (URL-prefix -> filesystem root) in order; serve verbatim if found",
    "safety":    "any path containing '..' or backslashes is rejected as not_found"
  }
}
]]
local M = {}

local MARKDOWN_ROOT = "documentation"
local README_PATH   = "README.md"

-- URL prefix → filesystem root, tried in order. First match wins.
--   /static/        — site assets (logo, images): orlando/static/
--   /client-assets/ — browser-side code (CSS, JS): orlando/client-assets/
--   /               — everything else served from documentation/
local STATIC_MOUNTS = {
    {url_prefix = "/static/",        fs_root = "orlando/static/"},
    {url_prefix = "/client-assets/", fs_root = "orlando/client-assets/"},
    {url_prefix = "/",               fs_root = "documentation/"},
}

local function file_exists(path)
    -- On Linux, io.open() succeeds for directories too. Distinguish by
    -- attempting a one-byte read: regular files (even empty) return nil
    -- without an error message; directories return nil WITH an error
    -- ("Is a directory").
    local f = io.open(path, "rb")
    if not f then return false end
    local _, err = f:read(1)
    f:close()
    return err == nil
end

local function is_unsafe(path)
    if path:find("%.%.") then return true end
    if path:find("\\")    then return true end
    return false
end

local function strip_query(url_path)
    return (url_path:gsub("%?.*$", ""))
end

local function strip_trailing_html(p)
    return (p:gsub("%.html$", ""))
end

-- documentation/foo/bar exists as a dir AND has a bar.md inside it → that's
-- the directory's index. Returns the .md path, or nil.
local function dir_index_for(rel_no_trailing_slash)
    local last = rel_no_trailing_slash:match("([^/]+)$")
    if not last then return nil end
    local candidate = MARKDOWN_ROOT .. "/" .. rel_no_trailing_slash .. "/" .. last .. ".md"
    if file_exists(candidate) then return candidate end
    return nil
end

-- A markdown path "foo/bar/bar" where the filename equals the parent dir
-- has a canonical short form ("foo/bar/"). Returns the redirect target, or nil.
local function canonical_dir_form(rel_no_trailing_slash)
    local parent, filename = rel_no_trailing_slash:match("^(.*)/([^/]+)$")
    if not (parent and filename) then return nil end
    local parent_last = parent:match("([^/]+)$") or parent
    if parent_last == filename then
        return "/" .. parent .. "/"
    end
    return nil
end

--[[ {
    "in":  {"url_path": "string — the request-line path, e.g. '/foo/bar.html?x=1'"},
    "out": "table — { kind, path?, location? } where kind is 'home' | 'markdown' | 'static' | 'redirect' | 'not_found'"
} ]]
function M.resolve(url_path)
    url_path = strip_query(url_path or "")
    if is_unsafe(url_path) then
        return { kind = "not_found" }
    end

    -- Normalize: strip leading and trailing slashes for internal lookup.
    local rel = url_path:gsub("^/+", ""):gsub("/+$", "")

    -- Home page.
    if rel == "" or rel == "index" or rel == "index.html" then
        return { kind = "home", path = README_PATH }
    end

    -- Drop trailing .html for markdown lookups.
    local md_base = strip_trailing_html(rel)

    -- Directory-index rule: /puck/ or /puck → documentation/puck/puck.md.
    local index_path = dir_index_for(md_base)
    if index_path then
        return { kind = "markdown", path = index_path }
    end

    -- Standard markdown lookup.
    local md_path = MARKDOWN_ROOT .. "/" .. md_base .. ".md"
    if file_exists(md_path) then
        -- If this file's name matches its parent dir, the canonical URL
        -- is the directory itself — redirect.
        local redirect_to = canonical_dir_form(md_base)
        if redirect_to then
            return { kind = "redirect", location = redirect_to }
        end
        return { kind = "markdown", path = md_path }
    end

    -- Static lookup: try each mount in order. (Use the original url_path so
    -- trailing slashes don't get folded — static dirs are leaf files anyway.)
    for _, mount in ipairs(STATIC_MOUNTS) do
        if url_path:sub(1, #mount.url_prefix) == mount.url_prefix then
            local sub = url_path:sub(#mount.url_prefix + 1)
            if sub ~= "" and not is_unsafe(sub) then
                local fs_path = mount.fs_root .. sub
                if file_exists(fs_path) then
                    return { kind = "static", path = fs_path }
                end
            end
        end
    end

    return { kind = "not_found" }
end

return M
