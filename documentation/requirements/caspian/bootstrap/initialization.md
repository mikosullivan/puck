# Initialization

<!--index: 3 -->

~~~vibecode
{"vibecode": {
	"doc": "caspian_bootstrap",
	"role": "canonical spec for how Caspian bootstraps — the sequence of steps from host process startup to the first user statement executing. Owns the host-engine boundary (what the host does vs. what the engine does), the property-based host API (`engine.caspianj`, `engine.run()`, etc.), and what runtime state is initialized before user code runs. Does NOT cover the lexer/parser/transpiler (separate docs), how dispatch works after a statement starts executing (separate doc), or the `instance` keyword (an unrelated 'bootstrap' word that builds one-off objects — see classes/instance, not migrated yet).",
	"status": "active spec — first authored fresh in the new requirements/ tree",
	"audience": "host implementers (Lua, Ruby, anyone bootstrapping the engine); Caspian programmers who want to understand what state exists when their first line runs; AI tooling reasoning about engine startup"
}}
~~~

**Bootstrapping** in Caspian means getting from "the host process just started" to "the first line of the user's Caspian program is about to execute." This doc owns that lifecycle.

## The layers

Caspian doesn't run by itself. It always runs inside a **host process** that loads the engine and feeds it the program to run.

~~~
┌──────────────────────────────────────────────┐
│ Host process                                 │
│ (Lua program; could be Ruby, Python, etc.)   │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ Caspian engine                         │  │
│  │ (modules: lexer, parser, transpiler,   │  │
│  │  engine itself; written in Lua for     │  │
│  │  the reference impl)                   │  │
│  │                                        │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │ Caspian runtime state            │  │  │
│  │  │ (roles, call stack, classes,     │  │  │
│  │  │  argv — initialized at bootstrap)│  │  │
│  │  └──────────────────────────────────┘  │  │
│  │                                        │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │ User program                     │  │  │
│  │  │ (the Caspian source or CaspianJ  │  │  │
│  │  │  tree the host wants to run)     │  │  │
│  │  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
~~~

Each layer can see the layer below it but not the other way around. The user program calls into the engine via system methods (`%engine`, `%stdout`, etc.); the engine reads host-configured properties. The user program cannot reach into the host directly.

## The startup sequence

The host walks through this sequence to bootstrap and run a Caspian program:

### 1. Load the engine modules

The host loads the Caspian engine code into its address space. For the Lua reference implementation, this is a Lua `require('caspian.engine')` (and whatever else — lexer/parser/transpiler — the host needs). This step produces an **engine module** — a table with properties the host can set and methods the host can call.

The engine module surface (per the V1 spec):

