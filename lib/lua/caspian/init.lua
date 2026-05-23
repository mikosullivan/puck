--[[
{
  "module": "caspian",
  "role": "Public API — single entry point for the Caspian toolchain",
  "pipeline": [
    "Caspian source (.casp file or string)",
    "lexer  →  token[]",
    "parser →  AST",
    "transpiler → CaspianJ (Lua table)",
    "json.encode → JSON string"
  ],
  "exports": {
    "tokenize":  "string → token[]           lex only; useful for syntax highlighting and tooling",
    "parse":     "string → AST               lex + parse; AST nodes are tables with a 'kind' field",
    "transpile": "string → table             full pipeline to CaspianJ as a Lua table (array of statements)",
    "to_json":   "(string, pretty?) → string full pipeline to JSON string; pretty=true for indented output",
    "dump":      "(AST, indent?) → string    debug pretty-printer for AST nodes",
    "null":      "sentinel                   JSON null value (distinct from Lua nil; use in CaspianJ output)"
  },
  "depends_on": ["caspian.lexer", "caspian.parser", "caspian.transpiler", "caspian.json"],
  "docs": ["documentation/caspian/caspian.md", "documentation/caspian/caspianj.md"],
  "tests": "tests/caspian/run.lua"
}
]]
local lexer       = require("caspian.lexer")
local parser      = require("caspian.parser")
local transpiler  = require("caspian.transpiler")
local json        = require("caspian.json")
local interpreter = require("caspian.interpreter")

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

--[[ { "in": {"source": "string"}, "out": "CaspianJ table  [stmt,...]", "note": "full pipeline; statements are arrays for calls, tagged objects for expressions" } ]]
function M.transpile(source)
    local ast = M.parse(source)
    return transpiler.transpile(ast)
end

--[[ { "in": {"source": "string", "pretty": "bool?"}, "out": "string  (JSON)", "note": "pretty=true for indented output; omit or false for compact" } ]]
function M.to_json(source, pretty)
    local caspj = M.transpile(source)
    return json.encode(caspj, pretty)
end

--[[ { "in": {"source": "string", "env": "table? (stdout override etc.)"}, "out": "nil", "note": "full pipeline: transpile then execute; env.stdout overrides the default print function" } ]]
function M.run(source, env)
    local caspj = M.transpile(source)
    local interp = interpreter.new(env)
    interp:exec(caspj)
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
