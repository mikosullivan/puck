# Aslan

~~~json
{"vibecode": {"codename": "Aslan", "delivers": "hello-world", "goal":
"execute a minimal caspianj program end_to_end and return a literal value to the test harness",
"medium": "caspianj_hand_written; not_caspian_source", "fixture":
"[[{\"value\": \"hello\"}, \"to_string\"]]", "expected_return": "hello",
"observation": "test_harness_captures_last_statement_value; no_stdout_io",
"covers": ["json_parser", "ksj_interpreter", "statement_dispatch",
"literal_materialization_with_owning_role", "method_dispatch_with_role_transition",
"string_class_minimum_with_to_string"], "deferred_to_later":
["caspian_text_parser", "transpiler", "stdout_io", "sys_references"]}}
~~~

The first runnable version. A single `.caspj` file containing the CaspianJ
encoding of "evaluate `"hello".to_string`" executes through the engine
under `lib/lua/` and returns the string `"hello"` to the test
harness. No I/O — no stdout, no sinks beyond what the harness needs to
observe the return value.

Caspian transpiles to CaspianJ (CaspianJ is the canonical runtime
format), so the engine consumes CaspianJ, not Caspian text. Aslan
hand-writes the CaspianJ fixture and skips the transpiler entirely. The
Caspian text parser, the transpiler, and `sys`-reference resolution
(`%stdout`, `%now`, etc.) are all deferred to later slices.

Aslan is intentionally tiny. Every layer the engine actually needs to
execute a single method-call statement has to exist in skeleton form to
pass — JSON parser, statement dispatcher, method dispatch with role
transition, literal materialization with owning-role tag, the minimum
string class with `to_string` — but each layer can be minimal. The point
is to prove the engine integrates end-to-end before any single layer is
built out fully.

<a id="definition-of-done"></a>
### Definition of done

~~~json
{"vibecode": {"scope_status": "confirmed_2026-05-15", "done_criteria":
{"fixture_runs": "[[{\"value\": \"hello\"}, \"to_string\"]]_parses_and_executes",
"runs_under_a_role":
"program_executes_in_user_role; dispatch_transitions_to_stdlib_role_and_back",
"has_a_string_class":
"minimum_built_in_string_class_with_to_string_returning_self; owned_by_engine_role",
"returns_hello":
"last_statement_return_value_equals_string_hello_observed_by_harness"}}}
~~~

Aslan is done when all four are true:

1. **The fixture runs.** `[[{"value": "hello"}, "to_string"]]` parses
   and executes through the engine without exception.
2. **Code runs under a role.** The engine assigns the program to the
   `user` role; method dispatch transitions to the string-class role
   for the `to_string` call and back to `user` on return.
3. **A string class exists.** The engine has a minimum built-in
   string class, owned by an engine role, supporting `to_string` (which
   for strings is identity).
4. **The harness receives `"hello"`.** The last statement's return
   value is captured by the Lua-side harness and matches the string
   `"hello"`.

That's the entirety of Aslan. Soft feature lock applies — no additional
scope without explicit unlock.

---

## Engine startup and invocation

~~~json
{"vibecode": {"section": "engine_startup_and_invocation", "scope":
"how_a_ksj_program_actually_runs_from_invocation_through_return",
"applies_from": "aslan", "covers": ["host_vs_engine_distinction",
"invocation_chain", "bootstrap_sequence", "program_model",
"what_user_ksj_can_see", "how_later_slices_extend"]}}
~~~

This section spells out the lifecycle of a CaspianJ run end-to-end: who
launches it, what the engine does before user code executes, what user
code can actually reference, and how that lifecycle grows in later
slices. It answers two related questions that came up while scoping
Aslan: **how do you start a CaspianJ script** and **how does the engine load
allowed objects into the outermost CaspianJ block**.

<a id="host-vs-engine"></a>
### Host vs. engine

~~~json
{"vibecode": {"host_vs_engine": {"engine":
"the_library_that_runs_ksj; located_under_code_caspian_lua",
"host": "anything_that_calls_into_the_engine; varies_by_slice",
"aslan_host": "lua_test_runner_invoked_from_command_line",
"later_hosts": ["standalone_cli_via_frank_caspian_cli_slice",
"sammy_request_handler_corin_plus",
"one_running_ksj_calling_another_via_function_dispatch"]}}}
~~~

The **engine** is the Lua library at `lib/lua/` that knows how
to parse and execute CaspianJ. The **host** is whatever calls into the
engine. They are different layers.

In Aslan the host is a Lua test runner invoked from the command line.
Later hosts include the standalone `caspian` CLI (arrives in the
[Frank caspian-cli slice](frank.md),
prerequisite for Glenstorm Bryton), a Sammy request handler (at the
first-HTTP slice — every handler closure is itself CaspianJ that the engine
runs in response to a request), and one piece of running CaspianJ calling
another (which emerges from normal function dispatch, no separate
engine API needed). Each host invokes the same `engine.run()` entry
point; what differs is who triggers it and what they pass in.

<a id="aslan-invocation-chain"></a>
### Invocation chain

~~~json
{"vibecode": {"aslan_invocation_chain": [{"step": 1, "name":
"command_line_invocation", "example":
"lua tests/caspian/run.lua tests/caspian/fixtures/hello_world.caspj"},
{"step": 2, "name": "runner_loads_engine_as_lua_library",
"example": "local engine = require(\"caspian\")"}, {"step": 3,
"name": "runner_calls_engine_run_with_file_path", "example":
"local result = engine.run(\"tests/caspian/fixtures/hello_world.caspj\")"},
{"step": 4, "name": "engine_bootstrap_then_parse_then_execute",
"covered_in_next_subsection": true}, {"step": 5, "name":
"engine_returns_last_statement_value_to_runner_as_lua_value"},
{"step": 6, "name":
"runner_compares_to_expected_string_hello_and_reports_pass_or_fail"}]}}
~~~

Top-level shape:

1. **Command-line invocation.** Something like
   `lua tests/caspian/run.lua tests/caspian/fixtures/hello_world.caspj`.
2. **Runner loads the engine as a Lua library.** Roughly
   `local engine = require("caspian")`.
3. **Runner calls `engine.run()` with the fixture path.** Roughly
   `local result = engine.run("...fixtures/hello_world.caspj")`.
4. **Engine bootstrap, parse, and execute happen behind that one
   call.** Detailed below.
5. **Engine returns the last statement's value to the runner** as a Lua
   return value.
6. **Runner compares to expected `"hello"`** and reports PASS or FAIL.

<a id="aslan-engine-bootstrap-sequence"></a>
### Engine bootstrap sequence

~~~json
{"vibecode": {"aslan_bootstrap_sequence": [{"step": 1, "name":
"create_role_registry", "creates": ["user", "stdlib"],
"role_object_aslan":
"name_only_no_methods_no_state_no_trust_web"}, {"step": 2, "name":
"create_built_in_string_class", "creates":
"string_class_object_with_one_method_to_string_returning_self",
"tagged_with": "stdlib"}, {"step": 3, "name":
"create_call_stack_with_top_level_frame", "frame":
{"action": "top_level", "role": "user_role_ref",
"chain": "empty_chain"}}, {"step":
4, "name": "load_and_parse_ksj_file", "uses": "json_parser",
"produces": "parsed_ksj_tree"}, {"step": 5, "name":
"execute_top_level_statements", "iterates":
"each_statement_in_top_level_array_of_parsed_tree", "captures":
"last_statement_return_value"}, {"step": 6, "name":
"return_to_host", "returns": "captured_last_value_as_lua_value"}]}}
~~~

