--[[
{
  "module": "caspian.cli",
  "role":   "CLI launcher entry point invoked by bin/caspian. Dispatches by first-argument shape: an argument starting with '--' is an admin flag (handled in-launcher); anything else is a path to a .casp file (the file form, runs the program). Program output (puts) goes to stdout; engine errors and uncaught exceptions go to stderr.",
  "two_form_invocation": "caspian <file.casp> [args...] runs the program. caspian --<flag> [...] runs an admin action; see documentation/requirements/caspian/cli.md for the canonical spec.",
  "admin_flags": "--update-cache, --clear-cache (with -y/--yes bypass for the confirmation prompt), --version, --help. Stubs for cache flags emit 'not yet implemented' because the cache subsystem itself lands with the Gabbo slice; the dispatch and exit-code shape are correct so they wire up cleanly when the cache exists.",
  "shebang_handling": "If the file's first two bytes are '#!', the entire first line is stripped before parsing so #!/usr/bin/env caspian shebangs don't reach the Caspian parser. Applies only in file form.",
  "argv": "Lua's `arg` table: arg[0] is the lua executable, arg[1] is the .casp file path (or --flag), arg[2..N] are the program's arguments / admin-flag modifiers. In file form, arg[2..N] are installed on engine.argv before run.",
  "exit_codes": "0 on clean completion (file form or info flag like --version/--help/--update-cache stub completes). 1 on engine errors and on cache-flag stubs (since the operation didn't really run). 2 on usage errors (unknown flag, missing file argument, etc.). 130 on user-cancelled prompt (--clear-cache 'n' response)."
}
]]

local engine = require("caspian.engine")

local CASPIAN_VERSION = "0.0.1-pre"  -- pre-release; updates with each slice ship

local function err(msg)
    io.stderr:write("caspian: " .. tostring(msg) .. "\n")
end

local function die(msg, code)
    err(msg)
    os.exit(code or 1)
end

----------------------------------------------------------------
-- Admin flag handlers
--
-- Each returns an exit code (0 = clean, nonzero = problem). The
-- launcher exits with whatever the handler returns.
----------------------------------------------------------------

local function print_version()
    io.stdout:write("caspian " .. CASPIAN_VERSION .. "\n")
    return 0
end

local function print_help()
    io.stdout:write(table.concat({
        "Usage:",
        "  caspian <file.casp> [args...]   Run a Caspian program.",
        "  caspian --<flag> [args...]      Run an admin action.",
        "",
        "Admin flags:",
        "  --update-cache       Refresh every cached library to its latest version.",
        "  --clear-cache        Wipe the cache (prompts for confirmation).",
        "  --version            Print the Caspian version.",
        "  --help               Print this message.",
        "",
        "Confirmation bypass:",
        "  --yes, -y            Skip confirmation prompts (for destructive actions).",
        "",
        "See https://puck.uno/documentation/requirements/caspian/cli for the full spec.",
        "",
    }, "\n"))
    return 0
end

-- Scan modifier flags from the arg tail. Returns recognized options as a table.
local function parse_modifiers(args)
    local opts = { yes = false }
    for _, a in ipairs(args) do
        if a == "--yes" or a == "-y" then
            opts.yes = true
        end
    end
    return opts
end

local function handle_update_cache(_args)
    -- Stub: cache subsystem ships with the Gabbo slice. The dispatch shape
    -- is correct; the actual fetch loop wires in when the cache exists.
    err("--update-cache is not yet implemented (cache subsystem planned for the Gabbo slice).")
    return 1
end

local function handle_clear_cache(args)
    -- Stub for the same reason. The confirmation flow is correct so the UX
    -- is established now; only the actual cache-removal step is missing.
    local opts = parse_modifiers(args)
    if not opts.yes then
        io.stdout:write("Continue? [y/N]: ")
        io.stdout:flush()
        local line = io.stdin:read("*l")
        if not line then
            err("(no tty; pass --yes / -y to skip the prompt)")
            return 130
        end
        line = line:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "y" and line ~= "yes" then
            io.stdout:write("Cancelled.\n")
            return 130
        end
    end
    err("--clear-cache is not yet implemented (cache subsystem planned for the Gabbo slice).")
    return 1
end

local ADMIN_HANDLERS = {
    ["--update-cache"] = handle_update_cache,
    ["--clear-cache"]  = handle_clear_cache,
    ["--version"]      = function(_args) return print_version() end,
    ["--help"]         = function(_args) return print_help() end,
}

----------------------------------------------------------------
-- File-form runner (the original cli.lua behavior, unchanged)
----------------------------------------------------------------

local function run_file_form(source_file, program_args)
    local f, open_err = io.open(source_file, "r")
    if not f then
        die("cannot open " .. source_file .. ": " .. tostring(open_err))
    end
    local source = f:read("*a")
    f:close()

    -- Strip an optional shebang line so it doesn't reach the parser.
    if source:sub(1, 2) == "#!" then
        source = source:gsub("^[^\n]*\n", "", 1)
    end

    -- Install host capabilities BEFORE engine.run is called.
    engine.std = function(s) io.stdout:write(s) end
    engine.err = function(s) io.stderr:write(s) end
    engine.argv = program_args

    local parse_ok, tree_or_err = pcall(engine.parse_caspian, source)
    if not parse_ok then
        die(tostring(tree_or_err))
    end
    engine.caspianj = tree_or_err

    local run_ok, run_err = pcall(engine.run)
    if not run_ok then
        die(tostring(run_err))
    end

    return 0
end

----------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------

local first = arg[1]
if not first then
    die("missing argument; usage: caspian <file.casp> [args...]  (or --help)", 2)
end

if first:sub(1, 2) == "--" or first == "-y" then
    -- Admin flag form. -y/--yes alone isn't a primary action; let the user know.
    if first == "-y" or first == "--yes" then
        die("'" .. first .. "' is a modifier, not a command. See --help.", 2)
    end
    local handler = ADMIN_HANDLERS[first]
    if not handler then
        die("unknown flag '" .. first .. "'. See --help.", 2)
    end
    local modifier_args = {}
    for i = 2, #arg do modifier_args[#modifier_args + 1] = arg[i] end
    os.exit(handler(modifier_args))
end

-- File form: arg[1] is the source path; arg[2..N] are the program's argv.
local program_args = {}
for i = 2, #arg do program_args[#program_args + 1] = arg[i] end
os.exit(run_file_form(first, program_args))
