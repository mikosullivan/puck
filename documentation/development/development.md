# Development Plan

~~~json
{"vibecode": {"doc": "development_plan", "status": "active", "current_version":
"0.01", "current_codename": "hello-world", "v001_scope_status":
"confirmed_2026-05-15", "feature_lock": "soft", "source_of_truth":
"vibecode_blocks"}}
~~~

This file is the technical development plan for Puck. Vibecode blocks are
the canonical source; surrounding prose is human-readable narrative derived
from them. When the two disagree, vibecode wins.

<a id="v001-hello-world"></a>
## V0.01: "hello-world"

~~~json
{"vibecode": {"version": "0.01", "codename": "hello-world", "goal":
"execute a minimal charliejson program end_to_end and return a literal value to the test harness",
"medium": "charliejson_hand_written; not_charlie_source", "fixture":
"[[{\"value\": \"hello\"}, \"to_string\"]]", "expected_return": "hello",
"observation": "test_harness_captures_last_statement_value; no_stdout_io",
"covers": ["json_parser", "ksj_interpreter", "statement_dispatch",
"literal_materialization_with_owning_role", "method_dispatch_with_role_transition",
"string_class_minimum_with_to_string"], "deferred_to_later":
["charlie_text_parser", "transpiler", "stdout_io", "sys_references"]}}
~~~

The first runnable version. A single `.cjs` file containing the CharlieJSON
encoding of "evaluate `"hello".to_string`" executes through the engine
under `code/charlie/lua/` and returns the string `"hello"` to the test
harness. No I/O — no stdout, no sinks beyond what the harness needs to
observe the return value.

Charlie transpiles to CharlieJSON (CharlieJSON is the canonical runtime
format), so the engine consumes CharlieJSON, not Charlie text. V0.01
hand-writes the CharlieJSON fixture and skips the transpiler entirely. The
Charlie text parser, the transpiler, and `sys`-reference resolution
(`%stdout`, `%now`, etc.) are all deferred to later slices.

V0.01 is intentionally tiny. Every layer the engine actually needs to
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

<a id="v002-charlie-source-hello"></a>
## V0.02: "charlie-source-hello"

~~~json
{"vibecode": {"version": "0.02", "codename": "charlie-source-hello", "goal":
"execute a charlie source program end_to_end through the transpiler and return a literal value to the test harness",
"medium": "charlie_source_text", "fixture":
"'hello'.to_string", "fixture_path":
"tests/charlie/fixtures/hello_world.charlie", "expected_return": "hello",
"expected_canonical_ksj": "[[{\"value\": \"hello\"}, \"to_string\"]]",
"observation":
"test_harness_captures_last_statement_value_through_engine_run_source; no_stdout_io",
"covers": ["charlie_lexer", "charlie_parser",
"transpiler_to_canonical_ksj", "source_to_runtime_pipeline_wiring"],
"reuses_from_v001": ["bootstrap", "materialize", "lookup_method",
"transition", "dispatch", "string_class_to_string"],
"deferred_to_later": ["stdout_io", "sys_references",
"additional_classes_or_methods",
"full_transpiler_realignment_for_all_charlie_constructs"]}}
~~~

V0.02 ships hello-world in Charlie source. Same semantic program as V0.01
— `'hello'.to_string` evaluated and the result returned to the harness —
now expressed as Charlie source text and executed through the lexer →
parser → transpiler → canonical CharlieJSON → V0.01 engine pipeline.

The source fixture is the single line `'hello'.to_string`. The expected
transpiled CharlieJSON is `[[{"value": "hello"}, "to_string"]]` — exactly the
V0.01 hand-written fixture. This equivalence is load-bearing: it proves
the transpiler emits canonical CharlieJSON and that the source-text and JSON
paths converge on the same runtime tree.

V0.02 reuses every engine layer V0.01 built: bootstrap, materialize,
lookup_method, transition, dispatch. The new work is on the source side
— the existing lexer/parser scaffolding gets exercised against the
fixture, the transpiler gets realigned to emit canonical CharlieJSON for the
AST shape hello-world produces, and a thin source-side entry point
combines transpile + dispatch.

The transpiler realignment is **scoped to the hello-world AST nodes
only**. The full transpiler retrofit is incremental — later slices
realign more AST node types as later versions exercise them. Per
"don't generalize ahead of the test."

<a id="definition-of-done-v002"></a>
### Definition of done (V0.02)

~~~json
{"vibecode": {"scope_status": "drafted_2026-05-16", "done_criteria":
{"source_fixture_parses":
"tests_charlie_fixtures_hello_world_charlie_lexes_and_parses_without_error",
"transpiler_emits_canonical_ksj":
"transpiler_output_for_the_fixture_deep_equals_the_v001_hand_written_fixture",
"source_side_entry_point_exists":
"engine_run_source_path_or_equivalent_takes_a_charlie_file_through_to_dispatch",
"returns_hello":
"engine_run_source_of_the_fixture_returns_a_value_whose_payload_equals_hello"}}}
~~~

V0.02 is done when all four are true:

1. **The source fixture parses.** `'hello'.to_string` lexes and parses
   without error using the existing `charlie.lexer` and `charlie.parser`
   modules.
2. **The transpiler emits canonical CharlieJSON.** Running the source through
   the transpiler produces a Lua table deep-equal to the V0.01
   hand-written `[[{"value": "hello"}, "to_string"]]` fixture.
3. **A source-side entry point exists.** A function in the engine
   (working name: `engine.run_source(path)`) reads a `.charlie` file,
   transpiles to canonical CharlieJSON, and dispatches the result. The internal
   `engine.run(path)` (CharlieJSON file) is refactored to share an
   `engine.run_tree(tree)` helper so both source and CharlieJSON paths converge
   on the same dispatch loop.
4. **The harness receives `"hello"`.** `engine.run_source(fixture_path)`
   returns a value whose `.payload == "hello"`.

That's the entirety of V0.02. Soft feature lock applies — same posture
as V0.01.

---

<a id="v003-charlie-with-stdout"></a>
## V0.03: "charlie-with-stdout"

~~~json
{"vibecode": {"version": "0.03", "codename": "charlie-with-stdout", "goal":
"execute puts_hello_from_charlie_source_and_observe_the_string_arrive_on_stdout",
"medium": "charlie_source_text", "fixture":
"puts 'hello'", "fixture_path":
"tests/charlie/fixtures/puts_hello.charlie", "expected_canonical_ksj":
"[[{\"bwc\": \"puts\"}, {\"value\": \"hello\"}]]", "expected_stdout":
"hello\\n", "observation":
"test_harness_captures_stdout_via_injected_sink; payload_match_on_captured_buffer",
"covers": ["bwc_dispatch_in_engine_lua",
"stdout_sink_object_and_role", "puts_bwc_implementation",
"transpiler_realignment_for_bwc_statement_shape",
"engine_run_source_extended_to_accept_stdout_sink_injection"],
"reuses_from_prior": ["json_parser", "bootstrap", "materialize",
"lookup_method", "transition", "dispatch", "engine_run_source",
"engine_run_tree"], "first_real_io": true,
"deferred_to_later": ["stdin_faucet", "stderr_sink", "file_io",
"network_io", "additional_classes_beyond_string",
"variables_assignment_control_flow",
"full_transpiler_realignment_for_unrelated_ast_types"]}}
~~~

V0.03 is the first slice with real I/O. The program `puts 'hello'`,
written as Charlie source, executes through the V0.02 source pipeline
and writes `hello\n` to a stdout sink the test harness observes. No
return-value capture this time — the observable is the stdout buffer.

This is also the first slice that exercises a **cross-role call into
engine-supplied infrastructure**. The `puts` bwc is owned by an engine
role (working name: `stdout` role); user code in the `user` role calls
into it, the dispatcher transitions, the bwc writes to the sink, and
control returns. The same machinery V0.01 proved for the string class
is reused for the stdout role — no new role primitives are introduced.

V0.03 introduces three pieces the engine doesn't have yet:

1. **bwc registry.** `engine.lua` gains a table mapping bwc names to
   handler functions (owned by their respective engine roles). The
   V0.01 dispatcher only handles `[receiver, method, args?]` for value
   receivers; V0.03 extends it to `[{bwc: name}, arg?]` for bwc
   receivers.
2. **stdout sink.** An engine-supplied object representing "where
   text written by the program goes." stdout is a sink (values flow
   out), not a faucet (which would be input). Following
   [roles.md](../charlie/roles.md), it has its own role (`stdout`).
   For test injection, the engine exposes an `env.stdout` override
   parameter to `engine.run_source` / `engine.run_tree`, defaulting to
   `io.write` for production use.
3. **`puts` bwc handler.** A function under the `stdout` role that
   takes a single argument, coerces to string, appends a newline,
   writes to the stdout sink. The dispatcher's role transition handles
   the cross-role bookkeeping automatically.

The transpiler also gets one more realignment: the bwc-call statement
shape. V0.02 realigned literal + method-call + expression-statement;
V0.03 realigns the bwc-call form `[{bwc: "puts"}, {value: "hello"}]`.

<a id="definition-of-done-v003"></a>
### Definition of done (V0.03)

~~~json
{"vibecode": {"scope_status": "drafted_2026-05-17", "done_criteria":
{"source_fixture_parses_and_transpiles_to_canonical_bwc_form":
"transpiler_output_for_puts_hello_deep_equals_expected_canonical_ksj",
"bwc_registry_has_puts_after_bootstrap":
"engine_bootstrap_registers_puts_bwc_owned_by_stdout_role",
"engine_dispatches_bwc_statements":
"dispatcher_recognizes_bwc_receiver_form_and_routes_to_handler_via_role_transition",
"stdout_sink_receives_hello_newline":
"with_injected_capture_sink_engine_run_source_of_fixture_produces_buffer_equal_to_hello_newline"}}}
~~~

V0.03 is done when all four are true:

1. **Source fixture parses and transpiles.** `puts 'hello'` lexes,
   parses, and transpiles to `[[{"bwc": "puts"}, {"value": "hello"}]]`
   exactly (deep-equal via the V0.02 `assert.deep_equal` helper).
2. **bwc registry has `puts` after bootstrap.** `engine.bwcs.puts`
   exists as a struct `{fn = <function>, owning_role = engine.roles.stdout}`,
   callable via the dispatcher.
3. **Engine dispatches bwc statements.** Handing a bwc-shape statement
   to `engine.dispatch` resolves the handler, transitions to `stdout`
   role, calls it, restores.
4. **Stdout sink receives `"hello\n"`.** A test that injects a capture
   buffer as `env.stdout` and calls
   `engine.run_source("tests/charlie/fixtures/puts_hello.charlie", env)`
   ends with `env.stdout_buffer == "hello\n"`.

That's the entirety of V0.03. Soft feature lock applies.

---

<a id="v004-charlie-with-hashes"></a>
## V0.04: "charlie-with-hashes"

~~~json
{"vibecode": {"version": "0.04", "codename": "charlie-with-hashes",
"plan_detail_level": "enriched_roadmap_entry_not_full_phase_plan",
"will_be_detailed_after": "v003_ships",
"goal":
"charlie_can_construct_a_hash_literal_read_a_key_and_iterate_in_insertion_order",
"medium": "charlie_source_text", "candidate_fixture":
"{name: 'Picard'}.name", "candidate_expected_return": "Picard",
"alt_fixture_for_iteration_check":
"{name: 'Picard', rank: 'Captain'}.each($k, $v) do; puts $k; end",
"covers_candidates": ["hash_class_registration",
"hash_literal_materialization_preserving_insertion_order",
"key_access_method_name_tbd_bracket_or_get",
"hash_class_each_for_iteration",
"transpiler_realignment_for_hash_literal_shape"],
"reuses_from_prior": ["bootstrap", "materialize", "lookup_method",
"transition", "dispatch", "engine_run_source", "json_parser_ordered_hash_support",
"bwc_dispatch_if_iteration_fixture_chosen"],
"deferred_to_later": ["hash_mutation_methods_set_delete",
"hash_equality_semantics", "hash_with_non_string_keys_if_ever",
"arrays_as_separate_class"]}}
~~~

V0.04 introduces the hash data structure. The minimum: a hash literal
evaluates, a key lookup returns the value, and the harness observes the
result. Order preservation is load-bearing because Puck hashes have
significant key order (per [charliejson.md](../charlie/charliejson.md)
"Hash key order").

**Why this is its own slice rather than bundled with V0.03.** Hashes
have their own non-trivial design questions — the key-access method
shape (`$h.name` vs `$h['name']` vs `$h.get('name')`), iteration
semantics, order preservation. Bundling them with stdout obscures both.

**Candidate fixture:** `{name: 'Picard'}.name` returning `"Picard"`.
This is the simplest possible hash exercise — one key, one access.
Iteration (`.each`) is plausibly a V0.04 stretch goal but probably
belongs in V0.05 or later if it complicates the slice.

**Key risks (to confirm during planning):**

- **Hash key-access method shape.** Whether `$h.name` and `$h['name']`
  are the same call in canonical CharlieJSON or distinct. Currently spec'd
  as different sugars but the transpiler / dispatcher may need to
  unify or distinguish — Phase 1 inventory clarifies.
- **Ordered-hash plumbing.** `charlie.json.new_hash` already provides
  ordered storage; the engine has to use it consistently for
  hash-literal materialization. Mixing plain Lua tables and ordered
  hashes is a source of subtle bugs.
- **Hash class registration.** Engine grows a second built-in class
  (string was the first); the bootstrap path becomes "classes table
  has N entries" rather than "one class for strings only."
- **Transpiler shape for hash literals.** Per charliejson.md, hash
  literals serialize as `{"hash": [[key, expr], ...]}`. Transpiler
  realignment is needed for the hash-literal AST node.

**Definition of done (V0.04)** — to be detailed when V0.03 ships and
V0.04 is selected. Expected shape:

