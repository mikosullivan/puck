# Frames as objects — promoted

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects",
	"role": "stub. The frames-as-objects design has been promoted to requirements/ and shipping code. This page points at where the work landed. Only the walkthroughs at examples/ remain here — kept as reference material for the design's motivation."
}}
~~~

The frames-as-objects design is settled and shipped. Frames became `objects` rows with `primitive = 'f'`; `ast` is biconditional with that primitive; the standard object-graph GC handles closure lifetime naturally.

**Where it landed:**

- [requirements/cvm/](https://www.puck.uno/requirements/cvm/) — spec.
- [src/engine/cvm/](https://www.puck.uno/src/engine/cvm/) — schema, connection-open, data-access engine, wrapper classes.
- [tests/main/lua/engine/](../../tests/main/lua/engine/) — `test_cvm.lua`, `test_cvm_engine.lua`, `test_view_indexes.lua`.
- [benchmarks/](../../benchmarks/) — `bench_bucket`, `bench_stack`, `bench_engine`, `bench_frame_locals`.

**What stayed here:**

- [examples/](examples/) — three walkthroughs (`end-of-bootstrap`, `first-variable`, and the deliberately-placeholder `closure`). Useful reference material for the design's motivation and the shape of the writes each dispatch step lands. Not part of the promoted spec.

**Deferred to a later slice:**

- Closure capture mechanism (`lexical_parent` removed; will return under a dedicated closure design that also reconciles with `requirements/lua/scope.md`'s scope-agg proposal).
- Frame-caller pointer (`frame_parent` was implemented and pulled back as premature optimization; may return with the closure design).
- Runtime dispatch loop (`frame:run`, engine main loop, shutdown) — the engine at promotion time is a data-access layer only.
- Pop semantics — how a frame's stack coordinates (`process` / `idx` / `stmt_idx`) transition to null on return.
