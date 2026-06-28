# Creating the engine

<!--index: 01-->

~~~vibecode
{"vibecode": {
	"doc": "under_the_hood_engine_creation",
	"role": "canonical spec for what the Caspian 'engine' actually IS at the Lua level — how it comes into existence, how a host loads it, how the host installs properties on it, and what that looks like across different host scenarios (test harness, CLI runner, embedded inside Ruby/Python). Owns the Lua-mechanical view of engine creation and configuration; delegates the conceptual host-engine model to initialization.md and per-property semantics to the engine-slots doc.",
	"status": "active spec — first authored fresh in the new requirements/ tree",
	"audience": "anyone writing a host that loads Caspian (Lua scripts, CLI runners, Ruby/Python embeddings); AI tooling reasoning about engine startup at the Lua layer"
}}
~~~

[initialization.md](initialization.md) covers the conceptual lifecycle — host process startup → first user statement. This doc covers the Lua-mechanical reality underneath: what the "engine" actually is when you look at the code, and how a host turns it from "module on disk" into "configured runtime ready to execute."

## What is a host?

A **host** is the surrounding program that loads and runs the Caspian engine. The engine isn't a standalone process; it can't run by itself. Something else has to be in charge of:

- Starting (or running inside) the Lua VM.
- Loading the engine module.
- Deciding what Caspian program to execute.
- Wiring up capabilities (stdout, files, network, whatever the program needs).
- Calling `engine.run()`.
- Doing something with the result.

That "something else" is the host. The engine itself doesn't know or care which kind of host is driving — it just sees its properties get set and its methods get called.

### Examples of hosts

Real and plausible scenarios:

- **A test runner.** A Lua script (e.g. `tests/caspian/run.lua`) that loads the engine, feeds it a fixture, asserts the result. The test script is the host.
- **The `caspian` CLI.** A Lua script (`lib/lua/caspian/cli.lua`) invoked by `caspian myprogram.casp`. It reads the file, transpiles it, runs it, sends output to the terminal. The CLI script is the host.
- **A REPL.** A Lua script that loops: read a line from the user → run it through the engine → print the result → repeat. The REPL loop is the host.
- **An IDE plugin.** A VS Code extension (in Node.js, say) loads Caspian through a Lua binding to evaluate snippets for autocompletion or linting. The extension process is the host.
- **A web app embedding Caspian.** A Ruby on Rails application that lets users write small Caspian expressions for some scripting feature. Each web request that needs to evaluate user-supplied Caspian becomes a host invocation. The Rails worker is the host.
- **A serverless function.** An AWS Lambda that runs Caspian for an event handler. The Lambda invocation environment is the host.
- **A long-running daemon.** A background service that pre-loads the engine once at startup, then handles incoming requests by configuring and running the engine for each. The daemon process is the host.

All of these do the same job: load → configure → run. They differ in *who* they're being driven by (a developer at a terminal, an HTTP request, a scheduled timer, an editor keystroke) and *what they expose* (stdout to a console, stdout to a captured buffer, no stdout at all, etc.). The host is whatever program turns those outside drivers into the load/configure/run pattern the engine understands.

### What a host is NOT

A few sources of confusion worth heading off:

- **The OS isn't the host.** The OS runs processes; one of those processes happens to be the host. The host is the program, not the machine.
- **Lua isn't the host.** Lua is the *language* the engine is written in. Lua provides the VM the engine runs inside. But the host is the program loading the engine — that program is itself usually written in Lua (or wraps a Lua binding), but "host" describes its role, not its language.
- **The Caspian engine isn't the host.** The engine is what gets loaded; the host loads it. The engine can't load itself.

If you can answer "who decided to call `engine.run()`?" — that's the host.

## The engine is just a Lua module

Caspian's engine isn't a class or a constructor. It's a **Lua module** at `lib/lua/caspian/engine.lua`. Like every Lua module, it follows the standard pattern:

~~~lua
-- lib/lua/caspian/engine.lua (sketch)

local lexer      = require("caspian.lexer")
local parser     = require("caspian.parser")
local transpiler = require("caspian.transpiler")

local M = {}

function M.parse_caspian(source) ... end
function M.bootstrap()           ... end
function M.run()                 ... end
function M.dispatch(statement)   ... end
-- ... more methods ...

