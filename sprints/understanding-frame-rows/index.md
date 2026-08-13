~~~vibecode
{"doc": "sprint-index", "sprint": "understanding-frame-rows",
	"role": "Sprint on the frame-dispatch layer: teach engine:run_row how to actually execute the CaspM statement-rows sitting in a frame's ast. Today run_row only knows how to raise `unrecognized_row_head` for anything it sees; the sprint registers the first handlers (assignment, value atom, local binding) so the `$x = 1` walkthrough — 'first-variable' — runs end-to-end.",
	"status": "kicked off; scope captured"}
~~~

# understanding-frame-rows

## What a "row" is

CaspM is a JSON tree. At the top level it's a **list of statements**. Each statement is itself a **list of atoms** — and the codebase (and [caspianj spec](https://puck.uno/requirements/caspianj#casp-m)) calls one of those inner lists a **row**.

Take the Caspian source:

~~~caspian
$x = 1
~~~

The transpiler produces CaspJ; the normalizer collapses it to CaspM. In CaspM it looks like this (as Lua tables — CaspM is JSON that Lua deserializes to nested tables):

~~~lua
{                                                        -- outer list: one entry per statement
    {{in = "as"}, {var = "x"}, {value = 1}}              -- one row: this is the whole `$x = 1` statement
}
~~~

The outer list has one element. That element — `{{in = "as"}, {var = "x"}, {value = 1}}` — is the **row** for `$x = 1`. It has three **atoms**:

- `{in = "as"}` — the norm-CaspM "assignment" internal-primitive atom. Says "this row is an assignment."
- `{var = "x"}` — a var atom naming the target of the assignment.
- `{value = 1}` — a value atom holding the number to assign.

A program with three statements has three rows. A frame's `ast` column holds one of these outer lists — the program (or program fragment) that frame is executing.

## What "dispatching a row" means

The engine can't just "run" a row. Each row could be an assignment, a call, an if/loop opening, a bareword command, anything. The engine has to **look at the row's shape and pick the handler function that knows how to execute that shape.**

That look-and-pick step is dispatch. Nothing Lua-specific — it's the standard interpreter pattern any language would use. Concretely, [engine:run_row(row)](https://puck.uno/src/engine/engine.lua) reads the first atom of the row (the **head**), looks its key set up in a handler table, and calls the matching function:

- Head is `{in = "as"}` → call the assignment handler.
- Head is `{in = "fc"}` → call the function-call handler.
- Head is `{bwc = "puts"}` → call the puts bareword handler.
- Head is anything the table doesn't know → raise `unrecognized_row_head` with the head's key set in the message.

Today only the last branch exists. There are no registered handlers for `{in = "as"}` or anything else — so `run_row` on the first statement of ANY program raises `unrecognized_row_head`. The engine can bootstrap, push frame 0, fetch the ast, reach dispatch — and then immediately trip on the very first row because nothing's registered to handle it.

## Why the sprint exists

To close that gap, one row shape at a time. Concretely, the sprint targets the **first-variable walkthrough**: run `$x = 1` end-to-end, from `engine:load('$x = 1')` through `engine:run()` returning cleanly, with the assignment actually landing in the CVM (a scalar row for `1`, a local binding for `x` in frame 0's locals bucket, refs wiring them together).

Getting there means registering at minimum:

- **Assignment dispatch** — handler for `{in = "as"}` row heads. Reads the target (var atom) and the value (value atom or nested-atom expression) and orchestrates the writes below.
- **Value-atom evaluation** — small dispatcher that turns a value-position atom into an object pk. `{value = 1}` → `cvm:add_scalar('n', 1, owner_role) → pk`. Later expands to handle vars, calls, etc.
- **Local binding** — plumbing to associate a name in a frame's locals with an object pk. Uses `frame:ensure_locals` + `frame:set_local_to_scalar` (both exist in the CVM data-access layer already).

Each of those is a small piece of code. The building blocks — `add_scalar`, `add_ref`, `ensure_locals`, `set_local_to_scalar` — all exist on the [cvm class](https://puck.uno/src/engine/cvm/init.lua). What's missing is the engine-side wiring that takes a row apart and calls into them.

## Deliverables (rough)

1. **Row-head dispatch table.** Something like `M.row_dispatch = {as = M.dispatch_as, fc = M.dispatch_fc, ...}` (or a keyed lookup on the head atom). Extensible — adding a new construct is registering one entry.
2. **`dispatch_as` (the assignment handler).** Reads the assignment row's atoms, evaluates the RHS via the value-atom dispatcher, binds the result into frame 0's locals.
3. **Value-atom dispatcher.** Small function that switches on a value-position atom's keys. Handles `{value = X}` (produce a scalar); grows to handle `{var = X}` (read a local), calls, etc.
4. **`first-variable` end-to-end test.** Load `$x = 1`, run(), assert frame 0's locals bucket has `x` pointing at a scalar row with value 1.

Non-goals for this sprint:
- Reads (`$x` lookup) beyond what the first-variable target needs — the walkthrough is single-assignment.
- Function calls, if/loop, bareword commands. Those get their own sprints once dispatch scaffolding is in place.
- Error surfaces beyond the existing `unrecognized_*` family.

## Status

**Sprint kicked off, scope captured.** No sprint-scoped code or tests yet.
