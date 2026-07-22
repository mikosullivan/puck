--[[
{
  "module":  "caspian.engine",
  "role":    "Canonical-CaspianJ executor. The host configures the engine via property assignment (engine.caspianj = tree, engine.std = sink, engine.root = jail), then calls engine.run() to execute. No arguments to run; everything comes from staged properties. Matches bootstrap.md's host capability model.",
  "scope":   "Aslan + Bree: a single string literal materialized and a single method (to_string) dispatched. No I/O, no other classes, no other methods. Corin will add bwc dispatch + engine.std stdout sink.",
  "exports": {
    "parse_caspian": "(source) -> tree         lex + parse + transpile Caspian source to a CaspianJ Lua table",
    "run":           "() -> value              entry point; reads engine.caspianj, bootstraps fresh state, dispatches each statement, returns the last value",
    "bootstrap":     "() -> nil                initializes engine.state (roles + call_stack) and engine.classes; fully resets every call",
    "materialize":   "(expr) -> value          turns a CaspianJ expression into a value table",
    "lookup_method": "(value, name) -> fn      finds a method on the value's class",
    "transition":    "(frame_meta, fn) -> result   pushes a frame, runs fn, pops, returns fn's result",
    "dispatch":      "(statement) -> value     handles one [receiver, method, args?] statement; pushes a method_call frame unconditionally"
  },
  "properties": {
    "caspianj":     "CaspianJ tree to execute. Host stages it before calling run(). Persists across runs until reassigned.",
    "std":          "(future, Corin) stdout sink function. Host injects before run(); puts bwc writes to it.",
    "root":         "(future) dirjail for filesystem access. Host injects before run()."
  },
  "state": {
    "engine.state.roles":      "role registry; lives IN drinian (program-visible)",
    "engine.state.call_stack": "the call stack; one top_level frame after bootstrap",
    "engine.classes":          "class registry; engine-private, NOT in drinian; keyed by UNS-prefixed class name (e.g. \"puck.uno/string\")"
  },
  "value_shape":  "{ type=\"puck.uno/<class>\", owning_role=role_object, payload=any_lua_value }",
  "frame_shape":  "{ action=string, role=role_object, chain={log={},misc={}}, locals={}, ... }",
  "depends_on":   ["caspian.lexer", "caspian.parser", "caspian.transpiler"],
  "docs":         ["documentation/development/v1/caspian/aslan.md", "documentation/development/v1/caspian/bree.md", "documentation/development/v1/caspian/corin.md", "documentation/development/v1/caspian/digory.md", "documentation/caspian/caspianj.md", "documentation/caspian/drinian/index.md", "documentation/caspian/roles.md"]
}
]]

local lexer      = require("caspian.lexer")
local parser     = require("caspian.parser")
local transpiler = require("caspian.transpiler")
local json       = require("caspian.json")

local M = {}

--[[
{
  "fn":   "parse_caspian",
  "in":   "source: Caspian source string",
  "out":  "CaspianJ tree (Lua table; array of statements)",
  "note": "Pure function: lex → parse → transpile. Does not touch engine state. Canonical home for the Caspian-source-to-tree pipeline; previously caspian.transpile, moved here so the host only needs to touch one module."
}
]]
function M.parse_caspian(source)
    local tokens = lexer.tokenize(source)
    local ast    = parser.parse(tokens)
    return transpiler.transpile(ast)
