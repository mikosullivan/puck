--[[
{
  "module": "orlando.config",
  "role": "Read Orlando's per-user config from ~/.orlando/config.json. The file lives outside the project tree so server-side preferences (e.g. which IP can submit edits direct-to-file) aren't checked into git. Re-read on every call — no in-memory caching, matching Orlando's no-caching design; the file is tiny.",
  "exports": {
    "load":      "() -> table  parsed config, or {} if the file is missing or malformed",
    "edit_allowed_ips": "() -> { [ip_string] = true }  set of IPs allowed to use direct-save edit features",
    "ip_can_edit": "(ip) -> bool  convenience: true iff ip appears in the allow-list"
  },
  "schema": {
    "edit": {
      "allowed_ips": "array of IPv4/IPv6 strings (exact match — no subnets in v1)"
    }
  },
  "missing_file_behavior": "returns empty config; ip_can_edit then returns false for every IP — fail closed"
}
]]
local cjson = require("cjson")

local M = {}

local function config_path()
    local home = os.getenv("HOME") or ""
    return home .. "/.orlando/config.json"
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

--[[ {
    "in":  {},
    "out": "table — parsed config or {} if missing/unreadable/malformed"
} ]]
function M.load()
    local raw = read_file(config_path())
    if not raw then return {} end

    local ok, parsed = pcall(cjson.decode, raw)
    if not ok or type(parsed) ~= "table" then return {} end

    return parsed
end

--[[ {
    "in":  {},
    "out": "table — { [ip] = true } set form for fast lookup"
} ]]
function M.edit_allowed_ips()
    local cfg = M.load()
    local set = {}
    local list = (cfg.edit or {}).allowed_ips

    if type(list) == "table" then
        for _, ip in ipairs(list) do
            if type(ip) == "string" and ip ~= "" then
                set[ip] = true
            end
        end
    end

    return set
end

--[[ {
    "in":  {"ip": "string?"},
    "out": "bool — true iff ip is in the edit allow-list"
} ]]
function M.ip_can_edit(ip)
    if not ip or ip == "" then return false end
    return M.edit_allowed_ips()[ip] == true
end

return M
