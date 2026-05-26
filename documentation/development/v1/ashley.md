# Ashley

~~~json
{"vibecode": {"codename": "Ashley",
"delivers": "inventory of the existing engine code as the starting baseline for V1 development",
"position_in_roadmap":
"first_slice_predates_aslan; pure_documentation_no_new_code",
"goal":
"document_what_exists_today_in_lib_lua_caspian_and_tests_caspian_so_subsequent_slices_have_a_clear_starting_point",
"new_code": "none",
"new_tests": "none (regression baseline: the existing test suite must reach a known-passing state)",
"slice_kind": "inventory_only"}}
~~~

Ashley is the first slice in V1 development, but it adds no new
code. It **documents what already exists** in this repository before
[Aslan](aslan.md) starts changing anything. Every subsequent slice
reads its "Phase 1 Step 1: Inventory" against the picture Ashley
records here.

Ashley sits in the slice order because it's a definable, completable
piece of work — the engine and tests need to be characterized
accurately before realignment work begins. Sorts before Aslan
alphabetically; comes before Aslan in development sequence.

---

<a id="existing-engine"></a>
## What's in `lib/lua/caspian/`

The Lua reference engine ("Lucy") with seven modules:

| Module | Size | Role |
|---|---|---|
| `init.lua` | ~4 KB | Public API. Composes the pipeline; exports `tokenize`, `parse`, `transpile`, `to_json`, `dump`, `null`. |
| `lexer.lua` | ~13 KB | Source → token stream. Used by `init.lua`'s `tokenize`. |
| `parser.lua` | ~37 KB | Token stream → AST. The largest module; covers expressions, statements, classes, functions, control flow. |
| `transpiler.lua` | ~20 KB | AST → CaspianJ (Lua table). **Emits the pre-spec CaspianJ format** — see [format gap](#format-gap) below. |
| `interpreter.lua` | ~10 KB | Pre-spec CaspianJ executor. Predates the canonical [caspianj.md](../../caspian/caspianj.md) spec. Slated for retirement as canonical dispatch replaces it. |
| `engine.lua` | ~8 KB | **Canonical-CaspianJ executor**. The V0.01 (Aslan) dispatch path. Already contains: `bootstrap`, `materialize`, `lookup_method`, `transition`, `dispatch`, `run`. Coexists with `interpreter.lua`; no shared state. |
| `json.lua` | ~11 KB | JSON parser + encoder. Includes the `null` sentinel. **Has a known issue** — see [known issues](#known-issues). |

Total: ~103 KB of Lua source.

`engine.lua` already exists because Aslan's implementation has been
partially done in advance. Aslan's job is to **finish** that work and
prove it end-to-end against the hello-world fixture, not to write the
engine from scratch.

---

<a id="existing-tests"></a>
## What's in `tests/caspian/`

The test suite is organized by pipeline stage:

Test code is organized by slice. The pre-existing pipeline tests
(lexer, parser, transpiler — the engine's source-side stages as
they stood before V1 work) live under `v00/`. Aslan's tests live
under `v001/`. Both directory names will eventually be renamed to
their codenames (`ashley/` and `aslan/`) — pending follow-up.

```
tests/caspian/
├─ run.lua              # entry point; requires every test module, calls runner.report()
├─ support/             # runner + assert helpers (unchanged)
├─ v00/                 # Ashley baseline: pre-existing source-pipeline tests
│  ├─ fixtures/         # sample .casp source files exercised by transpiler tests
│  │  ├─ hello.casp
│  │  ├─ foo.casp
│  │  ├─ control_flow.casp
│  │  ├─ functions.casp
│  │  ├─ strings.casp
│  │  ├─ pipes.casp
│  │  ├─ mikobase.casp
│  │  ├─ http-server.casp
│  │  ├─ system.casp
│  │  └─ lengthy.casp
│  ├─ lexer/
│  │  ├─ test_literals.lua
│  │  ├─ test_operators.lua
│  │  └─ test_sigils.lua
│  ├─ parser/
│  │  ├─ test_assignments.lua
│  │  ├─ test_classes.lua
│  │  ├─ test_control.lua
│  │  ├─ test_expressions.lua
│  │  └─ test_functions.lua
│  └─ transpiler/
│     ├─ test_examples.lua
│     ├─ test_expressions.lua
│     └─ test_statements.lua
└─ v001/                # Aslan-slice tests, already drafted
   ├─ fixtures/
   │  └─ hello_world.caspj     # canonical Aslan fixture
   ├─ test_bootstrap.lua
   ├─ test_dispatch.lua
   ├─ test_json_parse.lua
   ├─ test_lookup_method.lua
   ├─ test_materialize.lua
   ├─ test_run.lua
   ├─ test_sys_role.lua
   ├─ test_transition.lua
   └─ test_transition_observed.lua
```

Plus `tests/sanity/` (sibling of `tests/caspian/`) for the
pre-framework Phase 0 sanity checks (TA.0.1 through TA.0.6 in
the [Aslan](aslan.md) plan):

```
tests/sanity/
├─ fixtures/
│  └─ _sanity_text.txt
├─ lua_hello.lua
├─ test_framework_sanity.lua
├─ test_file_read.lua
├─ test_json_parse.lua
├─ test_lua_hello.lua
├─ test_lua_version.lua
└─ test_package_path.lua
```

The `v001/` subdir already has the test files for Aslan's
implementation (`test_bootstrap.lua` → TA.1, `test_materialize.lua`
→ TA.3, etc.).

---

<a id="format-gap"></a>
## The pre-spec / canonical CaspianJ gap

The existing `transpiler.lua` emits a **pre-spec CaspianJ format**
that predates the canonical [caspianj.md](../../caspian/caspianj.md)
spec. The two disagree on at least these shapes:

| Construct | Pre-spec (existing transpiler) | Canonical (per spec) |
|---|---|---|
| Method call | wrapped form (TBD per Aslan Phase 1 Step 2 inventory) | `[receiver, method, args?]` |
| Assignment | `["scope", "setvar", name, value]` (4-element) | `[receiver, method, args?]` shape |
| BWC call | `[{bwc:name}, '&', {args:[expr]}]` (extra wrapper) | `[{bwc:name}, expr]` (direct positional) |

`interpreter.lua` consumes the pre-spec format. `engine.lua` consumes
the canonical format. They run independent of each other — engine.lua
calls `caspian.json.parse` on a `.caspj` file directly, never through
the source-side pipeline.

The realignment work is incremental:

- [Aslan](aslan.md) — engine.lua's canonical dispatch path is finished and proven against the hand-written `[[{"value": "hello"}, "to_string"]]` fixture.
- [Bree](bree.md) — transpiler.lua's path for `string-literal + method-call + expression-statement` is realigned to emit canonical.
- [Corin](corin.md) — transpiler.lua's bwc-call path is realigned.
- [Digory](digory.md) — transpiler.lua's hash-literal path is realigned.
- [Edmund](edmund.md) — `.to_json` registration (no transpiler realignment needed; `.to_json` is a regular method call).

`interpreter.lua` shrinks as each realigned AST path migrates to
engine.lua. By [Glenstorm](glenstorm.md) it may be deletable, or may
remain as historical reference.

---

<a id="known-issues"></a>
## Known issues to address

These are real problems with the existing code that need fixing
during Ashley (or named explicitly as deferred work):

<a id="json-lua-version-incompatibility"></a>
### `json.lua` uses Lua 5.4 syntax

`lib/lua/caspian/json.lua` lines 182–184 use bitwise operators
(`>>`, `&`) introduced in Lua 5.3. These don't parse on Lua 5.1 or
5.2. The user's current `lua` binary is 5.1, so the test suite
**doesn't currently run at all** — it errors at the `require
"caspian.json"` step in `tests/sanity/test_package_path.lua`.

Two paths:

1. **Lock the engine to Lua 5.4** — per the
   [V1 dependency story](details/lua-dependencies.md), Lua 5.4 is the
   target version. The install bundle ships Lua 5.4 anyway. Document
   this requirement clearly and confirm the dev environment matches.
2. **Rewrite the offending UTF-8 helper in 5.1-compatible form** —
   replace `cp >> 6` with `math.floor(cp / 64)` etc. Allows the
   engine to run on older Lua at minor performance cost. Probably
   not worth it; commit to 5.4 instead.

Ashley's choice: **commit to Lua 5.4**. Update the dev environment
documentation in [aslan.md Step 0.1](aslan.md#step-01-confirm-lua-54)
to make this an explicit blocker.

<a id="claimed-vs-actual-test-count"></a>
### "172 passing tests" claim doesn't currently hold

[CLAUDE.md](../../../CLAUDE.md) and several slice docs reference 172
passing tests. With the json.lua issue above, that count can't be
verified — the suite errors out. Once Lua 5.4 is in place, re-run
and document the actual current count. The "172" figure stays as a
target until empirically reconfirmed.

<a id="v00-and-v001-dir-names"></a>
### `tests/caspian/v00/` and `v001/` directory names

Numeric versioning was removed from the doc layer (per the
codename-only cleanup that just landed). Test directories still
use the old `v00/` and `v001/` names. Plan:

- `tests/caspian/v00/` → `tests/caspian/ashley/` (this slice's tests)
- `tests/caspian/v001/` → `tests/caspian/aslan/` (Aslan slice's tests)

Deferred from Ashley itself to avoid mid-slice churn — done as part
of each slice's first-edit pass when work on it begins.

---

<a id="what-aslan-inherits"></a>
## What Aslan inherits from Ashley

When [Aslan](aslan.md) starts, it inherits:

- `engine.lua` with `bootstrap` / `materialize` / `lookup_method` /
  `transition` / `dispatch` / `run` already drafted. Aslan completes
  and validates them.
- `json.lua` — pending the Lua 5.4 commitment from the
  [known issues](#known-issues) above.
- 9 test files under `tests/caspian/v001/` corresponding to
  Aslan's TA.1–TA.8 plus json-parse sanity. These test the engine.lua
  surface; once the suite runs cleanly, Aslan verifies them green.
- The hand-written `tests/caspian/fixtures/hello_world.caspj`
  fixture (exact contents: `[[{"value": "hello"}, "to_string"]]`).

Aslan's actual work is therefore not "implement V0.01 from scratch"
but **"finish Aslan, prove it end-to-end, document the result."**

---

<a id="definition-of-done"></a>
## Definition of done

Ashley is done when all four are true:

1. **Engine modules are inventoried.** Every file in `lib/lua/caspian/`
   has a row in this doc with a one-line description.
2. **Tests are inventoried.** The full `tests/caspian/` tree
   structure is in this doc.
3. **Format gap is documented.** The pre-spec vs canonical CaspianJ
   differences are listed with enough specificity that Aslan's
   inventory step can reference this doc directly.
4. **Known issues are recorded.** Each known issue (Lua 5.4 commit,
   test-count reconfirmation, `v001/` rename) is either resolved or
   has an explicit owner in a downstream slice.

No new engine code. No new tests. Ashley is a baseline document.

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing",
"new_tests_in_this_slice": 0,
"baseline_action":
"once_lua_5_4_is_in_place_run_the_existing_test_suite_and_record_actual_pass_fail_count",
"target": "all_existing_tests_pass_or_each_failure_is_named_and_owned"}}
~~~

Ashley adds no tests. The acceptance criterion is **regression
baseline**: with Lua 5.4 installed, the existing test suite either
passes entirely or every failure is named and assigned to a downstream
slice as known-broken work. Pass count is recorded here as a snapshot
once it's known.

| ID | Level | Verifies | How |
|---|---|---|---|
| TAs.1 | meta | Lua 5.4 is the active interpreter | `lua -v` reports 5.4 |
| TAs.2 | regression | `lua tests/caspian/run.lua` reaches the report line | No early error; runner reports a summary |
| TAs.3 | regression | All currently-green tests stay green | Pass count matches the snapshot recorded in this doc |

Once TAs.1–TAs.3 are met, Ashley is complete and Aslan can start.

---

<a id="open-questions"></a>
## Open questions

- **Actual current pass count.** Cannot be confirmed until the Lua
  5.4 environment is in place. Record here as a footnote once known.
- **`v001/` rename timing.** Done as part of Ashley, or as Aslan's
  first concrete code change? Probably Ashley (documentation slice
  can include the rename since it's metadata, not behavior). To be
  decided.
- **Should `interpreter.lua` be quarantined now?** Ashley could move
  it to `lib/lua/caspian/legacy/interpreter.lua` to make its
  to-be-retired status structurally obvious. Mild scope creep —
  defer to the slice that actually removes its last consumer.
