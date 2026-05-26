# Bree

~~~json
{"vibecode": {"codename": "Bree", "delivers": "caspian-source-hello", "goal":
"execute a caspian source program end_to_end through the transpiler and return a literal value to the test harness",
"medium": "caspian_source_text", "fixture":
"'hello'.to_string", "fixture_path":
"tests/caspian/fixtures/hello_world.casp", "expected_return": "hello",
"expected_canonical_ksj": "[[{\"value\": \"hello\"}, \"to_string\"]]",
"observation":
"test_harness_captures_last_statement_value_through_engine_run_source; no_stdout_io",
"covers": ["caspian_lexer", "caspian_parser",
"transpiler_to_canonical_ksj", "source_to_runtime_pipeline_wiring"],
"reuses_from_aslan": ["bootstrap", "materialize", "lookup_method",
"transition", "dispatch", "string_class_to_string"],
"deferred_to_later": ["stdout_io", "sys_references",
"additional_classes_or_methods",
"full_transpiler_realignment_for_all_caspian_constructs"]}}
~~~

Bree ships hello-world in Caspian source. Same semantic program as Aslan
— `'hello'.to_string` evaluated and the result returned to the harness —
now expressed as Caspian source text and executed through the lexer →
parser → transpiler → canonical CaspianJ → Aslan engine pipeline.

The source fixture is the single line `'hello'.to_string`. The expected
transpiled CaspianJ is `[[{"value": "hello"}, "to_string"]]` — exactly the
Aslan hand-written fixture. This equivalence is load-bearing: it proves
the transpiler emits canonical CaspianJ and that the source-text and JSON
paths converge on the same runtime tree.

Bree reuses every engine layer Aslan built: bootstrap, materialize,
lookup_method, transition, dispatch. The new work is on the source side
— the existing lexer/parser scaffolding gets exercised against the
fixture, the transpiler gets realigned to emit canonical CaspianJ for the
AST shape hello-world produces, and a thin source-side entry point
combines transpile + dispatch.

The transpiler realignment is **scoped to the hello-world AST nodes
only**. The full transpiler retrofit is incremental — later slices
realign more AST node types as later versions exercise them. Per
"don't generalize ahead of the test."

<a id="definition-of-done-bree"></a>
### Definition of done

~~~json
{"vibecode": {"scope_status": "drafted_2026-05-16", "done_criteria":
{"source_fixture_parses":
"tests_caspian_fixtures_hello_world_caspian_lexes_and_parses_without_error",
"transpiler_emits_canonical_ksj":
"transpiler_output_for_the_fixture_deep_equals_the_aslan_hand_written_fixture",
"source_side_entry_point_exists":
"engine_run_source_path_or_equivalent_takes_a_caspian_file_through_to_dispatch",
"returns_hello":
"engine_run_source_of_the_fixture_returns_a_value_whose_payload_equals_hello"}}}
~~~

Bree is done when all four are true:

1. **The source fixture parses.** `'hello'.to_string` lexes and parses
   without error using the existing `caspian.lexer` and `caspian.parser`
   modules.
2. **The transpiler emits canonical CaspianJ.** Running the source through
   the transpiler produces a Lua table deep-equal to the Aslan
   hand-written `[[{"value": "hello"}, "to_string"]]` fixture.
3. **A source-side entry point exists.** A function in the engine
   (working name: `engine.run_source(path)`) reads a `.casp` file,
   transpiles to canonical CaspianJ, and dispatches the result. The internal
   `engine.run(path)` (CaspianJ file) is refactored to share an
   `engine.run_tree(tree)` helper so both source and CaspianJ paths converge
   on the same dispatch loop.
4. **The harness receives `"hello"`.** `engine.run_source(fixture_path)`
   returns a value whose `.payload == "hello"`.

That's the entirety of Bree. Soft feature lock applies — same posture
as Aslan.


---

<a id="bree-phase-0-source-side-workbench"></a>
## Phase 0: source-side workbench

~~~json
{"vibecode": {"phase": 0, "purpose":
"characterize_existing_lexer_parser_transpiler_state_against_bree_fixture; no_realignment_work_yet",
"steps_count": 4, "acceptance":
"all_four_workbench_checks_pass_and_produce_a_concrete_gap_list_for_phase_1; no_engine_code_changed",
"tactic":
"exercise_existing_pipeline_with_bree_fixture_string; observe_each_layer_output",
"differs_from_aslan_phase_0":
"aslan_phase_0_verified_lua_environment_and_json_lua_existed; bree_phase_0_verifies_existing_caspian_source_pipeline_handles_the_fixture_input"}}
~~~

