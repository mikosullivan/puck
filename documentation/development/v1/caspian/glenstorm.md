# Glenstorm

~~~json
{"vibecode": {"codename": "Glenstorm", "delivers": "bryton", "goal":
"first_usable_bryton_runner_executes_a_directory_of_test_files_and_aggregates_xeme_results",
"directive": "keep_very_light_per_user_instruction_2026-05-15",
"includes": ["runner_walks_directory_recursively_any_order",
"runs_every_file_as_subprocess",
"captures_stdout_parses_as_xeme_json",
"aggregates_flat_pass_fail_count",
"prints_summary_and_failure_list"], "explicitly_excludes_at_glenstorm":
["bryton_json_per_directory_config", "ordering_control",
"explicit_skipping", "per_language_helper_libraries",
"fail_fast", "tree_shaped_result_aggregation", "concurrency_control"],
"language_of_runner_glenstorm":
"lua_for_simplicity; caspian_hosted_runner_is_a_later_slice",
"distinct_from":
"lua_side_engine_tests_which_continue_to_use_tests_caspian_support_runner",
"spec_links":
["documentation/caspian/packages/bryton/index.md",
"documentation/caspian/packages/bryton/runner.md"]}}
~~~

Glenstorm is the first usable **Bryton** — see
[bryton.md](../../caspian/packages/bryton/index.md) and
[bryton/runner.md](../../caspian/packages/bryton/runner.md) for the full spec. Per the
direction to keep it very light at this stage, the Glenstorm runner does
only what's strictly needed: walk a directory, run each file as a
subprocess, parse each Xeme, aggregate, report.

**Glenstorm Bryton includes:**

- Runner walks a directory recursively. Order is undefined.
- Runs every file it finds as a subprocess.
- Captures each subprocess's stdout, parses it as Xeme JSON.
- Aggregates a flat pass/fail count across all tests.
- Prints a summary (`N passed, M failed`) plus a list of failures.

**Explicitly excluded from Glenstorm** (deferred to later Bryton slices):

- `bryton.json` per-directory config (no ordering, no skipping)
- Per-language helper libraries (no Caspian-side assertion helpers)
- Fail-fast
- Tree-shaped result aggregation (flat tally only)
- Concurrency control (sequential execution only)
- The runner being itself a Caspian program — Glenstorm runner is
  implemented in Lua for simplicity. A Caspian-hosted Bryton runner
  is a later slice (the language has to mature far enough to expose
  filesystem and subprocess capabilities).

**Distinct from Lua-side engine tests.** The existing
`tests/caspian/support/runner.lua` continues to test the engine
internals; that's fixed at Aslan. Bryton is for testing **Caspian
code with Caspian code** (or, in Glenstorm, with any script that emits
Xeme), layered on top of the engine.

<a id="glenstorm-prerequisites"></a>
### Prerequisites

~~~json
{"vibecode": {"glenstorm_prerequisites":
["aslan_engine_can_run_ksj_end_to_end",
"bree_caspian_text_parser_and_transpiler_so_test_files_can_be_caspian_source",
"digory_hash_class_so_caspian_tests_can_construct_xemes",
"corin_stdout_writing_so_caspian_tests_can_emit_xemes",
"edmund_json_serialization_method_on_hashes_so_tests_can_emit_their_xemes",
"lua_host_subprocess_invocation_io_popen",
"lua_host_directory_walk_find_via_io_popen_or_lfs"]}}
~~~

Several slices have to land before Glenstorm can ship:

| Prerequisite | Provided by |
|---|---|
| Engine can run CaspianJ end-to-end | Aslan |
| Caspian text → CaspianJ transpiler | Bree |
| Hash class | a Frank slice |
| `%stdout.write` (sys references + stdout sink) | a Frank slice |
| JSON serialization (hash → JSON string method) | a Frank slice |
| Caspian CLI executable (`caspian` command, shebang support, permission flags) | [Frank CLI slice](frank.md) |
| Lua-host subprocess invocation | runner host; native `io.popen` |
| Lua-host directory walk | runner host; `io.popen("find ...")` or `lfs` |

The Frank slices that fill these gaps are unscoped in this plan until
each is the next active slice. The current direction is to attempt
them in roughly the order shown; each unblocks the next.

<a id="glenstorm-phase-plan"></a>
### Phase plan

Three phases, same three-step shape as Aslan:

<a id="phase-0-lua-host-workbench-for-bryton"></a>
#### Phase 0: Lua-host workbench for Bryton