What happens between `engine.run(path)` being called and the result
coming back:

1. **Create the role registry.** A small map of role-name → role-object.
   Aslan needs two roles: `user` (what the program runs as) and the
   string-class role (provisional name TBD; owns the built-in string
   class). Role objects in Aslan are barely more than identity tags —
   they have a name and nothing else. Cross-role trust,
   role-introspection, role nicknames are all later.

2. **Create the built-in string class.** The engine constructs the
   string class object — internally a class-registry entry with one
   method, `to_string`, whose implementation is "return the receiver."
   The class is tagged with the string-class role as its owner; the
   method-object inherits that owner.

3. **Create the call stack with a top-level frame.** `engine.state.call_stack`
   starts as a one-element array holding a `top_level` frame whose
   `role` references the `user` role and whose `chain` is an empty
   placeholder. From this point forward, every value created counts
   as owned by the top frame's role (in Aslan, the user role); every
   method call pushes a new frame and pops it on return.

4. **Load and parse the CaspianJ file.** The engine reads the path it was
   handed, gives the text to the JSON parser, gets back a parsed tree.
   For Aslan the tree is `[[{"value": "hello"}, "to_string"]]`.

5. **Execute top-level statements.** The engine iterates the outermost
   array. For each statement, it calls the statement dispatcher; the
   dispatcher handles literal materialization, method lookup, role
   transition, and method execution. Each statement's return value is
   captured; the last one is what gets surfaced.

6. **Return to host.** The captured last-value is returned to the host
   (in Aslan, the Lua test runner) as a Lua return value.

<a id="program-model"></a>
### Program model

~~~json
{"vibecode": {"program_model_aslan": {"shape":
"top_level_array_of_statements", "entry_point":
"the_outermost_array_itself_no_main_function",
"result_of_program":
"value_of_last_top_level_statement", "execution":
"statements_run_in_order"}}}
~~~

A CaspianJ program is a **top-level array of statements**. The engine
executes them in order. The "result" of the program is the value of
the last top-level statement. There is no `main` function and no
entry-point declaration — the outermost array IS the entry point.

Statements can define functions and call them, but for Aslan the
program is just one statement.

<a id="what-user-caspianj-can-see-in-aslan"></a>
### What user CaspianJ can see

~~~json
{"vibecode": {"aslan_visibility": {"directly_referenceable_by_name":
"nothing", "implicitly_available":
["string_class_via_literal_materialization",
"to_string_via_method_dispatch_on_string_values"],
"explicitly_unavailable_aslan":
["sys_references_percent_stdout_percent_role_etc",
"other_built_in_classes_integer_hash_array",
"faucets", "jails", "trust_declarations"]}}}
~~~

The Aslan fixture doesn't reference any object by name. It only:

- Materializes a string literal (`{"value": "hello"}`) — the engine's
  literal-materializer knows about the string class and tags the new
  value with that class.
- Calls a method on the value (`"to_string"`) — the dispatcher looks
  up the method on the receiver's class.

The string class is **not exposed as a named object** in Aslan. It's
**discovered** by the dispatcher when a method call lands on a string
value. This is the simplest possible answer to "how do allowed objects
get loaded into the outermost CaspianJ block": in Aslan, they don't get
loaded explicitly at all — they're available only through the
dispatcher's class-lookup mechanism for values the engine itself
created.

<a id="how-later-slices-grow-the-lifecycle"></a>
### How later slices grow the lifecycle

~~~json
{"vibecode": {"growth_path": {"bree": {"bootstrap_change":
"none; transpiler_runs_before_engine_invoked",
"invocation_change":
"runner_may_optionally_transpile_caspian_text_to_ksj_before_engine_run; engine_still_consumes_ksj"},
"first_http": {"new_host": "sammy_request_handler",
"new_bootstrap_pieces":
["network_faucet_role; request_object_tagged_with_faucet_role"],
"new_visibility":
"sys_references_for_request_response_etc"}, "later_classes":
"each_new_built_in_added_to_class_registry_and_tagged_with_engine_role; discovered_via_literal_or_dispatch",
"sys_references_generally":
"engine_pre_populates_sys_table_during_bootstrap; user_code_reaches_via_sys_form",
"faucets_generally":
"each_added_to_faucet_registry_with_own_role; pulled_objects_inherit_faucet_role"},
"v1_open":
"engine_capability_allow_list_for_running_untrusted_code"}}
~~~

Bree (transpiler) doesn't change the bootstrap sequence — the
transpiler runs before the engine is invoked (probably as a runner-side
step that turns `.casp` text into CaspianJ), and the engine consumes the
CaspianJ exactly as in Aslan.

Later slices extend the lifecycle in these ways:

- **New hosts.** The first HTTP slice introduces a Sammy request
  handler as a host: an incoming request triggers a handler closure
  (itself CaspianJ) to execute. Same `engine.run()`-shaped entry; the
  caller is different.
- **Sys references** (`%stdout`, `%now`, `%role`, `%puck`, etc.). The
  engine pre-populates a sys-reference table during bootstrap; user
  code reaches the objects via `{"sys": "name"}`. Each sys-referenced
  object is tagged with its owning engine role.
- **More built-in classes** (integer, hash, array, etc.). Each gets
  added to the class registry and tagged with an engine role. Same
  discovery model as string: the dispatcher finds the class when a
  method call lands on a value of that type.
- **Faucets.** Each faucet (filesystem directory jail, network client, db
  connection, stdin, env, cli-args) gets registered with its own role
  during bootstrap. Objects pulled through inherit the faucet's role.

The bigger open question — **how the engine decides which capabilities
a particular invocation gets** — is V1 work, not Aslan. The shape is
still TBD. Likely candidates: engine-config-driven (the deployer
specifies which built-ins and faucets a given Caspian instance can
access); role-driven (a role's trust web determines what it can see).
This is core to "running untrusted code" — the engine must be able to
launch a Caspian instance with a restricted surface that the running
code cannot escape. Flagged as an open item.

---

<a id="lua-side-implementation-sketch"></a>
## Lua-side implementation sketch

~~~json
{"vibecode": {"section": "lua_implementation_sketch", "status":
"candidate_shape; to_be_reconciled_with_existing_code_during_inventory",
"language": "lua_5_4_assumed", "style":
"plain_tables_no_metatables_for_aslan; closures_for_role_transition_save_restore",
"deliberately_not_specified":
["module_layout_within_code_caspian_lua_caspian_directory",
"naming_conventions_for_internal_locals",
"exact_signature_of_existing_json_lua"]}}
~~~

This section sketches the engine's internal Lua shape for Aslan: data
structures, key procedures, and a pseudo-code skeleton. It is a
**candidate target** to be reconciled with what's already in
`lib/lua/caspian/` during Step 1 (inventory) of Phase 1. Where
existing code already does something workable, use it; where it
doesn't, the shapes below are the proposal.

<a id="data-structures-lua-tables"></a>
### Data structures (Lua tables)

~~~json
{"vibecode": {"data_structures": {"role_object":
"{name = string}", "role_registry":
"engine.roles = {[name] = role_object, ...}", "value":
"{type = string, owning_role = role_object, payload = any_lua_value}",
"class_object":
"{name = string, owning_role = role_object, methods = {[name] = lua_function}}",
"class_registry": "engine.classes = {[name] = class_object, ...}",
"skeletor_state_hash":
"engine.state = {call_stack = {frame_1, ...}}; each_frame_carries_action_role_chain_locals_pc; aslan_top_frame_is_top_level_with_user_role_empty_chain; grows_in_later_slices_per_skeletor_md",
"skeletor_doc": "../../caspian/skeletor/skeletor.md"}}}
~~~

**Skeletor from day one.** Per [skeletor.md](../../caspian/skeletor/skeletor.md),
all of Caspian's execution state lives in a single hash —
`engine.state` in this implementation. Aslan's state hash is tiny —
one field, `call_stack`, holding one frame to start — but the
discipline is in place from the first slice: the interpreter goes
through `engine.state` for all execution state, and the role/chain
context lives in the top-of-stack frame rather than as separate
top-level fields. Later slices grow the hash's contents (deeper stacks, iterator
state, pending exceptions, program-wide fields like `argv`) without
changing the shape. Roles and classes are bootstrap-time registries
(engine metadata, not execution state) and live alongside the hash as
`engine.roles` and `engine.classes`.

