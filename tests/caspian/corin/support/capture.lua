--[[
{
  "module": "tests.corin.support.capture",
  "role":   "Capture sink helper for Corin tests. capture.new() returns a struct with .sink (a function that the engine writes to via engine.std) and .text() (returns the accumulated buffer as a single string).",
  "usage":  "local cap = capture.new(); engine.std = cap.sink; engine.run(); assert_.equal(cap.text(), 'expected\\n')"
}
]]
local M = {}

function M.new()
    local buf = {}
    return {
        sink = function(s)
            buf[#buf + 1] = s
        end,
        text = function()
            return table.concat(buf)
        end,
    }
end

return M
