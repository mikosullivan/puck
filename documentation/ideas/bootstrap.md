# Bootstrapping the Charlie Interpreter

~~~json
{"vibecode": {
	"doc": "bootstrap",
	"role": "design notes for how a host language (Ruby as the worked example) integrates with and bootstraps the Charlie runtime through an embedded Lua VM; layered host/Lua/Charlie policy model",
	"key_concepts": ["host_layer", "embedded_lua_vm", "downward_visibility_only",
		"ruby_api_sketch", "policy_enforcement"],
	"status": "brainstorm"
}}
~~~

Notes on how a host language (Ruby used as the example) integrates with and bootstraps
the Charlie runtime.

---

<a id="architecture"></a>
## Architecture

```
Ruby (host / policy layer)
    ↓
Lua C library (embedded VM)
    ↓
Charlie runtime (written in Lua)
```

Ruby owns the process and enforces policy. Lua runs the Charlie engine. Charlie runs
the program (which may include untrusted code). Each layer can only see downward — Charlie
cannot reach into Lua internals, and Lua cannot reach into Ruby without an explicit
callback.

---

<a id="the-ruby-api"></a>
## The Ruby API

The host creates a runtime object, configures it, then runs code:

```ruby
engine = Charlie::Runtime.new
engine.timeout_seconds = 5

result = engine.run_string("puts 'hello'")
```

Configuration is set before execution. `run_string` (and equivalent `run_file`) take
source and return a structured result:

```ruby
result.success?         # true/false
result.value            # return value of the program
result.elapsed_seconds  # wall time
```

---

<a id="how-the-script-accesses-host-resources"></a>
## How the Script Accesses Host Resources

The top-level script uses `%engine` to pull in whatever the host has made available:

```
$db   = %engine['db']
$docs = %engine['docs']
```

From there, resources are passed down to functions explicitly as parameters. Inner
functions never see `%engine` — they only have access to what they are handed.

`%engine` is non-capturable: the runtime prevents it from being stored in a variable,
passed as an argument, or captured by a closure. This is enforced by the runtime, not
by convention.

---

<a id="injecting-capabilities"></a>
## Injecting Capabilities

Charlie has no ambient authority — no global filesystem access, no network. Everything
the program can do must be explicitly granted by the host. Built-in system methods like
`%now` (returns the current timestamp) are provided by the runtime and are not
capabilities — they carry no authority and grant no access to resources.

The host injects named capabilities before running:

```ruby
engine["db"] = Charlie::Capability.new { MyDatabase.connection }
```

Inside Charlie, injected capabilities appear as `%name`:

```
%db.query(...)
```

This means a Charlie program can only do what the host explicitly hands it. Nothing is
available by default.

<a id="stdout-and-stderr"></a>
### stdout and stderr

stdout and stderr follow the same capability model — they are not special. A program can
only write to stdout or stderr if the host has injected them.

The CLI runner injects them automatically, which is why running a script at the command
line produces output without any configuration:

```ruby
# what the CLI runner does implicitly
engine["stdout"] = $stdout
engine["stderr"] = $stderr
```

A Ruby host can inject them explicitly to capture output, redirect it, or suppress it
entirely by not injecting them at all:

```ruby
engine["stdout"] = StringIO.new   # capture
engine["stderr"] = StringIO.new   # capture
```

This keeps stdout and stderr consistent with every other resource. There is no global
stdout setting and no special rule that lets them cross security boundaries — untrusted
code can only write to stdout if it has been explicitly handed the capability.

---

<a id="data-vs-capabilities-vs-chain"></a>
## Data vs Capabilities vs Chain

Three distinct channels carry information into a Charlie execution:

- **Data** — plain values passed by value (strings, numbers, hashes). Safe to pass to
  untrusted code. No authority attached.
- **Capabilities** — objects that carry authority (filesystem handle, database connection,
  network socket). Explicitly injected; Charlie sees only what the host grants.
- **Chain** (`%chain`) — scoped ambient context (current user, request ID, locale).
  Flows downward through the call stack; changes do not propagate upward. Cleared when
  entering untrusted execution.

```
Data        →  passed by value
Authority   →  passed by capability
Context     →  passed by chain
```

---

<a id="filesystem-sandboxing"></a>
## Filesystem Sandboxing

Filesystem access is granted via jail objects — scoped handles to specific directories
with explicit read/write permissions:

```ruby
engine["docs"] = Charlie::Jail.new("/var/lib/myapp/docs", read: true)
engine["out"]  = Charlie::Jail.new("/var/lib/myapp/out",  read: true, write: true)
```

Inside Charlie:

```
%docs.path("readme.txt").read
%out.path("result.json").write($data)
```

Charlie never sees real filesystem paths — only virtual paths relative to the jail root.
The host resolves them. A program cannot escape its jail.

---

<a id="timeouts"></a>
## Timeouts

A compliant engine must enforce timeouts in a way that Charlie code cannot interfere with
or disable. In the Lua reference implementation this is done using `debug.sethook`.

The host sets a default timeout:

```ruby
engine.timeout_seconds = 5
```

Charlie code can set tighter timeouts on its own blocks, but cannot exceed the budget
granted by the host:

```
%timeout(2) do
    &untrusted_operation
end
```

Nested timeouts take the minimum of the requested time and the remaining parent budget:

```
effective_timeout = min(requested, remaining_parent_budget)
```

---

<a id="chain-and-security"></a>
## %chain and Security

`%chain` is cleared when entering an untrusted execution boundary. This prevents a
downloaded function from reading the caller's user context, request ID, or any other
ambient state.

See the `%chain` documentation for the full scoping model. The security implications
of `%chain` are to be discussed separately.

---

<a id="summary"></a>
## Summary

The bootstrapping process in a Ruby host:

1. Create a `Charlie::Runtime`
2. Set limits (timeout)
3. Inject capabilities (`engine["name"] = resource`), including stdout/stderr if needed
4. Call `engine.run_string` or `engine.run_file`
5. Inspect the structured result

Security is maintained by: capability isolation (no ambient authority), scoped context
(`%chain` cleared at trust boundaries), jailed filesystem access, and runtime-enforced
timeouts.