Every internal object is a plain Lua table — no metatables in Aslan.
References between tables are Lua's normal table-reference semantics
(passing a table around shares the same memory; assignment copies the
reference, not the contents).

- **Role object.** Minimal in Aslan:
  ```lua
  { name = "user" }
  ```
  Later slices will add trust webs, role-introspection state, etc.

- **Role registry.** A flat table mapping role-name to role-object:
  ```lua
  engine.roles = {
      user         = { name = "user" },
      stdlib = { name = "stdlib" },
  }
  ```

- **Value.** Every CaspianJ value the runtime holds is a Lua table with
  three fields:
  ```lua
  { type = "string", owning_role = engine.roles.user, payload = "hello" }
  ```
  The `owning_role` field is a *reference* to one of the role objects
  in `engine.roles` — same Lua table, shared. Once set, it's never
  reassigned (immutable per [roles.md](../../caspian/roles.md)).

- **Class object.** Holds methods as a sub-table of Lua functions:
  ```lua
  {
      name = "string",
      owning_role = engine.roles.stdlib,
      methods = {
          to_string = function(receiver, args) return receiver end,
      },
  }
  ```
  The method function takes the receiver value and optional args; it
  returns a value (another `{type, owning_role, payload}` table or one
  of its inputs).

- **Class registry.** Flat name → class table:
  ```lua
  engine.classes = { string = { ... } }
  ```

- **Execution state (Skeletor hash).** One table that holds all
  durable execution state. For Aslan, just a `call_stack` array
  starting with one `top_level` frame:
  ```lua
  engine.state = {
      call_stack = {
          {
              action = "top_level",
              role   = engine.roles.user,
              chain  = {},        -- empty placeholder for Aslan
              locals = {},
          },
      },
  }
  ```
  Each frame is a Lua table carrying `action`, `role`, `chain`,
  `locals`, and (in later slices) `src`, `iterator`, etc. The "current
  role" and "current chain" are just the top frame's `role` and
  `chain` — no separate top-level fields. This is the
  [Skeletor](../../caspian/skeletor/skeletor.md) hash. Cross-role transitions
  push a new frame on entry and pop it on return; Lua's own call
  stack runs alongside the explicit frame stack (the dispatcher
  function nests, and so does the explicit stack). Working state
  (intermediate expression results, args being marshaled) stays
  outside the hash, per skeletor.md.

<a id="key-procedures"></a>
### Key procedures

~~~json
{"vibecode": {"procedures": {"engine.run":
"(path) -> last_statement_value; entry_point",
"engine.bootstrap":
"() -> nil; populates_roles_classes_state_hash", "engine.dispatch":
"(statement) -> value; handles_one_top_level_statement",
"engine.materialize": "(expr) -> value; turns_ksj_expression_into_value",
"engine.transition":
"(new_role, fn) -> result; save_restore_state_hash_around_fn_call",
"engine.lookup_method": "(value, method_name) -> method_fn"}}}
~~~

Five procedures cover Aslan:

- `engine.run(path)` — entry point called by the host.
- `engine.bootstrap()` — populates the role registry, class registry,
  and execution context. Runs once per `engine.run` invocation.
- `engine.dispatch(statement)` — handles one parsed statement (the
  `[receiver, method, args?]` triple).
- `engine.materialize(expr)` — turns a CaspianJ expression
  (`{"value": ...}`, etc.) into a value table with `owning_role` tag.
- `engine.transition(new_role, fn)` — wraps a Lua function call with
  save/restore of `engine.state`. Uses Lua's call stack via closures;
  no explicit transition stack needed.
- `engine.lookup_method(value, method_name)` — finds the method
  function on the value's class. Looks up the class via `value.type`
  in `engine.classes`, then the method name in `class.methods`.

<a id="pseudo-code-skeleton"></a>
### Pseudo-code skeleton

~~~json
{"vibecode": {"pseudo_code_status":
"illustrative_target_shape; not_committed_until_reconciled_with_existing_engine"}}
~~~

```lua
local engine = {}
local json = require("caspian.json")     -- existing json.lua

function engine.run(path)
    engine.bootstrap()
    local source = read_file(path)
    local tree = json.parse(source)      -- top-level array
    local last_value = nil
    for _, statement in ipairs(tree) do
        last_value = engine.dispatch(statement)
    end
    return last_value                    -- handed to the host
end

function engine.bootstrap()
    engine.roles = {
        user         = { name = "user" },
        stdlib = { name = "stdlib" },
    }
    engine.classes = {
        string = {
            name = "string",
            owning_role = engine.roles.stdlib,
            methods = {
                to_string = function(receiver, args)
                    return receiver       -- identity on a string
                end,
            },
        },
    }
    engine.state = {
        call_stack = {
            {
                action = "top_level",
                role   = engine.roles.user,
                chain  = {},
                locals = {},
            },
        },
    }
end

local function top_frame()
    return engine.state.call_stack[#engine.state.call_stack]
end

function engine.dispatch(statement)
    local receiver = engine.materialize(statement[1])
    local method_name = statement[2]
    local args = statement[3]            -- may be nil
    local method_fn = engine.lookup_method(receiver, method_name)
    local class = engine.classes[receiver.type]
    local target_role = class.owning_role
    if target_role ~= top_frame().role then
        return engine.transition({
            action        = "method_call",
            role          = target_role,
            receiver_type = receiver.type,
            method        = method_name,
        }, function()
            return method_fn(receiver, args)
        end)
    end
    return method_fn(receiver, args)
end

function engine.materialize(expr)
    if expr.value ~= nil then
        local lua_type = type(expr.value)
        local ksj_type
        if lua_type == "string" then ksj_type = "string" end
        -- other types added in later slices
        return {
            type         = ksj_type,
            owning_role  = top_frame().role,
            payload      = expr.value,
        }
    end
    -- {var:...}, {sys:...}, {function:...}, etc. -- all later slices
    error("unsupported expression form in Aslan: " ..
          (next(expr) or "<empty>"))
end

function engine.lookup_method(value, method_name)
    local class = engine.classes[value.type]
    if not class then
        error("no class registered for type " .. tostring(value.type))
    end
    local method_fn = class.methods[method_name]
    if not method_fn then
        error("method " .. method_name .. " not found on class " .. class.name)
    end
    return method_fn
end

function engine.transition(frame_meta, fn)
    -- Push a new frame; cross-role wipes chain by giving the new
    -- frame its own fresh chain table.
    local frame = {
        action        = frame_meta.action,
        role          = frame_meta.role,
        receiver_type = frame_meta.receiver_type,
        method        = frame_meta.method,
        chain         = {},
        locals        = {},
    }
    table.insert(engine.state.call_stack, frame)
    local result = fn()
    table.remove(engine.state.call_stack)
    return result
end

return engine
```

