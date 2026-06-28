# Bootstrapping the Caspian Interpreter

~~~vibecode
{"vibecode": {
	"doc": "bootstrap",
	"role": "spec for how a host language (Ruby as the worked example) integrates with and bootstraps the Caspian runtime through an embedded Lua VM; layered host/Lua/Caspian policy model. The Bree, Corin, and other V1 slice docs reference this as the authoritative host-API surface.",
	"key_concepts": ["host_layer", "embedded_lua_vm", "downward_visibility_only",
		"ruby_api_sketch", "policy_enforcement"],
	"status": "active spec — promoted from ideas/ once V1 slice docs began citing it as authoritative"
}}
~~~

Notes on how a host language (Ruby used as the example) integrates with and bootstraps
the Caspian runtime.

---

## Architecture

```
Ruby (host / policy layer)
    ↓
Lua C library (embedded VM)
    ↓
Caspian runtime (written in Lua)
```

Ruby owns the process and enforces policy. Lua runs the Caspian engine. Caspian runs
the program (which may include untrusted code). Each layer can only see downward — Caspian
cannot reach into Lua internals, and Lua cannot reach into Ruby without an explicit
callback.

---

## How the Script Accesses Host Resources

The top-level script uses `%engine` to pull in whatever the host has made available:

```
$db   = %engine['db']
$docs = %engine['docs']
```

From there, resources are passed down to functions and libraries explicitly as
parameters.

**Only the `user` role can call methods on the engine object** — a deliberate
special case enforced by a dedicated check in the engine object itself. Loaded
libraries (running in their own roles) cannot reach `%engine`, even if passed a
reference to it. See [engine/](../requirements/caspian/engine/).

---

## Injecting Capabilities

Caspian has no ambient authority — no global filesystem access, no network. Everything
the program can do must be explicitly granted by the host. Built-in system methods like
`%now` (returns the current timestamp) are provided by the runtime and are not
capabilities — they carry no authority and grant no access to resources.

The host injects named capabilities before running:

```ruby
engine["db"] = Caspian::Capability.new { MyDatabase.connection }
```

Inside Caspian, injected capabilities appear as `%name`:

```
%db.query(...)
```

This means a Caspian program can only do what the host explicitly hands it. Nothing is
available by default.

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

## Data vs Capabilities vs Chain

Three distinct channels carry information into a Caspian execution:

- **Data** — plain values passed by value (strings, numbers, hashes). Safe to pass to
  untrusted code. No authority attached.
- **Capabilities** — objects that carry authority (filesystem handle, database connection,
  network socket). Explicitly injected; Caspian sees only what the host grants.
- **Chain** (`%chain`) — scoped ambient context (current user, request ID, locale).
  Flows downward through the call stack; changes do not propagate upward. Cleared when
  entering untrusted execution.

```
Data        →  passed by value
Authority   →  passed by capability
Context     →  passed by chain
```

---

## Filesystem Sandboxing

Filesystem access is granted via jail objects — scoped handles to specific directories
with explicit read/write permissions:

```ruby
engine["docs"] = Caspian::Jail.new("/var/lib/myapp/docs", read: true)
engine["out"]  = Caspian::Jail.new("/var/lib/myapp/out",  read: true, write: true)
```

Inside Caspian:

```
%docs.path("readme.txt").read
%out.path("result.json").write($data)
```

Caspian never sees real filesystem paths — only virtual paths relative to the jail root.
The host resolves them. A program cannot escape its jail.

---

## Timeouts

A compliant engine must enforce timeouts in a way that Caspian code cannot interfere with
or disable. In the Lua reference implementation this is done using `debug.sethook`.

The host sets a default timeout:

```ruby
engine.timeout_seconds = 5
```

Caspian code can set tighter timeouts on its own blocks, but cannot exceed the budget
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

## %chain and Security

`%chain` is cleared when entering an untrusted execution boundary. This prevents a
downloaded function from reading the caller's user context, request ID, or any other
ambient state.

See the `%chain` documentation for the full scoping model. The security implications
of `%chain` are to be discussed separately.

---

## Summary

The bootstrapping process in a Ruby host:

1. Create a `Caspian::Runtime`
2. Set limits (timeout)
3. Inject capabilities (`engine["name"] = resource`), including stdout/stderr if needed
4. Call `engine.run_string` or `engine.run_file`
5. Inspect the structured result

Security is maintained by: capability isolation (no ambient authority), scoped context
(`%chain` cleared at trust boundaries), jailed filesystem access, and runtime-enforced
timeouts.
