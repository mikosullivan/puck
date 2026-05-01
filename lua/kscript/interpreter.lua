--[[
{
  "module": "kscript.interpreter",
  "role": "KScriptJSON executor — walks a KScriptJSON program table and evaluates it",
  "exports": {
    "new":  "(env?) → interpreter  create a new interpreter instance with optional env overrides",
    "exec": "(interp, program)     execute a KScriptJSON program (array of statements) in order"
  },
  "env_keys": {
    "stdout": "function(str) → nil  called by puts and any stdout write; defaults to io.write with newline"
  },
  "statement_forms": {
    "bwc_call":   "[{bwc:'name'}, '&', args_obj]  bare word command; bwc carries the name, '&' is the call sigil",
    "assignment": "['scope', 'setvar', name, expr]  set a variable in the current scope",
    "if":         "['command', 'if', cmd_obj]  conditional; cmd_obj has expressions[] and optional else[]",
    "method":     "[recv_expr, 'method', args_obj?]  method call or binary operator on a value"
  },
  "scope_model": "flat table keyed by variable name; instance vars stored as '@name'; no lexical chaining yet",
  "bwc_registry": "self.bwcs table maps bwc name → function(interp, positional_args[])",
  "format_note": "handles the transpiler's actual output format, which predates kscriptjson.md; the two will be reconciled in a later pass",
  "implements": ["puts", "variable assignment", "if/elsif/else", "binary operators +,-,*,/,==,!=,<,<=,>,>="],
  "not_yet_implemented": ["method calls on objects", "function/closure definitions", "while loops",
    "catch/raise", "pipes", "string interpolation", "class definitions", "modules"]
}
]]
local M = {}
local interp_mt = {__index = M}

--[[
{
  "what": "per-type method tables",
  "role": "each KScript primitive type has its own method table; dispatch in exec_stmt looks up the receiver's Lua type here",
  "types": {
    "String":  "string operations; + is concatenation, not addition",
    "Number":  "arithmetic and comparison",
    "Boolean": "equality only"
  },
  "extension": "user-defined KScript classes will register their method tables through a separate class registry (not yet implemented)"
}
]]
local String_methods = {
    --[[ { "method": "+", "note": "concatenation; right operand coerced to string via tostring" } ]]
    ["+"]  = function(a, b) return a .. tostring(b) end,
    ["=="] = function(a, b) return a == b end,
    ["!="] = function(a, b) return a ~= b end,
    ["<"]  = function(a, b) return a <  b end,
    ["<="] = function(a, b) return a <= b end,
    [">"]  = function(a, b) return a >  b end,
    [">="] = function(a, b) return a >= b end,
}

local Number_methods = {
    ["+"]  = function(a, b) return a + b  end,
    ["-"]  = function(a, b) return a - b  end,
    ["*"]  = function(a, b) return a * b  end,
    ["/"]  = function(a, b) return a / b  end,
    ["=="] = function(a, b) return a == b end,
    ["!="] = function(a, b) return a ~= b end,
    ["<"]  = function(a, b) return a <  b end,
    ["<="] = function(a, b) return a <= b end,
    [">"]  = function(a, b) return a >  b end,
    [">="] = function(a, b) return a >= b end,
}

local Boolean_methods = {
    ["=="] = function(a, b) return a == b end,
    ["!="] = function(a, b) return a ~= b end,
}

--[[ maps Lua type() strings to their KScript method table ]]
local type_methods = {
    string  = String_methods,
    number  = Number_methods,
    boolean = Boolean_methods,
}

--[[
{
  "in": "env?: table of host overrides",
  "out": "interpreter instance",
  "env_fields": {
    "stdout": "function(str) — override default print behaviour; useful for capturing output in tests or embedding"
  },
  "initialises": ["self.scope (empty)", "self.stdout (env.stdout or io.write+newline)", "self.bwcs (built-in bwc registry)"],
  "bwcs_registered": ["puts"]
}
]]
function M.new(env)
    env = env or {}
    local self = setmetatable({}, interp_mt)
    self.scope  = {}
    self.stdout = env.stdout or function(s) io.write(tostring(s) .. "\n") end
    self.bwcs   = {
        --[[ { "bwc": "puts", "in": "args[1]: any value or nil", "out": "nil", "note": "converts arg to string; empty string if no arg; writes via interp.stdout" } ]]
        puts = function(interp, args)
            local s = (args and args[1] ~= nil) and tostring(args[1]) or ""
            interp.stdout(s)
        end,
    }
    return self
end

--[[
{
  "in": "args_obj: table with optional .args array and .kwargs hash, or nil",
  "out": "positional args array (may be empty)",
  "note": "helper used before bwcs and operators were fully split; kept for future positional-arg extraction"
}
]]
local function pos_args(args_obj)
    if not args_obj or not args_obj.args then return {} end
    return args_obj.args
end