<a id="notes-on-the-sketch"></a>
### Notes on the sketch

~~~json
{"vibecode": {"sketch_notes": ["plain_tables_only_no_metatables_aslan",
"role_objects_shared_by_reference_across_owning_role_fields",
"explicit_call_stack_array_in_engine_state_pushed_and_popped_per_transition",
"each_frame_carries_its_own_chain_so_cross_role_wipe_is_automatic_on_push",
"errors_use_lua_error_for_aslan_no_caspian_exception_machinery_yet",
"json_parse_assumed_to_return_nested_lua_tables_arrays_indexed_from_1"]}}
~~~

A few specifics worth flagging:

- **No metatables in Aslan.** Plain tables. Metatable-based dispatch
  is a later optimization (or never — the current explicit lookup is
  perfectly clear).
- **Role objects are shared by reference.** When ten values all sit
  under role `user`, they all point at the *same* Lua table
  (`engine.roles.user`). Identity comparison (`a.role == b.role`)
  is constant-time.
- **Explicit call stack in `engine.state.call_stack`.** Each
  transition pushes a frame on entry and pops it on return. Lua's
  call stack still nests (because `engine.transition` is a regular
  Lua function), but the Caspian-visible state is the explicit frame
  array. If `fn()` triggers another transition, another frame goes
  on top.
- **Cross-role chain wipe happens by frame creation.** The pushed
  frame gets `chain = {}` — a fresh table. The caller's chain
  belongs to its own frame and is untouched. On pop, the caller's
  frame is back on top and its chain is what it was.
- **Errors use Lua `error()` for Aslan.** Caspian-level exception
  machinery (alarms vs. regular exceptions per [roles.md](../../caspian/roles.md))
  lands in a later slice. For Aslan, anything wrong = engine bails
  with a Lua error.
- **JSON parser is assumed to return nested Lua tables**, arrays as
  arrays indexed from 1 (Lua-standard). To be confirmed during Step 1
  inventory of the existing `json.lua`.

---

<a id="aslan-phase-0-lua-workbench"></a>
## Phase 0: Lua workbench

~~~json
{"vibecode": {"phase": 0, "purpose":
"set_up_and_verify_lua_dev_environment_before_writing_any_engine_code",
"explicitly_excludes": "executing_caspian_or_ksj; only_lua_level_sanity",
"steps_count": 6, "acceptance":
"all_six_workbench_steps_pass; no_engine_code_written", "tactic":
"verify_the_workbench_before_building_in_it"}}
~~~

Before writing any engine code, the Lua-side development environment
has to be verified. Six steps, each independently runnable. If a step
fails, fix that before moving on. **No Caspian or CaspianJ execution
happens in Phase 0** — this is purely Lua-level sanity.

<a id="step-01-confirm-lua-54"></a>
### Step 0.1: Confirm Lua 5.4

~~~json
{"vibecode": {"step": "0.1", "name": "confirm_lua_5_4", "action":
"run_lua_dash_v_from_project_root", "expected_stdout_contains":
"Lua_5_4", "remedy_if_fail": "install_lua_5_4"}}
~~~

`lua -v` from the project root. Expected: a line containing `Lua 5.4`.
If a different major version is installed, install Lua 5.4 before
proceeding.

<a id="step-02-run-a-sanity-hello-in-pure-lua"></a>
### Step 0.2: Run a sanity hello in pure Lua

~~~json
{"vibecode": {"step": "0.2", "name": "lua_hello",
"fixture_path": "tests/sanity/lua_hello.lua", "fixture_content":
"print(\"hello from lua\")\n", "run":
"lua tests/sanity/lua_hello.lua", "expected_stdout":
"hello from lua\\n", "expected_exit_code": 0}}
~~~

Create `tests/sanity/lua_hello.lua`:

```lua
print("hello from lua")
```

Run: `lua tests/sanity/lua_hello.lua`. Expected stdout: `hello from lua`
followed by a newline. Exit code 0.

<a id="step-03-verify-packagepath-resolves-engine-modules"></a>
### Step 0.3: Verify package.path resolves engine modules

~~~json
{"vibecode": {"step": "0.3", "name": "package_path_check", "action":
"set_package_path_prefix_to_code_caspian_lua; require_a_known_engine_module_no_error",
"expected": "require_call_returns_a_table_without_error"}}
~~~

The engine lives under `lib/lua/`. Lua needs to find modules
when `require("caspian.X")` is called. The convention:

```lua
package.path = "lib/lua/?.lua;" .. package.path
```

Verify with a real existing engine module — `caspian.json` is the
natural choice since it's already in the tree:

The existing `tests/caspian/run.lua` already sets up `package.path` to
resolve both `lib/lua/?.lua` (engine modules) and
`tests/caspian/?.lua` (test-side modules including `support.runner`).
If launching tests from a different entry point, mirror that setup.

A small sanity test exercising the path:

```lua
-- tests/sanity/test_package_path.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("caspian.json")

runner.suite("sanity / package path")

runner.test("caspian.json loaded as a table", function()
    assert_.equal(type(json), "table")
end)
```

<a id="step-04-verify-the-existing-test-framework"></a>
### Step 0.4: Verify the existing test framework

~~~json
{"vibecode": {"step": "0.4", "name": "verify_existing_test_framework",
"existing_runner_module": "tests/caspian/support/runner.lua",
"existing_assert_module": "tests/caspian/support/assert.lua",
"existing_entry_point": "tests/caspian/run.lua",
"do_not": "invent_a_new_harness; use_what_is_already_there",
"runner_api": {"suite": "(name)", "test": "(name, fn)", "report":
"() returns true_if_all_passed"}, "assert_api":
["equal", "not_equal", "is_nil", "not_nil", "is_true", "is_false",
"kind", "count", "parse_error"], "verification":
"write_one_trivial_test_that_uses_runner_and_assert; require_it_from_run_lua_or_a_aslan_entry_point; confirm_passes_and_fails_are_reported_correctly"}}
~~~

The project already has a Lua test framework under
`tests/caspian/support/`:

- `support/runner.lua` — provides `runner.suite(name)`,
  `runner.test(name, fn)`, and `runner.report()`. Maintains pass/fail
  counts across all tests required during a run; prints `.` per pass,
  `F` per fail, then a summary.
- `support/assert.lua` — assertion helpers including `equal`,
  `not_equal`, `is_nil`, `not_nil`, `is_true`, `is_false`, `kind`,
  `count`, `parse_error`. Each errors with a descriptive message on
  failure.
- `tests/caspian/run.lua` — entry point. Adds `package.path`, requires
  all test modules, calls `runner.report()`, exits 0/1.

The existing lexer/parser/transpiler tests already use this framework
(`tests/caspian/lexer/test_literals.lua`, etc.). **Use it as-is for
Aslan.** Don't invent a parallel harness.

Verify it works by writing one trivial sanity test that uses the
framework:

```lua
-- tests/sanity/test_framework_sanity.lua
local runner = require("support.runner")
local assert_ = require("support.assert")

runner.suite("sanity / framework")

runner.test("equal passes for matching values", function()
    assert_.equal(1 + 1, 2)
end)

runner.test("not_nil works", function()
    assert_.not_nil("anything", "non-nil string")
end)
```

Then require it from `tests/caspian/run.lua` (or a temporary Aslan-only
entry point) and run. Expected: two dots and a `2 / 2 passed` summary,
exit 0.

