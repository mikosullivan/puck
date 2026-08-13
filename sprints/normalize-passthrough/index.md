~~~vibecode
{"doc": "sprint-index", "sprint": "normalize-passthrough",
	"role": "Sidequest: make CaspJ a strict superset of CaspM so the normalizer is a passthrough when handed already-normalized input. Prevents silent corruption when a caller confuses the two similar-looking JSON formats.",
	"status": "kicked off; not implementing yet",
	"parallel_to": "sprints/frame-0",
	"touches_module": "src/engine/normalize.lua",
	"key_concepts": ["idempotence", "strict_superset", "input_tolerance"]}
~~~

# normalize-passthrough

Sidequest sprint. Runs in parallel with [frame-0](../frame-0/); does not block it.

## Goal

**`normalize(caspM) == caspM`** for every valid CaspM. Feeding already-normalized JSON to the normalizer round-trips cleanly — the output is byte-for-byte the same shape as the input (structural equality; a fresh table, not the same reference).

## The problem

CaspJ (the transpiler's output) and CaspM (the normalizer's output — the compact form the engine walks) are both JSON with similar shapes. They're easy to confuse by eye. If a caller hands CaspM to `normalize()` thinking it's CaspJ, three outcomes are possible today, and only one is safe:

- **Safe:** Return the same CaspM unchanged. (What we want.)
- **Corrupting:** Apply a rewrite twice or in the wrong direction, producing garbage that looks superficially like CaspM but isn't.
- **Erroring:** Fail loudly on some construct that the normalizer doesn't recognize when it's already in normalized form.

We want option 1 always. That means the normalizer's rewrites must all be no-ops on already-normalized input.

## The design principle

**CaspJ is a strict superset of CaspM.** Every valid CaspM is also a valid CaspJ.

- The transpiler emits verbose CaspJ — a proper subset of the CaspJ universe (with `line`, `value`, `body`, `args`, `params`, `closure`, cosmetic flags, comment atoms, documentation / vibecode BWC rows, statement-prefix atoms in unfolded form, pipe operators as `{op: '|'}`, etc.).
- CaspM is a different subset of the CaspJ universe — compact keys (`l`, `v`, `bd`, `a`, `pm`, `cl`, ...), collapsed statement prefixes (`{in: 'as'}`, `{in: 'fc'}`), no comments, no docs, no cosmetic flags, pipe operators already desugared to nested calls.
- The union is CaspJ. The normalizer maps CaspJ → CaspM. On a CaspM input, every rewrite is already done, so every rewrite is a no-op, and the output equals the input.

## What the normalizer needs to handle idempotently

Each of these transformations needs an audit for "what happens if the input already has the target shape?"

- **Compact-key rewrite.** `line` → `l`, `value` → `v`, `body` → `bd`, `args` → `a`, `params` → `pm`, `closure` → `cl`, `fetch` → `ft`, `array` → `ar`, `varobj` → `vo`, `begin_end` → `be`. On input that already carries the short key, leave it alone. On input that carries both (shouldn't happen; would be a caller bug), decide which wins and fail loudly if it can't.
- **Statement-prefix collapse.** `[scope, setvar, ...]` → `[{in: 'as'}, ...]`; function-call rows → `[{in: 'fc'}, ...]`. On input that already starts with `{in: 'as'}` / `{in: 'fc'}`, leave the row alone.
- **Call-atom shape.** `{fn, rc, a?, kw?, blocks?}` for amp / dot-method / binop calls. On input that already has this compact shape, leave it alone.
- **Comment atoms.** Drop unconditionally. No-op on CaspM (which has none).
- **Documentation / vibecode BWC rows.** Drop unconditionally. No-op on CaspM.
- **Cosmetic flags.** `base` / `dq` dropped unconditionally. No-op on CaspM.
- **Trailing sole-`line` statement-position line metas.** Dropped unconditionally. No-op on CaspM (already dropped).
- **Pipe operator desugar.** `{op: '|'}` / `{op: '|&'}` → nested calls. On input with no pipe atoms, no-op.
- **General binop rewrite.** `{op: '+'}` etc. → two-element call row. On input already in call-row form, leave alone.
- **Bareword-command atoms (`{bwc: name}`).** Pass through unchanged in V1. Already a no-op.

## Sprint deliverables (rough shape, not settled)

1. **Audit** — walk each transformation above against a mental CaspM sample, confirm idempotence. Where behavior on CaspM input is unclear, either infer from code or add a targeted probe.
2. **Test suite** — a Lua test that takes every CaspM fixture in the existing test corpus and asserts `normalize(caspM)` returns a table structurally equal to `caspM`. Runs alongside `parse-spec.lua` / `parse-lines-spec.lua`.
3. **Fixes** — for any transformation that isn't idempotent, patch `normalize.lua` so it is.
4. **Doc** — one paragraph in `normalize.lua`'s module docstring stating the passthrough invariant explicitly, and a matching note in the `requirements/` spec for the transpiler / normalizer pipeline.

## Out of scope

- The transpiler itself. This sprint is only about the normalizer's input tolerance. If the transpiler someday learns to accept CaspM as a shortcut, that's a different sprint.
- Detection at the boundary. We're not adding "is this CaspJ or CaspM?" runtime checks — the design principle IS that the normalizer doesn't need to know.
- Format-tagging. No wrapper envelope, no version byte, no `"__format": "caspm"` marker. The whole point is that idempotence removes the need to tag.

## Status

**Sprint kicked off, no work done yet.** No sprint schema fork, no code changes, no tests written. Frame-0 continues as the primary sprint; this one waits its turn.