--[[
{
  "in": "expr: any KScriptJSON expression node (table) or raw Lua scalar",
  "out": "evaluated Lua value",
  "dispatch": {
    "non-table":        "returned as-is (already a Lua scalar)",
    "{value:v}":        "literal — return v directly",
    "{var:'name'}":     "variable lookup in self.scope; error if undefined",
    "{ivar:'name'}":    "instance variable — stored as '@name' in self.scope",
    "{bwc:'name'}":     "returned as-is — resolved at call time by exec_stmt",
    "{sys:'name'}":     "returned as-is — system method reference; runtime TBD",
    "{array:[...]}":    "each element recursively evaluated; returns Lua array table",
    "{hash:{...}}":     "each value recursively evaluated; keys preserved; returns Lua hash table",
    "array stmt [...]": "nested statement used as expression — delegated to exec_stmt"
  }
}
]]
function M:eval(expr)
    if type(expr) ~= "table" then return expr end

    if expr.value ~= nil then return expr.value end

    if expr["var"] then
        local v = self.scope[expr["var"]]
        if v == nil then error("undefined variable: $" .. expr["var"]) end
        return v
    end

    if expr.ivar then
        return self.scope["@" .. expr.ivar]
    end

    --[[ bwc and sys refs are returned as tagged tables; exec_stmt resolves them at call time ]]
    if expr.bwc then return {bwc = expr.bwc} end
    if expr.sys then return {sys = expr.sys} end

    if expr.array then
        local result = {}
        for i, elem in ipairs(expr.array) do result[i] = self:eval(elem) end
        return result
    end

    if expr.hash then
        --[[ hash is an ordered-hash table (metatable carries _keys); iterate string keys only ]]
        local result = {}
        for k, v in pairs(expr.hash) do
            if type(k) == "string" then result[k] = self:eval(v) end
        end
        return result
    end

    --[[ array with numeric keys → nested statement used as an expression ]]
    if expr[1] then return self:exec_stmt(expr) end

    error("eval: unrecognised expression form")
end

--[[
{
  "in": "stmt: one KScriptJSON statement — either an array or a no-op object",
  "out": "result value or nil",
  "dispatch_order": [
    "1. no-op objects: comment / vibecode / document → nil",
    "2. ['scope','setvar', name, expr] → variable assignment",
    "3. ['command','if', cmd_obj]      → conditional branch",
    "4. [{bwc}, '&', args_obj]         → bare word command call",
    "5. [recv, operator, args_obj]     → binary operator on evaluated recv"
  ],
  "note": "raises error for unknown forms or unimplemented method calls"
}
]]
function M:exec_stmt(stmt)
    if type(stmt) ~= "table" then return nil end

    --[[ no-op documentation statements — silently ignored ]]
    if stmt.comment or stmt.vibecode or stmt.document then return nil end

    local s1 = stmt[1]
    local s2 = stmt[2]
    local s3 = stmt[3]

    if s1 == nil then return nil end

    --[[ variable assignment: ["scope", "setvar", name, expr] ]]
    if s1 == "scope" and s2 == "setvar" then
        local val = self:eval(stmt[4])
        self.scope[s3] = val
        return val
    end

    --[[ conditional: ["command", "if", cmd_obj] ]]
    if s1 == "command" and s2 == "if" then
        return self:exec_if(s3)
    end

    --[[ bwc call: [{bwc:'name'}, '&', args_obj] ]]
    if type(s1) == "table" and s1.bwc then
        local handler = self.bwcs[s1.bwc]
        if not handler then error("unknown bwc: " .. s1.bwc) end
        --[[ s2 is '&' (call sigil) when args are present; s3 is args_obj ]]
        local args_obj = (s2 == "&") and s3 or s2
        local pargs = {}
        if type(args_obj) == "table" and args_obj.args then
            for i, a in ipairs(args_obj.args) do pargs[i] = self:eval(a) end
        elseif type(args_obj) == "table" and args_obj.value ~= nil then
            --[[ single bare value passed directly rather than wrapped in args ]]
            pargs[1] = self:eval(args_obj)
        end
        return handler(self, pargs)
    end

    --[[ method call or operator: [recv_expr, 'method', args_obj?] ]]
    if type(s2) == "string" then
        local recv = self:eval(s1)
        --[[ look up the method in the receiver's type table; raises a clear error if not found ]]
        local tbl = type_methods[type(recv)]
        local method = tbl and tbl[s2]
        if method then
            local right = s3 and s3.args and self:eval(s3.args[1])
            return method(recv, right)
        end
        error("undefined method '" .. tostring(s2) .. "' for " .. type(recv))
    end

    error("exec_stmt: unrecognised statement form")
end

--[[
{
  "in": "cmd: if-command object from the transpiler",
  "out": "nil",
  "cmd_fields": {
    "expressions": "array of {when: cond_expr, then: [stmts]} branches — evaluated top to bottom",
    "else":        "optional array of statements run if no branch matched"
  },
  "note": "also accepts 'branches' as an alias for 'expressions' to support both transpiler and kscriptjson.md formats"
}
]]
function M:exec_if(cmd)
    for _, branch in ipairs(cmd.expressions or cmd.branches or {}) do
        local cond = self:eval(branch.when)
        if cond and cond ~= false then
            for _, stmt in ipairs(branch["then"] or {}) do
                self:exec_stmt(stmt)
            end
            return
        end
    end
    if cmd["else"] then
        for _, stmt in ipairs(cmd["else"]) do
            self:exec_stmt(stmt)
        end
    end
end

--[[
{
  "in": "program: KScriptJSON array of statements (the top-level program node)",
  "out": "nil",
  "note": "executes each statement in order; stops on the first error; return values of statements are discarded at the top level"
}
]]
function M:exec(program)
    for _, stmt in ipairs(program) do
        self:exec_stmt(stmt)
    end
end

return M
