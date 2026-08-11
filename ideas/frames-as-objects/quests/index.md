# Quests

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_quests",
	"role": "index of parallel workstreams inside the frames-as-objects brainstorm. `main` holds the primary folding — schema, source, examples, tests. Each sidequest is a design change being carried alongside the folding: not strictly required by it, but landed here because it was the natural place. When frames-as-objects gets promoted to requirements/, every quest under this dir rides along.",
	"status": "living index"
}}
~~~

Parallel workstreams inside the frames-as-objects brainstorm. `main` is the primary folding; the sidequests are design changes riding along that will promote to `requirements/` at the same time.

## Current quests

- [main](https://www.puck.uno/ideas/frames-as-objects/quests/main/) — the primary folding: schema at `main/src/cvm.sql`, Lua source at `main/src/`, worked walkthroughs at `main/examples/`, tests at `main/tests/`
- [debug column on objects and refs](https://www.puck.uno/ideas/frames-as-objects/quests/debug-columns/) — permanent human-readable row-label field on both tables

## Promotion order

Every quest here carries the same coordination rule. When frames-as-objects promotes to `requirements/`, apply the quest in this order:

1. **Update `requirements/` docs first** — every doc that mentions the affected surface.
2. **Update the reference implementation** at `src/engine/mvm.sql`.
3. **Update the engine tests** at `tests/main/lua/engine/`.
4. **Run all tests** (engine tier + trivet tier + brainstorm `view-indexes.lua`) and confirm each passes.

Doing them out of order — code before docs, tests before code — leaves the codebase transiently inconsistent and produces spurious test failures. Docs first.
