--[[
{
  "module": "orlando.content_type",
  "role": "Map a filename extension to its HTTP Content-Type header value. Tiny lookup table — extend as new formats are needed.",
  "exports": {
    "for_ext":  "extension string (case-insensitive, no leading dot) -> content-type string",
    "for_file": "filename or path -> content-type string (extracts extension)",
    "DEFAULT":  "application/octet-stream — returned for unknown / missing extensions"
  }
}
]]
local M = {}

M.DEFAULT = "application/octet-stream"

local BY_EXT = {
    -- Rendered output
    html     = "text/html; charset=utf-8",
    css      = "text/css; charset=utf-8",
    js       = "text/javascript; charset=utf-8",

    -- Markdown source
    md       = "text/markdown; charset=utf-8",
    markdown = "text/markdown; charset=utf-8",

    -- Structured data
    json     = "application/json",

    -- Images
    svg      = "image/svg+xml",
    png      = "image/png",
    jpg      = "image/jpeg",
    jpeg     = "image/jpeg",
    gif      = "image/gif",
    webp     = "image/webp",
    ico      = "image/x-icon",

    -- Plain text (code, config, scripts) — all served as text/plain
    txt      = "text/plain; charset=utf-8",
    sh       = "text/plain; charset=utf-8",
    lua      = "text/plain; charset=utf-8",
    caspian  = "text/plain; charset=utf-8",
    sql      = "text/plain; charset=utf-8",
    toml     = "text/plain; charset=utf-8",
    conf     = "text/plain; charset=utf-8",
}

--[[ { "in": {"ext": "string?"}, "out": "content-type string", "note": "case-insensitive lookup; nil/unknown returns DEFAULT" } ]]
function M.for_ext(ext)
    if not ext then return M.DEFAULT end
    return BY_EXT[ext:lower()] or M.DEFAULT
end

--[[ { "in": {"filename": "string?"}, "out": "content-type string", "note": "extracts the part after the last dot; no extension returns DEFAULT" } ]]
function M.for_file(filename)
    if not filename then return M.DEFAULT end
    local ext = filename:match("%.([^%./]+)$")
    return M.for_ext(ext)
end

return M
