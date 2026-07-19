--[[
{
  "module": "orlando.tags",
  "role": "Parse the tag index at documentation/tags.md and provide tag→URL lookup. The index is a markdown pipe table with two columns (tag, URL). Accepts two column formats to keep the source hand-editable: bare `| grants | /documentation/... |` and markdown-link `| [grants](/tag/grants) | [/documentation/...](/documentation/...) |`. Rows whose URL doesn't start with '/' are skipped (this filters out the header row and any prose). Called by orlando.route for /tag/<name> HTTP redirects and by orlando.page for tag:<name> markdown link resolution.",
  "exports": {
    "lookup": "tag_name -> url or nil"
  },
  "no_caching": "every call re-reads documentation/tags.md per the Orlando no-caching design"
}
]]
local M = {}

local TAG_FILE = "documentation/tags.md"

local function parse_tags()
    local tags = {}
    local f = io.open(TAG_FILE, "r")
    if not f then return tags end
    for line in f:lines() do
        -- Try markdown-link format first: | [tag](anything) | [/url...](anything) |
        local tag, url = line:match("^%s*|%s*%[([%w_-]+)%]%b()%s*|%s*%[(/[^%]]+)%]")
        if not tag then
            -- Fall back to bare format: | tag | /url... |
            -- URL must start with '/' so header row and prose don't parse as entries.
            tag, url = line:match("^%s*|%s*([%w_-]+)%s*|%s*(/%S+)%s*|")
        end
        if tag and url then
            tags[tag] = url
        end
    end
    f:close()
    return tags
end

function M.lookup(tag)
    return parse_tags()[tag]
end

return M
