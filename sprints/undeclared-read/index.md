~~~vibecode
{"doc": "sprint-index", "sprint": "undeclared-read",
	"role": "Reading a variable that was never set MUST raise, not return null. Caspian requires variables to be initialized before use — the assignment path (`$x = ...`) creates a binding; the read path (`$x` in any expression position) must fail loudly when no binding exists. Distinct from the assign path, which is allowed (and required) to create the binding on first `$x = ...`. Spec is settled at [syntax/variables-and-assignment](https://puck.uno/production/requirements/syntax/variables-and-assignment) — reading an undeclared variable raises `undeclared-variable`. Sprint's job: make sure whatever scope-get primitive lands actually raises on miss instead of returning null.",
	"status": "seed — problem captured, spec confirmed, not yet implemented. Depends on the expressions sprint's Track 2 (real read handler) landing before there's code to change."}
~~~

# undeclared-read

Reading `$x` when no binding exists raises. Setting `$x` for the first time creates the binding. GET and SET have different miss semantics: GET must raise, SET must create.

## The rule

From [syntax/variables-and-assignment](https://puck.uno/production/requirements/syntax/variables-and-assignment) — settled spec, in the testing section:

> Reading an undeclared variable raises — `$never_set` at the top of a fresh scope raises undeclared-variable.

Two related shapes in the same spec also raise:

- `$never += 1` — compound assignment on an undeclared variable raises `undeclared-variable`.
- `$foo++` — postfix increment on an undeclared variable raises (desugars to `$foo = $foo + 1`; the RHS read fails first).

The error name is `undeclared-variable`. Distinct from `null` — a variable that was declared and assigned `null` reads as `null` (fine). A variable that was never assigned raises.

## Why "raises" and not "returns null"

Two names look the same from a distance and are actually different states:

- **`$x = null`, then read `$x`** → the binding exists and holds null. Read returns null.
- **Never set `$x`, then read `$x`** → no binding. Read raises `undeclared-variable`.

Returning null for both erases the distinction. That means:

- **Typos silently compile.** `$account_balnace` never fires an error, and the caller gets null where they expected a number.
- **`$x.method` looks like a null-dispatch bug** instead of the actual bug — the earlier line that mistyped `$x`.
- **`if $x` is ambiguous.** Was the flag set false, or never set? Behavior differs; the reader can't tell from the code.

Failing loudly at the read site names the bug directly. Same principle as [feedback/fail-loudly-early](https://puck.uno/production/requirements/errors/) — raise at the earliest layer that can detect.

## The distinction between GET and SET

The scope machinery has two entry points and they must diverge on miss:

- **`scope:get(name)`** — miss raises `undeclared-variable`. Never returns null-for-not-found. Null values that ARE present in the scope return null normally.
- **`scope:set(name, value)`** — miss creates the binding at the current scope. This is how a variable gets declared in the first place.

The two are asymmetric on purpose. `set` is the only way a name enters scope; `get` refuses to invent a null for anyone.

## What likely needs to change

No scope-GET primitive exists in production yet — the current handlers only cover the assign path ([handlers/variable-scalar](https://puck.uno/production/src/engine/handlers/variable-scalar.lua)). When the read primitive lands (probably as part of the expressions sprint's Track 2, when real `method_call` dispatch reads its receiver from scope), it must obey the rule.

Two places the check plausibly lives:

- **In the read primitive itself** — the Lua function that walks the scope chain returns a sentinel-or-nil-not-found on miss and the caller raises. Cleanest single point.
- **At the SQL layer** — the `frame_scoped_vars` view lookup returns no rows on miss; the caller (in Lua) raises. Same effect; the raise site is one hop away from the SQL.

Either works. Sprint decides at implementation time; both preserve the observable rule.

## What this sprint does NOT do

- **Doesn't design the read handler itself.** That's the expressions sprint's Track 2 or a follow-on. This sprint constrains what that handler must do on the miss path.
- **Doesn't touch the assign path.** `$x = ...` on an undeclared name continues to create the binding — that's not a miss, that's a declaration.
- **Doesn't decide the Caspian-level error class shape.** Whether the raise carries a specific class (e.g. `UndeclaredVariable`) or a generic error with an id string is a language-level decision that lives elsewhere.
- **Doesn't cover `%foo` system-method reads.** System methods have their own resolution path; not in scope here.

## Test approach

Once a read primitive exists:

- **Bare read of undeclared** — a fresh program body containing just `$never_set` raises `undeclared-variable` with the name in the error message.
- **Read after declared-but-null** — `$x = null; $x` returns null, does NOT raise.
- **Read after a rollback** — mid-expression raise leaves the LHS undeclared if it wasn't already declared (per the existing spec at line 120). A subsequent read of that name raises.
- **Compound-assign on undeclared** — `$never += 1` raises `undeclared-variable`.
- **Same name in different frames** — declaring `$x` in a nested frame does NOT retroactively declare `$x` for the parent's later read. The parent's read still raises.
- **Read of a name shadowed by an inner declaration then unshadowed** — if the frame that shadowed reaps, the parent's later read of the name still resolves to the parent's own binding (if any). If the parent never had one, it still raises.

## Related

- [production/requirements/syntax/variables-and-assignment](https://puck.uno/production/requirements/syntax/variables-and-assignment) — spec that already requires the raise.
- [production/src/engine/handlers/variable-scalar.lua](https://puck.uno/production/src/engine/handlers/variable-scalar.lua) — the assign-side handler; the read-side counterpart doesn't exist yet.
- [production/src/engine/cvm/sqlite/frame.lua](https://puck.uno/production/src/engine/cvm/sqlite/frame.lua) — houses `own_scope` / `ensure_own_scope`; the multi-scope read path noted there as landing "with the closure work" is the one this sprint constrains.
- [production/src/engine/cvm/sqlite/schema.sql](https://puck.uno/production/src/engine/cvm/sqlite/schema.sql) — `frame_scoped_vars` view is the raw lookup mechanism; miss = zero rows returned.
- [sprints/expressions](https://puck.uno/sprints/expressions/) — Track 2 needs a real read primitive; this sprint sets the contract for its miss path.
