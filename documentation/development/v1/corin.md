# Corin

~~~json
{"vibecode": {"codename": "Corin", "delivers": "caspian-with-stdout", "goal":
"execute puts_hello_from_caspian_source_and_observe_the_string_arrive_on_stdout",
"medium": "caspian_source_text", "fixture":
"puts 'hello'", "fixture_path":
"tests/caspian/fixtures/puts_hello.casp", "expected_canonical_ksj":
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

Corin is the first slice with real I/O. The program `puts 'hello'`,
written as Caspian source, executes through the Bree source pipeline
and writes `hello\n` to a stdout sink the test harness observes. No
return-value capture this time — the observable is the stdout buffer.

This is also the first slice that exercises a **cross-role call into
engine-supplied infrastructure**. The `puts` bwc is owned by an engine
role (working name: `stdout` role); user code in the `user` role calls
into it, the dispatcher transitions, the bwc writes to the sink, and
control returns. The same machinery Aslan proved for the string class
is reused for the stdout role — no new role primitives are introduced.

Corin introduces three pieces the engine doesn't have yet:

1. **bwc registry.** `engine.lua` gains a table mapping bwc names to
   handler functions (owned by their respective engine roles). The
   Aslan dispatcher only handles `[receiver, method, args?]` for value
   receivers; Corin extends it to `[{bwc: name}, arg?]` for bwc
   receivers.
2. **stdout sink.** An engine-supplied object representing "where
   text written by the program goes." stdout is a sink (values flow
   out), not a faucet (which would be input). Following
   [roles.md](../../caspian/roles.md), it has its own role (`stdout`).
   For test injection, the engine exposes an `env.stdout` override
   parameter to `engine.run_source` / `engine.run_tree`, defaulting to
   `io.write` for production use.
3. **`puts` bwc handler.** A function under the `stdout` role that
   takes a single argument, coerces to string, appends a newline,
   writes to the stdout sink. The dispatcher's role transition handles
   the cross-role bookkeeping automatically.

The transpiler also gets one more realignment: the bwc-call statement
shape. Bree realigned literal + method-call + expression-statement;
Corin realigns the bwc-call form `[{bwc: "puts"}, {value: "hello"}]`.

<a id="definition-of-done-corin"></a>
### Definition of done

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

Corin is done when all four are true:

1. **Source fixture parses and transpiles.** `puts 'hello'` lexes,
   parses, and transpiles to `[[{"bwc": "puts"}, {"value": "hello"}]]`
   exactly (deep-equal via the Bree `assert.deep_equal` helper).
2. **bwc registry has `puts` after bootstrap.** `engine.bwcs.puts`
   exists as a struct `{fn = <function>, owning_role = engine.roles.stdout}`,
   callable via the dispatcher.
3. **Engine dispatches bwc statements.** Handing a bwc-shape statement
   to `engine.dispatch` resolves the handler, transitions to `stdout`
   role, calls it, restores.
4. **Stdout sink receives `"hello\n"`.** A test that injects a capture
   buffer as `env.stdout` and calls
   `engine.run_source("tests/caspian/fixtures/puts_hello.casp", env)`
   ends with `env.stdout_buffer == "hello\n"`.

That's the entirety of Corin. Soft feature lock applies.


---

<a id="corin-phase-0-stdout-and-bwc-workbench"></a>
## Phase 0: stdout-and-bwc workbench

~~~json
{"vibecode": {"phase": 0, "purpose":
"verify_existing_pipeline_state_for_bwc_dispatch_and_stdout_injection_before_writing_corin_code",
"steps_count": 3, "acceptance":
"all_three_workbench_checks_pass; phase_1_inventory_has_concrete_baseline; no_engine_code_changed",
"tactic":
"exercise_existing_lexer_parser_transpiler_with_puts_hello_fixture_and_characterize_engine_role_for_handling_bwc_statements_and_stdout_injection",
"differs_from_bree_phase_0":
"bree_focused_on_method_call_ast; corin_focuses_on_bwc_call_ast_and_engine_extension_points_for_stdout"}}
~~~

Corin's workbench characterizes the pipeline state for the `puts`
fixture. Three steps — fewer than Bree because the lexer/parser/
transpiler are by Corin already exercised by both Aslan and Bree work.
The new questions are bwc-specific and stdout-injection-specific.

<a id="corin-step-01-confirm-the-source-pipeline-handles-the-puts-fixture"></a>
### Step 0.1: Confirm the source pipeline handles the puts fixture

~~~json
{"vibecode": {"step": "0.1", "name": "source_pipeline_baseline",
"input": "puts 'hello'", "tools":
["caspian.tokenize", "caspian.parse", "caspian.transpile"],
"acceptance":
"all_three_run_without_error; current_transpiler_output_for_puts_call_recorded_as_phase_1_baseline; ast_node_kind_for_bwc_call_documented"}}
~~~

Run `caspian.tokenize("puts 'hello'")`, `caspian.parse(...)`, and
`caspian.transpile(...)`. Record the AST node `kind` for the bwc-call
form and the current transpiler output. The current output is
pre-canonical (matches `interpreter.lua`'s legacy bwc shape, e.g.,
`[{bwc:'puts'}, '&', {args:[{value:'hello'}]}]`); the canonical target
is `[{bwc:'puts'}, {value:'hello'}]`. The diff drives Phase 1 step 2.

<a id="corin-step-02-confirm-enginerun_source-accepts-an-env-override"></a>
### Step 0.2: Confirm engine.run_source accepts an env override

~~~json
{"vibecode": {"step": "0.2", "name": "env_injection_check",
"action":
"run_bree_fixture_through_engine_run_source_with_an_env_table_argument_and_verify_no_error",
"acceptance":
"engine_run_source_accepts_optional_env_argument_or_can_be_extended_to_accept_one_without_breaking_bree_signature"}}
~~~

`engine.run_source(path, env)` is the working signature; the Bree plan
defines the function without specifying `env`. Step 0.2 confirms (or
flags the need for) a second optional argument that Corin will use for
the stdout capture buffer. The `env` table mirrors the existing
`interpreter.new(env)` pattern from `interpreter.lua`: a place for the
host to override engine-visible knobs (initially just `env.stdout`).

If `engine.run_source` doesn't yet accept `env`, Corin phase 1 step 2
extends it — purely additive, no Bree regression.

<a id="corin-step-03-pre-canonical-legacy-bwc-handling-for-reference"></a>
### Step 0.3: Pre-canonical legacy bwc handling, for reference

~~~json
{"vibecode": {"step": "0.3", "name": "legacy_bwc_reference",
"action":
"read_interpreter_lua_to_observe_how_puts_was_handled_in_the_pre_canonical_pipeline",
"acceptance":
"summary_recorded_of_legacy_puts_implementation_for_corin_phase_1_to_borrow_what_is_useful_without_inheriting_the_pre_canonical_shape"}}
~~~

`interpreter.lua` already has a `puts` bwc handler (it predates Aslan).
Step 0.3 reads that implementation as a reference for the Corin
implementation — particularly the stdout-override pattern via
`env.stdout`. Corin adopts that pattern verbatim; the canonical CaspianJ
shape is different but the host-level capture mechanism doesn't need
to change.

Corin phase 0 test coverage lives under [Testing](#testing) below.

---

<a id="corin-phase-1-puts-hello-from-caspian-source"></a>
## Phase 1: puts-hello from Caspian source

~~~json
{"vibecode": {"phase": 1, "fixture_path":
"tests/caspian/fixtures/puts_hello.casp", "fixture_content":
"puts 'hello'", "runner_path": "tests/caspian/run.lua",
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

Three steps. Same shape as Aslan/Bree Phase 1: inventory, fill gaps,
verify.

<a id="corin-step-1-inventory"></a>
### Step 1: Inventory

~~~json
{"vibecode": {"step": 1, "name": "inventory", "actions":
["read_existing_transpiler_to_see_how_bwc_calls_are_emitted_today",
"read_existing_interpreter_lua_puts_handler_for_reference",
"document_canonical_target_shape_per_caspianj_md",
"identify_engine_dispatch_branch_that_needs_extending_for_bwc_receiver_form",
"identify_transpiler_tests_that_will_need_updating_for_realigned_bwc_emit"],
"output":
"concrete_gap_description_for_step_2; list_of_existing_transpiler_tests_to_be_updated"}}
~~~

Read the existing `transpiler.lua` for its bwc-call output shape, the
existing `interpreter.lua` for its `puts` handler (lines around the
`puts = function(interp, args) ... end` definition), and
`caspianj.md` for the canonical bwc-call shape
(`[{bwc: "name"}, arg?]`). Document:

- Current transpiler output for `puts 'hello'`.
- Target canonical shape per caspianj.md.
- The diff (likely the `'&'` sigil and `{args: [...]}` wrapper drop
  away in canonical form).
- Which existing transpiler tests assert on the pre-canonical bwc
  shape and will need updating.
- The dispatcher branch in `engine.lua` that currently handles
  `[value, method, args]` — Corin adds a sibling branch for
  `[{bwc: name}, arg?]`.

<a id="corin-step-2-fill-the-gaps"></a>
### Step 2: Fill the gaps

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

For each gap from Step 1, add only what Corin needs:

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
  `tests/caspian/corin/` or extends `tests/caspian/support/` if reused.

Per the no-bolt-on principle: anything beyond `puts` with one string
argument (a second bwc, two arguments, kwargs, escapes inside the
string, etc.) is later work.

<a id="corin-step-2-skeletor-impact"></a>
#### Skeletor impact

Corin adds a new role (`stdout`), a new registry (`engine.bwcs`),
and a new sink (`env.stdout`) — but the shape of the
[Skeletor state hash](aslan.md#data-structures-lua-tables) doesn't
change. Where each piece lives:

| New thing | Where it lives | In the Skeletor hash? |
|---|---|---|
| `stdout` role object | `engine.roles.stdout` | No — `engine.roles` is bootstrap-time engine metadata, not execution state |
| `engine.bwcs.puts` entry | `engine.bwcs` | No — same rationale; bwc registry is engine metadata |
| Capture sink function | `env.stdout` (host-supplied) | No — sinks are engine-supplied infrastructure passed in by the host, not part of program state |
| Cross-role transition to `stdout` | A `bwc_call` frame with `role == engine.roles.stdout` pushed on `engine.state.call_stack` while the `puts` handler runs | **Yes** — this is the one execution-state effect Corin has |

So the Skeletor hash gains no new fields, but the top frame's `role`
gets a new possible value: alongside `user` and `stdlib`, Corin
dispatch can push a frame with `stdout` mid-call. Step 3's snapshots
show that transition in action.

<a id="corin-step-3-verify"></a>
### Step 3: Verify

~~~json
{"vibecode": {"step": 3, "name": "verify", "actions":
["create_caspian_source_fixture",
"build_capture_sink_env",
"run_via_engine_run_source_with_env",
"assert_captured_stdout_equals_hello_newline",
"separately_assert_transpiled_tree_matches_canonical_bwc_shape"],
"pass_condition":
"captured_stdout_buffer_equals_hello_newline_and_transpiled_tree_deep_equals_canonical_target",
"fail_condition":
"any_deviation; failure_message_names_which_layer_blocked"}}
~~~

Create `tests/caspian/fixtures/puts_hello.casp` containing
`puts 'hello'`. Build a capture-sink `env`. Run via
`engine.run_source(path, env)`. Verify:

1. The captured buffer equals `"hello\n"`.
2. The transpiled tree (captured before dispatch) deep-equals
   `[[{"bwc": "puts"}, {"value": "hello"}]]`.

If either fails, the message must identify which layer blocked. Loop
back to Step 2 for that layer.

When Corin passes, Digory is selected from the roadmap and planned at
the same detail level as Bree and Corin.

<a id="corin-step-3-skeletor-snapshots"></a>
#### Skeletor snapshots during the run

Corin doesn't add fields to the
[Skeletor state hash](aslan.md#data-structures-lua-tables), but it
**does** add a third possible value for a frame's `role`: the new
`stdout` role joins `user` and `stdlib` in `engine.roles`, and a
`puts` dispatch pushes a frame carrying it. The stdout sink itself
lives in `env.stdout` (the host-supplied capture buffer) — **not**
in `engine.state`, since sinks are engine-supplied infrastructure
rather than execution state.

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

**Mid-dispatch, inside the `puts` bwc handler (the cross-role
transition TC.5 verifies):**

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
      "action":   "bwc_call",
      "role":   "stdout",
      "bwc":    "puts",
      "chain":  {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

**After `puts` returns:**

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

Side effects visible outside the Skeletor hash during the `puts`
call: the capture buffer in `env.stdout` accumulates the string
`"hello\n"`. That buffer is the host's, not the engine's — Caspian
code has no reference to it from inside the program.

Corin phase 1 test coverage lives under [Testing](#testing) below.

<a id="corin-open-questions"></a>
### Open questions

~~~json
{"vibecode": {"open_questions":
["bwc_handler_calling_convention",
"capture_sink_signature",
"stderr_vs_stdout_split",
"sys_role_check_after_corin"],
"resolved":
["bwc_owning_role_attachment_mechanism_resolved_2026-05-17_as_struct_per_bwc_fn_and_owning_role"]}}
~~~

- **bwc handler calling convention.** Aslan method handlers take
  `(receiver, args)`. bwc handlers don't have a receiver — they're
  callable entities themselves. Options: `(args)`, `(env, args)`,
  `(interp, args)`. Recommendation: match the existing
  `interpreter.lua` pattern `(interp, args)` so the engine instance is
  available for stdout writes. Settled during implementation.
- **Capture sink signature.** `env.stdout(s)` taking a single string,
  matching `interpreter.lua`. Buffer reconstruction happens in the
  test helper, not in the engine.
- **stderr.** Out of scope for Corin. When stderr arrives, the same
  pattern duplicates: `engine.roles.stderr` + an `eprint` or similar
  bwc + `env.stderr` override.
- **Sys-role consistency check.** Per Aslan's role footprint, `%role`
  was supposed to be implemented as a system method but the Aslan
  shipping code didn't include it (the hello-world fixture didn't
  exercise it, so it passed). Corin doesn't need `%role` either, but
  the gap is worth tracking — fix when first slice that needs it
  arrives.

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing",
"test_directory": "tests/caspian/corin/",
"fixture_path": "tests/caspian/fixtures/puts_hello.casp",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TC.0.1", "TC.0.2"],
"phase_1_tests": ["TC.1", "TC.2", "TC.3", "TC.4", "TC.5",
"TC.6", "TC.7"],
"load_bearing_test":
"TC.5_transition_to_stdout_role_actually_observed"}}
~~~

Corin has nine tests total: two Phase 0 source-pipeline and signature
checks plus seven Phase 1 unit + integration + regression tests. TC.5
(role transition to `stdout` observed during `puts` dispatch) is the
load-bearing assertion — mirror of Aslan TA.8, proves the cross-role
machinery actually fires.

<a id="corin-phase-0-test-plan"></a>
### Phase 0 test plan

~~~json
{"vibecode": {"phase_0_tests":
[{"id": "TC.0.1", "verifies":
"source_pipeline_completes_for_puts_hello_fixture_and_baseline_output_captured",
"tool": "tests/caspian/corin/test_source_baseline.lua", "level": "unit"},
{"id": "TC.0.2", "verifies":
"engine_run_source_signature_compatible_with_optional_env_argument",
"tool": "tests/caspian/corin/test_env_signature.lua", "level": "unit"}]}}
~~~

| ID | Level | Verifies | Tool |
|---|---|---|---|
| TC.0.1 | unit | Source pipeline completes for `puts 'hello'`; baseline transpiler output captured | `test_source_baseline.lua` |
| TC.0.2 | unit | `engine.run_source` accepts (or can accept) an `env` argument compatibly | `test_env_signature.lua` |

Step 0.3 is reference reading, not a test. Both TC.0.x must pass
before Corin phase 1 begins.

<a id="corin-phase-1-test-plan"></a>
### Phase 1 test plan

~~~json
{"vibecode": {"phase_1_tests":
[{"id": "TC.1", "verifies":
"transpiler_emits_canonical_bwc_form_for_puts_hello_deep_equal_to_expected_target",
"level": "unit"}, {"id": "TC.2", "verifies":
"engine_bootstrap_registers_stdout_role_and_puts_bwc",
"level": "unit"}, {"id": "TC.3", "verifies":
"engine_dispatch_routes_bwc_statement_to_handler_via_role_transition",
"level": "unit"}, {"id": "TC.4", "verifies":
"engine_run_source_accepts_env_with_stdout_override",
"level": "unit"}, {"id": "TC.5", "verifies":
"transition_to_stdout_role_observed_during_puts_dispatch",
"level": "unit_observability_check"}, {"id": "TC.6", "verifies":
"end_to_end_puts_hello_source_produces_hello_newline_in_capture_buffer",
"level": "integration_end_to_end"}, {"id": "TC.7", "verifies":
"aslan_engine_run_and_bree_engine_run_source_paths_still_pass_for_their_prior_fixtures",
"level": "regression_check"}]}}
~~~

| ID | Level | Verifies | How |
|---|---|---|---|
| TC.1 | unit | Transpiler emits canonical bwc form | `assert.deep_equal(caspian.transpile("puts 'hello'"), {{ {bwc="puts"}, {value="hello"} }})` |
| TC.2 | unit | Bootstrap registers stdout role and `puts` | `engine.roles.stdout` exists; `engine.bwcs.puts.fn` is a function; `engine.bwcs.puts.owning_role == engine.roles.stdout` |
| TC.3 | unit | Dispatch routes bwc to handler | Hand-build `[{bwc:"puts"}, {value:"x"}]`; pass to `engine.dispatch` with a capture env; assert capture has `"x\n"` |
| TC.4 | unit | `env.stdout` override accepted | `engine.run_source(path, {stdout = capture})` runs without error |
| TC.5 | unit | Transition to stdout role observed during dispatch | Spy on `puts` handler records role at call time; assert it was `stdout` |
| TC.6 | integration | End-to-end via source file | `engine.run_source("tests/caspian/fixtures/puts_hello.casp", env)` leaves `env` buffer == `"hello\n"` |
| TC.7 | regression | Aslan and Bree fixtures still work | Run Aslan `hello_world.caspj` via `engine.run` and Bree `hello_world.casp` via `engine.run_source`; both still return payload `"hello"` |

All seven pass = Corin done.

<a id="corin-test-layout"></a>
### Test layout

~~~json
{"vibecode": {"test_directory": "tests/caspian/corin/",
"fixture_path": "tests/caspian/fixtures/puts_hello.casp",
"entry_point_change":
"tests_caspian_run_lua_extended_to_require_corin_test_modules",
"capture_sink_helper":
"tests_caspian_corin_support_capture_lua_or_inlined_per_test",
"transpiler_test_updates":
"tests_caspian_transpiler_test_files_for_bwc_paths_updated_only"}}
~~~

| Path | Contents |
|---|---|
| `tests/caspian/fixtures/puts_hello.casp` | Source fixture for Corin |
| `tests/caspian/corin/` | Phase 0 and Phase 1 tests |
| `tests/caspian/run.lua` | Extended to require Corin test modules |
| `tests/caspian/transpiler/test_*.lua` | Updated only for bwc paths realigned in Corin |
