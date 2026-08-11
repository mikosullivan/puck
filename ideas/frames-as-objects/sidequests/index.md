# Sidequests

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_sidequests",
	"role": "meta-page for design decisions being carried alongside the frames-as-objects brainstorm. Neither sidequest is strictly required by the folding, but each landed here because it was the natural place. Each sidequest describes what changed, what's affected, and the promotion-coordination rule for when frames-as-objects gets folded into requirements/.",
	"status": "living index"
}}
~~~

Design changes carried alongside the frames-as-objects brainstorm. Neither is strictly required by the folding, but each landed here because it was the natural place, and each will ride along when the brainstorm gets promoted to `requirements/`.

## Current sidequests

- [refs — renamed from relationships](https://www.puck.uno/ideas/frames-as-objects/sidequests/refs-rename) — schema rename affecting the table, column, triggers, indexes, and error ids
- [debug column on objects and refs](https://www.puck.uno/ideas/frames-as-objects/sidequests/debug-column) — permanent human-readable row-label field on both tables

## Promotion order

Every sidequest carries the same coordination rule: when frames-as-objects promotes to `requirements/`, apply the sidequest in this order:

1. **Update `requirements/` docs first** — every doc that mentions the affected surface.
2. **Update the reference implementation** at `src/engine/mvm.sql`.
3. **Update the engine tests** at `tests/main/lua/engine/`.
4. **Run all tests** (engine tier + trivet tier + brainstorm `view-indexes.lua`) and confirm each passes.

Doing them out of order — code before docs, tests before code — leaves the codebase transiently inconsistent and produces spurious test failures. Docs first.