Bree's workbench is the existing Caspian source pipeline (lexer →
parser → transpiler). Before realigning the transpiler, Phase 0
characterizes what each layer produces today for the Bree fixture
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
"tool": "caspian.tokenize from init.lua",
"acceptance":
"no_lex_error; token_sequence_includes_string_literal_hello_then_dot_then_identifier_to_string"}}
~~~

`caspian.tokenize("'hello'.to_string")` returns a token sequence
covering the literal, the dot, and the identifier `to_string`. Existing
lexer tests under `tests/caspian/lexer/` exercise each form
individually; this step confirms the combination tokenizes cleanly.

<a id="step-02-confirm-the-parser-produces-a-clean-ast"></a>
### Step 0.2: Confirm the parser produces a clean AST

~~~json
{"vibecode": {"step": "0.2", "name": "parser_check",
"input": "'hello'.to_string",
"expected_program_shape":
"program_node_with_one_statement_node_representing_a_method_call_on_a_string_literal",
"tool": "caspian.parse from init.lua",
"acceptance":
"no_parse_error; ast_shape_documented_for_phase_1_inventory"}}
~~~

`caspian.parse("'hello'.to_string")` returns an AST. Step 0.2 documents
the exact `kind` of the top-level node, the method-call node, and the
literal node so Phase 1 step 1 can compare directly.

<a id="step-03-observe-the-transpilers-current-output"></a>
### Step 0.3: Observe the transpiler's current output

~~~json
{"vibecode": {"step": "0.3", "name": "transpiler_baseline",
"input": "'hello'.to_string",
"tool": "caspian.transpile from init.lua",
"expected":
"captures_actual_current_output_for_comparison_to_canonical_in_phase_1",
"acceptance":
"transpile_completes_without_error; output_recorded_as_phase_1_baseline; current_shape_is_pre_canonical_and_that_is_expected"}}
~~~

`caspian.transpile("'hello'.to_string")` returns a Lua table. The
current output is pre-canonical — it matches `interpreter.lua`'s
consumption shape, not `caspianj.md`'s `[receiver, method, args?]`
shape. Phase 0 captures what comes out today; the diff against canonical
is computed in Phase 1.

<a id="step-04-confirm-enginerun-handles-a-hand-built-canonical-tree"></a>
### Step 0.4: Confirm engine.run handles a hand-built canonical tree

~~~json
{"vibecode": {"step": "0.4", "name": "engine_tree_entry_check",
"action":
"build_the_aslan_canonical_tree_in_lua_pass_to_a_run_tree_helper_or_equivalent_path",
"acceptance":
"end_to_end_returns_value_with_payload_hello_using_a_lua_built_tree_not_a_file",
"note":
"validates_the_run_tree_internal_split_before_phase_1_wires_it_to_transpiler_output"}}
~~~

The Aslan engine takes a path (`engine.run(path)`) — it reads the file,
parses JSON, then iterates. To wire the transpiler in, the file-read +
JSON-parse step has to be separable from the dispatch loop. Step 0.4
confirms (or, if needed, introduces) a callable
`engine.run_tree(tree)` that takes a pre-built canonical CaspianJ Lua table
and returns the same result the file-based path would.

If the Aslan implementation already factored this out, Step 0.4 is a
one-line test. If not, Step 0.4 adds the helper purely as refactoring
(behavior unchanged for the existing path).

<a id="bree-step-04-skeletor-snapshot"></a>
#### Skeletor snapshot during the hand-built-tree run

This is the first place in Bree where the engine actually runs, so
it's also the first place [`engine.state`](aslan.md#data-structures-lua-tables)
exists in a Bree context. The hand-built tree dispatches
`"hello".to_string` through the same Aslan engine machinery, so the
snapshots match aslan.md Step 8 exactly:

```json
{
  "call_stack": [
    {"action": "top_level", "role": "user",
     "chain": {"log": {}, "misc": {}}, "locals": {}}
  ]
}
```

after bootstrap, a `method_call` frame for `stdlib` pushed mid
`to_string`, then popped on return. Step
0.4's job is to confirm `engine.run_tree(tree)` walks this path
without depending on a `.caspj` file — the refactor doesn't change
what the hash looks like, only how the tree got into the dispatcher.

