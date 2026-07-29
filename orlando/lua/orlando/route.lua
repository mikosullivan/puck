--[[
{
  "module": "orlando.route",
  "role": "Resolve an incoming URL path to either a markdown file (to be rendered), a directory listing (for dirs without an index.md), a static file (to be served verbatim), or a 301 redirect target. The entire repo is the doc root — any URL path /foo/bar maps to <repo-root>/foo/bar (with .md rendering, dir-index / dir-listing conventions, and static fallback). No caching, no I/O retries; one lookup per call.",
  "exports": {
    "resolve": "url_path -> { kind = 'markdown'|'dir_listing'|'static'|'redirect'|'not_found', path? = '...', location? = '...' }"
  },
  "rules": {
    "site_root":     "GET / serves orlando/static/index.html — a hand-editable landing page",
    "repo_root":     "The URL space maps directly to the repo filesystem. /foo/bar/baz tries <repo>/foo/bar/baz.md (markdown), then <repo>/foo/bar/baz/index.md (dir-index), then <repo>/foo/bar/baz/ (dir-listing), then <repo>/foo/bar/baz (static file with any extension).",
    "dir_index":     "if <path>/index.md exists, /<path>/ serves that file as the dir index",
    "dir_listing":   "if /<path>/ has no index.md, returns kind='dir_listing' with the FS path so the page module can render a listing",
    "redirect_dir":  "/<path> (no slash, when <path> is a directory) 301s to /<path>/ — directories are always served with a trailing slash",
    "tag_redirect":  "/tag/<name> looks up <name> in the tag index and 302 redirects to the target URL; unknown tag returns not_found",
    "static_mounts": "/static/ and /client-assets/ serve orlando's own assets; everything else is served from the repo root directly",
    "safety":        "reject paths containing '..' or backslashes; reject any path where a segment starts with '.' (blocks .git/, .env, etc.); reject known-sensitive files (settings.json)"
  }
}
]]
local M = {}


-- Orlando's own asset mounts. These override the repo-root serving because
-- they need a URL prefix distinct from the repo layout (orlando/static/logo.png
-- lives on disk at that path but is served at /static/logo.png).
local STATIC_MOUNTS = {
    {url_prefix = "/static/",         fs_root = "orlando/static/"},
    {url_prefix = "/client-assets/",  fs_root = "orlando/client-assets/"},
}

-- Top-level names blocked from being served, even though they exist in the
-- repo. Anything starting with '.' is blocked separately.
local BLOCKED_TOP_LEVEL = {
    ["settings.json"] = true,
}

local function file_exists(path)
    -- On Linux, io.open() succeeds for directories too. Distinguish by
    -- attempting a one-byte read: regular files (even empty) return nil
    -- without an error message; directories return nil WITH an error.
    local f = io.open(path, "rb")
    if not f then return false end
    local _, err = f:read(1)
    f:close()
    return err == nil
end

local function dir_exists(path)
    -- A directory on Linux: io.open succeeds but the one-byte read errors.
    local f = io.open(path, "rb")
    if not f then return false end
    local _, err = f:read(1)
    f:close()
    return err ~= nil
end

local function is_unsafe(path)
    if path:find("%.%.") then return true end
    if path:find("\\")    then return true end
    -- Block any segment starting with '.' — hides .git, .env, .cache, etc.
    for segment in path:gmatch("[^/]+") do
        if segment:sub(1,1) == "." then return true end
    end
    -- Block known-sensitive top-level files.
    local top = path:match("^([^/]+)")
    if top and BLOCKED_TOP_LEVEL[top] then return true end
    return false
end

local function strip_query(url_path)
    return (url_path:gsub("%?.*$", ""))
end

local function strip_trailing_html(p)
    return (p:gsub("%.html$", ""))
end

