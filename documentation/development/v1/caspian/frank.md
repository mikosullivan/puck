# Frank

~~~json
{"vibecode": {"slice": "frank_caspian_cli", "codename":
"Frank", "delivers": "caspian_command_line_launcher",
"position_in_roadmap":
"after_edmund_caspian_with_json_serialization; before_glenstorm_bryton",
"goal":
"introduce_caspian_as_os_level_command_for_running_caspian_files_with_explicit_permission_model",
"hard_prerequisite_for": "glenstorm_bryton",
"permission_posture":
"default_restrictive; opt_in_via_flags_deno_shape",
"aligns_with":
["feedback_no_dangerous_defaults", "roles_md_role_based_security"]}}
~~~

Hard prerequisite for [Glenstorm](glenstorm.md) (Bryton) — Bryton
subprocess-invokes test files (per the
[Bryton spec](../../caspian/packages/bryton/index.md#tests-are-runnable-scripts), every
test file is "an ordinary executable"). This slice introduces
`caspian` as an OS-level command and pins down the permission model
for Caspian code launched at the CLI.

<a id="what-the-slice-introduces"></a>
### What the slice introduces

~~~json
{"vibecode": {"introduces": ["caspian_command_line_launcher",
"shebang_support", "argument_passing_into_caspian",
"stderr_sink_and_role",
"routing_convention_engine_errors_to_stderr_program_output_to_stdout",
"exit_codes_zero_on_clean_completion_nonzero_on_alarm_or_uncaught",
"permission_flag_machinery"],
"note_on_stdout":
"stdout_sink_and_puts_bwc_already_shipped_in_corin_caspian_with_stdout; frank_cli_adds_stderr_as_a_peer_sink_plus_the_routing_convention",
"launcher_responsibilities":
["take_a_caspian_file_path_as_first_argument",
"set_up_engine_with_minimum_roles",
"wire_up_faucets_for_any_granted_flags",
"invoke_engine_run_on_the_file",
"emit_program_output_to_stdout_and_stderr_appropriately",
"exit_with_appropriate_code"]}}
~~~

- A `caspian` command-line launcher — a small script taking a
  `.casp` file path as its first argument, invoking the engine,
  exiting with an appropriate code.
- Shebang support — `.casp` files starting with
  `#!/usr/bin/env caspian` are directly runnable via `chmod +x` and
  `./file.casp`.
- Argument passing from OS argv into the running Caspian program
  (surfaced via `%argv`; exact shape settled in this slice).
- **stderr sink** — engine-introduced peer of the stdout sink that
  shipped in Corin. Has its own role (`stderr`); writes go to the
  process's `io.stderr` by default; test injection via
  `env.stderr` mirrors `env.stdout`.
- **Routing convention** — engine errors and diagnostics go to
  stderr; the program's intentional output goes to stdout. This is
  the first slice that needs the distinction (Corin only had stdout,
  Digory/Edmund had no engine-error-vs-program-output ambiguity).
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

Following the role-based security model in [roles.md](../../caspian/roles.md) and the
no-dangerous-defaults discipline, the CLI uses a **default-restrictive**
posture: a `.casp` program invoked via the CLI gets only the minimum
roles and faucets, with everything else opt-in via flags. This mirrors
Deno's local-script model.

<a id="always-on-every-cli-invocation"></a>
#### Always on (every CLI invocation)

| Capability | Role | Why default |
|---|---|---|
| Program execution context | `user` | The program has to run as something |
| Clock | `clock` | Per [roles.md](../../caspian/roles.md) engine minimum |
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
| `--allow-fs=PATH` ⟳ | Read-write directory jail rooted at PATH (no locks) | per-directory jail role |
| `--allow-fs-read=PATH` ⟳ | Read-only directory jail rooted at PATH | per-directory jail role |
| `--allow-fs-lock=PATH` ⟳ | Read-write directory jail rooted at PATH, **including file-lock capability** | per-directory jail role |
| `--allow-net=HOST[:PORT]` ⟳ | Network faucet to specific host | per-faucet role |
| `--allow-net` | Network faucet to any host | broad `net` role |
| `--allow-env[=NAMES]` | Env-vars faucet, optionally narrowed | `env_vars` role |
| `--allow-puck` | Puck object access | `puck` role |
| `--allow-all` (or `-A`) | Everything above | convenience for trusted local scripts |

File locking is split from the basic read-write grant because it's a
distinct attack surface — see
[filesystem.md § Permissions](../../caspian/built-in-classes/filesystem.md#permissions).
A program that needs to read and write files almost never needs locks;
forcing the user to opt in separately means "I need to coordinate access
across processes" is a deliberate choice.

`--allow-all` is the escape hatch for "this is my own script and I
trust myself." Without it, Caspian at the CLI runs sandboxed by
default — the developer has to think about what the program needs.

<a id="examples"></a>
#### Examples

```bash
./hello.casp
# Stdin/out/err/argv + engine minimums only; nothing else

caspian --allow-fs=. ./read_file.casp
# Adds read-write directory jail rooted at current directory

caspian --allow-fs-read=. --allow-net=api.example.com:443 ./fetch.casp
# Read-only filesystem + single-host network

caspian --allow-all ./my_local_tool.casp
# Everything; for trusted local scripts
```

<a id="installation"></a>
### Installation

~~~json
{"vibecode": {"installation_model":
"project_local_bin_plus_path; no_system_install",
"launcher_path_in_repo": "bin/caspian",
"user_action_once":
"add_project_bin_directory_to_path_in_shell_rc",
"launcher_is_self_locating":
"launcher_computes_its_own_absolute_path_and_derives_repo_root_from_that_then_resolves_engine_relative_to_repo_root",
"no_root_required": true, "multiple_checkouts_coexist":
"each_repo_has_its_own_bin; path_order_picks_the_winner",
"easy_backout":
"remove_path_line_from_rc_file; nothing_else_to_clean_up",
"system_install_status": "v1_plus_deployment_concern; not_frank_work"}}
~~~

The `caspian` launcher lives at `bin/caspian` inside the repo. There
is **no system-level install** in Frank — root access is not required,
and `/usr/local/bin/` (or equivalent) is not touched.

To make `caspian` available as a command, the user adds the project's
`bin/` directory to their `$PATH` once, in their shell's rc file:

```bash
# In ~/.bashrc or ~/.zshrc
export PATH="/path/to/puck/working/bin:$PATH"   # replace with your local checkout path
```

After re-sourcing the rc file (or starting a new shell),
`caspian ./foo.casp` works from any directory.

**The launcher is self-locating.** When invoked, `bin/caspian`
computes its own absolute path, derives the repo root from that, and
resolves the engine at `<repo_root>/lib/lua/`. This works
regardless of the user's current directory when running `caspian`.

One candidate shape (bash form):

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
exec lua \
    -e "package.path='$REPO_ROOT/lib/lua/?.lua;'..package.path" \
    "$REPO_ROOT/lib/lua/caspian/cli.lua" "$@"
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

System-level install (`/usr/local/bin/caspian`, distribution packages,
homebrew formula, etc.) is a V1+ deployment concern, not Frank work.

<a id="bryton-interaction"></a>
### Bryton interaction

~~~json
{"vibecode": {"bryton_invocation": "caspian_dash_dash_allow_all_per_test",
"rationale": "test_files_typically_need_broad_access; per_test_narrowing_is_later_bryton_feature_out_of_scope_for_glenstorm"}}
~~~

Bryton subprocess-invokes test files using `caspian --allow-all` by
default. Test files typically need broad access (filesystem to read
fixtures, network to hit a service-under-test, etc.). Per-test
permission narrowing is a later Bryton feature (configurable via a
future `bryton.json` setting; out of scope for Glenstorm).

<a id="open-questions"></a>
### Open questions

~~~json
{"vibecode": {"open_questions_frank_cli":
["exact_flag_syntax_long_only_vs_short_forms_equals_vs_separate_args",
"default_for_puck_role_off_seems_right_but_puck_is_central",
"determinism_flag_for_clock_and_randomizer_seed_for_test_reproducibility_v2_plus",
"cross_platform_shebang_behavior_linux_macos_wsl",
"whether_engine_reading_the_dot_caspian_source_file_itself_should_require_a_permission_flag_or_be_pre_permission_engine_plumbing"]}}
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
- **Engine reading the `.casp` source file itself.** Current
  proposal: pre-permission engine plumbing (the engine has to read the
  script to run anything). If this becomes contentious, an explicit
  `--source=PATH` form could surface it.

---

<a id="skeletor-impact"></a>
## Skeletor impact

**Frank is the first slice where the
[Skeletor state hash](aslan.md#data-structures-lua-tables) grows
beyond the single `call_stack` field.** The CLI launcher hands `argv`
into the program as durable, program-wide state — visible across
every frame for the program's lifetime — which means it belongs as
a top-level Skeletor field, not in any single frame's locals. From
Frank onward, every snapshot has at least one more top-level field
than the Aslan–Edmund shape.

What Frank adds to `engine.state`, and what it leaves outside:

| New piece | In the Skeletor hash? | Why |
|---|---|---|
| `argv` (program's view of CLI args) | **Yes** — `engine.state.argv` | Durable program state; reachable from Caspian as `%argv` for the program's lifetime |
| Granted permission set (which `--allow-*` flags were given) | Open question, see below | Either bootstrap metadata or execution state — same observable behavior in Frank, matters post-V1.0 snapshot/revive |
| `stderr` sink function | No — `env.stderr` (host-supplied) | Same rationale as `stdout` in Corin — sinks are engine-supplied infrastructure |
| `stderr` role object | No — `engine.roles.stderr` | Bootstrap-time engine metadata, like every other role |
| Exit code | No — returned from `engine.run` to the launcher | Caspian programs don't see their own exit code; host-side concern |

<a id="skeletor-impact-snapshots"></a>
### Snapshots during a CLI run

Invocation: `caspian fixtures/echo_argv.casp foo bar baz`.

**Just after the launcher invokes the engine, before the first
statement dispatches:**

```json
{
  "argv":       ["foo", "bar", "baz"],
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

**Mid-dispatch, during a hypothetical `eprint` BWC that writes to
stderr (cross-role transition into the new `stderr` role):**

```json
{
  "argv":       ["foo", "bar", "baz"],
  "call_stack": [
    {
      "action":   "top_level",
      "role":   "user",
      "chain":  {"log": {}, "misc": {}},
      "locals": {}
    },
    {
      "action":   "bwc_call",
      "role":   "stderr",
      "bwc":    "eprint",
      "chain":  {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

**After the BWC returns:**

```json
{
  "argv":       ["foo", "bar", "baz"],
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

`argv` is a top-level Skeletor field — program-wide state, the same
across every frame. The frame stack pushes/pops as transitions
happen; `argv` doesn't move. Each frame carries its own `role` and
`chain` (per [skeletor.md](../../caspian/skeletor/index.md) — chain wipes at
boundaries by virtue of each frame having its own fresh chain).

<a id="skeletor-impact-open-permissions"></a>
### Open question: where does the granted permission set live?

The set of `--allow-*` flags the program was launched with has to be
recorded somewhere — the runtime needs to consult it on every
attempted privileged operation. Two interpretations:

- **In the hash** (`engine.state.permissions` or similar): treat it
  as program-visible state, durable across the program's lifetime.
  Future Caspian code could in principle introspect (`%engine.permissions`?)
  what it was granted.
- **Outside the hash** (engine-module-level): treat it as bootstrap
  metadata, immutable, parallel to `engine.roles` and `engine.classes`
  (already settled as outside the hash).

The two interpretations have **identical observable behavior in
[Frank](frank.md)**. The question becomes load-bearing only when
snapshot/revive lands post-V1.0: should a revived snapshot retain the permission
grants from the original invocation, or pick them up from the
reviving host's environment? Defer the call until snapshot/revive is
on the table.

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing", "test_directory":
"tests/caspian_cli/", "fixture_directory":
"tests/caspian_cli/fixtures/",
"framework":
"support_runner_and_assert; tests_invoke_caspian_via_io_popen_and_capture_stdout_stderr_exit_code",
"phase_0_tests": ["TF.0.1", "TF.0.2"],
"phase_1_tests": ["TF.1", "TF.2", "TF.3", "TF.4", "TF.5", "TF.6"],
"phase_2_tests": ["TF.7", "TF.8", "TF.9", "TF.10",
"TF.11", "TF.12", "TF.13", "TF.14"],
"load_bearing_tests":
["TF.7_through_TF.10_default_denial_proves_restrictive_posture",
"TF.5_stderr_routing_proves_diagnostic_vs_program_output_split"]}}
~~~

Tests for Frank sit under `tests/caspian_cli/`. Each test
subprocess-invokes `bin/caspian` via `io.popen` (or equivalent) and
asserts on captured stdout, stderr, and exit code. The load-bearing
assertions are TF.7–TF.10 (default denial proves the restrictive
posture actually denies) and TF.5 (stderr routing proves the
engine-error vs program-output split actually happens).

<a id="frank-phase-0-launcher-mechanics"></a>
### Phase 0: launcher mechanics

| ID | Level | Verifies |
|---|---|---|
| TF.0.1 | unit | `bin/caspian` is executable, self-locates its own directory, and derives the repo root correctly regardless of the caller's working directory |
| TF.0.2 | unit | `bin/caspian` resolves the engine via `package.path` and exits cleanly when handed a trivial fixture that prints to stdout |

<a id="frank-phase-1-cli-essentials"></a>
### Phase 1: CLI essentials

| ID | Level | Verifies | How |
|---|---|---|---|
| TF.1 | integration | Successful run exits 0 | `caspian fixtures/exit_zero.casp` → exit 0 |
| TF.2 | integration | Uncaught alarm/exception exits non-zero | `caspian fixtures/raise.casp` → non-zero exit; message on stderr |
| TF.3 | integration | Shebang execution | `chmod +x fixtures/hello_shebang.casp; ./fixtures/hello_shebang.casp` runs and exits 0 (shebang line is `#!/usr/bin/env caspian`) |
| TF.4 | integration | argv passing | `caspian fixtures/echo_argv.casp foo bar baz` → stdout contains `foo`, `bar`, `baz` in order |
| TF.5 | integration | stderr routing | `caspian fixtures/mixed_io.casp` (writes via `puts` AND raises) → program's `puts` output on stdout, engine error on stderr; streams do not interleave |
| TF.6 | integration | Defaults present without any flags | `caspian fixtures/exercise_defaults.casp` (uses clock, randomizer, `%utils`, stdin, stdout, stderr, argv) runs and exits 0 |

<a id="frank-phase-2-permission-flag-matrix"></a>
### Phase 2: permission flag matrix

| ID | Level | Verifies | How |
|---|---|---|---|
| TF.7 | integration | Default denial — filesystem | `caspian fixtures/read_file.casp` (no flags) → non-zero exit, permission-denied diagnostic on stderr |
| TF.8 | integration | Default denial — network | `caspian fixtures/http_get.casp` (no flags) → non-zero exit, network-denied diagnostic |
| TF.9 | integration | Default denial — env vars | `caspian fixtures/read_env.casp` (no flags) → non-zero exit |
| TF.10 | integration | Default denial — puck | `caspian fixtures/puck_get.casp` (no flags) → non-zero exit |
| TF.11 | integration | `--allow-fs=PATH` | `caspian --allow-fs=./allowed fixtures/read_file.casp` reads files under `./allowed`; same fixture against `./forbidden` still denied |
| TF.12 | integration | `--allow-fs-read=PATH` is read-only | `--allow-fs-read=./allowed` permits reads, denies writes |
| TF.13 | integration | `--allow-net=HOST` is host-scoped | `--allow-net=api.example.com:443` permits that host; other hosts still denied |
| TF.14 | integration | `--allow-all` opens everything | `caspian --allow-all fixtures/full_exercise.casp` (touches fs, net, env, puck) exits 0 |

<a id="frank-test-layout"></a>
### Test layout

| Path | Contents |
|---|---|
| `tests/caspian_cli/fixtures/` | Tiny `.casp` programs each exercising one capability (read_file, http_get, read_env, puck_get, raise, echo_argv, mixed_io, exercise_defaults, full_exercise) |
| `tests/caspian_cli/` | The `support/runner`-based Lua tests that subprocess-invoke `bin/caspian` and assert on stdout / stderr / exit code |
| `tests/caspian/run.lua` | Extended to require the Frank test modules |