Bree phase 0 test coverage lives under [Testing](#testing) below.

---

<a id="bree-phase-1-hello-world-from-caspian-source"></a>
## Phase 1: hello-world from Caspian source

~~~json
{"vibecode": {"phase": 1, "fixture_path":
"tests/caspian/fixtures/hello_world.casp", "fixture_content":
"'hello'.to_string", "runner_path":
"tests/caspian/run.lua", "acceptance":
"fixture_transpiles_to_canonical_ksj_and_engine_run_source_returns_value_payload_hello",
"required_work":
["transpiler_realignment_for_hello_world_ast_only",
"engine_run_source_entry_point",
"engine_run_tree_internal_helper_if_not_already_present",
"deep_equal_assert_helper"], "reuses_from_aslan":
["bootstrap", "materialize", "lookup_method", "transition", "dispatch"],
"out_of_scope":
["full_transpiler_retrofit", "interpreter_lua_removal",
"renaming_or_deprecation_of_existing_caspian_run_source_in_init_lua",
"sys_references_or_stdout_io",
"additional_classes_or_methods_beyond_to_string"],
"tactic":
"minimal_realignment_just_for_hello_world_ast; later_slices_extend",
"canon":
"caspianj_md_is_canonical; transpiler_output_must_match_aslan_hand_written_fixture_for_this_ast"}}
~~~

Three steps. Same shape as Aslan Phase 1: inventory, fill gaps, verify.

<a id="bree-step-1-inventory"></a>
### Step 1: Inventory

~~~json
{"vibecode": {"step": 1, "name": "inventory", "actions":
["catalog_existing_lexer_parser_transpiler_against_bree_fixture",
"document_ast_shape_for_method_call_on_string_literal",
"document_current_transpiler_output_for_that_ast",
"compute_diff_to_canonical_ksj_target",
"identify_which_transpiler_test_files_will_need_updating"],
"output":
"concrete_gap_description_for_step_2; list_of_existing_transpiler_tests_to_be_updated"}}
~~~

Read the existing `lexer.lua`, `parser.lua`, and `transpiler.lua` with
the Bree fixture in mind. Document:

- The exact AST node `kind` returned for `'hello'.to_string`.
- The exact Lua-table shape the current transpiler emits for that AST
  node.
- The diff between that shape and the canonical
  `[[{"value": "hello"}, "to_string"]]`.
- The set of existing transpiler tests under
  `tests/caspian/transpiler/` that assert on the pre-canonical shape
  for the AST nodes we'll realign. These will need updating in Step 2.

Output: a short text summary of the gap (which fields differ, which
wrapper objects are present in one but not the other) plus the list of
transpiler tests requiring updates.

<a id="bree-step-2-fill-the-gaps"></a>
### Step 2: Fill the gaps

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

For each gap from Step 1, add only what Bree needs:

- **Transpiler.** Realign the path covering the AST nodes the Bree
  fixture produces — likely the string-literal expression, the
  method-call expression, and the top-level expression-statement
  wrapper. Other AST node types (assignment, if, while, bwc, function
  definition, etc.) stay pre-canonical for now.
- **Engine wiring.** Add `engine.run_source(path)` that reads a
  `.casp` file, transpiles to canonical CaspianJ, and iterates the
  dispatch loop. If `engine.run` doesn't already separate file-read
  from dispatch, extract `engine.run_tree(tree)` and refactor
  `engine.run` to call it. `engine.run_source(path)` also calls
  `engine.run_tree`. **The Skeletor hash is unchanged by this
  wiring** — `engine.run_source` calls into the same
  `engine.bootstrap()` + dispatch loop as `engine.run`, so
  [`engine.state`](aslan.md#data-structures-lua-tables) goes through
  the same transitions whether the tree arrived from a file or from
  the transpiler.
- **Existing transpiler tests.** Any tests asserting on the
  pre-canonical shape for AST nodes we realign will fail; update those
  tests to the canonical shape. Tests for AST nodes we don't touch
  stay as-is.
- **Assertion helper.** Add `assert.deep_equal(got, expected, msg)` to
  `tests/caspian/support/assert.lua` for table equality with a
  first-divergent-path failure message. Needed by TB.1 and useful for
  every later slice that compares trees.

Anything beyond this — realigning the bwc path, the assignment path,
the if path, etc. — is later work. The principle: realign as later
slices exercise each AST node, not all at once.

<a id="bree-step-3-verify"></a>
### Step 3: Verify

~~~json
{"vibecode": {"step": 3, "name": "verify", "actions":
["create_caspian_source_fixture",
"run_via_engine_run_source",
"compare_returned_value_payload_to_hello",
"compare_transpiled_tree_to_aslan_hand_written_canonical_fixture"],
"pass_condition":
"return_value_payload_equals_hello_and_transpiled_tree_deep_equals_aslan_fixture_tree",
"fail_condition":
"any_deviation; failure_message_names_which_layer_blocked"}}
~~~

Create `tests/caspian/fixtures/hello_world.casp` containing
`'hello'.to_string`. Run it via `engine.run_source(path)`. Verify two
things:

1. The returned value has `payload == "hello"`.
2. The transpiled tree (captured before dispatch) deep-equals the Aslan
   hand-written `[[{"value": "hello"}, "to_string"]]` tree — the
   round-trip equivalence check that proves canonical alignment.

If either fails, the message must identify which layer blocked: parse
error, transpiler shape mismatch, dispatch failure, engine context
problem. Loop back to Step 2 for that layer.

When Bree passes, the next slice from the roadmap is selected and
planned in the same shape.

<a id="bree-step-3-skeletor-snapshots"></a>
#### Skeletor snapshots during the run

Bree runs the same semantic program as Aslan (just from source
instead of hand-written CaspianJ), so the
[Skeletor state hash](aslan.md#data-structures-lua-tables) goes
through the same three moments — bootstrap → mid-`to_string` →
return — and contains the same two fields. The transpiler step
happens **before** dispatch and leaves no Skeletor footprint;
intermediate AST nodes and the produced canonical tree live in Lua
locals, not in `engine.state`.

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

**Mid-dispatch, inside the `to_string` method call:**

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

**After `to_string` returns:**

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

Bree doesn't grow the Skeletor hash — the new source-side machinery
(lexer, parser, transpiler, `engine.run_source`, `engine.run_tree`)
all operates on working state outside the hash. The state hash next
changes shape in [Corin](corin.md), when the `stdout` role
joins the registry and shows up as the `role` on a pushed frame
during `puts` dispatch.

Bree phase 1 test coverage lives under [Testing](#testing) below.

<a id="bree-open-questions"></a>
### Open questions

~~~json
{"vibecode": {"open_questions":
["api_naming_for_source_side_entry_point",
"deep_equal_assert_helper_signature_and_first_divergent_path_format",
"whether_existing_caspian_run_source_in_init_lua_should_be_renamed_or_deprecated_in_bree_or_later",
"how_much_transpiler_test_churn_in_practice"]}}
~~~

- **API naming.** `engine.run_source(path)` is the working name.
  Alternatives: `engine.run_caspian(path)`, `caspian.run_source(path)`,
  `caspian.execute_file(path)`. Decision can wait until the function is
  written — easy to rename.
- **`assert.deep_equal` signature.** Existing `support/assert.lua` uses
  descriptive failure messages. The deep_equal helper should surface
  the first divergent path on mismatch (e.g.,
  `mismatch at [1][2]: expected "to_string", got "tostring"`). Exact
  message format settled when implemented.
- **Legacy `M.run(source, env)` in `init.lua`.** Currently goes through
  the pre-canonical pipeline + `interpreter.lua`. Out of scope for Bree
  — flagged for renaming or deprecation in a later slice once the
  transpiler is more broadly realigned.
- **Transpiler test churn.** Phase 0 step 3 will quantify how many
  existing transpiler tests assert on output shape that Bree changes.
  Expected to be small (only the string-literal and method-call paths)
  but worth confirming before Phase 1 starts.

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing",
"test_directory": "tests/caspian/bree/",
"fixture_path": "tests/caspian/fixtures/hello_world.casp",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TB.0.1", "TB.0.2", "TB.0.3", "TB.0.4"],
"phase_1_tests": ["TB.1", "TB.2", "TB.3", "TB.4", "TB.5", "TB.6"],
"load_bearing_tests":
["TB.1_transpiler_canonical_match", "TB.5_t2_6_regression_checks"]}}
~~~

Bree has ten tests total: four Phase 0 source-pipeline characterization
tests plus six Phase 1 unit + integration + regression tests. TB.1
(transpiler emits canonical for the fixture, deep-equal to the Aslan
hand-written tree) is the load-bearing correctness check; TB.5 and TB.6
are the load-bearing regression checks proving Bree's transpiler work
didn't break the Aslan CaspianJ path or pre-canonical AST nodes left
alone.

<a id="bree-phase-0-test-plan"></a>
### Phase 0 test plan

~~~json
{"vibecode": {"phase_0_tests":
[{"id": "TB.0.1", "verifies":
"lexer_handles_bree_fixture_string", "tool":
"tests/caspian/bree/test_lexer_check.lua", "level": "unit"},
{"id": "TB.0.2", "verifies":
"parser_returns_ast_for_bree_fixture_string", "tool":
"tests/caspian/bree/test_parser_check.lua", "level": "unit"},
{"id": "TB.0.3", "verifies":
"transpiler_completes_without_error_for_bree_fixture_string; current_output_captured_for_phase_1_comparison",
"tool": "tests/caspian/bree/test_transpiler_baseline.lua",
"level": "unit"}, {"id": "TB.0.4", "verifies":
"engine_run_tree_returns_value_for_hand_built_canonical_tree",
"tool": "tests/caspian/bree/test_engine_run_tree.lua",
"level": "unit"}]}}
~~~

| ID | Level | Verifies | Tool |
|---|---|---|---|
| TB.0.1 | unit | Lexer handles the fixture string | `test_lexer_check.lua` |
| TB.0.2 | unit | Parser returns an AST for the fixture | `test_parser_check.lua` |
| TB.0.3 | unit | Transpiler completes for the fixture; baseline captured | `test_transpiler_baseline.lua` |
| TB.0.4 | unit | `engine.run_tree` returns expected value for a hand-built tree | `test_engine_run_tree.lua` |

All four must pass (or the underlying issues must be resolved) before
Bree phase 1 begins.

<a id="bree-phase-1-test-plan"></a>
### Phase 1 test plan

~~~json
{"vibecode": {"phase_1_tests":
[{"id": "TB.1", "verifies":
"transpiler_emits_canonical_ksj_for_bree_fixture_deep_equal_to_aslan_hand_written_tree",
"level": "unit"}, {"id": "TB.2", "verifies":
"engine_run_tree_returns_payload_hello_for_aslan_canonical_tree",
"level": "unit"}, {"id": "TB.3", "verifies":
"engine_run_source_returns_payload_hello_for_bree_caspian_fixture_file",
"level": "integration_end_to_end"}, {"id": "TB.4", "verifies":
"ctx_back_to_user_after_engine_run_source_returns",
"level": "unit_observability_check"}, {"id": "TB.5", "verifies":
"existing_aslan_engine_run_path_still_returns_payload_hello_for_aslan_ksj_fixture",
"level": "regression_check"}, {"id": "TB.6", "verifies":
"existing_pre_canonical_transpiler_paths_for_unrelated_ast_types_unchanged_and_their_tests_still_pass",
"level": "regression_check"}]}}
~~~

Six tests for Bree phase 1. Each lives under `tests/caspian/bree/`
using the same framework (`support.runner` + `support.assert`).

| ID | Level | Verifies | How |
|---|---|---|---|
| TB.1 | unit | Transpiler emits canonical for the fixture | `assert.deep_equal(caspian.transpile("'hello'.to_string"), {{ {value="hello"}, "to_string" }})` |
| TB.2 | unit | `engine.run_tree` returns payload `"hello"` | Hand-build the canonical tree in Lua, pass to `engine.run_tree`, assert on result |
| TB.3 | integration | `engine.run_source` returns payload `"hello"` from the source fixture file | `engine.run_source("tests/caspian/fixtures/hello_world.casp")` |
| TB.4 | unit | ctx restored to user after `engine.run_source` returns | Mirror of Aslan TA.7's second assertion |
| TB.5 | regression | `engine.run` of Aslan CaspianJ fixture still works | Identical to Aslan TA.7 — must not regress |
| TB.6 | regression | Pre-canonical transpiler tests for unrelated AST types still pass | The unchanged transpiler test files continue to pass; the changed ones reflect canonical output |

All six pass = Bree done.

<a id="bree-test-layout"></a>
### Test layout

~~~json
{"vibecode": {"test_directory": "tests/caspian/bree/",
"fixture_path": "tests/caspian/fixtures/hello_world.casp",
"entry_point_change":
"tests_caspian_run_lua_extended_to_require_bree_test_modules",
"transpiler_test_updates":
"tests_caspian_transpiler_test_files_updated_only_for_realigned_ast_nodes",
"support_helper_addition":
"tests_caspian_support_assert_lua_gains_deep_equal_helper"}}
~~~

| Path | Contents |
|---|---|
| `tests/caspian/fixtures/hello_world.casp` | Caspian source fixture (sibling of `hello_world.caspj`) |
| `tests/caspian/bree/` | Phase 0 and Phase 1 unit + integration tests |
| `tests/caspian/run.lua` | Extended to require Bree test modules |
| `tests/caspian/support/assert.lua` | Gains a `deep_equal` helper |
| `tests/caspian/transpiler/test_*.lua` | Updated only for AST nodes realigned in Bree |
