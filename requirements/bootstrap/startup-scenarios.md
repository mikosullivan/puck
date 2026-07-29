# Startup scenarios
<!--index: 2 -->

~~~vibecode
{"vibecode": {
	"doc": "under_the_hood_startup_scenarios",
	"role": "worked end-to-end scenarios showing real hosts starting a Caspian engine. Each scenario walks through host code that loads the engine, configures it, runs a program, and reads the result. Owns the concrete examples; delegates the general lifecycle to initialization.md and the engine module mechanics to engine-creation.md.",
	"status": "active spec — first authored fresh in the new requirements/ tree; new scenarios may be added as new host environments come up",
	"audience": "anyone who needs to start a Caspian engine from a particular environment (shell command, Python program, JavaScript runtime); AI tooling reasoning about how Caspian fits into larger applications"
}}
~~~

Three worked examples of starting a Caspian engine — a shell-level CLI, a Python program, and a JavaScript program. Each shows the actual code a host would write, end to end, with notes on what's happening at each step.

For the general lifecycle and what "host" means, see [initialization.md](initialization.md) and [engine-creation.md](engine-creation.md).

## Scenario 1: CLI — `/usr/bin/caspian myprogram.casp`

The simplest host: a Lua launcher script invoked from the shell. The user has a Caspian source file and wants to run it.

### What the user types

~~~
$ /usr/bin/caspian myprogram.casp arg1 arg2
~~~

### What `/usr/bin/caspian` actually is

