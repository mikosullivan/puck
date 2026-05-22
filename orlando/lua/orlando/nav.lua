--[[
{
  "module": "orlando.nav",
  "role": "Walk the documentation directory and produce the sidebar HTML — nested <details>/<ul>/<li> reflecting the directory tree, with the current page highlighted.",
  "exports": {
    "build": "current_md_path -> sidebar HTML string"
  },
  "url_convention": "URLs match Orlando's routing: /foo/bar (no .md, no .html). The current-page detection compares against the current_md_path argument; if it matches, the entry is rendered as bold text rather than a link.",
  "no_caching": "build() walks the directory on every call. Cheap (a few dozen files), and aligns with the Orlando no-caching design."
}
]]
local quick_builder = require("orlando.quick_builder")

local M = {}

local DOC_ROOT = "documentation"

-- List entries in a directory, sorted, separating files from subdirectories.
local function list_dir(path)
    local files, dirs = {}, {}
    -- Use `ls -1aF` and parse: F appends / to dirs.
    local handle = io.popen('ls -1aF "' .. path .. '" 2>/dev/null')
    if not handle then return files, dirs end
    for entry in handle:lines() do
        if entry ~= "./" and entry ~= "../" then
            if entry:sub(-1) == "/" then
                local name = entry:sub(1, -2)
                if name:sub(1,1) ~= "." then
                    dirs[#dirs + 1] = name
                end
            else
                -- Strip trailing flag char if any (* for executable, @ for symlink, etc).
                local name = entry:gsub("[%*%@%|%=]$", "")
                if name:sub(1,1) ~= "." then
                    files[#files + 1] = name
                end
            end
        end
    end
    handle:close()
    table.sort(files)
    table.sort(dirs)
    return files, dirs
end

-- Build a tree: { files = [...], subdirs = { name = subtree } }
local function build_tree(fs_path)
    local tree = { files = {}, subdirs = {} }
    local files, dirs = list_dir(fs_path)
    for _, name in ipairs(files) do
        table.insert(tree.files, name)
    end
    for _, name in ipairs(dirs) do
        tree.subdirs[name] = build_tree(fs_path .. "/" .. name)
    end
    return tree
end

-- Recursively render a tree into a QuickBuilder <ul>.
-- True if `current_md_path` lies inside the directory at `fs_dir`.
local function on_path(current_md_path, fs_dir)
    if not current_md_path then return false end
    return current_md_path:sub(1, #fs_dir + 1) == fs_dir .. "/"
end

-- Return (filtered_files, has_index) where has_index is true iff `dir_name`
-- has a `<dir_name>.md` child (which is the dir's index page) and that
-- file has been removed from the returned list.
local function pull_index_file(files, dir_name)
    local index_filename = dir_name .. ".md"
    local out = {}
    local has_index = false
    for _, f in ipairs(files) do
        if f == index_filename then
            has_index = true
        else
            out[#out + 1] = f
        end
    end
    return out, has_index
end

local function render_ul(parent, tree, fs_prefix, url_prefix, current_md_path)
    -- Don't emit an empty <ul>; <ul/> self-close is misparsed by HTML5 as
    -- an unclosed opening tag (QuickBuilder has XML semantics).
    if #tree.files == 0 and next(tree.subdirs) == nil then return end

    -- Merge files and subdirs into one alphabetically sorted list so the
    -- nav reads top-to-bottom in name order regardless of kind.
    local entries = {}
    for _, name in ipairs(tree.files) do
        entries[#entries + 1] = { name = name, kind = "file" }
    end
    for name, _ in pairs(tree.subdirs) do
        entries[#entries + 1] = { name = name, kind = "dir" }
    end
    table.sort(entries, function(a, b) return a.name < b.name end)

    parent:tag("ul", function(ul)
        for _, entry in ipairs(entries) do
        if entry.kind == "file" then
            local name = entry.name
            local fs_path  = fs_prefix .. "/" .. name
            local is_md    = name:sub(-3) == ".md"
            local label, url
            if is_md then
                label = name:sub(1, -4)                  -- strip .md
                url   = url_prefix .. "/" .. label       -- e.g. /charlie/puck
            else
                label = name                              -- keep extension
                url   = url_prefix .. "/" .. name        -- e.g. /mikobase/AI2AI/ai2ai.json
            end
            local is_current = fs_path == current_md_path
            local li_class = (is_md and "file" or "file asset")
                .. (is_current and " current" or "")
            ul:tag("li", function(li)
                li:attr("class", li_class)
                if is_current then
                    li:tag("span", function(s) s:text(label) end)
                else
                    li:tag("a", function(a)
                        a:attr("href", url)
                        if not is_md then
                            -- Non-md assets (.html, .css, .json, .charlie,
                            -- images) open in a new tab so the doc context
                            -- isn't lost.
                            a:attr("target", "_blank")
                            a:attr("rel",    "noopener")
                        end
                        a:text(label)
                    end)
                end
            end)
        else
            local name = entry.name
            local subtree = tree.subdirs[name]
            local sub_fs       = fs_prefix .. "/" .. name
            local sub_url      = url_prefix .. "/" .. name
            local expanded     = on_path(current_md_path, sub_fs)
            local index_fs     = sub_fs .. "/" .. name .. ".md"
            local files, has_index = pull_index_file(subtree.files, name)
            local sub_tree     = { files = files, subdirs = subtree.subdirs }
            local is_current_index = has_index and current_md_path == index_fs
            local has_children = #files > 0 or next(subtree.subdirs) ~= nil

            if has_index and not has_children then
                -- Dir contains only its same-named index file: render as a
                -- leaf (no <details> toggle to nothing).
                local li_class = is_current_index and "dir current" or "dir"
                ul:tag("li", function(li)
                    li:attr("class", li_class)
                    if is_current_index then
                        li:tag("span", function(s) s:text(name .. "/") end)
                    else
                        li:tag("a", function(a)
                            a:attr("href", sub_url .. "/")
                            a:text(name .. "/")
                        end)
                    end
                end)
            elseif not has_index and not has_children then
                -- Truly empty dir (no index, no children): skip entirely.
            else
                local li_class = is_current_index and "dir current" or "dir"
                ul:tag("li", function(li)
                    li:attr("class", li_class)
                    li:tag("details", function(d)
                        if expanded then d:attr("open", "") end
                        d:tag("summary", function(s)
                            if has_index then
                                if is_current_index then
                                    s:tag("span", function(sp) sp:text(name .. "/") end)
                                else
                                    s:tag("a", function(a)
                                        a:attr("href", sub_url .. "/")
                                        a:text(name .. "/")
                                    end)
                                end
                            else
                                s:text(name .. "/")
                            end
                        end)
                        render_ul(d, sub_tree, sub_fs, sub_url, current_md_path)
                    end)
                end)
            end
        end
        end
    end)
end

--[[ {
    "in":  {"current_md_path": "string? — fs path of the doc currently being rendered, e.g. 'documentation/overview.md'; pass nil for the home page"},
    "out": "string (sidebar HTML, no surrounding <nav>)"
} ]]
function M.build(current_md_path)
    local tree = build_tree(DOC_ROOT)
    local root = quick_builder.new("div")  -- throwaway wrapper; we'll strip it
    render_ul(root, tree, DOC_ROOT, "/documentation", current_md_path)
    -- Render the wrapper and strip the <div>...</div>.
    local html = root:render()
    return (html:gsub("^<div>", ""):gsub("</div>$", ""))
end

return M