~~~json
{"vibecode": {"glenstorm_phase_0_purpose":
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
{"vibecode": {"glenstorm_phase_1_steps":
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

End-to-end acceptance: assemble fixtures that emit Xeme JSON, point
Bryton at the directory, assert the aggregated summary matches.
Detailed test plan lives under [Testing](#testing) below (TGl.2.1–TGl.2.3).

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing",
"phase_0_test_directory": "tests/bryton/glenstorm/sanity/",
"phase_1_test_directory": "tests/bryton/glenstorm/unit/",
"phase_2_test_directory": "tests/bryton/glenstorm/",
"fixture_directory": "tests/bryton/glenstorm/fixtures/",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TGl.0.1", "TGl.0.2", "TGl.0.3"],
"phase_1_tests": ["TGl.1.1", "TGl.1.2", "TGl.1.3", "TGl.1.4", "TGl.1.5", "TGl.1.6"],
"phase_2_tests": ["TGl.2.1", "TGl.2.2", "TGl.2.3"],
"load_bearing_test":
"TGl.2.3_mixed_directory_proves_aggregation_and_failure_reporting_in_one_test"}}
~~~

Glenstorm Bryton has twelve tests total: three Phase 0 Lua-host sanity
checks, six Phase 1 runner unit tests (one per implementation step),
and three Phase 2 end-to-end acceptance tests. TGl.2.3 (mixed pass/fail
directory) is the load-bearing acceptance — it's the smallest test that
exercises aggregation AND failure-listing AND mixed-result handling
simultaneously.

<a id="glenstorm-phase-0-test-plan"></a>
### Phase 0 test plan

| ID | Level | Verifies | How |
|---|---|---|---|
| TGl.0.1 | unit | `io.popen` runs a command and captures stdout | `io.popen("echo hello"):read("*a") == "hello\n"` |
| TGl.0.2 | unit | `io.popen` captures exit code | `io.popen("true"):close()` reports success; `io.popen("false"):close()` reports fail |
| TGl.0.3 | unit | Directory walking | `walk("tests/bryton/glenstorm/fixtures/")` returns the expected file list (mechanism chosen between shell-out-to-`find` or `lfs`) |

All three must pass before Phase 1 begins.

<a id="glenstorm-phase-1-test-plan"></a>
### Phase 1 test plan

Six unit tests, one per implementation step from the
[Phase 1 phase plan](#phase-1-runner-implementation). Each step's
function is independently callable so the test targets just that
step's behavior.

| ID | Level | Verifies | How |
|---|---|---|---|
| TGl.1.1 | unit | walk + collect | `walk(dir)` returns the full list of test files under `dir` |
| TGl.1.2 | unit | run one file as subprocess | `run_one(path)` returns `{stdout = "...", exit_code = 0}` for a known fixture |
| TGl.1.3 | unit | parse Xeme JSON | `parse_xeme('{"success": true}')` returns `{success = true}`; errors on malformed JSON |
| TGl.1.4 | unit | aggregate pass/fail | `aggregate({{success=true}, {success=false, message="X"}})` returns `{passed=1, failed=1, failures={"X"}}` |
| TGl.1.5 | unit | print summary | `print_summary({passed=2, failed=1, failures={"X"}})` emits a recognizable human-readable summary |
| TGl.1.6 | unit | bryton.lua entry point | Invoking the `bryton` entry with a directory arg wires steps 1–5; exits 0 on all-pass, 1 on any-fail |

<a id="glenstorm-phase-2-test-plan"></a>
### Phase 2 acceptance test plan

~~~json
{"vibecode": {"glenstorm_phase_2_tests":
[{"id": "TGl.2.1", "verifies": "trivial_pass_case"},
{"id": "TGl.2.2", "verifies": "trivial_fail_case_message_surfaces"},
{"id": "TGl.2.3", "verifies":
"mixed_directory_correct_aggregate_and_failures_listed"}]}}
~~~

| ID | Verifies | Setup |
|---|---|---|
| TGl.2.1 | Trivial pass case | A test file emits `{"success": true}`; Bryton reports 1 passed |
| TGl.2.2 | Trivial fail case | A test file emits `{"success": false, "message": "X"}`; Bryton reports 1 failed with `X` in the failure list |
| TGl.2.3 | Mixed directory | A directory with 2 passing + 1 failing test files; Bryton reports 2 passed, 1 failed, the failing test's message in the summary |

The test fixtures themselves can be in any language that emits Xeme
JSON to stdout (shell scripts, Lua scripts, or — once the
prerequisites land — Caspian files). For Glenstorm acceptance, the
simplest path is shell scripts that `echo` the Xeme JSON — this
lets us verify the runner works without depending on the Caspian
prerequisites being complete.

When all three pass, Glenstorm Bryton ships.

<a id="glenstorm-test-layout"></a>
### Test layout

~~~json
{"vibecode": {"glenstorm_test_layout":
{"runner_implementation_under":
"code/bryton/lua/bryton/",
"glenstorm_acceptance_fixtures_under":
"tests/bryton/glenstorm/fixtures/",
"glenstorm_acceptance_tests_under":
"tests/bryton/glenstorm/"}}}
~~~

| Path | Contents |
|---|---|
| `code/bryton/lua/bryton/` | The Lua-host Bryton runner implementation |
| `tests/bryton/glenstorm/sanity/` | Phase 0 Lua-host sanity tests (TGl.0.x) |
| `tests/bryton/glenstorm/unit/` | Phase 1 runner step unit tests (TGl.x) |
| `tests/bryton/glenstorm/fixtures/` | Test scripts emitting Xeme JSON (pass + fail cases) |
| `tests/bryton/glenstorm/` | Glenstorm acceptance tests (TB.x) using `support/runner` + `support/assert` |