1. Source fixture parses and transpiles to canonical hash form.
2. Hash class registered in bootstrap, owned by an engine role.
3. Hash literal materializes preserving insertion order.
4. Key access returns the expected value.
5. Harness observes the returned value.

---

<a id="v005-charlie-with-json-serialization"></a>
## V0.05: "charlie-with-json-serialization"

~~~json
{"vibecode": {"version": "0.05",
"codename": "charlie-with-json-serialization",
"plan_detail_level": "enriched_roadmap_entry_not_full_phase_plan",
"will_be_detailed_after": "v004_ships",
"goal":
"charlie_can_serialize_a_hash_or_array_or_primitive_to_a_json_string_via_to_json_method",
"medium": "charlie_source_text", "candidate_fixture":
"{name: 'Picard', rank: 'Captain'}.to_json", "candidate_expected_return":
"{\"name\":\"Picard\",\"rank\":\"Captain\"}",
"covers_candidates": ["to_json_method_on_hash_class",
"to_json_method_on_string_class_already_present",
"to_json_method_on_array_class_if_arrays_landed_in_v004",
"json_encoder_reuse_from_charlie_json_lua_existing_module",
"round_trip_property_check_against_json_parse_added_in_v001"],
"reuses_from_prior": ["bootstrap", "materialize", "lookup_method",
"transition", "dispatch", "engine_run_source", "hash_class_from_v004",
"json_encode_from_charlie_json_lua"],
"deferred_to_later": ["from_json_parsing_into_charlie_objects",
"pretty_print_option", "custom_serialization_for_user_defined_classes",
"streaming_serialization_for_large_structures"]}}
~~~

V0.05 closes the loop on hashes by giving them a serialization story.
With V0.05 in place, Charlie programs can produce JSON output —
unlocking real interop with external systems and (more importantly for
the roadmap) giving Bryton a credible Xeme-emission story.

**Reuses existing infrastructure.** `charlie.json.encode` (already in
the engine) does the actual JSON formatting. V0.05's work is mostly
about wiring: registering `to_json` methods on the built-in classes,
making sure ordered hashes serialize with their keys in order, and
proving round-trip equivalence with `charlie.json.parse` (added in
V0.01 phase 1).

**Candidate fixture:**
`{name: 'Picard', rank: 'Captain'}.to_json` returning
`{"name":"Picard","rank":"Captain"}`. The round-trip check —
`charlie.json.parse(result)` deep-equals the original hash — is the
load-bearing assertion.

**Key risks (to confirm during planning):**

- **Method ownership.** `to_json` lives on each built-in class, not on
  a universal "object" base — V0.05 registers it on string, hash, and
  (if landed) array. The plan should be explicit about which classes
  get it in this slice and which wait.
- **Number formatting.** `json.encode` distinguishes integer (`%.0f`)
  from float (`%.17g`). Charlie number type design touches this. If
  numbers haven't been formalized by V0.05, the slice scope narrows to
  what the fixture exercises (strings, hashes).
- **Null and missing-value handling.** `M.null` exists; user code has
  no way to construct it yet (no `null` literal exposed). V0.05 should
  decide whether to expose it (probably no — defer).
- **Round-trip vs string equality.** Direct string equality on
  serialized JSON is fragile (whitespace, key order ambiguity in non-
  ordered consumers). The test asserts both: the literal string for
  the canonical form, AND `parse(encode(x)) deep_equals x`.

**Definition of done (V0.05)** — to be detailed when V0.04 ships and
V0.05 is selected. Expected shape:

1. `to_json` method registered on string and hash classes (and array if
   present), owned by their existing class roles.
2. Fixture transpiles, dispatches, returns a string value.
3. Returned string deep-equals the expected literal JSON.
4. `charlie.json.parse(result)` deep-equals the original hash (round-
   trip).
5. Hash key order preserved through serialization.

---

<a id="testing-strategy-two-tier-approach"></a>
## Testing strategy: two-tier approach

