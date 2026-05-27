--[[
{
  "module":  "caspian.engine",
  "role":    "Aslan slice — canonical-CaspianJ executor. Reads a .caspj file, parses it, executes top-level statements, returns the last value to the host.",
  "scope":   "Aslan only: a single string literal materialized and a single method (to_string) dispatched. No I/O, no other classes, no other methods, no source-side pipeline.",
  "exports": {
    "run":           "(path) -> value      entry point; bootstraps fresh state, reads + parses file, dispatches each statement, returns the last value",
    "bootstrap":     "() -> nil            initializes engine.state (roles + call_stack) and engine.classes; fully resets every call",
    "materialize":   "(expr) -> value      turns a CaspianJ expression into a value table",
    "lookup_method": "(value, name) -> fn  finds a method on the value's class",
    "transition":    "(frame_meta, fn) -> result   pushes a frame, runs fn, pops, returns fn's result",
    "dispatch":      "(statement) -> value handles one [receiver, method, args?] statement; pushes a method_call frame unconditionally"
  },
  "state": {
    "engine.state.roles":      "role registry; lives IN skeletor (program-visible)",
    "engine.state.call_stack": "the call stack; one top_level frame after bootstrap",
    "engine.classes":          "class registry; engine-private, NOT in skeletor; keyed by UNS-prefixed class name (e.g. \"puck.uno/string\")"
  },
  "value_shape":  "{ type=\"puck.uno/<class>\", owning_role=role_object, payload=any_lua_value }",
  "frame_shape":  "{ action=string, role=role_object, chain={log={},misc={}}, locals={}, ... }",
  "depends_on":   ["caspian.json"],
  "docs":         ["documentation/development/v1/aslan.md", "documentation/caspian/caspianj.md", "documentation/caspian/skeletor/skeletor.md", "documentation/caspian/roles.md"]
}
]]

local json = require("caspian.json")

local M = {}

--[[
{
  "fn":   "top_frame",
  "in":   "(none)",
  "out":  "frame (Lua table)",
  "note": "local helper; returns the topmost frame on engine.state.call_stack"
}
]]
local function top_frame()
    return M.state.call_stack[#M.state.call_stack]
end

--[[
{
  "fn":   "bootstrap",
  "in":   "(none)",
  "out":  "nil",
  "note": "fully resets engine.state and engine.classes; safe to call repeatedly. After: state has user+stdlib roles and one top_level frame; classes has puck.uno/string."
}
]]
function M.bootstrap()
    -- Skeletor: roles registry lives inside state.
    M.state = {
        roles = {
            user   = { name = "user" },
            stdlib = { name = "stdlib" },
        },
        call_stack = {},
    }

    -- Engine-private: class registry is NOT in state. Keys are UNS-prefixed.
    M.classes = {
        ["puck.uno/string"] = {
            name        = "puck.uno/string",
            owning_role = M.state.roles.stdlib,
            methods     = {
                to_string = function(receiver)
                    return receiver
                end,
            },
        },
    }

    -- Top-level frame, with the canonical chain shape (log + misc pre-allocated).
    M.state.call_stack[1] = {
        action = "top_level",
        role   = M.state.roles.user,
        chain  = { log = {}, misc = {} },
        locals = {},
    }
end

--[[
{
  "fn":  "materialize",
  "in":  "expr (CaspianJ expression table; Aslan supports {value:<string>} only)",
  "out": "value table {type, owning_role, payload}",
  "note": "owning_role is the current top-frame's role; raises on any unsupported expression form or non-string literal payload."
}
]]
function M.materialize(expr)
    if type(expr) ~= "table" then
        error("engine.materialize: expected an expression table, got " .. type(expr))
    end

    if expr.value ~= nil then
        local lua_type = type(expr.value)
        local ksj_type

        if lua_type == "string" then
            ksj_type = "puck.uno/string"
        end

        if not ksj_type then
            error("engine.materialize: unsupported literal type in Aslan: " .. lua_type)
        end

        return {
            type        = ksj_type,
            owning_role = top_frame().role,
            payload     = expr.value,
        }
    end

    error("engine.materialize: unsupported expression form in Aslan: "
        .. (next(expr) or "<empty>"))
end

--[[
{
  "fn":  "lookup_method",
  "in":  "(value, method_name)",
  "out": "method function",
  "note": "resolves via engine.classes[value.type].methods[method_name]; raises if class or method is missing."
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
  "fn":  "transition",
  "in":  "(frame_meta, fn)",
  "out": "fn's return value",
  "note": "pushes a frame onto state.call_stack with the canonical chain shape, runs fn, pops the frame, returns fn's result. Called for every method call regardless of role; the per-frame fresh chain provides isolation."
}
]]
function M.transition(frame_meta, fn)
    local frame = {
        action        = frame_meta.action,
        role          = frame_meta.role,
        receiver_type = frame_meta.receiver_type,
        method        = frame_meta.method,
        chain         = { log = {}, misc = {} },
        locals        = {},
    }
    table.insert(M.state.call_stack, frame)
    local result = fn()
    table.remove(M.state.call_stack)
    return result
end

--[[
{
  "fn":  "dispatch",
  "in":  "statement: [receiver_expr, method_name, args?]  (Aslan: no args)",
  "out": "the method's return value (a value table)",
  "note": "pushes a method_call frame unconditionally (same-role and cross-role both push); the new frame's chain is fresh per skeletor.md's per-frame-chain model. Args at statement[3+] are deferred to Bree."
}
]]
function M.dispatch(statement)
    if type(statement) ~= "table" then
        error("engine.dispatch: expected a statement table")
    end

    local receiver    = M.materialize(statement[1])
    local method_name = statement[2]
    local method_fn   = M.lookup_method(receiver, method_name)
    local class       = M.classes[receiver.type]

    return M.transition({
        action        = "method_call",
        role          = class.owning_role,
        receiver_type = receiver.type,
        method        = method_name,
    }, function()
        return method_fn(receiver)
    end)
end

--[[
{
  "fn":  "run",
  "in":  "path: filesystem path to a .caspj file",
  "out": "value table of the last statement's result, or nil if the program is empty",
  "note": "calls bootstrap (fresh state), reads file, parses JSON, dispatches each statement, returns the last. Host extracts .payload."
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
        error("engine.run: top-level CaspianJ must be an array of statements")
    end

    local last_value = nil
    for _, statement in ipairs(tree) do
        last_value = M.dispatch(statement)
    end

    return last_value
end

return M