return M
~~~

When a host does `require('caspian.engine')`, Lua reads the file, executes it once, and returns the `M` table. That table **is** the engine.

After `require` returns, here's what the host has in its hands:

- A table with methods on it (`engine.run`, `engine.parse_caspian`, `engine.dispatch`, etc.).
- An empty slot ready to receive the program tree (the host writes `engine.caspianj = <tree>` later).
- Empty slots ready to receive capability values (`engine.argv`, `engine.stdout`, etc.).
- A few internal-use tables that get initialized by `engine.bootstrap()` later (`engine.state`, `engine.classes`).

There is no `new()` call. There is no constructor pattern. The module IS the engine.

## How the host populates it

Because the engine is a Lua table, configuring it is just property assignment:

~~~lua
local engine = require('caspian.engine')

engine.caspianj = my_tree           -- the program to run
engine.argv     = {'arg1', 'arg2'}  -- argv to expose
engine.stdout   = function(s)       -- where puts writes
    io.write(s)
end
~~~

The engine reads these properties when it needs them. There's no setter ceremony, no event firing, no validation at write time — it's just a table key being assigned. Validation (if any) happens when the engine reads the value, not when the host writes it.

This is deliberately minimal. Anything that can write to a Lua table can configure the engine: a hand-written Lua script, a generated config, a higher-level host wrapping Lua.

## The lifecycle

From the host's perspective, the engine's lifecycle has three phases:

1. **Load.** `require('caspian.engine')` returns the engine table. Happens once per Lua process; subsequent `require` calls return the same cached table.
2. **Configure.** Host assigns the properties it wants the engine to see. Order doesn't matter; the host can interleave configuration and other work freely until it's ready to run.
3. **Run.** Host calls `engine.run()`. The engine reads its properties, initializes its runtime state inside `bootstrap()`, walks the program tree, and returns the last statement's value to the host.

After `engine.run()` returns, the host can:

- Reconfigure (assign new property values) and run again. The engine's `bootstrap()` resets its runtime state on each `run()` call — fresh roles registry, empty call stack — so successive runs don't carry state forward unless the host explicitly preserved something.
- Walk away. Lua eventually collects the module when the host process exits.

The reset-on-every-run behavior means tests can call `engine.run()` repeatedly against different fixtures without cross-contamination. It also means a CLI runner that's meant to execute one program and exit doesn't need to think about state cleanup — it gets a fresh runtime for free.

## Different host scenarios

The same loading pattern works regardless of who's driving:

### Test harness (Lua-native)

A test file under `tests/caspian/` does the loading itself:

~~~lua
package.path = './lib/lua/?.lua;./lib/lua/?/init.lua;' .. package.path
local engine = require('caspian.engine')

engine.caspianj = {{{value = "hello"}, "to_string"}}
local result = engine.run()
-- assert result.payload == "hello"
~~~

The "host" is the test runner. It loads the engine, stages a fixture, runs, asserts. Same module, same lifecycle, no special test-mode flag.

### CLI runner

The CLI runner at `lib/lua/caspian/cli.lua` is the host when the user types `caspian myprogram.casp`:

~~~lua
local engine = require('caspian.engine')

local source = read_file(arg[1])
engine.caspianj = engine.parse_caspian(source)
engine.argv     = {table.unpack(arg, 2)}
engine.stdout   = function(s) io.write(s) end

engine.run()
~~~

Same pattern, plus a parse step (CLI starts from Caspian source, not pre-made CaspianJ) and OS-stream wiring.

### Embedded inside another host language

A Ruby host loads the Lua VM, then loads the engine inside it. From Ruby:

~~~ruby
lua = Lua::State.new
lua.execute "engine = require('caspian.engine')"

lua.execute "engine.caspianj = #{tree_as_lua_literal}"
lua.set "engine_stdout_callback", -> (s) { $stdout.write(s) }
lua.execute "engine.stdout = engine_stdout_callback"

lua.execute "return engine.run()"
~~~

The marshaling between Ruby and Lua is the host's concern. The engine doesn't know which language is calling it; from inside, it just sees a Lua table with Lua functions and values. The host could equally well be Python (via lupa, etc.), Rust (via mlua), or any other language with a Lua binding.