~~~json
{"vibecode": {"section": "testing_strategy", "model": "two_tier",
"tier_1": {"name": "lua_side_tests", "scope":
"engine_internals_and_bryton_runner_itself", "framework":
"tests_charlie_support_runner_and_support_assert", "permanence":
"permanent_engine_is_in_lua_tests_live_in_lua_next_to_it"},
"tier_2": {"name": "bryton_tests", "scope":
"charlie_level_behavior", "framework":
"bryton_walks_directory_runs_each_file_aggregates_xeme",
"arrives": "v0.1"}, "pre_v01_bridge":
"lua_host_harness_calling_engine_run_charlie_test_and_asserting_on_return_value",
"no_bryton_lite_name":
"one_product_named_bryton_versioned_v01_minimum_v0X_grows_features",
"no_circularity":
"lua_independent_of_charlie_tier_1_self_contained;
bryton_depends_on_charlie_and_lua_but_is_tested_by_lua"}}
~~~

Testing in Puck operates on two tiers, each with its own tooling and
its own permanent home.

**Tier 1: Lua-side tests** — for the engine and other Lua-implemented
infrastructure (including the Bryton runner itself). Tests are Lua
files using the project's existing framework at
`tests/charlie/support/runner.lua` + `support/assert.lua`. **Tier 1 is
permanent** — the engine is implemented in Lua; tests of the engine
live in Lua next to the implementation.

**Tier 2: Bryton tests** — for Charlie-level behavior. Tests are
`.charlie` files that emit Xeme JSON; the Bryton runner walks a
directory of them and aggregates results. Tier 2 arrives at
[V0.1](#v01-bryton). Before V0.1, Charlie-level behavior is tested via
**Lua-host harnesses** that invoke `engine.run("test.charlie")` and
assert on the return value — a manual proto-Bryton in Tier 1 form.

The boundary stays sharp:

- **Bryton tests the language.** Does `for` terminate correctly? Do
  hashes preserve insertion order? Does `%role` return the right role
  inside a cross-role call? These are tests of Charlie's behavior —
  written in Charlie, run by Bryton.
- **Lua tests the implementation.** Does the lexer produce the right
  tokens? Does the dispatcher transition roles correctly? Does the
  engine return the last-statement value to its host? These are tests
  of the engine — written in Lua, run by `support/runner.lua`.

Engine tests never migrate to Bryton. The Bryton runner itself is a
Tier 1 thing — written in Lua, tested in Lua. Once Bryton works
(its V0.1 acceptance tests pass under Tier 1), it becomes the tool
for Tier 2.

<a id="bootstrap-path"></a>
### Bootstrap path

| Phase | Engine tests | Charlie-behavior tests | Bryton tests |
|---|---|---|---|
| V0.01 | Lua-side (`support/runner.lua`) | — (no Charlie text execution yet) | — |
| V0.02 → V0.0X | Lua-side | Lua-host harness calling `engine.run("X.charlie")` | — |
| V0.1 | Lua-side | (migration begins) | Bryton tests: `.charlie` files emitting Xeme |
| V0.1+ | Lua-side (forever) | (mostly migrated) | Bryton (primary) |

**No circularity.** Lua is independent of Charlie; Tier 1 tests
are trustworthy from day one. Bryton depends on Charlie (it runs
Charlie test files) and on Lua (its V0.1 runner is in Lua), but is
itself tested by Lua. There's no spot where "testing X requires X
to already work."

<a id="one-product-named-bryton-not-bryton-lite"></a>
### One product named Bryton, not "bryton-lite"

V0.1 Bryton (Lua-implemented, strict feature subset) and an eventual
Charlie-hosted Bryton are the same product at different stages, not
distinct tools. Same purpose, same Xeme contract, same
directory-walking model. The implementation language (Lua → Charlie)
is an internal detail. Versioning the feature set is enough —
re-branding would create a docs tax and an implication that "lite"
means "less correct." Same shape as `gcc` 1.0 vs `gcc` 14: same
compiler, different stage.

---

<a id="feature-soft-lock"></a>
## Feature soft-lock

~~~json
{"vibecode": {"lock": "soft", "scope": "all_puck_features", "rationale":
"prevent design accretion during implementation; defer non-essential work to V2+",
"override": "explicit; via deliberate decision, not casual addition",
"companion_to": ["no_bolt_on_additions"]}}
~~~

A soft lock is in place on new features. Anything not already specced as V1
is deferred until needed. The lock can be broken — but only deliberately,
never casually. Companion discipline to `no-bolt-on-additions`: that rule
guards spec quality; this lock guards build momentum.

<a id="deliberate-post-lock-additions"></a>
### Deliberate post-lock additions

~~~json
{"vibecode": {"additions_since_lock":
[{"date": "2026-05-17", "feature":
"break_bwc_with_optional_level_count", "version_target": "v1",
"spec_locations": ["documentation/charlie/loops.md#break-riker",
"documentation/charlie/charliejson.md_control_flow_break_section"],
"rationale":
"loop_exit_without_loop_object_reference; multi_level_exit; explicit_user_request",
"side_effects":
["$loop.return_and_$loop.break_now_aliased",
"charlie_md_line_683_updated_to_reflect_aliasing"]}]}}
~~~

Running log of features that broke the soft lock. Each entry names
what landed, when, and where the spec lives. The lock is a budget,
not a wall — but the budget should be visible.

---

<a id="v1-scope-after-001"></a>
## V1 scope (after 0.01)

~~~json
{"vibecode": {"v1_in": ["charlie", "charlie_cli", "mikobase", "touchstone",
"sammy", "trivet", "uma", "bryton", "jasmine", "puck_identity",
"deployment"], "v1_out": ["robinson"], "v1_blockchain_role":
"external_service; charlie_client_is_thin_http", "v1_http_path":
"sammy_explicit_handlers", "v1_authn": "signed_request", "v1_authz":
"handler_implements_directly; no_declarative_role_policy"}}
~~~

V1 ships Puck.uno as a deployable service. The HTTP layer that ships with
V1 is Sammy (built on Touchstone); the V1 HTTP path is Sammy-style
explicit handlers. **Robinson** (the filesystem-tree page-server) is **not
bundled with V1** — it's a library resolved through Puck on demand, so it
can land on its own timeline without blocking V1. Programs that don't use
Robinson never pull it in; programs that want it call
`%['puck.uno/robinson']` and Puck fetches and caches it on first use.

Authentication is signed-request based; authorization is whatever the handler
implements directly.

The blockchain is treated as an external service. Charlie's blockchain
involvement is a thin HTTP client (~20 lines) that calls the blockchain API
for signature verification, key lookups, etc. The chain itself runs as
separate infrastructure (the existing Python `blockchain/sim/` evolved to
production).

---

<a id="walking-skeleton-roadmap"></a>
## Walking-skeleton roadmap

~~~json
{"vibecode": {"approach": "walking_skeleton", "principle":
"each_phase_runnable_end_to_end; expand_outward_feature_by_feature", "phases":
[{"v": "0.01", "name": "hello_world_ksj", "proves":
"json_parser; ksj_interpreter; stdlib_minimum"}, {"v": "0.02", "name":
"hello_world_charlie", "proves":
"charlie_text_parser; transpiler_to_ksj; round_trip"}, {"v": "0.03",
"name": "charlie_with_stdout", "proves":
"bwc_dispatch; stdout_sink_and_role; puts_bwc"}, {"v": "0.04",
"name": "charlie_with_hashes", "proves":
"hash_class; hash_literal; key_access; ordered_iteration"}, {"v": "0.05",
"name": "charlie_with_json_serialization", "proves":
"to_json_method_on_built_in_classes; round_trip_with_json_parse"},
{"v": "0.0X", "name": "charlie_cli", "proves":
"os_executable_charlie_files; shebang_support; permission_flag_machinery_with_default_restrictive_posture"},
{"v": "0.1", "name": "bryton", "proves":
"first_usable_test_framework_for_charlie_code; runner_walks_dir_and_aggregates_xemes"},
{"v": "0.0X", "name": "first_http_response", "proves":
"sammy_routing; handler_chain; response_object"}, {"v": "0.0X", "name":
"first_db_read", "proves": "mikobase_client; data_flow"}, {"v": "0.0X",
"name": "first_uma_response", "proves":
"trivet; uma; body_handle_to_string"}, {"v": "0.0X", "name":
"first_signed_request", "proves":
"puck_identity; blockchain_api_client"}, {"v": "0.0X", "name":
"first_deployment", "proves": "puck_uno_hosting; ops"}, {"v": "0.0X",
"name": "first_hosted_service", "proves":
"service_on_stack_pattern"}], "continuous_threads": ["jasmine"]}}
~~~

Development proceeds in vertical slices. Each slice is a runnable end-to-end
demo proving a thin band of the stack. The order follows dependencies —
earlier slices unblock later ones. Bryton (tests) and Jasmine (logs) are
continuous threads, used from V0.01 onward.

V0.01 (hello-world in CharlieJSON) and V0.02 (hello-world in Charlie
source, via the new transpiler) bracket the engine's bootstrapping.
V0.03, V0.04, and V0.05 are atomic prerequisites Bryton needs: real
stdout, hash data structures, and JSON serialization. They were once
bundled as a single V0.0X slice; splitting them keeps each slice tiny
and end-to-end runnable. **V0.1 is the first named user-facing
milestone — Bryton.** Beyond V0.1, slice numbers are assigned when the
prior is green.

Bryton is no longer listed as a continuous thread — it's a discrete
V0.1 deliverable. Jasmine (logging) remains a continuous thread,
used wherever a layer needs to surface diagnostic output.

---

<a id="role-system-baking-from-the-start"></a>
## Role system: baking from the start

~~~json
{"vibecode": {"principle": "roles_are_core_not_bolt_on", "reason":
"every_value_must_be_role_tagged_from_creation; retrofit_touches_every_value_creation_path_and_every_method_call_path",
"applies_from": "v001", "spec_doc": "documentation/roles.md",
"v001_primitives": ["role_registry", "owning_role_on_every_value",
"role_transition_on_method_call", "role_system_method",
"chain_wipe_on_cross_role_call"], "v001_deferred": ["faucets", "jails",
"cross_role_trust_declarations", "alarms_with_sink_side_checks",
"source_side_propagation", "chain_isolate_developer_facing"]}}
~~~

Roles are not a bolt-on to Charlie — they are part of the engine's core
architecture from V0.01 onward. The role spec lives in
[roles.md](../charlie/roles.md); this section is the implementation plan for layering
it in incrementally.

**Why roles cannot be deferred.** Every value in the runtime needs an
owning-role tag at creation; every method call needs to check the
receiver's role and transition. Both are pervasive concerns — adding them
later means touching every value-creation path and every method-call path.
Easier to bake the primitives in from the first slice and grow outward.

**V0.01 role footprint.** The minimum to support hello-world's single
cross-role call (`user` → string-class role → `user`):

~~~json
{"vibecode": {"v001_role_footprint": {"registry_entries_min":
["user", "stdlib"], "value_layer":
"every_value_carries_owning_role_slot_immutable_after_creation",
"dispatcher_layer":
"on_method_call_compare_method_owning_role_to_current; if_differ_save_state_set_new_role_wipe_chain_run_restore",
"sys_methods_implemented": ["role"], "chain_state":
"empty_placeholder_but_wipeable_on_boundary"}}}
~~~

- **Role registry.** Engine maintains a name → role-object map.
  Populated at startup with `user` and the engine role owning the
  built-in string class (and any other built-in classes V0.01 touches).
  Per [roles.md](../charlie/roles.md), the broader minimum is `user`, `clock`,
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

~~~json
{"vibecode": {"growth_path": [{"slice": "v0.01", "adds":
"core_primitives_registry_owning_role_transition_role_chain_wipe"},
{"slice": "v0.02", "adds":
"transpiler_role; ksj_emitted_tagged_with_caller_role"},
{"slice": "v0.03", "adds":
"stdout_role; owns_stdout_sink_and_puts_bwc; first_cross_role_boundary_for_engine_supplied_io"},
{"slice": "v0.04", "adds":
"no_new_role_primitives; built_in_hash_class_registered_under_existing_stdlib_role; same_pattern_as_v001_string_class"},
{"slice": "v0.05", "adds":
"no_new_role_primitives; to_json_methods_register_on_existing_stdlib_class_methods"},
{"slice": "v0_0x_cli", "adds":
"stderr_role; per_dirjail_roles_when_allow_fs_flag_used; per_faucet_roles_when_allow_net_flag_used; env_vars_and_cli_args_roles"},
{"slice": "first_http", "adds":
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
"when_string_provenance_question_settles"}}}
~~~

| Slice | Role additions |
|---|---|
| V0.01 | Core: registry, `owning_role` on values, transition-on-call, `%role`, `%chain` wipe |
| V0.02 | Transpiler role; emitted CharlieJSON tagged with caller role |
| V0.03 | `stdout` role; owns the stdout sink and the `puts` bwc; first cross-role boundary for engine-supplied I/O |
| V0.04 | No new role primitives; built-in hash class is registered under the existing `stdlib` role (same pattern as V0.01's string class) |
| V0.05 | No new role primitives; `to_json` methods register on existing `stdlib`-owned classes |
| V0.0X CLI | `stderr` role; per-dirjail roles when `--allow-fs` is used; per-faucet roles when `--allow-net` is used; `env_vars` and `cli_args` roles |
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
[string-provenance question](../charlie/roles.md#open-questions) settles.

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

<a id="engine-startup-and-invocation"></a>
## Engine startup and invocation

~~~json
{"vibecode": {"section": "engine_startup_and_invocation", "scope":
"how_a_ksj_program_actually_runs_from_invocation_through_return",
"applies_from": "v001", "covers": ["host_vs_engine_distinction",
"invocation_chain", "bootstrap_sequence", "program_model",
"what_user_ksj_can_see", "how_later_slices_extend"]}}
~~~

This section spells out the lifecycle of a CharlieJSON run end-to-end: who
launches it, what the engine does before user code executes, what user
code can actually reference, and how that lifecycle grows in later
slices. It answers two related questions that came up while scoping
V0.01: **how do you start a CharlieJSON script** and **how does the engine load
allowed objects into the outermost CharlieJSON block**.

<a id="host-vs-engine"></a>
### Host vs. engine

~~~json
{"vibecode": {"host_vs_engine": {"engine":
"the_library_that_runs_ksj; located_under_code_charlie_lua",
"host": "anything_that_calls_into_the_engine; varies_by_slice",
"v001_host": "lua_test_runner_invoked_from_command_line",
"later_hosts": ["standalone_cli_via_v00x_charlie_cli_slice",
"sammy_request_handler_v003_plus",
"one_running_ksj_calling_another_via_function_dispatch"]}}}
~~~

The **engine** is the Lua library at `code/charlie/lua/` that knows how
to parse and execute CharlieJSON. The **host** is whatever calls into the
engine. They are different layers.

In V0.01 the host is a Lua test runner invoked from the command line.
Later hosts include the standalone `charlie` CLI (arrives in the
[V0.0X charlie-cli slice](#v00x-charlie-command-line-execution),
prerequisite for V0.1 Bryton), a Sammy request handler (at the
first-HTTP slice — every handler closure is itself CharlieJSON that the engine
runs in response to a request), and one piece of running CharlieJSON calling
another (which emerges from normal function dispatch, no separate
engine API needed). Each host invokes the same `engine.run()` entry
point; what differs is who triggers it and what they pass in.

<a id="v001-invocation-chain"></a>
### V0.01 invocation chain

~~~json
{"vibecode": {"v001_invocation_chain": [{"step": 1, "name":
"command_line_invocation", "example":
"lua tests/charlie/run.lua tests/charlie/fixtures/hello_world.cjs"},
{"step": 2, "name": "runner_loads_engine_as_lua_library",
"example": "local engine = require(\"charlie\")"}, {"step": 3,
"name": "runner_calls_engine_run_with_file_path", "example":
"local result = engine.run(\"tests/charlie/fixtures/hello_world.cjs\")"},
{"step": 4, "name": "engine_bootstrap_then_parse_then_execute",
"covered_in_next_subsection": true}, {"step": 5, "name":
"engine_returns_last_statement_value_to_runner_as_lua_value"},
{"step": 6, "name":
"runner_compares_to_expected_string_hello_and_reports_pass_or_fail"}]}}
~~~

Top-level shape:

1. **Command-line invocation.** Something like
   `lua tests/charlie/run.lua tests/charlie/fixtures/hello_world.cjs`.
2. **Runner loads the engine as a Lua library.** Roughly
   `local engine = require("charlie")`.
3. **Runner calls `engine.run()` with the fixture path.** Roughly
   `local result = engine.run("...fixtures/hello_world.cjs")`.
4. **Engine bootstrap, parse, and execute happen behind that one
   call.** Detailed below.
5. **Engine returns the last statement's value to the runner** as a Lua
   return value.
6. **Runner compares to expected `"hello"`** and reports PASS or FAIL.

<a id="v001-engine-bootstrap-sequence"></a>
### V0.01 engine bootstrap sequence

~~~json
{"vibecode": {"v001_bootstrap_sequence": [{"step": 1, "name":
"create_role_registry", "creates": ["user", "stdlib"],
"role_object_v001":
"name_only_no_methods_no_state_no_trust_web"}, {"step": 2, "name":
"create_built_in_string_class", "creates":
"string_class_object_with_one_method_to_string_returning_self",
"tagged_with": "stdlib"}, {"step": 3, "name":
"establish_execution_context", "sets":
{"current_role": "user", "chain": "empty_placeholder"}}, {"step":
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

4. **Load and parse the CharlieJSON file.** The engine reads the path it was
   handed, gives the text to the JSON parser, gets back a parsed tree.
   For V0.01 the tree is `[[{"value": "hello"}, "to_string"]]`.

5. **Execute top-level statements.** The engine iterates the outermost
   array. For each statement, it calls the statement dispatcher; the
   dispatcher handles literal materialization, method lookup, role
   transition, and method execution. Each statement's return value is
   captured; the last one is what gets surfaced.

6. **Return to host.** The captured last-value is returned to the host
   (in V0.01, the Lua test runner) as a Lua return value.

<a id="program-model"></a>
### Program model

~~~json
{"vibecode": {"program_model_v001": {"shape":
"top_level_array_of_statements", "entry_point":
"the_outermost_array_itself_no_main_function",
"result_of_program":
"value_of_last_top_level_statement", "execution":
"statements_run_in_order"}}}
~~~

A CharlieJSON program is a **top-level array of statements**. The engine
executes them in order. The "result" of the program is the value of
the last top-level statement. There is no `main` function and no
entry-point declaration — the outermost array IS the entry point.

Statements can define functions and call them, but for V0.01 the
program is just one statement.

<a id="what-user-charliejson-can-see-in-v001"></a>
### What user CharlieJSON can see in V0.01

~~~json
{"vibecode": {"v001_visibility": {"directly_referenceable_by_name":
"nothing", "implicitly_available":
["string_class_via_literal_materialization",
"to_string_via_method_dispatch_on_string_values"],
"explicitly_unavailable_v001":
["sys_references_percent_stdout_percent_role_etc",
"other_built_in_classes_integer_hash_array",
"faucets", "jails", "trust_declarations"]}}}
~~~

The V0.01 fixture doesn't reference any object by name. It only:

- Materializes a string literal (`{"value": "hello"}`) — the engine's
  literal-materializer knows about the string class and tags the new
  value with that class.
- Calls a method on the value (`"to_string"`) — the dispatcher looks
  up the method on the receiver's class.

The string class is **not exposed as a named object** in V0.01. It's
**discovered** by the dispatcher when a method call lands on a string
value. This is the simplest possible answer to "how do allowed objects
get loaded into the outermost CharlieJSON block": in V0.01, they don't get
loaded explicitly at all — they're available only through the
dispatcher's class-lookup mechanism for values the engine itself
created.

<a id="how-later-slices-grow-the-lifecycle"></a>
### How later slices grow the lifecycle

~~~json
{"vibecode": {"growth_path": {"v002": {"bootstrap_change":
"none; transpiler_runs_before_engine_invoked",
"invocation_change":
"runner_may_optionally_transpile_charlie_text_to_ksj_before_engine_run; engine_still_consumes_ksj"},
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

V0.02 (transpiler) doesn't change the bootstrap sequence — the
transpiler runs before the engine is invoked (probably as a runner-side
step that turns `.charlie` text into CharlieJSON), and the engine consumes the
CharlieJSON exactly as in V0.01.

Later slices extend the lifecycle in these ways:

- **New hosts.** The first HTTP slice introduces a Sammy request
  handler as a host: an incoming request triggers a handler closure
  (itself CharlieJSON) to execute. Same `engine.run()`-shaped entry; the
  caller is different.
- **Sys references** (`%stdout`, `%now`, `%role`, `%puck`, etc.). The
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
specifies which built-ins and faucets a given Charlie instance can
access); role-driven (a role's trust web determines what it can see).
This is core to "running untrusted code" — the engine must be able to
launch a Charlie instance with a restricted surface that the running
code cannot escape. Flagged as an open item.

---

<a id="lua-side-implementation-sketch"></a>
## Lua-side implementation sketch

~~~json
{"vibecode": {"section": "lua_implementation_sketch", "status":
"candidate_shape; to_be_reconciled_with_existing_code_during_inventory",
"language": "lua_5_4_assumed", "style":
"plain_tables_no_metatables_for_v001; closures_for_role_transition_save_restore",
"deliberately_not_specified":
["module_layout_within_code_charlie_lua_charlie_directory",
"naming_conventions_for_internal_locals",
"exact_signature_of_existing_json_lua"]}}
~~~

This section sketches the engine's internal Lua shape for V0.01: data
structures, key procedures, and a pseudo-code skeleton. It is a
**candidate target** to be reconciled with what's already in
`code/charlie/lua/charlie/` during Step 1 (inventory) of Phase 1. Where
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
"execution_context":
"{current_role = role_object, chain = lua_table_placeholder}"}}}
~~~

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
      stdlib = { name = "stdlib" },
  }
  ```

- **Value.** Every CharlieJSON value the runtime holds is a Lua table with
  three fields:
  ```lua
  { type = "string", owning_role = engine.roles.user, payload = "hello" }
  ```
  The `owning_role` field is a *reference* to one of the role objects
  in `engine.roles` — same Lua table, shared. Once set, it's never
  reassigned (immutable per [roles.md](../charlie/roles.md)).

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

<a id="key-procedures"></a>
### Key procedures

~~~json
{"vibecode": {"procedures": {"engine.run":
"(path) -> last_statement_value; entry_point",
"engine.bootstrap":
"() -> nil; populates_roles_classes_ctx", "engine.dispatch":
"(statement) -> value; handles_one_top_level_statement",
"engine.materialize": "(expr) -> value; turns_ksj_expression_into_value",
"engine.transition":
"(new_role, fn) -> result; save_restore_ctx_around_fn_call",
"engine.lookup_method": "(value, method_name) -> method_fn"}}}
~~~

Five procedures cover V0.01:

- `engine.run(path)` — entry point called by the host.
- `engine.bootstrap()` — populates the role registry, class registry,
  and execution context. Runs once per `engine.run` invocation.
- `engine.dispatch(statement)` — handles one parsed statement (the
  `[receiver, method, args?]` triple).
- `engine.materialize(expr)` — turns a CharlieJSON expression
  (`{"value": ...}`, etc.) into a value table with `owning_role` tag.
- `engine.transition(new_role, fn)` — wraps a Lua function call with
  save/restore of `engine.ctx`. Uses Lua's call stack via closures;
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
local json = require("charlie.json")     -- existing json.lua

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

<a id="notes-on-the-sketch"></a>
### Notes on the sketch

~~~json
{"vibecode": {"sketch_notes": ["plain_tables_only_no_metatables_v001",
"role_objects_shared_by_reference_across_owning_role_fields",
"transition_uses_lua_call_stack_via_closure_no_explicit_transition_stack",
"chain_is_initialized_to_empty_table_wipe_means_replace_with_fresh_table",
"errors_use_lua_error_for_v001_no_charlie_exception_machinery_yet",
"json_parse_assumed_to_return_nested_lua_tables_arrays_indexed_from_1"]}}
~~~

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
- **Errors use Lua `error()` for V0.01.** Charlie-level exception
  machinery (alarms vs. regular exceptions per [roles.md](../charlie/roles.md))
  lands in a later slice. For V0.01, anything wrong = engine bails
  with a Lua error.
- **JSON parser is assumed to return nested Lua tables**, arrays as
  arrays indexed from 1 (Lua-standard). To be confirmed during Step 1
  inventory of the existing `json.lua`.

---

<a id="v001-phase-0-lua-workbench"></a>
## V0.01 phase 0: Lua workbench

~~~json
{"vibecode": {"phase": 0, "version": "0.01", "purpose":
"set_up_and_verify_lua_dev_environment_before_writing_any_engine_code",
"explicitly_excludes": "executing_charlie_or_ksj; only_lua_level_sanity",
"steps_count": 6, "acceptance":
"all_six_workbench_steps_pass; no_engine_code_written", "tactic":
"verify_the_workbench_before_building_in_it"}}
~~~

Before writing any engine code, the Lua-side development environment
has to be verified. Six steps, each independently runnable. If a step
fails, fix that before moving on. **No Charlie or CharlieJSON execution
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
"set_package_path_prefix_to_code_charlie_lua; require_a_known_engine_module_no_error",
"expected": "require_call_returns_a_table_without_error"}}
~~~

The engine lives under `code/charlie/lua/`. Lua needs to find modules
when `require("charlie.X")` is called. The convention:

```lua
package.path = "code/charlie/lua/?.lua;" .. package.path
```

Verify with a real existing engine module — `charlie.json` is the
natural choice since it's already in the tree:

The existing `tests/charlie/run.lua` already sets up `package.path` to
resolve both `code/charlie/lua/?.lua` (engine modules) and
`tests/charlie/?.lua` (test-side modules including `support.runner`).
If launching tests from a different entry point, mirror that setup.

A small sanity test exercising the path:

```lua
-- tests/sanity/test_package_path.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("charlie.json")

runner.suite("sanity / package path")

runner.test("charlie.json loaded as a table", function()
    assert_.equal(type(json), "table")
end)
```

<a id="step-04-verify-the-existing-test-framework"></a>
### Step 0.4: Verify the existing test framework

~~~json
{"vibecode": {"step": "0.4", "name": "verify_existing_test_framework",
"existing_runner_module": "tests/charlie/support/runner.lua",
"existing_assert_module": "tests/charlie/support/assert.lua",
"existing_entry_point": "tests/charlie/run.lua",
"do_not": "invent_a_new_harness; use_what_is_already_there",
"runner_api": {"suite": "(name)", "test": "(name, fn)", "report":
"() returns true_if_all_passed"}, "assert_api":
["equal", "not_equal", "is_nil", "not_nil", "is_true", "is_false",
"kind", "count", "parse_error"], "verification":
"write_one_trivial_test_that_uses_runner_and_assert; require_it_from_run_lua_or_a_v001_entry_point; confirm_passes_and_fails_are_reported_correctly"}}
~~~

The project already has a Lua test framework under
`tests/charlie/support/`:

- `support/runner.lua` — provides `runner.suite(name)`,
  `runner.test(name, fn)`, and `runner.report()`. Maintains pass/fail
  counts across all tests required during a run; prints `.` per pass,
  `F` per fail, then a summary.
- `support/assert.lua` — assertion helpers including `equal`,
  `not_equal`, `is_nil`, `not_nil`, `is_true`, `is_false`, `kind`,
  `count`, `parse_error`. Each errors with a descriptive message on
  failure.
- `tests/charlie/run.lua` — entry point. Adds `package.path`, requires
  all test modules, calls `runner.report()`, exits 0/1.

The existing lexer/parser/transpiler tests already use this framework
(`tests/charlie/lexer/test_literals.lua`, etc.). **Use it as-is for
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

Then require it from `tests/charlie/run.lua` (or a temporary V0.01-only
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
"requires_module": "charlie.json", "parses": "{\"a\": 1}",
"expected": "lua_table_with_a_equals_1", "side_effect":
"discovers_json_lua_actual_api_for_inventory_step",
"framework_used": "tests/charlie/support/runner_and_assert"}}
~~~

The existing `code/charlie/lua/charlie/json.lua` is assumed to provide
a `parse` function. This step confirms it (and surfaces any API
surprises for the V0.01 phase 1 inventory step).

```lua
-- tests/sanity/test_json_parse.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("charlie.json")

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

<a id="step-06-verify-file-reading"></a>
### Step 0.6: Verify file reading

~~~json
{"vibecode": {"step": "0.6", "name": "file_read_sanity",
"fixture_path": "tests/charlie/fixtures/_sanity_text.txt",
"fixture_content": "ok\\n", "test_file":
"tests/sanity/test_file_read.lua",
"framework_used": "tests/charlie/support/runner_and_assert"}}
~~~

The engine has to read CharlieJSON files from disk; this step confirms that
works.

Fixture: `tests/charlie/fixtures/_sanity_text.txt` containing the two
bytes `ok` followed by a newline.

```lua
-- tests/sanity/test_file_read.lua
local runner = require("support.runner")
local assert_ = require("support.assert")

runner.suite("sanity / file read")

runner.test("io.open + read('*a') returns expected bytes", function()
    local f = assert(io.open("tests/charlie/fixtures/_sanity_text.txt", "r"))
    local content = f:read("*a")
    f:close()
    assert_.equal(content, "ok\n")
end)
```

When all six steps pass, the workbench is verified and Phase 1 can
begin.

<a id="phase-0-test-plan"></a>
### Phase 0 test plan

~~~json
{"vibecode": {"phase_0_tests":
[{"id": "T0.1", "verifies": "lua_5_4_installed", "tool":
"command_line_lua_dash_v", "framework": "none"}, {"id": "T0.2",
"verifies": "pure_lua_script_runs_and_prints", "tool":
"tests/sanity/lua_hello.lua", "framework": "none"}, {"id": "T0.3",
"verifies": "package_path_resolves_charlie_json_via_require",
"tool": "tests/sanity/test_package_path.lua", "framework":
"support_runner_and_assert"}, {"id": "T0.4", "verifies":
"existing_test_framework_reports_pass_fail_and_exit_code", "tool":
"tests/sanity/test_framework_sanity.lua", "framework":
"support_runner_and_assert"}, {"id": "T0.5", "verifies":
"charlie_json_parse_handles_simple_object", "tool":
"tests/sanity/test_json_parse.lua", "framework":
"support_runner_and_assert"}, {"id": "T0.6", "verifies":
"file_io_read_returns_expected_bytes", "tool":
"tests/sanity/test_file_read.lua", "framework":
"support_runner_and_assert"}]}}
~~~

T0.1 and T0.2 are pre-framework — Lua isn't even confirmed working
yet, so they can't depend on `support/runner.lua`. T0.3 onward use the
project's existing framework (`tests/charlie/support/runner.lua` +
`support/assert.lua`).

| ID | Verifies | Tool | Framework |
|---|---|---|---|
| T0.1 | Lua 5.4 installed | `lua -v` | none |
| T0.2 | Pure Lua script runs and prints | `tests/sanity/lua_hello.lua` | none |
| T0.3 | package.path resolves charlie modules | `tests/sanity/test_package_path.lua` | `support/runner` |
| T0.4 | Existing framework reports pass/fail | `tests/sanity/test_framework_sanity.lua` | `support/runner` |
| T0.5 | json.lua parses simple object | `tests/sanity/test_json_parse.lua` | `support/runner` |
| T0.6 | File I/O read returns expected bytes | `tests/sanity/test_file_read.lua` | `support/runner` |

All six must pass before V0.01 phase 1 begins.

---

<a id="v001-phase-1-hello-world-in-charliejson"></a>
## V0.01 phase 1: hello-world in CharlieJSON

~~~json
{"vibecode": {"phase": 1, "version": "0.01", "fixture_path":
"tests/charlie/fixtures/hello_world.cjs", "fixture_content":
"[[{\"value\": \"hello\"}, \"to_string\"]]", "runner_path":
"tests/charlie/run.lua", "acceptance":
"fixture_runs_via_engine_and_harness_captures_return_value_hello",
"required_ksj_forms": ["value_literal", "statement_call"], "required_runtime":
["json_parser", "ksj_format_alignment_to_canonical_charliejson_spec",
"statement_dispatcher_with_role_transition",
"method_dispatch", "literal_materialization_with_owning_role_tag",
"role_registry_with_user_and_stdlib", "role_system_method",
"chain_wipe_on_boundary",
"top_level_returns_last_statement_value_to_harness"],
"required_stdlib": ["string_class_min_with_to_string_returning_self"],
"tactic": "inventory_then_fill_gaps_and_align_format; spec_wins_over_existing_code",
"canon": "charliejson_md_is_canonical; existing_transpiler_interpreter_format_is_pre_spec_and_gets_brought_into_line",
"deferred_to_v002":
["charlie_text_parser", "transpiler_emitting_canonical_ksj"],
"deferred_to_later":
["sys_references_including_stdout", "stdout_io",
"any_method_beyond_to_string", "any_class_beyond_string"]}}
~~~

The first concrete development task. Work splits into three steps. The
tactic is **inventory then fill gaps** — but with an important caveat:
the existing engine consumes a CharlieJSON shape that **predates the
canonical [charliejson.md](../charlie/charliejson.md) spec.** The
[V0.01 fixture](#v001-hello-world) is in the canonical form; the
existing interpreter currently isn't.

**Canon: the spec wins.** When `charliejson.md` and the existing
engine disagree, the spec is authoritative and the engine gets
brought into line. The format-alignment work is part of V0.01
scope, not a separate slice — Phase 1 doesn't end until the
interpreter consumes canonical CharlieJSON. (Per
[`feedback_surface_conflicts`](../../../.claude/projects/-home-miko-projects-mikobase-working/memory/feedback_surface_conflicts.md):
this is a specific decision for this specific conflict, not a
universal rule. Future conflicts get surfaced and resolved
case-by-case.)

The existing engine under `code/charlie/lua/charlie/` has a
`json.lua`, `interpreter.lua`, and other modules with 172 passing
tests. The V0.01 work is to (a) verify the JSON parser handles the
canonical form, (b) realign the CharlieJSON-execution path to the
canonical statement shape `[receiver, method, args?]`, and (c)
complete enough of the executor to run `hello-world`. The Charlie
text path (`lexer.lua`, `parser.lua`, `transpiler.lua`) is V0.02
work; when it lands, the transpiler must also emit canonical CharlieJSON
so the source→runtime pipeline is end-to-end canonical.

<a id="step-1-inventory"></a>
### Step 1: Inventory

~~~json
{"vibecode": {"step": 1, "name": "inventory", "actions":
["read_existing_json_lua", "read_existing_interpreter_lua",
"note_state_of_json_parser", "note_state_of_ksj_executor",
"confirm_text_side_modules_exist_as_scaffolding_only"], "output":
"state_of_engine_doc; gap_list_for_v001"}}
~~~

Read what's already in `code/charlie/lua/charlie/`: in particular `json.lua`
and `interpreter.lua`. Note the state of each:

- Does `json.lua` parse the JSON forms `hello-world.cjs` needs (top-level
  array, nested array, object with string keys, string values)?
- Does `interpreter.lua` accept a parsed CharlieJSON tree and dispatch
  statements?

`lexer.lua`, `parser.lua`, and `transpiler.lua` are Charlie-text-side
concerns deferred to V0.02. Confirm they exist as scaffolding; don't trial
them for V0.01.

Output: a short gap list — "the JSON parser handles these forms / doesn't
handle these; the interpreter executes these CharlieJSON shapes / doesn't
execute these; this is what's needed to clear V0.01."

<a id="step-2-fill-the-gaps"></a>
### Step 2: Fill the gaps

~~~json
{"vibecode": {"step": 2, "name": "fill_gaps", "scope":
"only_what_v001_needs; not_full_ksj_spec",
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

For each gap in the inventory, add only what V0.01 needs.
**Don't generalize ahead of the test.** The required surface is tiny:

- Enough JSON parsing to read `[[{"value": "hello"}, "to_string"]]`.
- Enough CharlieJSON execution to handle one top-level statement list,
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

<a id="step-3-verify"></a>
### Step 3: Verify

~~~json
{"vibecode": {"step": 3, "name": "verify", "actions":
["create_ksj_fixture_file", "run_via_engine",
"capture_last_statement_return_value", "compare_to_expected_string_hello"],
"pass_condition":
"return_value_equals_hello_and_no_exception_raised", "fail_condition":
"any_deviation; failure_message_should_name_which_layer_blocked"}}
~~~

Create the fixture at `tests/charlie/fixtures/hello_world.cjs` containing
the CharlieJSON encoding, run it via the engine, capture the last
statement's return value, compare to the string `"hello"`. Pass = exact
match on return value plus no exception. Fail = capture which layer
blocked (JSON parse error? statement dispatch failed? literal
materialization failed? `to_string` method missing? role transition
botched? return-to-harness path missing?). That layer is the next thing
to fix; loop back to Step 2.

When V0.01 passes, V0.02 (hello-world in Charlie source, via the transpiler)
is selected from the roadmap and planned in the same three-step shape.

<a id="phase-1-test-plan"></a>
### Phase 1 test plan

~~~json
{"vibecode": {"phase_1_tests":
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
"unit_observability_check"}]}}
~~~

Seven unit tests plus one end-to-end integration test verify Phase 1.
Each test is a Lua file under `tests/charlie/v001/` using the existing
project framework (`support.runner` + `support.assert`), required from
`tests/charlie/run.lua` (or a V0.01-specific entry point) and reported
through `runner.report()`.

Skeleton for a V0.01 test file:

```lua
-- tests/charlie/v001/test_bootstrap.lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local engine = require("charlie")

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
| T1.5 | unit | transition save/restore | Call `engine.transition(engine.roles.stdlib, function() return engine.ctx.current_role end)`; verify return == `engine.roles.stdlib` AND after the call `engine.ctx.current_role == engine.roles.user` and `engine.ctx.chain` is the original table |
| T1.6 | unit | dispatch one statement | `engine.dispatch({{value="hello"}, "to_string"})` returns a value with `payload == "hello"` |
| T1.7 | integration | full end-to-end | `engine.run("tests/charlie/fixtures/hello_world.cjs")` returns a value whose `payload == "hello"` |
| T1.8 | unit | transition observed | A spy in the `to_string` method records `engine.ctx.current_role` at call time; assert it was `engine.roles.stdlib`, not `engine.roles.user` |

T1.8 is the load-bearing test for the role system: it proves the
transition *actually happened* (not just that it was set up). Without
it, role machinery could be missing entirely and the other tests
would still pass.

All eight pass = V0.01 done.

<a id="test-layout"></a>
### Test layout

~~~json
{"vibecode": {"test_framework":
"project_existing_at_tests_charlie_support_runner_and_assert; do_not_invent_a_new_one",
"file_naming_convention":
"test_topic_dot_lua_matching_existing_lexer_parser_transpiler_files",
"directory_layout": {"tests/sanity/":
"phase_0_workbench_sanity_tests_engine_independent",
"tests/charlie/fixtures/":
"ksj_and_text_fixtures_consumed_by_engine_or_tests",
"tests/charlie/v001/":
"phase_1_unit_and_integration_tests_for_v001",
"tests/charlie/run.lua":
"shared_entry_point_requires_all_test_modules_and_calls_runner_report",
"tests/charlie/support/":
"existing_runner_and_assert_modules_unchanged"}}}
~~~

The project uses its existing test framework — `tests/charlie/support/runner.lua`
(provides `suite`, `test`, `report`) and `tests/charlie/support/assert.lua`
(assertion helpers). No new framework gets invented for V0.01. File
naming follows the existing convention (`test_<topic>.lua`).

| Path | Contents |
|---|---|
| `tests/sanity/` | Phase 0 workbench tests (engine-independent) |
| `tests/charlie/fixtures/` | CharlieJSON and text fixtures (e.g., `hello_world.cjs`, `_sanity_text.txt`) |
| `tests/charlie/v001/` | Phase 1 unit and integration tests (V0.01-specific) |
| `tests/charlie/run.lua` | Entry point — extended to also require sanity + V0.01 tests |
| `tests/charlie/support/` | Existing `runner.lua` and `assert.lua`, unchanged |

Existing scaffolding under `tests/charlie/lexer/`, `tests/charlie/parser/`,
and `tests/charlie/transpiler/` is V0.02+ territory; not exercised by
V0.01 directly but already uses the same framework so the patterns
above mirror what's there.

---

<a id="v002-phase-0-source-side-workbench"></a>
## V0.02 phase 0: source-side workbench

~~~json
{"vibecode": {"phase": 0, "version": "0.02", "purpose":
"characterize_existing_lexer_parser_transpiler_state_against_v002_fixture; no_realignment_work_yet",
"steps_count": 4, "acceptance":
"all_four_workbench_checks_pass_and_produce_a_concrete_gap_list_for_phase_1; no_engine_code_changed",
"tactic":
"exercise_existing_pipeline_with_v002_fixture_string; observe_each_layer_output",
"differs_from_v001_phase_0":
"v001_phase_0_verified_lua_environment_and_json_lua_existed; v002_phase_0_verifies_existing_charlie_source_pipeline_handles_the_fixture_input"}}
~~~

V0.02's workbench is the existing Charlie source pipeline (lexer →
parser → transpiler). Before realigning the transpiler, Phase 0
characterizes what each layer produces today for the V0.02 fixture
string. The output is a concrete gap list driving Phase 1 step 2.

Phase 0 changes no engine code. It exists to surface surprises before
implementation.

<a id="step-01-confirm-the-lexer-tokenizes-the-fixture"></a>
### Step 0.1: Confirm the lexer tokenizes the fixture

~~~json
{"vibecode": {"step": "0.1", "name": "lexer_check",
"input": "'hello'.to_string",
"expected_token_kinds_in_order":
["string_literal", "dot", "identifier"],
"tool": "charlie.tokenize from init.lua",
"acceptance":
"no_lex_error; token_sequence_includes_string_literal_hello_then_dot_then_identifier_to_string"}}
~~~

`charlie.tokenize("'hello'.to_string")` returns a token sequence
covering the literal, the dot, and the identifier `to_string`. Existing
lexer tests under `tests/charlie/lexer/` exercise each form
individually; this step confirms the combination tokenizes cleanly.

<a id="step-02-confirm-the-parser-produces-a-clean-ast"></a>
### Step 0.2: Confirm the parser produces a clean AST

~~~json
{"vibecode": {"step": "0.2", "name": "parser_check",
"input": "'hello'.to_string",
"expected_program_shape":
"program_node_with_one_statement_node_representing_a_method_call_on_a_string_literal",
"tool": "charlie.parse from init.lua",
"acceptance":
"no_parse_error; ast_shape_documented_for_phase_1_inventory"}}
~~~

`charlie.parse("'hello'.to_string")` returns an AST. Step 0.2 documents
the exact `kind` of the top-level node, the method-call node, and the
literal node so Phase 1 step 1 can compare directly.

<a id="step-03-observe-the-transpilers-current-output"></a>
### Step 0.3: Observe the transpiler's current output

~~~json
{"vibecode": {"step": "0.3", "name": "transpiler_baseline",
"input": "'hello'.to_string",
"tool": "charlie.transpile from init.lua",
"expected":
"captures_actual_current_output_for_comparison_to_canonical_in_phase_1",
"acceptance":
"transpile_completes_without_error; output_recorded_as_phase_1_baseline; current_shape_is_pre_canonical_and_that_is_expected"}}
~~~

`charlie.transpile("'hello'.to_string")` returns a Lua table. The
current output is pre-canonical — it matches `interpreter.lua`'s
consumption shape, not `charliejson.md`'s `[receiver, method, args?]`
shape. Phase 0 captures what comes out today; the diff against canonical
is computed in Phase 1.

<a id="step-04-confirm-enginerun-handles-a-hand-built-canonical-tree"></a>
### Step 0.4: Confirm engine.run handles a hand-built canonical tree

~~~json
{"vibecode": {"step": "0.4", "name": "engine_tree_entry_check",
"action":
"build_the_v001_canonical_tree_in_lua_pass_to_a_run_tree_helper_or_equivalent_path",
"acceptance":
"end_to_end_returns_value_with_payload_hello_using_a_lua_built_tree_not_a_file",
"note":
"validates_the_run_tree_internal_split_before_phase_1_wires_it_to_transpiler_output"}}
~~~

The V0.01 engine takes a path (`engine.run(path)`) — it reads the file,
parses JSON, then iterates. To wire the transpiler in, the file-read +
JSON-parse step has to be separable from the dispatch loop. Step 0.4
confirms (or, if needed, introduces) a callable
`engine.run_tree(tree)` that takes a pre-built canonical CharlieJSON Lua table
and returns the same result the file-based path would.

If the V0.01 implementation already factored this out, Step 0.4 is a
one-line test. If not, Step 0.4 adds the helper purely as refactoring
(behavior unchanged for the existing path).

<a id="v002-phase-0-test-plan"></a>
### V0.02 phase 0 test plan

~~~json
{"vibecode": {"phase_0_tests":
[{"id": "T2.0.1", "verifies":
"lexer_handles_v002_fixture_string", "tool":
"tests/charlie/v002/test_lexer_check.lua", "level": "unit"},
{"id": "T2.0.2", "verifies":
"parser_returns_ast_for_v002_fixture_string", "tool":
"tests/charlie/v002/test_parser_check.lua", "level": "unit"},
{"id": "T2.0.3", "verifies":
"transpiler_completes_without_error_for_v002_fixture_string; current_output_captured_for_phase_1_comparison",
"tool": "tests/charlie/v002/test_transpiler_baseline.lua",
"level": "unit"}, {"id": "T2.0.4", "verifies":
"engine_run_tree_returns_value_for_hand_built_canonical_tree",
"tool": "tests/charlie/v002/test_engine_run_tree.lua",
"level": "unit"}]}}
~~~

| ID | Level | Verifies | Tool |
|---|---|---|---|
| T2.0.1 | unit | Lexer handles the fixture string | `test_lexer_check.lua` |
| T2.0.2 | unit | Parser returns an AST for the fixture | `test_parser_check.lua` |
| T2.0.3 | unit | Transpiler completes for the fixture; baseline captured | `test_transpiler_baseline.lua` |
| T2.0.4 | unit | `engine.run_tree` returns expected value for a hand-built tree | `test_engine_run_tree.lua` |

All four must pass (or the underlying issues must be resolved) before
V0.02 phase 1 begins.

---

<a id="v002-phase-1-hello-world-from-charlie-source"></a>
## V0.02 phase 1: hello-world from Charlie source

~~~json
{"vibecode": {"phase": 1, "version": "0.02", "fixture_path":
"tests/charlie/fixtures/hello_world.charlie", "fixture_content":
"'hello'.to_string", "runner_path":
"tests/charlie/run.lua", "acceptance":
"fixture_transpiles_to_canonical_ksj_and_engine_run_source_returns_value_payload_hello",
"required_work":
["transpiler_realignment_for_hello_world_ast_only",
"engine_run_source_entry_point",
"engine_run_tree_internal_helper_if_not_already_present",
"deep_equal_assert_helper"], "reuses_from_v001":
["bootstrap", "materialize", "lookup_method", "transition", "dispatch"],
"out_of_scope":
["full_transpiler_retrofit", "interpreter_lua_removal",
"renaming_or_deprecation_of_existing_charlie_run_source_in_init_lua",
"sys_references_or_stdout_io",
"additional_classes_or_methods_beyond_to_string"],
"tactic":
"minimal_realignment_just_for_hello_world_ast; later_slices_extend",
"canon":
"charliejson_md_is_canonical; transpiler_output_must_match_v001_hand_written_fixture_for_this_ast"}}
~~~

Three steps. Same shape as V0.01 Phase 1: inventory, fill gaps, verify.

<a id="v002-step-1-inventory"></a>
### V0.02 Step 1: Inventory

~~~json
{"vibecode": {"step": 1, "name": "inventory", "actions":
["catalog_existing_lexer_parser_transpiler_against_v002_fixture",
"document_ast_shape_for_method_call_on_string_literal",
"document_current_transpiler_output_for_that_ast",
"compute_diff_to_canonical_ksj_target",
"identify_which_transpiler_test_files_will_need_updating"],
"output":
"concrete_gap_description_for_step_2; list_of_existing_transpiler_tests_to_be_updated"}}
~~~

Read the existing `lexer.lua`, `parser.lua`, and `transpiler.lua` with
the V0.02 fixture in mind. Document:

- The exact AST node `kind` returned for `'hello'.to_string`.
- The exact Lua-table shape the current transpiler emits for that AST
  node.
- The diff between that shape and the canonical
  `[[{"value": "hello"}, "to_string"]]`.
- The set of existing transpiler tests under
  `tests/charlie/transpiler/` that assert on the pre-canonical shape
  for the AST nodes we'll realign. These will need updating in Step 2.

Output: a short text summary of the gap (which fields differ, which
wrapper objects are present in one but not the other) plus the list of
transpiler tests requiring updates.

<a id="v002-step-2-fill-the-gaps"></a>
### V0.02 Step 2: Fill the gaps

~~~json
{"vibecode": {"step": 2, "name": "fill_gaps", "scope":
"transpiler_path_for_hello_world_ast_only; not_full_realignment",
"work_items":
["transpiler_emit_canonical_for_string_literal_expression",
"transpiler_emit_canonical_for_method_call_expression",
"transpiler_emit_canonical_for_top_level_expression_statement_wrapper",
"engine_run_tree_helper_extracted_from_engine_run_if_not_already",
"engine_run_source_function_combining_transpile_and_run_tree",
"support_assert_deep_equal_helper_added"], "non_work":
["other_ast_node_types_left_pre_canonical",
"interpreter_lua_and_its_tests_left_untouched",
"existing_transpiler_tests_updated_only_for_realigned_paths"]}}
~~~

For each gap from Step 1, add only what V0.02 needs:

- **Transpiler.** Realign the path covering the AST nodes the V0.02
  fixture produces — likely the string-literal expression, the
  method-call expression, and the top-level expression-statement
  wrapper. Other AST node types (assignment, if, while, bwc, function
  definition, etc.) stay pre-canonical for now.
- **Engine wiring.** Add `engine.run_source(path)` that reads a
  `.charlie` file, transpiles to canonical CharlieJSON, and iterates the
  dispatch loop. If `engine.run` doesn't already separate file-read
  from dispatch, extract `engine.run_tree(tree)` and refactor
  `engine.run` to call it. `engine.run_source(path)` also calls
  `engine.run_tree`.
- **Existing transpiler tests.** Any tests asserting on the
  pre-canonical shape for AST nodes we realign will fail; update those
  tests to the canonical shape. Tests for AST nodes we don't touch
  stay as-is.
- **Assertion helper.** Add `assert.deep_equal(got, expected, msg)` to
  `tests/charlie/support/assert.lua` for table equality with a
  first-divergent-path failure message. Needed by T2.1 and useful for
  every later slice that compares trees.

Anything beyond this — realigning the bwc path, the assignment path,
the if path, etc. — is later work. The principle: realign as later
slices exercise each AST node, not all at once.

<a id="v002-step-3-verify"></a>
### V0.02 Step 3: Verify

~~~json
{"vibecode": {"step": 3, "name": "verify", "actions":
["create_charlie_source_fixture",
"run_via_engine_run_source",
"compare_returned_value_payload_to_hello",
"compare_transpiled_tree_to_v001_hand_written_canonical_fixture"],
"pass_condition":
"return_value_payload_equals_hello_and_transpiled_tree_deep_equals_v001_fixture_tree",
"fail_condition":
"any_deviation; failure_message_names_which_layer_blocked"}}
~~~

Create `tests/charlie/fixtures/hello_world.charlie` containing
`'hello'.to_string`. Run it via `engine.run_source(path)`. Verify two
things:

1. The returned value has `payload == "hello"`.
2. The transpiled tree (captured before dispatch) deep-equals the V0.01
   hand-written `[[{"value": "hello"}, "to_string"]]` tree — the
   round-trip equivalence check that proves canonical alignment.

If either fails, the message must identify which layer blocked: parse
error, transpiler shape mismatch, dispatch failure, engine context
problem. Loop back to Step 2 for that layer.

When V0.02 passes, the next slice from the roadmap is selected and
planned in the same shape.

<a id="v002-phase-1-test-plan"></a>
### V0.02 phase 1 test plan

~~~json
{"vibecode": {"phase_1_tests":
[{"id": "T2.1", "verifies":
"transpiler_emits_canonical_ksj_for_v002_fixture_deep_equal_to_v001_hand_written_tree",
"level": "unit"}, {"id": "T2.2", "verifies":
"engine_run_tree_returns_payload_hello_for_v001_canonical_tree",
"level": "unit"}, {"id": "T2.3", "verifies":
"engine_run_source_returns_payload_hello_for_v002_charlie_fixture_file",
"level": "integration_end_to_end"}, {"id": "T2.4", "verifies":
"ctx_back_to_user_after_engine_run_source_returns",
"level": "unit_observability_check"}, {"id": "T2.5", "verifies":
"existing_v001_engine_run_path_still_returns_payload_hello_for_v001_ksj_fixture",
"level": "regression_check"}, {"id": "T2.6", "verifies":
"existing_pre_canonical_transpiler_paths_for_unrelated_ast_types_unchanged_and_their_tests_still_pass",
"level": "regression_check"}]}}
~~~

Six tests for V0.02 phase 1. Each lives under `tests/charlie/v002/`
using the same framework (`support.runner` + `support.assert`).

| ID | Level | Verifies | How |
|---|---|---|---|
| T2.1 | unit | Transpiler emits canonical for the fixture | `assert.deep_equal(charlie.transpile("'hello'.to_string"), {{ {value="hello"}, "to_string" }})` |
| T2.2 | unit | `engine.run_tree` returns payload `"hello"` | Hand-build the canonical tree in Lua, pass to `engine.run_tree`, assert on result |
| T2.3 | integration | `engine.run_source` returns payload `"hello"` from the source fixture file | `engine.run_source("tests/charlie/fixtures/hello_world.charlie")` |
| T2.4 | unit | ctx restored to user after `engine.run_source` returns | Mirror of V0.01 T1.7's second assertion |
| T2.5 | regression | `engine.run` of V0.01 CharlieJSON fixture still works | Identical to V0.01 T1.7 — must not regress |
| T2.6 | regression | Pre-canonical transpiler tests for unrelated AST types still pass | The unchanged transpiler test files continue to pass; the changed ones reflect canonical output |

T2.5 and T2.6 are regression checks: the engine's CharlieJSON-file path and the
unchanged transpiler paths must continue to work after V0.02's
realignment. If either breaks, that's a sign V0.02 reached further than
its declared scope.

All six pass = V0.02 done.

<a id="v002-test-layout"></a>
### V0.02 test layout

~~~json
{"vibecode": {"test_directory": "tests/charlie/v002/",
"fixture_path": "tests/charlie/fixtures/hello_world.charlie",
"entry_point_change":
"tests_charlie_run_lua_extended_to_require_v002_test_modules",
"transpiler_test_updates":
"tests_charlie_transpiler_test_files_updated_only_for_realigned_ast_nodes",
"support_helper_addition":
"tests_charlie_support_assert_lua_gains_deep_equal_helper"}}
~~~

| Path | Contents |
|---|---|
| `tests/charlie/fixtures/hello_world.charlie` | Charlie source fixture (sibling of `hello_world.cjs`) |
| `tests/charlie/v002/` | Phase 0 and Phase 1 unit + integration tests |
| `tests/charlie/run.lua` | Extended to require V0.02 test modules |
| `tests/charlie/support/assert.lua` | Gains a `deep_equal` helper |
| `tests/charlie/transpiler/test_*.lua` | Updated only for AST nodes realigned in V0.02 |

<a id="v002-open-questions"></a>
### V0.02 open questions

~~~json
{"vibecode": {"open_questions":
["api_naming_for_source_side_entry_point",
"deep_equal_assert_helper_signature_and_first_divergent_path_format",
"whether_existing_charlie_run_source_in_init_lua_should_be_renamed_or_deprecated_in_v002_or_later",
"how_much_transpiler_test_churn_in_practice"]}}
~~~

- **API naming.** `engine.run_source(path)` is the working name.
  Alternatives: `engine.run_charlie(path)`, `charlie.run_source(path)`,
  `charlie.execute_file(path)`. Decision can wait until the function is
  written — easy to rename.
- **`assert.deep_equal` signature.** Existing `support/assert.lua` uses
  descriptive failure messages. The deep_equal helper should surface
  the first divergent path on mismatch (e.g.,
  `mismatch at [1][2]: expected "to_string", got "tostring"`). Exact
  message format settled when implemented.
- **Legacy `M.run(source, env)` in `init.lua`.** Currently goes through
  the pre-canonical pipeline + `interpreter.lua`. Out of scope for V0.02
  — flagged for renaming or deprecation in a later slice once the
  transpiler is more broadly realigned.
- **Transpiler test churn.** Phase 0 step 3 will quantify how many
  existing transpiler tests assert on output shape that V0.02 changes.
  Expected to be small (only the string-literal and method-call paths)
  but worth confirming before Phase 1 starts.

---

<a id="v003-phase-0-stdout-and-bwc-workbench"></a>
## V0.03 phase 0: stdout-and-bwc workbench

~~~json
{"vibecode": {"phase": 0, "version": "0.03", "purpose":
"verify_existing_pipeline_state_for_bwc_dispatch_and_stdout_injection_before_writing_v003_code",
"steps_count": 3, "acceptance":
"all_three_workbench_checks_pass; phase_1_inventory_has_concrete_baseline; no_engine_code_changed",
"tactic":
"exercise_existing_lexer_parser_transpiler_with_puts_hello_fixture_and_characterize_engine_role_for_handling_bwc_statements_and_stdout_injection",
"differs_from_v002_phase_0":
"v002_focused_on_method_call_ast; v003_focuses_on_bwc_call_ast_and_engine_extension_points_for_stdout"}}
~~~

V0.03's workbench characterizes the pipeline state for the `puts`
fixture. Three steps — fewer than V0.02 because the lexer/parser/
transpiler are by V0.03 already exercised by both V0.01 and V0.02 work.
The new questions are bwc-specific and stdout-injection-specific.

<a id="v003-step-01-confirm-the-source-pipeline-handles-the-puts-fixture"></a>
### V0.03 Step 0.1: Confirm the source pipeline handles the puts fixture

~~~json
{"vibecode": {"step": "0.1", "name": "source_pipeline_baseline",
"input": "puts 'hello'", "tools":
["charlie.tokenize", "charlie.parse", "charlie.transpile"],
"acceptance":
"all_three_run_without_error; current_transpiler_output_for_puts_call_recorded_as_phase_1_baseline; ast_node_kind_for_bwc_call_documented"}}
~~~

Run `charlie.tokenize("puts 'hello'")`, `charlie.parse(...)`, and
`charlie.transpile(...)`. Record the AST node `kind` for the bwc-call
form and the current transpiler output. The current output is
pre-canonical (matches `interpreter.lua`'s legacy bwc shape, e.g.,
`[{bwc:'puts'}, '&', {args:[{value:'hello'}]}]`); the canonical target
is `[{bwc:'puts'}, {value:'hello'}]`. The diff drives Phase 1 step 2.

<a id="v003-step-02-confirm-enginerun_source-accepts-an-env-override"></a>
### V0.03 Step 0.2: Confirm engine.run_source accepts an env override

~~~json
{"vibecode": {"step": "0.2", "name": "env_injection_check",
"action":
"run_v002_fixture_through_engine_run_source_with_an_env_table_argument_and_verify_no_error",
"acceptance":
"engine_run_source_accepts_optional_env_argument_or_can_be_extended_to_accept_one_without_breaking_v002_signature"}}
~~~

`engine.run_source(path, env)` is the working signature; the V0.02 plan
defines the function without specifying `env`. Step 0.2 confirms (or
flags the need for) a second optional argument that V0.03 will use for
the stdout capture buffer. The `env` table mirrors the existing
`interpreter.new(env)` pattern from `interpreter.lua`: a place for the
host to override engine-visible knobs (initially just `env.stdout`).

If `engine.run_source` doesn't yet accept `env`, V0.03 phase 1 step 2
extends it — purely additive, no V0.02 regression.

<a id="v003-step-03-pre-canonical-legacy-bwc-handling-for-reference"></a>
### V0.03 Step 0.3: Pre-canonical legacy bwc handling, for reference

~~~json
{"vibecode": {"step": "0.3", "name": "legacy_bwc_reference",
"action":
"read_interpreter_lua_to_observe_how_puts_was_handled_in_the_pre_canonical_pipeline",
"acceptance":
"summary_recorded_of_legacy_puts_implementation_for_v003_phase_1_to_borrow_what_is_useful_without_inheriting_the_pre_canonical_shape"}}
~~~

`interpreter.lua` already has a `puts` bwc handler (it predates V0.01).
Step 0.3 reads that implementation as a reference for the V0.03
implementation — particularly the stdout-override pattern via
`env.stdout`. V0.03 adopts that pattern verbatim; the canonical CharlieJSON
shape is different but the host-level capture mechanism doesn't need
to change.

<a id="v003-phase-0-test-plan"></a>
### V0.03 phase 0 test plan

~~~json
{"vibecode": {"phase_0_tests":
[{"id": "T3.0.1", "verifies":
"source_pipeline_completes_for_puts_hello_fixture_and_baseline_output_captured",
"tool": "tests/charlie/v003/test_source_baseline.lua", "level": "unit"},
{"id": "T3.0.2", "verifies":
"engine_run_source_signature_compatible_with_optional_env_argument",
"tool": "tests/charlie/v003/test_env_signature.lua", "level": "unit"}]}}
~~~

| ID | Level | Verifies | Tool |
|---|---|---|---|
| T3.0.1 | unit | Source pipeline completes for `puts 'hello'`; baseline transpiler output captured | `test_source_baseline.lua` |
| T3.0.2 | unit | `engine.run_source` accepts (or can accept) an `env` argument compatibly | `test_env_signature.lua` |

Step 0.3 is reference reading, not a test. Both T3.0.x must pass
before V0.03 phase 1 begins.

---

<a id="v003-phase-1-puts-hello-from-charlie-source"></a>
## V0.03 phase 1: puts-hello from Charlie source

~~~json
{"vibecode": {"phase": 1, "version": "0.03", "fixture_path":
"tests/charlie/fixtures/puts_hello.charlie", "fixture_content":
"puts 'hello'", "runner_path": "tests/charlie/run.lua",
"acceptance":
"fixture_transpiles_to_canonical_bwc_form_and_engine_run_source_with_capture_sink_produces_stdout_buffer_hello_newline",
"required_work":
["transpiler_realignment_for_bwc_call_statement",
"engine_bwc_registry_with_puts_handler_owned_by_stdout_role",
"engine_stdout_role_in_role_registry",
"engine_dispatch_extended_to_recognize_bwc_receiver_form",
"engine_run_source_accepts_env_stdout_override",
"capture_sink_helper_for_tests"],
"reuses_from_prior":
["bootstrap", "materialize", "lookup_method", "transition",
"dispatch_for_method_call_form", "engine_run_source", "engine_run_tree",
"assert_deep_equal"], "out_of_scope":
["stdin_faucet", "stderr_sink", "file_io", "variables_assignment",
"control_flow", "full_transpiler_retrofit_for_unrelated_bwcs"],
"tactic":
"minimal_extension_just_for_puts_with_one_string_argument; other_bwcs_and_multi_argument_bwc_calls_left_for_later"}}
~~~

Three steps. Same shape as V0.01/V0.02 Phase 1: inventory, fill gaps,
verify.

<a id="v003-step-1-inventory"></a>
### V0.03 Step 1: Inventory

~~~json
{"vibecode": {"step": 1, "name": "inventory", "actions":
["read_existing_transpiler_to_see_how_bwc_calls_are_emitted_today",
"read_existing_interpreter_lua_puts_handler_for_reference",
"document_canonical_target_shape_per_charliejson_md",
"identify_engine_dispatch_branch_that_needs_extending_for_bwc_receiver_form",
"identify_transpiler_tests_that_will_need_updating_for_realigned_bwc_emit"],
"output":
"concrete_gap_description_for_step_2; list_of_existing_transpiler_tests_to_be_updated"}}
~~~

Read the existing `transpiler.lua` for its bwc-call output shape, the
existing `interpreter.lua` for its `puts` handler (lines around the
`puts = function(interp, args) ... end` definition), and
`charliejson.md` for the canonical bwc-call shape
(`[{bwc: "name"}, arg?]`). Document:

- Current transpiler output for `puts 'hello'`.
- Target canonical shape per charliejson.md.
- The diff (likely the `'&'` sigil and `{args: [...]}` wrapper drop
  away in canonical form).
- Which existing transpiler tests assert on the pre-canonical bwc
  shape and will need updating.
- The dispatcher branch in `engine.lua` that currently handles
  `[value, method, args]` — V0.03 adds a sibling branch for
  `[{bwc: name}, arg?]`.

<a id="v003-step-2-fill-the-gaps"></a>
### V0.03 Step 2: Fill the gaps

~~~json
{"vibecode": {"step": 2, "name": "fill_gaps", "scope":
"bwc_dispatch_and_stdout_injection_only; not_other_bwcs_not_multi_argument_handling",
"work_items":
["transpiler_emit_canonical_for_bwc_call_statement",
"engine_bootstrap_extended_to_register_stdout_role_and_puts_bwc",
"engine_dispatch_extended_to_branch_on_bwc_receiver_form",
"engine_run_source_extended_to_accept_env_stdout_override",
"engine_run_tree_passed_env_through_to_dispatch_chain",
"assert_helper_for_capture_buffer_in_support_assert_lua_if_useful",
"existing_transpiler_tests_for_bwc_paths_updated_to_canonical_shape"],
"non_work":
["other_bwcs_beyond_puts", "multi_argument_bwc_calls",
"keyword_argument_bwc_calls", "stderr_separation",
"flushing_or_buffering_strategies",
"interpreter_lua_or_its_tests_modified"]}}
~~~

For each gap from Step 1, add only what V0.03 needs:

- **Transpiler.** Realign the bwc-call path to emit the canonical
  `[{bwc: name}, arg?]` shape. Existing transpiler tests for bwc paths
  get updated; tests for unrelated paths stay as-is.
- **Engine bootstrap.** Add an `stdout` role to `engine.roles` and an
  `engine.bwcs` table mapping `"puts"` to a struct entry:
  `engine.bwcs.puts = {fn = function(args) ... end, owning_role = engine.roles.stdout}`.
  Each bwc carries its own metadata (handler function, owning role)
  in a single entry — no parallel role-lookup table to keep in sync.
  Forward-compatible for additional per-bwc fields later (docs,
  deprecation flag, version) without an engine-wide refactor.
- **Engine dispatch.** Extend `engine.dispatch` to branch on the
  receiver form: if `statement[1]` is `{bwc: <name>}`, look up the
  entry in `engine.bwcs`, run `entry.fn` inside `engine.transition`
  to `entry.owning_role`, pass the materialized arg.
- **Engine run_source signature.** Accept `(path, env)` with `env`
  optional. `env.stdout` overrides the default sink (which writes to
  `io.stdout` for production use). `engine.run_tree(tree, env)`
  follows the same pattern.
- **Test capture sink.** A small Lua-side helper builds an `env` with
  `env.stdout = function(s) buf[#buf+1] = s end` and exposes the
  concatenated buffer for the test assertion. Lives under
  `tests/charlie/v003/` or extends `tests/charlie/support/` if reused.

Per the no-bolt-on principle: anything beyond `puts` with one string
argument (a second bwc, two arguments, kwargs, escapes inside the
string, etc.) is later work.

<a id="v003-step-3-verify"></a>
### V0.03 Step 3: Verify

~~~json
{"vibecode": {"step": 3, "name": "verify", "actions":
["create_charlie_source_fixture",
"build_capture_sink_env",
"run_via_engine_run_source_with_env",
"assert_captured_stdout_equals_hello_newline",
"separately_assert_transpiled_tree_matches_canonical_bwc_shape"],
"pass_condition":
"captured_stdout_buffer_equals_hello_newline_and_transpiled_tree_deep_equals_canonical_target",
"fail_condition":
"any_deviation; failure_message_names_which_layer_blocked"}}
~~~

Create `tests/charlie/fixtures/puts_hello.charlie` containing
`puts 'hello'`. Build a capture-sink `env`. Run via
`engine.run_source(path, env)`. Verify:

1. The captured buffer equals `"hello\n"`.
2. The transpiled tree (captured before dispatch) deep-equals
   `[[{"bwc": "puts"}, {"value": "hello"}]]`.

If either fails, the message must identify which layer blocked. Loop
back to Step 2 for that layer.

When V0.03 passes, V0.04 is selected from the roadmap and planned at
the same detail level as V0.02 and V0.03.

<a id="v003-phase-1-test-plan"></a>
### V0.03 phase 1 test plan

~~~json
{"vibecode": {"phase_1_tests":
[{"id": "T3.1", "verifies":
"transpiler_emits_canonical_bwc_form_for_puts_hello_deep_equal_to_expected_target",
"level": "unit"}, {"id": "T3.2", "verifies":
"engine_bootstrap_registers_stdout_role_and_puts_bwc",
"level": "unit"}, {"id": "T3.3", "verifies":
"engine_dispatch_routes_bwc_statement_to_handler_via_role_transition",
"level": "unit"}, {"id": "T3.4", "verifies":
"engine_run_source_accepts_env_with_stdout_override",
"level": "unit"}, {"id": "T3.5", "verifies":
"transition_to_stdout_role_observed_during_puts_dispatch",
"level": "unit_observability_check"}, {"id": "T3.6", "verifies":
"end_to_end_puts_hello_source_produces_hello_newline_in_capture_buffer",
"level": "integration_end_to_end"}, {"id": "T3.7", "verifies":
"v001_engine_run_and_v002_engine_run_source_paths_still_pass_for_their_prior_fixtures",
"level": "regression_check"}]}}
~~~

Seven tests for V0.03 phase 1. Each lives under `tests/charlie/v003/`
using the same framework. T3.5 is the load-bearing role test (mirror of
V0.01 T1.8): a spy on the `puts` handler records
`engine.ctx.current_role` at call time; assert it was `stdout`, not
`user`.

| ID | Level | Verifies | How |
|---|---|---|---|
| T3.1 | unit | Transpiler emits canonical bwc form | `assert.deep_equal(charlie.transpile("puts 'hello'"), {{ {bwc="puts"}, {value="hello"} }})` |
| T3.2 | unit | Bootstrap registers stdout role and `puts` | `engine.roles.stdout` exists; `engine.bwcs.puts.fn` is a function; `engine.bwcs.puts.owning_role == engine.roles.stdout` |
| T3.3 | unit | Dispatch routes bwc to handler | Hand-build `[{bwc:"puts"}, {value:"x"}]`; pass to `engine.dispatch` with a capture env; assert capture has `"x\n"` |
| T3.4 | unit | `env.stdout` override accepted | `engine.run_source(path, {stdout = capture})` runs without error |
| T3.5 | unit | Transition to stdout role observed during dispatch | Spy on `puts` handler records role at call time; assert it was `stdout` |
| T3.6 | integration | End-to-end via source file | `engine.run_source("tests/charlie/fixtures/puts_hello.charlie", env)` leaves `env` buffer == `"hello\n"` |
| T3.7 | regression | V0.01 and V0.02 fixtures still work | Run V0.01 `hello_world.cjs` via `engine.run` and V0.02 `hello_world.charlie` via `engine.run_source`; both still return payload `"hello"` |

All seven pass = V0.03 done.

<a id="v003-test-layout"></a>
### V0.03 test layout

~~~json
{"vibecode": {"test_directory": "tests/charlie/v003/",
"fixture_path": "tests/charlie/fixtures/puts_hello.charlie",
"entry_point_change":
"tests_charlie_run_lua_extended_to_require_v003_test_modules",
"capture_sink_helper":
"tests_charlie_v003_support_capture_lua_or_inlined_per_test",
"transpiler_test_updates":
"tests_charlie_transpiler_test_files_for_bwc_paths_updated_only"}}
~~~

| Path | Contents |
|---|---|
| `tests/charlie/fixtures/puts_hello.charlie` | Source fixture for V0.03 |
| `tests/charlie/v003/` | Phase 0 and Phase 1 tests |
| `tests/charlie/run.lua` | Extended to require V0.03 test modules |
| `tests/charlie/transpiler/test_*.lua` | Updated only for bwc paths realigned in V0.03 |

<a id="v003-open-questions"></a>
### V0.03 open questions

~~~json
{"vibecode": {"open_questions":
["bwc_handler_calling_convention",
"capture_sink_signature",
"stderr_vs_stdout_split",
"sys_role_check_after_v003"],
"resolved":
["bwc_owning_role_attachment_mechanism_resolved_2026-05-17_as_struct_per_bwc_fn_and_owning_role"]}}
~~~

- **bwc handler calling convention.** V0.01 method handlers take
  `(receiver, args)`. bwc handlers don't have a receiver — they're
  callable entities themselves. Options: `(args)`, `(env, args)`,
  `(interp, args)`. Recommendation: match the existing
  `interpreter.lua` pattern `(interp, args)` so the engine instance is
  available for stdout writes. Settled during implementation.
- **Capture sink signature.** `env.stdout(s)` taking a single string,
  matching `interpreter.lua`. Buffer reconstruction happens in the
  test helper, not in the engine.
- **stderr.** Out of scope for V0.03. When stderr arrives, the same
  pattern duplicates: `engine.roles.stderr` + an `eprint` or similar
  bwc + `env.stderr` override.
- **Sys-role consistency check.** Per V0.01's role footprint, `%role`
  was supposed to be implemented as a system method but the V0.01
  shipping code didn't include it (the hello-world fixture didn't
  exercise it, so it passed). V0.03 doesn't need `%role` either, but
  the gap is worth tracking — fix when first slice that needs it
  arrives.

---

<a id="v00x-charlie-command-line-execution"></a>
## V0.0X: Charlie command-line execution

~~~json
{"vibecode": {"slice": "v0_0x_charlie_cli", "codename":
"charlie_cli", "position_in_roadmap":
"after_v005_charlie_with_json_serialization; before_v01_bryton",
"goal":
"introduce_charlie_as_os_level_command_for_running_charlie_files_with_explicit_permission_model",
"hard_prerequisite_for": "v0_1_bryton",
"permission_posture":
"default_restrictive; opt_in_via_flags_deno_shape",
"aligns_with":
["feedback_no_dangerous_defaults", "roles_md_role_based_security"]}}
~~~

Hard prerequisite for [V0.1 Bryton](#v01-bryton) — Bryton
subprocess-invokes test files (per the
[Bryton spec](../overview.md#tests-are-runnable-scripts), every
test file is "an ordinary executable"). This slice introduces
`charlie` as an OS-level command and pins down the permission model
for Charlie code launched at the CLI.

<a id="what-the-slice-introduces"></a>
### What the slice introduces

~~~json
{"vibecode": {"introduces": ["charlie_command_line_launcher",
"shebang_support", "argument_passing_into_charlie",
"stderr_sink_and_role",
"routing_convention_engine_errors_to_stderr_program_output_to_stdout",
"exit_codes_zero_on_clean_completion_nonzero_on_alarm_or_uncaught",
"permission_flag_machinery"],
"note_on_stdout":
"stdout_sink_and_puts_bwc_already_shipped_in_v003_charlie_with_stdout; v00x_cli_adds_stderr_as_a_peer_sink_plus_the_routing_convention",
"launcher_responsibilities":
["take_a_charlie_file_path_as_first_argument",
"set_up_engine_with_minimum_roles",
"wire_up_faucets_for_any_granted_flags",
"invoke_engine_run_on_the_file",
"emit_program_output_to_stdout_and_stderr_appropriately",
"exit_with_appropriate_code"]}}
~~~

- A `charlie` command-line launcher — a small script taking a
  `.charlie` file path as its first argument, invoking the engine,
  exiting with an appropriate code.
- Shebang support — `.charlie` files starting with
  `#!/usr/bin/env charlie` are directly runnable via `chmod +x` and
  `./file.charlie`.
- Argument passing from OS argv into the running Charlie program
  (surfaced via `%argv`; exact shape settled in this slice).
- **stderr sink** — engine-introduced peer of the stdout sink that
  shipped in V0.03. Has its own role (`stderr`); writes go to the
  process's `io.stderr` by default; test injection via
  `env.stderr` mirrors `env.stdout`.
- **Routing convention** — engine errors and diagnostics go to
  stderr; the program's intentional output goes to stdout. This is
  the first slice that needs the distinction (V0.03 only had stdout,
  V0.04/V0.05 had no engine-error-vs-program-output ambiguity).
- Exit codes — 0 on clean completion, non-zero on uncaught exception
  or alarm.
- The permission-flag machinery described below.

<a id="permissions-default-restrictive-opt-in-via-flags"></a>
### Permissions: default restrictive, opt-in via flags

~~~json
{"vibecode": {"permission_model": "default_restrictive_opt_in_via_flags",
"defaults_always_on": ["user_role", "clock_role_plus_clock_object",
"randomizer_role_plus_random_source",
"utils_role_plus_percent_utils_namespace",
"stdin_role_plus_stdin_object", "stdout_role_plus_stdout_object",
"stderr_role_plus_stderr_object",
"cli_args_role_plus_argv"], "off_by_default_grant_via_flag":
["filesystem_dirjails", "network_faucets", "env_vars", "puck",
"all_at_once_convenience"], "rationale_links":
["feedback_no_dangerous_defaults", "roles_md_role_based_security"]}}
~~~

Following the role-based security model in [roles.md](../charlie/roles.md) and the
no-dangerous-defaults discipline, the CLI uses a **default-restrictive**
posture: a `.charlie` program invoked via the CLI gets only the minimum
roles and faucets, with everything else opt-in via flags. This mirrors
Deno's local-script model.

<a id="always-on-every-cli-invocation"></a>
#### Always on (every CLI invocation)

| Capability | Role | Why default |
|---|---|---|
| Program execution context | `user` | The program has to run as something |
| Clock | `clock` | Per [roles.md](../charlie/roles.md) engine minimum |
| Randomizer | `randomizer` | Per engine minimum |
| `%utils` namespace | `utils` | Per engine minimum |
| stdin object | `stdin` faucet | The controlling terminal |
| stdout object | `stdout` faucet | Writing to the terminal |
| stderr object | `stderr` faucet | Diagnostics |
| `argv` | `cli_args` faucet | The program needs to see its own arguments |

<a id="off-by-default-grant-via-flag"></a>
#### Off by default, grant via flag

| Flag (repeatable where listed) | Grants | Role created |
|---|---|---|
| `--allow-fs=PATH` ⟳ | Read-write dirjail rooted at PATH | per-dirjail role |
| `--allow-fs-read=PATH` ⟳ | Read-only dirjail rooted at PATH | per-dirjail role |
| `--allow-net=HOST[:PORT]` ⟳ | Network faucet to specific host | per-faucet role |
| `--allow-net` | Network faucet to any host | broad `net` role |
| `--allow-env[=NAMES]` | Env-vars faucet, optionally narrowed | `env_vars` role |
| `--allow-puck` | Puck object access | `puck` role |
| `--allow-all` (or `-A`) | Everything above | convenience for trusted local scripts |

`--allow-all` is the escape hatch for "this is my own script and I
trust myself." Without it, Charlie at the CLI runs sandboxed by
default — the developer has to think about what the program needs.

<a id="examples"></a>
#### Examples

```bash
./hello.charlie
# stdin/out/err/argv + engine minimums only; nothing else

charlie --allow-fs=. ./read_file.charlie
# adds read-write dirjail rooted at current directory

charlie --allow-fs-read=. --allow-net=api.example.com:443 ./fetch.charlie
# read-only filesystem + single-host network

charlie --allow-all ./my_local_tool.charlie
# everything; for trusted local scripts
```

<a id="installation"></a>
### Installation

~~~json
{"vibecode": {"installation_model":
"project_local_bin_plus_path; no_system_install",
"launcher_path_in_repo": "bin/charlie",
"user_action_once":
"add_project_bin_directory_to_path_in_shell_rc",
"launcher_is_self_locating":
"launcher_computes_its_own_absolute_path_and_derives_repo_root_from_that_then_resolves_engine_relative_to_repo_root",
"no_root_required": true, "multiple_checkouts_coexist":
"each_repo_has_its_own_bin; path_order_picks_the_winner",
"easy_backout":
"remove_path_line_from_rc_file; nothing_else_to_clean_up",
"system_install_status": "v1_plus_deployment_concern; not_v00x_work"}}
~~~

The `charlie` launcher lives at `bin/charlie` inside the repo. There
is **no system-level install** in V0.0X — root access is not required,
and `/usr/local/bin/` (or equivalent) is not touched.

To make `charlie` available as a command, the user adds the project's
`bin/` directory to their `$PATH` once, in their shell's rc file:

```bash
# in ~/.bashrc or ~/.zshrc
export PATH="/path/to/puck/working/bin:$PATH"   # replace with your local checkout path
```

After re-sourcing the rc file (or starting a new shell),
`charlie ./foo.charlie` works from any directory.

**The launcher is self-locating.** When invoked, `bin/charlie`
computes its own absolute path, derives the repo root from that, and
resolves the engine at `<repo_root>/code/charlie/lua/`. This works
regardless of the user's current directory when running `charlie`.

One candidate shape (bash form):

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
exec lua \
    -e "package.path='$REPO_ROOT/code/charlie/lua/?.lua;'..package.path" \
    "$REPO_ROOT/code/charlie/lua/charlie/cli.lua" "$@"
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

System-level install (`/usr/local/bin/charlie`, distribution packages,
homebrew formula, etc.) is a V1+ deployment concern, not V0.0X work.

<a id="bryton-interaction"></a>
### Bryton interaction

~~~json
{"vibecode": {"bryton_invocation": "charlie_dash_dash_allow_all_per_test",
"rationale": "test_files_typically_need_broad_access; per_test_narrowing_is_later_bryton_feature_out_of_scope_for_v01"}}
~~~

Bryton subprocess-invokes test files using `charlie --allow-all` by
default. Test files typically need broad access (filesystem to read
fixtures, network to hit a service-under-test, etc.). Per-test
permission narrowing is a later Bryton feature (configurable via a
future `bryton.json` setting; out of scope for V0.1).

<a id="open-questions"></a>
### Open questions

~~~json
{"vibecode": {"open_questions_v00x_cli":
["exact_flag_syntax_long_only_vs_short_forms_equals_vs_separate_args",
"default_for_puck_role_off_seems_right_but_puck_is_central",
"determinism_flag_for_clock_and_randomizer_seed_for_test_reproducibility_v2_plus",
"cross_platform_shebang_behavior_linux_macos_wsl",
"whether_engine_reading_the_dot_charlie_source_file_itself_should_require_a_permission_flag_or_be_pre_permission_engine_plumbing"]}}
~~~

- **Exact flag syntax.** Long-only or short forms? `--allow-fs=./`
  versus `--allow-fs ./`? Settled in this slice.
- **Default for the `puck` role.** Off-by-default seems right, but
  `puck` is so central to the platform that always-on might be more
  first-contact-friendly. Deferred — re-examine when the puck client
  lands.
- **Determinism flag for `clock`/`randomizer`** (e.g., `--seed=N`) for
  test reproducibility. V2+.
- **Cross-platform shebang behavior** (Linux / macOS / WSL).
  Mostly-portable on the three Unix-flavored cases; Windows native is
  V2+.
- **Engine reading the `.charlie` source file itself.** Current
  proposal: pre-permission engine plumbing (the engine has to read the
  script to run anything). If this becomes contentious, an explicit
  `--source=PATH` form could surface it.

---

<a id="v01-bryton"></a>
## V0.1: Bryton

~~~json
{"vibecode": {"version": "0.1", "codename": "bryton", "goal":
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
"lua_for_simplicity; charlie_hosted_runner_is_a_later_slice",
"distinct_from":
"lua_side_engine_tests_which_continue_to_use_tests_charlie_support_runner",
"spec_links":
["documentation/charlie/bryton/overview.md",
"documentation/charlie/bryton/runner.md"]}}
~~~

V0.1 is the first usable **Bryton** — see
[bryton/overview.md](../charlie/bryton/overview.md) and
[bryton/runner.md](../charlie/bryton/runner.md) for the full spec. Per the
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
- Per-language helper libraries (no Charlie-side assertion helpers)
- Fail-fast
- Tree-shaped result aggregation (flat tally only)
- Concurrency control (sequential execution only)
- The runner being itself a Charlie program — V0.1 runner is
  implemented in Lua for simplicity. A Charlie-hosted Bryton runner
  is a later slice (the language has to mature far enough to expose
  filesystem and subprocess capabilities).

**Distinct from Lua-side engine tests.** The existing
`tests/charlie/support/runner.lua` continues to test the engine
internals; that's fixed at V0.01. Bryton is for testing **Charlie
code with Charlie code** (or, in V0.1, with any script that emits
Xeme), layered on top of the engine.

<a id="v01-prerequisites"></a>
### V0.1 prerequisites

~~~json
{"vibecode": {"v01_prerequisites":
["v001_engine_can_run_ksj_end_to_end",
"v00X_charlie_text_parser_and_transpiler_so_test_files_can_be_charlie_source",
"v00X_hash_class_so_charlie_tests_can_construct_xemes",
"v00X_stdout_writing_so_charlie_tests_can_emit_xemes",
"v00X_json_serialization_method_on_hashes_so_tests_can_emit_their_xemes",
"lua_host_subprocess_invocation_io_popen",
"lua_host_directory_walk_find_via_io_popen_or_lfs"]}}
~~~

Several slices in the V0.0X range have to land before V0.1 can ship:

| Prerequisite | Provided by |
|---|---|
| Engine can run CharlieJSON end-to-end | V0.01 |
| Charlie text → CharlieJSON transpiler | V0.02 |
| Hash class | a V0.0X slice |
| `%stdout.write` (sys references + stdout sink) | a V0.0X slice |
| JSON serialization (hash → JSON string method) | a V0.0X slice |
| Charlie CLI executable (`charlie` command, shebang support, permission flags) | [V0.0X CLI slice](#v00x-charlie-command-line-execution) |
| Lua-host subprocess invocation | runner host; native `io.popen` |
| Lua-host directory walk | runner host; `io.popen("find ...")` or `lfs` |

The V0.0X slices that fill these gaps are unscoped in this plan until
each is the next active slice. The current direction is to attempt
them in roughly the order shown; each unblocks the next.

<a id="v01-phase-plan"></a>
### V0.1 phase plan

Three phases, same three-step shape as V0.01:

<a id="phase-0-lua-host-workbench-for-bryton"></a>
#### Phase 0: Lua-host workbench for Bryton

~~~json
{"vibecode": {"v01_phase_0_purpose":
"verify_lua_host_capabilities_bryton_needs_before_writing_bryton_code",
"steps_count": 3, "acceptance":
"all_three_pass_no_bryton_code_written_yet"}}
~~~

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

<a id="phase-1-runner-implementation"></a>
#### Phase 1: runner implementation

~~~json
{"vibecode": {"v01_phase_1_steps":
[{"step": 1, "name": "walk_directory_collect_test_files"},
{"step": 2, "name": "run_one_file_as_subprocess_capture_stdout"},
{"step": 3, "name": "parse_captured_stdout_as_xeme_json"},
{"step": 4, "name":
"aggregate_pass_fail_counts_across_multiple_tests"},
{"step": 5, "name": "print_flat_summary_and_failure_list"},
{"step": 6, "name":
"wire_steps_1_through_5_as_bryton_dot_lua_entry_point"}]}}
~~~

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

<a id="phase-2-acceptance-tests"></a>
#### Phase 2: acceptance tests

~~~json
{"vibecode": {"v01_phase_2_tests":
[{"id": "TB.1", "verifies": "trivial_pass_case"},
{"id": "TB.2", "verifies": "trivial_fail_case_message_surfaces"},
{"id": "TB.3", "verifies":
"mixed_directory_correct_aggregate_and_failures_listed"}]}}
~~~

| ID | Verifies | Setup |
|---|---|---|
| TB.1 | Trivial pass case | A test file emits `{"success": true}`; Bryton reports 1 passed |
| TB.2 | Trivial fail case | A test file emits `{"success": false, "message": "X"}`; Bryton reports 1 failed with `X` in the failure list |
| TB.3 | Mixed directory | A directory with 2 passing + 1 failing test files; Bryton reports 2 passed, 1 failed, the failing test's message in the summary |

The test fixtures themselves can be in any language that emits Xeme
JSON to stdout (shell scripts, Lua scripts, or — once the
prerequisites land — Charlie files). For V0.1 acceptance, the
simplest path is shell scripts that `echo` the Xeme JSON — this
lets us verify the runner works without depending on the Charlie
prerequisites being complete.

When all three pass, V0.1 Bryton ships.

<a id="v01-test-layout"></a>
### V0.1 test layout

~~~json
{"vibecode": {"v01_test_layout":
{"runner_implementation_under":
"code/bryton/lua/bryton/",
"v01_acceptance_fixtures_under":
"tests/bryton/v01/fixtures/",
"v01_acceptance_tests_under":
"tests/bryton/v01/"}}}
~~~

| Path | Contents |
|---|---|
| `code/bryton/lua/bryton/` | The Lua-host Bryton runner implementation |
| `tests/bryton/v01/fixtures/` | Test scripts emitting Xeme JSON (pass + fail cases) |
| `tests/bryton/v01/` | V0.1 acceptance tests using `support/runner` + `support/assert` |

---

<a id="methodology"></a>
## Methodology

~~~json
{"vibecode": {"notes": ["vibecode_is_source_of_truth", "prose_is_derivative",
"each_phase_runnable", "tests_drive_roadmap",
"soft_lock_applies_until_explicit_unlock",
"phase_completion_requires_acceptance_criterion_passing",
"inventory_before_implement; never_rewrite_without_understanding",
"minimal_surface_per_slice; not_full_spec_upfront",
"ksj_is_runtime_format; charlie_text_is_for_humans"]}}
~~~

- Vibecode blocks are canonical; prose is derivative.
- Each phase ends runnable.
- Tests drive the roadmap. What's missing in the next test is what gets
  built next.
- Soft feature lock applies until explicitly unlocked.
- A phase isn't complete until its acceptance criterion passes.
- Inventory existing code before adding new code; never rewrite without
  understanding what's there.
- Each slice builds the minimal surface it needs. The full CharlieJSON
  spec, the full Charlie grammar, and the full stdlib emerge over many
  slices, not as single upfront efforts.
- CharlieJSON is the runtime format the engine consumes; Charlie text is
  for human authors and gets transpiled to CharlieJSON before execution.

---

<a id="lua-dependencies"></a>
## Lua dependencies

~~~json
{"vibecode": {"section": "lua_dependencies",
"role": "pointer to the running list of non-stdlib Lua libraries the
project depends on", "canonical_doc": "lua-dependencies.md"}}
~~~

Lua's standard library doesn't cover networking, crypto, markdown,
or much else we need. The running list of external Lua libraries
(and their C-level deps) lives in
[lua-dependencies.md](lua-dependencies.md). Add new deps there as
they're adopted, with a short note on what uses each and why.

---

<a id="open"></a>
## Open

~~~json
{"vibecode": {"open": ["test_runner_decision", "fixture_layout",
"vibecode_attachment_form", "bootstrap_parser_in_ksj",
"chain_placeholder_form_in_v001",
"top_level_return_path_to_harness",
"engine_capability_allow_list_v1_plus"],
"resolved":
["string_class_role_name_resolved_2026-05-17_as_stdlib_for_all_built_in_classes"]}}
~~~

- **Test runner.** Use the existing `tests/charlie/run.lua` or evolve it?
  To be decided during Step 1 (inventory) of V0.01.
- **Fixture layout.** The proposed `tests/charlie/fixtures/` path mirrors
  the existing test directory structure but should be confirmed on
  inventory.
- **Vibecode attachment form.** The mechanism for attaching vibecode blocks
  to runtime statements is TBD per the existing memory. Doesn't block V0.01
  — vibecode in docs is fine for now.
- **Bootstrap parser.** The CharlieJSON spec notes that the bootstrap
  parser (Charlie text → CharlieJSON) must be written directly in
  CharlieJSON. This is V0.02 work, not V0.01, but flagged here so it isn't
  lost.
- **String-class role name.** The engine role owning the built-in string
  class needs a name. Per [roles.md](../charlie/roles.md) the broader minimum role
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
