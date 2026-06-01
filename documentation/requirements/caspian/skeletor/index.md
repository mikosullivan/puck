# Skeletor

~~~json
{"vibecode": {
	"doc": "skeletor",
	"role": "Caspian's runtime state organization: all execution state lives in a single hash; eventually that hash can be serialized for snapshot-and-revive, enabling transparent process pause/resume across remote calls",
	"status": "V1.0 objective — narrow scope; broader capabilities deferred",
	"v1_0_scope": "in-memory state hash only; no export API; no snapshot/revive; no HTTP promise()",
	"future_scope": "serialize/revive machinery, enabling HTTP promise() and the full snapshot-and-resume flow",
	"depends_on": ["deterministic_gc"],
	"inspired_by": "Temporal / AWS Step Functions workflow engines, applied as a language primitive"
}}
~~~

**Skeletor** is the code name for Caspian's process-state organization: all execution
state lives in a single hash, and the interpreter accesses runtime state only through
that hash's interface. The longer-term goal is to serialize that hash for
snapshot-and-revive — letting a Caspian process pause across a remote call, release the
host process during the wait, and revive transparently when the response arrives. The
foundation (the hash) ships in V1.0; the snapshot/revive machinery is deferred.

**Skeletor is also the foundation for deterministic GC.** The trace
that determines what's reachable starts from the **uspace roots** —
reference objects whose class declares `uspace: true` (variables in
live frames are the canonical example). The `references` hash inside
Skeletor (see [references.md](references.md)) maps every reference
object to the object it points at; the engine walks from the uspace
roots through this hash to determine reachability without reference
counting. See [garbage-collection.md](../garbage-collection.md#how-it-works)
for the GC side of this dependency.

<a id="v1-0-scope"></a>
## V1.0 scope

~~~json
{"vibecode": {
	"section": "v1_0_scope",
	"ships": "in-memory state hash + interpreter discipline",
	"does_not_ship": ["export_api", "snapshot_revive", "http_promise", "engine_provided_hash"]
}}
~~~

V1.0 of Skeletor ships **only the in-memory hash** and the structural commitment that
the interpreter goes through it for all execution state:

- The runtime creates a plain in-memory hash on startup (Lua-table-backed in Lucy).
- All execution state — objects, references, call stack frames (with their locals,
  src, iterator positions, role, and chain), pending exceptions — lives in the hash.
- Working state (intermediate expression results, arguments being marshaled, return
  values being prepared) stays outside the hash.
- The interpreter never bypasses the hash interface. One rule, enforced in code
  review, opens every door that follows.

**Not in V1.0:**

- **No export API.** The hash cannot be serialized to JSON or any other format.
- **No snapshot/revive.** Without export, processes cannot be paused-and-resumed.
- **No HTTP `promise()`** — the user-facing feature described later in this doc
  depends on snapshot/revive, so it does not ship in V1.0.
- **No engine-provided hash.** The runtime creates and owns its hash; engine
  overrides (SQLite, distributed, etc.) are a deferred extension point — see
  [#160](https://github.com/mikosullivan/puck/issues/160).

Why ship the foundation without the feature? Because the discipline matters even
without the export. The hash organization makes deterministic GC clean, makes the
reference graph natural, makes the runtime inspectable, and makes every future
serialization/persistence/snapshot story a contained addition rather than a runtime
overhaul. V1.0 ships the foundation; V1.x lands the export and the features that
depend on it.

<a id="worked-example"></a>
## Worked example: Skeletor mid-execution

~~~json
{"vibecode": {"section": "worked_example",
	"purpose": "illustrate_v1_0_skeletor_hash_with_a_realistic_nested_execution_moment_so_callers_can_see_what_the_data_structure_looks_like_beyond_the_minimal_aslan_snapshot",
	"shape_committed": false,
	"note": "field_names_and_frame_kinds_in_this_example_are_speculative_and_will_settle_as_each_slice_grows_the_hash"}}
~~~

The [Aslan slice](../../development/v1/caspian/aslan.md) ships the minimum
Skeletor footprint — a single-field hash, `call_stack`, holding one
`top_level` frame whose `role` and `chain` are the program's
starting role and an empty chain. Later slices grow the hash
(deeper stacks, iterator state, pending exceptions, etc.) without
changing the shape. This section illustrates what a fuller hash
looks like for a realistic nested
execution moment.

Consider this Caspian program:

~~~caspian
function &greet($who)
    $msg = 'hello, ' + $who
    return $msg
end

$names = ['Aslan', 'Bree']
$count = 0

$names.each($name) do
    if $name == 'Aslan'
        $count = $count + 1
        $title = 'Lord '
        puts $title + &greet($name)
    end
end
~~~

`$count` is set at top level (line 7) and **modified from inside the
`if` block** (line 11). That's the case worth tracing: variable
defined in an outer scope, mutated in an inner one. Assignment to an
existing name walks the lexical chain to find where the variable
lives and updates it there — it does NOT create a new shadowed local
in the inner scope. Compare to `$title`, which is a *fresh* name in
the if-block scope and lives in that frame's locals.

Trace the execution to a specific paused moment: the engine is **on
the first iteration**, inside the `do` block, the `if` test
succeeded (`$name == 'Aslan'`), `$count` has been incremented to 1,
`$title` has been bound, and `&greet` has been called with
`$who = 'Aslan'`. The local variable `$msg` inside `greet` has been
computed but not yet returned. We freeze the state right there.

The Skeletor hash at that moment. The `comment` fields throughout
are explanatory annotations for this walkthrough — real Skeletor
snapshots won't carry them. (Though `comment` is a reserved
pass-through field per [standard-fields.md](../../ecoverse/standard-fields.md),
so they'd be tolerated, not stripped.)

~~~json
{
  "comment": "Skeletor mid-execution, paused inside greet on the first iteration. Note count's value: it was set to 0 at line 7 and incremented to 1 from inside the if (line 11) — the updated value lives in frame 0's locals, not in the if-block's, because that's where count was defined. See Source-location tagging below for the file/src scheme.",
  "srcs": {
    "a": {"file": "/path/to/greetings.casp"}
  },
  "roles": {
    "user": {},
    "stdlib": {}
  },
  "call_stack": [
    {
      "comment":        "Frame 0: the program's outermost frame. names and count were assigned at lines 6-7. count now reads 1, not 0 — the assignment on line 11 walked the lexical chain from the if-block, found count here, and updated it in place.",
      "action":         "top_level",
      "role":           "user",
      "lexical_parent": null,
      "src":             ["a", 9],
      "locals": {
        "names": {"array": [
          {"value": "Aslan", "src": ["a", 6]},
          {"value": "Bree",  "src": ["a", 6]}
        ], "src": ["a", 6]},
        "count": {"value": 1, "src": ["a", 11]}
      }
    },
    {
      "comment":        "Frame 1: built-in array.each called by user code on line 9. Cross-role into stdlib; new frame's chain is fresh. lexical_parent is null because built-in code has no Caspian-level enclosing scope; src is null because stdlib internals have no source line.",
      "action":         "method_call",
      "role":           "stdlib",
      "receiver_type":  "array",
      "method":         "each",
      "iterator":       {"position": 0, "of": 2},
      "lexical_parent": null,
      "src":             null,
      "locals":         {}
    },
    {
      "comment":        "Frame 2: the do/end block at lines 9-15. Called back by array.each (which is why it's above the stdlib frame on the call stack), but lexical_parent jumps to frame 0 because the block was DEFINED at top level in user code. name = 'Aslan' for this iteration — value carries src ['a', 6] because it was born as a string literal on line 6.",
      "action":         "block",
      "role":           "user",
      "lexical_parent": 0,
      "src":             ["a", 10],
      "locals":         {"name": {"value": "Aslan", "src": ["a", 6]}}
    },
    {
      "comment":        "Frame 3: the if's lexical scope, pushed because the test on line 10 was true. lexical_parent is the enclosing do-block (frame 2). title is local to this if and disappears when the engine reaches `end` on line 14. Notice count is NOT here — its assignment on line 11 modified frame 0, not this frame, because that's where count was defined.",
      "action":         "if_block",
      "role":           "user",
      "lexical_parent": 2,
      "src":             ["a", 13],
      "locals":         {"title": {"value": "Lord ", "src": ["a", 12]}}
    },
    {
      "comment":        "Frame 4: the greet call. greet was DEFINED at top level (line 1), so lexical_parent jumps PAST frames 1, 2, 3 back to frame 0. who carries src ['a', 6] (its value was the same string literal that became name on line 6 — bindings move, the value's birth line doesn't). msg was computed on line 2 by the + operator, so its src is ['a', 2].",
      "action":         "function_call",
      "role":           "user",
      "function":       "greet",
      "lexical_parent": 0,
      "src":             ["a", 3],
      "locals":   {
        "who": {"value": "Aslan",        "src": ["a", 6]},
        "msg": {"value": "hello, Aslan", "src": ["a", 2]}
      }
    }
  ],
  "pending_exceptions": [],
  "gc_errors": []
}
~~~

Walkthrough, frame by frame:

- **Frame 0 — top-level.** `$names` and `$count` are bound in this
  frame's locals — there are no globals in Caspian; top-level
  assignments are just locals in the top-level frame. `$count` reads
  `1`, not `0`: the assignment on line 11 walked the lexical chain
  from inside the if-block, found `$count` here, and updated it in
  place. src sits at line 9 where `$names.each(...)` was called.
- **Frame 1 — `array.each` running in `stdlib`.** This is a
  cross-role call: user code called into a stdlib-owned method. The
  frame records its iterator state (`{position: 0, of: 2}`), and
  carries its own `chain` (wiped at the boundary per
  [roles.md](../roles.md#role-transitions) — the user's chain
  is preserved out-of-band and restored on return). `role: stdlib`.
- **Frame 2 — the do-block.** Cross-role back to `user` (the block
  is a closure created in user code). Its local `$name` is bound to
  `'Aslan'` for this iteration. src is line 10, the `if` statement
  that's currently being executed.
- **Frame 3 — the if-block.** Same-role lexical scope inside the do
  block. `$title` is local to this scope and disappears when the
  `if` exits. src is line 13, where `puts $title + &greet($name)` is
  in the middle of evaluating its expression. `lexical_parent` is 2
  (the enclosing do-block); variable lookup walks that chain: own
  locals → frame 2 (`$name`) → frame 0 (`$names`, `$count`).
  **`$count` is NOT in this frame's locals** even though it was
  assigned from inside the if — assignment to an existing name
  modifies the frame where the name lives, not the frame where the
  assignment is written. Only fresh names (`$title`) land in the
  inner frame.
- **Frame 4 — `greet` function.** Still `user` (functions run as
  their owner; `greet` is user-defined). `$who` is the argument;
  `$msg` is a local that's been computed but not yet returned. src
  is line 3. **`lexical_parent` is 0, not 3** — `greet` was DEFINED
  at top level, not inside the if. Its lexical chain is own locals
  → frame 0. `$name` and `$title` are physically between greet's
  frame and the top on the call stack, but they're not in greet's
  lexical chain and aren't visible from inside greet.

The "current role" and "current chain" are just the top frame's
`role` and `chain`. There are no separate top-level `current_role`
or `chain` fields — they'd be redundant with what the top frame
already carries. Whatever helpers the runtime exposes (`%role`,
`%chain`) read from the top of the stack.

Things to notice:

- **Role names are bare strings; the top-level `roles` registry
  holds per-role metadata.** Each frame's `role` field is a string
  that must resolve in `state.roles`. The engine validates this on
  every push — an unregistered name is a hard error, not a silent
  misdispatch. The registry's per-role entries are empty hashes in
  this example because Aslan-era roles have no metadata yet; later
  slices fill in trust webs, introspection state, etc.
- **Role keys are proxy-primary keys.** `"user"`, `"stdlib"`,
  `markdown.uno/render` — these are convenient labels for human
  readability, but the engine treats them as **opaque
  identifiers**. Code should not parse role keys, derive meaning
  from them, or assume any particular naming scheme. They're just
  unique strings within the registry. Two loaded libraries could
  in principle use arbitrary-looking keys (`"r0"`, `"r1"`) and the
  runtime would work identically; readable keys are a convention,
  not a contract.
- **Roles alternate down the stack.** user → stdlib → user → user →
  user. Each cross-role transition leaves a frame with its own
  fresh `chain`.
- **`if`/`for`/`while`/`do` are all frames.** Any new lexical scope
  pushes a frame with `action` indicating which kind of block. Cheap
  — no role transition, no method dispatch — but it makes variable
  lifetimes explicit (`$title` evaporates on the if's `end`) and
  keeps the model uniform with function and method calls.
- **`lexical_parent` is the scope chain; the call stack isn't.**
  Variable lookup follows `lexical_parent`, not "the frame below
  me." For block / if_block / for_block / while_block, those happen
  to match — the lexical parent is the frame immediately below.
  For function_call (and any closure), they DIVERGE: the function
  carries its definition environment, so `lexical_parent` points to
  whatever frame was on top when the function was defined. In the
  snapshot, greet (frame 4) was defined at top level, so its
  `lexical_parent` is 0 — past three intervening call frames.
- **Indices vs references.** `lexical_parent`, `origin_frame`, and
  any other "this frame points to that frame" field are integer
  indices in the JSON serialization but Lua table references in
  memory. The index is scoped to whichever array it appears in: a
  `lexical_parent: 0` on a frame in `call_stack` means position 0
  of `call_stack`; the same field on a frame in
  `captured_stack` means position 0 of *that* captured_stack. The
  serializer is what converts the in-memory reference to the
  appropriate index for the array being emitted.
- **Closures that outlive their defining scope: deferred.** When a
  function escapes the scope where it was defined (returned as a
  value, stored in a container, called later), the captured
  environment can't live on the call stack — that scope has
  unwound. Handled in most languages by giving each closure a
  captured-environment object that outlives the call stack. For
  Skeletor that'd be a sibling field like
  `captured_envs: [{locals, lexical_parent}, ...]`, with
  `lexical_parent` on a function_call frame pointing either into
  `call_stack` (still-live defining scope) or into `captured_envs`
  (defining scope has unwound). V1.0 may not need this if closures
  don't escape; left for later.
- **Chain is per-frame, independent.** Every frame gets its own
  fresh `chain` on push, regardless of role. A `%chain.misc.foo = 1`
  written inside a function is private to that function's frame;
  the caller doesn't see it, and the function doesn't see what its
  caller had in chain either. No cascade, no aliasing. Most
  programs barely use chain at all — when ambient-context
  propagation IS wanted, programs can build it explicitly (return
  values, or wrap a `puck.uno/meta_hash` over the layers they
  actually want to share). The default is simple isolation.
- **All values carry their CaspianJ expression shape.** `$msg` isn't
  the bare string `"hello, Aslan"`; it's `{"value": "hello, Aslan"}`
  — the same shape the dispatcher consumes. That uniformity means
  the hash is directly inspectable by the engine without re-marshaling.
- **Iterator state is just data.** `{"position": 0, "of": 2}` —
  enough for the engine to resume iteration from where it left off.
  No special "iterator object" type, no opaque handle. (Compare to
  Python generators, which hide iteration state inside an opaque
  frame.)
- **`pending_exceptions` is an empty array unless one or more exceptions are
  unwinding.** A stack: index 0 is the original raise; the last
  element is the currently-active exception. Each push happens on
  raise, each pop happens on resolve (catch or top-level escape).
  Stacked rather than single-slot because an `on_close` hook can
  itself throw while a prior exception is unwinding — the new one
  pushes onto the stack rather than silently replacing the old. See
  [Exceptions and the captured stack](#exceptions-and-captured-stack)
  below for the per-exception shape and why each entry carries its
  own `captured_stack`.
- **`gc_errors` is an engine-maintained list of on_close failures.**
  Stays empty when no GC handler has raised. When one does, the
  runtime catches the error (so one bad handler doesn't break GC
  for other objects), appends a record `{class, message, src}` to
  this list, and continues. Inspectable from any snapshot —
  a long list is a smell. Programs can read `%state.gc_errors`
  if they want to check for cleanup failures at shutdown. NOT the
  per-frame `chain` mechanism; that's frame-scoped ambient context,
  this is process-wide engine state. See
  [garbage-collection.md § Errors during on_close](../garbage-collection.md#on-close-errors).

This is what V1.0 Skeletor is **shaped like** — not what it ships in
Aslan. Aslan's hash is the bottom slice of this (the `roles` registry
populated with `user` + `stdlib`, and a `call_stack` with one
`top_level` frame); subsequent slices fill in the other fields as
the engine grows to need them.

<a id="classes-not-in-skeletor"></a>
### Classes are NOT in Skeletor

~~~json
{"vibecode": {"section": "classes_not_in_skeletor",
	"purpose": "establish_that_class_registries_are_engine_private_state_not_part_of_the_observable_skeletor_hash",
	"contrast_with": "roles_which_DO_live_in_skeletor_as_state_roles",
	"rationale": "classes_are_implementation_detail_of_the_dispatcher_not_program_visible_execution_state"}}
~~~

Class registries — built-in classes (string, array, hash, integer,
etc.) plus any runtime-registered classes (user-defined via
`Class.new`, library-defined when a library loads) — live as
**engine-private state**, alongside the inverse index, dispatch
caches, and the object-ID counter. They are **not** top-level fields
in Skeletor.

This is a deliberate asymmetry with **roles, which DO live in
Skeletor** (`state.roles`). Roles are program-visible execution state
— a running program can inspect `%role`, frames carry role
references, the role registry is part of "what the program is doing
right now." Classes, by contrast, are dispatcher implementation
detail. Programs don't need to inspect the class registry through
Skeletor to function; the dispatcher reaches into engine-private
state to resolve method calls.

Class references that appear *in* Skeletor (e.g., `receiver_type:
"string"` on a `method_call` frame, or `class_ref: "..."` on a
value) are name strings. The dispatcher resolves names against the
engine-private registry at dispatch time. Class lookup follows
Caspian's scoping rules (lexical chain for any per-scope class
registrations), but the resolution is engine-internal — the
registry's contents don't show up in snapshots.

<a id="source-location-tagging"></a>
### Source-location tagging

~~~json
{"vibecode": {"section": "source_location_tagging",
	"purpose": "preserve_caspian_source_file_and_line_through_to_skeletor_so_inspectors_debuggers_and_error_reports_can_point_users_back_to_the_code",
	"mechanism": "top_level_file_registry_plus_src_tuple_on_values_and_pc_on_frames",
	"data_source": "transpiler_already_emits_line_on_every_caspianj_node_per_caspianj_md_line_annotations",
	"cost": "negligible_one_int_per_value_plus_tiny_top_level_registry"}}
~~~

Every value in Skeletor — locals, chain entries, frame `src` — can
carry a back-pointer to where it came from in source. The
infrastructure: a top-level `srcs` registry interning paths to
short keys, plus a 2-element `src` tuple `[src_key, line]` on
each tagged thing.

**The registry** sits at the top of the hash, alongside `roles`:

```json
"srcs": {
  "1": {"file": "/path/to/greetings.casp"},
  "8": {"file": "/path/to/lib/io.casp"}
}
```

Each entry is a tagged object — the entry's value declares what
kind of source it refers to. Local files use `{"file": "..."}`;
Puck UNS sources use `{"uns": "..."}`. **For multi-file Puck
libraries, each source file gets its own registry entry** with
the file name in the UNS path (e.g., `{"uns":
"markdown.uno/render/render.casp"}`). Future kinds can be added
(`{"url": ...}`, `{"git": ...}`, etc.) without changing the
registry shape.

**Keys come from the global sequencer** — the same counter that
mints object IDs and platter IDs (see
[sequence.md § Engine use](../built-in-classes/sequence.md#engine-use)).
They're integer-strings drawn from the shared pool, interleaved
with object/platter IDs. Keys are stable within a single program
execution but not across runs — the registry is in the snapshot,
so anything reading it can resolve. Typical program has 1-50 src
entries; the registry itself is tiny.

**The `src` tuple** appears wherever a thing has a source origin:

```json
{"value": "Aslan", "src": ["a", 6]}    // value created on line 6 of file a
{"value": 1,       "src": ["a", 11]}   // result of "$count + 1" computed on line 11
```

**The `src` field on frames** uses the same tuple shape, since src
is just "current source position" of a frame:

```json
"src": ["a", 9]      // currently at line 9 of file a
"src": null          // stdlib internal — no source line
```

**Cost.** O(1) extra per value (one small array). Snapshot growth
~5-10% in the verbose case; less in compact serializations. Memory
per value: tens of bytes vs. the kilobytes you'd pay without
interning. The transpiler already populates `line` on every
CaspianJ node (per
[caspianj.md § line annotations](../caspianj.md#line-annotations)),
so propagation through Skeletor is "copy the line during
materialization" — one helper, applied everywhere a value is born.

**Semantics of `src` on a value:**

- The value's *birth* line, not the binding's. `$x = $y` doesn't
  change `$y`'s value's `src` — the binding moved, the value
  didn't. So a string passed through five function calls
  retains the `src` of the literal that created it.
- A value produced by an operator (`+`, `==`, etc.) gets the
  operator's `src` — "this value came into existence here."
- A value from a method or function return gets the `src` of the
  `return` statement (or last-expression line for implicit return).

**Hand-written CaspianJ (Aslan-era) has no `line` annotations,**
so its values have no `src`. The field is simply omitted.
Inspectors render "(no source)" or skip the source-link column.
Slice docs from Aslan through the early Caspian-source slices
show snapshots without `src` for this reason.

**Metaprogramming.** Most metaprogramming is handled naturally by
function literals: a `function ... end` body carries a real
`src` even when attached to a dynamically-created class at
runtime. When `$obj.greet(...)` dispatches a method whose body
came from a function literal on lines 12-14, the frame's `src`
tracks those lines. No special case.

The only genuinely source-less case (a method body constructed
from a string, via some future `eval`-like primitive) is handled
by simply **omitting `src`**. The inspector renders "(no source)"
and moves on. A richer scheme (e.g., a `meta_src` field pointing
to the construction site) is a natural future extension, but
V1.0 doesn't need it: Caspian's V1 metaprogramming surface
(`Class.new`, `add_method(name, function_literal)`, dynamic
dispatch) preserves source through function literals. If a
string-to-code primitive lands later, the `src`-or-omitted
structure leaves room to grow.

<a id="src-summary"></a>
#### Decisions summary

- **Top-level field is `srcs`** (plural of `src`, matching the convention
  used for `roles`). Maps short keys to full paths.
- **Keys come from the global sequencer** — integer-strings drawn from
  the shared pool that also mints object IDs and platter IDs. Stable
  within a single program execution; not stable across runs.
- **Multi-file Puck libraries get one srcs entry per file**, with
  the file name in the UNS value (e.g., `{"uns":
  "markdown.uno/render/render.casp"}`).
- **The reference field is `src`** (chose this over `loc`, the
  named `{"file": "a", "line": 42}` split form, etc.). Holds a
  2-element tuple `[src_key, line]`.
- **`src` tags values** in `locals`, in arrays/hashes, in chain
  entries, in pending exceptions — anything with a creation point
  in source.
- **`src` on frames uses the same `[src_key, line]` shape** since
  it's just "where this frame currently is in source." `null`
  when there's no source (stdlib internals, hand-written
  CaspianJ).
- **A value's `src` is its birth line, not its current binding's
  line.** Passing a value through assignments and calls doesn't
  change its `src`.
- **A value produced by an operator gets the operator's `src`.**
  `$msg = $a + $b` on line 7 gives the result `src: ["a", 7]`
  regardless of where `$a` and `$b` came from.
- **A value returned from a function/method gets the return
  statement's `src`** (or the last expression's `src` for
  implicit return).
- **`src` is omitted when unknown.** Hand-written CaspianJ
  (Aslan-era) and truly source-less metaprogramming output both
  produce values without `src`. Inspectors render "(no source)"
  and move on. No `null`, no sentinel — the field is simply
  absent.
- **Future extension stays open.** A `meta_src` field for
  construction-site provenance, or external debugger plugins
  (see [Future possibilities](#future-debugger-plugin-interface)),
  can fill in gaps later without changing the V1.0 structure.

**Multi-file libraries: one entry per file.** A UNS-loaded library
with multiple source files registers one `srcs` entry per file,
with the file name baked into each entry's `uns` value (e.g.,
`{"uns": "foo.bar/baz/render.casp"}` vs `{"uns":
"foo.bar/baz/parser.casp"}`). That keeps the src tuple uniform
at 2 elements — `[src_key, line]` — everywhere, regardless of
whether the source is a single file, a library file, or anything
else added later. The alternative (one entry per library with
file disambiguation inside the src tuple) was rejected because it
makes every src consumer handle two tuple shapes; pushing the
cost to one registry table instead of many readers is the better
trade.

<a id="src-examples"></a>
#### Examples

**Multi-file registry.** A program that uses `&greet` from
`lib/io.casp` and the array-each block from `main.casp`:

```json
"srcs": {
  "a": {"file": "/path/to/main.casp"},
  "b": {"file": "/path/to/lib/io.casp"}
}
```

A value created by a literal in `lib/io.casp` line 4 carries
`"src": ["b", 4]`; a value created in `main.casp` line 9 carries
`"src": ["a", 9]`. The registry grows as new sources are
encountered during loading — typically 1-50 entries even for
substantial programs.

**Mixed local and remote.** A program that also loads a Puck
library:

```json
"srcs": {
  "a": {"file": "/path/to/main.casp"},
  "b": {"file": "/path/to/lib/io.casp"},
  "c": {"uns": "markdown.uno/render/render.casp"}
}
```

A value created inside the loaded library on line 17 carries
`"src": ["c", 17]`. The `uns` key declares the source kind, so
the value doesn't need a `puck://` prefix — that's implicit.

**Birth line, not binding line.** Tracing where a value came from
across multiple assignments:

```caspian
$first = 'Aslan'        # line 6 — string literal created here
$second = $first         # line 7 — rebinding, no new value
$third = $second         # line 8 — rebinding, no new value
```

After execution:

```json
"locals": {
  "first":  {"value": "Aslan", "src": ["a", 6]},
  "second": {"value": "Aslan", "src": ["a", 6]},
  "third":  {"value": "Aslan", "src": ["a", 6]}
}
```

All three bindings point at the same string value, which was
born on line 6. The bindings moved across lines 7 and 8; the
value didn't. (In memory, all three locals can even alias the
same value record; the serializer shows the value inline for
each.)

**Operator-produced value.** Arithmetic and string operations
give their result the operator's `src`:

```caspian
$a = 2                   # line 10
$b = 3                   # line 11
$sum = $a + $b           # line 12 — operator on line 12
```

Result:

```json
"locals": {
  "a":   {"value": 2, "src": ["a", 10]},
  "b":   {"value": 3, "src": ["a", 11]},
  "sum": {"value": 5, "src": ["a", 12]}
}
```

`sum`'s value `5` came into existence on line 12, not 10 or 11
(its operand birth lines).

**Function return.** A value returned from a function gets the
return statement's `src`:

```caspian
function &double($x)
    return $x * 2        # line 2 — return statement
end                      # line 3

$y = &double(7)          # line 5 — call site
```

Result:

```json
"locals": {
  "y": {"value": 14, "src": ["a", 2]}
}
```

`y`'s value `14` came into existence on line 2 (where the
`return` executed), not line 5 (where it was bound to `y`). The
call site is recoverable from the function_call frame's
position when paused mid-call; the value's `src` records its
birth, not where it landed.

**Chain entry tagging.** When user code writes to chain, the
write line is recorded:

```caspian
$some_function_on_line_50()    # writes %chain.misc.user_id = 'u42'
```

The chain entry:

```json
"chain": {
  "log":  {},
  "misc": {
    "user_id": {"value": "u42", "src": ["a", 50]}
  }
}
```

The src on the entry tracks the write line, which is the same
as the value's birth line in this case (a literal string
written via assignment).

**Source-less value.** A method body constructed dynamically
without source:

```json
"locals": {
  "result": {"value": "computed", "src": ["a", 22]},
  "dynamic": {"value": "from_eval"}
}
```

`result` has its src; `dynamic` doesn't — `src` is simply
absent. An inspector rendering this would show:

```
result   "computed"   main.casp:22
dynamic  "from_eval"  (no source)
```

**Inspector-rendered stack trace.** A formatter walking
`call_stack` with the srcs registry resolved:

```
Stack trace:
  frame 4: greet     /path/to/lib/io.casp:3       (function_call, user)
  frame 3: <if>      /path/to/main.casp:13        (if_block, user)
  frame 2: <do>      /path/to/main.casp:10        (block, user)
  frame 1: each      (internal)                   (method_call, stdlib)
  frame 0: <top>     /path/to/main.casp:9         (top_level, user)
```

Frame 1's `src: null` renders as `(internal)`. All other frames
resolve their `src: [src_key, line]` tuple against `srcs` to
produce human-readable paths.

<a id="deeper-stack"></a>
### Deeper stack: recursive tree walk

~~~json
{"vibecode": {"section": "deeper_stack",
	"purpose": "second_worked_example_showing_substantially_more_call_stack_depth_via_recursion_through_a_three_level_tree; demonstrates_repeated_user_stdlib_alternation_and_recursive_function_frames_at_different_depths",
	"shape_committed": false}}
~~~

The previous example tops out at four frames. Real programs go much
deeper — recursion, nested method calls, helper functions calling
helper functions. This example walks a three-level tree to show what
a meaningfully deeper Skeletor looks like.

~~~caspian
function &print_tree($node, $depth)
    puts $node['name']
    $node['children'].each($child) do
        &print_tree($child, $depth + 1)
    end
end

$tree = {
    'name':     'root',
    'children': [{
        'name':     'mid',
        'children': [{
            'name':     'leaf',
            'children': []
        }]
    }]
}

&print_tree($tree, 0)
~~~

Pause point: the innermost `&print_tree` call (for the `leaf` node)
has just been entered. Execution sits at `puts $node['name']` —
about to dispatch `puts`, not into it yet. Eight call-stack frames.

~~~json
{
  "call_stack": [
    {
      "action":   "top_level",
      "role":   {"name": "user"},
      "src":     "line 19",
      "locals": {
        "tree": {"hash": {
          "name":     {"value": "root"},
          "children": {"array": [{"hash": {
            "name":     {"value": "mid"},
            "children": {"array": [{"hash": {
              "name":     {"value": "leaf"},
              "children": {"array": []}
            }}]}
          }}]}
        }}
      }
    },
    {
      "action":     "function_call",
      "role":     {"name": "user"},
      "function": "print_tree",
      "src":       "line 3",
      "locals":   {
        "node":  "<ref to top-frame tree>",
        "depth": {"value": 0}
      }
    },
    {
      "action":          "method_call",
      "role":          {"name": "stdlib"},
      "receiver_type": "array",
      "method":        "each",
      "iterator":      {"position": 0, "of": 1},
      "src":            "internal",
      "locals":        {}
    },
    {
      "action":   "block",
      "role":   {"name": "user"},
      "src":     "line 4",
      "locals": {"child": "<ref to mid node>"}
    },
    {
      "action":     "function_call",
      "role":     {"name": "user"},
      "function": "print_tree",
      "src":       "line 3",
      "locals":   {
        "node":  "<ref to mid node>",
        "depth": {"value": 1}
      }
    },
    {
      "action":          "method_call",
      "role":          {"name": "stdlib"},
      "receiver_type": "array",
      "method":        "each",
      "iterator":      {"position": 0, "of": 1},
      "src":            "internal",
      "locals":        {}
    },
    {
      "action":   "block",
      "role":   {"name": "user"},
      "src":     "line 4",
      "locals": {"child": "<ref to leaf node>"}
    },
    {
      "action":     "function_call",
      "role":     {"name": "user"},
      "function": "print_tree",
      "src":       "line 2",
      "locals":   {
        "node":  "<ref to leaf node>",
        "depth": {"value": 2}
      }
    }
  ],
  "pending_exceptions": []
}
~~~

What the deeper stack illustrates that the shorter one didn't:

- **Same function, different frames.** Three `function_call` frames
  all named `print_tree`, at src line 3, line 3, and line 2 — three
  different call sites, three different `$depth` values (0, 1, 2),
  three different `$node` bindings. Recursion is just stack frames;
  the engine doesn't model recursion specially.
- **Role alternation persists at depth.** user → user → **stdlib** →
  user → user → **stdlib** → user → user. Every `array.each` is a
  cross-role hop into stdlib; the body block hops back to user. Each
  stdlib frame carries its own wiped `chain`.
- **Iterator state survives recursion.** Two distinct `array.each`
  frames, each at `position: 0, of: 1`. When `&print_tree(leaf, 2)`
  finishes and unwinds, the engine resumes the inner `each` from its
  saved position — independently of the outer `each`. No shared
  iterator state, no implicit nesting trick.
- **References, not value-copies.** `$node` in frames 1, 4, and 7
  uses `"<ref to ...>"` placeholders in this rendering, but in the
  actual hash each binding is a short object ID (see
  [references.md § Object IDs](references.md#object-ids)) whose
  target lives in the top-level `references` hash. The shared
  `$node` aliasing is recorded by multiple reference IDs pointing
  at the same target object — see
  [example 07](examples/07-references.md) for what that looks like
  concretely. The placeholders here are a notational shorthand for
  readability.
- **src granularity matters.** Frames 1 and 4 both sit at "line 3"
  (the `puts` statement), but they're at different points in their
  respective executions: frame 1 finished `puts 'root'` and is now
  inside `.each`; frame 4 finished `puts 'mid'` and is now inside
  *its* `.each`. src alone doesn't distinguish them — the frame's
  surrounding state does.

Production Skeletor will need a richer src representation (likely
adding a `statement_index` or `sub_position` alongside the
existing `[src_key, line]` to disambiguate paused-mid-expression
cases). V1.0 doesn't tackle
that; it ships enough src fidelity to support resumption between
statements, which is all a single-process in-memory hash needs.

<a id="exceptions-and-captured-stack"></a>
### Exceptions and the captured stack

~~~json
{"vibecode": {"section": "exceptions_and_captured_stack",
	"purpose": "describe_how_pending_exception_preserves_the_call_stack_state_at_raise_time_via_reference_capture_so_uncaught_exception_reports_show_where_the_program_actually_was_not_the_residue_after_unwinding",
	"shape_committed": false,
	"key_idea": "capture_by_reference_not_deep_copy; popped_frames_stop_mutating_so_references_are_stable_point_in_time_snapshots"}}
~~~

`pending_exceptions` is a **stack** of exception records — index
0 is the original raise, the last element is the currently-active
one. Push on raise, pop on resolve (catch or top-level escape).
A stack rather than a single slot because an `on_close` hook can
itself throw while a prior exception is unwinding: the new
exception pushes onto the stack rather than silently replacing
the one already in flight. Most of the time the stack has 0 or 1
entries; exception-during-handling deepens it.

When an exception is raised, the engine unwinds the call stack
looking for a handler. By the time the exception reaches a
debugger, an uncaught-error handler, or the host, the frames
between the raise point and the catch point (or the top, for
uncaught) have been popped. Without intervention, what you'd see
in `pending_exceptions[top]` is just "an exception happened" —
the context where it actually happened is gone.

So at raise time, the engine snapshots the call stack into the
new exception's `captured_stack` field. Each exception on the
stack carries its own `captured_stack`. **Capture is by reference,
not by deep copy** — see
[Capture-by-reference](#capture-by-reference) below for the cost
analysis.

Consider this Caspian program, with the second iteration raising:

~~~caspian
function &greet($who)
    if $who == ''
        throw 'name cannot be empty'
    end
    $msg = 'hello, ' + $who
    return $msg
end

$names = ['Aslan', '']

$names.each($name) do
    puts &greet($name)
end
~~~

First iteration prints `hello, Aslan`. Second iteration calls
`&greet('')`, the `if` test succeeds, `throw` fires on line 3. No
`try` catches it; unwinding proceeds all the way up.

**Snapshot at the moment `throw` fires** (before any unwinding):

~~~json
{
  "roles": {"user": {}, "stdlib": {}},
  "call_stack": [
    {"action": "top_level",     "role": "user",   "lexical_parent": null, "src": "line 11", "locals": {"names": "<...>"},          "chain": "<...>"},
    {"action": "method_call",   "role": "stdlib", "lexical_parent": null, "src": "internal", "method": "each", "iterator": {"position": 1, "of": 2}, "locals": {}, "chain": "<...>"},
    {"action": "block",         "role": "user",   "lexical_parent": 0,    "src": "line 12", "locals": {"name": {"value": ""}},     "chain": "<...>"},
    {"action": "function_call", "role": "user",   "lexical_parent": 0,    "src": "line 3",  "function": "greet", "locals": {"who": {"value": ""}}, "chain": "<...>"},
    {"action": "if_block",      "role": "user",   "lexical_parent": 3,    "src": "line 3",  "locals": {},                          "chain": "<...>"}
  ],
  "pending_exceptions": [{
    "class": "puck.uno/error/runtime",
    "message": "name cannot be empty",
    "captured_stack": "<five references — one per frame above, in order>"
  }]
}
~~~

The `captured_stack` and the live `call_stack` point at the same
five frame tables. No copy yet — just five pointers.

**Snapshot after full unwinding** (uncaught; engine is about to
hand the exception to the host):

~~~json
{
  "roles": {"user": {}, "stdlib": {}},
  "call_stack": [
    {"action": "top_level", "role": "user", "lexical_parent": null, "src": "line 11", "locals": {"names": "<...>"}, "chain": "<...>"}
  ],
  "pending_exceptions": [{
    "class": "puck.uno/error/runtime",
    "message": "name cannot be empty",
    "captured_stack": [
      {"action": "top_level", "role": "user", "lexical_parent": null, "src": "line 11", "locals": {"names": "<...>"}, "chain": "<...>"},
      {"action": "method_call", "role": "stdlib", "lexical_parent": null, "src": "internal", "method": "each", "iterator": {"position": 1, "of": 2}, "locals": {}, "chain": "<...>"},
      {"action": "block", "role": "user", "lexical_parent": 0, "src": "line 12", "locals": {"name": {"value": ""}}, "chain": "<...>"},
      {"action": "function_call", "role": "user", "lexical_parent": 0, "src": "line 3", "function": "greet", "locals": {"who": {"value": ""}}, "chain": "<...>"},
      {"action": "if_block", "role": "user", "lexical_parent": 3, "src": "line 3", "locals": {}, "chain": "<...>"}
    ]
  }]
}
~~~

The live `call_stack` is short (the method_call, block,
function_call, and if_block frames have all been popped). The
`captured_stack` still holds all five — the popped frame tables
weren't destroyed, just removed from `call_stack`. The exception's
references kept them alive.

An uncaught-exception report formatted from `captured_stack` shows
the program at line 3 inside `greet`, called via the do-block,
called via `array.each`, called from line 11. That's the actually-
useful debugging output. A report formatted from the live
`call_stack` would just say "at line 11" — technically true and
completely useless.

**Exception during unwinding.** When an `on_close` hook on a
frame being popped *itself* throws, the new exception pushes
onto `pending_exceptions` rather than replacing the original.
The stack grows; the engine still has both records to work with.
Inspecting the snapshot mid-double-unwind:

```json
"pending_exceptions": [
  {
    "class": "puck.uno/error/runtime",
    "message": "name cannot be empty",
    "captured_stack": ["<5 frames from the original raise>"]
  },
  {
    "class": "puck.uno/error/io",
    "message": "tempfile cleanup failed: permission denied",
    "captured_stack": ["<3 frames from the on_close hook's raise>"]
  }
]
```

Index 0 is the original raise that triggered unwinding. Index 1
is the new exception thrown by an `on_close` hook during that
unwinding. A formatted report would render something like:

```
Uncaught: puck.uno/error/io: tempfile cleanup failed: permission denied
  ...stack from index 1's captured_stack...
During handling of: puck.uno/error/runtime: name cannot be empty
  ...stack from index 0's captured_stack...
```

When the engine resolves an exception (catch handler runs and
completes, or one bubbles out the top), `pending_exceptions.pop()`
removes the top-of-stack record. If exceptions are resolved in
LIFO order (the normal case), the stack shrinks to empty
naturally. If a catch handler resolves an exception that wasn't
at the top — exotic but possible — the engine pops it from the
middle of the array rather than the end.

<a id="capture-by-reference"></a>
### Capture-by-reference: the cost model

~~~json
{"vibecode": {"section": "capture_by_reference_cost_model",
	"why_cheap": ["pointer_per_frame_not_deep_copy",
		"popped_frames_stop_mutating_so_references_are_stable",
		"memory_pinned_only_until_exception_resolves"],
	"costs_to_flag": ["referenced_frame_locals_pin_their_reachable_state_from_gc_until_exception_resolves",
		"caught_exceptions_with_long_held_references_could_extend_lifetime_of_large_local_state",
		"shallow_frames_that_survive_unwinding_continue_to_mutate_post_capture"]}}
~~~

The naive read of "snapshot the stack at raise time" is "deep-copy
everything reachable" — which would be expensive (potentially
megabytes of state copied on every exception). That's not what
happens.

**What actually happens:**

```lua
exception.captured_stack = {}
for i, frame in ipairs(engine.state.call_stack) do
    exception.captured_stack[i] = frame   -- reference, not copy
end
```

O(stack_depth) pointer storage. Typical depths are 5-50 frames,
so 5-50 pointer-sized writes. Effectively free compared to the
exception itself.

**Why references are stable:** the engine doesn't mutate a frame
after popping it. `table.remove(call_stack, i)` removes the
reference from the array; it doesn't touch the table itself. So a
held reference to a popped frame is a true point-in-time view —
frozen the moment the frame stopped being on the live stack.

**Memory implication:** frames in `captured_stack` (and everything
reachable from their `locals` and `chain`) can't be garbage-
collected until the exception resolves. Short-lived in practice
(catch handlers run quickly, uncaught exceptions terminate the
program). The pathological case is a long-lived caught exception
that pins large locals — worth a note, not worth solving in V1.0.

**Caught-vs-uncaught nuance:** for uncaught exceptions, every
referenced frame is popped → frozen. Perfect point-in-time
snapshot. For caught exceptions, the catching frame survives
unwinding and may continue mutating after capture (its src advances
into the catch handler, new locals get bound). The `captured_stack`
reference to that frame would reflect the live state, not the
at-raise state. Two ways to handle this:

1. **Only capture the would-be-popped portion.** At catch time the
   engine knows which frames will pop; capture just those. The
   surviving frames can be inspected live.
2. **Capture the full stack but mark the catch boundary.** The
   captured_stack[catch_index] entry gets a flag saying "this
   frame is still live; don't trust its post-raise state."

V1.0 can defer this choice — exception machinery isn't in scope
until later slices. For uncaught (the common debugging case), both
designs give the same answer.

**Engine-only access:** `captured_stack` is engine-controlled, not
exposed to user-code catch handlers. Two reasons:

- **Secrets in locals.** A function holding an API token in its
  locals throws → the catcher shouldn't be able to read the token
  via the exception. The engine offers a *formatted* stack trace
  (class names, function names, line numbers as strings) and the
  exception's own class/message, but not the raw frame tables.
- **Trust-web preservation.** If any frame could read any other
  frame's state by raising-and-catching, role boundaries would be
  defeated.

The user-visible API (sketch):

~~~caspian
catch ($e)
    puts $e.message          # OK — formatted
    puts $e.stack_trace      # OK — formatted strings
    puts $e.captured_stack   # error — engine-only
end
~~~

<a id="remote-library-and-trust-barrier"></a>
### Loaded remote library and the trust barrier

~~~json
{"vibecode": {"section": "remote_library_and_trust_barrier",
	"purpose": "show_how_a_runtime_loaded_remote_library_appears_in_skeletor_and_demonstrate_that_cross_role_chain_isolation_handles_the_trust_barrier_with_no_special_machinery",
	"shape_committed": false,
	"key_idea": "loaded_library_gets_its_own_role_and_files_entries; cross_role_chain_wipe_does_the_trust_isolation_work_for_free"}}
~~~

A program that loads a remote Caspian library via `%puck` and
calls a method on it — and along the way puts something into
`%chain.misc` that the library is NOT supposed to see:

~~~caspian
$markdown = %puck['markdown.uno/render']
%chain.misc.api_token = 'sk-secret-abc123'
$html = $markdown.to_html('# Hello')
puts $html
~~~

Pause point: inside `to_html` in the loaded library, partway
through. The library has tokenized the input and is building the
output string.

```json
{
  "srcs": {
    "a": {"file": "/home/miko/projects/site/render_post.casp"},
    "b": {"uns": "markdown.uno/render/render.casp"}
  },
  "roles": {
    "user": {},
    "stdlib": {},
    "markdown.uno/render": {
      "loaded_from": "puck://markdown.uno/render",
      "loaded_at": ["a", 1],
      "trust": []
    }
  },
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "lexical_parent": null,
      "src": ["a", 3],
      "locals": {
        "markdown": {"class_ref": "Renderer", "src": ["a", 1]}
      },
      "chain": {
        "log": {},
        "misc": {
          "api_token": {"value": "sk-secret-abc123", "src": ["a", 2]}
        }
      }
    },
    {
      "action": "method_call",
      "role": "markdown.uno/render",
      "receiver_type": "Renderer",
      "method": "to_html",
      "lexical_parent": null,
      "src": ["b", 47],
      "locals": {
        "input": {"value": "# Hello", "src": ["a", 3]},
        "tokens": {"array": [
          {"value": "H1_OPEN", "src": ["b", 32]},
          {"value": "Hello", "src": ["b", 35]},
          {"value": "H1_CLOSE", "src": ["b", 38]}
        ], "src": ["b", 41]}
      }
    }
  ],
  "pending_exceptions": []
}
```

Things to notice:

- **`roles` registry has three entries.** Two engine-bootstrap
  roles (`user`, `stdlib`) and one runtime-loaded one
  (`markdown.uno/render`). The library's role entry carries
  metadata: where it was loaded from (the UNS), where in user
  code the load happened (`["a", 1]` — `%puck[...]` on line 1),
  and its trust web (empty — the library can't reach any other
  role from inside its own dispatch).
- **`srcs` registry mixes local and remote, with tagged kinds.**
  Entry `a` is `{"file": "..."}`. Entry `b` is `{"uns": "..."}`.
  The key in each entry declares the source kind, so consumers
  don't have to parse strings to tell file paths from UNS
  references. The `uns` value drops the `puck://` prefix since
  the key already declares the kind. Future kinds (`url`, `git`,
  etc.) slot in without disturbing the registry shape.
- **The library's role name IS its UNS.** `markdown.uno/render`
  as a role name is fine — names are arbitrary strings, and UNS
  gives a globally unique identifier with no risk of collision
  with other loaded libraries.
- **The library's class is not visible in the snapshot.** Class
  registries are engine-private state, not part of Skeletor (see
  [Classes are NOT in Skeletor](#classes-not-in-skeletor)).
  `Renderer` was registered when `%puck['markdown.uno/render']`
  executed on line 1; the dispatcher knows about it because the
  engine's registry knows about it, not because it appears in any
  frame. Dispatch resolves `class_ref: "Renderer"` (on `markdown`)
  and `receiver_type: "Renderer"` (on the `method_call` frame) by
  looking up "Renderer" in the engine's class registry following
  whatever scope rules apply. The lookup is engine-internal; the
  snapshot just shows the *name* being resolved.
- **The trust barrier is invisible in the snapshot, by design.**
  Look at the two frames' `chain` fields. The user's frame
  (frame 0) has `chain.misc.api_token = "sk-secret-abc123"`. The
  library's frame (frame 1) has `chain: {"log": {}, "misc": {}}`
  — empty. The library's `to_html` cannot reach the token by
  walking `%chain.misc.api_token` or similar — the chain is
  wiped at the role boundary, exactly the same mechanism that
  wipes the chain for any cross-role call (stdlib, stdout, etc.).
  Trust isolation is the role boundary's normal behavior, not a
  special "remote library" feature. Skeletor needs no new field
  for this.
- **`lexical_parent: null` on the library's frame.** The
  library's `to_html` was defined in the library's own top-level
  scope — which ran once when the library was loaded, then
  unwound. Its captured environment isn't on the live
  `call_stack`. In a full implementation this would point into
  `captured_envs` (the sketched future field). For V1.0 it shows
  as `null` because escaped-closure environments aren't built
  yet.
- **`input`'s `src` is `["a", 3]`, not `["b", N]`.** The value
  `'# Hello'` was born as a literal on line 3 of the user's
  file, then passed across the role boundary. Birth-line travels
  with the value — the library can see where the input
  originated. Whether that's a *feature* or an *information
  leak* (the trust barrier arguably should hide caller-source
  detail from the callee) is an open question worth deciding
  before V1.0.
- **`tokens`'s `src` is `["b", 41]`.** Values created inside the
  library carry the library's source location. No conflict with
  user-file lines because the file key disambiguates.

The takeaway: loading a remote library is **structurally
identical** to anything else that introduces a role — adding an
entry to `roles`, a possible entry to `srcs`, and pushing frames
that reference it. The chain wipe at role boundaries does all
the trust isolation work. Skeletor's job is just to make the
role and file boundaries visible.

---

<a id="future-snapshot-and-revive"></a>
## Future: snapshot-and-revive (post-V1.0)

The original Skeletor vision — transparent snapshot-and-revive across blocking remote
calls — depends on adding an export API to the V1.0 hash. The sections below describe
that target shape. None of it ships in V1.0; it's recorded here so the V1.0 work is
done with the post-V1.0 capability in mind.

The post-V1.0 flow: a Caspian program makes what looks like a synchronous call; under
the hood, the runtime serializes the entire process state, releases the host,
dispatches the remote operation, and revives the process with the response value in
hand when the operation completes. Code stays linear. Host resources go to zero during
the wait. Crashes during the wait are transparent — the snapshot revives on whatever
host picks it up next.

---

<a id="post-v1-0-api"></a>
## Post-V1.0 API (deferred)

~~~json
{"vibecode": {
	"section": "post_v1_0_api",
	"surface": "single method on a single class",
	"class": "puck.uno/http/request",
	"method": "promise()",
	"return": "puck.uno/http/response instance",
	"status": "deferred — requires the export API not in V1.0"
}}
~~~

The only way to make a promise (in the post-V1.0 design) is via an HTTP request object:

~~~caspian
$http = %['puck.uno/http/request'].new('https://foo.com?q=303')
$response = $http.promise()
~~~

From the developer's view, `promise()` is a blocking call that returns the HTTP
response. Under the hood, the runtime may snapshot the entire process, free the
host, dispatch the request through whatever HTTP infrastructure is available, and
revive the process with the response value bound to `$response`.

Whether a particular call actually snapshots, or completes inline because the
response is fast enough, is the runtime's decision — programs cannot distinguish
between the two cases. That gives the runtime room to optimize (inline-fast,
snapshot-slow) without changing program semantics.

---

<a id="what-happens-under-the-hood"></a>
## What happens under the hood

~~~json
{"vibecode": {
	"section": "under_the_hood",
	"steps": ["assign_correlation_id", "snapshot_to_disk", "dispatch_request",
		"host_exits", "watcher_monitors", "response_arrives",
		"revive_snapshot", "bind_response_value", "resume_execution"],
	"caller_visibility": "none — looks like a synchronous call"
}}
~~~

At the `promise()` call:

1. The runtime assigns the request a unique correlation ID.
2. The runtime serializes the entire process state — worldlet, call stack, src, roots
   — tagged with the correlation ID. The snapshot includes everything needed to
   resume execution from the line after the `promise()` call.
3. The runtime hands `(correlation_id, request)` to an external dispatcher (a small
   daemon, a queue, or a Puck service — exact mechanism TBD per the host).
4. The Caspian host process exits. Memory is freed.
5. The dispatcher executes the HTTP request.
6. When the response arrives, the dispatcher locates the snapshot by correlation
   ID, revives it, and binds the response value as the return of `promise()`.
7. Execution continues from the line after the call as if nothing had happened.

No class-level hooks fire at snapshot or revive. The runtime serializes whatever's
in the worldlet; the worldlet is everything. Anything that genuinely needs to live
outside the worldlet (an open TCP socket, a file descriptor) belongs to the host
engine, not to user code — see
[no on_snapshot / on_revive hooks](#out-of-scope-snapshot-revive-hooks) below.

---

<a id="engine-granted-permission"></a>
## Engine-granted permission

~~~json
{"vibecode": {
	"section": "engine_permission",
	"role": "the host engine must grant a Caspian program permission to make promise() calls",
	"reason": "promise() exits the host process; embedding engines need explicit opt-in",
	"mechanism": "TBD"
}}
~~~

A Caspian program cannot make `promise()` calls unless the embedding engine has
granted it permission. This matters because `promise()` involves the host process
exiting — an engine that embeds Caspian inside a larger system needs to decide
whether that's acceptable behavior. A web framework that runs Caspian per-request
probably wants `promise()` allowed. A trigger-firing engine that expects every
invocation to complete in milliseconds probably does not.

The mechanism for granting and revoking this permission is TBD. See
[engine permission model](#open-engine-permission-model) below.

---

<a id="explicitly-out-of-scope"></a>
## Explicitly out of scope for V1

~~~json
{"vibecode": {
	"section": "out_of_scope_v1",
	"role": "scope-tightening — features that are plausible but not in V1",
	"principle": "narrow_surface_first_evolve_when_real_use_cases_emerge"
}}
~~~

<a id="out-of-scope-general-primitive"></a>
### A general `%utils.promise($anything)` primitive

V1 has no general "promise this arbitrary operation" entry point. The only thing
that gets `promise()` is `puck.uno/http/request`. Other plausible primitives
(`%fs.read_async`, `%db.query_async`, system-operation promises, etc.) are not
in V1.

<a id="out-of-scope-promise-all-race-timeout"></a>
### Parallel / race / timeout combinators

No `promise_all([reqs])`, no `race([reqs])`, no `promise(req, timeout: 5.minutes)`
in V1. The first version is one request, one wait, one response. Combinators are a
natural V2 extension when real workloads ask for them.

<a id="out-of-scope-cancellation"></a>
### Cancellation

No external-cancel of an in-flight promise in V1. Once dispatched, the promise
runs to completion or to whatever the underlying HTTP layer does on failure.

<a id="out-of-scope-promise-objects"></a>
### Promise objects you can pass around

V1 `promise()` returns the resolved value directly, not a promise/future object.
Promise-as-a-first-class-value (passing pending promises between functions,
storing them in variables before awaiting) is a different design that would
require changes to the language's evaluation model. Not in V1.

<a id="out-of-scope-snapshot-revive-hooks"></a>
### `on_snapshot` / `on_revive` class hooks

No per-class hooks fire at snapshot or revive time **in V1**. The original
aspiration was "never to need them" — the worldlet is the single source of truth
for runtime state, and external-resource management belongs in the engine, not in
user code.

That position is softened by at least one concrete future use case:
**redaction of sensitive fields before serialization.** If a snapshot is written
to disk or over a network, sensitive fields (passwords, API tokens, session
keys) would be exposed in the serialized form. The class needs a chance to
sanitize itself before the snapshot is taken.

Sketch of the future API (NOT shipping in V1):

```caspian
class 'myapp.com/auth'
    @username = nil
    @password = nil

    on_snapshot do($call)
        $call.receiver.@password = nil    # redact; value lost forever
    end
end
```

`on_snapshot` fires for every reachable instance before the engine serializes
the worldlet. The handler can mutate `$call.receiver` to redact fields. The
mutation is permanent — once `@password` is nilled, the original is gone from
this snapshot. If the program continues running after the snapshot, it would
need to re-acquire the password (re-prompt, re-fetch, etc.) to use it again.

Possible sugar for the common "just null out these fields" case:

```caspian
class 'myapp.com/auth'
    redact_on_snapshot ['password', 'api_token']
end
```

Or a field-level annotation:

```caspian
class 'myapp.com/auth'
    @password = nil @redact
end
```

`on_revive` would be the companion hook firing after revival — useful for
re-establishing redacted state from a secure source. Less urgent than
`on_snapshot` (the program can do this lazily via normal code paths), but
natural to design alongside.

Open design questions to resolve before implementing:

- **Order of `on_snapshot` calls** across reachable instances. Probably
  undefined like `on_close`, with the same "don't depend on order" rule.
- **What happens if `on_snapshot` itself raises?** Probably the same engine-
  level catch + `state.gc_errors`-style log + continue pattern from
  [garbage-collection.md § Engine wraps the handler](../garbage-collection.md#on-close-catch-anything).
  Same time/allocation/I/O constraints might apply.
- **Mutation visibility to the live program.** If the program continues after
  the snapshot, do the redactions persist in the live worldlet? Probably yes —
  the redaction IS the mutation, and a program that snapshotted and continued
  would see the redacted state. (To preserve live state across a snapshot,
  the engine would need to copy-then-redact, doubling memory cost. Probably
  not worth it.)
- **Composition with non-redaction use cases.** If `on_snapshot` is the
  general "pre-serialize hook," other use cases might emerge (computed
  derivations, normalization, etc.). Worth scoping to "just redaction" for
  the initial implementation and resisting feature creep.

Until then, treat the absence of these hooks as deliberate for V1. **Programs
that handle sensitive data should not snapshot in V1.** When the hooks land,
revisit.

---

<a id="future-possibilities"></a>
## Future possibilities

These are not commitments, just things worth noting as the V1 design rules in or
rules out without saying so:

<a id="future-promise-all-and-race"></a>
### Parallel-promise combinators

If real workloads need to fire N HTTP requests and wait for all/any of them,
`promise_all([reqs])` and `race([reqs])` are the natural shape. The snapshot
mechanism doesn't need to change — only the dispatcher's correlation-tracking does.

<a id="future-non-http-promise-sources"></a>
### Non-HTTP promise sources

Filesystem, database, message queue, system-process-completion, human approval —
any operation that can be "fire and wait" is in principle a candidate. None
known to be needed for V1. Each new source would need its own request class
exposing `promise()`.

<a id="future-timeouts"></a>
### Timeouts

`puck.uno/http/request` could grow a `timeout` parameter that bounds how long
the wait can take before the promise raises a `puck.uno/error/timeout`. Same
under-the-hood — just expires the correlation ID after a deadline.

<a id="future-snapshot-replay-debugging"></a>
### Snapshot-as-debugging-tool

The snapshot infrastructure built for Skeletor is the same infrastructure
needed for time-travel debugging. Once Skeletor exists, "save the snapshot
on uncaught error, let the developer revive locally" is a small layer on top.

<a id="future-debugger-plugin-interface"></a>
### Debugger / inspector plugin interface

Caspian (or third-party "People" libraries) could expose hook points into
Skeletor at well-defined moments — pre-dispatch, post-dispatch, frame push,
frame pop, exception raise, on_close, etc. — letting an external library
participate in the debugging story without being baked into the engine.

A plugin sees the Skeletor hash at each hook, can read state, attach
metadata (via the reserved `comment`/`misc` pass-through fields), and
emit its own diagnostic output. Examples that fall out naturally:

- A profiler counting time per frame
- An invariant checker that asserts a property after every dispatch
- A logger that streams a structured trace of role transitions
- A `meta_src`-style provenance tracker that fills in source-location
  gaps for dynamically-generated code by observing creation sites
- A test-coverage instrumenter

This is well after V1.0 — needs Skeletor to be stable, needs the hook
interface to be designed (which hooks, what they can do, security model
for what plugins can read or modify, what isolation looks like). Noted
here so the V1.0 design doesn't preclude it.

---

<a id="open-questions"></a>
## Open questions

<a id="open-engine-permission-model"></a>
### Engine permission model

How does the embedding engine grant a Caspian program permission to call
`promise()`? Options sketched, none chosen:

- A capability passed at engine setup: `%engine.allow_promise(true)` or similar
- A role-based check: programs running in a certain role have it; others don't
- A method-missing-style runtime intercept: every `promise()` call asks the
  engine "is this allowed?"
- A static check at code load: program declares it uses promises; engine
  decides at load time

<a id="open-snapshot-storage-location"></a>
### Snapshot storage location

Where do snapshots live during the pause? Local disk on the host that wrote
them? A shared object store (Mikobase worldlet)? A network-accessible blob
store so a different host can pick up the revive? Affects whether crash
transparency works across host failures.

<a id="open-snapshot-format-versioning"></a>
### Snapshot format versioning

A snapshot taken with Caspian V1.2 — can it be revived by Caspian V1.3? V2.0?
If not, deployments mid-flight could leave un-revivable snapshots. Spec needs
a compatibility rule.

<a id="open-snapshot-ttl"></a>
### Snapshot TTL

A snapshot for a request whose response never arrives is a leak. How long does
the runtime hold a snapshot before giving up? Per-request? Global default?
On expiry, does the promise raise `puck.uno/error/timeout` (requiring revive
just to deliver the error) or just silently drop?

<a id="open-side-effects-during-pause"></a>
### Side effects during the pause

Between snapshot and revive, the outside world changes. Files get modified,
database rows change, other Caspian processes mutate shared Mikobase state.
The revived program assumes its view of the world is current — it isn't.
Same problem as restoring a backup. Worth a doc note; probably not solvable
at the runtime level.

<a id="open-dispatcher-implementation"></a>
### Dispatcher implementation

The external dispatcher (the thing that holds the HTTP request and watches for
the response) is its own component. Is it part of every Caspian engine? A
sidecar daemon? A Puck-protocol service that engines talk to? Different choices
have different operational costs.
