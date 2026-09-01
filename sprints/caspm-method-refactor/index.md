~~~vibecode
{"vibecode": {
	"doc": "sprint-index",
	"sprint": "caspm-method-refactor",
	"role": "Sprint index for the CaspM method-dispatch refactor. Explores replacing today's nested-mc CaspM shape with a flat step-list shape where every step either produces a value (atom step) or dispatches a method (rv-based or explicit-receiver). The invariant we're chasing: every dispatch's receiver is a known object at dispatch time — either the previous step's rv or a resolvable atom. Substantial change; touches the normalizer, the engine walker, every handler, every test that asserts against CaspM. Working file `parse.casp` is a copy of production/tests/main/lua/transpiler/parse.casp so we can iterate on shape choices against real fixtures without disturbing production.",
	"status": "in progress"
}}
~~~

# caspm-method-refactor

Sprint for reshaping the CaspM into a flat step-list form.

## Working files

- [parse.casp](parse.casp) — snapshot of the production transpiler fixture corpus. Iterate on shape choices against real examples here.

## Design so far

- Frame ast becomes a flat list of steps (no outer statement-array wrapping).
- Two step kinds share a shape but differ by which keys they carry:
  - **Value step:** exactly one atom-key at top level (`scalar`, `var`, `sys`, `at`, `class`, ...); no `fn`. Produces a value into rv.
  - **Dispatch step:** `fn: NAME`; receiver source is either `rv:true` (chain from previous step's rv) or `rcvr: {atom}` (inline receiver — still on the table for compact-form dispatches).
- Every step sets rv.
- Args are closures — nested step-lists (form TBD for single-step args).
- The `syn: true` sugar marker carries through unchanged from the current design.

## Open questions

- **Atom keys top-level vs `rcvr:` wrapper.** Miko's lean: top-level (matches existing atom convention `{v:X}`/`{var:X}`/`{sys:X}` throughout CaspM). Perf negligible; consistency wins.
- **When a receiver combines with a dispatch on one step.** Is `{var:"foo", fn:"bar"}` a single combined step, or must it decompose to `[{var:"foo"}, {rv:true, fn:"bar"}]`? Strict split (always two steps) is more uniform; combined form is more compact for lookup atoms.
- **Arg shape.** Is a single-step arg a bare hash `{var:"x"}` or wrapped `[{var:"x"}]`? Uniform wrapping vs compact single-step form.
- **Statement boundaries.** In the flat model, do multiple commands cluster within one frame's ast (with implicit boundaries at atom-steps that reset rv), or spawn separate frames?

## Not decided yet

- Nothing is committed to production. This sprint is design exploration.
