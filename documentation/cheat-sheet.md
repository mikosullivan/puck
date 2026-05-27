# Cheat sheet

~~~json
{"vibecode": {
	"doc": "cheat_sheet",
	"role": "compact reference to settled design decisions that span many docs; consult before making design claims about object model, IDs, dispatch, equality, skeletor fields, or engine-only classes; when this disagrees with a canonical doc, the canonical doc wins",
	"audience": "Claude (primary), Miko (secondary as a settled-decisions index)",
	"format": "topic_groups_with_one_line_facts_plus_links_to_canonical_locations",
	"maintenance": "append_when_new_decisions_land; update_when_existing_decisions_change",
	"not_the_spec": "this_file_is_a_finder_not_the_authority"
}}
~~~

This is a compact reference to settled design decisions that span many docs. When a question lands and you're not sure of the current state, check here first. **This file is a finder, not the authoritative spec.** Each entry points to where the full context lives.

When facts here disagree with the canonical doc linked from the entry, the canonical doc wins — and this file is out of date and should be updated.

## Object model

- **Object shape**: `{classes, bucket}`. `classes` is a hash keyed by platter ID; each platter is `{class, bucket, sticky?, active?}`. See [base-class-use.md § Per-platter buckets](ideas/base-class-use.md#per-platter-buckets).
- **Bucket invariants**: always a hash, never a scalar/array/null; no reserved keys, anywhere. Top-level bucket and each platter bucket follow the same rules. See [base-class-use.md § Bucket policy](ideas/base-class-use.md#bucket-policy).
- **Aslan exception**: Aslan deliberately uses the simpler `{type, owning_role, payload}` shape — walking-skeleton, not platter model. The platter model arrives in a later slice. See [aslan.md](development/v1/aslan.md), [decisions.md § Engine and runtime](development/v1/decisions.md#engine-and-runtime).
- **Pinned vs mutable regions**: pinned platters at the top, fixed position, engine-managed; mutable region below, where `.classes.add` inserts. See [base-class-use.md § Pinned and mutable regions](ideas/base-class-use.md#pinned-and-mutable-regions).
- **Method resolution**: walk platter stack top-to-bottom × each platter's class's inheritance chain, with a per-dispatch visited set. First match wins for unicast; all matches fire for multicast. See [base-class-use.md § Method resolution](ideas/base-class-use.md#method-resolution).

## IDs and the global sequence

- **One global counter mints every unique string** in the engine — object IDs, platter IDs, future bookkeeping. Integer-string format (`"1"`, `"2"`, ..., `"99"`, `"100"`, ...), stable within a program's lifetime, not stable across runs. See [sequence.md § Engine use](caspian/built-in-classes/sequence.md#engine-use), [references.md § Object IDs](caspian/skeletor/references.md#object-ids).
- **The class is `puck.uno/sequence`**: array of digit-strings + transitions hash + lazy string cache. Engine's hot-path minter bypasses the class entirely (closed-over Lua local). See [sequence.md § Implementation](caspian/built-in-classes/sequence.md#implementation).
- **Engine holds a jailed sequence** with `(:next, :peek)` — no `.reset`. See [sequence.md § Engine use](caspian/built-in-classes/sequence.md#engine-use).
- **Future compaction**: `%utils.sequence.compact(threshold)` is V1.1+, not V1. See [#345](https://github.com/mikosullivan/puck/issues/345).

## Skeletor fields

- **In skeletor**: `roles` (the role registry), `call_stack`, `references` (the ref-id → object-id hash), `objects` (the object record store), `srcs` (source-path interning), `pending_exceptions`, `gc_errors`.
- **NOT in skeletor**: classes. Class registry is engine-private — alongside the inverse index, dispatch caches, etc. See [skeletor.md § Classes are NOT in Skeletor](caspian/skeletor/skeletor.md#classes-not-in-skeletor).
- **Aslan ships**: only `state.roles` + `state.call_stack`. Everything else fills in over later slices. See [aslan.md § Data structures](development/v1/aslan.md#data-structures-lua-tables).
- **`current_role` / `current_chain` are NOT top-level fields** — they're the top-of-stack frame's `role` and `chain`. See [skeletor.md § Worked example](caspian/skeletor/skeletor.md#worked-example).
- **Working state stays OUT of skeletor** — intermediate expression results, args being marshaled, etc. live in Lua locals during dispatch. See [skeletor.md § V1.0 scope](caspian/skeletor/skeletor.md#v1-0-scope).

## Truthiness

- **Single platter class**: `puck.uno/truthiness`, with `bucket: {truthy: null | false | true | absent}`. Absent platter = truthy (default). See [object.md § Mechanism](caspian/built-in-classes/object.md#bool-mechanism).
- **Only null and false are non-truthy**. Empty string `""`, zero `0`, empty array `[]`, empty hash `{}` are all truthy. Ruby-style.
- **Locked at instantiation**: truthiness can never change after the object is created. The truthiness platter is pinned, engine_only, and its bucket is immutable.

## Three primitives

- **null, false, true are instances** of `puck.uno/null`, `puck.uno/false`, `puck.uno/true`. Each carries a sticky pinned `puck.uno/truthiness` platter with the corresponding `truthy` value.
- **All four classes are `engine_only`**: `puck.uno/truthiness`, `puck.uno/null`, `puck.uno/false`, `puck.uno/true`. User code can't push any of them onto another object's stack via `.classes.add` — the engine is the only entity that creates them. See [object.md § Identity](caspian/built-in-classes/object.md#identity), [nulls.md § `puck.uno/null` is `engine_only`](caspian/built-in-classes/nulls.md#engine-only-class).
- **null is per-call**: every `null` invocation produces a fresh instance. Two distinct nulls compare `==` by value (both null), but their `.object == .object` is false (distinct instances). See [nulls.md § Equality](caspian/built-in-classes/nulls.md#equality).

## References and uspace

- **Reference class hierarchy**: `puck.uno/reference` base; subclasses `puck.uno/variable` (uspace: true) and `puck.uno/hash_element` (uspace: false). See [references.md § Reference classes](caspian/skeletor/references.md#reference-classes).
- **`uspace` is a class-level property**, not per-instance. GC roots = the subset of references whose class declares `uspace: true`. See [references.md § Uspace: a class-level property](caspian/skeletor/references.md#uspace-class-property).
- **`references` hash**: `{ref_id: object_id}` — the bare pointer storage. Single source of truth for what each reference points at. See [references.md § Shape](caspian/skeletor/references.md#shape).
- **Inverse index is engine-private**: maintained via `after_set` / `after_delete` hooks on the references hash. Not exposed to user code in V1. See [example 07](caspian/skeletor/examples/07-references.md#inverse-index-engine-internal).

## Dispatch

- **Every method call pushes a `method_call` frame**, regardless of role. Same-role and cross-role calls both push. Role is one field on the frame, not the trigger for frame creation. See [skeletor.md § Worked example](caspian/skeletor/skeletor.md#worked-example).
- **Default is unicast**: first match wins, walk stops. Used by all normal method calls.
- **Multicast for lifecycle hooks**: every match fires, in walk order. Used by `on_close` and (when they land) `after_set`, `after_delete`, etc.
- **Dispatch kind is a function property**: `$foo.on_call = :first` (default) or `:all` (multicast). Convention is to put the property assignment on the line after the function definition. See [lucy.md § `on_call` property](caspian/lucy/lucy.md#on-call-property), [base-class-use.md § Unicast vs multicast](ideas/base-class-use.md#unicast-vs-multicast).
- **`on_call` is mutable**: metaprogrammers can flip it any time; role boundary handles safety. Engine can't cache dispatch identity aggressively.
- **`on_close` specifically**: 2ms cap per hook, engine catches per hook, deepest-first across objects, top-of-stack first within one object. See [garbage-collection.md § Multicast across platters](caspian/garbage-collection.md#on-close-multicast).

## Equality

- **Default `==` is identity** (overridable per class). Equivalent to `.object == .object` at the base level. Classes that want value equality (string, number, hash, etc.) override `==` for their use case. See [object.md § Identity](caspian/built-in-classes/object.md#identity).
- **`.object == .object` is engine-enforced identity**. Never overridable. The canonical "same object?" check.
- **No built-in `===`**. Developers can define their own where useful. Not reserved by the engine.

## Roles

- **Roles live in Skeletor** at `state.roles`. Program-visible execution state. See [aslan.md § Data structures](development/v1/aslan.md#data-structures-lua-tables).
- **Role on the object, not per-platter**: when an object has multiple platters, the owning role is on the object itself; the role that owns the object owns the whole stack.
- **Chain is per-frame**, regardless of role. Every frame gets a fresh `{log: {}, misc: {}}` on push — two reserved sub-fields pre-allocated even when empty. See [jasmine/caspian.md](caspian/packages/jasmine/caspian.md), [nulls.md § Use cases](caspian/built-in-classes/nulls.md#use-cases).
- **"Chain wipe at the role boundary" is a special case of per-frame chain isolation** — same-role and cross-role calls both push a fresh chain.

## Jails

- **"Jail" is a concept, not a specific class.** A jail is any object that contains another object and exposes only a selected list of its methods. The pattern shows up often in Caspian.
- **`puck.uno/jail` is the convenience class** for building one quickly via `$foo.object.jail(:method1, :method2)`. Useful when you don't want to write a custom wrapper. See [lucy.md § Jail](caspian/lucy/lucy.md#jail).
- **Directory jails** are a different specialization — a directory object that won't tell you where it lives on disk. Same conceptual pattern (restrict what's exposed), different concrete class. See [filesystem.md](caspian/built-in-classes/filesystem.md).
- **Inline construction idiom**: `%['puck.uno/sequence'].new.object.jail('next', 'peek')` — instantiate-and-wrap on one line, raw object never gets a name.

## CaspianJ

- **Canonical statement shape**: `[receiver, method, arg1?, arg2?, ...]`. Uniform across the language. Assignment is just `[{"var":"foo"}, "=", expr]`. See [caspianj.md § Core Principle](caspian/caspianj.md#core-principle), [decisions.md § Engine and runtime](development/v1/decisions.md#engine-and-runtime).
- **Literal expressions**: `{"value": <json>}` for primitives (class inferred from JSON type) or `{"value": <json>, "class": "uns/name"}` for non-primitives (class's materializer parses). See [caspianj.md § Literals](caspian/caspianj.md#literals).
- **Program shape**: array of statements. `[[stmt1], [stmt2], ...]`. Outer array is always there even for a single statement.

## Aslan scope (what walking-skeleton looks like)

- **Fixture**: `[[{"value": "hello"}, "to_string"]]`. Hand-written CaspianJ, no transpiler involved.
- **Returns `"hello"`** to the Lua test harness. No I/O, no stdout.
- **Engine has**: `state.roles` (user + stdlib) + `state.call_stack` (one top_level frame). That's all that's in skeletor.
- **Engine-private**: `engine.classes` (just the `puck.uno/string` class with `to_string` returning self). Registry keyed by UNS-prefixed name.
- **Method dispatch**: every method call pushes a `method_call` frame (regardless of role). For Aslan's fixture, dispatch is cross-role `user → stdlib → user`. TA.8 verifies the role transition is observed.
- **Chain shape**: every frame's chain is `{ log = {}, misc = {} }` — two reserved sub-fields pre-allocated, even when empty.
- **Value shape**: `{type, owning_role, payload}` Lua tables; `type` is the UNS-prefixed class name (e.g., `"puck.uno/string"`).
- **No platter model, no references hash, no objects hash, no IDs, no truthiness platter** — these arrive in later slices. See [aslan.md](development/v1/aslan.md).

## Conventions specific to this project

- **Class identifiers are always UNS-prefixed**: `puck.uno/foo`, `myapp.com/bar`, `puck.uno/string`. No bare names anywhere, including Aslan. Lua key access uses bracket notation: `engine.classes["puck.uno/string"]`.
- **Role names are bare strings**: `"user"`, `"stdlib"` for engine roles; UNS-named (e.g. `"markdown.uno/render"`) for runtime-loaded roles.
- **Caspian code in markdown**: use `~~~caspian` (per `feedback_caspian_code_fence` memory).
- **Field names use underscores; file names use dashes** (per CLAUDE.md).
- **JSON files use 2-space indent**; everything else uses tabs (per `feedback_json_two_space_indent` memory).
- **Vibecode blocks** sit immediately after a section heading, before any prose intro.

## Where to file things

- **New bugs / design issues**: `gh issue create --repo mikosullivan/puck` (per `feedback_new_issues_to_github` memory). NOT `documentation/issues.md`.
- **Design decisions log**: [decisions.md](development/v1/decisions.md) — one row per decision pointing to its canonical home.

## What this cheat sheet is NOT

- **Not a spec**. Don't quote it as authority; quote the canonical doc it points at.
- **Not exhaustive**. Plenty of settled decisions live only in their canonical docs without an entry here. The entries here are the ones that get *forgotten* during work in adjacent areas.
- **Not stable forever**. When a decision changes, both this file and the canonical doc need updating. If you find a contradiction between this file and a canonical doc, the canonical doc wins and this file gets fixed.