What stays constant across all hosts: the contract is `engine.caspianj`, `engine.argv`, `engine.stdout`, etc., as Lua-table properties, plus the `engine.run()` method. Conform to that surface and you can bootstrap.

## Why there's only one engine per process today

Because `require` caches its results, the engine module is effectively a singleton. Calling `require('caspian.engine')` from two different places in the same Lua process returns the same table. Reading `engine.caspianj` from one place sees what the other place wrote.

This is fine for today's use cases (one host, one program, one engine). It would be a problem for a process that wanted to run two independent Caspian programs side by side — they'd share the engine module's state and step on each other.

If multi-engine support becomes needed, the engine module would have to add a constructor:

~~~lua
local engine_a = caspian.engine.new()   -- hypothetical
local engine_b = caspian.engine.new()
engine_a.caspianj = ...
engine_b.caspianj = ...
~~~

The reference impl doesn't have this. When it's needed, the module would refactor so the table-with-methods pattern stays, but each `new()` produces a fresh table with its own state.

## Why "no constructor" matters

In OOP languages, a **constructor** is the special function you call to create a fresh instance of a class. The typical pattern looks like:

~~~python
# Python — typical constructor-based design
class Engine:
    def __init__(self, config):
        self.config = config
        self.state = {}

    def run(self):
        ...

engine = Engine(config=my_config)   # ← this is the constructor call
engine.run()
~~~

You can't use the engine until you've called `Engine(...)` to construct an instance. The constructor is mandatory; it's how you get from "the class definition" to "a thing you can call methods on."

**Caspian's engine doesn't work that way.** There's no `Engine.new()` step. The Lua module — the thing `require('caspian.engine')` hands back — is itself the engine. You start using it immediately, by setting properties on it and calling its methods:

~~~lua
-- Caspian — no constructor; the module IS the engine
local engine = require('caspian.engine')

engine.caspianj = my_tree    -- configure by writing to the module
engine.run()                 -- call methods on the module
~~~

There is no separate "instantiate" step. The module loads once; from that moment on, it's a ready-to-configure engine. Configuration is property assignment; running is a method call.

### Why this pattern over a constructor

The minimal load → configure → run pattern is chosen over an OOP-flavored engine class for a few reasons:

- **It's the smallest thing that works.** A host needs to call functions and set values. A constructor adds a step without adding capability.
- **Configuration is whatever you write, in whatever order.** No required parameters at construction time; no two-phase "build then configure" mismatch.
- **Mocking and substitution are trivial.** Tests replace properties; sandboxes withhold them. There's no ceremony around overriding an instance method or stubbing a constructor.
- **Lua makes tables-with-functions look exactly like objects-with-methods anyway.** Adding a `new()` would buy nothing on the calling side; just one more layer of indirection.

The shape we ship is essentially the same as a constructor-based design, minus the constructor.

## What's in `lib/lua/caspian/`

For grounding, the reference implementation's full Lua module inventory:

| Module | Role |
|---|---|
| `engine.lua` | the engine module itself (this doc's subject) |
| `lexer.lua` | Caspian source text → token stream |
| `parser.lua` | token stream → AST |
| `transpiler.lua` | AST → CaspianJ tree (the engine's input format) |
| `json.lua` | JSON encode/decode used by CaspianJ persistence and serialization |
| `interpreter.lua` | older pre-engine interpreter; being phased out |
| `cli.lua` | CLI runner — the host that invokes the engine for `caspian <file>` |
| `init.lua` | barrel module re-exporting lexer/parser/transpiler/etc. for `require('caspian')` convenience |

A host typically only needs `caspian.engine` and (if it's parsing Caspian source rather than feeding pre-made CaspianJ) implicitly the lexer/parser/transpiler via `engine.parse_caspian()`. The other modules are internal plumbing.

## Related

- [initialization.md](initialization.md) — the conceptual host-engine lifecycle (what bootstrap means, the five-step sequence, what state exists after bootstrap).
- The engine-slots doc (owns the per-property semantics: what `engine.stdout` expects, what `engine.argv` looks like, etc.) — not yet migrated to the new tree.
- The dispatch doc (owns what `engine.run()` does once it starts walking statements) — not yet migrated.
