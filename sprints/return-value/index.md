~~~vibecode
{"doc": "sprint-index", "sprint": "return-value",
	"role": "Explore modeling every operation in Caspian as producing a value that flows through a special variable (working name: `$_`). An assignment like `$x = 1` becomes two logical operations: `$_ = 1` (produce the value) and `$x = $_` (bind it). If it holds up, this unifies expression evaluation, statement dispatch, implicit-last-value return, and possibly chaining under one execution model. This sprint is brainstorm-mode — evaluate whether the reformulation actually simplifies things, sketch the failure modes, decide if it lands as a rewrite or a rejection.",
	"status": "brainstorm — no implementation, evaluating the shape"}
~~~

# return-value

Every operation in Caspian is (or could be) modeled as producing a value that flows through a special variable — working name `$_`. Assignment decomposes into two logical operations:

- `$_ = 1` — produce the value.
- `$x = $_` — bind it.

Whether `$_` is source-level visible (Perl / Ruby's `$_`) or purely an internal register (Ruby's implicit-return, or a CaspM-only artifact) is a design choice; both are on the table.

## Why this might simplify things

- **One execution model, not many.** Right now the handler chain in the engine dispatches on row shape (`variable-scalar`, `variable-object`, and eventually every other operator). If every row produces a value in `$_` and every binding reads from `$_`, the handler chain gets shorter — one path for "produce" and one path for "bind." Composed operations decompose in the normalizer, not in the interpreter.
- **Implicit-last-value return falls out for free.** Caspian already returns the last expression's value by default ([[feedback_caspian_return_idiom]]). Under the `$_` model, a function's return value IS its `$_` at the moment `%call.return` fires (or the frame reaches terminal). No special "the last row's value is the return" rule — it's the same rule that binds `$x`.
- **Chaining without intermediate names.** Pipelines, method chains, and the eventual `%stdout %<` shape can all read the current `$_` and produce a new one. No mandatory intermediate variable for every hop.
- **Debugger has a natural place to show "what just happened."** After every row dispatches, `$_` holds the value that row produced. A debugger view of the current frame can always display it, whether the source named a variable or not.

## Open questions

- **Scope of `$_`.** Per-frame? Per-statement (reset between rows)? Persisting across statements enables chaining but leaks state — a bug in row N shows up in row N+1 via an unexpected `$_`. Resetting per-statement is safer but kills the chaining benefit.
- **Compound expressions.** In `$x = 1 + 2`, does the normalizer produce `$_ = 1; $_ = $_ + 2; $x = $_` (fine-grained), or `$_ = 3; $x = $_` (evaluate first, then bind)? The fine-grained form is more uniform; the coarse form matches how the transpiler currently emits CaspM.
- **Interaction with functions and closures.** If a called function has its own `$_`, does the caller's survive? Presumably yes (per-frame); need to spell it out.
- **Source-level visibility.** If `$_` is nameable in source, you get Perl-style implicit-context idioms (love-them-or-hate-them) but you also give programmers a reliable read-back for the last operation's value. If it's CaspM-only, you get the internal simplification without the surface-language change.
- **Related to the existing `%call.return` design.** [[project_caspian_engine]] and the caller/return docs may already assume a model that's compatible or in conflict. Audit before committing to a direction.

## Not deciding yet

- Whether `$_` is a real variable name or a synthetic register with a different surface presentation.
- Whether this replaces the current row-shape handlers or supplements them.
- Whether the normalizer or the transpiler emits the two-op form.

## Status

**Brainstorm.** No code changes yet. Next step: sketch a small end-to-end trace of `$x = 1` and one more example (probably `$x = 1 + 2` or a function call) under the proposed model, then decide if it's worth prototyping in a follow-on sprint.
