# Development Plan

```
vibecode: {"doc": "development_plan", "status": "active", "current_version":
"0.01", "current_codename": "hello-world", "v001_scope_status":
"confirmed_2026-05-15", "feature_lock": "soft", "source_of_truth":
"vibecode_blocks"}
```

This file is the technical development plan for Kiera. Vibecode blocks are
the canonical source; surrounding prose is human-readable narrative derived
from them. When the two disagree, vibecode wins.

## Contents (Spock)

- [V0.01: "hello-world"](#v001-hello-world)
  - [Definition of done](#definition-of-done)
- [Testing strategy: two-tier approach](#testing-strategy-two-tier-approach)
  - [Bootstrap path](#bootstrap-path)
  - [One product named Bryton, not "bryton-lite"](#one-product-named-bryton-not-bryton-lite)
- [Feature soft-lock](#feature-soft-lock)
- [V1 scope (after 0.01)](#v1-scope-after-001)
- [Walking-skeleton roadmap](#walking-skeleton-roadmap)
- [Role system: baking from the start](#role-system-baking-from-the-start)
- [Engine startup and invocation](#engine-startup-and-invocation)
  - [Host vs. engine](#host-vs-engine)
  - [V0.01 invocation chain](#v001-invocation-chain)
  - [V0.01 engine bootstrap sequence](#v001-engine-bootstrap-sequence)
  - [Program model](#program-model)
  - [What user KSJ can see in V0.01](#what-user-ksj-can-see-in-v001)
  - [How later slices grow the lifecycle](#how-later-slices-grow-the-lifecycle)
- [Lua-side implementation sketch](#lua-side-implementation-sketch)
  - [Data structures (Lua tables)](#data-structures-lua-tables)
  - [Key procedures](#key-procedures)
  - [Pseudo-code skeleton](#pseudo-code-skeleton)
  - [Notes on the sketch](#notes-on-the-sketch)
- [V0.01 phase 0: Lua workbench](#v001-phase-0-lua-workbench)
  - [Step 0.1: Confirm Lua 5.4](#step-01-confirm-lua-54)
  - [Step 0.2: Run a sanity hello in pure Lua](#step-02-run-a-sanity-hello-in-pure-lua)
  - [Step 0.3: Verify package.path resolves engine modules](#step-03-verify-packagepath-resolves-engine-modules)
  - [Step 0.4: Verify the existing test framework](#step-04-verify-the-existing-test-framework)
  - [Step 0.5: Verify json.lua loads and parses](#step-05-verify-jsonlua-loads-and-parses)
  - [Step 0.6: Verify file reading](#step-06-verify-file-reading)
  - [Phase 0 test plan](#phase-0-test-plan)
- [V0.01 phase 1: hello-world in KScriptJSON](#v001-phase-1-hello-world-in-kscriptjson)
  - [Step 1: Inventory](#step-1-inventory)
  - [Step 2: Fill the gaps](#step-2-fill-the-gaps)
  - [Step 3: Verify](#step-3-verify)
  - [Phase 1 test plan](#phase-1-test-plan)
  - [Test layout](#test-layout)
- [V0.0X: KScript command-line execution](#v00x-kscript-command-line-execution)
  - [What the slice introduces](#what-the-slice-introduces)
  - [Permissions: default restrictive, opt-in via flags](#permissions-default-restrictive-opt-in-via-flags)
  - [Installation](#installation)
  - [Bryton interaction](#bryton-interaction)
  - [Open questions](#open-questions)
- [V0.1: Bryton](#v01-bryton)
  - [V0.1 prerequisites](#v01-prerequisites)
  - [V0.1 phase plan](#v01-phase-plan)
  - [V0.1 test layout](#v01-test-layout)
- [Methodology](#methodology)
- [Open](#open)

---

## V0.01: "hello-world" (Kirk)

```
vibecode: {"version": "0.01", "codename": "hello-world", "goal":
"execute a minimal kscriptjson program end_to_end and return a literal value to the test harness",
"medium": "kscriptjson_hand_written; not_kscript_source", "fixture":
"[[{\"value\": \"hello\"}, \"to_string\"]]", "expected_return": "hello",
"observation": "test_harness_captures_last_statement_value; no_stdout_io",
"covers": ["json_parser", "ksj_interpreter", "statement_dispatch",
"literal_materialization_with_owning_role", "method_dispatch_with_role_transition",
"string_class_minimum_with_to_string"], "deferred_to_later":
["kscript_text_parser", "transpiler", "stdout_io", "sys_references"]}
```

The first runnable version. A single `.ksj` file containing the KScriptJSON
encoding of "evaluate `"hello".to_string`" executes through the engine
under `code/kscript/lua/` and returns the string `"hello"` to the test
harness. No I/O — no stdout, no sinks beyond what the harness needs to
observe the return value.

KScript transpiles to KScriptJSON (KScriptJSON is the canonical runtime
format), so the engine consumes KScriptJSON, not KScript text. V0.01
hand-writes the KScriptJSON fixture and skips the transpiler entirely. The
KScript text parser, the transpiler, and `sys`-reference resolution
(`%stdout`, `%now`, etc.) are all deferred to later slices.

V0.01 is intentionally tiny. Every layer the engine actually needs to
execute a single method-call statement has to exist in skeleton form to
pass — JSON parser, statement dispatcher, method dispatch with role
transition, literal materialization with owning-role tag, the minimum
string class with `to_string` — but each layer can be minimal. The point
is to prove the engine integrates end-to-end before any single layer is
built out fully.

### Definition of done

```
vibecode: {"scope_status": "confirmed_2026-05-15", "done_criteria":
{"fixture_runs": "[[{\"value\": \"hello\"}, \"to_string\"]]_parses_and_executes",
"runs_under_a_role":
"program_executes_in_user_role; dispatch_transitions_to_string_class_role_and_back",
"has_a_string_class":
"minimum_built_in_string_class_with_to_string_returning_self; owned_by_engine_role",
"returns_hello":
"last_statement_return_value_equals_string_hello_observed_by_harness"}}
```

V0.01 is done when all four are true:

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

That's the entirety of V0.01. Soft feature lock applies — no additional
scope without explicit unlock.

---

## Testing strategy: two-tier approach (McCoy)

```
vibecode: {"section": "testing_strategy", "model": "two_tier",
"tier_1": {"name": "lua_side_tests", "scope":
"engine_internals_and_bryton_runner_itself", "framework":
"tests_kscript_support_runner_and_support_assert", "permanence":
"permanent_engine_is_in_lua_tests_live_in_lua_next_to_it"},
"tier_2": {"name": "bryton_tests", "scope":
"kscript_level_behavior", "framework":
"bryton_walks_directory_runs_each_file_aggregates_xeme",
"arrives": "v0.1"}, "pre_v01_bridge":
"lua_host_harness_calling_engine_run_kscript_test_and_asserting_on_return_value",
"no_bryton_lite_name":
"one_product_named_bryton_versioned_v01_minimum_v0X_grows_features",
"no_circularity":
"lua_independent_of_kscript_tier_1_self_contained;
bryton_depends_on_kscript_and_lua_but_is_tested_by_lua"}
```

Testing in Kiera operates on two tiers, each with its own tooling and
its own permanent home.

**Tier 1: Lua-side tests** — for the engine and other Lua-implemented
infrastructure (including the Bryton runner itself). Tests are Lua
files using the project's existing framework at
`tests/kscript/support/runner.lua` + `support/assert.lua`. **Tier 1 is
permanent** — the engine is implemented in Lua; tests of the engine
live in Lua next to the implementation.

**Tier 2: Bryton tests** — for KScript-level behavior. Tests are
`.kscript` files that emit Xeme JSON; the Bryton runner walks a
directory of them and aggregates results. Tier 2 arrives at
[V0.1](#v01-bryton). Before V0.1, KScript-level behavior is tested via
**Lua-host harnesses** that invoke `engine.run("test.kscript")` and
assert on the return value — a manual proto-Bryton in Tier 1 form.

The boundary stays sharp:

- **Bryton tests the language.** Does `for` terminate correctly? Do
  hashes preserve insertion order? Does `%role` return the right role
  inside a cross-role call? These are tests of KScript's behavior —
  written in KScript, run by Bryton.
- **Lua tests the implementation.** Does the lexer produce the right
  tokens? Does the dispatcher transition roles correctly? Does the
  engine return the last-statement value to its host? These are tests
  of the engine — written in Lua, run by `support/runner.lua`.

Engine tests never migrate to Bryton. The Bryton runner itself is a
Tier 1 thing — written in Lua, tested in Lua. Once Bryton works
(its V0.1 acceptance tests pass under Tier 1), it becomes the tool
for Tier 2.

### Bootstrap path

| Phase | Engine tests | KScript-behavior tests | Bryton tests |
|---|---|---|---|
| V0.01 | Lua-side (`support/runner.lua`) | — (no KScript text execution yet) | — |
| V0.02 → V0.0X | Lua-side | Lua-host harness calling `engine.run("X.kscript")` | — |
| V0.1 | Lua-side | (migration begins) | Bryton tests: `.kscript` files emitting Xeme |
| V0.1+ | Lua-side (forever) | (mostly migrated) | Bryton (primary) |

**No circularity.** Lua is independent of KScript; Tier 1 tests
are trustworthy from day one. Bryton depends on KScript (it runs
KScript test files) and on Lua (its V0.1 runner is in Lua), but is
itself tested by Lua. There's no spot where "testing X requires X
to already work."

### One product named Bryton, not "bryton-lite"

V0.1 Bryton (Lua-implemented, strict feature subset) and an eventual
KScript-hosted Bryton are the same product at different stages, not
distinct tools. Same purpose, same Xeme contract, same
directory-walking model. The implementation language (Lua → KScript)
is an internal detail. Versioning the feature set is enough —
re-branding would create a docs tax and an implication that "lite"
means "less correct." Same shape as `gcc` 1.0 vs `gcc` 14: same
compiler, different stage.

---

## Feature soft-lock (Scotty)

```
vibecode: {"lock": "soft", "scope": "all_kiera_features", "rationale":
"prevent design accretion during implementation; defer non-essential work to V2+",
"override": "explicit; via deliberate decision, not casual addition",
"companion_to": ["no_bolt_on_additions"]}
```

A soft lock is in place on new features. Anything not already specced as V1
is deferred until needed. The lock can be broken — but only deliberately,
never casually. Companion discipline to `no-bolt-on-additions`: that rule
guards spec quality; this lock guards build momentum.

---

## V1 scope (after 0.01)

```
vibecode: {"v1_in": ["kscript", "kscript_cli", "mikobase", "touchstone",
"sinatra", "trivet", "uma", "bryton", "jasmine", "kiera_identity",
"deployment"], "v1_out": ["robinson"], "v1_blockchain_role":
"external_service; kscript_client_is_thin_http", "v1_http_path":
"sinatra_explicit_handlers", "v1_authn": "signed_request", "v1_authz":
"handler_implements_directly; no_declarative_role_policy"}
```

V1 ships Kiera.uno as a deployable service. The HTTP layer that ships with
V1 is Sinatra (built on Touchstone); the V1 HTTP path is Sinatra-style
explicit handlers. **Robinson** (the filesystem-tree page-server) is **not
bundled with V1** — it's a library resolved through Kiera on demand, so it
can land on its own timeline without blocking V1. Programs that don't use
Robinson never pull it in; programs that want it call
`%['kiera.uno/robinson']` and Kiera fetches and caches it on first use.

Authentication is signed-request based; authorization is whatever the handler
implements directly.

The blockchain is treated as an external service. KScript's blockchain
involvement is a thin HTTP client (~20 lines) that calls the blockchain API
for signature verification, key lookups, etc. The chain itself runs as
separate infrastructure (the existing Python `blockchain/sim/` evolved to
production).

---

## Walking-skeleton roadmap (Sulu)

```
vibecode: {"approach": "walking_skeleton", "principle":
"each_phase_runnable_end_to_end; expand_outward_feature_by_feature", "phases":
[{"v": "0.01", "name": "hello_world_ksj", "proves":
"json_parser; ksj_interpreter; stdlib_minimum"}, {"v": "0.02", "name":
"hello_world_kscript", "proves":
"kscript_text_parser; transpiler_to_ksj; round_trip"}, {"v": "0.0X",
"name": "kscript_stdout_and_hashes_and_json_serialization", "proves":
"sys_references; stdout_sink; hash_class; json_serialize_method"},
{"v": "0.0X", "name": "kscript_cli", "proves":
"os_executable_kscript_files; shebang_support; permission_flag_machinery_with_default_restrictive_posture"},
{"v": "0.1", "name": "bryton", "proves":
"first_usable_test_framework_for_kscript_code; runner_walks_dir_and_aggregates_xemes"},
{"v": "0.0X", "name": "first_http_response", "proves":
"sinatra_routing; handler_chain; response_object"}, {"v": "0.0X", "name":
"first_db_read", "proves": "mikobase_client; data_flow"}, {"v": "0.0X",
"name": "first_uma_response", "proves":
"trivet; uma; body_handle_to_string"}, {"v": "0.0X", "name":
"first_signed_request", "proves":
"kiera_identity; blockchain_api_client"}, {"v": "0.0X", "name":
"first_deployment", "proves": "kiera_uno_hosting; ops"}, {"v": "0.0X",
"name": "first_hosted_service", "proves":
"service_on_stack_pattern"}], "continuous_threads": ["jasmine"]}
```

Development proceeds in vertical slices. Each slice is a runnable end-to-end
demo proving a thin band of the stack. The order follows dependencies —
earlier slices unblock later ones. Bryton (tests) and Jasmine (logs) are
continuous threads, used from V0.01 onward.

V0.01 (hello-world in KScriptJSON) and V0.02 (hello-world in KScript
source, via the new transpiler) bracket the engine's bootstrapping.
**V0.1 is the first named user-facing milestone — Bryton.** It arrives
after a handful of V0.0X engine-feature slices (stdout, hashes, JSON
serialization) that Bryton needs as prerequisites. Beyond V0.1, slice
numbers are assigned when the prior is green.

Bryton is no longer listed as a continuous thread — it's a discrete
V0.1 deliverable. Jasmine (logging) remains a continuous thread,
used wherever a layer needs to surface diagnostic output.

---

## Role system: baking from the start (Chekov)

```
vibecode: {"principle": "roles_are_core_not_bolt_on", "reason":
"every_value_must_be_role_tagged_from_creation; retrofit_touches_every_value_creation_path_and_every_method_call_path",
"applies_from": "v001", "spec_doc": "documentation/roles.md",
"v001_primitives": ["role_registry", "owning_role_on_every_value",
"role_transition_on_method_call", "role_system_method",
"chain_wipe_on_cross_role_call"], "v001_deferred": ["faucets", "jails",
"cross_role_trust_declarations", "alarms_with_sink_side_checks",
"source_side_propagation", "chain_isolate_developer_facing"]}
```

Roles are not a bolt-on to KScript — they are part of the engine's core
architecture from V0.01 onward. The role spec lives in
[roles.md](../kscript/roles.md); this section is the implementation plan for layering
it in incrementally.

**Why roles cannot be deferred.** Every value in the runtime needs an
owning-role tag at creation; every method call needs to check the
receiver's role and transition. Both are pervasive concerns — adding them
later means touching every value-creation path and every method-call path.
Easier to bake the primitives in from the first slice and grow outward.

**V0.01 role footprint.** The minimum to support hello-world's single
cross-role call (`user` → string-class role → `user`):

```
vibecode: {"v001_role_footprint": {"registry_entries_min":
["user", "string_class_role_name_tbd"], "value_layer":
"every_value_carries_owning_role_slot_immutable_after_creation",
"dispatcher_layer":
"on_method_call_compare_method_owning_role_to_current; if_differ_save_state_set_new_role_wipe_chain_run_restore",
"sys_methods_implemented": ["role"], "chain_state":
"empty_placeholder_but_wipeable_on_boundary"}}
```

- **Role registry.** Engine maintains a name → role-object map.
  Populated at startup with `user` and the engine role owning the
  built-in string class (and any other built-in classes V0.01 touches).
  Per [roles.md](../kscript/roles.md), the broader minimum is `user`, `clock`,
  `randomizer`, `utils`; V0.01 needs only what it actually exercises.
  The others arrive as their values get wired up in later slices.
- **Owning role on every value.** Each value carries an `owning_role`
  slot, set at creation, immutable thereafter.
- **Role transition in the dispatcher.** Method dispatch compares the
  method-object's owning role to the current role. If different: save
  current role + chain, set new role, wipe chain, execute, restore.
- **`%role` system method.** Returns the current role.
- **`%chain` wipe at boundaries.** Even if `%chain` is just an empty
  placeholder in V0.01 (hello-world uses no chain entries), the wipe
  machinery is in place so later slices add chain entries without
  retrofitting boundary behavior.

**Role-system growth path:**

```
vibecode: {"growth_path": [{"slice": "v0.01", "adds":
"core_primitives_registry_owning_role_transition_role_chain_wipe"},
{"slice": "v0.02", "adds":
"transpiler_role; ksj_emitted_tagged_with_caller_role"}, {"slice":
"first_http", "adds":
"network_faucet_role; request_body_values_inherit_faucet_role"},
{"slice": "first_db", "adds":
"per_mikobase_instance_role; rows_inherit_db_role"}, {"slice":
"first_uma", "adds": "no_new_role_primitives; uma_objects_user_owned"},
{"slice": "first_signed_request", "adds":
"identity_faucet_role; trust_mechanism_scaffolding"}, {"slice":
"first_deployment", "adds":
"no_new_role_primitives; deployment_context_may_add_engine_roles"},
{"slice": "first_hosted_service", "adds":
"per_tenant_roles_tbd; cross_role_trust_mechanics_tbd"}],
"feature_arrival_triggers": {"jails":
"when_first_slice_has_values_worth_narrowing", "cross_role_trust_declarations":
"when_first_slice_needs_to_grant_trust", "alarms_vs_exceptions":
"when_first_slice_has_sinks_that_must_hard_stop", "source_side_propagation":
"when_string_provenance_question_settles"}}
```

| Slice | Role additions |
|---|---|
| V0.01 | Core: registry, `owning_role` on values, transition-on-call, `%role`, `%chain` wipe |
| V0.02 | Transpiler role; emitted KScriptJSON tagged with caller role |
| First HTTP | Network faucet role; request-body values inherit it |
| First DB | Per-Mikobase-instance role; rows inherit it |
| First Uma | No new role primitives; Uma objects are user-owned by default |
| First signed request | Identity faucet role; trust-mechanism scaffolding |
| First deployment | No new role primitives; deployment context may add engine roles |
| First hosted service | Per-tenant roles (TBD); cross-role-trust mechanics (TBD) |

Jails arrive when a slice has values worth narrowing. Cross-role trust
declarations arrive when a slice needs to grant trust. Alarms (vs.
regular exceptions) arrive when a slice has sinks that must hard-stop.
Source-side propagation is deferred until the
[string-provenance question](../kscript/roles.md#open-questions) settles.

**Hello-world's role behavior end-to-end.** Program starts in role
`user`. The fixture materializes the literal `"hello"` — a string value
owned by `user` (created by user-role code). Method dispatch on
`to_string`: the method lives on the built-in string class, owned by an
engine role. Receiver-method-owning-role differs from current →
transition. Wipe (empty) chain, set current role to the string-class
role, execute `to_string` (which returns the receiver, since a string's
`to_string` is identity), restore current role to `user`. The returned
value's owning role is the receiver's (user-owned); the test harness
captures it. This proves the role-transition machinery at the smallest
possible scale; every later slice exercises more of the model.

---

## Engine startup and invocation (Chapel)

```
vibecode: {"section": "engine_startup_and_invocation", "scope":
"how_a_ksj_program_actually_runs_from_invocation_through_return",
"applies_from": "v001", "covers": ["host_vs_engine_distinction",
"invocation_chain", "bootstrap_sequence", "program_model",
"what_user_ksj_can_see", "how_later_slices_extend"]}
```

This section spells out the lifecycle of a KSJ run end-to-end: who
launches it, what the engine does before user code executes, what user
code can actually reference, and how that lifecycle grows in later
slices. It answers two related questions that came up while scoping
V0.01: **how do you start a KSJ script** and **how does the engine load
allowed objects into the outermost KSJ block**.

### Host vs. engine

```
vibecode: {"host_vs_engine": {"engine":
"the_library_that_runs_ksj; located_under_code_kscript_lua",
"host": "anything_that_calls_into_the_engine; varies_by_slice",
"v001_host": "lua_test_runner_invoked_from_command_line",
"later_hosts": ["standalone_cli_via_v00x_kscript_cli_slice",
"sinatra_request_handler_v003_plus",
"one_running_ksj_calling_another_via_function_dispatch"]}}
```

The **engine** is the Lua library at `code/kscript/lua/` that knows how
to parse and execute KSJ. The **host** is whatever calls into the
engine. They are different layers.

In V0.01 the host is a Lua test runner invoked from the command line.
Later hosts include the standalone `kscript` CLI (arrives in the
[V0.0X kscript-cli slice](#v00x-kscript-command-line-execution),
prerequisite for V0.1 Bryton), a Sinatra request handler (at the
first-HTTP slice — every handler closure is itself KSJ that the engine
runs in response to a request), and one piece of running KSJ calling
another (which emerges from normal function dispatch, no separate
engine API needed). Each host invokes the same `engine.run()` entry
point; what differs is who triggers it and what they pass in.

### V0.01 invocation chain

```
vibecode: {"v001_invocation_chain": [{"step": 1, "name":
"command_line_invocation", "example":
"lua tests/kscript/run.lua tests/kscript/fixtures/hello_world.ksj"},
{"step": 2, "name": "runner_loads_engine_as_lua_library",
"example": "local engine = require(\"kscript\")"}, {"step": 3,
"name": "runner_calls_engine_run_with_file_path", "example":
"local result = engine.run(\"tests/kscript/fixtures/hello_world.ksj\")"},
{"step": 4, "name": "engine_bootstrap_then_parse_then_execute",
"covered_in_next_subsection": true}, {"step": 5, "name":
"engine_returns_last_statement_value_to_runner_as_lua_value"},
{"step": 6, "name":
"runner_compares_to_expected_string_hello_and_reports_pass_or_fail"}]}
```

Top-level shape:

1. **Command-line invocation.** Something like
   `lua tests/kscript/run.lua tests/kscript/fixtures/hello_world.ksj`.
2. **Runner loads the engine as a Lua library.** Roughly
   `local engine = require("kscript")`.
3. **Runner calls `engine.run()` with the fixture path.** Roughly
   `local result = engine.run("...fixtures/hello_world.ksj")`.
4. **Engine bootstrap, parse, and execute happen behind that one
   call.** Detailed below.
5. **Engine returns the last statement's value to the runner** as a Lua
   return value.
6. **Runner compares to expected `"hello"`** and reports PASS or FAIL.

### V0.01 engine bootstrap sequence

```
vibecode: {"v001_bootstrap_sequence": [{"step": 1, "name":
"create_role_registry", "creates": ["user", "string_class_role"],
"role_object_v001":
"name_only_no_methods_no_state_no_trust_web"}, {"step": 2, "name":
"create_built_in_string_class", "creates":
"string_class_object_with_one_method_to_string_returning_self",
"tagged_with": "string_class_role"}, {"step": 3, "name":
"establish_execution_context", "sets":
{"current_role": "user", "chain": "empty_placeholder"}}, {"step":
4, "name": "load_and_parse_ksj_file", "uses": "json_parser",
"produces": "parsed_ksj_tree"}, {"step": 5, "name":
"execute_top_level_statements", "iterates":
"each_statement_in_top_level_array_of_parsed_tree", "captures":
"last_statement_return_value"}, {"step": 6, "name":
"return_to_host", "returns": "captured_last_value_as_lua_value"}]}
```

What happens between `engine.run(path)` being called and the result
coming back:

1. **Create the role registry.** A small map of role-name → role-object.
   V0.01 needs two roles: `user` (what the program runs as) and the
   string-class role (provisional name TBD; owns the built-in string
   class). Role objects in V0.01 are barely more than identity tags —
   they have a name and nothing else. Cross-role trust,
   role-introspection, role nicknames are all later.

2. **Create the built-in string class.** The engine constructs the
   string class object — internally a class-registry entry with one
   method, `to_string`, whose implementation is "return the receiver."
   The class is tagged with the string-class role as its owner; the
   method-object inherits that owner.

3. **Establish the execution context.** Two pieces of state:
   `current_role` is set to `user`, `chain` is the empty placeholder.
   From this point forward, every value created counts as user-owned
   (current role is `user`); every method call goes through the
   dispatcher.

4. **Load and parse the KSJ file.** The engine reads the path it was
   handed, gives the text to the JSON parser, gets back a parsed tree.
   For V0.01 the tree is `[[{"value": "hello"}, "to_string"]]`.

5. **Execute top-level statements.** The engine iterates the outermost
   array. For each statement, it calls the statement dispatcher; the
   dispatcher handles literal materialization, method lookup, role
   transition, and method execution. Each statement's return value is
   captured; the last one is what gets surfaced.

6. **Return to host.** The captured last-value is returned to the host
   (in V0.01, the Lua test runner) as a Lua return value.

### Program model

```
vibecode: {"program_model_v001": {"shape":
"top_level_array_of_statements", "entry_point":
"the_outermost_array_itself_no_main_function",
"result_of_program":
"value_of_last_top_level_statement", "execution":
"statements_run_in_order"}}
```

A KSJ program is a **top-level array of statements**. The engine
executes them in order. The "result" of the program is the value of
the last top-level statement. There is no `main` function and no
entry-point declaration — the outermost array IS the entry point.

Statements can define functions and call them, but for V0.01 the
program is just one statement.

### What user KSJ can see in V0.01

```
vibecode: {"v001_visibility": {"directly_referenceable_by_name":
"nothing", "implicitly_available":
["string_class_via_literal_materialization",
"to_string_via_method_dispatch_on_string_values"],
"explicitly_unavailable_v001":
["sys_references_percent_stdout_percent_role_etc",
"other_built_in_classes_integer_hash_array",
"faucets", "jails", "trust_declarations"]}}
```

The V0.01 fixture doesn't reference any object by name. It only:

- Materializes a string literal (`{"value": "hello"}`) — the engine's
  literal-materializer knows about the string class and tags the new
  value with that class.
- Calls a method on the value (`"to_string"`) — the dispatcher looks
  up the method on the receiver's class.

The string class is **not exposed as a named object** in V0.01. It's
**discovered** by the dispatcher when a method call lands on a string
value. This is the simplest possible answer to "how do allowed objects
get loaded into the outermost KSJ block": in V0.01, they don't get
loaded explicitly at all — they're available only through the
dispatcher's class-lookup mechanism for values the engine itself
created.

### How later slices grow the lifecycle

```
vibecode: {"growth_path": {"v002": {"bootstrap_change":
"none; transpiler_runs_before_engine_invoked",
"invocation_change":
"runner_may_optionally_transpile_kscript_text_to_ksj_before_engine_run; engine_still_consumes_ksj"},
"first_http": {"new_host": "sinatra_request_handler",
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
"engine_capability_allow_list_for_running_untrusted_code"}
```

V0.02 (transpiler) doesn't change the bootstrap sequence — the
transpiler runs before the engine is invoked (probably as a runner-side
step that turns `.kscript` text into KSJ), and the engine consumes the
KSJ exactly as in V0.01.

Later slices extend the lifecycle in these ways:

- **New hosts.** The first HTTP slice introduces a Sinatra request
  handler as a host: an incoming request triggers a handler closure
  (itself KSJ) to execute. Same `engine.run()`-shaped entry; the
  caller is different.
- **Sys references** (`%stdout`, `%now`, `%role`, `%kiera`, etc.). The
  engine pre-populates a sys-reference table during bootstrap; user
  code reaches the objects via `{"sys": "name"}`. Each sys-referenced
  object is tagged with its owning engine role.
- **More built-in classes** (integer, hash, array, etc.). Each gets
  added to the class registry and tagged with an engine role. Same
  discovery model as string: the dispatcher finds the class when a
  method call lands on a value of that type.
- **Faucets.** Each faucet (filesystem dirjail, network client, db
  connection, stdin, env, cli-args) gets registered with its own role
  during bootstrap. Objects pulled through inherit the faucet's role.

The bigger open question — **how the engine decides which capabilities
a particular invocation gets** — is V1 work, not V0.01. The shape is
still TBD. Likely candidates: engine-config-driven (the deployer
specifies which built-ins and faucets a given KScript instance can
access); role-driven (a role's trust web determines what it can see).
This is core to "running untrusted code" — the engine must be able to
launch a KScript instance with a restricted surface that the running
code cannot escape. Flagged as an open item.

---

## Lua-side implementation sketch (Rand)

```
vibecode: {"section": "lua_implementation_sketch", "status":
"candidate_shape; to_be_reconciled_with_existing_code_during_inventory",
"language": "lua_5_4_assumed", "style":
"plain_tables_no_metatables_for_v001; closures_for_role_transition_save_restore",
"deliberately_not_specified":
["module_layout_within_code_kscript_lua_kscript_directory",
"naming_conventions_for_internal_locals",
"exact_signature_of_existing_json_lua"]}
```

This section sketches the engine's internal Lua shape for V0.01: data
structures, key procedures, and a pseudo-code skeleton. It is a
**candidate target** to be reconciled with what's already in
`code/kscript/lua/kscript/` during Step 1 (inventory) of Phase 1. Where
existing code already does something workable, use it; where it
doesn't, the shapes below are the proposal.

### Data structures (Lua tables)

```
vibecode: {"data_structures": {"role_object":
"{name = string}", "role_registry":
"engine.roles = {[name] = role_object, ...}", "value":
"{type = string, owning_role = role_object, payload = any_lua_value}",
"class_object":
"{name = string, owning_role = role_object, methods = {[name] = lua_function}}",
"class_registry": "engine.classes = {[name] = class_object, ...}",
"execution_context":
"{current_role = role_object, chain = lua_table_placeholder}"}}
```

Every internal object is a plain Lua table — no metatables in V0.01.
References between tables are Lua's normal table-reference semantics
(passing a table around shares the same memory; assignment copies the
reference, not the contents).

- **Role object.** Minimal in V0.01:
  ```lua
  { name = "user" }
  ```
  Later slices will add trust webs, role-introspection state, etc.

- **Role registry.** A flat table mapping role-name to role-object:
  ```lua
  engine.roles = {
      user         = { name = "user" },
      string_class = { name = "string_class_role" },  -- name TBD
  }
  ```

- **Value.** Every KSJ value the runtime holds is a Lua table with
  three fields:
  ```lua
  { type = "string", owning_role = engine.roles.user, payload = "hello" }
  ```
  The `owning_role` field is a *reference* to one of the role objects
  in `engine.roles` — same Lua table, shared. Once set, it's never
  reassigned (immutable per [roles.md](../kscript/roles.md)).

- **Class object.** Holds methods as a sub-table of Lua functions:
  ```lua
  {
      name = "string",
      owning_role = engine.roles.string_class,
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

- **Execution context.** One table that holds the current role and
  current chain:
  ```lua
  engine.ctx = {
      current_role = engine.roles.user,
      chain        = {},  -- empty placeholder for V0.01
  }
  ```
  This is the mutable runtime state. Cross-role transitions save and
  restore this table's fields via Lua locals (closures), not via a
  separate stack data structure — Lua's own call stack does the work.

### Key procedures

```
vibecode: {"procedures": {"engine.run":
"(path) -> last_statement_value; entry_point",
"engine.bootstrap":
"() -> nil; populates_roles_classes_ctx", "engine.dispatch":
"(statement) -> value; handles_one_top_level_statement",
"engine.materialize": "(expr) -> value; turns_ksj_expression_into_value",
"engine.transition":
"(new_role, fn) -> result; save_restore_ctx_around_fn_call",
"engine.lookup_method": "(value, method_name) -> method_fn"}}
```

Five procedures cover V0.01:

- `engine.run(path)` — entry point called by the host.
- `engine.bootstrap()` — populates the role registry, class registry,
  and execution context. Runs once per `engine.run` invocation.
- `engine.dispatch(statement)` — handles one parsed statement (the
  `[receiver, method, args?]` triple).
- `engine.materialize(expr)` — turns a KSJ expression
  (`{"value": ...}`, etc.) into a value table with `owning_role` tag.
- `engine.transition(new_role, fn)` — wraps a Lua function call with
  save/restore of `engine.ctx`. Uses Lua's call stack via closures;
  no explicit transition stack needed.
- `engine.lookup_method(value, method_name)` — finds the method
  function on the value's class. Looks up the class via `value.type`
  in `engine.classes`, then the method name in `class.methods`.

### Pseudo-code skeleton

```
vibecode: {"pseudo_code_status":
"illustrative_target_shape; not_committed_until_reconciled_with_existing_engine"}
```

```lua
local engine = {}
local json = require("kscript.json")     -- existing json.lua

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
        string_class = { name = "string_class_role" },
    }
    engine.classes = {
        string = {
            name = "string",
            owning_role = engine.roles.string_class,
            methods = {
                to_string = function(receiver, args)
                    return receiver       -- identity on a string
                end,
            },
        },
    }
    engine.ctx = {
        current_role = engine.roles.user,
        chain        = {},
    }
end

function engine.dispatch(statement)
    local receiver = engine.materialize(statement[1])
    local method_name = statement[2]
    local args = statement[3]            -- may be nil
    local method_fn = engine.lookup_method(receiver, method_name)
    local class = engine.classes[receiver.type]
    local target_role = class.owning_role
    if target_role ~= engine.ctx.current_role then
        return engine.transition(target_role, function()
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
            owning_role  = engine.ctx.current_role,
            payload      = expr.value,
        }
    end
    -- {var:...}, {sys:...}, {function:...}, etc. -- all later slices
    error("unsupported expression form in V0.01: " ..
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

function engine.transition(new_role, fn)
    local saved_role  = engine.ctx.current_role
    local saved_chain = engine.ctx.chain
    engine.ctx.current_role = new_role
    engine.ctx.chain        = {}            -- wipe at boundary
    local result = fn()
    engine.ctx.current_role = saved_role
    engine.ctx.chain        = saved_chain
    return result
end

return engine
```

### Notes on the sketch

```
vibecode: {"sketch_notes": ["plain_tables_only_no_metatables_v001",
"role_objects_shared_by_reference_across_owning_role_fields",
"transition_uses_lua_call_stack_via_closure_no_explicit_transition_stack",
"chain_is_initialized_to_empty_table_wipe_means_replace_with_fresh_table",
"errors_use_lua_error_for_v001_no_kscript_exception_machinery_yet",
"json_parse_assumed_to_return_nested_lua_tables_arrays_indexed_from_1"]}
```

A few specifics worth flagging:

- **No metatables in V0.01.** Plain tables. Metatable-based dispatch
  is a later optimization (or never — the current explicit lookup is
  perfectly clear).
- **Role objects are shared by reference.** When ten values all sit
  under role `user`, they all point at the *same* Lua table
  (`engine.roles.user`). Identity comparison (`a.owning_role == b.owning_role`)
  is constant-time.
- **No explicit transition stack.** The save/restore lives in Lua
  locals inside `engine.transition`. Lua's own call stack handles
  nesting. If `fn()` itself triggers another transition, that nests
  naturally via another Lua call frame.
- **Chain wipe = replace, not clear.** `engine.ctx.chain = {}` creates
  a fresh empty table; the caller's saved-chain reference still points
  to the original. On restore, the original is reattached. Safe.
- **Errors use Lua `error()` for V0.01.** KScript-level exception
  machinery (alarms vs. regular exceptions per [roles.md](../kscript/roles.md))
  lands in a later slice. For V0.01, anything wrong = engine bails
  with a Lua error.
- **JSON parser is assumed to return nested Lua tables**, arrays as
  arrays indexed from 1 (Lua-standard). To be confirmed during Step 1
  inventory of the existing `json.lua`.

---

## V0.01 phase 0: Lua workbench (Pike)

```
vibecode: {"phase": 0, "version": "0.01", "purpose":
"set_up_and_verify_lua_dev_environment_before_writing_any_engine_code",
"explicitly_excludes": "executing_kscript_or_ksj; only_lua_level_sanity",
"steps_count": 6, "acceptance":
"all_six_workbench_steps_pass; no_engine_code_written", "tactic":
"verify_the_workbench_before_building_in_it"}
```

Before writing any engine code, the Lua-side development environment
has to be verified. Six steps, each independently runnable. If a step
fails, fix that before moving on. **No KScript or KSJ execution
happens in Phase 0** — this is purely Lua-level sanity.

### Step 0.1: Confirm Lua 5.4

```
vibecode: {"step": "0.1", "name": "confirm_lua_5_4", "action":
"run_lua_dash_v_from_project_root", "expected_stdout_contains":
"Lua_5_4", "remedy_if_fail": "install_lua_5_4"}
```

`lua -v` from the project root. Expected: a line containing `Lua 5.4`.
If a different major version is installed, install Lua 5.4 before
proceeding.

### Step 0.2: Run a sanity hello in pure Lua

```
vibecode: {"step": "0.2", "name": "lua_hello",
"fixture_path": "tests/sanity/lua_hello.lua", "fixture_content":
"print(\"hello from lua\")\n", "run":
"lua tests/sanity/lua_hello.lua", "expected_stdout":
"hello from lua\\n", "expected_exit_code": 0}
```

Create `tests/sanity/lua_hello.lua`:

```lua
print("hello from lua")
```

Run: `lua tests/sanity/lua_hello.lua`. Expected stdout: `hello from lua`
followed by a newline. Exit code 0.

### Step 0.3: Verify package.path resolves engine modules

```
vibecode: {"step": "0.3", "name": "package_path_check", "action":
"set_package_path_prefix_to_code_kscript_lua; require_a_known_engine_module_no_error",
"expected": "require_call_returns_a_table_without_error"}
```

The engine lives under `code/kscript/lua/`. Lua needs to find modules
when `require("kscript.X")` is called. The convention:

```lua
package.path = "code/kscript/lua/?.lua;" .. package.path
```

Verify with a real existing engine module — `kscript.json` is the
natural choice since it's already in the tree:

The existing `tests/kscript/run.lua` already sets up `package.path` to
resolve both `code/kscript/lua/?.lua` (engine modules) and
`tests/kscript/?.lua` (test-side modules including `support.runner`).
If launching tests from a different entry point, mirror that setup.

A small sanity test exercising the path:

```lua
-- tests/sanity/test_package_path.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("kscript.json")

runner.suite("sanity / package path")

runner.test("kscript.json loaded as a table", function()
    assert_.equal(type(json), "table")
end)
```

### Step 0.4: Verify the existing test framework

```
vibecode: {"step": "0.4", "name": "verify_existing_test_framework",
"existing_runner_module": "tests/kscript/support/runner.lua",
"existing_assert_module": "tests/kscript/support/assert.lua",
"existing_entry_point": "tests/kscript/run.lua",
"do_not": "invent_a_new_harness; use_what_is_already_there",
"runner_api": {"suite": "(name)", "test": "(name, fn)", "report":
"() returns true_if_all_passed"}, "assert_api":
["equal", "not_equal", "is_nil", "not_nil", "is_true", "is_false",
"kind", "count", "parse_error"], "verification":
"write_one_trivial_test_that_uses_runner_and_assert; require_it_from_run_lua_or_a_v001_entry_point; confirm_passes_and_fails_are_reported_correctly"}
```

The project already has a Lua test framework under
`tests/kscript/support/`:

- `support/runner.lua` — provides `runner.suite(name)`,
  `runner.test(name, fn)`, and `runner.report()`. Maintains pass/fail
  counts across all tests required during a run; prints `.` per pass,
  `F` per fail, then a summary.
- `support/assert.lua` — assertion helpers including `equal`,
  `not_equal`, `is_nil`, `not_nil`, `is_true`, `is_false`, `kind`,
  `count`, `parse_error`. Each errors with a descriptive message on
  failure.
- `tests/kscript/run.lua` — entry point. Adds `package.path`, requires
  all test modules, calls `runner.report()`, exits 0/1.

The existing lexer/parser/transpiler tests already use this framework
(`tests/kscript/lexer/test_literals.lua`, etc.). **Use it as-is for
V0.01.** Don't invent a parallel harness.

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

Then require it from `tests/kscript/run.lua` (or a temporary V0.01-only
entry point) and run. Expected: two dots and a `2 / 2 passed` summary,
exit 0.

To verify failure reporting, temporarily change one assertion to
something false (`assert_.equal(1, 2)`), re-run, expect `.F`, a failure
description in the summary, and exit 1.

### Step 0.5: Verify json.lua loads and parses

```
vibecode: {"step": "0.5", "name": "json_parse_sanity",
"fixture_path": "tests/sanity/test_json_parse.lua",
"requires_module": "kscript.json", "parses": "{\"a\": 1}",
"expected": "lua_table_with_a_equals_1", "side_effect":
"discovers_json_lua_actual_api_for_inventory_step",
"framework_used": "tests/kscript/support/runner_and_assert"}
```

The existing `code/kscript/lua/kscript/json.lua` is assumed to provide
a `parse` function. This step confirms it (and surfaces any API
surprises for the V0.01 phase 1 inventory step).

```lua
-- tests/sanity/test_json_parse.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("kscript.json")

runner.suite("sanity / json")

runner.test("parses a simple object", function()
    local parsed = json.parse('{"a": 1}')
    assert_.not_nil(parsed, "parse returned nil")
    assert_.equal(parsed.a, 1)
end)
```

If `json.lua`'s API differs (different function name, returns wrapped
result, etc.), this is where we discover it — and the
[V0.01 phase 1 inventory step](#step-1-inventory) starts here.

### Step 0.6: Verify file reading

```
vibecode: {"step": "0.6", "name": "file_read_sanity",
"fixture_path": "tests/kscript/fixtures/_sanity_text.txt",
"fixture_content": "ok\\n", "test_file":
"tests/sanity/test_file_read.lua",
"framework_used": "tests/kscript/support/runner_and_assert"}
```

The engine has to read KSJ files from disk; this step confirms that
works.

Fixture: `tests/kscript/fixtures/_sanity_text.txt` containing the two
bytes `ok` followed by a newline.

```lua
-- tests/sanity/test_file_read.lua
local runner = require("support.runner")
local assert_ = require("support.assert")

runner.suite("sanity / file read")

runner.test("io.open + read('*a') returns expected bytes", function()
    local f = assert(io.open("tests/kscript/fixtures/_sanity_text.txt", "r"))
    local content = f:read("*a")
    f:close()
    assert_.equal(content, "ok\n")
end)
```

When all six steps pass, the workbench is verified and Phase 1 can
begin.

### Phase 0 test plan

```
vibecode: {"phase_0_tests":
[{"id": "T0.1", "verifies": "lua_5_4_installed", "tool":
"command_line_lua_dash_v", "framework": "none"}, {"id": "T0.2",
"verifies": "pure_lua_script_runs_and_prints", "tool":
"tests/sanity/lua_hello.lua", "framework": "none"}, {"id": "T0.3",
"verifies": "package_path_resolves_kscript_json_via_require",
"tool": "tests/sanity/test_package_path.lua", "framework":
"support_runner_and_assert"}, {"id": "T0.4", "verifies":
"existing_test_framework_reports_pass_fail_and_exit_code", "tool":
"tests/sanity/test_framework_sanity.lua", "framework":
"support_runner_and_assert"}, {"id": "T0.5", "verifies":
"kscript_json_parse_handles_simple_object", "tool":
"tests/sanity/test_json_parse.lua", "framework":
"support_runner_and_assert"}, {"id": "T0.6", "verifies":
"file_io_read_returns_expected_bytes", "tool":
"tests/sanity/test_file_read.lua", "framework":
"support_runner_and_assert"}]}
```

T0.1 and T0.2 are pre-framework — Lua isn't even confirmed working
yet, so they can't depend on `support/runner.lua`. T0.3 onward use the
project's existing framework (`tests/kscript/support/runner.lua` +
`support/assert.lua`).

| ID | Verifies | Tool | Framework |
|---|---|---|---|
| T0.1 | Lua 5.4 installed | `lua -v` | none |
| T0.2 | Pure Lua script runs and prints | `tests/sanity/lua_hello.lua` | none |
| T0.3 | package.path resolves kscript modules | `tests/sanity/test_package_path.lua` | `support/runner` |
| T0.4 | Existing framework reports pass/fail | `tests/sanity/test_framework_sanity.lua` | `support/runner` |
| T0.5 | json.lua parses simple object | `tests/sanity/test_json_parse.lua` | `support/runner` |
| T0.6 | File I/O read returns expected bytes | `tests/sanity/test_file_read.lua` | `support/runner` |

All six must pass before V0.01 phase 1 begins.

---

## V0.01 phase 1: hello-world in KScriptJSON (Number One)

```
vibecode: {"phase": 1, "version": "0.01", "fixture_path":
"tests/kscript/fixtures/hello_world.ksj", "fixture_content":
"[[{\"value\": \"hello\"}, \"to_string\"]]", "runner_path":
"tests/kscript/run.lua", "acceptance":
"fixture_runs_via_engine_and_harness_captures_return_value_hello",
"required_ksj_forms": ["value_literal", "statement_call"], "required_runtime":
["json_parser", "statement_dispatcher_with_role_transition",
"method_dispatch", "literal_materialization_with_owning_role_tag",
"role_registry_with_user_and_string_class_role", "role_system_method",
"chain_wipe_on_boundary",
"top_level_returns_last_statement_value_to_harness"],
"required_stdlib": ["string_class_min_with_to_string_returning_self"],
"tactic": "inventory_then_fill_gaps; not_rewrite", "deferred_to_v002":
["kscript_text_parser", "transpiler"], "deferred_to_later":
["sys_references_including_stdout", "stdout_io",
"any_method_beyond_to_string", "any_class_beyond_string"]}
```

The first concrete development task. Work splits into three steps. The
tactic is **inventory then fill gaps** — not rewrite. The existing engine
under `code/kscript/lua/kscript/` already has a `json.lua`, `interpreter.lua`,
and other modules with tests; the V0.01 work is to verify and complete the
KScriptJSON-execution path just enough for `hello-world` to run. The KScript
text path (`lexer.lua`, `parser.lua`, `transpiler.lua`) is V0.02 work and
is not exercised by V0.01.

### Step 1: Inventory

```
vibecode: {"step": 1, "name": "inventory", "actions":
["read_existing_json_lua", "read_existing_interpreter_lua",
"note_state_of_json_parser", "note_state_of_ksj_executor",
"confirm_text_side_modules_exist_as_scaffolding_only"], "output":
"state_of_engine_doc; gap_list_for_v001"}
```

Read what's already in `code/kscript/lua/kscript/`: in particular `json.lua`
and `interpreter.lua`. Note the state of each:

- Does `json.lua` parse the JSON forms `hello-world.ksj` needs (top-level
  array, nested array, object with string keys, string values)?
- Does `interpreter.lua` accept a parsed KScriptJSON tree and dispatch
  statements?

`lexer.lua`, `parser.lua`, and `transpiler.lua` are KScript-text-side
concerns deferred to V0.02. Confirm they exist as scaffolding; don't trial
them for V0.01.

Output: a short gap list — "the JSON parser handles these forms / doesn't
handle these; the interpreter executes these KScriptJSON shapes / doesn't
execute these; this is what's needed to clear V0.01."

### Step 2: Fill the gaps

```
vibecode: {"step": 2, "name": "fill_gaps", "scope":
"only_what_v001_needs; not_full_ksj_spec",
"json_parser_forms": ["json_object", "json_array", "json_string",
"json_string_escapes_min"], "ksj_executor_forms":
["top_level_statement_list", "statement_call_dispatch_with_role_transition",
"value_literal_materialization_with_owning_role",
"top_level_returns_last_statement_value"], "role_forms":
["role_registry_init_with_user_and_string_class_role",
"owning_role_slot_on_every_value", "role_transition_save_and_restore",
"chain_wipe_at_boundary_even_if_chain_is_empty_placeholder",
"role_system_method_returning_current_role"], "stdlib_forms":
["string_class_with_to_string_returning_self_owned_by_string_class_role"]}
```

For each gap in the inventory, add only what V0.01 needs.
**Don't generalize ahead of the test.** The required surface is tiny:

- Enough JSON parsing to read `[[{"value": "hello"}, "to_string"]]`.
- Enough KScriptJSON execution to handle one top-level statement list,
  dispatch a single method call (with role transition), materialize a
  `value` literal with its owning-role tag, and return the last
  statement's value to the test harness.
- The role primitives from the [Role system](#role-system-baking-from-the-start)
  section: a registry with `user` and the string-class role, an
  `owning_role` slot on every value, save/restore of role + chain at
  the boundary, the `%role` system method, and the `%chain` wipe even
  though chain is empty for V0.01.
- One stdlib piece: a minimal string class with `to_string` (the
  identity for strings) owned by the string-class role.

Anything beyond these — `sys` references like `%stdout`, real I/O, any
class beyond string, any method beyond `to_string` — is later work, not
this one's.

### Step 3: Verify

```
vibecode: {"step": 3, "name": "verify", "actions":
["create_ksj_fixture_file", "run_via_engine",
"capture_last_statement_return_value", "compare_to_expected_string_hello"],
"pass_condition":
"return_value_equals_hello_and_no_exception_raised", "fail_condition":
"any_deviation; failure_message_should_name_which_layer_blocked"}
```

Create the fixture at `tests/kscript/fixtures/hello_world.ksj` containing
the KScriptJSON encoding, run it via the engine, capture the last
statement's return value, compare to the string `"hello"`. Pass = exact
match on return value plus no exception. Fail = capture which layer
blocked (JSON parse error? statement dispatch failed? literal
materialization failed? `to_string` method missing? role transition
botched? return-to-harness path missing?). That layer is the next thing
to fix; loop back to Step 2.

When V0.01 passes, V0.02 (hello-world in KScript source, via the transpiler)
is selected from the roadmap and planned in the same three-step shape.

### Phase 1 test plan

```
vibecode: {"phase_1_tests":
[{"id": "T1.1", "verifies":
"json_parse_handles_the_ksj_fixture_structure", "level": "unit"},
{"id": "T1.2", "verifies":
"engine_bootstrap_populates_roles_classes_ctx", "level": "unit"},
{"id": "T1.3", "verifies":
"engine_materialize_wraps_literal_with_user_owning_role", "level": "unit"},
{"id": "T1.4", "verifies":
"engine_lookup_method_finds_to_string_on_string_class", "level": "unit"},
{"id": "T1.5", "verifies":
"engine_transition_saves_and_restores_ctx_correctly", "level": "unit"},
{"id": "T1.6", "verifies":
"engine_dispatch_runs_one_statement_returns_string_value",
"level": "unit"}, {"id": "T1.7", "verifies":
"engine_run_on_fixture_file_returns_value_whose_payload_is_hello",
"level": "integration_end_to_end"}, {"id": "T1.8", "verifies":
"role_transition_actually_happened_during_dispatch", "level":
"unit_observability_check"}]}
```

Seven unit tests plus one end-to-end integration test verify Phase 1.
Each test is a Lua file under `tests/kscript/v001/` using the existing
project framework (`support.runner` + `support.assert`), required from
`tests/kscript/run.lua` (or a V0.01-specific entry point) and reported
through `runner.report()`.

Skeleton for a V0.01 test file:

```lua
-- tests/kscript/v001/test_bootstrap.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local engine = require("kscript")

runner.suite("v0.01 / bootstrap")

runner.test("populates the role registry with user and string-class roles", function()
    engine.bootstrap()
    assert_.not_nil(engine.roles.user)
    assert_.not_nil(engine.roles.string_class)
end)

runner.test("populates the class registry with the string class", function()
    engine.bootstrap()
    assert_.not_nil(engine.classes.string)
    assert_.equal(type(engine.classes.string.methods.to_string), "function")
end)

runner.test("execution context starts in user role", function()
    engine.bootstrap()
    assert_.equal(engine.ctx.current_role, engine.roles.user)
end)
```

Every test in the plan below follows this pattern.

| ID | Level | Verifies | How |
|---|---|---|---|
| T1.1 | unit | JSON parses the fixture | `json.parse('[[{"value": "hello"}, "to_string"]]')` returns the expected nested table |
| T1.2 | unit | bootstrap populates state | After `engine.bootstrap()`: `engine.roles.user` exists, `engine.classes.string` exists with `to_string` method, `engine.ctx.current_role == engine.roles.user` |
| T1.3 | unit | materialize wraps literal | `engine.materialize({value = "hello"})` returns `{type = "string", payload = "hello", owning_role = engine.roles.user}` |
| T1.4 | unit | method lookup | `engine.lookup_method(string_value, "to_string")` returns a function |
| T1.5 | unit | transition save/restore | Call `engine.transition(string_class_role, function() return engine.ctx.current_role end)`; verify return == string_class_role AND after the call `engine.ctx.current_role == user` and `engine.ctx.chain` is the original table |
| T1.6 | unit | dispatch one statement | `engine.dispatch({{value="hello"}, "to_string"})` returns a value with `payload == "hello"` |
| T1.7 | integration | full end-to-end | `engine.run("tests/kscript/fixtures/hello_world.ksj")` returns a value whose `payload == "hello"` |
| T1.8 | unit | transition observed | A spy in the `to_string` method records `engine.ctx.current_role` at call time; assert it was `string_class_role`, not `user` |

T1.8 is the load-bearing test for the role system: it proves the
transition *actually happened* (not just that it was set up). Without
it, role machinery could be missing entirely and the other tests
would still pass.

All eight pass = V0.01 done.

### Test layout

```
vibecode: {"test_framework":
"project_existing_at_tests_kscript_support_runner_and_assert; do_not_invent_a_new_one",
"file_naming_convention":
"test_topic_dot_lua_matching_existing_lexer_parser_transpiler_files",
"directory_layout": {"tests/sanity/":
"phase_0_workbench_sanity_tests_engine_independent",
"tests/kscript/fixtures/":
"ksj_and_text_fixtures_consumed_by_engine_or_tests",
"tests/kscript/v001/":
"phase_1_unit_and_integration_tests_for_v001",
"tests/kscript/run.lua":
"shared_entry_point_requires_all_test_modules_and_calls_runner_report",
"tests/kscript/support/":
"existing_runner_and_assert_modules_unchanged"}}
```

The project uses its existing test framework — `tests/kscript/support/runner.lua`
(provides `suite`, `test`, `report`) and `tests/kscript/support/assert.lua`
(assertion helpers). No new framework gets invented for V0.01. File
naming follows the existing convention (`test_<topic>.lua`).

| Path | Contents |
|---|---|
| `tests/sanity/` | Phase 0 workbench tests (engine-independent) |
| `tests/kscript/fixtures/` | KSJ and text fixtures (e.g., `hello_world.ksj`, `_sanity_text.txt`) |
| `tests/kscript/v001/` | Phase 1 unit and integration tests (V0.01-specific) |
| `tests/kscript/run.lua` | Entry point — extended to also require sanity + V0.01 tests |
| `tests/kscript/support/` | Existing `runner.lua` and `assert.lua`, unchanged |

Existing scaffolding under `tests/kscript/lexer/`, `tests/kscript/parser/`,
and `tests/kscript/transpiler/` is V0.02+ territory; not exercised by
V0.01 directly but already uses the same framework so the patterns
above mirror what's there.

---

## V0.0X: KScript command-line execution (Sarek)

```
vibecode: {"slice": "v0_0x_kscript_cli", "codename":
"kscript_cli", "position_in_roadmap":
"after_v002_kscript_text_runs; before_v01_bryton",
"goal":
"introduce_kscript_as_os_level_command_for_running_kscript_files_with_explicit_permission_model",
"hard_prerequisite_for": "v0_1_bryton",
"permission_posture":
"default_restrictive; opt_in_via_flags_deno_shape",
"aligns_with":
["feedback_no_dangerous_defaults", "roles_md_role_based_security"]}
```

Hard prerequisite for [V0.1 Bryton](#v01-bryton) — Bryton
subprocess-invokes test files (per the
[Bryton spec](../overview.md#tests-are-runnable-scripts), every
test file is "an ordinary executable"). This slice introduces
`kscript` as an OS-level command and pins down the permission model
for KScript code launched at the CLI.

### What the slice introduces

```
vibecode: {"introduces": ["kscript_command_line_launcher",
"shebang_support", "argument_passing_into_kscript",
"stdout_stderr_separation",
"exit_codes_zero_on_clean_completion_nonzero_on_alarm_or_uncaught",
"permission_flag_machinery"], "launcher_responsibilities":
["take_a_kscript_file_path_as_first_argument",
"set_up_engine_with_minimum_roles",
"wire_up_faucets_for_any_granted_flags",
"invoke_engine_run_on_the_file",
"emit_program_output_to_stdout_and_stderr_appropriately",
"exit_with_appropriate_code"]}
```

- A `kscript` command-line launcher — a small script taking a
  `.kscript` file path as its first argument, invoking the engine,
  exiting with an appropriate code.
- Shebang support — `.kscript` files starting with
  `#!/usr/bin/env kscript` are directly runnable via `chmod +x` and
  `./file.kscript`.
- Argument passing from OS argv into the running KScript program
  (surfaced via `%argv`; exact shape settled in this slice).
- Stdout / stderr separation — engine errors to stderr, the program's
  intentional output to stdout.
- Exit codes — 0 on clean completion, non-zero on uncaught exception
  or alarm.
- The permission-flag machinery described below.

### Permissions: default restrictive, opt-in via flags

```
vibecode: {"permission_model": "default_restrictive_opt_in_via_flags",
"defaults_always_on": ["user_role", "clock_role_plus_clock_object",
"randomizer_role_plus_random_source",
"utils_role_plus_percent_utils_namespace",
"stdin_role_plus_stdin_object", "stdout_role_plus_stdout_object",
"stderr_role_plus_stderr_object",
"cli_args_role_plus_argv"], "off_by_default_grant_via_flag":
["filesystem_dirjails", "network_faucets", "env_vars", "kiera",
"all_at_once_convenience"], "rationale_links":
["feedback_no_dangerous_defaults", "roles_md_role_based_security"]}
```

Following the role-based security model in [roles.md](../kscript/roles.md) and the
no-dangerous-defaults discipline, the CLI uses a **default-restrictive**
posture: a `.kscript` program invoked via the CLI gets only the minimum
roles and faucets, with everything else opt-in via flags. This mirrors
Deno's local-script model.

#### Always on (every CLI invocation)

| Capability | Role | Why default |
|---|---|---|
| Program execution context | `user` | The program has to run as something |
| Clock | `clock` | Per [roles.md](../kscript/roles.md) engine minimum |
| Randomizer | `randomizer` | Per engine minimum |
| `%utils` namespace | `utils` | Per engine minimum |
| stdin object | `stdin` faucet | The controlling terminal |
| stdout object | `stdout` faucet | Writing to the terminal |
| stderr object | `stderr` faucet | Diagnostics |
| `argv` | `cli_args` faucet | The program needs to see its own arguments |

#### Off by default, grant via flag

| Flag (repeatable where listed) | Grants | Role created |
|---|---|---|
| `--allow-fs=PATH` ⟳ | Read-write dirjail rooted at PATH | per-dirjail role |
| `--allow-fs-read=PATH` ⟳ | Read-only dirjail rooted at PATH | per-dirjail role |
| `--allow-net=HOST[:PORT]` ⟳ | Network faucet to specific host | per-faucet role |
| `--allow-net` | Network faucet to any host | broad `net` role |
| `--allow-env[=NAMES]` | Env-vars faucet, optionally narrowed | `env_vars` role |
| `--allow-kiera` | Kiera object access | `kiera` role |
| `--allow-all` (or `-A`) | Everything above | convenience for trusted local scripts |

`--allow-all` is the escape hatch for "this is my own script and I
trust myself." Without it, KScript at the CLI runs sandboxed by
default — the developer has to think about what the program needs.

#### Examples

```bash
./hello.kscript
# stdin/out/err/argv + engine minimums only; nothing else

kscript --allow-fs=. ./read_file.kscript
# adds read-write dirjail rooted at current directory

kscript --allow-fs-read=. --allow-net=api.example.com:443 ./fetch.kscript
# read-only filesystem + single-host network

kscript --allow-all ./my_local_tool.kscript
# everything; for trusted local scripts
```

### Installation

```
vibecode: {"installation_model":
"project_local_bin_plus_path; no_system_install",
"launcher_path_in_repo": "bin/kscript",
"user_action_once":
"add_project_bin_directory_to_path_in_shell_rc",
"launcher_is_self_locating":
"launcher_computes_its_own_absolute_path_and_derives_repo_root_from_that_then_resolves_engine_relative_to_repo_root",
"no_root_required": true, "multiple_checkouts_coexist":
"each_repo_has_its_own_bin; path_order_picks_the_winner",
"easy_backout":
"remove_path_line_from_rc_file; nothing_else_to_clean_up",
"system_install_status": "v1_plus_deployment_concern; not_v00x_work"}
```

The `kscript` launcher lives at `bin/kscript` inside the repo. There
is **no system-level install** in V0.0X — root access is not required,
and `/usr/local/bin/` (or equivalent) is not touched.

To make `kscript` available as a command, the user adds the project's
`bin/` directory to their `$PATH` once, in their shell's rc file:

```bash
# in ~/.bashrc or ~/.zshrc
export PATH="/home/miko/projects/mikobase/working/bin:$PATH"
```

After re-sourcing the rc file (or starting a new shell),
`kscript ./foo.kscript` works from any directory.

**The launcher is self-locating.** When invoked, `bin/kscript`
computes its own absolute path, derives the repo root from that, and
resolves the engine at `<repo_root>/code/kscript/lua/`. This works
regardless of the user's current directory when running `kscript`.

One candidate shape (bash form):

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
exec lua \
    -e "package.path='$REPO_ROOT/code/kscript/lua/?.lua;'..package.path" \
    "$REPO_ROOT/code/kscript/lua/kscript/cli.lua" "$@"
```

A pure-Lua form with a `#!/usr/bin/env lua` shebang also works (use
`arg[0]` to derive the script's own path). The slice settles which form
to ship.

**Why this approach:**

- No root, no system-wide pollution.
- Multiple project checkouts coexist — each has its own `bin/`, and
  `$PATH` order picks the winner.
- Easy to back out — remove the PATH line; nothing else to clean up.
- Standard pattern (Cargo, rustup, NVM, pyenv, etc. all ship dev tools
  this shape).

System-level install (`/usr/local/bin/kscript`, distribution packages,
homebrew formula, etc.) is a V1+ deployment concern, not V0.0X work.

### Bryton interaction

```
vibecode: {"bryton_invocation": "kscript_dash_dash_allow_all_per_test",
"rationale": "test_files_typically_need_broad_access; per_test_narrowing_is_later_bryton_feature_out_of_scope_for_v01"}
```

Bryton subprocess-invokes test files using `kscript --allow-all` by
default. Test files typically need broad access (filesystem to read
fixtures, network to hit a service-under-test, etc.). Per-test
permission narrowing is a later Bryton feature (configurable via a
future `bryton.json` setting; out of scope for V0.1).

### Open questions

```
vibecode: {"open_questions_v00x_cli":
["exact_flag_syntax_long_only_vs_short_forms_equals_vs_separate_args",
"default_for_kiera_role_off_seems_right_but_kiera_is_central",
"determinism_flag_for_clock_and_randomizer_seed_for_test_reproducibility_v2_plus",
"cross_platform_shebang_behavior_linux_macos_wsl",
"whether_engine_reading_the_dot_kscript_source_file_itself_should_require_a_permission_flag_or_be_pre_permission_engine_plumbing"]}
```

- **Exact flag syntax.** Long-only or short forms? `--allow-fs=./`
  versus `--allow-fs ./`? Settled in this slice.
- **Default for the `kiera` role.** Off-by-default seems right, but
  `kiera` is so central to the platform that always-on might be more
  first-contact-friendly. Deferred — re-examine when the kiera client
  lands.
- **Determinism flag for `clock`/`randomizer`** (e.g., `--seed=N`) for
  test reproducibility. V2+.
- **Cross-platform shebang behavior** (Linux / macOS / WSL).
  Mostly-portable on the three Unix-flavored cases; Windows native is
  V2+.
- **Engine reading the `.kscript` source file itself.** Current
  proposal: pre-permission engine plumbing (the engine has to read the
  script to run anything). If this becomes contentious, an explicit
  `--source=PATH` form could surface it.

---

## V0.1: Bryton (Amanda)

```
vibecode: {"version": "0.1", "codename": "bryton", "goal":
"first_usable_bryton_runner_executes_a_directory_of_test_files_and_aggregates_xeme_results",
"directive": "keep_very_light_per_user_instruction_2026-05-15",
"includes": ["runner_walks_directory_recursively_any_order",
"runs_every_file_as_subprocess",
"captures_stdout_parses_as_xeme_json",
"aggregates_flat_pass_fail_count",
"prints_summary_and_failure_list"], "explicitly_excludes_at_v01":
["bryton_json_per_directory_config", "ordering_control",
"explicit_skipping", "per_language_helper_libraries",
"fail_fast", "tree_shaped_result_aggregation", "concurrency_control"],
"language_of_runner_v01":
"lua_for_simplicity; kscript_hosted_runner_is_a_later_slice",
"distinct_from":
"lua_side_engine_tests_which_continue_to_use_tests_kscript_support_runner",
"spec_links":
["documentation/bryton/overview.md",
"documentation/bryton/runner.md"]}
```

V0.1 is the first usable **Bryton** — see
[bryton/overview.md](../overview.md) and
[bryton/runner.md](../kscript/bryton/runner.md) for the full spec. Per the
direction to keep it very light at this stage, the V0.1 runner does
only what's strictly needed: walk a directory, run each file as a
subprocess, parse each Xeme, aggregate, report.

**V0.1 Bryton includes:**

- Runner walks a directory recursively. Order is undefined.
- Runs every file it finds as a subprocess.
- Captures each subprocess's stdout, parses it as Xeme JSON.
- Aggregates a flat pass/fail count across all tests.
- Prints a summary (`N passed, M failed`) plus a list of failures.

**Explicitly excluded from V0.1** (deferred to later Bryton slices):

- `bryton.json` per-directory config (no ordering, no skipping)
- Per-language helper libraries (no KScript-side assertion helpers)
- Fail-fast
- Tree-shaped result aggregation (flat tally only)
- Concurrency control (sequential execution only)
- The runner being itself a KScript program — V0.1 runner is
  implemented in Lua for simplicity. A KScript-hosted Bryton runner
  is a later slice (the language has to mature far enough to expose
  filesystem and subprocess capabilities).

**Distinct from Lua-side engine tests.** The existing
`tests/kscript/support/runner.lua` continues to test the engine
internals; that's fixed at V0.01. Bryton is for testing **KScript
code with KScript code** (or, in V0.1, with any script that emits
Xeme), layered on top of the engine.

### V0.1 prerequisites

```
vibecode: {"v01_prerequisites":
["v001_engine_can_run_ksj_end_to_end",
"v00X_kscript_text_parser_and_transpiler_so_test_files_can_be_kscript_source",
"v00X_hash_class_so_kscript_tests_can_construct_xemes",
"v00X_stdout_writing_so_kscript_tests_can_emit_xemes",
"v00X_json_serialization_method_on_hashes_so_tests_can_emit_their_xemes",
"lua_host_subprocess_invocation_io_popen",
"lua_host_directory_walk_find_via_io_popen_or_lfs"]}
```

Several slices in the V0.0X range have to land before V0.1 can ship:

| Prerequisite | Provided by |
|---|---|
| Engine can run KSJ end-to-end | V0.01 |
| KScript text → KSJ transpiler | V0.02 |
| Hash class | a V0.0X slice |
| `%stdout.write` (sys references + stdout sink) | a V0.0X slice |
| JSON serialization (hash → JSON string method) | a V0.0X slice |
| KScript CLI executable (`kscript` command, shebang support, permission flags) | [V0.0X CLI slice](#v00x-kscript-command-line-execution) |
| Lua-host subprocess invocation | runner host; native `io.popen` |
| Lua-host directory walk | runner host; `io.popen("find ...")` or `lfs` |

The V0.0X slices that fill these gaps are unscoped in this plan until
each is the next active slice. The current direction is to attempt
them in roughly the order shown; each unblocks the next.

### V0.1 phase plan

Three phases, same three-step shape as V0.01:

#### Phase 0: Lua-host workbench for Bryton

```
vibecode: {"v01_phase_0_purpose":
"verify_lua_host_capabilities_bryton_needs_before_writing_bryton_code",
"steps_count": 3, "acceptance":
"all_three_pass_no_bryton_code_written_yet"}
```

- **Step 0.1: subprocess invocation.** `io.popen` runs a command and
  captures stdout. Sanity test: `io.popen("echo hello"):read("*a")`
  returns `"hello\n"`.
- **Step 0.2: exit-code capture.** `io.popen` closes with success/fail
  info. Sanity: a command exiting 0 reports success; non-zero reports
  fail.
- **Step 0.3: directory walking.** Some mechanism for listing files
  recursively under a directory. Two candidates: shell out to `find`
  via `io.popen` (no extra dependency) or use `lfs` (LuaFileSystem) if
  installed. Test: walking a known fixture directory produces the
  expected file list.

#### Phase 1: runner implementation

```
vibecode: {"v01_phase_1_steps":
[{"step": 1, "name": "walk_directory_collect_test_files"},
{"step": 2, "name": "run_one_file_as_subprocess_capture_stdout"},
{"step": 3, "name": "parse_captured_stdout_as_xeme_json"},
{"step": 4, "name":
"aggregate_pass_fail_counts_across_multiple_tests"},
{"step": 5, "name": "print_flat_summary_and_failure_list"},
{"step": 6, "name":
"wire_steps_1_through_5_as_bryton_dot_lua_entry_point"}]}
```

Build the runner step by step, each independently testable:

1. **Walk + collect.** A function taking a directory path and
   returning a list of test file paths.
2. **Run one file.** A function that runs one file as a subprocess
   and returns `{stdout, exit_code}`.
3. **Parse Xeme.** A function that takes captured stdout and returns
   the parsed Xeme (a Lua table). Errors on malformed JSON.
4. **Aggregate.** A function that takes a list of Xemes and produces
   `{passed_count, failed_count, failures_list}`.
5. **Print summary.** A function that prints the aggregate in a
   human-readable form.
6. **Entry point.** A `bryton.lua` that wires everything: takes a
   directory path arg, walks, runs each file, aggregates, reports,
   exits 0 if all passed / 1 if any failed.

#### Phase 2: acceptance tests

```
vibecode: {"v01_phase_2_tests":
[{"id": "TB.1", "verifies": "trivial_pass_case"},
{"id": "TB.2", "verifies": "trivial_fail_case_message_surfaces"},
{"id": "TB.3", "verifies":
"mixed_directory_correct_aggregate_and_failures_listed"}]}
```

| ID | Verifies | Setup |
|---|---|---|
| TB.1 | Trivial pass case | A test file emits `{"success": true}`; Bryton reports 1 passed |
| TB.2 | Trivial fail case | A test file emits `{"success": false, "message": "X"}`; Bryton reports 1 failed with `X` in the failure list |
| TB.3 | Mixed directory | A directory with 2 passing + 1 failing test files; Bryton reports 2 passed, 1 failed, the failing test's message in the summary |

The test fixtures themselves can be in any language that emits Xeme
JSON to stdout (shell scripts, Lua scripts, or — once the
prerequisites land — KScript files). For V0.1 acceptance, the
simplest path is shell scripts that `echo` the Xeme JSON — this
lets us verify the runner works without depending on the KScript
prerequisites being complete.

When all three pass, V0.1 Bryton ships.

### V0.1 test layout

```
vibecode: {"v01_test_layout":
{"runner_implementation_under":
"code/bryton/lua/bryton/",
"v01_acceptance_fixtures_under":
"tests/bryton/v01/fixtures/",
"v01_acceptance_tests_under":
"tests/bryton/v01/"}}
```

| Path | Contents |
|---|---|
| `code/bryton/lua/bryton/` | The Lua-host Bryton runner implementation |
| `tests/bryton/v01/fixtures/` | Test scripts emitting Xeme JSON (pass + fail cases) |
| `tests/bryton/v01/` | V0.1 acceptance tests using `support/runner` + `support/assert` |

---

## Methodology (T'Pring)

```
vibecode: {"notes": ["vibecode_is_source_of_truth", "prose_is_derivative",
"each_phase_runnable", "tests_drive_roadmap",
"soft_lock_applies_until_explicit_unlock",
"phase_completion_requires_acceptance_criterion_passing",
"inventory_before_implement; never_rewrite_without_understanding",
"minimal_surface_per_slice; not_full_spec_upfront",
"ksj_is_runtime_format; kscript_text_is_for_humans"]}
```

- Vibecode blocks are canonical; prose is derivative.
- Each phase ends runnable.
- Tests drive the roadmap. What's missing in the next test is what gets
  built next.
- Soft feature lock applies until explicitly unlocked.
- A phase isn't complete until its acceptance criterion passes.
- Inventory existing code before adding new code; never rewrite without
  understanding what's there.
- Each slice builds the minimal surface it needs. The full KScriptJSON
  spec, the full KScript grammar, and the full stdlib emerge over many
  slices, not as single upfront efforts.
- KScriptJSON is the runtime format the engine consumes; KScript text is
  for human authors and gets transpiled to KScriptJSON before execution.

---

## Open (T'Pau)

```
vibecode: {"open": ["test_runner_decision", "fixture_layout",
"vibecode_attachment_form", "bootstrap_parser_in_ksj",
"string_class_role_name", "chain_placeholder_form_in_v001",
"top_level_return_path_to_harness",
"engine_capability_allow_list_v1_plus"]}
```

- **Test runner.** Use the existing `tests/kscript/run.lua` or evolve it?
  To be decided during Step 1 (inventory) of V0.01.
- **Fixture layout.** The proposed `tests/kscript/fixtures/` path mirrors
  the existing test directory structure but should be confirmed on
  inventory.
- **Vibecode attachment form.** The mechanism for attaching vibecode blocks
  to runtime statements is TBD per the existing memory. Doesn't block V0.01
  — vibecode in docs is fine for now.
- **Bootstrap parser.** The KScriptJSON spec notes that the bootstrap
  parser (KScript text → KScriptJSON) must be written directly in
  KScriptJSON. This is V0.02 work, not V0.01, but flagged here so it isn't
  lost.
- **String-class role name.** The engine role owning the built-in string
  class needs a name. Per [roles.md](../kscript/roles.md) the broader minimum role
  set includes `user`, `clock`, `randomizer`, `utils` — the string class
  isn't named there explicitly. Provisional name to be decided at V0.01
  implementation.
- **`%chain` placeholder form in V0.01.** Chain wipe needs to be in place
  even though no chain entries are used. Decide whether `%chain` exists as
  an empty hash, an empty list, or a typed object whose methods all
  no-op for V0.01.
- **Top-level return path to harness.** The engine needs to surface the
  last top-level statement's value to the Lua-side test harness. Exact
  shape (Lua return value? a captured field on the engine instance? an
  output buffer?) to be decided at V0.01 implementation.
- **Engine capability allow-list (V1+).** Beyond V0.01, the engine
  needs a deliberate way to decide which capabilities (built-ins,
  faucets, sys references) a given invocation gets. Core to running
  untrusted code: the engine must be able to launch with a restricted
  surface the running code cannot escape. Likely shapes are engine-
  config-driven or role-trust-driven; the design hasn't been picked
  yet. Not a V0.01 blocker.
