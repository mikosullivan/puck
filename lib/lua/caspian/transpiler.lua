--[[
{
  "module": "caspian.transpiler",
  "role": "Caspian AST → CaspianJ — converts a parsed program node to a Lua table tree ready for JSON encoding",
  "exports": { "transpile": "AST program node → CaspianJ table  [stmt, ...]" },
  "expression_forms": {
    "literal":    {"value": "scalar"},
    "var":        {"var": "name"},
    "ivar":       {"ivar": "name"},
    "varobj":     {"varobj": "name"},
    "sys":        {"sys": "name"},
    "bwc":        {"bwc": "name"},
    "array":      {"array": "[expr,...]"},
    "hash":       {"hash": "{k:expr,...}"},
    "function":   {"function": "{params,kwparams,body}"},
    "untrusted":  {"untrusted": "expr"},
    "safe_nav":   {"safe": "{recv,method}"},
    "pipe":       {"pipe": "{stages:[expr,...],null_safe:bool}"}
  },
  "call_form": "[recv_expr, 'method']  or  [recv_expr, 'method', args_obj]",
  "args_obj_fields": {"args": "[expr,...]", "kwargs": "{k:expr,...}", "block": "{params,body,before?,between?,after?,noloop?,name?}"},
  "statement_forms": {
    "setvar":    ["scope", "setvar",    "name", "expr"],
    "setivar":   ["scope", "setivar",   "name", "expr"],
    "setfunc":   ["scope", "setfunc",   "name", "expr"],
    "setremote": ["scope", "setremote", "name", "expr"],
    "index_set": ["recv",  "[]=",       "{args:[key,val]}"],
    "setter":    ["recv",  "name=",     "{args:[val]}"],
    "return":    ["command", "return",  "expr?"],
    "yield":     ["command", "yield",   "expr?"],
    "while":     ["command", "while",   "{cond,body}"],
    "if":        ["command", "if",      "{expressions:[{when,then},...],else?}"],
    "catch":     ["command", "catch",   "{target,classes,body}"],
    "heed":      ["command", "heed",    "{target,classes,kwargs,body}"],
    "class":     ["command", "class",   "{uns,body:[decl,...]}"]
  },
  "class_decl_forms": [
    "{decl:'inherits', uns}",
    "{decl:'abstract', value}",
    "{decl:'field',    name, opts}",
    "{decl:'join',     fields}",
    "{decl:'accessor', name}",
    "{decl:'helper',   name, body}",
    "{decl:'function', name, type, remote, params, kwparams, body}"
  ]
}
]]
local json = require("caspian.json")
local JSON_NULL = json.null

local M = {}
local json = require("caspian.json")

-- Forward declarations
local transpile_expr, transpile_stmt, transpile_stmts, transpile_block

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------

