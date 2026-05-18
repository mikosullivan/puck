# First Steps

~~~json
{"vibecode": {"doc": "first_steps", "purpose":
"concrete_file_by_file_actions_to_start_v001; companion_to_high_level_development_plan",
"audience": "developer_sitting_down_to_start_implementation",
"position": "between_reading_development_md_and_writing_engine_code",
"scope": "first_six_concrete_steps_only; remainder_emerges_as_each_completes"}}
~~~

The [development plan](development.md) describes V0.01 at the phase
level — what each layer needs, why the roles bake in from the start,
the test-plan shape. This doc is the **concrete companion**: the
file-by-file commands and edits for the very first few steps, before
anything else.

Six steps. Each one is small, runnable, and observable on its own. Do
them in order; don't skip ahead. The point is to get from "nothing
started" to "the first V0.01 test passes" through a sequence that's
hard to fail at.

---

<a id="step-1-run-the-existing-test-suite"></a>
## 1 Step 1: Run the existing test suite

From the project root:

```
lua tests/charlie/run.lua
```

The existing scaffolding includes lexer, parser, and transpiler tests
from earlier work. **We are not trying to make all of these pass for
V0.01.** Their purpose at this step is to establish a baseline:

- Does the test runner load and execute at all?
- What's the pass / fail count right now?
- Which tests fail, and roughly why?

