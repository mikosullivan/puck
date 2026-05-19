--[[
{
  "module": "orlando",
  "role": "Public entry point for the Orlando HTTP server",
  "exports": {
    "serve": "see orlando.server.serve"
  },
  "stage": "1 (server skeleton)"
}
]]
local server = require("orlando.server")

local M = {}

M.serve = server.serve

return M
