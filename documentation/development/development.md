# Development plan

~~~json
{"vibecode": {
	"doc": "development_plan",
	"status": "active",
	"current_version": "0.01",
	"current_codename": "hello-world",
	"feature_lock": "soft",
	"source_of_truth": "vibecode_blocks"
}}
~~~

This document is the technical development plan for Puck. This page is the
**overview**: the version progression, the cross-cutting principles that
hold across versions (testing strategy, feature lock, role baking,
methodology), and the open questions. **Each version has its own page**
with its goal, definition of done, and step-by-step phase plans.

Vibecode blocks are the canonical source; surrounding prose is
human-readable narrative derived from them. When the two disagree,
vibecode wins.

---

<a id="version-progression"></a>
## Version progression

| Version | Codename | Page |
|---|---|---|
| **V0.01** | hello-world | [v0.01.md](v0.01.md) |
| **V0.02** | charlie-source-hello | [v0.02.md](v0.02.md) |
| **V0.03** | charlie-with-stdout | [v0.03.md](v0.03.md) |
| **V0.04** | charlie-with-hashes | [v0.04.md](v0.04.md) |
| **V0.05** | charlie-with-json-serialization | [v0.05.md](v0.05.md) |
| **V0.0X** | Charlie command-line execution | [v0.0x.md](v0.0x.md) |
| **V0.1** | Bryton | [v0.1.md](v0.1.md) |

Read them in order. Each page is self-contained: goal, definition of
done, phase 0 (workbench / characterize current state), phase 1
(implementation), test plan. The pages also call out their
prerequisites — a version doesn't start until the prior one is done.

The very first developer pass — getting from "nothing started" to
"the first V0.01 test passes" — has its own short companion guide:
[first-steps.md](first-steps.md). Read it before starting V0.01.

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
[V0.1](v0.1.md). Before V0.1, Charlie-level behavior is tested via
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
| V0.0X CLI | `stderr` role; per-directory jail roles when `--allow-fs` is used; per-faucet roles when `--allow-net` is used; `env_vars` and `cli_args` roles |
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