To verify failure reporting, temporarily change one assertion to
something false (`assert_.equal(1, 2)`), re-run, expect `.F`, a failure
description in the summary, and exit 1.

<a id="step-05-verify-jsonlua-loads-and-parses"></a>
### Step 0.5: Verify json.lua loads and parses

~~~json
{"vibecode": {"step": "0.5", "name": "json_parse_sanity",
"fixture_path": "tests/sanity/test_json_parse.lua",
"requires_module": "caspian.json", "parses": "{\"a\": 1}",
"expected": "lua_table_with_a_equals_1", "side_effect":
"discovers_json_lua_actual_api_for_inventory_step",
"framework_used": "tests/caspian/support/runner_and_assert"}}
~~~

The existing `lib/lua/caspian/json.lua` is assumed to provide
a `parse` function. This step confirms it (and surfaces any API
surprises for the Aslan phase 1 inventory step).

```lua
-- tests/sanity/test_json_parse.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("caspian.json")

runner.suite("sanity / json")

runner.test("parses a simple object", function()
    local parsed = json.parse('{"a": 1}')
    assert_.not_nil(parsed, "parse returned nil")
    assert_.equal(parsed.a, 1)
end)
```

If `json.lua`'s API differs (different function name, returns wrapped
result, etc.), this is where we discover it — and the
[Aslan phase 1 inventory step](#step-1-inventory) starts here.

<a id="step-06-verify-file-reading"></a>
### Step 0.6: Verify file reading

~~~json
{"vibecode": {"step": "0.6", "name": "file_read_sanity",
"fixture_path": "tests/caspian/fixtures/_sanity_text.txt",
"fixture_content": "ok\\n", "test_file":
"tests/sanity/test_file_read.lua",
"framework_used": "tests/caspian/support/runner_and_assert"}}
~~~

The engine has to read CaspianJ files from disk; this step confirms that
works.

Fixture: `tests/caspian/fixtures/_sanity_text.txt` containing the two
bytes `ok` followed by a newline.

```lua
-- tests/sanity/test_file_read.lua
local runner = require("support.runner")
local assert_ = require("support.assert")

runner.suite("sanity / file read")

runner.test("io.open + read('*a') returns expected bytes", function()
    local f = assert(io.open("tests/caspian/fixtures/_sanity_text.txt", "r"))
    local content = f:read("*a")
    f:close()
    assert_.equal(content, "ok\n")
end)
```

When all six steps pass, the workbench is verified and Phase 1 can
begin.

Phase 0 test coverage lives under [Testing](#testing) below.

---

<a id="aslan-phase-1-hello-world-in-caspianj"></a>
## Phase 1: hello-world in CaspianJ

~~~json
{"vibecode": {"phase": 1, "fixture_path":
"tests/caspian/fixtures/hello_world.caspj", "fixture_content":
"[[{\"value\": \"hello\"}, \"to_string\"]]", "runner_path":
"tests/caspian/run.lua", "acceptance":
"fixture_runs_via_engine_and_harness_captures_return_value_hello",
"required_ksj_forms": ["value_literal", "statement_call"], "required_runtime":
["json_parser", "ksj_format_alignment_to_canonical_caspianj_spec",
"statement_dispatcher_with_role_transition",
"method_dispatch", "literal_materialization_with_owning_role_tag",
"role_registry_with_user_and_stdlib", "role_system_method",
"chain_wipe_on_boundary",
"top_level_returns_last_statement_value_to_harness"],
"required_stdlib": ["string_class_min_with_to_string_returning_self"],
"tactic": "inventory_then_fill_gaps_and_align_format; spec_wins_over_existing_code",
"canon": "caspianj_md_is_canonical; existing_transpiler_interpreter_format_is_pre_spec_and_gets_brought_into_line",
"deferred_to_bree":
["caspian_text_parser", "transpiler_emitting_canonical_ksj"],
"deferred_to_later":
["sys_references_including_stdout", "stdout_io",
"any_method_beyond_to_string", "any_class_beyond_string"]}}
~~~

The first concrete development task. Work splits into eight steps, each
small, runnable, and observable on its own. Do them in order; don't
skip ahead. The point is to get from "Phase 0 done" to "the Aslan
acceptance tests pass" through a sequence that's hard to fail at.

The tactic is **inventory then fill gaps** — but with an important
caveat: the existing engine consumes a CaspianJ shape that **predates
the canonical [caspianj.md](../../caspian/caspianj.md) spec.** The Aslan
fixture (shown at the top of this page) is in the canonical form; the
existing interpreter currently isn't.

**Canon: the spec wins.** When `caspianj.md` and the existing
engine disagree, the spec is authoritative and the engine gets
brought into line. The format-alignment work is part of Aslan
scope, not a separate slice — Phase 1 doesn't end until the
interpreter consumes canonical CaspianJ. (Per the
`feedback_surface_conflicts` editorial policy: this is a specific
decision for this specific conflict, not a universal rule. Future
conflicts get surfaced and resolved case-by-case.)

The existing engine under `lib/lua/caspian/` has a
`json.lua`, `interpreter.lua`, and other modules with 172 passing
tests. The Aslan work is to (a) verify the JSON parser handles the
canonical form, (b) realign the CaspianJ-execution path to the
canonical statement shape `[receiver, method, args?]`, and (c)
complete enough of the executor to run `hello-world`. The Caspian
text path (`lexer.lua`, `parser.lua`, `transpiler.lua`) is Bree
work; when it lands, the transpiler must also emit canonical CaspianJ
so the source→runtime pipeline is end-to-end canonical.

<a id="step-1-run-the-existing-test-suite"></a>
### Step 1: Run the existing test suite

~~~json
{"vibecode": {"step": 1, "name": "baseline_existing_suite", "action":
"run_lua_tests_caspian_run_lua_from_project_root", "purpose":
"snapshot_pass_fail_count_before_changing_anything",
"not_a_goal": "making_all_existing_tests_pass_for_aslan"}}
~~~

Phase 0 verified the workbench. This is the first action against the
engine itself. From the project root:

```
lua tests/caspian/run.lua
```

The existing scaffolding includes lexer, parser, and transpiler tests
from earlier work. **We are not trying to make all of these pass for
Aslan.** Their purpose at this step is to establish a baseline:

- Does the test runner load and execute at all?
- What's the pass / fail count right now?
- Which tests fail, and roughly why?

Record the output somewhere casual (a scratch note, a paste into a
gist — doesn't need to be checked in). This is the "before" snapshot.

If the runner itself errors out before running any tests
(e.g., `module 'caspian.lexer' not found`), that's a `package.path`
problem and Phase 0 Step 0.3 is where you'll fix it.

<a id="step-2-inventory-the-engine-source"></a>
### Step 2: Inventory the engine source

~~~json
{"vibecode": {"step": 2, "name": "inventory", "actions":
["read_existing_json_lua", "read_existing_interpreter_lua",
"note_state_of_json_parser", "note_state_of_ksj_executor",
"confirm_text_side_modules_exist_as_scaffolding_only",
"identify_format_mismatches_against_canonical_caspianj_spec"],
"output": "state_of_engine_doc; gap_list_for_aslan; format_mismatch_list"}}
~~~

Open these files in your editor in this order:

| File | Why first |
|---|---|
| `tests/caspian/run.lua` | Confirms how `package.path` is set; that's how every test discovers the engine modules |
| `tests/caspian/support/runner.lua` | The test framework: `suite`, `test`, `report` |
| `tests/caspian/support/assert.lua` | The assertion helpers (`equal`, `is_nil`, `not_nil`, etc.) |
| `lib/lua/caspian/json.lua` | The JSON parser the engine will use to load `.caspj` files |
| `lib/lua/caspian/interpreter.lua` | The CaspianJ executor in whatever state it's currently in |

Read top-to-bottom, get a sense of:

- Does `json.lua` parse the JSON forms `hello-world.caspj` needs
  (top-level array, nested array, object with string keys, string values)?
  Does it export a `parse` function? What does it return for a nested
  JSON array?
- Does `interpreter.lua` accept a parsed CaspianJ tree and dispatch
  statements? Does it have a `run` (or `execute`, or similar) entry
  point? What does it expect as input?
- Does `support.runner` have any state we have to clear between test
  files (a global pass/fail counter, for instance)?

`lexer.lua`, `parser.lua`, and `transpiler.lua` are Caspian-text-side
concerns deferred to Bree. Confirm they exist as scaffolding; don't
trial them for Aslan.

**One thing to specifically look for:** the existing interpreter
consumes a **pre-spec CaspianJ format** (its own docstring notes this).
Concretely:

- Assignment is emitted as `["scope", "setvar", name, value]` — a
  four-element shape, not the canonical `[receiver, method, args?]`.
- BWC calls wrap their args in an extra `{"args": [...]}` layer
  rather than passing the positional expression directly.
- Other shapes may differ; only two paths have been checked.

The canonical form lives in
[caspianj.md](../../caspian/caspianj.md), and the Aslan fixture uses it.
**The spec wins** — when the interpreter and the spec disagree, the
interpreter is the thing that changes.

Output: a short list — "the JSON parser handles these forms / doesn't
handle these; the interpreter executes these CaspianJ shapes / doesn't
execute these; here are the exact format mismatches that need
realignment; this is what's needed to clear Aslan."

<a id="step-3-write-the-aslan-fixture"></a>
### Step 3: Write the fixture

~~~json
{"vibecode": {"step": 3, "name": "write_fixture", "fixture_path":
"tests/caspian/fixtures/hello_world.caspj", "fixture_content":
"[[{\"value\": \"hello\"}, \"to_string\"]]", "shape":
"outer_array_is_program_inner_array_is_one_statement_in_canonical_receiver_method_args_shape"}}
~~~

Create the file `tests/caspian/fixtures/hello_world.caspj`. Contents,
exactly:

```
[[{"value": "hello"}, "to_string"]]
```

One line, no trailing comment, no surrounding whitespace beyond the
final newline. This is the **entire input** for Aslan. The outer array
is the program (a list of statements); the inner array is one
statement in the canonical `[receiver, method, args?]` shape; the
receiver is the string literal `"hello"`; the method is `to_string`;
no args.

Verify the file is there:

```
cat tests/caspian/fixtures/hello_world.caspj
wc -l tests/caspian/fixtures/hello_world.caspj
```

Expected output: the literal JSON string, and `1` line.

<a id="step-4-first-sanity-test-parse-the-fixture"></a>
### Step 4: First sanity test — parse the fixture

~~~json
{"vibecode": {"step": 4, "name": "fixture_parse_test", "test_file":
"tests/caspian/aslan/test_fixture_parse.lua", "verifies":
"caspian_json_parses_the_fixture_into_expected_nested_table_shape",
"wires_into": "tests/caspian/run.lua_via_require_aslan_test_fixture_parse"}}
~~~

Create `tests/caspian/aslan/test_fixture_parse.lua`:

```lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("caspian.json")

runner.suite("v0.01 / fixture parse")

runner.test("parses the hello_world fixture", function()
    local f = assert(io.open("tests/caspian/fixtures/hello_world.caspj"))
    local source = f:read("*a")
    f:close()

    local parsed = json.parse(source)
    assert_.not_nil(parsed, "json.parse returned nil")
    assert_.equal(type(parsed), "table")

    -- The outermost array should hold exactly one statement.
    assert_.equal(#parsed, 1)
    -- That statement should itself be an array of [receiver, method].
    assert_.equal(type(parsed[1]), "table")
    assert_.equal(#parsed[1], 2)
end)
```

Wire it into the test runner. Open `tests/caspian/run.lua` and add:

```lua
require("aslan.test_fixture_parse")
```

…alongside the existing `require("lexer.test_literals")` etc. lines.

Run:

```
lua tests/caspian/run.lua
```

Expected: a dot for this test in the runner output, and a final
summary line showing one additional pass.

If `caspian.json`'s API doesn't match what the test assumes (different
function name, different return shape), this is where you discover it.
Update either the test or `caspian.json` as appropriate. Step 2's
inventory should have told you which.

<a id="step-5-wire-the-engine-entry-point"></a>
### Step 5: Wire the engine entry point

~~~json
{"vibecode": {"step": 5, "name": "engine_entry_point", "creates_or_evolves":
"lib/lua/caspian/init_lua_or_engine_lua", "exports":
"engine_dot_run_path_returns_parsed_tree_for_now",
"test_file": "tests/caspian/aslan/test_engine_run.lua"}}
~~~

In `lib/lua/caspian/`, create `engine.lua` (or evolve whatever
top-level entry already lives there) so that `require("caspian")`
returns a table with a `run` function:

```lua
local engine = {}
local json = require("caspian.json")

function engine.run(path)
    local f = assert(io.open(path))
    local source = f:read("*a")
    f:close()
    local tree = json.parse(source)

    -- TODO Steps 6-7: bootstrap roles + classes + state hash, then execute
    -- the parsed tree's statements, then return the last value.
    -- For now, return the parsed tree so we can confirm the load path
    -- works end-to-end before adding executor logic.
    return tree
end

return engine
```

If `lib/lua/caspian/init.lua` already exists and `caspian` is
already a module, integrate the `run` function there instead. The
import surface from the test side stays the same:

```lua
local engine = require("caspian")
```

Add `tests/caspian/aslan/test_engine_run.lua`:

```lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local engine = require("caspian")

runner.suite("v0.01 / engine.run")

runner.test("engine.run on the fixture returns a parsed tree", function()
    local result = engine.run("tests/caspian/fixtures/hello_world.caspj")
    assert_.not_nil(result)
    assert_.equal(type(result), "table")
    assert_.equal(#result, 1)
end)
```

Wire this into `tests/caspian/run.lua` the same way as Step 4.

Run the suite again. Expected: two new passing tests for Aslan plus
whatever was passing before.

<a id="step-6-fill-the-gaps"></a>
### Step 6: Fill the gaps

~~~json
{"vibecode": {"step": 6, "name": "fill_gaps", "scope":
"only_what_aslan_needs; not_full_ksj_spec",
"json_parser_forms": ["json_object", "json_array", "json_string",
"json_string_escapes_min"], "ksj_executor_forms":
["top_level_statement_list", "statement_call_dispatch_with_role_transition",
"value_literal_materialization_with_owning_role",
"top_level_returns_last_statement_value"], "role_forms":
["role_registry_init_with_user_and_stdlib",
"owning_role_slot_on_every_value", "role_transition_save_and_restore",
"chain_wipe_at_boundary_even_if_chain_is_empty_placeholder",
"role_system_method_returning_current_role"], "stdlib_forms":
["string_class_with_to_string_returning_self_owned_by_stdlib_role"]}}
~~~

The engine now loads, parses, and returns the parsed tree. **It
doesn't execute anything yet.** For each gap in the Step 2 inventory,
add only what Aslan needs. **Don't generalize ahead of the test.** The
required surface is tiny:

- Enough JSON parsing to read `[[{"value": "hello"}, "to_string"]]`.
- Enough CaspianJ execution to handle one top-level statement list,
  dispatch a single method call (with role transition), materialize a
  `value` literal with its owning-role tag, and return the last
  statement's value to the test harness.
- The role primitives from the [V1 cross-cutting principles](v1.md#cross-cutting-principles)
  section: a registry with `user` and the string-class role, an
  `owning_role` slot on every value, save/restore of role + chain at
  the boundary, the `%role` system method, and the `%chain` wipe even
  though chain is empty for Aslan.
- One stdlib piece: a minimal string class with `to_string` (the
  identity for strings) owned by the string-class role.

Anything beyond these — `sys` references like `%stdout`, real I/O, any
class beyond string, any method beyond `to_string` — is later work, not
this one's.

<a id="step-7-implementation-slices-in-order"></a>
### Step 7: Implementation slices in order

~~~json
{"vibecode": {"step": 7, "name": "implementation_slices", "order":
["bootstrap", "materialize", "lookup_method", "transition", "dispatch",
"format_alignment_for_rest_of_interpreter"], "acceptance":
"each_slice_one_test_one_implementation_one_commit",
"target": "engine_run_returns_a_value_whose_payload_is_hello"}}
~~~

To get from "parsed tree returned" to "TA.7 passes" (engine.run returns
a value whose payload equals `"hello"`), the next slices are:

| Candidate | What it does | Lines (rough) |
|---|---|---|
| `engine.bootstrap()` | Creates the role registry (`user` + `stdlib`) and the string class with `to_string` (owned by `stdlib`). Sets `engine.state` | ~40 |
| `engine.materialize(expr)` | Turns `{"value": "hello"}` into a value table `{type, owning_role, payload}` | ~20 |
| `engine.lookup_method(value, name)` | Finds `to_string` on the string class | ~15 |
| `engine.transition(new_role, fn)` | Save/restore the Skeletor state hash around a Lua function call | ~15 |
| `engine.dispatch(statement)` | Ties it all together: materialize receiver, look up method, transition if needed, call, restore. **Consumes canonical `[receiver, method, args?]` shape per [caspianj.md](../../caspian/caspianj.md)** — the existing interpreter's pre-spec shapes are deprecated by this work. | ~25 |
| Format alignment for the rest of the interpreter | Migrate the remaining statement-shape handlers (assignment, `if`/`elsif`/`else`, etc.) from the pre-spec format to canonical CaspianJ. Touches every dispatch path in `interpreter.lua`. Existing parser/transpiler tests still pass — they test the source-side, not the runtime format. Some interpreter-level tests may need to be added or rewritten. | varies |

Recommended order: `bootstrap` first (everything else needs the roles
and classes to exist), then `materialize`, then `lookup_method`, then
`transition`, then `dispatch`. After `dispatch` exists, hook it into
`engine.run` to actually execute each statement and return the last
result.

For each slice:

1. **Write the unit test first** under `tests/caspian/aslan/`, named
   `test_<slice>.lua`. The test plans in the
   [Phase 1 test plan](#phase-1-test-plan) below (TA.2 through TA.6)
   spell out what each one should assert.
2. **Implement the slice** in `lib/lua/caspian/engine.lua`
   (or its companions). Keep each implementation small — just enough
   to make the test pass.
3. **Run the suite.** Confirm the new test passes and nothing else
   broke.
4. **Commit.** One slice per commit makes the history readable.

<a id="step-8-verify-the-fixture-runs-end-to-end"></a>
### Step 8: Verify the fixture runs end-to-end

~~~json
{"vibecode": {"step": 8, "name": "verify", "actions":
["run_engine_run_on_fixture", "capture_last_statement_return_value",
"compare_to_expected_string_hello", "verify_role_transition_observed"],
"pass_condition":
"return_value_equals_hello_and_no_exception_raised_and_role_transition_observed",
"fail_condition":
"any_deviation; failure_message_should_name_which_layer_blocked"}}
~~~

Run `engine.run("tests/caspian/fixtures/hello_world.caspj")` via the
test harness, capture the last statement's return value, compare to
the string `"hello"`. Pass = exact match on return value plus no
exception. Fail = capture which layer blocked (JSON parse error?
statement dispatch failed? literal materialization failed? `to_string`
method missing? role transition botched? return-to-harness path
missing?). That layer is the next thing to fix; loop back to Step 7.

The slice loop ends when TA.7 (engine.run returns a value with payload
`"hello"`) passes. TA.8 (role transition observed during dispatch)
closes Aslan.

<a id="step-8-skeletor-snapshots"></a>
#### Skeletor snapshots during the run

The [Skeletor state hash](#data-structures-lua-tables) (`engine.state`)
at three moments during the `"hello".to_string` run. Aslan's hash only
holds `current_role` and `chain` — later slices grow the contents:

**After `engine.bootstrap()`, before any statement dispatches:**

```json
{
  "call_stack": [
    {
      "action":   "top_level",
      "role":   "user",
      "chain":  {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

**Mid-dispatch, inside the `to_string` method call (the cross-role
transition TA.8 verifies):**

```json
{
  "call_stack": [
    {
      "action":   "top_level",
      "role":   "user",
      "chain":  {"log": {}, "misc": {}},
      "locals": {}
    },
    {
      "action":          "method_call",
      "role":          "stdlib",
      "receiver_type": "string",
      "method":        "to_string",
      "chain":         {"log": {}, "misc": {}},
      "locals":        {}
    }
  ]
}
```

**After `to_string` returns, control back in the dispatcher:**

```json
{
  "call_stack": [
    {
      "action":   "top_level",
      "role":   "user",
      "chain":  {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

Each frame's `role` is a reference to a role object in `engine.roles`.
The role object in Aslan is minimal — just a `name` field — but
later slices grow it (trust webs, role-introspection state, etc.)
without changing the reference shape. The "current role" is the top
frame's `role`; the "current chain" is the top frame's `chain`. The
chain is an empty placeholder for Aslan — no chain operations
exercised. Working state (the receiver value being materialized, the
method function being called, the return value being passed back to
the harness) lives in Lua locals during dispatch, **not** in
`engine.state`, per [skeletor.md's working-state carve-out](../../caspian/skeletor/skeletor.md#v1-0-scope).

When Aslan passes, Bree (hello-world in Caspian source, via the
transpiler) is selected from the roadmap and planned in the same
step-by-step shape.

Phase 1 test coverage lives under [Testing](#testing) below.

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing",
"test_framework":
"project_existing_at_tests_caspian_support_runner_and_assert; do_not_invent_a_new_one",
"file_naming_convention":
"test_topic_dot_lua_matching_existing_lexer_parser_transpiler_files",
"phase_0_tests": ["TA.0.1", "TA.0.2", "TA.0.3", "TA.0.4", "TA.0.5", "TA.0.6"],
"phase_1_tests": ["TA.1", "TA.2", "TA.3", "TA.4", "TA.5", "TA.6",
"TA.7", "TA.8"],
"load_bearing_test":
"TA.8_role_transition_actually_observed_during_dispatch"}}
~~~

Aslan has fourteen tests total: six Phase 0 workbench checks plus
eight Phase 1 unit + integration tests. TA.8 is the load-bearing
role-system test — without it, role machinery could be missing
entirely and every other test would still pass.

<a id="phase-0-test-plan"></a>
### Phase 0 test plan

~~~json
{"vibecode": {"phase_0_tests":
[{"id": "TA.0.1", "verifies": "lua_5_4_installed", "tool":
"command_line_lua_dash_v", "framework": "none"}, {"id": "TA.0.2",
"verifies": "pure_lua_script_runs_and_prints", "tool":
"tests/sanity/lua_hello.lua", "framework": "none"}, {"id": "TA.0.3",
"verifies": "package_path_resolves_caspian_json_via_require",
"tool": "tests/sanity/test_package_path.lua", "framework":
"support_runner_and_assert"}, {"id": "TA.0.4", "verifies":
"existing_test_framework_reports_pass_fail_and_exit_code", "tool":
"tests/sanity/test_framework_sanity.lua", "framework":
"support_runner_and_assert"}, {"id": "TA.0.5", "verifies":
"caspian_json_parse_handles_simple_object", "tool":
"tests/sanity/test_json_parse.lua", "framework":
"support_runner_and_assert"}, {"id": "TA.0.6", "verifies":
"file_io_read_returns_expected_bytes", "tool":
"tests/sanity/test_file_read.lua", "framework":
"support_runner_and_assert"}]}}
~~~

TA.0.1 and TA.0.2 are pre-framework — Lua isn't even confirmed working
yet, so they can't depend on `support/runner.lua`. TA.0.3 onward use the
project's existing framework (`tests/caspian/support/runner.lua` +
`support/assert.lua`).

| ID | Verifies | Tool | Framework |
|---|---|---|---|
| TA.0.1 | Lua 5.4 installed | `lua -v` | none |
| TA.0.2 | Pure Lua script runs and prints | `tests/sanity/lua_hello.lua` | none |
| TA.0.3 | package.path resolves caspian modules | `tests/sanity/test_package_path.lua` | `support/runner` |
| TA.0.4 | Existing framework reports pass/fail | `tests/sanity/test_framework_sanity.lua` | `support/runner` |
| TA.0.5 | json.lua parses simple object | `tests/sanity/test_json_parse.lua` | `support/runner` |
| TA.0.6 | File I/O read returns expected bytes | `tests/sanity/test_file_read.lua` | `support/runner` |

All six must pass before Aslan phase 1 begins.

<a id="phase-1-test-plan"></a>
### Phase 1 test plan

~~~json
{"vibecode": {"phase_1_tests":
[{"id": "TA.1", "verifies":
"json_parse_handles_the_ksj_fixture_structure", "level": "unit"},
{"id": "TA.2", "verifies":
"engine_bootstrap_populates_roles_classes_state_hash", "level": "unit"},
{"id": "TA.3", "verifies":
"engine_materialize_wraps_literal_with_user_owning_role", "level": "unit"},
{"id": "TA.4", "verifies":
"engine_lookup_method_finds_to_string_on_string_class", "level": "unit"},
{"id": "TA.5", "verifies":
"engine_transition_pushes_and_pops_a_call_stack_frame", "level": "unit"},
{"id": "TA.6", "verifies":
"engine_dispatch_runs_one_statement_returns_string_value",
"level": "unit"}, {"id": "TA.7", "verifies":
"engine_run_on_fixture_file_returns_value_whose_payload_is_hello",
"level": "integration_end_to_end"}, {"id": "TA.8", "verifies":
"role_transition_actually_happened_during_dispatch", "level":
"unit_observability_check"}]}}
~~~

Seven unit tests plus one end-to-end integration test verify Phase 1.
Each test is a Lua file under `tests/caspian/aslan/` using the existing
project framework (`support.runner` + `support.assert`), required from
`tests/caspian/run.lua` (or a Aslan-specific entry point) and reported
through `runner.report()`.

Skeleton for a Aslan test file:

```lua
-- tests/caspian/aslan/test_bootstrap.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local engine = require("caspian")

runner.suite("v0.01 / bootstrap")

runner.test("populates the role registry with user and string-class roles", function()
    engine.bootstrap()
    assert_.not_nil(engine.roles.user)
    assert_.not_nil(engine.roles.stdlib)
end)

runner.test("populates the class registry with the string class", function()
    engine.bootstrap()
    assert_.not_nil(engine.classes.string)
    assert_.equal(type(engine.classes.string.methods.to_string), "function")
end)

runner.test("execution context starts in user role", function()
    engine.bootstrap()
    local top = engine.state.call_stack[#engine.state.call_stack]
    assert_.equal(top.role, engine.roles.user)
end)
```

Every test in the plan below follows this pattern.

| ID | Level | Verifies | How |
|---|---|---|---|
| TA.1 | unit | JSON parses the fixture | `json.parse('[[{"value": "hello"}, "to_string"]]')` returns the expected nested table |
| TA.2 | unit | bootstrap populates state | After `engine.bootstrap()`: `engine.roles.user` exists, `engine.classes.string` exists with `to_string` method, `engine.state.call_stack` has one frame with `role == engine.roles.user`, `action == "top_level"` |
| TA.3 | unit | materialize wraps literal | `engine.materialize({value = "hello"})` returns `{type = "string", payload = "hello", owning_role = engine.roles.user}` |
| TA.4 | unit | method lookup | `engine.lookup_method(string_value, "to_string")` returns a function |
| TA.5 | unit | transition push/pop | Call `engine.transition({action="method_call", role=engine.roles.stdlib}, function() return engine.state.call_stack[#engine.state.call_stack].role end)`; verify return == `engine.roles.stdlib` AND after the call `#engine.state.call_stack == 1` and the surviving frame's `role == engine.roles.user` |
| TA.6 | unit | dispatch one statement | `engine.dispatch({{value="hello"}, "to_string"})` returns a value with `payload == "hello"` |
| TA.7 | integration | full end-to-end | `engine.run("tests/caspian/fixtures/hello_world.caspj")` returns a value whose `payload == "hello"` |
| TA.8 | unit | transition observed | A spy in the `to_string` method records the top-of-stack frame's `role` at call time; assert it was `engine.roles.stdlib`, not `engine.roles.user` |

All eight pass = Aslan done.

<a id="test-layout"></a>
### Test layout

~~~json
{"vibecode": {"directory_layout": {"tests/sanity/":
"phase_0_workbench_sanity_tests_engine_independent",
"tests/caspian/fixtures/":
"ksj_and_text_fixtures_consumed_by_engine_or_tests",
"tests/caspian/aslan/":
"phase_1_unit_and_integration_tests_for_aslan",
"tests/caspian/run.lua":
"shared_entry_point_requires_all_test_modules_and_calls_runner_report",
"tests/caspian/support/":
"existing_runner_and_assert_modules_unchanged"}}}
~~~

The project uses its existing test framework — `tests/caspian/support/runner.lua`
(provides `suite`, `test`, `report`) and `tests/caspian/support/assert.lua`
(assertion helpers). No new framework gets invented for Aslan. File
naming follows the existing convention (`test_<topic>.lua`).

| Path | Contents |
|---|---|
| `tests/sanity/` | Phase 0 workbench tests (engine-independent) |
| `tests/caspian/fixtures/` | CaspianJ and text fixtures (e.g., `hello_world.caspj`, `_sanity_text.txt`) |
| `tests/caspian/aslan/` | Phase 1 unit and integration tests (Aslan-specific) |
| `tests/caspian/run.lua` | Entry point — extended to also require sanity + Aslan tests |
| `tests/caspian/support/` | Existing `runner.lua` and `assert.lua`, unchanged |

Existing scaffolding under `tests/caspian/lexer/`, `tests/caspian/parser/`,
and `tests/caspian/transpiler/` is Bree+ territory; not exercised by
Aslan directly but already uses the same framework so the patterns
above mirror what's there.
