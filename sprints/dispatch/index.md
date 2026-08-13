~~~vibecode
{"doc": "sprint-index", "sprint": "dispatch",
	"role": "Build the row-head dispatch mechanism `M:run_row` uses to route CaspM rows to handlers. Design: a chain of responsibility — an array of handler functions, each of which inspects a row, decides whether to handle it, and (if it does) executes it. Registration is `table.insert` — no keyed routing table to maintain, no rebuild-the-logic-tree tax when adding handlers. Also a real extensibility affordance: outside engine writers can plug in their own handlers (their own AST shapes) without engine-side changes.",
	"status": "code + tests landed in sprint; implementation plan in progress",
	"depends_on": [],
	"blocks": ["first-variable"]}
~~~

# dispatch

**Current phase: working on the [implementation plan](./integration).** The sprint's code and tests are landed under `src/` and `tests/`; the next move is settling how it integrates into shipping. See [integration.md](./integration) for the plan-in-progress (still has an open decision about whether integration installs the mechanism only or also wires it into `M:run_row`).

## Overview

Row-head dispatch scaffolding — the shape `M:run_row` uses to route CaspM statement rows to the code that executes them.

### The pattern

**Chain of responsibility.** A plain array of handler INSTANCES (see [The Handler class](#the-handler-class) below for what those are). Each row that comes into `M:run_row` gets offered to each handler in order until one claims it.

~~~lua
function M:run_row(row)
    for _, handler in ipairs(self.row_handlers) do
        if handler:handle(self, row) then
            return
        end
    end

    error("unrecognized_row_head: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {" .. atom_keys(row[1]) .. "}")
end
~~~

Each handler is an instance whose `:handle(engine, row)` method inspects the row, decides whether it recognizes the shape, and either handles it (returns `true`) or passes (returns `false`). Loop stops at the first `true`.

### The Handler class

Handlers are instances of a `Handler` class (or subclasses of it), not bare functions. The base class defines one overridable method — `:handle(engine, row) -> true | false | (raise)` — and subclasses override to match specific row shapes and execute them.

Full definition + rationale + subclass pattern live in [`src/handler.lua`](./src/handler.lua). Test-support subclass example: [`tests/always_true.lua`](./tests/always_true.lua).

### Return-value convention

**Handlers return `true` or `false`. Nothing else.** `true` means the handler recognized the row and executed it, with no further detail about what happened. `false` means the handler didn't recognize the shape — the loop moves on to the next handler.

No multi-return, no result-carrying truthy value, no sentinel table. Just a boolean. If a handler produces state the caller needs to see, that state lives on the engine or in the DB — not in the dispatch return.

The loop iterates until one handler returns `true`; then stops. If no handler returns `true`, the fallback raises `unrecognized_row_head`.

### Error reporting

If a handler hits a problem while executing, it raises a Lua exception; the chain loop doesn't catch it, so the raise propagates out through `run_row` and `run()` to the caller. The boolean return is only for "did I match this shape?" — never overloaded to carry failure info.

### What this simplifies

**Registration.** Adding a new handler is `table.insert(self.row_handlers, new_handler)`. Nothing else. No keyed table to update, no switch-statement branch to add, no logic-tree to rebuild each time.

**Handler independence.** Each handler is self-contained. It knows its own shape check and its own execution logic. Handlers don't have to fit a shared schema of "key extraction happens here, dispatch happens there." A single handler can match multiple related row shapes (`{in: 'as'}` and `{in: 'as', kw: ...}`) by branching internally.

**Ordering is explicit.** Array-position is precedence. Specific handlers can be inserted before general ones. With keyed dispatch you'd have to bake specificity into the keys themselves.

### The hidden-door angle

This is a genuine extensibility affordance, not aesthetic. Outside engine writers can:

- Append their own handler to `row_handlers` before calling `run()`.
- Handle CaspM shapes the canonical engine doesn't know about.
- Effectively extend the language by adding row-head shapes and the handlers that execute them.

Pairs cleanly with the transpiler slot on the engine (which lets alternate frontends produce whatever CaspJ they want): alternate frontends produce CaspM that alternate handlers execute. Both seams line up on the same design intent.

Real double-edge worth naming: since the handler array IS the language's semantics, replacing a handler changes what CaspM means to this engine instance. Someone could swap `dispatch_as` for a variant that logs every assignment, or one that rejects assignments to certain names, or one that does something entirely different. That's the "expand the language" power AND the "shoot yourself in the foot" affordance in the same shape. Sprint doesn't try to gate this; just calling out the property.

### Tradeoffs

- **Performance.** Every row walks the array until a handler matches. Keyed dispatch would be O(1) per row; chain is O(N) worst case in the number of handlers. Doesn't matter at walking-skeleton scale. If dispatch performance ever becomes a bottleneck, a keyed fast-path can layer over the chain (check the table first, fall through to the chain on miss) without changing the extensibility model.
- **Silent misses.** If no handler in the chain matches, the loop just ends. Handled by making the fallback raise explicit — `error("unrecognized_row_head: ...")` after the loop, as shown above. Chain-of-responsibility patterns often silently drop unhandled cases; we're specifically NOT doing that.
- **Two-handlers-both-claim.** First one wins by array order. Usually fine. Occasionally you want a "one and only one handler matches" invariant; this shape doesn't enforce it. Deferred until a real ambiguity surfaces.

### Interaction with `M:run_row`'s current shape

Today's `M:run_row` at [src/engine/engine.lua](https://puck.uno/src/engine/engine.lua) has hardcoded branches — checks for `{bwc: name}` heads, routes to `run_bwc`, raises `unrecognized_row_head` otherwise. Under this sprint's design, that hardcoded branching goes away; the bwc branch becomes one handler in the chain (registered at engine construction time, probably alongside whatever other stock handlers ship with the engine).

### Storage — instance slot vs class table

Small design choice worth naming: does `row_handlers` live on the engine INSTANCE (`self.row_handlers`) or on the CLASS TABLE (`M.row_handlers`)?

- **Instance slot** — each engine has its own array; hosts can register per-engine handlers without affecting other engines. Extensibility is per-engine.
- **Class table** — all engines share the same array; a registered handler affects every engine constructed after registration. Simpler but couples engines.

Instance slot is more flexible; class table is smaller. Not decided; likely instance for consistency with the other host-wiring slots (`stdout`, `debugger`, `transpiler`, `process_pk`, `caspm`).

### What this sprint does

**Make sure the dispatch function works the way this doc describes.** Sprint-scoped only — build the mechanism in [sprints/dispatch/src/](./src/), verify it with tests in [sprints/dispatch/tests/](./tests/). Shipping isn't touched by this sprint.

Concretely, that's:

1. A standalone dispatch function that takes a handlers array + a row, walks the array, calls each handler in order, and returns/raises per the semantics above (first `true` wins, no `true` = raise `unrecognized_row_head`, handler raise propagates).
2. Tests exercising the mechanism directly: mock handlers wired into a mock array; verify multi-handler registration, ordering, first-wins, the fallback raise on no-match, and that a handler raise propagates through the walk.

That's the entire sprint. No shipping code touched.

## Concrete changes

Four files land inside the sprint. Nothing else moves.

### The Handler class (base + test-support subclasses)

Lands at [`sprints/dispatch/src/handler.lua`](./src/). One file, four classes:

- **`Handler`** — the base class. Single overridable method `:handle(engine, row)` returning `false` by default. Concrete subclasses override.
- **`Handler.AlwaysTrue`** — test-support subclass; `:handle` always returns `true`.
- **`Handler.AlwaysFalse`** — test-support subclass; `:handle` always returns `false`.
- **`Handler.AlwaysRaise`** — test-support subclass; `:handle` always raises.

The three test-support subclasses are baked into `handler.lua` for now so tests can exercise the dispatch mechanism without needing a separate test-support file. They'll move out to their own file when the sprint's test infrastructure scales up.

### The dispatch function

Lands at [`sprints/dispatch/src/dispatch.lua`](./src/). Sketched signature:

~~~lua
local function dispatch(handlers, row, ...)
    for _, handler in ipairs(handlers) do
        if handler:handle(row, ...) then
            return
        end
    end

    error("unrecognized_row_head: cannot dispatch statement — no rule handles a row starting with an atom whose keys are {" .. atom_keys(row[1]) .. "}")
end

return dispatch
~~~

Takes the handlers array (of instances), the row, and any extra args (variadic — forwarded to each handler's `:handle` so handlers can receive engine / context / etc. without dispatch knowing what those are). Returns nothing on success. Raises `unrecognized_row_head` when no handler claims the row. Handler raises propagate — dispatch doesn't catch.

### The test suite

Lands at [`sprints/dispatch/tests/test_dispatch.lua`](./tests/). Uses `Handler.AlwaysTrue`, `Handler.AlwaysFalse`, and `Handler.AlwaysRaise` as the test-support handlers. Six tests:

1. **Empty handlers array raises `unrecognized_row_head`.** No handlers, no `true` return, fallback fires.
2. **`AlwaysTrue` alone: dispatch returns cleanly.** Loop stops on the first `true`.
3. **`AlwaysFalse` alone: raises.** Handler declined, no other handlers, fallback fires.
4. **`AlwaysFalse` then `AlwaysTrue`: dispatch returns cleanly.** Proves fall-through — false doesn't stop the walk; a later true does.
5. **`AlwaysRaise` alone: raise propagates.** Dispatch doesn't catch; raise reaches the test via `pcall`.
6. **`AlwaysTrue` then `AlwaysRaise`: dispatch returns cleanly.** Proves first-wins — the `AlwaysRaise` never fires because the earlier `AlwaysTrue` already claimed the row.

## Status

**Sprint code + tests landed** — [`src/handler.lua`](./src/handler.lua) (base class + three test-support subclasses), [`src/dispatch.lua`](./src/dispatch.lua), [`tests/test_dispatch.lua`](./tests/test_dispatch.lua) (9 tests, all passing). **Currently working on the [implementation plan](./integration)** — see there for what promotes into shipping and the open decision on wiring shape.
