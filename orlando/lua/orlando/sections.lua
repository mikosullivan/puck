--[[
{
  "module": "orlando.sections",
  "role": "Extract markdown source for a named section of a doc, given the anchor that Orlando renders for that section. Used by the per-section 'Edit' form so the form's textarea can be pre-populated with the section's current source. A section's markdown includes its own heading line plus every line up to (but not including) the next sibling-or-higher heading.",
  "exports": {
    "extract": "(md_path) -> { whole_file = string, by_anchor = { [id] = markdown } }  scan a file and return the source for every named section",
    "section_for": "(md_path, anchor) -> string | nil  convenience: just the section for one anchor, or whole_file if anchor is nil/empty"
  },
  "anchor_resolution": [
    "explicit anchor: a line `<a id=\"foo\"></a>` immediately preceding a heading binds anchor 'foo' to that heading (matches Orlando's promote_anchors behavior)",
    "implicit anchor: slugify the heading text using the same rules as orlando.page (lowercase, non-word → dashes, trim leading/trailing dashes)",
    "disambiguation: duplicate ids get -2, -3, ... suffix — same order page.lua's ensure_heading_ids produces"
  ],
  "code_fence_handling": "lines inside ```...``` or ~~~...~~~ blocks are not treated as headings (so '# Python comment' inside a code block doesn't get picked up)"
}
]]
local M = {}

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function split_lines(text)
    local lines = {}

    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    return lines
end

local function slugify(text)
    local t = text:lower()
    t = t:gsub("[^%w]+", "-")
    t = t:gsub("^%-+", ""):gsub("%-+$", "")
    if t == "" then t = "heading" end
    return t
end

local function clean_heading_text(text)
    -- Drop any inline HTML tags (the anchor we just consumed, links, etc.)
    local t = text:gsub("<[^>]+>", "")
    -- Drop leading section numbers like "1 " or "1.2 "
    t = t:gsub("^[%d%.]+%s+", "")
    -- Trim
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    return t
end

-- "## My heading"   -> level=2, text="My heading"
-- "###   foo  "      -> level=3, text="foo"
-- not a heading      -> nil
local function parse_heading(line)
    local hashes, text = line:match("^(#+)%s+(.+)$")

    if hashes and #hashes >= 1 and #hashes <= 6 then
        return #hashes, text
    end

    return nil
end

-- "<a id=\"foo\"></a>" → "foo".  Leading/trailing whitespace tolerated.
-- nil if the line isn't a bare anchor.
local function parse_bare_anchor(line)
    return line:match('^%s*<a%s+id="([^"]+)"></a>%s*$')
end

-- Track whether we're currently inside a fenced code block. Returns true
-- if the current line is inside (or is) a fence marker; mutates state.
local function update_fence(state, line)
    local marker = line:match("^(```+)") or line:match("^(~~~+)")

    if marker then
        if state.open then
            -- Closing fence if the marker character/length matches what opened.
            if line:sub(1, #state.open) == state.open then
                state.open = nil
            end
        else
            state.open = marker
        end
        return true
    end

    return state.open ~= nil
end

-- Walk the file, collect { line_index, level, id } for every heading.
-- Handles explicit-anchor promotion and the same -2/-3 disambiguation
-- Orlando renders.
local function find_headings(lines)
    local headings = {}
    local seen = {}
    local fence = {}
    local pending_anchor = nil

    for i, line in ipairs(lines) do
        local in_fence = update_fence(fence, line)

        if not in_fence then
            local anchor = parse_bare_anchor(line)

            if anchor then
                pending_anchor = anchor
            else
                local level, text = parse_heading(line)

                if level then
                    local id

                    if pending_anchor then
                        id = pending_anchor
                    else
                        id = slugify(clean_heading_text(text))
                    end

                    if seen[id] then
                        local n = 2
                        while seen[id .. "-" .. n] do n = n + 1 end
                        id = id .. "-" .. n
                    end

                    seen[id] = true
                    headings[#headings + 1] = {
                        line_index = i,
                        level      = level,
                        id         = id,
                    }
                    pending_anchor = nil
                elseif line:match("%S") then
                    -- Any non-blank, non-anchor, non-heading line breaks the
                    -- "anchor immediately precedes heading" association.
                    pending_anchor = nil
                end
            end
        else
            pending_anchor = nil
        end
    end

    return headings
end

-- Trim trailing blank lines: inter-section whitespace belongs to the
-- file (between sections), not to the section itself. Without this, a
-- direct-save edit replaces "## Foo\n\nfoo body\n\n" with what the user
-- typed (typically just "## Foo\n\nfoo body") and eats the blank line
-- that separated this section from the next.
local function slice(lines, from, to)
    while to > from and lines[to]:match("^%s*$") do
        to = to - 1
    end

    local out = {}

    for i = from, to do
        out[#out + 1] = lines[i]
    end

    return table.concat(out, "\n")
end

--[[ {
    "in":  {"md_path": "string — path to a markdown file"},
    "out": "{ whole_file = string, by_anchor = { [id] = markdown } }  empty by_anchor if file unreadable or contains no h2-h6 headings"
} ]]
function M.extract(md_path)
    local text = read_file(md_path)

    if not text then
        return { whole_file = "", by_anchor = {} }
    end

    local lines    = split_lines(text)
    local headings = find_headings(lines)
    local by_anchor = {}

    for idx, h in ipairs(headings) do
        local end_line = #lines

        for j = idx + 1, #headings do
            if headings[j].level <= h.level then
                end_line = headings[j].line_index - 1
                break
            end
        end

        by_anchor[h.id] = slice(lines, h.line_index, end_line)
    end

    return { whole_file = text, by_anchor = by_anchor }
end

--[[ {
    "in":  {"md_path": "string", "anchor": "string? — nil/empty returns the whole file"},
    "out": "string | nil  nil if the anchor isn't found"
} ]]
function M.section_for(md_path, anchor)
    local sections = M.extract(md_path)

    if not anchor or anchor == "" then
        return sections.whole_file
    end

    return sections.by_anchor[anchor]
end

return M