A Lua script. The Caspian distribution ships it (the reference impl is at `lib/lua/caspian/cli.lua`). A simplified, illustrative version (`lua5.4` is the current development target — see [engine-creation § Lua version](https://puck.uno/requirements/bootstrap/engine-creation#lua-version) for why no minimum has been committed to yet):

~~~lua
#!/usr/bin/env lua5.4
-- /usr/bin/caspian — runs a Caspian program from a file path.

local engine = require('caspian.engine')

-- arg[0] is the Lua interpreter; arg[1] is the .casp path; arg[2..] are program args.
local file_path = arg[1]

if not file_path then
    io.stderr:write('Usage: caspian <file.casp> [args...]\n')
    os.exit(2)
end

-- Load the program's source text from disk.
local f, err = io.open(file_path, 'r')

if not f then
    io.stderr:write('caspian: cannot open ' .. file_path .. ': ' .. err .. '\n')
    os.exit(2)
end

local source = f:read('*a')
f:close()

-- Configure the engine.
engine.caspianj = engine.parse_caspian(source)        -- transpile source → CaspianJ tree
engine.argv     = {table.unpack(arg, 2)}              -- pass through program args
engine.stdout   = function(s) io.write(s) end         -- real OS stdout
engine.stderr   = function(s) io.stderr:write(s) end  -- real OS stderr

-- Run the program. No meaningful return value in V1; observable output flows through
-- the wired stdout/stderr callbacks during the run itself.
local ok, err = pcall(engine.run)

if not ok then
    io.stderr:write('caspian: ' .. tostring(err) .. '\n')
    os.exit(1)
end

os.exit(0)
~~~

### What's happening

1. The shell finds `caspian` on the PATH (just a Lua script with a `#!` shebang). It hands it to `lua5.4` and passes the user's args as `arg[1]`, `arg[2]`, etc.
2. The script `require`s the engine module — gets back the engine table.
3. It reads the user's `.casp` file from disk into a string.
4. It calls `engine.parse_caspian(source)` to transpile the source into a CaspianJ tree, and stores that on `engine.caspianj`.
5. It wires the OS stdout and stderr functions onto `engine.stdout` and `engine.stderr`, so `puts` and friends write to the terminal.
6. It calls `engine.run()` inside `pcall` so any error gets caught and printed cleanly. V1 has no return value from `run()`; the CLI cares about stdout and exit codes, both of which are already handled through the wired callbacks and the pcall error path.
7. It exits with status 0 on success or 1 on engine error.

The reference CLI at `lib/lua/caspian/cli.lua` adds admin flags (`--version`, `--help`, cache management) and shebang handling so a `.casp` file can start with `#!/usr/bin/env caspian` and be directly executable. The core pattern is the same.

## Scenario 2: Python — embedding Caspian in a Python program

A Python application wants to evaluate Caspian code from inside its process — maybe for user-supplied scripting, maybe to share logic with other parts of the system that use Caspian. Python doesn't speak Lua natively; it needs a binding.

### The setup

Install [`lupa`](https://github.com/scoder/lupa), a Python ↔ Lua bridge:

~~~
pip install lupa
~~~

`lupa` exposes Lua tables as Python objects you can read and assign to.

### The Python code

~~~python
import lupa
import sys

# Spin up a Lua runtime inside this Python process.
lua = lupa.LuaRuntime(unpack_returned_tuples=True)

# Tell Lua where to find the Caspian modules on disk.
lua.execute("""
    package.path = './lib/lua/?.lua;./lib/lua/?/init.lua;' .. package.path
""")

# Load the engine module. After this, `engine` is a Python handle to the Lua table.
engine = lua.eval("require('caspian.engine')")

# Configure the engine.
# Parse Caspian source from a Python string:
source = "puts 'hello from python host'"
engine.caspianj = engine.parse_caspian(source)
engine.argv     = lua.table_from(['python-host', 'arg1'])
engine.stdout   = lambda s: sys.stdout.write(s)
engine.stderr   = lambda s: sys.stderr.write(s)

# Run it. V1 has no meaningful return value; observable output flows through the wired
# stdout/stderr lambdas during the run itself.
engine.run()
~~~

### What's happening

1. `lupa.LuaRuntime()` creates a Lua state inside the Python process. Multiple Lua states can coexist; each one is independent.
2. `lua.execute(...)` runs Lua code. The first call extends `package.path` so subsequent `require`s find the Caspian modules.
3. `lua.eval("require('caspian.engine')")` runs the require and returns the resulting Lua table as a Python object. From Python, `engine.caspianj = ...` IS a Lua property assignment under the hood.
4. `engine.parse_caspian(source)` calls the Lua function — `lupa` handles the marshaling of the Python string in and the Lua tree out. The tree is now stored on `engine.caspianj`.
5. `lua.table_from([...])` converts a Python list into a Lua-array-shaped table, since `engine.argv` expects a Lua array.
6. `engine.stdout = lambda s: ...` installs a Python function as the engine's stdout. When the engine eventually calls `engine.stdout(some_string)` from inside Lua, lupa marshals back into Python and runs the lambda.
7. `engine.run()` executes the program. Output flows through the lambdas to Python's `sys.stdout`. V1 has no return value from `run()` — programs that need to signal results back to the host use stdout, stderr, or a host-wired callback in the meantime.

### Notes specific to this scenario

- **Multiple engines in one Python process.** Each `LuaRuntime()` instance is independent, so a Python process can spin up several Lua states, each running its own Caspian engine, all in parallel. The engine module's singleton-within-a-Lua-state pattern doesn't propagate to Python — at the Python level, "an engine" is a `lua` runtime plus the engine table inside it.
- **Marshaling cost.** Each call from Python into Lua (and the Lua callback to Python for stdout) involves marshaling. Fine for occasional invocation; if you're calling Caspian thousands of times per second, batch on the Lua side instead.
- **Errors.** Lua errors propagate as Python `LuaError` exceptions. Wrap `engine.run()` in `try`/`except` to catch them.

## Scenario 3: JavaScript — embedding Caspian in a JavaScript program

A JavaScript program (browser or Node.js) wants to run Caspian. JavaScript doesn't speak Lua either, so it needs a Lua runtime that runs in JS. [`wasmoon`](https://github.com/ceifa/wasmoon) is the cleanest option — a WebAssembly build of Lua 5.4 with first-class JS value marshaling.

### The setup

~~~
npm install wasmoon
~~~

### The JavaScript code

~~~javascript
import { LuaFactory } from 'wasmoon';
import * as fs from 'node:fs/promises';

// Create a Lua VM (runs as WebAssembly).
const factory = new LuaFactory();

// Mount the Caspian Lua files into the VM's virtual filesystem.
// (Each .lua file the engine requires needs to be readable from inside the VM.)
for (const name of ['engine', 'lexer', 'parser', 'transpiler', 'json']) {
    const src = await fs.readFile(`./lib/lua/caspian/${name}.lua`, 'utf-8');
    await factory.mountFile(`/lib/lua/caspian/${name}.lua`, src);
}

const lua = await factory.createEngine();

// Tell Lua where to find the Caspian modules in the mounted virtual filesystem.
await lua.doString(`
    package.path = '/lib/lua/?.lua;/lib/lua/?/init.lua;' .. package.path
`);

// Load the engine module. After this, JS holds a reference to the Lua engine table.
await lua.doString(`engine = require('caspian.engine')`);
const engine = lua.global.get('engine');

// Configure the engine.
const source = "puts 'hello from javascript host'";
engine.caspianj = engine.parse_caspian(source);
engine.argv     = ['js-host', 'arg1'];

// Install a JS callback as engine.stdout. wasmoon marshals the call from Lua.
lua.global.set('engine_stdout', (s) => process.stdout.write(s));
await lua.doString(`engine.stdout = engine_stdout`);

// Run it.
const result = engine.run();

// `result` is a JS object representing a Caspian value (type / payload / owning_role).
console.log('program returned:', result?.payload ?? null);

// Always close the engine when done — wasmoon needs explicit cleanup.
lua.global.close();
~~~

### What's happening

1. `LuaFactory()` produces a factory for creating Lua VMs. Each VM is independent.
2. The Caspian modules live on disk as `.lua` files; wasmoon's VM is a WebAssembly sandbox that can't read the host filesystem directly. The host pre-mounts the files into the VM's virtual filesystem so `require` can find them.
3. `factory.createEngine()` instantiates the VM with stdlib loaded. The VM is now ready to run Lua code.
4. `lua.doString(...)` runs Lua code inside the VM. The first call extends `package.path` to include the mount point; the second loads the engine module and assigns it to a Lua global.
5. `lua.global.get('engine')` returns a JS proxy that lets you read and assign properties on the Lua engine table. From JS, `engine.caspianj = ...` IS a Lua property assignment, mediated by wasmoon.
6. The `parse_caspian` call goes JS → Lua, runs, and the result is returned as a JS-friendly representation of the Lua tree. wasmoon does the marshaling automatically.
7. The stdout callback is a JS function. wasmoon registers it as a Lua global, and the subsequent `engine.stdout = engine_stdout` makes it the engine's output sink. When the program calls `puts`, the callback fires in JS.
8. `engine.run()` executes. V1 has no meaningful return value from `run()`; observable output flows through the stdout callback during the run itself.
9. `lua.global.close()` releases the WebAssembly memory. Skipping this leaks the VM.

### Notes specific to this scenario

- **Browser vs Node.js.** The pattern works in both. In a browser, mount the `.lua` files using `fetch` instead of `fs`. Everything else stays the same.
- **First load is slow.** wasmoon downloads and instantiates a WebAssembly build of Lua; expect a one-time cost on first use. After that, calls into the VM are fast.
- **Each `createEngine()` is independent.** A JS program can run multiple Caspian engines side by side, each in its own VM.
- **Async wrapping.** wasmoon's `doString` is async (returns a promise) because the WASM-bridge crossings are async. Awaiting around individual calls is the norm.

## Errors

If the engine encounters an uncaught error during the run (a method-not-found, a type mismatch, a manual `raise`), `engine.run()` doesn't complete — it raises in the host's language (Lua error, Python `LuaError`, JS thrown error). The host catches it separately from the "run completed" path.

Observable output has already flowed through the wired stdout / stderr callbacks by the time an error is raised or a run completes; there is nothing else the host consumes from the call.

## What stays the same across all three

Despite the wildly different host languages, every scenario follows the same shape:

1. Get the Caspian engine module loaded (require / lua.eval / lua.doString — all equivalent).
2. Stage the program tree on `engine.caspianj` (either by calling `engine.parse_caspian(source)` or by writing a CaspianJ tree directly).
3. Set capabilities on engine properties — `engine.argv`, `engine.stdout`, `engine.stderr`, etc.
4. Call `engine.run()`.
5. Handle any raised error; ignore the return value (V1 has none).

The hosts differ in:

- Which language they're written in.
- How they communicate with Lua (direct, lupa, wasmoon, etc.).
- How they marshal values across the language boundary.
- What kind of stdout they wire up (terminal, captured buffer, Python file object, JS callback).
- How they handle errors.

But the **engine surface they touch is identical**: same property names, same method names. That's the contract the engine guarantees. Any host that conforms to it can start a Caspian engine and run programs through it.

## Testing

- **CLI: missing file argument** — `caspian` invoked with no path writes a usage message to stderr and exits with status 2.
- **CLI: unreadable file** — `caspian /nonexistent.casp` writes "cannot open" to stderr and exits with status 2.
- **CLI: successful run** — `caspian program.casp` reads the file, parses, runs, and exits 0.
- **CLI: passes program args as argv** — `caspian program.casp a b c` makes `a`, `b`, `c` visible via `%engine.argv`; the `.casp` path itself is NOT included.
- **CLI: engine error caught** — an uncaught error during `engine.run()` is caught by `pcall`, printed to stderr, and the process exits with status 1.
- **CLI: `puts` reaches the real terminal** — a program's `puts 'hi'` produces `hi\n` on the launcher's stdout.
- **CLI: stderr routing** — output through `engine.stderr` reaches the launcher's stderr, not stdout.
- **CLI: shebang execution** — a `.casp` file starting with `#!/usr/bin/env caspian` and marked executable runs when invoked directly.
- **CLI: admin flags** — `--version` and `--help` invoke the reference CLI's admin paths without executing a program.
- **Python: engine module reachable via lupa** — after extending `package.path`, `lua.eval("require('caspian.engine')")` returns a handle usable from Python.
- **Python: `parse_caspian` accepts a Python string** — passing a Python `str` returns a CaspianJ tree usable as `engine.caspianj`.
- **Python: `engine.argv` via `lua.table_from`** — a Python list arrives as a Lua-array-shaped table the engine reads correctly.
- **Python: stdout callback fires** — a Python lambda installed on `engine.stdout` receives each write from `puts` as a Python string.
- **Python: multiple engines in one process** — two separate `LuaRuntime()` instances hold independent engine states; changes in one do not affect the other.
- **Python: engine errors as `LuaError`** — an uncaught error propagates as a Python `LuaError` exception raised out of `engine.run()`.
- **Python: multiple invocations reuse the engine** — a single `LuaRuntime` can call `engine.run()` repeatedly with new fixtures.
- **JS: engine module loads via mounted VFS** — after `factory.mountFile` for each `caspian/*.lua`, `require('caspian.engine')` inside the VM resolves.
- **JS: `parse_caspian` accepts a JS string** — passing a JS string returns a CaspianJ representation usable as `engine.caspianj`.
- **JS: JS array assigns as argv** — a JS `['js-host', 'arg1']` assigned to `engine.argv` is visible via `%engine.argv`.
- **JS: stdout callback fires** — a JS function set via `lua.global.set(...)` then bound to `engine.stdout` receives each write from `puts`.
- **JS: `lua.global.close()` releases WASM memory** — omitting `close()` leaks the VM; calling it releases it.
- **JS: multiple VMs in parallel** — two `factory.createEngine()` VMs run independent programs concurrently.
- **JS: async wrapping** — `doString` returns a promise; awaiting it works within JS's async model.
- **JS: browser vs Node.js** — the same code path works in either; mounting via `fetch` in the browser and `fs` in Node.js produces identical engine behavior.
- **`engine.run()` has no meaningful return value in V1** — hosts do not consume a value from `run()`; observable output flows through the stdout/stderr callbacks during the run.
- **Exit code is host-decided** — the engine has no exit-code concept; the CLI translates outcomes to `exit(0)` / `exit(1)`.
- **Cross-host surface identity** — CLI, Python, and JS scenarios touch identical property/method names (`caspianj`, `argv`, `stdout`, `stderr`, `parse_caspian`, `run`).

## Related

- [initialization.md](initialization.md) — the conceptual host-engine lifecycle.
- [engine-creation.md](engine-creation.md) — what the engine module actually IS at the Lua level, and why there's no constructor.