--[[ {
    "in":  {"url_path": "string — the request-line path, e.g. '/documentation/foo/bar.html?x=1'"},
    "out": "table — { kind, path?, location? } where kind is 'markdown' | 'static' | 'redirect' | 'not_found'"
} ]]
function M.resolve(url_path)
    url_path = strip_query(url_path or "")

    local had_trailing_slash = url_path:match("/$") ~= nil
    -- Normalize: strip leading and trailing slashes for internal lookup.
    local rel = url_path:gsub("^/+", ""):gsub("/+$", "")

    -- Site root → repo README.md, rendered with normal doc chrome (sidebar,
    -- tags, edit form, etc.). Homepage is just another doc page.
    if rel == "" or rel == "index" or rel == "index.html" then
        return { kind = "markdown", path = "README.md" }
    end

    -- Browsers request /favicon.ico from the URL root by convention.
    -- Serve it from orlando/static/ without the /static/ prefix.
    if rel == "favicon.ico" then
        return { kind = "static", path = "orlando/static/favicon.ico" }
    end

    -- /tag/<name> → look up in the tag index and 302 to the target URL.
    -- Missing tag returns not_found (clear 404 for unresolvable tags).
    local tag_name = rel:match("^tag/(.+)$")
    if tag_name then
        local target = require("orlando.tags").lookup(tag_name)
        if target then
            return { kind = "redirect", location = target }
        end
        return { kind = "not_found" }
    end

    -- Orlando's own asset mounts (checked before the repo-root serve so
    -- /static/foo hits orlando/static/foo and not <repo>/static/foo).
    for _, mount in ipairs(STATIC_MOUNTS) do
        if url_path:sub(1, #mount.url_prefix) == mount.url_prefix then
            local sub = url_path:sub(#mount.url_prefix + 1)
            if sub ~= "" and not is_unsafe(sub) then
                local fs_path = mount.fs_root .. sub
                if file_exists(fs_path) then
                    return { kind = "static", path = fs_path }
                end
            end
            return { kind = "not_found" }
        end
    end

    -- Safety: block hidden dirs (.git/, .cache/, etc.) and known-sensitive
    -- top-level files (settings.json). Also blocks '..' and backslashes.
    if is_unsafe(rel) then
        return { kind = "not_found" }
    end

    -- Repo-root serving. `rel` is the URL path with slashes trimmed and IS
    -- the filesystem path from the repo root.

    -- If the literal URL points at a real non-markdown file, serve as static
    -- BEFORE the .html strip and markdown lookups. Without this, foo.html →
    -- foo would rewrite to foo.md and silently serve foo.md if it exists.
    -- .md files keep their existing behavior (rendered by markdown branch
    -- when extensionless; raw via the static fallback below when the URL
    -- ends in .md).
    if not rel:match("%.md$") then
        if file_exists(rel) then
            -- Extra guard: don't serve a directory as static.
            if not dir_exists(rel) then
                return { kind = "static", path = rel }
            end
        end
    end

    local md_base = strip_trailing_html(rel)

    -- Dir-index rule (index.md): trailing-slash form is canonical.
    local index_path = md_base .. "/index.md"
    if file_exists(index_path) then
        if not had_trailing_slash then
            return { kind = "redirect", location = "/" .. md_base .. "/" }
        end
        return { kind = "markdown", path = index_path }
    end

    -- Directory exists but has no index.md → directory listing.
    if dir_exists(md_base) then
        if not had_trailing_slash then
            return { kind = "redirect", location = "/" .. md_base .. "/" }
        end
        return { kind = "dir_listing", path = md_base }
    end

    -- Standard markdown lookup.
    local md_path = md_base .. ".md"
    if file_exists(md_path) then
        -- /foo/index → /foo/ (canonical dir-index form).
        local parent = md_base:match("^(.+)/index$")
        if parent then
            return { kind = "redirect", location = "/" .. parent .. "/" }
        end
        return { kind = "markdown", path = md_path }
    end

    -- Static fallback for .md URLs (raw markdown source) and any other
    -- files not caught above.
    if file_exists(rel) and not dir_exists(rel) then
        return { kind = "static", path = rel }
    end

    return { kind = "not_found" }
end

return M