| Member | What it is |
|---|---|
| `engine.caspianj` | property — host sets this to the program's CaspianJ tree before calling `run()` |
| `engine.argv` | property — host sets this to the program's command-line arguments |
| `engine.stdout` | property — host sets this to a function the engine calls when the program writes to stdout |
| `engine.stdin`, `engine.stderr` | parallel properties for input and diagnostic output |
| `engine.parse_caspian(source)` | method — takes Caspian source text, returns the CaspianJ tree |
| `engine.run()` | method — no arguments; executes the staged tree and returns whatever the program set via [`%engine.return_val`](https://puck.uno/documentation/requirements/caspian/engine/return-val), or null if it was never called |
| `engine.bootstrap()` | internal — called by `engine.run()`; not normally called by the host directly |

More properties and slots arrive as later slices add them. The current shape is set by the V1 development plan; the canonical inventory of engine properties (the user-visible `%engine.*` surface) will live in its own doc once the slice machinery for it migrates from `requirements-old/`.

### 2. Configure the engine

The host installs its capabilities and configuration by setting properties on the engine module:

~~~lua
engine.argv   = {'first-arg', 'second-arg'}
engine.stdout = function(s) io.write(s) end
~~~

Each property has a documented default (or "unset means raise on use"). The host only sets the ones it wants to expose. Tests substitute fakes (`engine.stdout = function(s) captured_buffer = captured_buffer .. s end`); a CLI wires real OS streams; a sandbox can withhold a property entirely.

### 3. Stage the program

The host gets the program into the engine in one of two ways:

- **From Caspian source.** The host calls `engine.parse_caspian(source)` to lex/parse/transpile a Caspian text string into a CaspianJ tree, then assigns the result to `engine.caspianj`.
- **From a pre-made CaspianJ tree.** The host (e.g., a test harness) writes the CaspianJ tree directly and assigns it to `engine.caspianj`. Skips the source-text pipeline entirely.

Both paths converge on the same property: `engine.caspianj = <tree>`.

### 4. Run

The host calls `engine.run()` with no arguments. Everything `run()` needs has already been wired as properties. Internally `run()`:

1. Validates `engine.caspianj` is set (raises if not).
2. Calls `engine.bootstrap()` to initialize runtime state (next section).
3. Walks the tree's statements top to bottom; dispatches each.
4. Returns to the host whatever the program set via [`%engine.return_val`](https://puck.uno/documentation/requirements/caspian/engine/return-val), or null if it was never called.

### 5. Read the result

`engine.run()` returns the program's signaled return value (or null). The host does whatever it wants with that — print it, return it from a test, ignore it, use it as the program's exit code.

## What `bootstrap()` initializes

When `engine.run()` calls `engine.bootstrap()`, the engine builds the runtime state the user program will see. This state lives on `engine.state` and includes:

- **Roles registry.** Named roles the engine knows about. V1 commits to: `user` (the role the user program starts in), `engine` (engine-emitted attribution; doesn't run user-program frames), and one role per engine-provided faucet (stdin, argv, env, filesystem, network, downloads — see [pipes/faucets](https://puck.uno/documentation/requirements/caspian/pipes/faucets/)). Post-V1 role candidates (a `stdlib` distinction, `request` / `agent` identity roles, fork behavior) are covered under [roles § Deferred until post-V1](https://puck.uno/documentation/requirements/caspian/roles/#deferred-until-post-v1). The registry is the source of truth for which roles exist.
- **Call stack.** Starts empty. The first frame is pushed when dispatch starts on the first statement (under the `user` role).
- **argv.** Copied from `engine.argv` if set; defaults to an empty array.
- **Built-in classes.** A minimum set the engine guarantees: at least `puck.uno/string` (with `to_string`/`to_json` methods) so literal materialization can produce real string values. Additional built-in classes (numbers, booleans, hashes, arrays, etc.) arrive in later slices.

After `bootstrap()` returns, user code is about to execute its first statement. The state is fully initialized; nothing further happens between `bootstrap()` and the first dispatch.

## What's available to the user program immediately

When the first statement of the user program runs, it can reach:

- `%engine.*` — the engine object the host configured (argv, stdout, stdin, stderr, and whatever else the host wired).
- `%stdout`, `%stderr`, `%stdin` — top-level system methods that read through `engine.*` properties. The exact access rules (which roles can call them) live in the system-methods doc once it migrates.
- The built-in classes — `puck.uno/string` and others — reachable for instantiation and method dispatch.
- All language constructs the slice this program is targeting actually supports. (Aslan: literal-method-call only. Bree: + the source-text pipeline. Corin: + BWC dispatch and `puts`. Etc.)

What the user program does NOT see:

- The host directly. There is no escape hatch from a user program to the host process. Capabilities flow only through the engine properties the host wired.
- Anything the host chose not to expose. If `engine.stdout` is unset, the program raises when it tries to write — there's no ambient default.

## Host-engine responsibilities

| Host does | Engine does |
|---|---|
| Loads engine modules into memory | Provides the module surface (properties, methods) |
| Sets engine properties (capabilities, config, program) | Reads engine properties when needed |
| Calls `engine.run()` | Initializes runtime state inside `bootstrap()` |
| Receives the return value of `engine.run()` | Walks statements; dispatches; returns last value |
| Decides what to do on errors | Raises errors the host can catch |
| Wires real OS resources or fakes | Doesn't know what's behind a property — just uses it |

The split is deliberate: the engine never directly opens files, allocates network sockets, or reads OS environment. The host does those things and hands the engine the results (or wraps them in callable functions the engine invokes). This is what makes the engine sandbox-able — replacing the host swaps out the entire I/O substrate.

## Host language independence

The Lua reference implementation isn't a privileged host. Any language that can load the engine and conform to the property-based surface can be a host:

- A Ruby host would expose `engine.caspianj=`, `engine["stdout"]=`, `engine.run`, etc. in Ruby idiom.
- A Python host would do the same with Python attribute / item access.
- The engine doesn't know or care which host is running it. Internally it sees Lua tables (because the engine itself is Lua); the host's marshaling layer converts.

The contract is the surface, not the syntax. Conform to the surface and you can bootstrap.

## What this doc deliberately doesn't cover

- **Lexer / parser / transpiler.** The pipeline from Caspian source text to CaspianJ tree is part of the engine's surface (via `engine.parse_caspian`) but how each stage works internally lives in its own docs (not yet migrated to the new tree).
- **Dispatch.** Once `bootstrap()` finishes and the engine starts walking statements, what happens inside `dispatch()` (method lookup, role transition, materialization) is the dispatch doc's territory (not yet migrated).
- **The `instance` keyword.** Different concept; covered in `classes/instance` (not yet migrated). Calling that "bootstrap" was historical.
- **CLI wiring.** How a `caspian` command-line runner instantiates a host and invokes the engine is the CLI doc's territory (not yet migrated).
- **Per-property semantics.** What each `engine.*` property does in detail (e.g., the contract for the `stdout` function, the shape of `argv`) lives in the engine-slots doc once it migrates.