end

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
  "note": "fully resets engine.state and engine.classes; safe to call repeatedly. After: state has user+stdlib roles and one top_level frame; classes has puck.uno/string. Called internally by run(); host does not normally call this directly."
}
]]
function M.bootstrap()
    -- Drinian: roles registry lives inside state.
    M.state = {
        roles = {
            user   = { name = "user"   },
            stdlib = { name = "stdlib" },
            stdout = { name = "stdout" },
            stderr = { name = "stderr" },
        },
        call_stack = {},
        -- argv: program's view of the OS argv after the script path.
        -- Host (Frank's CLI launcher) installs engine.argv before calling
        -- engine.run(); bootstrap copies it here. Empty when unset.
        argv = M.argv or {},
    }

    -- to_json walks the materialized value tree, producing a JSON string.
    -- Primitives (string/number/bool/null) have json-encodable payloads
    -- directly. Hash payloads contain nested value tables, so we recurse
    -- and reassemble — preserving insertion order via json.hash_keys.
    local function value_to_json(value)
        if value.type == "puck.uno/hash" then
            local out = {}
            local keys = json.hash_keys(value.payload)
            for _, k in ipairs(keys) do
                out[#out + 1] = json.encode(k, false) .. ":" .. value_to_json(value.payload[k])
            end
            return "{" .. table.concat(out, ",") .. "}"
        end
        return json.encode(value.payload, false)
    end

    local function to_json_method(receiver)
        return {
            type        = "puck.uno/string",
            owning_role = top_frame().role,
            payload     = value_to_json(receiver),
        }
    end

    -- Engine-private: class registry is NOT in state. Keys are UNS-prefixed.
    M.classes = {
        ["puck.uno/string"] = {
            name        = "puck.uno/string",
            owning_role = M.state.roles.stdlib,
            methods     = {
                to_string = function(receiver) return receiver end,
                to_json   = to_json_method,
            },
        },

        ["puck.uno/number"] = {
            name        = "puck.uno/number",
            owning_role = M.state.roles.stdlib,
            methods     = { to_json = to_json_method },
        },

        ["puck.uno/null"] = {
            name        = "puck.uno/null",
            owning_role = M.state.roles.stdlib,
            methods     = { to_json = to_json_method },
        },

        ["puck.uno/true"] = {
            name        = "puck.uno/true",
            owning_role = M.state.roles.stdlib,
            methods     = { to_json = to_json_method },
        },

        ["puck.uno/false"] = {
            name        = "puck.uno/false",
            owning_role = M.state.roles.stdlib,
            methods     = { to_json = to_json_method },
        },

        ["puck.uno/hash"] = {
            name        = "puck.uno/hash",
            owning_role = M.state.roles.stdlib,
            methods     = { to_json = to_json_method },
            -- Hash dispatches every other method through method_missing,
            -- which reads the bucket. See Digory.
            method_missing = function(receiver, name)
                local v = receiver.payload[name]
                if v == nil then
                    error("puck.uno/hash: no such key '" .. tostring(name) .. "'")
                end
                return v
            end,
        },
    }

    -- Engine-private: bwc registry. Each entry carries handler + owning role.
    M.bwcs = {
        puts = {
            owning_role = M.state.roles.stdout,
            fn = function(value)
                local sink = M.std
                if sink == nil then
                    error("puts: engine.std is not set — host must install a stdout sink (see bootstrap.md § stdout and stderr)")
                end
                sink(tostring(value.payload) .. "\n")
            end,
        },
        eprint = {
            owning_role = M.state.roles.stderr,
            fn = function(value)
                local sink = M.err
                if sink == nil then
                    error("eprint: engine.err is not set — host must install a stderr sink (see bootstrap.md § stdout and stderr)")
                end
                sink(tostring(value.payload) .. "\n")
            end,
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

    -- JSON null is a sentinel table, so it passes `expr.value ~= nil`.
    -- Catch it FIRST so it doesn't fall into the generic type-dispatch
    -- (which would see lua_type == "table" and treat it like a hash).
    if expr.value == json.null then
        return {
            type        = "puck.uno/null",
            owning_role = top_frame().role,
            payload     = json.null,
        }
    end

    if expr.value ~= nil then
        local lua_type = type(expr.value)
        local ksj_type

        if lua_type == "string" then
            ksj_type = "puck.uno/string"
        elseif lua_type == "number" then
            ksj_type = "puck.uno/number"
        elseif lua_type == "boolean" then
            ksj_type = expr.value and "puck.uno/true" or "puck.uno/false"
        end

        if not ksj_type then
            error("engine.materialize: unsupported literal type: " .. lua_type)
        end

        return {
            type        = ksj_type,
            owning_role = top_frame().role,
            payload     = expr.value,
        }
    end

    -- Sys reference: {"sys": "<name>"} — resolves engine-supplied values.
    -- Frank scope: %argv only. Later slices add %now, %utils, etc.
    -- %argv materializes as a space-joined string for now (arrays arrive
    -- in a later slice; when they do, %argv graduates to puck.uno/array).
    if expr.sys ~= nil then
        if expr.sys == "argv" then
            return {
                type        = "puck.uno/string",
                owning_role = top_frame().role,
                payload     = table.concat(M.state.argv or {}, " "),
            }
        end
        error("engine.materialize: unsupported %sys reference: " .. tostring(expr.sys))
    end

    -- Hash literal: canonical CaspianJ shape is {"hash": [[k, expr], ...]}.
    -- Payload is a json.new_hash so insertion order is preserved.
    if expr.hash ~= nil then
        if type(expr.hash) ~= "table" then
            error("engine.materialize: hash expression must have an array-of-pairs payload")
        end
        local payload = json.new_hash()
        for _, pair in ipairs(expr.hash) do
            local key = pair[1]
            if type(key) ~= "string" then
                error("engine.materialize: hash key must be a string, got " .. type(key))
            end
            json.hash_set(payload, key, M.materialize(pair[2]))
        end
        return {
            type        = "puck.uno/hash",
            owning_role = top_frame().role,
            payload     = payload,
        }
    end

    error("engine.materialize: unsupported expression form: "
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
    if method_fn then return method_fn end

    -- method_missing fallback: class can declare a catch-all handler that
    -- receives (receiver, method_name). Wrap it so the dispatcher's
    -- `method_fn(receiver)` call still works uniformly.
    if class.method_missing then
        return function(receiver)
            return class.method_missing(receiver, method_name)
        end
    end

    error("engine.lookup_method: method '" .. tostring(method_name)
        .. "' not found on class " .. class.name)
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
        receiver_type = frame_meta.receiver_type,  -- method_call only
        method        = frame_meta.method,         -- method_call only
        bwc           = frame_meta.bwc,            -- bwc_call only
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
  "in":  "statement: a CaspianJ statement. Two shapes today: method-call [receiver, method, args?] and bwc-call [{bwc:name}, arg1?, ...].",
  "out": "the call's return value (a value table for method calls; bwc handler return for bwc calls, typically nil)",
  "note": "Pushes a frame unconditionally. method_call frames carry receiver_type+method; bwc_call frames carry bwc instead. The new frame's chain is fresh per drinian.md's per-frame-chain model."
}
]]
function M.dispatch(statement)
    if type(statement) ~= "table" then
        error("engine.dispatch: expected a statement table")
    end

    -- Bwc-call shape: [{bwc:name}, arg1?, arg2?, ...]
    local head = statement[1]
    if type(head) == "table" and head.bwc then
        local bwc_name = head.bwc
        local entry    = M.bwcs and M.bwcs[bwc_name]
        if not entry then
            error("engine.dispatch: no bwc registered for name '" .. tostring(bwc_name) .. "'")
        end

        -- Materialize the first arg (Corin scope: single positional arg).
        local arg = nil
        if statement[2] ~= nil then
            arg = M.materialize(statement[2])
        end

        return M.transition({
            action = "bwc_call",
            role   = entry.owning_role,
            bwc    = bwc_name,
        }, function()
            return entry.fn(arg)
        end)
    end

    -- Method-call shape: [receiver, method, args?]
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
  "in":  "(none) — reads engine.caspianj for the tree to execute",
  "out": "value table of the last statement's result, or nil if the program is empty",
  "note": "No arguments. The host stages the tree on engine.caspianj (and capabilities on engine.std, engine.root, etc.) before calling run(). Calls bootstrap (fresh state), then dispatches each statement, returns the last."
}
]]
function M.run()
    local tree = M.caspianj
    if type(tree) ~= "table" then
        error("engine.run: engine.caspianj must be set to a CaspianJ tree (Lua table) before calling run; got " .. type(tree))
    end

    M.bootstrap()

    local last_value = nil
    for _, statement in ipairs(tree) do
        last_value = M.dispatch(statement)
    end

    return last_value
end

return M
