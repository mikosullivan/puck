--[[
{
  "module": "orlando.route",
  "role": "Resolve an incoming URL path to either a markdown file (to be rendered), a directory listing (for dirs without an index.md), a static file (to be served verbatim), or a 301 redirect target. No caching, no I/O retries; one lookup per call.",
  "exports": {
    "resolve": "url_path -> { kind = 'markdown'|'dir_listing'|'static'|'redirect'|'not_found', path? = '...', location? = '...' }"
  },
  "rules": {
    "site_root":     "GET / serves orlando/static/index.html — a hand-editable landing page outside the docs tree",
    "doc_root":      "GET /documentation/ serves README.md (rendered with full site chrome)",
    "doc_prefix":    "all markdown lives under /documentation/...; URL /documentation/foo/bar maps to documentation/foo/bar.md",
    "dir_index":     "if documentation/<path>/index.md exists, /documentation/<path>/ serves that file as the dir index",
    "dir_listing":   "if /documentation/<path>/ has no index.md, returns kind='dir_listing' with the FS path so the page module can render a listing",
    "redirect_dir":  "/documentation/foo (no slash, when foo is a directory) 301s to /documentation/foo/ — directories are always served with a trailing slash",
    "tag_redirect":  "/tag/<name> looks up <name> in documentation/tags.md and 302 redirects to the target URL; unknown tag returns not_found",
    "static_mounts": "/static/, /client-assets/, and /documentation/ are mount roots; first match wins",
    "safety":        "any path containing '..' or backslashes is rejected as not_found"
  }
}
]]
local M = {}

local MARKDOWN_ROOT    = "documentation"
local DOC_URL_PREFIX   = "/documentation"
local DOC_URL_PREFIX_S = "/documentation/"
local README_PATH      = "README.md"
local INDEX_HTML_PATH  = "orlando/static/index.html"

-- URL prefix → filesystem root, tried in order. First match wins.
--   /static/         — site assets (logo, images): orlando/static/
--   /client-assets/  — browser-side code (CSS, JS): orlando/client-assets/
--   /documentation/  — markdown sources AND any static files in the doc tree
local STATIC_MOUNTS = {
    {url_prefix = "/static/",         fs_root = "orlando/static/"},
    {url_prefix = "/client-assets/",  fs_root = "orlando/client-assets/"},
    {url_prefix = "/documentation/",  fs_root = "documentation/"},
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
    return false
end

local function strip_query(url_path)
    return (url_path:gsub("%?.*$", ""))
end

local function strip_trailing_html(p)
    return (p:gsub("%.html$", ""))
end

-- documentation/foo/bar exists as a dir AND has an index.md inside it → that's
-- the directory's index. Returns the .md path, or nil. Argument is
-- relative to documentation/ (no leading or trailing slash).
local function dir_index_for(rel)
    local candidate = MARKDOWN_ROOT .. "/" .. rel .. "/index.md"
    if file_exists(candidate) then return candidate end
    return nil
end

--[[ {
    "in":  {"url_path": "string — the request-line path, e.g. '/documentation/foo/bar.html?x=1'"},
    "out": "table — { kind, path?, location? } where kind is 'markdown' | 'static' | 'redirect' | 'not_found'"
} ]]
function M.resolve(url_path)
    url_path = strip_query(url_path or "")
    if is_unsafe(url_path) then
        return { kind = "not_found" }
    end

    local had_trailing_slash = url_path:match("/$") ~= nil
    -- Normalize: strip leading and trailing slashes for internal lookup.
    local rel = url_path:gsub("^/+", ""):gsub("/+$", "")

    -- Site root → hand-edited landing page (NOT a markdown render).
    if rel == "" or rel == "index" or rel == "index.html" then
        return { kind = "static", path = INDEX_HTML_PATH }
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

    -- /documentation (bare, no slash) → canonical is with slash.
    if rel == "documentation" then
        if not had_trailing_slash then
            return { kind = "redirect", location = DOC_URL_PREFIX_S }
        end
        return { kind = "markdown", path = README_PATH }
    end

    -- /documentation/... — markdown lookups under the prefix.
    if rel:sub(1, #"documentation/") == "documentation/" then
        local doc_rel = rel:sub(#"documentation/" + 1)

        -- If the literal URL points at a real non-markdown file in the docs
        -- tree (.html, .css, .js, .png, etc.), serve it as static. Without
        -- this, strip_trailing_html below would rewrite foo.html → foo and
        -- silently serve foo.md if it exists, hiding the actual foo.html.
        -- .md files keep their existing behavior (rendered by markdown
        -- branch when extensionless; raw via static-mount fallback when
        -- the URL ends in .md).
        if doc_rel ~= "" and not is_unsafe(doc_rel) and not doc_rel:match("%.md$") then
            local literal_path = MARKDOWN_ROOT .. "/" .. doc_rel
            if file_exists(literal_path) then
                return { kind = "static", path = literal_path }
            end
        end

        local md_base = strip_trailing_html(doc_rel)

        -- Dir-index rule (index.md): trailing-slash form is canonical, no-slash 301s.
        local index_path = dir_index_for(md_base)
        if index_path then
            if not had_trailing_slash then
                return { kind = "redirect", location = DOC_URL_PREFIX_S .. md_base .. "/" }
            end
            return { kind = "markdown", path = index_path }
        end

        -- Directory exists but has no index.md → directory listing.
        -- Same canonical-trailing-slash rule applies.
        local dir_path = MARKDOWN_ROOT .. "/" .. md_base
        if md_base ~= "" and dir_exists(dir_path) then
            if not had_trailing_slash then
                return { kind = "redirect", location = DOC_URL_PREFIX_S .. md_base .. "/" }
            end
            return { kind = "dir_listing", path = dir_path }
        end

        -- Standard markdown lookup.
        local md_path = MARKDOWN_ROOT .. "/" .. md_base .. ".md"
        if file_exists(md_path) then
            -- /foo/index → /foo/ (canonical dir-index form). Otherwise
            -- direct hits on index.md would serve the page without
            -- redirecting to the canonical trailing-slash URL.
            local parent = md_base:match("^(.+)/index$")
            if parent then
                return { kind = "redirect", location = DOC_URL_PREFIX_S .. parent .. "/" }
            end
            return { kind = "markdown", path = md_path }
        end
    end

    -- Static mounts. Use the original url_path so trailing slashes survive
    -- — static dirs are leaf files anyway.
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
