# Frank

~~~json
{"vibecode": {"slice": "frank_caspian_cli", "codename":
"Frank", "delivers": "caspian_command_line_launcher",
"position_in_roadmap":
"after_edmund_caspian_with_json_serialization; before_glenstorm_bryton",
"goal":
"introduce_caspian_as_os_level_command_for_running_caspian_files_with_argv_and_stderr",
"hard_prerequisite_for": "glenstorm_bryton",
"scope_narrowed_2026_05_28":
"permission_flag_machinery_split_into_per_capability_slices; engine_does_not_yet_have_filesystem_network_env_or_puck_to_gate; permission_flags_section_kept_as_future_direction",
"aligns_with":
["feedback_no_dangerous_defaults", "roles_md_role_based_security"]}}
~~~

Hard prerequisite for [Glenstorm](glenstorm.md) (Bryton) — Bryton
subprocess-invokes test files (per the
[Bryton spec](../../caspian/packages/bryton/index.md#tests-are-runnable-scripts), every
test file is "an ordinary executable"). This slice introduces
`caspian` as an OS-level command, adds stderr as a peer of Corin's
stdout, and wires `%argv` into the running program.

**Permission-flag enforcement is NOT in Frank.** The engine has no
filesystem, network, env-var, or Puck capabilities to gate today.
Each will land in its own slice along with the corresponding
`--allow-*` flag. Frank ships the launcher and the language pieces
the launcher needs; the
[Permissions section](#permissions-default-restrictive-opt-in-via-flags)
below is preserved as **future direction**, not as Frank's work.

<a id="what-the-slice-introduces"></a>
### What the slice introduces

~~~json
{"vibecode": {"introduces": ["caspian_command_line_launcher",
"shebang_support", "argv_via_engine_state_argv_and_percent_argv",
"stderr_sink_and_role_and_engine_err_property",
"eprint_bwc_writing_to_engine_err",
"routing_convention_engine_errors_to_stderr_program_output_to_stdout",
"exit_codes_zero_on_clean_completion_nonzero_on_uncaught"],
"not_in_frank":
["permission_flag_enforcement_for_fs_net_env_puck",
"clock_role", "randomizer_role", "utils_role", "stdin_role"],
"note_on_stdout":
"stdout_sink_and_puts_bwc_already_shipped_in_corin; frank_adds_stderr_as_a_peer_sink_plus_the_routing_convention",
"launcher_responsibilities":
["take_a_caspian_file_path_as_first_argument",
"read_the_file_and_parse_caspian_to_a_caspianj_tree",
"install_engine_caspianj_engine_std_engine_err_and_engine_state_argv",
"call_engine_run_inside_pcall",
"forward_program_puts_output_to_stdout_and_uncaught_errors_to_stderr",
"exit_zero_on_clean_completion_nonzero_on_pcall_failure"]}}
~~~

- A `caspian` command-line launcher — a small script taking a
  `.casp` file path as its first argument, invoking the engine,
  exiting with an appropriate code.
- Shebang support — `.casp` files starting with
  `#!/usr/bin/env caspian` are directly runnable via `chmod +x` and
  `./file.casp`.
- Argument passing from OS argv into the running Caspian program.
  Frank adds an `argv` field on the Skeletor state hash and a
  `{sys: "argv"}` materialize branch so `%argv` resolves to the
  program's argument list.
- **stderr sink** — engine-introduced peer of the stdout sink that
  shipped in Corin. Adds a `stderr` role on `engine.state.roles`,
  an `eprint` (or similarly named) bwc that writes to it, and an
  `engine.err` property on the engine module (mirroring `engine.std`).
  If unset when `eprint` fires, the handler raises — no ambient
  default, same posture as `engine.std`.
- **Routing convention** — engine errors and diagnostics go to
  stderr; the program's intentional output goes to stdout. The CLI
  launcher installs `engine.std = io.stdout` and
  `engine.err = io.stderr`, then `pcall`s `engine.run()` and
  routes any caught Lua error to stderr.
- Exit codes — 0 on clean completion (the launcher's `pcall` returned
  true); non-zero on any caught error (the `pcall` returned false).

<a id="permissions-default-restrictive-opt-in-via-flags"></a>
### Permissions: default restrictive, opt-in via flags (future direction, not Frank)

~~~json
{"vibecode": {"status": "future_direction_not_in_frank",
"permission_model": "default_restrictive_opt_in_via_flags",
"defaults_always_on": ["user_role", "clock_role_plus_clock_object",
"randomizer_role_plus_random_source",
"utils_role_plus_percent_utils_namespace",
"stdin_role_plus_stdin_object", "stdout_role_plus_stdout_object",
"stderr_role_plus_stderr_object",
"cli_args_role_plus_argv"], "off_by_default_grant_via_flag":
["filesystem_dirjails", "network_faucets", "env_vars", "puck",
"all_at_once_convenience"], "rationale_links":
["feedback_no_dangerous_defaults", "roles_md_role_based_security"],
"why_not_in_frank":
"engine_has_no_filesystem_network_env_or_puck_capability_to_gate_today; each_capability_lands_in_its_own_slice_with_its_corresponding_allow_flag; frank_settles_the_launcher_and_the_routing_only"}}
~~~

> **This section is future direction, not Frank work.** Frank ships
> the launcher, stderr, and argv. The permission-flag matrix arrives
> incrementally — when filesystem, network, env, or Puck capabilities
> land in their own slices, each brings the corresponding `--allow-*`
> flag with it. Frank's CLI launcher accepts unknown flags it doesn't
> understand without error, so this future work can be added without
> revisiting Frank.

Following the role-based security model in [roles.md](../../caspian/roles.md) and the
no-dangerous-defaults discipline, the CLI will eventually use a
**default-restrictive** posture: a `.casp` program invoked via the CLI
gets only the minimum roles and faucets, with everything else opt-in
via flags. This mirrors Deno's local-script model.

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
{"vibecode": {"bryton_invocation": "caspian_path_to_test_file_at_glenstorm_then_allow_all_once_flags_exist",
"rationale": "frank_does_not_yet_have_permission_flags; bryton_just_invokes_caspian_with_the_file_path; the_allow_all_form_arrives_when_permission_flags_do"}}
~~~

At Glenstorm, Bryton subprocess-invokes test files as
`caspian <test_file>` — just the launcher and the path. There are no
permission flags to pass yet because no capability-gating exists
post-Frank. Once filesystem/network/env/puck slices land along with
their `--allow-*` flags, Bryton's invocation grows to
`caspian --allow-all <test_file>` (test files typically need broad
access; per-test narrowing is later Bryton work).

<a id="open-questions"></a>
### Open questions

~~~json
{"vibecode": {"open_questions_frank_cli":
["bash_launcher_vs_pure_lua_launcher",
"cross_platform_shebang_behavior_linux_macos_wsl"],
"deferred_to_later_slices":
["flag_syntax_when_permission_flags_arrive",
"determinism_flag_for_clock_and_randomizer",
"default_for_puck_role"]}}
~~~

- **Bash launcher vs pure-Lua launcher.** The launcher could be a
  small bash script (`#!/usr/bin/env bash`) that `exec`s lua, or a
  pure-Lua script (`#!/usr/bin/env lua`) that uses `arg[0]` to
  self-locate. Either works; settled during implementation.
- **Cross-platform shebang behavior** (Linux / macOS / WSL).
  Mostly-portable on the three Unix-flavored cases; Windows native is
  V2+.

Deferred to whichever slice introduces them:

- **Flag syntax** (`--allow-fs=PATH` vs `--allow-fs PATH`, long vs
  short forms) — settles when the first permission flag lands.
- **Determinism flag for `clock`/`randomizer`** (e.g. `--seed=N`) —
  settles with the clock/randomizer slice.
- **Default for the `puck` role** — settles with the Puck client slice.

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
| `stderr` sink function | No — `engine.err` (host-installed property on the engine module) | Same rationale as `engine.std` in Corin — sinks are host-installed capabilities, not program state |
| `stderr` role object | Yes — `engine.state.roles.stderr` | Same place as `stdout` and `stdlib`; `state.roles` lives in Skeletor |
| `eprint` bwc entry | No — `engine.bwcs.eprint` | Engine-private metadata, alongside `engine.classes` and `engine.bwcs.puts` |
| Exit code | Not engine state at all — the launcher derives it from whether its `pcall(engine.run)` returned cleanly | Caspian programs don't see their own exit code; host-side concern |

<a id="skeletor-impact-snapshots"></a>
### Snapshots during a CLI run

Invocation: `caspian fixtures/echo_argv.casp foo bar baz`.

**Just after the launcher invokes the engine, before the first
statement dispatches:**

```json
{
  "argv": ["foo", "bar", "baz"],
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

**Mid-dispatch, during a hypothetical `eprint` BWC that writes to
stderr (cross-role transition into the new `stderr` role):**

```json
{
  "argv": ["foo", "bar", "baz"],
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    },
    {
      "action": "bwc_call",
      "role": "stderr",
      "bwc": "eprint",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

**After the BWC returns:**

```json
{
  "argv": ["foo", "bar", "baz"],
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

`argv` is a top-level Skeletor field — program-wide state, the same
across every frame. The frame stack pushes/pops as transitions
happen; `argv` doesn't move. Each frame carries its own `role` and
`chain` (per [skeletor.md](../../caspian/skeletor/index.md) — chain wipes at
boundaries by virtue of each frame having its own fresh chain).

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing", "test_directory":
"tests/caspian/frank/", "fixture_directory":
"tests/caspian/fixtures/",
"framework":
"support_runner_and_assert; tests_invoke_caspian_via_io_popen_and_capture_stdout_stderr_exit_code",
"phase_0_tests": ["TF.0.1", "TF.0.2"],
"phase_1_tests": ["TF.1", "TF.2", "TF.3", "TF.4", "TF.5"],
"deferred_to_per_capability_slices":
["default_denial_tests_for_fs_net_env_puck",
"allow_flag_grant_tests_for_each_capability"],
"load_bearing_test":
"TF.5_stderr_routing_proves_engine_error_vs_program_output_split"}}
~~~

Tests for Frank sit under `tests/caspian/frank/` (parallel to
`tests/caspian/aslan/`, `bree/`, `corin/`, etc.). Each test
subprocess-invokes `bin/caspian` via `io.popen` (or equivalent) and
asserts on captured stdout, stderr, and exit code. The load-bearing
assertion is TF.5 — stderr routing proves the engine-error vs
program-output split actually happens.

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
| TF.1 | integration | Successful run exits 0 | `caspian fixtures/exit_zero.casp` (just `puts 'ok'`) → exit 0 |
| TF.2 | integration | Uncaught error exits non-zero | `caspian fixtures/raise.casp` (e.g. calls `puts` with `engine.std` unset isn't possible because the launcher installs it; instead trigger a method-missing failure on a known type) → non-zero exit; error text on stderr |
| TF.3 | integration | Shebang execution | `chmod +x fixtures/hello_shebang.casp; ./fixtures/hello_shebang.casp` runs and exits 0 (shebang line is `#!/usr/bin/env caspian`) |
| TF.4 | integration | argv passing | `caspian fixtures/echo_argv.casp foo bar baz` → stdout contains `foo`, `bar`, `baz` in order (via `%argv`) |
| TF.5 | integration | stderr routing | `caspian fixtures/mixed_io.casp` (writes via `puts` AND raises an error after) → program's `puts` output appears on stdout, engine error on stderr; streams do not interleave |

<a id="frank-test-layout"></a>
### Test layout

| Path | Contents |
|---|---|
| `tests/caspian/fixtures/` | Tiny `.casp` programs each exercising one Frank concern (`exit_zero.casp`, `raise.casp`, `hello_shebang.casp`, `echo_argv.casp`, `mixed_io.casp`) |
| `tests/caspian/frank/` | The `support/runner`-based Lua tests that subprocess-invoke `bin/caspian` and assert on stdout / stderr / exit code |
| `tests/caspian/run.lua` | Extended to require the Frank test modules |
| `bin/caspian` | The launcher script itself |
