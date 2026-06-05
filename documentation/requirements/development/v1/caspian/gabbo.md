# Gabbo

~~~json
{"vibecode": {"slice": "gabbo_caspj_cache", "codename": "Gabbo",
"delivers": "on_disk_caspj_cache_with_caspj_subdir_next_to_source",
"position_in_roadmap":
"after_frank_frank_caspian_cli; before_glenstorm_glenstorm_bryton",
"goal":
"add_persistent_caspj_cache_so_the_engine_skips_lexer_parser_transpiler_on_subsequent_runs_of_unchanged_source",
"design_doc": "../../../caspian/downloads/caching/index.md",
"primary_beneficiary": "glenstorm_glenstorm_bryton_which_subprocess_invokes_every_test_file_independently",
"aligns_with": ["feedback_no_dangerous_defaults",
"caspianj_is_runtime_caspian_text_is_for_humans"]}}
~~~

Gabbo adds the on-disk CaspianJ cache designed in
[caching/index.md](../../../caspian/downloads/caching/index.md). After a `.casp` file
runs once, the transpiler's JSON output is written to a `caspj/`
subdir next to the source. Subsequent runs read the cache directly
and skip lexer + parser + transpiler entirely, paying only the
JSON-parse cost the engine would pay regardless.

Gabbo sits between [Frank](frank.md) (the CLI launcher) and
[Glenstorm](glenstorm.md) (Bryton). It lands when CLI invocations
have started happening (so the cache benefits everyday `caspian
foo.casp` runs) and just before Bryton subprocess-invokes every
test file (so the per-file parse cost collapses to "only files
whose source actually changed").

The cache discipline mirrors the existing `bucket/` convention —
data that belongs to a directory lives in a subdirectory named
after the data's kind. Hence `caspj/`.

<a id="definition-of-done"></a>
### Definition of done

~~~json
{"vibecode": {"scope_status": "drafted_2026-05-24", "done_criteria":
{"caspj_subdir_creation":
"first_transpile_creates_caspj_subdir_next_to_source_file",
"cache_file_format":
"cached_caspj_files_are_json_objects_with_meta_plus_tree_keys; hand_written_caspj_remains_bare_array",
"validity_checks":
"engine_version_transpiler_version_source_mtime_source_sha256_all_must_match",
"atomic_write":
"writes_use_temp_file_plus_rename_no_torn_writes_on_concurrent_invocations",
"fallback_chain":
"side_by_side_then_user_cache_then_in_memory_only",
"regression":
"all_prior_slice_fixtures_still_pass"}}}
~~~

Gabbo is done when all six are true:

1. **`caspj/` subdir is created** next to a `.casp` file the first
   time the engine transpiles it. The subdir is created lazily —
   sources never transpiled get no `caspj/` next to them.
2. **Cache files use the wrapped format** (`{"meta": {...},
   "tree": [...]}`) and hand-written `.caspj` fixtures (bare JSON
   arrays) continue to work unchanged.
3. **Validity checks reject stale or tampered cache files** — engine
   version, transpiler version, source mtime, source SHA-256 all
   must match or the cache is treated as missing and the source is
   re-parsed.
4. **Writes are atomic** — temp file in the same directory then
   `rename`. Two processes invoking the same source at the same time
   produce no torn writes; the later rename simply wins.
5. **The fallback chain works** — side-by-side cache when the source
   directory is writable, user cache dir
   (`~/.cache/caspian/<source-path-hash>.caspj`) when it isn't,
   in-memory-only when neither is possible.
6. **Every prior slice's fixtures still pass.** Aslan hand-written
   CaspianJ, Bree source hello-world, Corin `puts`, Digory hashes,
   Edmund `.to_json`, Frank CLI launcher tests — all still produce
   the same outputs.

That's the entirety of Gabbo. Soft feature lock applies.

---

<a id="gabbo-phase-0-cache-mechanics-workbench"></a>
## Phase 0: cache mechanics workbench

~~~json
{"vibecode": {"phase": 0, "purpose":
"verify_host_filesystem_capabilities_gabbo_depends_on_before_writing_cache_logic",
"steps_count": 4, "acceptance":
"all_four_workbench_checks_pass_no_cache_logic_written",
"tactic": "isolate_filesystem_and_hash_operations_from_engine_changes"}}
~~~

Gabbo depends on a few host capabilities — atomic rename, SHA-256
computation, mtime stat, user-cache-dir creation. Phase 0 verifies
each in isolation before any engine code changes.

<a id="gabbo-step-01-atomic-rename"></a>
### Step 0.1: Verify atomic rename within a directory

`os.rename(tmp, final)` is atomic on every reasonable filesystem
when both paths are in the same mount. Write a small Lua sanity
test that confirms rename works and the temp file vanishes after.

<a id="gabbo-step-02-sha256-of-a-file"></a>
### Step 0.2: Verify SHA-256 of a file

The cache validity check compares `sha256(source_bytes)` to a stored
value. luasodium exposes `crypto_hash_sha256`. Sanity test: known
file with a known SHA-256, confirm match.

<a id="gabbo-step-03-mtime-stat"></a>
### Step 0.3: Verify mtime stat

`os.execute('stat -c %Y file')` or similar — or, if luaposix is in
the install, `posix.stat(path).mtime`. Either way, confirm the
engine can read source mtime as an integer.

<a id="gabbo-step-04-user-cache-dir-creation"></a>
### Step 0.4: Verify user cache dir creation

`~/.cache/caspian/` is created on demand (with `mkdir -p`
equivalent) before any file is written there. Confirm creation
works under a non-existent parent path.

When all four pass, Phase 1 can begin.

---

<a id="gabbo-phase-1-cache-integration"></a>
## Phase 1: cache integration

~~~json
{"vibecode": {"phase": 1, "acceptance":
"engine_run_source_consults_cache_first_and_writes_cache_after_a_fresh_parse_with_all_validity_checks_in_place_and_atomic_writes",
"required_work":
["engine_cache_load_function_with_validation",
"engine_cache_write_function_with_atomic_rename",
"engine_run_source_integration_via_cache_lookup_before_parse",
"fallback_chain_side_by_side_then_user_cache_then_in_memory",
"startup_cleanup_pass_for_stale_tmp_files",
"caspj_format_distinguisher_object_vs_bare_array"]}}
~~~

Three steps, same shape as prior slices.

<a id="gabbo-step-1-inventory"></a>
### Step 1: Inventory

Read `engine.run_source` and `engine.run_tree` as they stand after
Frank. Note where the lexer/parser/transpiler chain runs, and where
the dispatcher receives the tree. The cache lookup goes immediately
before the chain runs; the cache write goes immediately after the
chain produces the tree and before dispatch.

Document the existing `engine.run` (CaspianJ file) path — it
already accepts a JSON tree directly. The cache load reads exactly
this shape, so the integration is a small branch: if a valid cache
exists, take the existing `engine.run_tree` path with the cached
tree; otherwise fall through to the existing source-parse path.

<a id="gabbo-step-2-fill-the-gaps"></a>
### Step 2: Fill the gaps

Add four engine functions:

- **`engine.cache_path(source_path)`** — returns the side-by-side
  cache path (e.g., `src/foo.casp` → `src/caspj/foo.caspj`) or the
  user-cache fallback path. Tries side-by-side first; if the parent
  isn't writable, returns the user-cache path.
- **`engine.cache_load(source_path)`** — looks up the cache,
  validates engine version + transpiler version + source mtime +
  source SHA-256, returns the parsed tree if valid or `nil`
  otherwise. Treats malformed JSON, missing meta, and any
  validation failure identically (return `nil`).
- **`engine.cache_write(source_path, tree)`** — wraps `tree` in
  `{meta, tree}`, writes to a temp file, renames atomically. On any
  error (disk full, EACCES, etc.), silently abandon the cache
  write — the run still succeeds in-memory.
- **`engine.cache_cleanup()`** — best-effort sweep of stale
  `.foo.caspj.tmp.*` files older than an hour in any `caspj/` dir
  the engine has touched in this process. Runs at engine startup
  before any source is processed.

Modify `engine.run_source(path, env)`:

```lua
function engine.run_source(path, env)
    local cached = engine.cache_load(path)
    if cached then
        return engine.run_tree(cached, env)
    end
    local tree = parse_source_to_tree(path)
    engine.cache_write(path, tree)  -- best effort
    return engine.run_tree(tree, env)
end
```

Add the wrapper-format distinguisher to `engine.run_tree`:

```lua
function engine.run_tree(loaded, env)
    if type(loaded) == "table" and loaded.meta and loaded.tree then
        return dispatch(loaded.tree, env)
    end
    -- Bare array: hand-written CaspianJ fixture
    return dispatch(loaded, env)
end
```

<a id="gabbo-step-3-verify"></a>
### Step 3: Verify

Three end-to-end checks:

1. First run of `caspian src/hello.casp` parses source, writes
   `src/caspj/hello.caspj`, returns expected output.
2. Second run of the same file loads from `src/caspj/hello.caspj`,
   skips the parser (provable via a spy/counter), returns the same
   output.
3. After `touch src/hello.casp` (mtime change), the next run
   detects the stale cache, re-parses, re-writes, returns the same
   output.

When Gabbo passes, Glenstorm is selected. Bryton inherits
Gabbo automatically — every subprocess Bryton spawns benefits.

---

<a id="drinian-impact"></a>
## Drinian impact

**Gabbo does not change the
[Drinian state hash](aslan.md#data-structures-lua-tables) shape
or contents.** Cache load and cache write happen in engine
plumbing, not in the runtime state the program sees. Whether the
tree arrived from a fresh parse or from a cache file, dispatch
proceeds identically — same `engine.state`, same `current_role`
transitions, same `chain` semantics.

The cache is an optimization on the path *into* the dispatcher, not
a change to the dispatcher or to what it manages.

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing",
"test_directory": "tests/caspian/gabbo/",
"fixture_directory": "tests/caspian/fixtures/gabbo/",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TGa.0.1", "TGa.0.2", "TGa.0.3", "TGa.0.4"],
"phase_1_tests": ["TGa.1", "TGa.2", "TGa.3", "TGa.4", "TGa.5",
"TGa.6", "TGa.7", "TGa.8", "TGa.9", "TGa.10"],
"load_bearing_tests":
["TGa.7_atomic_write_holds_under_simulated_concurrent_writers",
"TGa.9_second_run_demonstrably_skips_parser"]}}
~~~

