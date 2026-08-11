# Cost-if-you-don't-use-it audit

~~~vibecode
{"vibecode": {
	"doc": "ideas_cost_if_you_dont_use_it_audit",
	"role": "audit report identifying features in requirements/ and ideas/ that impose costs on programs that don't use them; frame for redesign or acceptance",
	"status": "audit complete 2026-07-30",
	"audience": "Miko and other spec reviewers weighing whether each finding is well-spent cost, worth redesigning, or worth deferring"
}}
~~~

Applies the check from [concepts § Cost if you don't use it](https://puck.uno/requirements/concepts#cost-if-you-dont-use-it): does the feature add cycles, memory, or complexity to every program regardless of whether the program uses it? Findings organized by how universal the tax is.

## LOAD-BEARING

### String `contributors` list on every string

- **Spec:** [roles/string-contributors](https://puck.uno/requirements/roles/string-contributors).
- **Cost:** every String instance carries a `contributors` array. Every string-producing operation (`+`, interpolation, `.slice`, `.upper`, `.lower`, `.strip`, `.replace`, etc.) must compute the union of every input's contributors. Also a per-composition allocation.
- **Non-users pay:** a single-role program never has more than one contributor per string, but every string still carries `[user]`, every concatenation still allocates and unions.
- **Alternative:** lazy list — a string starts with `contributors: null` (meaning "same as owner role"); the array is only materialized on first cross-role composition. Programs that never mix roles across a string boundary bear zero cost.
- **Suggested action:** redesign to lazy shape.

### Per-value `src` birth-line tagging in CVM

- **Spec:** [cvm § Source-location tagging](https://puck.uno/requirements/cvm/#source-location-tagging).
- **Cost:** every value in CVM (locals, chain entries, hash values, array elements) can carry a `src` tuple. The transpiler populates `line` on every CaspJ node; propagation is "copy the line during materialization" — one helper applied at every value birth. Snapshot growth estimated at 5-10%.
- **Non-users pay:** programs that never inspect stack traces or use a debugger still pay the per-value tuple allocation and the per-op line-copy on every value birth (arithmetic result, function return, literal materialization).
- **Alternative:** the spec already contemplates `normalize(caspj, {lines: false})` for stripping — extend the strip opt to a runtime engine-mode "cheap mode" that omits `src` on ordinary value births and reconstructs only for the frame carrying the exception. Debug-mode engines keep the current shape.
- **Suggested action:** engine-mode selection; the machinery is already there, wire the toggle.

### No-interning for primitive literals

- **Spec:** [primitives § No interning](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets#no-interning-every-primitive-literal-is-a-fresh-instance).
- **Cost:** every `true`, `false`, `null`, `5`, `''` literal allocates a fresh instance with its own bucket. The rationale is enabling per-instance bucket writes (downloaded methods attaching `@debug_id`) and per-instance null flavors.
- **Non-users pay:** the vast majority of Caspian code never writes buckets on booleans or null. Every literal encountered still allocates. Hot loops that reference `null` or `true` are the most affected.
- **Alternative:** the spec already notes "the runtime can still choose to represent bare (empty-bucket) primitives compactly at the engine level — that's an internal optimization, invisible at the Caspian level — but it can't collapse two literal mentions into a single shared object." Copy-on-write with a shared compact backing until the first bucket write is exactly the shape needed.
- **Suggested action:** accept the language semantic; require the reference engine to implement COW-on-bucket-write in [primitive-buckets](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets) as a hard mandate, not a hint.

### Reference-table + back-refs double-bookkeeping

- **Spec:** [mvm/references](https://puck.uno/requirements/cvm/references) and [ideas/drinian § The reference table](https://puck.uno/ideas/drinian/#the-reference-table).
- **Cost:** every reference (variable, hash element) has an entry in `references`. The idea doc adds a mandatory inverse `back_refs` index. Every assignment is a delete+add pair; every mutation cascades through triggers.
- **Non-users pay:** programs that never trigger GC (short-lived scripts) and programs that never form cycles still pay per-mutation back-refs maintenance. It's the same tax whether the program allocates one cycle or none.
- **Alternative:** the trace design pays for itself only when cycles form. Refcount-first with cycle-detection-on-suspicion (Python's approach) skips back-refs maintenance in the common case.
- **Suggested action:** flag for design review before promoting the ideas/drinian back-refs proposal — the promise is O(1) cycle detection but the cost is per-mutation, and most programs never cycle.

## MODERATE

### Every scope frame's element is a note-deleted hash

- **Spec:** [lua/scope § Scope elements](https://puck.uno/requirements/lua/scope#scope-elements).
- **Cost:** every scope element sets `.note_deleted = true` at creation, so the walker can distinguish "never bound" from "explicitly deleted." Programs that never `%bucket.delete` a scope-shadowed name pay the tombstone-set overhead per frame.
- **Non-users pay:** the option-in is per-scope-frame, so every begin/if/while/for/function push allocates the tombstone container. Small but universal.
- **Alternative:** lazy — leave `note_deleted` false; flip it and start tracking only when a delete happens.
- **Suggested action:** defer — small enough that the design cleanliness is worth it.

### `%amber` layer allocation on every frame push

- **Spec:** [amber § Aggregate-hash mechanics](https://puck.uno/requirements/amber#aggregate-hash-mechanics).
- **Cost:** the testing rule "Aggregate-hash push and pop are O(1) per frame. Frame push adds an empty amber layer" confirms per-frame allocation. Programs that never call `%amber.init` still allocate an empty layer per frame.
- **Non-users pay:** small allocation per push, but a real one.
- **Alternative:** lazy — no amber layer until the first `.init` in the current frame; walks stop at the first amber-carrying ancestor.
- **Suggested action:** redesign to lazy layer creation before amber ships.

### Warning / vibecode / nested / per-platter buckets on every object

- **Spec:** [object structure § Stack](https://puck.uno/requirements/built-in-classes/object/structure#stack).
- **Cost:** each platter can carry six recognized fields. Method dispatch has to skip past class-less platters (warning-only, vibecode-only, nested-link). The instructions to dispatch check for the presence of each field.
- **Non-users pay:** programs that never attach warnings, vibecode, or nested objects still have dispatchers that check for these fields on every platter walked.
- **Alternative:** most platters carry only `class`. Dispatch's default-fast-path can check "is this platter a plain class?" (single field, most common shape) and skip the six-field probe unless the platter looks unusual.
- **Suggested action:** implementation-only concern; note in the [object structure Implementation notes] section if profiling shows dispatch dominance.

### Frame `lexical_parent` field on every frame push

- **Spec:** [cvm § lexical_parent is the scope chain](https://puck.uno/requirements/cvm/#worked-example-cvm-mid-execution).
- **Cost:** every frame carries `lexical_parent`. For if/for/while/do frames it's the enclosing frame (redundant); for function_call it's the definition-site frame.
- **Non-users pay:** every block-frame push writes a lexical_parent that equals "the frame below." Redundant per-push cost.
- **Alternative:** omit lexical_parent when it equals `call_stack.length - 1` (implicit-parent optimization). Only function_call frames whose lexical parent differs from the physical parent carry it.
- **Suggested action:** implementation optimization; document in implementation notes.

## LOW

### Bootstrap seeding of chain capabilities from `%engine`

- **Spec:** [initial-state § The chain is populated from %engine](https://puck.uno/requirements/initial-state#the-chain-is-populated-from-engine).
- **Cost:** at bootstrap, the engine walks every host-provisioned `%engine` slot and seeds the corresponding chain capability. One-time cost bounded by the fixed slot list.
- **Non-users pay:** a hello-world program pays the full seed walk even though it will use one slot at most.
- **Alternative:** lazy per-capability — seed on first access. Given the slot count is small (~11) and startup is once per program, the current eager form is fine.
- **Suggested action:** accept — startup cost is bounded and one-time.

### Captured stack O(depth) on every exception raise

- **Spec:** [cvm § Capture-by-reference: the cost model](https://puck.uno/requirements/cvm/#capture-by-reference-the-cost-model).
- **Cost:** every exception raise allocates `O(stack_depth)` pointers into `captured_stack`. Typical depths are 5-50 frames.
- **Non-users pay:** programs that raise without inspecting the captured stack still pay the pointer array.
- **Alternative:** capture on first access to `.captured_stack` rather than at raise time — the frames haven't popped yet, so a lazy capture works.
- **Suggested action:** the spec explicitly analyzes and accepts this cost; leave as-is.

## Non-findings

### Events (`.broadcast` / `.listen`)

- [ideas/events](https://puck.uno/ideas/events/). Zero cost when nothing is listening — a single hash lookup misses and the broadcaster returns. Explicitly designed for the invariant. The concept doc cites this as the exemplar.

### Class-listeners inheritance walk

- [ideas/listen-to-class § Cost when nothing uses class-listeners](https://puck.uno/ideas/listen-to-class#how-dispatch-works). O(inheritance depth) hash misses if no class-listeners are registered. Bounded (inheritance depth 3-5 in real code) and each miss is a single hash-table lookup. Design already reasoned through.

### Capability `.grant` / `.revoke` machinery

- [global-methods § Capability objects](https://puck.uno/requirements/global-methods/#capability-objects). Programs that never grant / revoke pay only the ordinary chain hash lookups that the language uses for other reasons. Concept doc cites this too.

### Method-resolution walk-per-call (no cache)

- [classes/method-resolution § No cache](https://puck.uno/requirements/classes/method-resolution#no-cache). Explicitly reasoned: the invalidation logic for a cache would cost more than the walk saves, given classes and objects are mutable. Well-spent cost, spec has receipts.

### Aggregate hash primitive underlying `%chain`, scope, class resolution

- [lua/aggregate-hash](https://puck.uno/requirements/lua/aggregate-hash). Concept doc lists this in the "well-spent universal cost" category. One primitive shared by many chain-of-hashes patterns; no per-feature tax.

### Object shadow platter

- [object structure § shadow](https://puck.uno/requirements/built-in-classes/object/structure#shadow). Explicitly lazy — the shadow comes into existence only when code defines a singleton method. Programs that never use singleton methods pay nothing.

### Object truthiness bit

- [primitive-buckets § Truthiness](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets#truthiness). Single header bit set at construction; the check is one header lookup with no dispatch. Universal but the design is what makes the check O(1) — the alternative (walk class hierarchy at every truth check) is what would tax everyone.

### `.new()` role assignment

- [object-access § Class instantiation is not an exception](https://puck.uno/requirements/roles/object-access#class-instantiation-is-not-an-exception). The role tag on every new instance is set by the creator-owns rule with one comparison. Universal but O(1); no alternative shape avoids it while keeping provenance answerable.

### `%import` cache

- [import § Two levels of caching](https://puck.uno/requirements/import#two-levels-of-caching). Programs that never `%import` pay nothing; the cache is populated per-URL on demand.
