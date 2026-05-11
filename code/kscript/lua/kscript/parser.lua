--[[
{
  "module": "kscript.parser",
  "role": "Recursive descent parser for KScript — converts a token array to an AST",
  "exports": { "parse": "token[] → AST  {kind:'program', stmts:[node,...]}" },
  "node_kinds": [
    "program", "assign", "func_def", "func_expr", "class_def",
    "if_stmt", "while_stmt", "catch_stmt", "heed_stmt", "yield_stmt", "return_stmt",
    "expr_stmt", "with_block",
    "var", "varobj", "ivar", "sys", "self", "ident",
    "func_call", "method_call", "safe_call", "call", "index",
    "string", "number", "bool", "null", "array", "hash",
    "binop", "unop", "pipe", "block",
    "untrusted", "inherits", "field_decl", "join_decl", "property_decl", "abstract_decl", "helper_decl"
  ],
  "operator_precedence": ["pipe (| |&)", "or (||)", "and (&&)", "cmp (== != < > <= >=)", "add (+ -)", "mul (* /)", "unary (! -)"],
  "note": "String interpolation in double-quoted strings stored raw; evaluator handles it"
}
]]
local M = {}

--[[ { "in": "tokens: token[]", "out": "parser object  (call :parse() to produce AST)", "note": "factory; creates all inner parsing closures" } ]]
local function new_parser(tokens)
    local p = { tokens = tokens, pos = 1 }

    -- -------------------------------------------------------------------------
    -- Helpers
    -- -------------------------------------------------------------------------

    --[[ { "in": "n: number?  (default 0)", "out": "token  (at pos+n, or EOF sentinel)", "note": "non-consuming lookahead" } ]]
    local function peek(n)
        local i = p.pos + (n or 0)
        return p.tokens[i] or { type = "EOF" }
    end

    --[[ { "out": "token  (current token without consuming)" } ]]
    local function cur()      return peek(0) end
    --[[ { "out": "string  (type field of current token)" } ]]
    local function cur_type() return cur().type end
    --[[ { "out": "any  (value field of current token)" } ]]
    local function cur_val()  return cur().value end

    --[[ { "out": "token  (the token consumed)", "note": "advances pos" } ]]
    local function advance()
        local t = p.tokens[p.pos]
        p.pos = p.pos + 1
        return t
    end

    --[[ { "in": {"typ": "string", "val": "any?"}, "out": "token  (consumed)", "note": "errors with line number if type or value doesn't match" } ]]
    local function expect(typ, val)
        local t = cur()
        if t.type ~= typ then
            error(string.format("line %d: expected %s but got %s %q",
                t.line, typ, t.type, tostring(t.value)))
        end
        if val ~= nil and t.value ~= val then
            error(string.format("line %d: expected %s %q but got %q",
                t.line, typ, tostring(val), tostring(t.value)))
        end
        return advance()
    end

    --[[ { "note": "consumes zero or more NEWLINE tokens; used before bodies and after operator-split lines" } ]]
    local function skip_newlines()
        while cur_type() == "NEWLINE" do advance() end
    end

    --[[ { "in": {"typ": "string", "val": "any?"}, "out": "bool", "note": "non-consuming; tests type and optional value of current token" } ]]
    local function at(typ, val)
        if cur_type() ~= typ then return false end
        if val ~= nil and cur_val() ~= val then return false end
        return true
    end

    --[[ { "in": "word: string", "out": "bool", "note": "keywords are IDENT tokens; tests cur type == IDENT and cur value == word" } ]]
    local function kw(word) return cur_type() == "IDENT" and cur_val() == word end

    --[[ { "in": {"kind": "string", "fields": "table?"}, "out": "AST node table", "note": "stamps kind onto fields (or a new table); returns the node" } ]]
    local function node(kind, fields)
        local n = fields or {}
        n.kind = kind
        return n
    end

    -- -------------------------------------------------------------------------
    -- Forward declarations
    -- -------------------------------------------------------------------------
    local parse_expr, parse_stmts

    -- -------------------------------------------------------------------------
    -- Call argument list: (pos_arg, ..., kw_name: val, ...)
    -- -------------------------------------------------------------------------
    --[[ { "out": "args: node[], kwargs: {key,value}[]", "note": "consumes LPAREN…RPAREN; bare_ident ':' starts a kwarg, otherwise positional" } ]]
    local function parse_call_args()
        expect("LPAREN")
        local args, kwargs = {}, {}
        skip_newlines()
        while not at("RPAREN") and not at("EOF") do
            skip_newlines()
            -- keyword arg: bare_ident ':'
            if cur_type() == "IDENT" and peek(1).type == "COLON" then
                local key = advance().value
                advance()  -- ':'
                kwargs[#kwargs + 1] = { key = key, value = parse_expr() }
            else
                args[#args + 1] = parse_expr()
            end
            skip_newlines()
            if at("COMMA") then advance() end
        end
        expect("RPAREN")
        return args, kwargs
    end

    -- -------------------------------------------------------------------------
    -- do($param, ...) block with optional before/between/after/noloop clauses
    -- -------------------------------------------------------------------------
    --[[ { "out": "block node  {kind, params, body, before?, between?, after?, noloop?}", "note": "consumes 'do' … 'end'; params are bare variable names (no $)" } ]]
    local function parse_do_block()
        expect("IDENT", "do")

        local params = {}
        if at("LPAREN") then
            advance()
            while not at("RPAREN") and not at("EOF") do
                if cur_type() == "VAR" then params[#params + 1] = advance().value end
                if at("COMMA") then advance() end
            end
            expect("RPAREN")
        end

        skip_newlines()
        local body = parse_stmts({ "before", "between", "after", "noloop", "end" })

        local clauses = {}
        for _, clause in ipairs({ "before", "between", "after", "noloop" }) do
            if kw(clause) then
                advance(); skip_newlines()
                local remaining = { "before", "between", "after", "noloop", "end" }
                -- only clauses that come after this one remain as stops
                local stops = { "end" }
                local found = false
                for _, c in ipairs({ "before", "between", "after", "noloop" }) do
                    if found then stops[#stops + 1] = c end
                    if c == clause then found = true end
                end
                clauses[clause] = parse_stmts(stops)
            end
        end

        expect("IDENT", "end")

        return node("block", {
            params  = params,
            body    = body,
            before  = clauses.before,
            between = clauses.between,
            after   = clauses.after,
            noloop  = clauses.noloop,
        })
    end

    -- -------------------------------------------------------------------------
    -- No-paren argument lists: method arg1, :sym, kw: val  (stops at newline/do/EOF)
    -- -------------------------------------------------------------------------
    --[[ { "out": "bool", "note": "true if current token can begin an argument — used to detect no-paren call sites after a DOT or IDENT" } ]]
    local function can_start_arg()
        local t = cur_type()
        return t == "STRING" or t == "NUMBER" or t == "BOOL"   or t == "NULL"   or
               t == "SYMBOL" or t == "VAR"    or t == "VAROBJ" or t == "IVAR"   or
               t == "FUNC"   or t == "SYS"    or t == "LBRACK" or t == "LBRACE" or
               t == "LPAREN" or (t == "OP" and (cur_val() == "!" or cur_val() == "-"))
    end

    --[[ { "out": "args: node[], kwargs: {key,value}[]", "note": "parses comma-separated args without surrounding parens; stops at NEWLINE, EOF, or 'do'" } ]]
    local function parse_no_paren_args()
        local args, kwargs = {}, {}
        repeat
            if cur_type() == "IDENT" and peek(1).type == "COLON" then
                local key = advance().value
                advance()  -- ':'
                kwargs[#kwargs + 1] = { key = key, value = parse_expr() }
            else
                args[#args + 1] = parse_expr()
            end
            if at("COMMA") then advance() else break end
        until at("NEWLINE") or at("EOF") or kw("do")
        return args, kwargs
    end

    -- -------------------------------------------------------------------------
    -- Postfix chain: .method, &.method, [key], (args)
    -- Checks for a trailing `do` block after method calls.
    -- -------------------------------------------------------------------------
    --[[ { "in": "base: AST node", "out": "AST node", "note": "left-recursively wraps base in method_call/safe_call/index/call nodes; also attaches do-blocks" } ]]
    local function parse_postfix(base)
        while true do
            if at("DOT") then
                advance()
                local name = expect("IDENT").value
                local args, kwargs
                if     at("LPAREN")    then args, kwargs = parse_call_args()
                elseif can_start_arg() then args, kwargs = parse_no_paren_args() end
                local blk
                if kw("do") then blk = parse_do_block() end
                base = node("method_call", {
                    object = base, name = name,
                    args   = args or {}, kwargs = kwargs or {},
                    block  = blk,
                })

            elseif at("SAFENAV") then
                advance()
                local name = expect("IDENT").value
                local args, kwargs
                if at("LPAREN") then args, kwargs = parse_call_args() end
                base = node("safe_call", {
                    object = base, name = name,
                    args   = args or {}, kwargs = kwargs or {},
                })

            elseif at("LBRACK") then
                advance()
                local key = parse_expr()
                expect("RBRACK")
                base = node("index", { object = base, key = key })

            elseif at("LPAREN") then
                local args, kwargs = parse_call_args()
                base = node("call", { callee = base, args = args, kwargs = kwargs })

            else
                break
            end
        end
        return base
    end

    -- -------------------------------------------------------------------------
    -- Function parameter list parser (shared by func_def and func_expr)
    -- -------------------------------------------------------------------------
    --[[ { "out": "params: string[], kwparams: string[]", "note": "parses optional LPAREN…RPAREN; $name → positional, bare_ident ':' → keyword param; returns empty arrays if no parens" } ]]
    local function parse_func_params()
        local params, kwparams = {}, {}
        if at("LPAREN") then
            advance()
            while not at("RPAREN") and not at("EOF") do
                if cur_type() == "VAR" then
                    params[#params + 1] = advance().value
                elseif cur_type() == "IDENT" and peek(1).type == "COLON" then
                    local name = advance().value
                    advance()  -- ':'
                    kwparams[#kwparams + 1] = name
                end
                if at("COMMA") then advance() end
            end
            expect("RPAREN")
        end
        return params, kwparams
    end

    -- -------------------------------------------------------------------------
    -- Primary expressions
    -- -------------------------------------------------------------------------
    --[[
    {
      "out": "AST node",
      "dispatches_on": ["VAR ($)", "VAROBJ ($$)", "IVAR (@)", "FUNC (&name)", "SAFENAV (&.)", "SYS (%)", "STRING", "SYMBOL", "NUMBER", "BOOL", "NULL", "LPAREN (grouped expr)", "LBRACK (array)", "LBRACE (hash)", "IDENT: self/untrusted/function/if/bare-word"],
      "note": "bare IDENT followed by a startable-arg token becomes a no-paren call node; LPAREN excluded to avoid ambiguity with grouped expressions"
    }
    ]]
    local function parse_primary()
        local t = cur()

        -- $var
        if t.type == "VAR" then
            advance()
            return parse_postfix(node("var", { name = t.value }))

        -- $$varobj
        elseif t.type == "VAROBJ" then
            advance()
            return parse_postfix(node("varobj", { name = t.value }))

        -- @ivar
        elseif t.type == "IVAR" then
            advance()
            return parse_postfix(node("ivar", { name = t.value }))

        -- &func_call
        elseif t.type == "FUNC" then
            advance()
            local args, kwargs
            if at("LPAREN") then args, kwargs = parse_call_args() end
            local blk
            if kw("do") then blk = parse_do_block() end
            return parse_postfix(node("func_call", {
                name   = t.value,
                args   = args or {}, kwargs = kwargs or {},
                block  = blk,
            }))

        -- &. safe navigation from implicit self
        elseif t.type == "SAFENAV" then
            advance()
            local name = expect("IDENT").value
            return node("safe_call", { object = node("self"), name = name })

        -- %sys
        elseif t.type == "SYS" then
            advance()
            return parse_postfix(node("sys", { name = t.value }))

        -- String literal
        elseif t.type == "STRING" then
            advance()
            return node("string", { value = t.value })

        -- :symbol is just string shorthand
        elseif t.type == "SYMBOL" then
            advance()
            return node("string", { value = t.value })

        -- Number
        elseif t.type == "NUMBER" then
            advance()
            return node("number", { value = t.value })

        -- Boolean
        elseif t.type == "BOOL" then
            advance()
            return node("bool", { value = t.value })

        -- Null
        elseif t.type == "NULL" then
            advance()
            return node("null")

        -- self
        elseif t.type == "IDENT" and t.value == "self" then
            advance()
            return parse_postfix(node("self"))

        -- untrusted($expr)
        elseif t.type == "IDENT" and t.value == "untrusted" then
            advance()
            expect("LPAREN")
            local val = parse_expr()
            expect("RPAREN")
            return node("untrusted", { value = val })

        -- Anonymous function expression: function(...) ... end
        elseif t.type == "IDENT" and t.value == "function" then
            advance()
            local params, kwparams = parse_func_params()
            skip_newlines()
            local body = parse_stmts({ "end" })
            expect("IDENT", "end")
            return node("func_expr", { params = params, kwparams = kwparams, body = body })

        -- Parenthesised expression
        elseif t.type == "LPAREN" then
            advance()
            local val = parse_expr()
            expect("RPAREN")
            return parse_postfix(val)

        -- Array literal: [a, b, c]
        elseif t.type == "LBRACK" then
            advance()
            local elems = {}
            skip_newlines()
            while not at("RBRACK") and not at("EOF") do
                skip_newlines()
                elems[#elems + 1] = parse_expr()
                skip_newlines()
                if at("COMMA") then advance() end
                skip_newlines()
            end
            expect("RBRACK")
            return node("array", { elements = elems })

        -- Hash literal: {key: val, 'key': val, :sym => val}
        elseif t.type == "LBRACE" then
            advance()
            local pairs = {}
            skip_newlines()
            while not at("RBRACE") and not at("EOF") do
                skip_newlines()
                local key
                if cur_type() == "IDENT" and peek(1).type == "COLON" then
                    -- bare_word: val
                    key = node("string", { value = advance().value })
                    advance()  -- ':'
                elseif cur_type() == "STRING" and peek(1).type == "COLON" then
                    -- 'string': val
                    key = node("string", { value = advance().value })
                    advance()  -- ':'
                elseif cur_type() == "SYMBOL" then
                    -- :sym => val
                    key = node("string", { value = advance().value })
                    expect("ROCKET")
                else
                    -- fallback: expr => val
                    key = parse_expr()
                    if at("ROCKET") then advance() end
                end
                local val = parse_expr()
                pairs[#pairs + 1] = { key = key, value = val }
                skip_newlines()
                if at("COMMA") then advance() end
                skip_newlines()
            end
            expect("RBRACE")
            return node("hash", { pairs = pairs })

        -- if as expression: $x = if (cond) ... end
        elseif t.type == "IDENT" and t.value == "if" then
            advance()
            expect("LPAREN")
            local cond = parse_expr()
            expect("RPAREN")
            -- optional 'as $name' binding on the if
            local block_name
            if kw("as") then
                advance()
                if cur_type() == "VAR" then block_name = advance().value end
            end
            skip_newlines()
            local then_body = parse_stmts({ "elsif", "else", "end" })
            local elsifs = {}
            while kw("elsif") do
                advance()
                expect("LPAREN")
                local ec = parse_expr()
                expect("RPAREN")
                skip_newlines()
                local eb = parse_stmts({ "elsif", "else", "end" })
                elsifs[#elsifs + 1] = { cond = ec, body = eb }
            end
            local else_body
            if kw("else") then
                advance(); skip_newlines()
                else_body = parse_stmts({ "end" })
            end
            expect("IDENT", "end")
            return node("if_stmt", {
                cond       = cond,
                then_body  = then_body,
                elsifs     = elsifs,
                else_body  = else_body,
                block_name = block_name,
            })

        -- Bare identifier — may be a no-paren call: puts $v, puts &func, etc.
        -- LPAREN is intentionally excluded here; parse_postfix handles it.
        elseif t.type == "IDENT" then
            advance()
            local base = node("ident", { name = t.value })
            local ct = cur_type()
            local is_noparen = ct == "STRING" or ct == "NUMBER" or ct == "BOOL" or
                ct == "NULL"   or ct == "SYMBOL" or ct == "VAR"    or ct == "VAROBJ" or
                ct == "IVAR"   or ct == "FUNC"   or ct == "SYS"    or ct == "LBRACK" or
                ct == "LBRACE" or (ct == "OP" and (cur_val() == "!" or cur_val() == "-"))
            if is_noparen then
                local args, kwargs = parse_no_paren_args()
                base = node("call", { callee = base, args = args, kwargs = kwargs })
            end
            return parse_postfix(base)

        else
            error(string.format("line %d: unexpected token %s %q",
                t.line, t.type, tostring(t.value)))
        end
    end

    -- -------------------------------------------------------------------------
    -- Operator precedence levels (lowest to highest binding):
    --   pipe  |  |&
    --   or    ||
    --   and   &&
    --   cmp   == != < > <= >=
    --   add   + -
    --   mul   * /
    --   unary ! -
    --   postfix/primary
    -- -------------------------------------------------------------------------

    -- Operator precedence chain (lowest to highest binding — each calls the next level):
    --   parse_pipe → parse_or → parse_and → parse_cmp → parse_add → parse_mul → parse_unary → parse_primary

    --[[ { "out": "AST node", "note": "handles prefix ! and unary -; recurses for chaining (!!x)" } ]]
    local function parse_unary()
        if at("OP", "!") then
            advance(); return node("unop", { op = "!", operand = parse_unary() })
        elseif at("OP", "-") then
            advance(); return node("unop", { op = "-", operand = parse_unary() })
        end
        return parse_primary()
    end

    --[[ { "out": "AST node", "note": "left-recursive * and /" } ]]
    local function parse_mul()
        local left = parse_unary()
        while at("OP", "*") or at("OP", "/") do
            local op = advance().value
            left = node("binop", { op = op, left = left, right = parse_unary() })
        end
        return left
    end

    --[[ { "out": "AST node", "note": "left-recursive + and -" } ]]
    local function parse_add()
        local left = parse_mul()
        while at("OP", "+") or at("OP", "-") do
            local op = advance().value
            left = node("binop", { op = op, left = left, right = parse_mul() })
        end
        return left
    end

    --[[ { "out": "AST node", "note": "single comparison (== != < > <= >=); not left-recursive — no chaining" } ]]
    local function parse_cmp()
        local left = parse_add()
        if at("OP","==") or at("OP","!=") or at("OP","<") or
           at("OP",">")  or at("OP","<=") or at("OP",">=") then
            local op = advance().value
            return node("binop", { op = op, left = left, right = parse_add() })
        end
        return left
    end

    --[[ { "out": "AST node", "note": "left-recursive &&" } ]]
    local function parse_and()
        local left = parse_cmp()
        while at("OP", "&&") do
            advance()
            left = node("binop", { op = "&&", left = left, right = parse_cmp() })
        end
        return left
    end

    --[[ { "out": "AST node", "note": "left-recursive ||" } ]]
    local function parse_or()
        local left = parse_and()
        while at("OP", "||") do
            advance()
            left = node("binop", { op = "||", left = left, right = parse_and() })
        end
        return left
    end

    --[[ { "out": "AST node", "note": "left-recursive | and |&; sets null_safe=true on any |& in the chain; allows newline after pipe operator" } ]]
    local function parse_pipe()
        local left = parse_or()
        local null_safe = false
        while at("OP", "|") or at("OP", "|&") do
            if at("OP", "|&") then null_safe = true end
            advance()
            skip_newlines()  -- pipes may split across lines
            left = node("pipe", { left = left, right = parse_or(), null_safe = null_safe })
        end
        return left
    end

    parse_expr = parse_pipe

    -- -------------------------------------------------------------------------
    -- Function definition: function $name(...) ... end
    --                      function &name(...) ... end
    -- -------------------------------------------------------------------------
    --[[ { "in": "remote: bool", "out": "func_def node  {name, name_type ('var'|'func'), params, kwparams, body, remote}", "note": "called after 'function' keyword is consumed" } ]]
    local function parse_func_def(remote)
        local name, name_type
        if cur_type() == "VAR" then
            name, name_type = advance().value, "var"
        elseif cur_type() == "FUNC" then
            name, name_type = advance().value, "func"
        else
            error(string.format("line %d: expected function name ($name or &name), got %s",
                cur().line, cur_type()))
        end
        local params, kwparams = parse_func_params()
        skip_newlines()
        local body = parse_stmts({ "end" })
        expect("IDENT", "end")
        return node("func_def", {
            name      = name,
            name_type = name_type,
            params    = params,
            kwparams  = kwparams,
            body      = body,
            remote    = remote or false,
        })
    end

    -- -------------------------------------------------------------------------
    -- Class body: inherits, abstract, field, join, property, helper, function
    -- -------------------------------------------------------------------------
    --[[ { "out": "decl[]  (array of AST nodes)", "note": "parses class body declarations until 'end' or EOF; also used recursively for helper bodies" } ]]
    local function parse_class_body()
        local decls = {}
        skip_newlines()
        while not kw("end") and not at("EOF") do

            if kw("inherits") then
                advance()
                decls[#decls + 1] = node("inherits", { uns = expect("STRING").value })

            elseif kw("abstract") then
                advance()
                decls[#decls + 1] = node("abstract_decl", { value = expect("BOOL").value })

            elseif kw("field") then
                advance()
                local name
                if     cur_type() == "SYMBOL" then name = advance().value
                elseif cur_type() == "STRING" then name = advance().value
                else error(string.format("line %d: expected field name", cur().line)) end

                local opts = {}
                while at("COMMA") do
                    advance(); skip_newlines()
                    if cur_type() == "IDENT" and peek(1).type == "COLON" then
                        local k = advance().value
                        advance()  -- ':'
                        opts[k] = parse_expr()
                    end
                end
                decls[#decls + 1] = node("field_decl", { name = name, opts = opts })

            elseif kw("join") then
                advance()
                local fields = {}
                repeat
                    if     cur_type() == "SYMBOL" then fields[#fields + 1] = advance().value
                    elseif cur_type() == "STRING" then fields[#fields + 1] = advance().value end
                    if at("COMMA") then advance() end
                until cur_type() ~= "SYMBOL" and cur_type() ~= "STRING"
                decls[#decls + 1] = node("join_decl", { fields = fields })

            elseif kw("property") then
                advance()
                local name
                if     cur_type() == "SYMBOL" then name = advance().value
                elseif cur_type() == "STRING" then name = advance().value end
                decls[#decls + 1] = node("property_decl", { name = name })

            elseif kw("helper") then
                advance()
                local name
                if     cur_type() == "SYMBOL" then name = advance().value
                elseif cur_type() == "STRING" then name = advance().value end
                skip_newlines()
                local body = parse_class_body()
                expect("IDENT", "end")
                decls[#decls + 1] = node("helper_decl", { name = name, body = body })

            elseif kw("remote") and peek(1).type == "IDENT" and peek(1).value == "function" then
                advance(); advance()
                decls[#decls + 1] = parse_func_def(true)

            elseif kw("function") then
                advance()
                decls[#decls + 1] = parse_func_def(false)

            else
                advance()  -- skip unknown tokens inside class body
            end

            skip_newlines()
        end
        return decls
    end

    -- -------------------------------------------------------------------------
    -- Stop-set check: are we at a keyword that terminates the current block?
    -- -------------------------------------------------------------------------
    --[[ { "in": "stops: string[]?", "out": "bool", "note": "returns true at EOF or when current IDENT value is in stops; used by parse_stmts to know when to stop" } ]]
    local function is_stop(stops)
        if at("EOF") then return true end
        if stops and cur_type() == "IDENT" then
            local v = cur_val()
            for _, s in ipairs(stops) do
                if v == s then return true end
            end
        end
        return false
    end

    -- -------------------------------------------------------------------------
    -- Statement parser
    -- -------------------------------------------------------------------------
    --[[
    {
      "out": "AST node (a statement)",
      "dispatches_on": ["return", "yield", "function", "remote function", "class", "while", "if", "expression/assignment/catch/heed"],
      "assignment_rhs_special": ["catch(...) … end  → catch_stmt", "heed(...) … end  → heed_stmt", "expr do…end  → with_block"],
      "note": "expression statements may carry a trailing 'as $name' block binding or an explicit 'do' block"
    }
    ]]
    local function parse_stmt()
        skip_newlines()

        -- return
        if kw("return") then
            advance()
            local val
            if not at("NEWLINE") and not at("EOF") then val = parse_expr() end
            return node("return_stmt", { value = val })

        -- yield [expr]
        elseif kw("yield") then
            advance()
            local val
            if not at("NEWLINE") and not at("EOF") then val = parse_expr() end
            return node("yield_stmt", { value = val })

        -- function $name / function &name
        elseif kw("function") then
            advance()
            return parse_func_def(false)

        -- remote function &name
        elseif kw("remote") and peek(1).type == "IDENT" and peek(1).value == "function" then
            advance(); advance()
            return parse_func_def(true)

        -- class 'uns.name' ... end
        elseif kw("class") then
            advance()
            local uns = expect("STRING").value
            skip_newlines()
            local body = parse_class_body()
            expect("IDENT", "end")
            return node("class_def", { uns = uns, body = body })

        -- while (cond) ... end
        elseif kw("while") then
            advance()
            expect("LPAREN")
            local cond = parse_expr()
            expect("RPAREN")
            skip_newlines()
            local body = parse_stmts({ "end" })
            expect("IDENT", "end")
            return node("while_stmt", { cond = cond, body = body })

        -- if (cond) ... [elsif (cond) ...] [else ...] end
        elseif kw("if") then
            advance()
            expect("LPAREN")
            local cond = parse_expr()
            expect("RPAREN")
            skip_newlines()
            local then_body = parse_stmts({ "elsif", "else", "end" })

            local elsifs = {}
            while kw("elsif") do
                advance()
                expect("LPAREN")
                local ec = parse_expr()
                expect("RPAREN")
                skip_newlines()
                local eb = parse_stmts({ "elsif", "else", "end" })
                elsifs[#elsifs + 1] = { cond = ec, body = eb }
            end

            local else_body
            if kw("else") then
                advance(); skip_newlines()
                else_body = parse_stmts({ "end" })
            end

            expect("IDENT", "end")
            return node("if_stmt", {
                cond      = cond,
                then_body = then_body,
                elsifs    = elsifs,
                else_body = else_body,
            })

        else
            -- Expression, assignment, or catch
            local expr = parse_expr()

            -- Optional 'as $name' block naming
            local block_name
            if kw("as") then
                advance()
                if cur_type() == "VAR" then block_name = advance().value end
            end

            -- Trailing block: explicit do, or implicit body after 'as $name'
            if kw("do") then
                local blk = parse_do_block()
                blk.name = block_name
                return node("expr_stmt", { expr = expr, block = blk })
            elseif block_name then
                -- Implicit block: $col.each($x) as $loop \n body \n end
                skip_newlines()
                local body = parse_stmts({ "before", "between", "after", "noloop", "end" })
                local clauses = {}
                for _, clause in ipairs({ "before", "between", "after", "noloop" }) do
                    if kw(clause) then
                        advance(); skip_newlines()
                        local stops = { "end" }
                        local found = false
                        for _, c in ipairs({ "before", "between", "after", "noloop" }) do
                            if found then stops[#stops + 1] = c end
                            if c == clause then found = true end
                        end
                        clauses[clause] = parse_stmts(stops)
                    end
                end
                expect("IDENT", "end")
                local blk = node("block", {
                    name    = block_name,
                    params  = {},
                    body    = body,
                    before  = clauses.before,
                    between = clauses.between,
                    after   = clauses.after,
                    noloop  = clauses.noloop,
                })
                return node("expr_stmt", { expr = expr, block = blk })
            end

            -- Assignment  (including $e = catch(...) ... end)
            if at("ASSIGN") then
                advance()
                skip_newlines()   -- allow RHS to start on a new line

                if kw("catch") then
                    advance()
                    local classes = {}
                    if at("LPAREN") then
                        advance()
                        while not at("RPAREN") and not at("EOF") do
                            classes[#classes + 1] = parse_expr()
                            if at("COMMA") then advance() end
                        end
                        expect("RPAREN")
                    end
                    skip_newlines()
                    local body = parse_stmts({ "end" })
                    expect("IDENT", "end")
                    return node("catch_stmt", { target = expr, classes = classes, body = body })

                elseif kw("heed") then
                    advance()
                    local classes, kwargs = {}, {}
                    if at("LPAREN") then
                        advance()
                        while not at("RPAREN") and not at("EOF") do
                            if cur_type() == "IDENT" and peek(1).type == "COLON" then
                                local k = advance().value; advance()
                                kwargs[k] = parse_expr()
                            else
                                classes[#classes + 1] = parse_expr()
                            end
                            if at("COMMA") then advance() end
                        end
                        expect("RPAREN")
                    end
                    skip_newlines()
                    local body = parse_stmts({ "end" })
                    expect("IDENT", "end")
                    return node("heed_stmt", { target = expr, classes = classes, kwargs = kwargs, body = body })
                end

                local val = parse_expr()
                -- Trailing do on the rhs: $x = &foo do...end
                if kw("do") then
                    val = node("with_block", { expr = val, block = parse_do_block() })
                end
                return node("assign", { target = expr, value = val, block_name = block_name })
            end

            return node("expr_stmt", { expr = expr, block_name = block_name })
        end
    end

    -- -------------------------------------------------------------------------
    -- Statement sequence, stopping at any keyword in `stops`
    -- -------------------------------------------------------------------------
    --[[ { "in": "stops: string[]?", "out": "node[]", "note": "parses statements until is_stop(stops) is true; skips leading newlines before each statement" } ]]
    parse_stmts = function(stops)
        local stmts = {}
        skip_newlines()
        while not is_stop(stops) do
            stmts[#stmts + 1] = parse_stmt()
            skip_newlines()
        end
        return stmts
    end

    -- -------------------------------------------------------------------------
    -- Entry point
    -- -------------------------------------------------------------------------
    --[[ { "out": "program node  {kind:'program', stmts:[...]}", "note": "parses all statements then expects EOF; errors if tokens remain" } ]]
    function p:parse()
        local stmts = parse_stmts(nil)
        expect("EOF")
        return node("program", { stmts = stmts })
    end

    return p
end

--[[ { "in": "tokens: token[]", "out": "AST  {kind:'program', stmts:[...]}", "note": "public entry point; creates a parser and runs it" } ]]
function M.parse(tokens)
    return new_parser(tokens):parse()
end

return M
