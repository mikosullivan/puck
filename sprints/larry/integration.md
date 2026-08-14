~~~vibecode
{"doc": "sprint-integration-plan", "sprint": "larry",
	"role": "Plan for promoting the row-handler chain public API (add_handler, prepend_handler, remove_handler, clear_handlers, handlers) from Larry down into the base Engine class.",
	"issue": "https://github.com/mikosullivan/puck/issues/1622",
	"trigger": "requires 'proceed with the integration' / 'proceed with the assimilation'"}
~~~

# Integration plan — handler-chain public API

## Overview

The five row-handler-chain methods currently live on Larry:

- `add_handler(handler)` → self
- `prepend_handler(handler)` → self
- `remove_handler(handler)` → self (raises `handler_not_found`)
- `clear_handlers()` → self
- `handlers()` → shallow-copy array

Integration moves them into the base Engine class, converts existing direct-mutation call sites in shipping tests to use the API, and removes the now-redundant Larry-side definitions. Larry keeps inheriting the methods for free.

After integration, direct `table.insert(engine.row_handlers, h)` and `engine.row_handlers = {}` are still mechanically possible (Lua has no field privacy), but the docstring stops advertising them — the API is the sanctioned surface.

## Concrete changes

### 1. Move the five methods into `src/engine/engine.lua`

Copy the five method definitions and their docstrings verbatim from [sprints/larry/src/larry.lua](https://puck.uno/sprints/larry/src/larry.lua) into [src/engine/engine.lua](https://puck.uno/src/engine/engine.lua). Land them after `M:run_row` and before `return M`. Adjust the docstring "Prototype surface for #1622; moves down to Engine at integration." parenthetical to just reference the issue as historical context (or drop it — the git log will carry the story).

### 2. Update the Engine module-header JSON block

The `exports` hash in the top-of-file JSON docstring currently only lists `new`. Add entries for the five new methods, matching the shape used in Larry's header.

The `role` field mentions "Iteratively extended by registering Handler subclasses into row_handlers — no if/elseif branching in run_row." Broaden this to "via the row-handler-chain API (add_handler / prepend_handler / …)" — the concept doesn't change, but the sanctioned way to do it does.

### 3. Update the `row_handlers` slot docstring

The current text (roughly lines 127–134 of [src/engine/engine.lua](https://puck.uno/src/engine/engine.lua)) says:

> Hosts can append their own handlers post-construction with `table.insert(engine.row_handlers, MyHandler.new())`.

Replace with a reference to the API:

> Hosts extend the chain via `engine:add_handler(h)`, `engine:prepend_handler(h)`, `engine:remove_handler(h)`, `engine:clear_handlers()`, and inspect it via `engine:handlers()`. Direct mutation of the underlying array is not the sanctioned surface — the engine reserves the right to change the internal representation.

The `run_row` docstring (roughly line 276) that reads "registered into `self.row_handlers`" can be rephrased as "registered via `engine:add_handler`" or left as-is; the phrasing describes the effect, and the effect is unchanged.

### 4. (Optional aesthetic) `engine.new()` self-hosts on `add_handler`

The stock-handler wiring loop in `engine.new()` currently reads:

~~~lua
for _, handler in ipairs(handlers.stock_instances()) do
	table.insert(engine.row_handlers, handler)
end
~~~

Rewriting it as:

~~~lua
for _, handler in ipairs(handlers.stock_instances()) do
	engine:add_handler(handler)
end
~~~

means even the engine's own constructor uses the public API. Slightly slower per-handler (function-call overhead) but negligible for a stock roster of a handful of handlers, and it demonstrates the API is sufficient for all mutation the engine itself does. Recommend making this change.

### 5. Convert direct-mutation sites in shipping tests

[tests/main/lua/engine/test_dispatch.lua](https://puck.uno/tests/main/lua/engine/test_dispatch.lua) has four call sites to convert:

- Line 186: `table.insert(e.row_handlers, AlwaysTrue.new())` → `e:add_handler(AlwaysTrue.new())`
- Line 194: `e.row_handlers = {}` → `e:clear_handlers()`
- Line 206: `e.row_handlers = {}` → `e:clear_handlers()`
- Line 219: `e.row_handlers = { AlwaysRaise.new() }` → `e:clear_handlers(); e:add_handler(AlwaysRaise.new())` (or `e:clear_handlers():add_handler(AlwaysRaise.new())` using method chaining)

The stock-roster inspection test around line 265 that does `for i, actual_instance in ipairs(e.row_handlers) do` can either stay on direct read (it's read-only inspection) or convert to `e:handlers()`. Recommend converting — every access post-integration goes through the API, no exceptions in shipping code.

### 6. Remove the migrated methods from Larry

Delete the five method definitions and their docstrings from [sprints/larry/src/larry.lua](https://puck.uno/sprints/larry/src/larry.lua). Larry inherits them from Engine via the metatable chain — no shim needed.

Update the Larry module-header JSON `exports` hash to drop the five entries. Remove the `promotion_target` field (integration is done).

### 7. Move the handler-API tests from Larry to Engine

The 13 tests currently at the bottom of [sprints/larry/tests/test_larry.lua](https://puck.uno/sprints/larry/tests/test_larry.lua) (from "add_handler appends to row_handlers" through "handlers() returns a copy") belong on the Engine test suite once the methods live there. Two options:

- **(recommended)** Move them into a new file at `tests/main/lua/engine/test_row_handlers.lua`, converting `larry`/`Larry.new()` to `e`/`engine.new()`. Delete them from `test_larry.lua`. Larry gets test coverage for these methods for free via inheritance — the Engine tests exercise the same code path.
- **(alternative)** Leave them in `test_larry.lua` unchanged. They still pass (Larry inherits) but they're testing "an inherited method works on the subclass" rather than the direct feature, which is noise.

## Verification

After the moves, both test suites must pass with no regressions:

~~~
lua5.4 tests/run.lua
lua5.4 sprints/larry/tests/test_larry.lua
~~~

Then re-run the end-to-end `$x = 1` smoke path to confirm dispatch still works via the stock chain:

~~~
lua5.4 tests/main/lua/engine/test_first_variable.lua
~~~

(Or whichever file currently holds the first-variable end-to-end test.)

## Post-integration cleanup

- Close issue [#1622](https://github.com/mikosullivan/puck/issues/1622).
- Delete this integration plan file, or move to `sprints/larry/completed/` if the sprint is retaining historical plans.
- Update `sprints/larry/index.md` to move "Public API for the row-handler chain" out of "In flight."

## Sprint boundary

This is the integration. It touches shipping code (`src/engine/engine.lua`, `tests/main/lua/engine/test_dispatch.lua`). Requires the explicit trigger — "proceed with the integration" or "proceed with the assimilation" — before any of the above happens outside the sprint directory.
