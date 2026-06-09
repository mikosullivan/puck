# Corin

~~~vibecode
{"vibecode": {"codename": "Corin", "delivers": "caspian-with-stdout", "goal":
"execute puts_hello_from_caspian_source_and_observe_the_string_arrive_on_stdout",
"medium": "caspian_source_text", "fixture":
"puts 'hello'", "fixture_path":
"tests/caspian/fixtures/puts_hello.casp", "expected_canonical_ksj":
"[[{\"bwc\": \"puts\"}, {\"value\": \"hello\"}]]", "expected_stdout":
"hello\\n", "observation":
"host_sets_engine_std_to_capture_sink_then_stages_tree_and_calls_engine_run; capture_buffer_payload_match",
"covers": ["bwc_dispatch_in_engine_lua",
"stdout_sink_capability_and_role", "puts_bwc_implementation",
"transpiler_realignment_for_bwc_statement_shape",
"engine_std_property_for_stdout_sink_injection"],
"reuses_from_prior": ["json_parser", "bootstrap", "materialize",
"lookup_method", "transition", "dispatch", "engine_run",
"engine_parse_caspian", "engine_caspianj_property"], "first_real_io": true,
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
   handler structs `{fn, owning_role}`. The Aslan dispatcher only handles
   `[receiver, method, args?]` for value receivers; Corin extends it to
   `[{bwc: name}, arg?]` for bwc receivers.
2. **stdout sink capability.** A function the host installs on
   `engine.std` before calling `engine.run()`. stdout is a sink (values
   flow out), not a faucet (which would be input). Following
   [roles.md](../../caspian/roles.md), the bwc that writes to it has
   its own role (`stdout`). Per
   [bootstrap.md § stdout and stderr](../../caspian/bootstrap.md#stdout-and-stderr)
   it is **not ambient** — there is no default. If `engine.std` is unset
   when `puts` dispatches, the handler raises. The CLI runner (later)
   wires `engine.std = function(s) io.write(s) end`; tests wire a capture
   buffer.
3. **`puts` bwc handler.** A function under the `stdout` role that
   takes a single materialized value, coerces its payload to string,
   appends a newline, writes to `engine.std`. The dispatcher's role
   transition handles the cross-role bookkeeping automatically.

The transpiler also gets one more realignment: the bwc-call statement
shape. Bree realigned literal + method-call + expression-statement;
Corin realigns the bwc-call form `[{bwc: "puts"}, {value: "hello"}]`.

<a id="definition-of-done-corin"></a>
### Definition of done

~~~vibecode
{"vibecode": {"scope_status": "drafted_2026-05-17; updated_2026-05-27_for_property_based_engine_api",
"done_criteria":
{"source_fixture_parses_and_transpiles_to_canonical_bwc_form":
"engine_parse_caspian_output_for_puts_hello_deep_equals_expected_canonical_ksj",
"bwc_registry_has_puts_after_bootstrap":
"engine_bootstrap_registers_puts_bwc_owned_by_stdout_role",
"engine_dispatches_bwc_statements":
"dispatcher_recognizes_bwc_receiver_form_and_routes_to_handler_via_role_transition_pushing_bwc_call_frame",
"stdout_sink_receives_hello_newline":
"with_engine_std_set_to_capture_sink_and_tree_staged_on_engine_caspianj_calling_engine_run_produces_buffer_equal_to_hello_newline",
"puts_raises_without_engine_std":
"with_engine_std_nil_calling_engine_run_on_the_fixture_raises_no_silent_default_to_io_stdout"}}}
~~~

Corin is done when all five are true:

1. **Source fixture parses and transpiles.** `puts 'hello'` lexes,
   parses, and transpiles to `[[{"bwc": "puts"}, {"value": "hello"}]]`
   exactly (deep-equal via the Bree `assert.deep_equal` helper).
2. **bwc registry has `puts` after bootstrap.** `engine.bwcs.puts`
   exists as a struct `{fn = <function>, owning_role = engine.state.roles.stdout}`,
   callable via the dispatcher.
3. **Engine dispatches bwc statements.** Handing a bwc-shape statement
   to `engine.dispatch` resolves the handler, transitions to `stdout`
   role (pushing a `bwc_call` frame with `bwc: <name>` instead of the
   `receiver_type`/`method` pair on a `method_call` frame), calls the
   handler, pops the frame.
4. **Stdout sink receives `"hello\n"`.** A test that installs a capture
   sink on `engine.std`, stages the parsed fixture on `engine.caspianj`,
   and calls `engine.run()` ends with the captured buffer equal to
   `"hello\n"`.
5. **`puts` raises when `engine.std` is unset.** With `engine.std = nil`,
   `engine.run()` on the fixture raises a clear error. There is no
   silent default to `io.stdout`; stdout is a capability, not ambient
   ([bootstrap.md § stdout and stderr](../../caspian/bootstrap.md#stdout-and-stderr)).

That's the entirety of Corin. Soft feature lock applies.


---

<a id="corin-phase-0-stdout-and-bwc-workbench"></a>
## Phase 0: stdout-and-bwc workbench

~~~vibecode
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

~~~vibecode
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

<a id="corin-step-02-confirm-engine-std-property-slot"></a>
### Step 0.2: Confirm the engine has a property slot for stdout

~~~vibecode
{"vibecode": {"step": "0.2", "name": "std_property_slot_check",
"action":
"verify_that_setting_engine_std_to_a_function_before_running_a_bree_fixture_does_not_break_anything; bree_run_should_be_a_no_op_with_respect_to_engine_std",
"acceptance":
"engine_std_can_be_assigned_without_error; bree_fixture_still_returns_payload_hello_when_engine_std_is_set_because_bree_fixture_does_not_call_puts"}}
~~~

Bree settled the property-based engine API: `engine.caspianj` for the
tree, `engine.std` reserved for the stdout sink, `engine.run()` with no
args. Step 0.2 confirms `engine.std` can be assigned today without
disturbing anything — Bree's hello-world doesn't call `puts`, so setting
`engine.std = function(s) end` and running the Bree fixture must still
return payload `"hello"`.

If `engine.std` isn't currently mentioned in `engine.lua`'s module
header, Corin Phase 1 Step 2 documents it as a recognized property
(the field is just `M.std`; no code change needed to "support"
assignment in Lua — but the doc reflects that the property is now
load-bearing).

<a id="corin-step-03-pre-canonical-legacy-bwc-handling-for-reference"></a>
### Step 0.3: Pre-canonical legacy bwc handling, for reference

~~~vibecode
{"vibecode": {"step": "0.3", "name": "legacy_bwc_reference",
"action":
"read_interpreter_lua_to_observe_how_puts_was_handled_in_the_pre_canonical_pipeline",
"acceptance":
"summary_recorded_of_legacy_puts_implementation_for_corin_phase_1_to_borrow_what_is_useful_without_inheriting_the_pre_canonical_shape"}}
~~~

`interpreter.lua` already has a `puts` bwc handler (it predates Aslan
and is otherwise dead code now). Step 0.3 reads that implementation as
a reference — particularly the "sink is just a one-arg function that
takes a string" pattern. Corin adopts that idea verbatim (now via
`engine.std` instead of `env.stdout`); the canonical CaspianJ shape is
different but the sink interface doesn't need to change.

Corin phase 0 test coverage lives under [Testing](#testing) below.

---

<a id="corin-phase-1-puts-hello-from-caspian-source"></a>
## Phase 1: puts-hello from Caspian source

~~~vibecode
{"vibecode": {"phase": 1, "fixture_path":
"tests/caspian/fixtures/puts_hello.casp", "fixture_content":
"puts 'hello'", "runner_path": "tests/caspian/run.lua",
"acceptance":
"fixture_transpiles_to_canonical_bwc_form_and_with_engine_std_capture_sink_engine_run_produces_capture_buffer_hello_newline",
"required_work":
["transpiler_realignment_for_bwc_call_statement",
"engine_bwc_registry_with_puts_handler_owned_by_stdout_role",
"engine_stdout_role_in_state_roles",
"engine_dispatch_extended_to_recognize_bwc_receiver_form_and_push_bwc_call_frame",
"engine_std_property_documented_in_module_header",
"puts_handler_reads_engine_std_and_raises_when_nil",
"capture_sink_helper_for_tests"],
"reuses_from_prior":
["bootstrap", "materialize", "lookup_method", "transition",
"dispatch_for_method_call_form", "engine_run", "engine_caspianj_property",
"engine_parse_caspian", "assert_deep_equal"], "out_of_scope":
["stdin_faucet", "stderr_sink", "file_io", "variables_assignment",
"control_flow", "full_transpiler_retrofit_for_unrelated_bwcs",
"engine_run_signature_change"],
"tactic":
"minimal_extension_just_for_puts_with_one_string_argument; other_bwcs_and_multi_argument_bwc_calls_left_for_later"}}
~~~

Three steps. Same shape as Aslan/Bree Phase 1: inventory, fill gaps,
verify.

<a id="corin-step-1-inventory"></a>
### Step 1: Inventory

~~~vibecode
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

~~~vibecode
{"vibecode": {"step": 2, "name": "fill_gaps", "scope":
"bwc_dispatch_and_engine_std_property_only; not_other_bwcs_not_multi_argument_handling",
"work_items":
["transpiler_emit_canonical_for_bwc_call_statement",
"engine_bootstrap_extended_to_register_stdout_role_and_puts_bwc",
"engine_dispatch_extended_to_branch_on_bwc_receiver_form_and_push_bwc_call_frame",
"engine_std_property_documented_as_load_bearing_no_default_unset_raises",
"puts_handler_reads_engine_std_and_raises_when_nil",
"capture_sink_helper_for_tests",
"existing_transpiler_tests_for_bwc_paths_updated_to_canonical_shape"],
"non_work":
["other_bwcs_beyond_puts", "multi_argument_bwc_calls",
"keyword_argument_bwc_calls", "stderr_separation",
"flushing_or_buffering_strategies",
"interpreter_lua_or_its_tests_modified",
"engine_run_signature_change"]}}
~~~

For each gap from Step 1, add only what Corin needs:

- **Transpiler.** Realign the bwc-call path to emit the canonical
  `[{bwc: name}, arg?]` shape. Existing transpiler tests for bwc paths
  get updated; tests for unrelated paths stay as-is.
- **Engine bootstrap.** Add an `stdout` role to `engine.state.roles`
  and an `engine.bwcs` table mapping `"puts"` to a struct entry:
  `engine.bwcs.puts = {fn = function(value) ... end, owning_role = engine.state.roles.stdout}`.
  Each bwc carries its own metadata (handler function, owning role)
  in a single entry — no parallel role-lookup table to keep in sync.
  Forward-compatible for additional per-bwc fields later (docs,
  deprecation flag, version) without an engine-wide refactor.
- **Engine dispatch.** Extend `engine.dispatch` to branch on the
  receiver form: if `statement[1]` is `{bwc: <name>}`, look up the
  entry in `engine.bwcs`, push a `bwc_call` frame (carrying `bwc: <name>`
  instead of the `receiver_type`/`method` pair a `method_call` frame
  carries) via `engine.transition` to `entry.owning_role`, call
  `entry.fn(materialized_arg)`, pop.
- **`engine.std` property is now load-bearing.** Documented in
  `engine.lua`'s module header as recognized. No default. If a `puts`
  dispatch fires while `engine.std == nil`, the handler raises with
  a clear message. Per
  [bootstrap.md § stdout and stderr](../../caspian/bootstrap.md#stdout-and-stderr).
- **`puts` handler.** Signature: takes one materialized value
  `{type, owning_role, payload}`. Reads `engine.std`; if nil, raises.
  Otherwise: `engine.std(tostring(value.payload) .. "\n")`. The
  handler closes over the engine module reference (it's defined in
  `engine.lua` inside `bootstrap`, so direct module access is trivial).
- **Test capture sink helper.** A small Lua-side helper that returns
  a function plus a buffer reference. The test sets
  `engine.std = capture.sink` and inspects `capture.buffer` after
  `engine.run()` returns. Lives under `tests/caspian/corin/support/`
  or inlined per test.

Per the no-bolt-on principle: anything beyond `puts` with one string
argument (a second bwc, two arguments, kwargs, escapes inside the
string, etc.) is later work. `engine.run` keeps its no-args signature
from Bree.

<a id="corin-step-2-drinian-impact"></a>
#### Drinian impact

Corin adds a new role (`stdout`), a new registry (`engine.bwcs`),
and a new sink property (`engine.std`) — but the shape of the
[Drinian state hash](aslan.md#data-structures-lua-tables) doesn't
change. Where each piece lives:

| New thing | Where it lives | In the Drinian hash? |
|---|---|---|
| `stdout` role object | `engine.state.roles.stdout` | Yes — `state.roles` lives IN drinian (per Aslan) |
| `engine.bwcs.puts` entry | `engine.bwcs` | No — bwc registry is engine-private metadata, alongside `engine.classes` |
| Capture sink function | `engine.std` (host-supplied property) | No — sinks are host-installed capabilities on the engine module, not program state |
| Cross-role transition to `stdout` | A `bwc_call` frame with `role == engine.state.roles.stdout` and `bwc == "puts"` pushed on `engine.state.call_stack` while the `puts` handler runs | **Yes** — this is the one execution-state effect Corin has |

So `engine.state.roles` grows (gains `stdout`), but the top-level
Drinian shape stays the same. Mid-call, the top frame's `role` gets
a new possible value: alongside `user` and `stdlib`, Corin dispatch
can push a frame with `stdout`. Step 3's snapshots show that
transition in action.

**`bwc_call` frame shape** is a new frame variant alongside
`method_call`: `{action: "bwc_call", role: <stdout role>, bwc: <name>,
chain, locals}`. No `receiver_type` or `method` (those are
method-call-specific).

<a id="corin-step-3-verify"></a>
### Step 3: Verify

~~~vibecode
{"vibecode": {"step": 3, "name": "verify", "actions":
["create_caspian_source_fixture",
"build_capture_sink",
"set_engine_std_to_capture_sink",
"stage_parsed_tree_on_engine_caspianj",
"call_engine_run",
"assert_captured_buffer_equals_hello_newline",
"separately_assert_parse_caspian_output_matches_canonical_bwc_shape"],
"pass_condition":
"captured_buffer_equals_hello_newline_and_parse_caspian_output_deep_equals_canonical_target",
"fail_condition":
"any_deviation; failure_message_names_which_layer_blocked"}}
~~~

Create `tests/caspian/fixtures/puts_hello.casp` containing
`puts 'hello'`. Build a capture sink. Stage and run:

```lua
local capture = make_capture()                  -- returns { sink, get_buffer }
engine.std    = capture.sink

local f = assert(io.open("tests/caspian/fixtures/puts_hello.casp", "r"))
local source = f:read("*a"); f:close()
engine.caspianj = engine.parse_caspian(source)
engine.run()
```

Verify:

1. `capture.get_buffer()` returns `"hello\n"`.
2. The parse_caspian output (captured separately) deep-equals
   `[[{"bwc": "puts"}, {"value": "hello"}]]`.

If either fails, the message must identify which layer blocked. Loop
back to Step 2 for that layer.

When Corin passes, Digory is selected from the roadmap and planned at
the same detail level as Bree and Corin.

<a id="corin-step-3-drinian-snapshots"></a>
#### Drinian snapshots during the run

Corin doesn't change the top-level Drinian hash shape, but it does
grow `state.roles` (gaining `stdout`) and a `puts` dispatch pushes a
frame carrying that role mid-call. The stdout sink itself lives on
`engine.std` (the host-installed capability property on the engine
module) — **not** in `engine.state`, since sinks are host-supplied
capabilities, not program state.

**After `engine.bootstrap()`, before any statement dispatches:**

```json
{
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "chain": {"log": {}, "misc": {}},
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
      "action": "top_level",
      "role": "user",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    },
    {
      "action": "bwc_call",
      "role": "stdout",
      "bwc": "puts",
      "chain": {"log": {}, "misc": {}},
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
      "action": "top_level",
      "role": "user",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

Side effects visible outside the Drinian hash during the `puts`
call: the capture buffer behind `engine.std` accumulates the string
`"hello\n"`. That buffer is the host's, not the engine's — Caspian
code has no reference to it from inside the program.

Corin phase 1 test coverage lives under [Testing](#testing) below.

<a id="corin-open-questions"></a>
### Open questions

~~~vibecode
{"vibecode": {"open_questions":
["sys_role_check_after_corin"],
"resolved":
["bwc_owning_role_attachment_mechanism_resolved_2026-05-17_as_struct_per_bwc_fn_and_owning_role",
"bwc_handler_signature_resolved_2026-05-27_as_single_materialized_value_via_closure_over_engine_module",
"capture_sink_signature_resolved_2026-05-27_as_function_taking_one_string",
"stderr_resolved_2026-05-27_as_out_of_scope_same_pattern_when_it_arrives"]}}
~~~

- **bwc handler signature: `(value)` — one materialized value.** The
  handler closes over the engine module (it's registered inside
  `engine.bootstrap`), so it reads `engine.std` directly. Multi-arg
  bwcs are out of scope for Corin; when they arrive, the signature
  generalizes to a list of values.
- **Capture sink signature: `function(s)` taking one string.** The
  test helper accumulates strings into a buffer and exposes the
  concatenated form for assertion.
- **stderr.** Out of scope for Corin. When stderr arrives, the same
  pattern duplicates: `engine.state.roles.stderr` + an `eprint` (or
  similar) bwc + `engine.err` (or similar) property.
- **Sys-role consistency check.** Per Aslan's role footprint, `%role`
  was supposed to be implemented as a system method but the Aslan
  shipping code didn't include it (the hello-world fixture didn't
  exercise it, so it passed). Corin doesn't need `%role` either, but
  the gap is worth tracking — fix when first slice that needs it
  arrives.

---

<a id="testing"></a>
## Testing

~~~vibecode
{"vibecode": {"section": "testing",
"test_directory": "tests/caspian/corin/",
"fixture_path": "tests/caspian/fixtures/puts_hello.casp",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TC.0.1", "TC.0.2"],
"phase_1_tests": ["TC.1", "TC.2", "TC.3", "TC.4", "TC.5",
"TC.6", "TC.7", "TC.8"],
"load_bearing_test":
"TC.5_transition_to_stdout_role_actually_observed"}}
~~~

Corin has ten tests total: two Phase 0 source-pipeline and property
checks plus eight Phase 1 unit + integration + regression tests. TC.5
(role transition to `stdout` observed during `puts` dispatch) is the
load-bearing assertion — mirror of Aslan TA.8, proves the cross-role
machinery actually fires. TC.8 verifies the no-ambient-stdout property
— `puts` raises when `engine.std` is unset.

<a id="corin-phase-0-test-plan"></a>
### Phase 0 test plan

~~~vibecode
{"vibecode": {"phase_0_tests":
[{"id": "TC.0.1", "verifies":
"source_pipeline_completes_for_puts_hello_fixture_and_baseline_parse_caspian_output_captured",
"tool": "tests/caspian/corin/test_source_baseline.lua", "level": "unit"},
{"id": "TC.0.2", "verifies":
"engine_std_property_can_be_assigned_without_disturbing_bree_fixture_run",
"tool": "tests/caspian/corin/test_std_property_slot.lua", "level": "unit"}]}}
~~~

| ID | Level | Verifies | Tool |
|---|---|---|---|
| TC.0.1 | unit | Source pipeline completes for `puts 'hello'`; baseline `engine.parse_caspian` output captured | `test_source_baseline.lua` |
| TC.0.2 | unit | Setting `engine.std = function(s) end` before running the Bree fixture doesn't disturb the result (the fixture has no `puts`) | `test_std_property_slot.lua` |

Step 0.3 is reference reading, not a test. Both TC.0.x must pass
before Corin phase 1 begins.

<a id="corin-phase-1-test-plan"></a>
### Phase 1 test plan

~~~vibecode
{"vibecode": {"phase_1_tests":
[{"id": "TC.1", "verifies":
"engine_parse_caspian_emits_canonical_bwc_form_for_puts_hello_deep_equal_to_expected_target",
"level": "unit"}, {"id": "TC.2", "verifies":
"engine_bootstrap_registers_stdout_role_and_puts_bwc",
"level": "unit"}, {"id": "TC.3", "verifies":
"engine_dispatch_routes_bwc_statement_to_handler_via_role_transition_pushing_bwc_call_frame",
"level": "unit"}, {"id": "TC.4", "verifies":
"engine_std_property_accepts_a_function_and_puts_handler_writes_through_it",
"level": "unit"}, {"id": "TC.5", "verifies":
"transition_to_stdout_role_observed_during_puts_dispatch",
"level": "unit_observability_check"}, {"id": "TC.6", "verifies":
"end_to_end_puts_hello_source_produces_hello_newline_in_capture_buffer",
"level": "integration_end_to_end"}, {"id": "TC.7", "verifies":
"aslan_caspianj_and_bree_source_pipelines_still_pass_for_their_prior_fixtures",
"level": "regression_check"}, {"id": "TC.8", "verifies":
"puts_raises_when_engine_std_is_nil_no_silent_default_to_io_stdout",
"level": "unit"}]}}
~~~

| ID | Level | Verifies | How |
|---|---|---|---|
| TC.1 | unit | `engine.parse_caspian` emits canonical bwc form | `assert.deep_equal(engine.parse_caspian("puts 'hello'"), {{ {bwc="puts"}, {value="hello"} }})` |
| TC.2 | unit | Bootstrap registers stdout role and `puts` | `engine.state.roles.stdout` exists; `engine.bwcs.puts.fn` is a function; `engine.bwcs.puts.owning_role == engine.state.roles.stdout` |
| TC.3 | unit | Dispatch routes bwc to handler | Set `engine.std = capture.sink`; hand-build `[{bwc:"puts"}, {value:"x"}]`; pass to `engine.dispatch`; assert capture buffer is `"x\n"` |
| TC.4 | unit | `engine.std` property accepted; `puts` writes through it | Set `engine.std = capture.sink`; stage a `[{bwc:"puts"}, {value:"hi"}]` tree on `engine.caspianj`; call `engine.run()`; assert capture buffer is `"hi\n"` |
| TC.5 | unit | Transition to stdout role observed during dispatch | Spy on `puts` handler records role-of-top-frame at call time; assert it was `stdout` |
| TC.6 | integration | End-to-end via source file | Set `engine.std = capture.sink`; stage parsed `puts_hello.casp` on `engine.caspianj`; `engine.run()`; assert capture buffer `== "hello\n"` |
| TC.7 | regression | Aslan and Bree fixtures still work | Run Aslan `hello_world.caspj` via stage-and-run, and Bree `hello_world.casp` via parse-stage-and-run; both still return payload `"hello"` |
| TC.8 | unit | `puts` raises when `engine.std` is unset | Set `engine.std = nil`; stage parsed `puts_hello.casp`; call `engine.run()`; assert it raises with a clear message |

All eight pass = Corin done.

<a id="corin-test-layout"></a>
### Test layout

~~~vibecode
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