Record the output somewhere casual (a scratch note, a paste into a
gist — doesn't need to be checked in). This is the "before" snapshot.

If the runner itself errors out before running any tests
(e.g., `module 'charlie.lexer' not found`), that's a `package.path`
problem and Step 2 is where you'll fix it.

---

<a id="step-2-read-the-engine-source"></a>
## 2 Step 2: Read the engine source

Open these files in your editor in this order:

| File | Why first |
|---|---|
| `tests/charlie/run.lua` | Confirms how `package.path` is set; that's how every test discovers the engine modules |
| `tests/charlie/support/runner.lua` | The test framework: `suite`, `test`, `report` |
| `tests/charlie/support/assert.lua` | The assertion helpers (`equal`, `is_nil`, `not_nil`, etc.) |
| `code/charlie/lua/charlie/json.lua` | The JSON parser the engine will use to load `.ksj` files |
| `code/charlie/lua/charlie/interpreter.lua` | The CharlieJSON executor in whatever state it's currently in |

Open each, read top-to-bottom, get a sense of:

- Does `charlie.json` export a `parse` function? What does it return for
  a nested JSON array?
- Does `charlie.interpreter` have a `run` (or `execute`, or
  similar) entry point? What does it expect as input?
- Does `support.runner` have any state we have to clear between test
  files (a global pass/fail counter, for instance)?

You don't need to understand everything — just enough to know what's
already there. This is the inventory phase. Output: a short list of
"this exists, this is missing, this is unclear."

**One thing to specifically look for in the inventory:** the existing
interpreter consumes a **pre-spec CharlieJSON format** (its own
docstring notes this). Concretely:

- Assignment is emitted as `["scope", "setvar", name, value]` — a
  four-element shape, not the canonical `[receiver, method, args?]`.
- BWC calls wrap their args in an extra `{"args": [...]}` layer
  rather than passing the positional expression directly.
- Other shapes may differ; only two paths have been checked.

The canonical form lives in
[charliejson.md](../charlie/charliejson.md), and the V0.01 fixture
uses it. **The spec wins** — when the interpreter and the spec
disagree, the interpreter is the thing that changes. Part of Step 1's
output is therefore the exact list of format mismatches the engine
needs to be brought into line on.

---

<a id="step-3-write-the-v001-fixture"></a>
## 3 Step 3: Write the V0.01 fixture

Create the file `tests/charlie/fixtures/hello_world.ksj`. Contents,
exactly:

```
[[{"value": "hello"}, "to_string"]]
```

One line, no trailing comment, no surrounding whitespace beyond the
final newline. This is the **entire input** for V0.01. The outer array
is the program (a list of statements); the inner array is one
statement in the canonical `[receiver, method, args?]` shape; the
receiver is the string literal `"hello"`; the method is `to_string`;
no args.

Verify the file is there:

```
cat tests/charlie/fixtures/hello_world.ksj
wc -l tests/charlie/fixtures/hello_world.ksj
```

Expected output: the literal JSON string, and `1` line.

---

<a id="step-4-first-sanity-test-parse-the-fixture"></a>
## 4 Step 4: First sanity test — parse the fixture

Create `tests/charlie/v001/test_fixture_parse.lua`:

```lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local json = require("charlie.json")

runner.suite("v0.01 / fixture parse")

runner.test("parses the hello_world fixture", function()
    local f = assert(io.open("tests/charlie/fixtures/hello_world.ksj"))
    local source = f:read("*a")
    f:close()

    local parsed = json.parse(source)
    assert_.not_nil(parsed, "json.parse returned nil")
    assert_.equal(type(parsed), "table")

    -- The outermost array should hold exactly one statement.
    assert_.equal(#parsed, 1)
    -- That statement should itself be an array of [receiver, method].
    assert_.equal(type(parsed[1]), "table")
    assert_.equal(#parsed[1], 2)
end)
```

Wire it into the test runner. Open `tests/charlie/run.lua` and add:

```lua
require("v001.test_fixture_parse")
```

…alongside the existing `require("lexer.test_literals")` etc. lines.

Run:

```
lua tests/charlie/run.lua
```

Expected: a dot for this test in the runner output, and a final
summary line showing one additional pass.

If `charlie.json`'s API doesn't match what the test assumes (different
function name, different return shape), this is where you discover it.
Update either the test or `charlie.json` as appropriate. Step 2's
inventory should have told you which.

---

<a id="step-5-engine-entry-point"></a>
## 5 Step 5: Engine entry point

In `code/charlie/lua/charlie/`, create `engine.lua` (or evolve whatever
top-level entry already lives there) so that `require("charlie")`
returns a table with a `run` function:

```lua
local engine = {}
local json = require("charlie.json")

function engine.run(path)
    local f = assert(io.open(path))
    local source = f:read("*a")
    f:close()
    local tree = json.parse(source)

    -- TODO Step 6+: bootstrap roles + classes + ctx, then execute
    -- the parsed tree's statements, then return the last value.
    -- For now, return the parsed tree so we can confirm the load path
    -- works end-to-end before adding executor logic.
    return tree
end

return engine
```

If `code/charlie/lua/charlie/init.lua` already exists and `charlie` is
already a module, integrate the `run` function there instead. The
import surface from the test side stays the same:

```lua
local engine = require("charlie")
```

Add `tests/charlie/v001/test_engine_run.lua`:

```lua
local runner = require("support.runner")
local assert_ = require("support.assert")
local engine = require("charlie")

runner.suite("v0.01 / engine.run")

runner.test("engine.run on the fixture returns a parsed tree", function()
    local result = engine.run("tests/charlie/fixtures/hello_world.ksj")
    assert_.not_nil(result)
    assert_.equal(type(result), "table")
    assert_.equal(#result, 1)
end)
```

Wire this into `tests/charlie/run.lua` the same way as Step 4.

Run the suite again. Expected: two new passing tests for V0.01 plus
whatever was passing before.

---

<a id="step-6-pick-the-first-real-implementation-slice"></a>
## 6 Step 6: Pick the first real implementation slice

At this point the engine loads, parses, and returns the parsed tree.
**It doesn't execute anything yet.** The V0.01 acceptance test
([T1.7 in the main plan](development.md#phase-1-test-plan)) wants
`engine.run(...)` to return a value whose payload equals the string
`"hello"`. To get there, the next concrete slice is one of:

| Candidate | What it does | Lines (rough) |
|---|---|---|
| `engine.bootstrap()` | Creates the role registry (`user` + `stdlib`) and the string class with `to_string` (owned by `stdlib`). Sets `engine.ctx` | ~40 |
| `engine.materialize(expr)` | Turns `{"value": "hello"}` into a value table `{type, owning_role, payload}` | ~20 |
| `engine.lookup_method(value, name)` | Finds `to_string` on the string class | ~15 |
| `engine.transition(new_role, fn)` | Save/restore ctx around a Lua function call | ~15 |
| `engine.dispatch(statement)` | Ties it all together: materialize receiver, look up method, transition if needed, call, restore. **Consumes canonical `[receiver, method, args?]` shape per [charliejson.md](../charlie/charliejson.md)** — the existing interpreter's pre-spec shapes are deprecated by this work. | ~25 |
| Format alignment for the rest of the interpreter | Migrate the remaining statement-shape handlers (assignment, `if`/`elsif`/`else`, etc.) from the pre-spec format to canonical CharlieJSON. Touches every dispatch path in `interpreter.lua`. Existing parser/transpiler tests still pass — they test the source-side, not the runtime format. Some interpreter-level tests may need to be added or rewritten. | varies |

Recommended order: `bootstrap` first (everything else needs the roles
and classes to exist), then `materialize`, then `lookup_method`, then
`transition`, then `dispatch`. After `dispatch` exists, hook it into
`engine.run` to actually execute each statement and return the last
result.

For each slice:

1. **Write the unit test first** under `tests/charlie/v001/`, named
   `test_<slice>.lua`. The test plans in [development.md
   §Phase 1 test plan](development.md#phase-1-test-plan) (T1.2
   through T1.6) spell out what each one should assert.
2. **Implement the slice** in `code/charlie/lua/charlie/engine.lua`
   (or its companions). Keep each implementation small — just enough
   to make the test pass.
3. **Run the suite.** Confirm the new test passes and nothing else
   broke.
4. **Commit.** One slice per commit makes the history readable.

The slice loop ends when T1.7 (engine.run returns a value with
payload "hello") passes. T1.8 (role transition observed) closes
V0.01.

---

<a id="what-this-doc-does-not-cover"></a>
## 7 What this doc does NOT cover

~~~json
{"vibecode": {"out_of_scope_for_first_steps":
["v002_charlie_text_parser_and_transpiler", "v00X_stdout_hashes_json_serialization",
"v00X_charlie_cli", "v01_bryton", "lua_host_optimizations",
"performance_tuning", "error_message_polish"]}}
~~~

This doc covers only the first six concrete actions. Once V0.01
passes, the next slice (V0.02, Charlie-text → CharlieJSON transpiler)
gets its own first-steps treatment when the time comes. Same shape:
phase-level in [development.md](development.md), file-by-file in a
companion doc.

The point is to **never go from "high-level plan" directly to "type
code." There's always a short, concrete intermediate doc that says
exactly what to do first.**
