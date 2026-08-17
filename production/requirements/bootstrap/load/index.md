# Load — `require('engine')`

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_load",
	"role": "canonical spec for the Load step in Caspian's bootstrap sequence — how the host loads the engine module and gets back the engine table. Covers the no-constructor rule, Lua's module caching, and what the returned table is.",
	"status": "V1 spec"
}}
~~~

The second step in the bootstrap sequence. Lua's `require` reads the engine module file ([src/engine/engine.lua](../../../src/engine/engine.lua)) into the Lua VM, executes it top-to-bottom, and returns whatever the module returned. By convention `engine.lua` ends with `return M` where `M` is a Lua table full of methods and empty property slots. **That table IS the engine.**

~~~lua
local engine = require('engine')
~~~

## Two things worth internalizing

**There is no constructor.** No `Engine.new()`, no allocation step. The moment `require` returns, the engine is a fully-formed table ready to use. Fields the host will populate (stdout, stderr, stdin, argv) exist as `nil` slots ready for assignment; methods (`load`, `run`, dispatch helpers) are present and callable.

**Lua caches modules.** A second `require('engine')` in the same process returns the same table — same instance, same properties, same runtime state. A CLI that runs one program and exits doesn't care about this; a long-lived host (test runner, embedded evaluator) that runs multiple programs in one process must know that engine state carries forward unless explicitly reset.

## What comes next

Once `require` returns, the host moves to [Wire capabilities](https://www.puck.uno/requirements/bootstrap/wire/) to fill the empty slots.