Gabbo has fourteen tests total: four Phase 0 host-capability checks
plus ten Phase 1 unit + integration + regression tests. TGa.7
(atomic write under concurrency) and TGa.9 (second-run cache hit
provably skips the parser) are the load-bearing assertions — they
prove the two things Gabbo actually has to deliver.

<a id="gabbo-phase-0-test-plan"></a>
### Phase 0 test plan

| ID | Level | Verifies | Tool |
|---|---|---|---|
| TGa.0.1 | unit | Atomic rename within a directory | `test_rename.lua` |
| TGa.0.2 | unit | SHA-256 of a known file matches a known digest | `test_sha256.lua` |
| TGa.0.3 | unit | Source-file mtime stat returns an integer | `test_mtime.lua` |
| TGa.0.4 | unit | `~/.cache/caspian/` created on demand under a non-existent parent | `test_user_cache_mkdir.lua` |

All four must pass before Phase 1 begins.

<a id="gabbo-phase-1-test-plan"></a>
### Phase 1 test plan

| ID | Level | Verifies | How |
|---|---|---|---|
| TGa.1 | unit | `cache_load` returns nil for missing cache | No `caspj/` dir present; assert `cache_load(path) == nil` |
| TGa.2 | unit | `cache_load` returns nil for mtime mismatch | Hand-craft a cache file with stale mtime; assert rejected |
| TGa.3 | unit | `cache_load` returns nil for SHA-256 mismatch | Hand-craft a cache file with wrong source hash; assert rejected |
| TGa.4 | unit | `cache_load` returns nil for version mismatch | Hand-craft a cache file with old engine version; assert rejected |
| TGa.5 | unit | `cache_load` returns parsed tree for valid cache | Hand-craft a valid cache file; assert tree returned matches expected |
| TGa.6 | unit | `cache_write` creates `caspj/` subdir lazily | Source dir has no `caspj/`; after write, dir exists with cache file inside |
| TGa.7 | unit | Atomic write holds under simulated concurrent writers | Spawn two Lua coroutines / processes both calling `cache_write` for the same source; assert resulting file contents are valid and equal |
| TGa.8 | unit | Fallback to user cache when source dir is read-only | `chmod -w` the source dir; `cache_write` succeeds in `~/.cache/caspian/`; `cache_load` finds it there |
| TGa.9 | integration | Second run demonstrably skips the parser | Spy/counter wrapping the lexer; first run increments, second run does not |
| TGa.10 | regression | All prior slice fixtures still pass | Aslan–Frank fixtures run via `caspian` and produce expected outputs |

All ten pass = Gabbo done.

<a id="gabbo-test-layout"></a>
### Test layout

| Path | Contents |
|---|---|
| `tests/caspian/fixtures/gabbo/` | Source files used as cache inputs (`gabbo_hello.casp` etc.) |
| `tests/caspian/gabbo/` | Phase 0 + Phase 1 tests |
| `tests/caspian/run.lua` | Extended to require Gabbo test modules |
| `tests/caspian/support/` | May gain a small `cache_spy` helper if useful across tests |
