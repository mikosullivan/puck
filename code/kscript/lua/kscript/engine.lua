--[[
{
  "module": "kscript.engine",
  "role": "V0.01 canonical-KSJ executor — consumes the [receiver, method, args?] statement shape from kscriptjson.md",
  "scope": "V0.01 hello-world only: string literal materialization, single method dispatch, role transition, last-statement value capture",
  "exports": {
    "bootstrap":     "() → nil  populate engine.roles, engine.classes, engine.ctx",
    "materialize":   "(expr) → value  turn a KSJ expression into a tagged value table",
    "lookup_method": "(value, name) → method_fn  resolve a method via the value's class",
    "transition":    "(new_role, fn) → result  save/restore ctx around fn(); wipes chain at boundary",
    "dispatch":      "(statement) → value  execute one [receiver, method, args?] statement",
    "run":           "(path) → value  read a .ksj file, parse, execute, return last statement's value"
  },
  "state": {
    "roles":   "{ user, stdlib }  populated by bootstrap; role objects are {name=string} only; stdlib owns all built-in classes",
    "classes": "{ string }  populated by bootstrap; class objects are {name, owning_role, methods}; all are owned by the stdlib role",
    "ctx":     "{ current_role, chain }  mutable execution context; restored across transitions"
  },
  "value_shape": "{ type=string, owning_role=role_object, payload=any_lua_value }",
  "relationship_to_existing_interpreter": "engine.lua handles canonical KSJ for V0.01; interpreter.lua handles the pre-canonical shape emitted by the existing transpiler. They coexist; no shared state.",
  "depends_on": ["kscript.json"],
  "docs": ["documentation/development/development.md (Rand sketch)", "documentation/kscript/kscriptjson.md", "documentation/kscript/roles.md"]
}
]]
local json = require("kscript.json")

local M = {}

--[[
{
  "in":  "(none)",
  "out": "nil",
  "side_effect": "populates M.roles, M.classes, M.ctx",
  "notes": [
    "idempotent — calling twice replaces the state with a fresh copy",
    "string class methods.to_string is identity (returns its receiver unchanged)",
    "ctx.chain is a fresh empty table; the wipe-at-boundary contract relies on transition replacing it (not clearing in place)"
  ]
}
]]
function M.bootstrap()
    M.roles = {
        user   = { name = "user" },
        stdlib = { name = "stdlib" },
    }
    M.classes = {
        string = {
            name        = "string",
            owning_role = M.roles.stdlib,
            methods = {
                to_string = function(receiver, args) return receiver end,
            },
        },
    }
    M.ctx = {
        current_role = M.roles.user,
        chain        = {},
    }
end

--[[
{
  "in":  "expr: a KSJ expression",
  "out": "value table {type, owning_role, payload}",
  "owning_role": "always M.ctx.current_role at the moment of materialization",
  "supported_forms": {
    "literal_string": "{value: <string>}",
    "sys_role":       "{sys: 'role'} — returns the current role wrapped as a value"
  },
  "errors": "raises on unsupported expression forms; sys references other than 'role' are deferred"
}
]]
function M.materialize(expr)
    if type(expr) ~= "table" then
        error("engine.materialize: expected a table, got " .. type(expr))
    end
    if expr.value ~= nil then
        local lua_type = type(expr.value)
        local ksj_type
        if lua_type == "string" then
            ksj_type = "string"
        else
            error("engine.materialize: V0.01 only supports string literals; got " .. lua_type)
        end
        return {
            type        = ksj_type,
            owning_role = M.ctx.current_role,
            payload     = expr.value,
        }
    end
    if expr.sys ~= nil then
        --[[ V0.01 ships only %role; other sys methods land with the slices that need them ]]
        if expr.sys == "role" then
            return {
                type        = "role",
                owning_role = M.ctx.current_role,
                payload     = M.ctx.current_role,
            }
        end
        error("engine.materialize: unsupported sys reference in V0.01: " .. tostring(expr.sys))
    end
    error("engine.materialize: unsupported expression form in V0.01")
end

--[[
{
  "in":  "(value, method_name)",
  "out": "method_fn",
  "lookup": "value.type → M.classes[type] → class.methods[name]",
  "errors": "raises if the class or the method is missing"
}
]]
function M.lookup_method(value, method_name)
    local class = M.classes[value.type]
    if not class then
        error("engine.lookup_method: no class registered for type " .. tostring(value.type))
    end
    local method_fn = class.methods[method_name]
    if not method_fn then
        error("engine.lookup_method: method '" .. tostring(method_name)
            .. "' not found on class " .. class.name)
    end
    return method_fn
end

--[[
{
  "in":  "(new_role, fn)",
  "out": "fn's return value",
  "behavior": [
    "saves M.ctx.current_role and M.ctx.chain into Lua locals",
    "sets current_role = new_role; replaces chain with a fresh empty table (wipe at boundary)",
    "calls fn()",
    "restores both fields"
  ],
  "nesting": "uses Lua's call stack via the local closure; no separate transition stack",
  "no_op_case": "if new_role equals the current role, save/restore still happens (chain is still wiped); callers can short-circuit upstream if they want to skip the no-op",
  "errors": "if fn raises, ctx is NOT restored (V0.01 has no exception machinery yet); document and revisit when alarms land"
}
]]
function M.transition(new_role, fn)
    local saved_role  = M.ctx.current_role
    local saved_chain = M.ctx.chain
    M.ctx.current_role = new_role
    M.ctx.chain        = {}
    local result = fn()
    M.ctx.current_role = saved_role
    M.ctx.chain        = saved_chain
    return result
end

--[[
{
  "in":  "statement: a [receiver, method, args?] array",
  "out": "the method's return value",
  "steps": [
    "1. materialize statement[1] → receiver value",
    "2. lookup_method(receiver, statement[2]) → method_fn",
    "3. determine target_role from the receiver's class",
    "4. if target_role differs from current, run inside transition(target_role, ...)",
    "5. otherwise call method_fn(receiver, args) directly"
  ],
  "args": "statement[3] may be nil; passed through to the method unchanged"
}
]]
function M.dispatch(statement)
    if type(statement) ~= "table" then
        error("engine.dispatch: expected a statement table")
    end
    local receiver    = M.materialize(statement[1])
    local method_name = statement[2]
    local args        = statement[3]
    local method_fn   = M.lookup_method(receiver, method_name)
    local class       = M.classes[receiver.type]
    local target_role = class.owning_role
    if target_role ~= M.ctx.current_role then
        return M.transition(target_role, function()
            return method_fn(receiver, args)
        end)
    end
    return method_fn(receiver, args)
end

--[[
{
  "in":  "path: filesystem path to a .ksj file",
  "out": "the value of the last top-level statement, or nil if the program is empty",
  "steps": [
    "1. bootstrap (fresh role/class/ctx state)",
    "2. read the file as a string",
    "3. json.parse → top-level array of statements",
    "4. iterate, dispatch each, capture the last return value"
  ],
  "host_contract": "returns a Lua value (the captured last value); errors propagate as Lua errors"
}
]]
function M.run(path)
    M.bootstrap()
    local f, err = io.open(path, "r")
    if not f then
        error("engine.run: cannot open " .. tostring(path) .. ": " .. tostring(err))
    end
    local source = f:read("*a")
    f:close()
    local tree = json.parse(source)
    if type(tree) ~= "table" then
        error("engine.run: top-level KSJ must be an array of statements")
    end
    local last_value = nil
    for _, statement in ipairs(tree) do
        last_value = M.dispatch(statement)
    end
    return last_value
end

return M
