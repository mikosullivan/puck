# Wire capabilities

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_wire",
	"role": "canonical spec for the Wire step in Caspian's bootstrap sequence — how the host attaches capabilities (stdout, stderr, stdin, argv, etc.) to the engine before user code runs. Covers slot shapes, the withheld-capability model, and why assignment is plain-Lua rather than method-based.",
	"status": "V1 spec"
}}
~~~

The third step in the bootstrap sequence. The engine table has empty slots for the host to fill:

~~~lua
engine.stdout = { print = function(self, s) io.write(s)        end }
engine.stderr = { print = function(self, s) io.stderr:write(s) end }
engine.stdin  = function() return io.read('*l') end
engine.argv   = {'first-arg', 'second-arg'}
-- ...more as the surface grows: engine.fs, engine.net, engine.env, engine.forks, ...
~~~

## The rules

**Each slot is a plain Lua table key.** No setter ceremony, no event firing, no validation at write time. Assignment order does not matter.

**Slots left unset are withheld capabilities.** User code that tries to reach for a withheld capability raises when it does — no silent default, no fallback stdout, nothing. That's what makes the wire step matter: what you wire is what the program can reach; what you don't wire is a raise-on-touch.

## Slot shapes vary

- **`stdin`** — a plain callable. The engine invokes it to read a line.
- **`stdout` / `stderr`** — compound capabilities. Lua tables with method fields, invoked as `stdout:print(bytes)`. The Caspian-side sink surface (`.puts`, `.print`, jails, attribution, etc.) layers inside the engine on top of the host's `:print`.
- **`argv`** — a plain Lua array of strings.
- **Compound capabilities like `%fs`** — follow the same table-of-methods pattern as stdout: a Lua table whose method fields the engine invokes.

The engine holds every wired value opaquely — it never looks at `io.write` directly.

## What comes next

Once capabilities are wired (or intentionally left unset), the host moves to [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/) to bring up the runtime state store.
