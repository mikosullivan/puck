~~~vibecode
{"doc": "sprint-index", "sprint": "expressions",
	"status": "track 1 landed 2026-08-24 — transpiler bare-expression fallback + `frames_child_delete_propagates_rv` schema trigger + design docs are in production. Track 2 (postnormalize + build-frames machinery) still resident in sprint pending its own integration.",
	"role": "Design for how Caspian evaluates expressions. The core decision: `.` is Caspian's only binary operator; every other apparent binary operator (`+`, `<`, `||`, `&&`, `?:`, etc.) is syntactic sugar over a method call via `.`. Every command reduces to one or more method_call invocations. Args are (conceptually) closures the walker wraps at the call site; a callee's parameter signature dictates which are auto-invoked (eager) and which pass through unchanged (lazy). Frame chain is the whole evaluation state; no eval placeholders, no walker path pointers, no evals hash. Related sprints [method-call](https://puck.uno/sprints/method-call/) and [lazy-params](https://puck.uno/sprints/lazy-params/) hold specific pieces."}
~~~

# Expressions

Design for how Caspian evaluates expressions. Every command reduces to a tree of method calls; every method call goes through one primitive dispatch (`method_call`); args are closures the walker wraps at the call site.

## Landed to production

Track 1 has been integrated. The design docs, transpiler fallback, and schema trigger live in production:

- **Design** — [requirements/expressions/](https://puck.uno/requirements/expressions/) covers the evaluation model, the walker algorithm, the frame-advancement rules, and every primitive-command spec (method-call, assign, if, while, or, and).
- **Transpiler** — bare-expression fallback in `production/src/engine/transpiler.lua`. `'foo'`, `1`, `$x`, `1 + 2` now parse as valid statements. Bareword commands (leading token starts with a letter or underscore) still take the fast path.
- **Schema** — `frames_child_delete_propagates_rv` trigger in `production/src/engine/cvm/sqlite/schema.sql` (v12.1). When a nested frame reaps, its rv propagates to the parent's rv slot via bucket-key. Cap-exempt. Materializes the parent's bucket on demand.

## Still in sprint

Track 2 — the evaluation-model machinery — is not yet integrated. The following files remain resident in the sprint:

- [src/postnormalize.lua](./src/postnormalize.lua) — the sprint's postnormalize pass that rewrites CaspM into the evaluation-model shape (`.obj.<name>` for operators, `engine.<name>` for bareword commands).
- [src/build-frames.lua](./src/build-frames.lua) — build the initial frame chain from a normalized CaspM row.
- [src/demo.lua](./src/demo.lua) — a demo runner that shows postnormalize's before-and-after on a set of fixture sources.
- [caspm-status](./caspm-status) — inventory of what the current transpiler + normalizer produce and what still needs adjusting.
- [integration](./integration) — the two-track integration plan; Track 1 is done, Track 2 is next.
- [report](./report) — sprint report.

## Related sprints

- **[method-call](https://puck.uno/sprints/method-call/)** — spec for the engine-primitive dispatcher itself.
- **[lazy-params](https://puck.uno/sprints/lazy-params/)** — the `&` sigil for declaring lazy parameters in function signatures.
