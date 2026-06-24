# Bree

~~~vibecode
{"vibecode": {"codename": "Bree", "delivers": "caspian-source-hello", "goal":
"execute a caspian source program end_to_end through the transpiler and return a literal value to the test harness",
"medium": "caspian_source_text", "fixture":
"'hello'.to_string", "fixture_path":
"tests/caspian/fixtures/hello_world.casp", "expected_return": "hello",
"expected_canonical_caspj": "[[{\"value\": \"hello\"}, \"to_string\"]]",
"observation":
"test_harness_composes_transpile_plus_engine_run_and_captures_last_statement_value; no_stdout_io",
"covers": ["caspian_lexer", "caspian_parser",
"transpiler_to_canonical_caspj", "source_to_runtime_pipeline_wiring"],
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
fixture, a parser extension is added for the specific syntactic gap
the fixture exposes, the transpiler is verified to emit canonical
CaspianJ for that AST, and a thin source-side entry point combines
transpile + dispatch.

<a id="parser-extension"></a>
### Parser extension needed: literal-as-receiver

Phase-0 probing (2026-05-27) found a real gap: the current parser
rejects `'hello'.to_string` with "unexpected token DOT" — the grammar
treats string literals as terminal expressions and doesn't accept
them as receivers for method calls. The workaround `('hello').to_string`
parses fine because the parens promote the literal to a parenthesized
expression that can serve as a receiver.

**Bree extends the parser** to accept method calls on literal
expressions directly. The fixture stays as the natural form
`'hello'.to_string`.

**Scope of the extension: ALL literal kinds**, not just the string
literal Bree's fixture exercises. Once the postfix-method-call rule
is opened up, it accepts string, integer, decimal, boolean, null,
array, and hash literals as receivers:

```caspian
'hello'.to_string       # Bree's fixture
42.to_string            # integer literal as receiver
true.bool               # boolean as receiver
null.flavor             # null as receiver
[1, 2, 3].length        # array literal as receiver
{a: 1}.keys             # hash literal as receiver
```

Bree only **tests** the string case (per the fixture). The grammar
rule covers everything else for consistency — later slices that
exercise array, hash, or other literal receivers don't need to revisit
the parser. One small grammar change avoids four piecemeal updates.

**The transpiler does NOT need changes for Bree.** Existing transpiler
output for `('hello').to_string` is already `[[{"value": "hello"}, "to_string"]]`
— exactly canonical. Once the parser accepts the bare-literal form,
the transpiler walks the AST and produces the same canonical CaspianJ.
For Bree's specific AST shape (literal receiver + bare method name +
no args), pre-spec and canonical happen to agree.

<a id="lexer-end-marker"></a>
### Lexer extension: `__END__` recognition

A line containing only `__END__` terminates Caspian source — see
[caspian.md § The `__END__` Marker](../caspian/index.md#the-__end__-marker).
The current lexer has no handling for it (`grep __END__ lib/lua/caspian/lexer.lua`
on 2026-05-27 returned nothing).

Bree's hello-world fixture doesn't use `__END__`, so strictly the
walking-skeleton principle would defer this. But the change is small —
when the lexer starts a new line and sees `__END__` followed by a
newline or EOF (with optional trailing whitespace before the newline),
stop tokenizing and return the tokens collected so far. The two spec
rules from caspian.md:

- **Must be on its own line.** `foo __END__ bar` does not trigger. The
  check only fires at start-of-line (after handling whitespace).
- **Must not be inside a string literal or heredoc body.** The existing
  lexer reads heredoc and string bodies inline (see
  `read_heredoc` in `lexer.lua`), so by the time the start-of-line check
  fires, we're already outside any string context. Spec rule satisfied
  by placement, no extra logic required.

Bundling this into Bree saves every later slice from hitting the same
gap the first time a real `.casp` file uses the construct.

<a id="format-alignment-deferred"></a>
### Pre-spec format alignment is deferred

The wider transpiler still emits pre-spec CaspianJ for other AST node
types — `["scope", "setvar", name, value]` for assignment,
`[bwc, "&", {"args": [...]}]` for BWC dispatch, `["command", "if", ...]`
for if/elsif/else, etc. **Those are not Bree's problem.** Bree only
needs the hello-world AST shape to produce canonical CaspianJ, and
the transpiler already does that for the literal-method-call form.

The full pre-spec retrofit is incremental — later slices realign more
AST node types as later versions exercise them. Per
"don't generalize ahead of the test."

<a id="definition-of-done-bree"></a>
### Definition of done

~~~vibecode
{"vibecode": {"scope_status": "drafted_2026-05-16; updated_2026-05-27_to_add_parser_extension_and_end_marker_criteria",
"done_criteria":
{"parser_accepts_literal_method_call":
"parser_extended_to_accept_string_or_other_literal_as_method_receiver_so_hello_to_string_parses_without_workaround",
"lexer_recognizes_end_marker":
"lexer_extended_to_stop_tokenizing_at_a_bare_end_marker_line_per_caspian_md_spec",
"source_fixture_parses":
"tests_caspian_fixtures_hello_world_caspian_lexes_and_parses_without_error",
"transpiler_emits_canonical_caspj":
"transpiler_output_for_the_fixture_deep_equals_the_aslan_hand_written_fixture",
"executor_takes_tree_not_path":
"engine_run_refactored_to_accept_a_pre_parsed_caspianj_tree; file_reading_and_json_parsing_move_to_caller",
"returns_hello":
"compose_caspian_transpile_with_caspian_engine_run_on_the_fixture_returns_a_value_whose_payload_equals_hello"}}}
~~~

Bree is done when all six are true:

1. **The parser accepts literal-as-receiver for all literal kinds.**
   The fixture `'hello'.to_string` parses without the paren workaround.
   The parser's postfix-method-call rule accepts **all literal kinds**
   as receivers — string, integer, decimal, boolean, null, array, and
   hash literals — not just identifiers and parenthesized expressions.
   Bree only tests the string case, but the grammar rule covers
   everything for consistency.
2. **The lexer recognizes `__END__`.** A line containing only `__END__`
   (with optional trailing whitespace before the newline) terminates
   tokenization, per [caspian.md § The `__END__` Marker](../caspian/index.md#the-__end__-marker).
   Bree's fixture doesn't use `__END__`, but a dedicated unit test
   covers the construct so every later slice inherits a working lexer.
3. **The source fixture parses.** `'hello'.to_string` lexes and parses
   without error using the existing `caspian.lexer` and `caspian.parser`
   modules (with the extensions from criteria 1 and 2).
4. **The transpiler emits canonical CaspianJ.** Running the source through
   the transpiler produces a Lua table deep-equal to the Aslan
   hand-written `[[{"value": "hello"}, "to_string"]]` fixture.
5. **The host configures the engine via properties; `engine.run()` takes no args.**
   Aslan's `engine.run(path)` is refactored during Bree to a property-based API:
   the host stages the tree on `engine.caspianj` and any capabilities on
   sibling properties (`engine.std`, `engine.root`, etc.), then calls
   `engine.run()`. No positional args, no env, no harness hooks. Matches the
   Ruby host API model in [bootstrap.md](../../caspian/bootstrap.md). Bree
   itself injects no capabilities — the hello-world program just returns a
   value. Capability wiring arrives in later slices ([Corin](corin.md) for
   stdout/puts, etc.).

   The Caspian-source-to-tree pipeline lives on the engine module as
   **`engine.parse_caspian(source)`** — the canonical home. (`caspian.transpile`
   no longer exists; one obvious location, one obvious name.)

   Two clear pipeline paths converge on `engine.run()`:

   ```lua
   -- Running CaspianJ from a file:
   local f = assert(io.open(path, "r"))
   local source = f:read("*a")
   f:close()
   engine.caspianj = caspian.json.parse(source)
   local result    = engine.run()

   -- Running Caspian source from a file:
   local f = assert(io.open(path, "r"))
   local source = f:read("*a")
   f:close()
   engine.caspianj = engine.parse_caspian(source)
   local result    = engine.run()
   ```

   **Signature settled twice.** Initially Bree locked `engine.run(tree)` with
   one positional arg. On 2026-05-27 the signature was revisited and locked
   at zero positional args, with the tree staged via `engine.caspianj`
   — symmetric with how capabilities will be staged in Corin and beyond.
   `engine.parse_caspian` and `caspian.transpile` collapsed into one
   location at the same time.
6. **The harness receives `"hello"`.** Reading the fixture, calling
   `engine.parse_caspian` on it, staging on `engine.caspianj`, and calling
   `engine.run()` returns a value whose `.payload == "hello"`.

That's the entirety of Bree. Soft feature lock applies — same posture
as Aslan.


---

<a id="bree-phase-0-source-side-workbench"></a>
## Phase 0: source-side workbench

~~~vibecode
{"vibecode": {"phase": 0, "purpose":
"characterize_existing_lexer_parser_transpiler_state_against_bree_fixture; refactor_engine_run_from_path_to_tree",
"steps_count": 4, "acceptance":
"all_four_workbench_checks_pass_and_produce_a_concrete_gap_list_for_phase_1; engine_run_refactored_to_take_a_tree",
"tactic":
"exercise_existing_pipeline_with_bree_fixture_string; observe_each_layer_output",
"differs_from_aslan_phase_0":
"aslan_phase_0_verified_lua_environment_and_json_lua_existed; bree_phase_0_verifies_existing_caspian_source_pipeline_handles_the_fixture_input"}}
~~~

Bree's workbench is the existing Caspian source pipeline (lexer →
parser → transpiler). Before realigning the transpiler, Phase 0
characterizes what each layer produces today for the Bree fixture
string. The output is a concrete gap list driving Phase 1 step 2.

Phase 0 also performs one engine refactor — `engine.run` changes from
taking a path to taking a pre-parsed tree (Step 0.4) — to set up the
single-responsibility split that Phase 1 builds on.

<a id="step-01-confirm-the-lexer-tokenizes-the-fixture"></a>
### Step 0.1: Confirm the lexer tokenizes the fixture

~~~vibecode
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

~~~vibecode
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

~~~vibecode
{"vibecode": {"step": "0.3", "name": "transpiler_baseline",
"input": "'hello'.to_string",
"tool": "engine.parse_caspian (post-refactor; originally caspian.transpile)",
"expected":
"captures_actual_current_output; phase_0_probing_2026_05_27_found_it_already_canonical_for_this_ast",
"acceptance":
"parse_caspian_completes_without_error; output_recorded; current_shape_already_canonical_for_the_literal_method_call_ast_no_transpiler_changes_needed_for_bree"}}
~~~

`engine.parse_caspian("'hello'.to_string")` returns a Lua table. (At
the time of Phase-0 probing the function was named `caspian.transpile`;
it was renamed to `engine.parse_caspian` later on 2026-05-27.) Phase-0
probing found the output is **already canonical** for this AST —
`[[{"value": "hello"}, "to_string"]]`, exactly the Aslan hand-written
fixture. The transpiler still emits pre-spec shapes for other AST node
types (assignment, BWC, if/else, etc.), but for the specific
literal-method-call AST Bree exercises, pre-spec and canonical happen
to coincide. No transpiler changes are needed for Bree; Step 0.3 just
records the actual output for Step 3 verification.

<a id="step-04-refactor-enginerun-to-property-based-api"></a>
### Step 0.4: Refactor engine.run to a property-based API

~~~vibecode
{"vibecode": {"step": "0.4", "name": "engine_run_property_based",
"action":
"refactor_engine_run_from_taking_a_path_to_a_property_based_api; host_stages_tree_on_engine_caspianj_then_calls_engine_run_with_no_args",
"acceptance":
"end_to_end_still_returns_value_with_payload_hello_when_caller_stages_tree_on_engine_caspianj_and_calls_engine_run",
"note":
"first_pass_2026_05_27_morning_locked_engine_run_at_one_positional_arg_engine_run_tree; afternoon_revisit_moved_tree_to_engine_caspianj_property_and_locked_engine_run_at_zero_args; the_doc_below_reflects_the_final_state"}}
~~~

The Aslan engine took a path (`engine.run(path)`) — it read the file,
parsed JSON, then iterated. **Bree refactors this** to a property-based
API: the host stages the tree on `engine.caspianj`, then calls
`engine.run()` with no arguments. File reading and JSON parsing move
out of the executor entirely; capabilities (when they arrive in Corin)
land on sibling properties like `engine.std`.

After the refactor, the caller composes the pipeline:

```lua
local f = assert(io.open(path, "r"))
local source = f:read("*a")
f:close()
engine.caspianj = caspian.json.parse(source)
local result    = engine.run()
```

Aslan's tests are updated to use this composed form. The refactor
preserves behavior — same fixture, same return value — and sets up
the Caspian-source path to converge on the same `engine.run()` call
by substituting `engine.parse_caspian(source)` for
`caspian.json.parse(source)`.

<a id="bree-step-04-drinian-snapshot"></a>
#### Drinian snapshot during the hand-built-tree run

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
`to_string`, then popped on return. Step 0.4's job is to confirm
`engine.run()` walks this path when the tree is staged on
`engine.caspianj` instead of read from a file — the refactor doesn't
change what the hash
looks like, only how the tree got into the dispatcher.

Bree phase 0 test coverage lives under [Testing](#testing) below.

---

<a id="bree-phase-1-hello-world-from-caspian-source"></a>
## Phase 1: hello-world from Caspian source

~~~vibecode
{"vibecode": {"phase": 1, "fixture_path":
"tests/caspian/fixtures/hello_world.casp", "fixture_content":
"'hello'.to_string", "runner_path":
"tests/caspian/run.lua", "acceptance":
"fixture_parses_via_extended_parser_transpiles_to_canonical_caspj_and_engine_run_on_the_tree_returns_value_payload_hello",
"required_work":
["parser_extension_for_literal_as_receiver_all_literal_kinds",
"engine_run_refactored_to_take_a_tree_not_a_path",
"deep_equal_assert_helper"], "reuses_from_aslan":
["bootstrap", "materialize", "lookup_method", "transition", "dispatch"],
"out_of_scope":
["full_transpiler_retrofit_for_pre_spec_ast_node_types",
"interpreter_lua_removal",
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

~~~vibecode
{"vibecode": {"step": 1, "name": "inventory", "actions":
["catalog_existing_lexer_parser_transpiler_against_bree_fixture",
"document_ast_shape_for_method_call_on_string_literal",
"document_current_transpiler_output_for_that_ast"],
"output":
"concrete_record_of_ast_shape_and_transpiler_output_for_phase_1_step_3_verification",
"note":
"phase_0_probing_2026_05_27_already_established_that_transpiler_output_for_this_ast_is_canonical; no_diff_to_compute_and_no_transpiler_tests_need_updating_for_bree"}}
~~~

Read the existing `lexer.lua`, `parser.lua`, and `transpiler.lua` with
the Bree fixture in mind. Document:

- The exact AST node `kind` returned for `'hello'.to_string`.
- The exact Lua-table shape the current transpiler emits for that AST
  node.

Phase-0 probing on 2026-05-27 already established that the transpiler
output for this AST is canonical — there is no diff to compute and no
transpiler tests need updating for Bree. Step 1 just records the shape
for use in Step 3 verification.

<a id="bree-step-2-fill-the-gaps"></a>
### Step 2: Fill the gaps

~~~vibecode
{"vibecode": {"step": 2, "name": "fill_gaps", "scope":
"transpiler_path_for_hello_world_ast_only; not_full_realignment",
"work_items":
["parser_extension_for_literal_as_receiver_all_literal_kinds",
"lexer_extension_for_bare_end_marker_line",
"transpiler_path_verified_unchanged_for_hello_world_ast",
"engine_run_refactored_from_taking_a_path_to_taking_a_tree",
"aslan_tests_updated_to_compose_file_read_plus_json_parse_plus_engine_run",
"support_assert_deep_equal_helper_added"], "non_work":
["transpiler_realignment_for_other_pre_spec_ast_node_types",
"interpreter_lua_and_its_tests_left_untouched"]}}
~~~

For each gap from Step 1, add only what Bree needs:

- **Parser extension.** Allow literal expressions (string, integer,
  decimal, boolean, null, array, hash) as receivers in the
  postfix-method-call rule. The grammar change is small; Bree only
  tests the string case, but the rule covers all literals for
  consistency.
- **Lexer extension.** Add `__END__` recognition. At start-of-line,
  if the next characters are `__END__` followed by optional trailing
  whitespace and a newline or EOF, stop tokenizing and return the tokens
  collected so far. See the [Lexer extension](#lexer-end-marker) section
  for the full rule.
- **Transpiler.** No work needed for Bree's specific fixture — the
  existing transpiler already emits canonical CaspianJ for the
  literal-method-call AST shape (verified via `('hello').to_string`
  during Phase-0 probing). Other AST node types stay pre-canonical;
  later slices realign them as needed.
- **Engine refactor.** `engine.run` changes from taking a path to
  taking a pre-parsed tree. Aslan's tests get a small update to
  do the file-read + json.parse separately and pass the tree to
  `engine.run`. **The Drinian hash is unchanged by this refactor** —
  same dispatch loop, same transitions, just the tree arrives via
  the caller composing the pipeline rather than the executor doing
  it all.
- **Assertion helper.** Add `assert.deep_equal(got, expected, msg)` to
  `tests/caspian/support/assert.lua`. Signature: three arguments, `msg`
  optional. Compares Lua tables structurally (recursively, with primitive
  equality at leaves). On mismatch, raises an error whose message names
  the first divergent path in the form:

  ```
  mismatch at [1][2]: expected "to_string", got "tostring"
  ```

  Path segments are `[k]` for any key (numeric or string, with strings
  quoted: `["foo"]`). When `msg` is provided, it prefixes the mismatch
  line: `<msg>: mismatch at [1][2]: expected ..., got ...`. Needed by
  TB.2 and useful for every later slice that compares trees.

Anything beyond this — realigning the bwc path, the assignment path,
the if path, etc. — is later work. The principle: realign as later
slices exercise each AST node, not all at once.

<a id="bree-step-3-verify"></a>
### Step 3: Verify

~~~vibecode
{"vibecode": {"step": 3, "name": "verify", "actions":
["create_caspian_source_fixture",
"compose_file_read_plus_caspian_transpile_plus_engine_run",
"compare_returned_value_payload_to_hello",
"compare_transpiled_tree_to_aslan_hand_written_canonical_fixture"],
"pass_condition":
"return_value_payload_equals_hello_and_transpiled_tree_deep_equals_aslan_fixture_tree",
"fail_condition":
"any_deviation; failure_message_names_which_layer_blocked"}}
~~~

Create `tests/caspian/fixtures/hello_world.casp` containing
`'hello'.to_string`. Read it, parse it, stage it, run:

```lua
local f = assert(io.open("tests/caspian/fixtures/hello_world.casp", "r"))
local source = f:read("*a")
f:close()
engine.caspianj = engine.parse_caspian(source)
local result    = engine.run()
```

Verify two things:

1. The returned value has `payload == "hello"`.
2. The transpiled tree (`tree` above) deep-equals the Aslan
   hand-written `[[{"value": "hello"}, "to_string"]]` tree — the
   round-trip equivalence check that proves canonical alignment.

If either fails, the message must identify which layer blocked: parse
error, transpiler shape mismatch, dispatch failure, engine context
problem. Loop back to Step 2 for that layer.

When Bree passes, the next slice from the roadmap is selected and
planned in the same shape.

<a id="bree-step-3-drinian-snapshots"></a>
#### Drinian snapshots during the run

Bree runs the same semantic program as Aslan (just from source
instead of hand-written CaspianJ), so the
[Drinian state hash](aslan.md#data-structures-lua-tables) goes
through the same three moments — bootstrap → mid-`to_string` →
return — and contains the same two fields. The transpiler step
happens **before** dispatch and leaves no Drinian footprint;
intermediate AST nodes and the produced canonical tree live in Lua
locals, not in `engine.state`.

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

**Mid-dispatch, inside the `to_string` method call:**

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
      "action": "method_call",
      "role": "stdlib",
      "receiver_type": "string",
      "method": "to_string",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

**After `to_string` returns:**

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

Bree doesn't grow the Drinian hash — the new source-side machinery
(lexer, parser, transpiler, plus the `engine.run()` property-based
refactor) all operates on working state outside the hash. The state hash next
changes shape in [Corin](corin.md), when the `stdout` role
joins the registry and shows up as the `role` on a pushed frame
during `puts` dispatch.

Bree phase 1 test coverage lives under [Testing](#testing) below.

<a id="bree-open-questions"></a>
### Open questions

~~~vibecode
{"vibecode": {"open_questions":
["whether_legacy_caspian_run_in_init_lua_should_be_renamed_or_deprecated_in_bree_or_later"]}}
~~~

- **Legacy `M.run(source, env)` in `init.lua`.** Currently goes through
  the pre-canonical pipeline + `interpreter.lua`. Out of scope for Bree
  — flagged for renaming or deprecation in a later slice once the
  transpiler is more broadly realigned.

---

<a id="testing"></a>
## Testing

~~~vibecode
{"vibecode": {"section": "testing",
"test_directory": "tests/caspian/bree/",
"fixture_path": "tests/caspian/fixtures/hello_world.casp",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TB.0.1", "TB.0.2", "TB.0.3", "TB.0.4"],
"phase_1_tests": ["TB.1", "TB.2", "TB.3", "TB.4", "TB.5", "TB.6", "TB.7"],
"load_bearing_tests":
["TB.1_transpiler_canonical_match", "TB.5_t2_6_regression_checks"]}}
~~~

Bree has eleven tests total: four Phase 0 source-pipeline
characterization tests plus seven Phase 1 unit + integration + regression
tests. TB.2 (transpiler emits canonical for the fixture, deep-equal to
the Aslan hand-written tree) is the load-bearing correctness check;
TB.5 and TB.6 are the load-bearing regression checks proving Bree's
work didn't break the Aslan CaspianJ path or pre-canonical AST nodes
left alone. TB.7 covers the `__END__` lexer extension.

<a id="bree-phase-0-test-plan"></a>
### Phase 0 test plan

~~~vibecode
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
"engine_run_returns_value_for_hand_built_canonical_tree_after_refactor",
"tool": "tests/caspian/bree/test_engine_run_tree.lua",
"level": "unit"}]}}
~~~

| ID | Level | Verifies | Tool |
|---|---|---|---|
| TB.0.1 | unit | Lexer handles the fixture string | `test_lexer_check.lua` |
| TB.0.2 | unit | Parser returns an AST for the fixture | `test_parser_check.lua` |
| TB.0.3 | unit | Transpiler completes for the fixture; baseline captured | `test_transpiler_baseline.lua` |
| TB.0.4 | unit | `engine.run()` returns expected value for a hand-built tree staged on `engine.caspianj` | `test_engine_run_tree.lua` |

All four must pass (or the underlying issues must be resolved) before
Bree phase 1 begins.

<a id="bree-phase-1-test-plan"></a>
### Phase 1 test plan

~~~vibecode
{"vibecode": {"phase_1_tests":
[{"id": "TB.1", "verifies":
"parser_accepts_literal_as_receiver; hello_to_string_parses_natively",
"level": "unit"}, {"id": "TB.2", "verifies":
"transpiler_emits_canonical_caspj_for_bree_fixture_deep_equal_to_aslan_hand_written_tree",
"level": "unit"}, {"id": "TB.3", "verifies":
"engine_run_returns_payload_hello_for_aslan_canonical_tree_post_refactor",
"level": "unit"}, {"id": "TB.4", "verifies":
"compose_transpile_plus_engine_run_returns_payload_hello_for_bree_caspian_fixture_file",
"level": "integration_end_to_end"}, {"id": "TB.5", "verifies":
"top_frame_on_call_stack_has_role_user_after_bree_pipeline_returns",
"level": "unit_observability_check"}, {"id": "TB.6", "verifies":
"aslan_test_files_edited_to_compose_file_read_plus_json_parse_plus_engine_run_with_tree; all_updated_aslan_tests_pass",
"level": "regression_check"},
{"id": "TB.7", "verifies":
"lexer_stops_tokenizing_at_bare_end_marker_line; tokens_after_end_marker_are_not_emitted",
"level": "unit"}]}}
~~~

Seven tests for Bree phase 1. Each lives under `tests/caspian/bree/`
using the same framework (`support.runner` + `support.assert`).

| ID | Level | Verifies | How |
|---|---|---|---|
| TB.1 | unit | Parser accepts literal-as-receiver | `caspian.parse("'hello'.to_string")` returns an AST without raising |
| TB.2 | unit | Transpiler emits canonical for the fixture | `assert.deep_equal(engine.parse_caspian("'hello'.to_string"), {{ {value="hello"}, "to_string" }})` |
| TB.3 | unit | `engine.run()` returns payload `"hello"` | Hand-build the canonical tree in Lua, stage on `engine.caspianj`, call `engine.run()`, assert on result |
| TB.4 | integration | Compose source → parse → stage → run | Read fixture, `engine.parse_caspian`, stage on `engine.caspianj`, `engine.run()`, assert `.payload == "hello"` |
| TB.5 | unit | Top frame on `call_stack` has `role == "user"` after Bree pipeline returns | Mirror of Aslan TA.7's second assertion |
| TB.6 | regression | Aslan test files **edited** to stage `engine.caspianj` from `json.parse` output and call `engine.run()`; all updated Aslan tests pass | Edit each Aslan TA.* test that currently calls `engine.run(path)` to compose `io.open` + `json.parse`, stage on `engine.caspianj`, then call `engine.run()`; rerun the Aslan suite and confirm green |
| TB.7 | unit | Lexer stops tokenizing at a bare `__END__` line | Tokenize `"$foo = 'hello'\n__END__\nignored garbage that would otherwise lex-error\n"` and assert the token stream ends cleanly after the assignment (no error, no tokens from the post-`__END__` text) |

All seven pass = Bree done.

<a id="bree-test-layout"></a>
### Test layout

~~~vibecode
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
| `tests/caspian/fixtures/hello_world.casp` | Caspian source fixture (sibling of `hello_world.caspj`). File ends with a trailing newline — source string is `"'hello'.to_string\n"`. The lexer must handle the trailing newline cleanly (no spurious tokens, no error) since real-world `.casp` files will always have one. |
| `tests/caspian/bree/` | Phase 0 and Phase 1 unit + integration tests |
| `tests/caspian/run.lua` | Extended to require Bree test modules |
| `tests/caspian/support/assert.lua` | Gains a `deep_equal` helper |
| `tests/caspian/transpiler/test_*.lua` | Updated only for AST nodes realigned in Bree |
