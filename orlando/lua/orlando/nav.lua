--[[
{
  "module": "orlando.nav",
  "role": "Walk every configured doc-tree directory (documentation/, requirements/, etc.) and produce the sidebar HTML — nested <details>/<ul>/<li> reflecting each tree, with the current page highlighted.",
  "exports": {
    "build": "current_md_path -> sidebar HTML string"
  },
  "url_convention": "URLs match Orlando's routing: /<doc-root>/foo/bar (no .md, no .html). The current-page detection compares against the current_md_path argument; if it matches, the entry is rendered as bold text rather than a link.",
  "no_caching": "build() walks the directories on every call. Cheap (a few dozen files each), and aligns with the Orlando no-caching design."
}
]]
local quick_builder = require("orlando.quick_builder")

local M = {}

-- Doc trees to walk for the sidebar. Order determines display order.
-- Sidebar-only whitelist — Orlando's routing serves the whole repo now,
-- but the sidebar stays focused on doc trees (not code/, tests/, etc.).
local DOC_ROOTS = {"archive", "documentation", "ideas", "requirements", "skills"}

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

-- Return (filtered_files, has_index) where has_index is true iff the dir
-- has an `index.md` child (which is the dir's index page) and that
-- file has been removed from the returned list.
local function pull_index_file(files, dir_name)
    local out = {}
    local has_index = false
    for _, f in ipairs(files) do
        if f == "index.md" then
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

    -- Merge files and subdirs into one alphabetically-ordered list.
    -- index.md itself never appears as a sibling entry — pull_index_file
    -- has already removed it; the directory it lives in carries its
    -- ordering instead.
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
                url   = url_prefix .. "/" .. label       -- e.g. /caspian/puck
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
                            -- Non-md assets (.html, .css, .json, .casp,
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
            local index_fs     = sub_fs .. "/index.md"
            local files, has_index = pull_index_file(subtree.files, name)
            local sub_tree     = { files = files, subdirs = subtree.subdirs }
            local is_current_index = has_index and current_md_path == index_fs
            -- The current page is this dir's own dir-listing when the
            -- caller passed `<sub_fs>/` as current_md_path (see
            -- render_dir_listing). This treats the dir entry as "current"
            -- so the same highlight CSS used for index-page entries fires.
            local is_current_dir_listing = current_md_path
                and current_md_path == sub_fs .. "/"
            local is_current = is_current_index or is_current_dir_listing
            local has_children = #files > 0 or next(subtree.subdirs) ~= nil

            -- Every directory entry is linked, regardless of whether it has
            -- an index.md, children, or is empty. A dir without index.md
            -- resolves to Orlando's directory listing; an empty dir resolves
            -- to an "(empty directory)" listing; a dir with index.md serves
            -- the index. Either way, clicking the link goes somewhere
            -- meaningful.
            local li_class = is_current and "dir current" or "dir"

            if not has_children then
                -- No children: render as a leaf with a link to the dir.
                ul:tag("li", function(li)
                    li:attr("class", li_class)
                    if is_current then
                        li:tag("span", function(s) s:text(name .. "/") end)
                    else
                        li:tag("a", function(a)
                            a:attr("href", sub_url .. "/")
                            a:text(name .. "/")
                        end)
                    end
                end)
            else
                -- Has children: wrap in <details>; the summary is always a
                -- link to the dir, whether or not the dir has its own
                -- index.md.
                ul:tag("li", function(li)
                    li:attr("class", li_class)
                    li:tag("details", function(d)
                        if expanded then d:attr("open", "") end
                        d:tag("summary", function(s)
                            -- Marker rendered as a separate span so that
                            -- clicking the arrow triggers the summary's
                            -- native toggle (an ::before on the link
                            -- would navigate instead of toggle).
                            -- text('') forces an explicit </span> close;
                            -- QuickBuilder otherwise emits <span/> which
                            -- HTML5 parses as an unclosed opening tag,
                            -- wrapping the link inside the marker.
                            s:tag("span", function(m)
                                m:attr("class", "marker")
                                m:text("")
                            end)
                            if is_current then
                                s:tag("span", function(sp) sp:text(name .. "/") end)
                            else
                                s:tag("a", function(a)
                                    a:attr("href", sub_url .. "/")
                                    a:text(name .. "/")
                                end)
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
    local root = quick_builder.new("div")  -- throwaway wrapper; we'll strip it
    root:tag("ul", function(top_ul)
        for _, doc_root in ipairs(DOC_ROOTS) do
            local tree = build_tree(doc_root)
            if #tree.files > 0 or next(tree.subdirs) ~= nil then
                local expanded = on_path(current_md_path, doc_root)
                -- Also expand if the doc_root's own index.md is the current page.
                if current_md_path == doc_root .. "/index.md" then
                    expanded = true
                end
                top_ul:tag("li", function(li)
                    li:attr("class", "dir")
                    li:tag("details", function(d)
                        if expanded then d:attr("open", "") end
                        d:tag("summary", function(s)
                            s:tag("span", function(m)
                                m:attr("class", "marker")
                                m:text("")
                            end)
                            s:tag("a", function(a)
                                a:attr("href", "/" .. doc_root .. "/")
                                a:text(doc_root .. "/")
                            end)
                        end)
                        -- Strip index.md from top-level so it doesn't appear
                        -- as a sibling entry (same rule as subdirs).
                        local top_files, _ = pull_index_file(tree.files, doc_root)
                        local top_tree = { files = top_files, subdirs = tree.subdirs }
                        render_ul(d, top_tree, doc_root, "/" .. doc_root, current_md_path)
                    end)
                end)
            end
        end
    end)
    -- Render the wrapper and strip the <div>...</div>.
    local html = root:render()
    return (html:gsub("^<div>", ""):gsub("</div>$", ""))
end

return M
