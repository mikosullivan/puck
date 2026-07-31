# Bootstrap

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap",
	"role": "canonical spec for how the Caspian engine boots — the sequence from host process startup to the first user statement executing. Owns the host-engine boundary, the surface the host wires against, and what runtime state is guaranteed to exist before user code runs. Ground-up rewrite in progress; the prior version is archived under archive/003/misc/bootstrap-old/.",
	"status": "in progress — initialization (load / wire / stage) drafted; execution (`engine.run()`, bootstrap(), first dispatch) and subsequent runtime state not yet covered"
}}
~~~

## Initializing the engine

Before any Caspian code runs, a host program has to get the engine loaded into memory, hand it the capabilities it needs (stdout, filesystem, network, etc.), and give it the program to execute. The minimal shape:

~~~lua
local engine = require('engine')                  -- load
engine.stdout = function(s) io.write(s) end       -- wire capabilities
engine.caspianj = engine.parse_caspian(source)    -- stage the program
-- engine.run() comes later; that's execution, spec'd separately.
~~~

Three steps, taken in order.

### Load — `require('engine')`

Lua's `require` reads the engine module file (`src/engine/engine.lua`) into the Lua VM, executes it top-to-bottom, and returns whatever the module returned. By convention `engine.lua` ends with `return M` where `M` is a Lua table full of methods and empty property slots. **That table IS the engine.**

Two things worth internalizing:

- **There is no constructor.** No `Engine.new()`, no allocation step. The moment `require` returns, the engine is a fully-formed table ready to use.
- **Lua caches modules.** A second `require('engine')` in the same process returns the same table — same instance, same properties, same runtime state. A CLI that runs one program and exits doesn't care about this; a long-lived host (test runner, embedded evaluator) that runs multiple programs in one process must know that engine state carries forward unless explicitly reset.

### Wire capabilities — property assignment

The engine table has empty slots for the host to fill:

~~~lua
engine.stdout = function(s) io.write(s) end
engine.stderr = function(s) io.stderr:write(s) end
engine.stdin  = function() return io.read('*l') end
engine.argv   = {'first-arg', 'second-arg'}
-- ...more as the surface grows: engine.fs, engine.net, engine.env, engine.forks, ...
~~~

Each slot is a plain Lua table key. There is no setter ceremony, no event firing, no validation at write time. Assignment order does not matter. If a slot is left unset, the corresponding capability is **withheld** — user code that tries to reach for it raises when it does.

The host is the OS-aware layer. It knows how to reach real files and real sockets. It hands the engine those OS handles wrapped as Lua functions (or as tables of Lua functions, for compound capabilities like `%fs`). The engine holds them opaquely — it never looks at `io.write` directly.

### Stage the program — `engine.caspianj = ...`

The engine needs the program it will execute. Two paths land in the same slot:

- **From source text** — `engine.caspianj = engine.parse_caspian('puts hi\n$x = 42\n...')`. The engine's parser produces a CaspianJ tree from Caspian source.
- **From a pre-built tree** — `engine.caspianj = my_hand_authored_tree`. This is the shape a test harness typically uses; it skips the parser entirely.

Everything after the tree lands in `engine.caspianj` is execution, which this section deliberately doesn't cover.

## The CLI as a host

The CLI (`src/engine/cli.lua`, not yet written) is a Lua host like any other, but wraps the three initialization steps above with the plumbing a command-line tool needs:

- **Parses `argv` itself first** — figures out which source file to load, which flags to interpret. The CLI receives argv from Lua's global `arg` table.
- **Reads the source file** — `io.open(path):read('*a')`.
- **Wires real OS streams** — `engine.stdout = function(s) io.write(s) end` is the canonical shape; nothing fancier.
- **Passes through remaining argv** — anything after the source-file argument becomes the program's own argv (`engine.argv = ...`).
- **Handles errors** — wraps `engine.run()` in `pcall`, decides the process exit code.

Everything above the load/wire/stage/run pattern is CLI plumbing (arg parsing, file reading, exit-code policy), not engine initialization. Substitute a different host — a test runner, a Ruby-embedded host, a serverless function — and the initialization sequence is identical; only the plumbing around it changes.
