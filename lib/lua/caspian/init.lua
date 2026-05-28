--[[
{
  "module": "caspian",
  "role": "Public API — lower-level pipeline entry points (lexer, parser) and JSON sentinel. The full Caspian-source-to-CaspianJ pipeline lives on the engine module as engine.parse_caspian, not here.",
  "pipeline": [
    "Caspian source (.casp file or string)",
    "lexer  →  token[]",
    "parser →  AST",
    "transpiler → CaspianJ (Lua table)  -- via caspian.engine.parse_caspian"
  ],
  "exports": {
    "tokenize":  "string → token[]           lex only; useful for syntax highlighting and tooling",
    "parse":     "string → AST               lex + parse; AST nodes are tables with a 'kind' field",
    "dump":      "(AST, indent?) → string    debug pretty-printer for AST nodes",
    "null":      "sentinel                   JSON null value (distinct from Lua nil; use in CaspianJ output)"
  },
  "see_also": {
    "caspian.engine.parse_caspian": "full pipeline to CaspianJ (Lua table)",
    "caspian.engine.run":           "execute a tree staged on engine.caspianj"
  },
  "depends_on": ["caspian.lexer", "caspian.parser", "caspian.json"],
  "docs": ["documentation/caspian/index.md", "documentation/caspian/caspianj.md"],
  "tests": "tests/caspian/run.lua"
}
]]
local lexer  = require("caspian.lexer")
local parser = require("caspian.parser")
local json   = require("caspian.json")

local M = {}

--[[ { "what": "JSON null sentinel", "why": "Lua nil cannot round-trip through tables; use M.null when building CaspianJ that contains a null value" } ]]
M.null = json.null

--[[ { "in": {"source": "string"}, "out": "token[]  each token: {type, value, line, col}", "note": "lex only — does not parse; useful for syntax highlighting and tooling" } ]]
function M.tokenize(source)
    return lexer.tokenize(source)
end

--[[ { "in": {"source": "string"}, "out": "AST  {kind:'program', body:[node,...]}", "note": "lex + parse; every node is a table with a 'kind' field plus kind-specific fields" } ]]
function M.parse(source)
    local tokens = lexer.tokenize(source)
    return parser.parse(tokens)
end

--[[ { "in": {"node": "AST node or any table", "indent": "number? (default 0)"}, "out": "string", "note": "debug pretty-printer; works on any table, not just AST nodes" } ]]
function M.dump(node, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    if type(node) ~= "table" then
        return tostring(node)
    end
    local kind = node.kind
    if not kind then
        local parts = {}
        for k, v in pairs(node) do
            parts[#parts + 1] = string.format("%s%s = %s", pad .. "  ", k, M.dump(v, indent + 1))
        end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
    end
    local parts = { pad .. kind }
    for k, v in pairs(node) do
        if k ~= "kind" then
            if type(v) == "table" then
                parts[#parts + 1] = string.format("%s  %s:", pad, k)
                if v.kind then
                    parts[#parts + 1] = M.dump(v, indent + 2)
                else
                    for i, item in ipairs(v) do
                        parts[#parts + 1] = M.dump(item, indent + 2)
                    end
                end
            else
                parts[#parts + 1] = string.format("%s  %s: %s", pad, k, tostring(v))
            end
        end
    end
    return table.concat(parts, "\n")
end

return M