--[[ { "in": {"pos_args": "node[]?", "kw_args": "{key,value}[]?", "block_node": "AST block node?"}, "out": "args_obj table or nil", "note": "returns nil when all inputs are empty — callers omit args_obj from the call array in that case" } ]]
local function make_args(pos_args, kw_args, block_node)
    local has_pos   = pos_args  and #pos_args  > 0
    local has_kw    = kw_args   and #kw_args   > 0
    local has_block = block_node ~= nil
    if not has_pos and not has_kw and not has_block then return nil end

    local obj = {}
    if has_pos then
        obj.args = {}
        for _, a in ipairs(pos_args) do
            obj.args[#obj.args + 1] = transpile_expr(a)
        end
    end
    if has_kw then
        obj.kwargs = {}
        for _, kw in ipairs(kw_args) do
            obj.kwargs[kw.key] = transpile_expr(kw.value)
        end
    end
    if has_block then
        obj.block = transpile_block(block_node)
    end
    return obj
end

--[[ { "in": {"recv_ksj": "CaspianJ expr", "method": "string", "pos_args": "node[]?", "kw_args": "{key,value}[]?", "block_node": "AST block?"}, "out": "call array  [recv, method]  or  [recv, method, args_obj]" } ]]
local function make_call(recv_ksj, method, pos_args, kw_args, block_node)
    local call = { recv_ksj, method }
    local args = make_args(pos_args, kw_args, block_node)
    if args then call[3] = args end
    return call
end

-- -------------------------------------------------------------------------
-- Block
-- -------------------------------------------------------------------------

--[[ { "in": "node: AST block node or nil", "out": "CaspianJ block object or nil", "note": "copies params; transpiles body, before, between, after, noloop; preserves name" } ]]
transpile_block = function(node)
    if not node then return nil end
    local blk = {
        params = node.params or {},
        body   = transpile_stmts(node.body or {}),
    }
    if node.before  then blk.before  = transpile_stmts(node.before)  end
    if node.between then blk.between = transpile_stmts(node.between) end
    if node.after   then blk.after   = transpile_stmts(node.after)   end
    if node.noloop  then blk.noloop  = transpile_stmts(node.noloop)  end
    if node.name    then blk.name    = node.name                      end
    return blk
end

-- -------------------------------------------------------------------------
-- Pipe  (represented as {"pipe": {stages, null_safe}} — runtime owns it)
-- -------------------------------------------------------------------------

--[[ { "in": "node: pipe AST node", "out": "{'pipe': {stages:[CaspianJ expr,...], null_safe:bool}}", "note": "walks the left-recursive pipe chain to collect stages left-to-right; any |& in the chain sets null_safe=true" } ]]
local function transpile_pipe(node)
    -- Walk the left-recursive pipe chain and collect stages left-to-right.
    local stages = {}
    local null_safe = false
    local cur = node
    while cur.kind == "pipe" do
        table.insert(stages, 1, cur.right)
        if cur.null_safe then null_safe = true end
        cur = cur.left
    end
    table.insert(stages, 1, cur)   -- leftmost expression

    local ksj_stages = {}
    for _, s in ipairs(stages) do
        ksj_stages[#ksj_stages + 1] = transpile_expr(s)
    end
    return { pipe = { stages = ksj_stages, null_safe = null_safe } }
end

-- -------------------------------------------------------------------------
-- Expression
-- -------------------------------------------------------------------------

--[[
{
  "in": "node: AST expression node (or nil)",
  "out": "CaspianJ expression value (tagged object, call array, or JSON_NULL)",
  "dispatches_on": ["number", "string", "bool", "null", "var", "ivar", "varobj", "sys", "self", "ident", "array", "hash", "func_expr", "untrusted", "binop", "unop", "method_call", "safe_call", "func_call", "call", "index", "pipe", "if_stmt", "with_block"],
  "note": "binop/unop → call arrays (operators are methods); nil input → JSON_NULL"
}
]]
transpile_expr = function(node)
    if not node then return JSON_NULL end
    local k = node.kind

    if     k == "number"  then return { value = node.value }
    elseif k == "string"  then return { value = node.value }
    elseif k == "bool"    then return { value = node.value }
    elseif k == "null"    then return { value = JSON_NULL  }
    elseif k == "var"     then return { var    = node.name }
    elseif k == "ivar"    then return { ivar   = node.name }
    elseif k == "varobj"  then return { varobj = node.name }
    elseif k == "sys"     then return { sys    = node.name }
    elseif k == "self"    then return { sys    = "self"    }
    elseif k == "ident"   then return { bwc    = node.name }

    elseif k == "array" then
        local elems = {}
        for _, e in ipairs(node.elements) do
            elems[#elems + 1] = transpile_expr(e)
        end
        return { array = elems }

    elseif k == "hash" then
        -- Canonical hash-literal shape: {"hash": [[k, expr], ...]} (array of pairs).
        -- The pair-array form makes insertion order explicit in the structure,
        -- not dependent on JSON object key-order guarantees.
        local pairs_arr = {}
        for _, p in ipairs(node.pairs) do
            if p.key.kind ~= "string" then
                error("hash key must be a string literal, got " .. p.key.kind)
            end
            pairs_arr[#pairs_arr + 1] = { p.key.value, transpile_expr(p.value) }
        end
        return { hash = pairs_arr }

    elseif k == "func_expr" then
        return {
            ["function"] = {
                params   = node.params,
                kwparams = node.kwparams,
                body     = transpile_stmts(node.body),
            }
        }

    elseif k == "untrusted" then
        return { untrusted = transpile_expr(node.value) }

    elseif k == "binop" then
        -- Operators are method calls: left.op(right)
        return { transpile_expr(node.left), node.op,
                 { args = { transpile_expr(node.right) } } }

    elseif k == "unop" then
        -- Unary  !expr  or  -expr
        return { transpile_expr(node.operand), node.op }

    elseif k == "method_call" then
        return make_call(transpile_expr(node.object), node.name,
                         node.args, node.kwargs, node.block)

    elseif k == "safe_call" then
        local call = { recv = transpile_expr(node.object), method = node.name }
        if node.args and #node.args > 0 or node.kwargs and #node.kwargs > 0 then
            call.args = make_args(node.args, node.kwargs, nil)
        end
        return { safe = call }

    elseif k == "func_call" then
        -- &name(args)  →  call the & method on the value of $name
        return make_call({ var = node.name }, "&",
                         node.args, node.kwargs, node.block)

    elseif k == "call" then
        -- Generic call: callee is any expression (bare-word calls, etc.)
        local callee_ksj = transpile_expr(node.callee)

        -- Bwc-call canonical shape: [{bwc:name}, arg1, arg2, ...] (no method slot,
        -- no {args} wrapper). Detected when the callee transpiles to a bwc receiver
        -- AND there are no kwargs and no block (Corin scope: single positional args).
        if callee_ksj.bwc
            and (not node.kwargs or #node.kwargs == 0)
            and not node.block
        then
            local stmt = { callee_ksj }
            if node.args then
                for _, arg in ipairs(node.args) do
                    stmt[#stmt + 1] = transpile_expr(arg)
                end
            end
            return stmt
        end

        return make_call(callee_ksj, "&",
                         node.args, node.kwargs, nil)

    elseif k == "index" then
        -- $foo['key']  →  [recv, "[]", {args:[key]}]
        return { transpile_expr(node.object), "[]",
                 { args = { transpile_expr(node.key) } } }

    elseif k == "pipe" then
        return transpile_pipe(node)

    elseif k == "if_stmt" then
        -- if used as an expression (right side of assignment)
        local branches = {}
        branches[1] = {
            when     = transpile_expr(node.cond),
            ["then"] = transpile_stmts(node.then_body),
        }
        for _, ei in ipairs(node.elsifs or {}) do
            branches[#branches + 1] = {
                when     = transpile_expr(ei.cond),
                ["then"] = transpile_stmts(ei.body),
            }
        end
        local cmd = { expressions = branches }
        if node.else_body  then cmd["else"] = transpile_stmts(node.else_body) end
        if node.block_name then cmd.name    = node.block_name                 end
        return { "command", "if", cmd }

    elseif k == "with_block" then
        -- $x = &foo do...end  — block was parsed after the assignment =
        -- Attach the block to the inner call.
        local inner = transpile_expr(node.expr)
        if type(inner) == "table" and inner[1] ~= nil then
            local ao = inner[3] or {}
            ao.block = transpile_block(node.block)
            inner[3] = ao
        end
        return inner

    else
        error("transpile_expr: unknown node kind '" .. tostring(k) .. "'")
    end
end

-- -------------------------------------------------------------------------
-- Assignment target dispatch
-- -------------------------------------------------------------------------

--[[ { "in": "node: assign AST node", "out": "CaspianJ statement", "dispatches_on": ["var→setvar", "ivar→setivar", "varobj→setvarobj", "index→[]=", "method_call→setter", "func_call→setfunc", "sys→setsys"] } ]]
local function transpile_assign(node)
    local target  = node.target
    local val_ksj = transpile_expr(node.value)

    if target.kind == "var" then
        return { "scope", "setvar", target.name, val_ksj }
    elseif target.kind == "ivar" then
        return { "scope", "setivar", target.name, val_ksj }
    elseif target.kind == "varobj" then
        return { "scope", "setvarobj", target.name, val_ksj }
    elseif target.kind == "index" then
        -- $foo['key'] = val
        return { transpile_expr(target.object), "[]=",
                 { args = { transpile_expr(target.key), val_ksj } } }
    elseif target.kind == "method_call" then
        -- $foo.bar = val  →  setter call
        return { transpile_expr(target.object), target.name .. "=",
                 { args = { val_ksj } } }
    elseif target.kind == "func_call" then
        -- &foo = val  →  store function in the & namespace
        return { "scope", "setfunc", target.name, val_ksj }
    elseif target.kind == "sys" then
        return { "scope", "setsys", target.name, val_ksj }
    else
        error("transpile_assign: unsupported target kind '" .. target.kind .. "'")
    end
end

-- -------------------------------------------------------------------------
-- If statement
-- -------------------------------------------------------------------------

--[[ { "in": "node: if_stmt AST node", "out": "['command','if',{expressions:[{when,then},...],else?}]", "note": "first branch is the main if; subsequent branches are elsifs" } ]]
local function transpile_if(node)
    local branches = {}
    branches[1] = {
        when     = transpile_expr(node.cond),
        ["then"] = transpile_stmts(node.then_body),
    }
    for _, ei in ipairs(node.elsifs or {}) do
        branches[#branches + 1] = {
            when     = transpile_expr(ei.cond),
            ["then"] = transpile_stmts(ei.body),
        }
    end

    local cmd = { expressions = branches }
    if node.else_body then cmd["else"] = transpile_stmts(node.else_body) end

    return { "command", "if", cmd }
end

-- -------------------------------------------------------------------------
-- Function definition
-- -------------------------------------------------------------------------

--[[ { "in": "node: func_def AST node", "out": "['scope', op, name, {'function':{params,kwparams,body}}]", "note": "op is setvar ($name), setfunc (&name), or setremote (remote &name)" } ]]
local function transpile_func_def(node)
    local fn = {
        ["function"] = {
            params   = node.params,
            kwparams = node.kwparams,
            body     = transpile_stmts(node.body),
        }
    }

    if node.name_type == "var" then
        return { "scope", "setvar",    node.name, fn }
    elseif node.remote then
        return { "scope", "setremote", node.name, fn }
    else
        return { "scope", "setfunc",   node.name, fn }
    end
end

-- -------------------------------------------------------------------------
-- Class body
-- -------------------------------------------------------------------------

--[[ { "in": "body: decl AST node[]", "out": "CaspianJ decl object[]", "note": "maps each class-body declaration kind to its CaspianJ decl object; unknown kinds silently skipped; recurses for helper bodies" } ]]
local function transpile_class_body(body)
    local decls = {}
    for _, d in ipairs(body) do
        if d.kind == "inherits" then
            decls[#decls + 1] = { decl = "inherits", uns = d.uns }

        elseif d.kind == "abstract_decl" then
            decls[#decls + 1] = { decl = "abstract", value = d.value }

        elseif d.kind == "field_decl" then
            local opts = {}
            for k, v in pairs(d.opts or {}) do
                opts[k] = transpile_expr(v)
            end
            decls[#decls + 1] = { decl = "field", name = d.name, opts = opts }

        elseif d.kind == "join_decl" then
            decls[#decls + 1] = { decl = "join", fields = d.fields }

        elseif d.kind == "accessor_decl" then
            decls[#decls + 1] = { decl = "accessor", name = d.name }

        elseif d.kind == "helper_decl" then
            decls[#decls + 1] = {
                decl = "helper",
                name = d.name,
                body = transpile_class_body(d.body),
            }

        elseif d.kind == "func_def" then
            decls[#decls + 1] = {
                decl     = "function",
                name     = d.name,
                type     = d.name_type,
                remote   = d.remote,
                params   = d.params,
                kwparams = d.kwparams,
                body     = transpile_stmts(d.body),
            }
        end
        -- unknown declarations are silently skipped
    end
    return decls
end

-- -------------------------------------------------------------------------
-- Statement
-- -------------------------------------------------------------------------

--[[ { "in": "node: AST statement node", "out": "CaspianJ statement", "dispatches_on": ["assign", "expr_stmt", "return_stmt", "yield_stmt", "if_stmt", "while_stmt", "func_def", "class_def", "catch_stmt", "heed_stmt"] } ]]
transpile_stmt = function(node)
    local k = node.kind

    if k == "assign" then
        return transpile_assign(node)

    elseif k == "expr_stmt" then
        local result = transpile_expr(node.expr)
        -- An 'as $name' implicit block is stored directly on the expr_stmt.
        if node.block then
            if type(result) == "table" and result[1] ~= nil then
                local ao = result[3] or {}
                ao.block = transpile_block(node.block)
                result[3] = ao
            end
        end
        return result

    elseif k == "return_stmt" then
        if node.value then
            return { "command", "return", transpile_expr(node.value) }
        else
            return { "command", "return" }
        end

    elseif k == "yield_stmt" then
        if node.value then
            return { "command", "yield", transpile_expr(node.value) }
        else
            return { "command", "yield" }
        end

    elseif k == "if_stmt" then
        return transpile_if(node)

    elseif k == "while_stmt" then
        return { "command", "while", {
            cond = transpile_expr(node.cond),
            body = transpile_stmts(node.body),
        } }

    elseif k == "func_def" then
        return transpile_func_def(node)

    elseif k == "class_def" then
        return { "command", "class", {
            uns  = node.uns,
            body = transpile_class_body(node.body),
        } }

    elseif k == "catch_stmt" then
        local classes_ksj = {}
        for _, c in ipairs(node.classes or {}) do
            classes_ksj[#classes_ksj + 1] = transpile_expr(c)
        end
        local target_name
        if node.target.kind == "var" then target_name = node.target.name end
        return { "command", "catch", {
            target  = target_name,
            classes = classes_ksj,
            body    = transpile_stmts(node.body),
        } }

    elseif k == "heed_stmt" then
        local classes_ksj = {}
        for _, c in ipairs(node.classes or {}) do
            classes_ksj[#classes_ksj + 1] = transpile_expr(c)
        end
        local kwargs_ksj = {}
        for kname, v in pairs(node.kwargs or {}) do
            kwargs_ksj[kname] = transpile_expr(v)
        end
        local target_name
        if node.target and node.target.kind == "var" then
            target_name = node.target.name
        end
        return { "command", "heed", {
            target  = target_name,
            classes = classes_ksj,
            kwargs  = kwargs_ksj,
            body    = transpile_stmts(node.body),
        } }

    else
        error("transpile_stmt: unknown node kind '" .. tostring(k) .. "'")
    end
end

--[[ { "in": "nodes: AST node[]", "out": "CaspianJ statement[]", "note": "maps transpile_stmt over the array; used for bodies, branches, and class bodies" } ]]
transpile_stmts = function(nodes)
    local out = {}
    for _, n in ipairs(nodes) do
        out[#out + 1] = transpile_stmt(n)
    end
    return out
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

--[[ { "in": "ast: program node  {kind:'program', stmts:[...]}", "out": "CaspianJ Lua table  [stmt,...]", "note": "public entry point; errors if ast.kind ~= 'program'" } ]]
function M.transpile(ast)
    if ast.kind ~= "program" then
        error("transpile: expected program node, got " .. tostring(ast.kind))
    end
    return transpile_stmts(ast.stmts)
end

return M
