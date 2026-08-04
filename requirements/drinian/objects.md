# Objects

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_objects",
	"role": "spec for the objects hash inside Drinian — the top-level table that holds every live object's record, keyed by object ID from the global sequencer; complements built-in-classes/object/structure (which spec's what an object IS from the language surface) by describing how that structure is REPRESENTED inside the Drinian hash",
	"status": "draft — top-level shape, per-object fields (role / src / bucket / stack), the array-shape stack encoding, the sequence-counter ID scheme (with UUIDs for nested-object platters), class / variable / hash_element records, and object lifecycle. The three big shape questions (stack encoding, platter IDs, class-field value) are settled per Miko 2026-08-04; see Settled since first draft. Remaining open items are smaller (primitive-slot location, src on identity objects, stale on_close cross-ref)",
	"audience": "Caspian engine implementers building the object runtime and GC; tooling authors (inspectors, debuggers, snapshot readers) consuming Drinian snapshots"
}}
~~~

`objects` is a top-level field in the [Drinian](https://puck.uno/requirements/drinian/) hash. It holds every live object's record — variables, hashes, arrays, strings, numbers, class instances, and classes themselves — keyed by object ID. Everything the [`references`](https://puck.uno/requirements/drinian/references) hash points at resolves through here.

This page is the Drinian-internal companion to [built-in-classes/object/structure](https://puck.uno/requirements/built-in-classes/object/structure). That page describes what an object IS from the language's perspective (the bucket / stack / shadow / platter / nested-object model developers and class authors reason about). This page describes how that structure is **represented** inside the Drinian hash — the field names, the ID scheme, and the discipline the engine uses to keep both hashes in sync as the program runs.


## Top-level shape

`objects` is a hash keyed by **object ID**. Values are per-object records:

~~~json
"objects": {
	"9": {
		"role": "user",
		"src": ["a", 6],
		"bucket": {"0": "7", "1": "8"},
		"stack": [
			{"class": "core:array"}
		]
	},
	"10": {
		"role": "user",
		"src": ["a", 6],
		"bucket": {"value": "Aslan"},
		"stack": [
			{"class": "core:string"}
		]
	}
}
~~~

Every live object in the program has exactly one entry. When the engine collects an object (see [Object lifecycle](#object-lifecycle) below) its entry is removed. Nothing else in Drinian caches object records — the `objects` hash is the single source of truth for what each object IS; the `references` hash is the single source of truth for what each reference POINTS AT.

## Object IDs

Object IDs are integer-strings drawn from a single program-wide counter — the same counter that mints reference IDs and hash-element IDs. See [references § Object IDs](https://puck.uno/requirements/drinian/references#object-ids) for the counter's properties (stable within a run; not stable across runs; not designed for cross-process merging; no sigil).

A reference is itself an object (an instance of `core:reference` or one of its subclasses), so the same ID appears once as a key in `references` (where the value is the reference's target ID) and once as a key in `objects` (where the value is the reference's own record — its bucket, stack, and other per-object state). The two hashes work together: `references` holds bare pointers; `objects` holds the object records.

**Platter IDs are UUIDs, but most platters have no ID.** Only platters that carry a nested-object marker (`nested: <UUID>` per [built-in-classes/object/structure § Nested objects](https://puck.uno/requirements/built-in-classes/object/structure#nested-objects)) carry an ID — the UUID that links the platter to its matching bucket entry. Regular class platters are anonymous elements of the [stack array](#stack); they have no identity because they don't need one — their position in the stack is their identity. The UUID discipline exists specifically to avoid collisions with user-chosen field names inside the bucket, and the discipline is only load-bearing where a bucket entry has to point at a specific platter — the nested-object case.

## Per-object fields

Every entry in `objects` is a hash carrying at least `bucket` and `stack`. `role` and `src` appear when set. Additional optional fields (`comment` for annotation walkthroughs; see below) may appear in example snapshots but do not ship with real state.

### role

The role that owns this object — one of the string keys in [`state.roles`](https://puck.uno/requirements/drinian/#worked-example-drinian-mid-execution).

~~~json
"10": {
	"role": "user",
	"src": ["a", 6],
	"bucket": {"value": "Aslan"},
	"stack": [{"class": "core:string"}]
}
~~~

Semantics live in [drinian § Object ownership](https://puck.uno/requirements/drinian/#object-ownership) — short version: the object's role is the role of the code that *conceptually* creates it (the expression-evaluator), not necessarily the runtime frame doing the underlying work. A string produced by user code's `'a' + 'b'` is `role: "user"` even though the `+` method internally runs in an engine frame.

Once set at allocation, the field is immutable. Values can move between roles (be passed into a different-role function, returned to a different-role caller) but the ownership recorded here follows the value, not the value's current location.

**Frame role and object role answer different questions.** A frame's `role` (in `call_stack` entries) tells you whose code is executing in that frame right now. An object's `role` (in `objects` entries) tells you who owns the value. They coincide in most cases but are independent fields tracking independent things.

### src

The 2-element source tuple `[src_key, line]` recording where this object came into existence — the value's **birth line**, not the binding's. See [drinian § Source-location tagging](https://puck.uno/requirements/drinian/#source-location-tagging) for the full semantics (birth line follows the value through assignments and calls; operator-produced values get the operator's src; returns get the return statement's src).

`src` is **omitted** when there is no source line:

- Engine-created objects with no Caspian-source origin (the objects backing the built-in stdin/stdout/stderr streams, engine-allocated infrastructure objects).
- Objects produced from hand-written CaspM fixtures (no source file was ever registered).
- Truly source-less metaprogramming output (a method body constructed from a string via some future eval-like primitive).

Inspectors render omitted `src` as `(no source)`. The field is simply absent — no `null`, no sentinel.

Variable objects and hash-element objects (whose bucket and stack are engine-managed identity records; see [Variable objects](#variable-objects) and [Hash-element objects](#hash-element-objects) below) may or may not carry a `src` depending on their creation path — the sequencing examples currently show them without `src`, which reflects the current in-example convention rather than a settled rule. See the [Open questions](#open-questions) tail.

### bucket

The object's user-mutable data hash. See [built-in-classes/object/structure § Bucket](https://puck.uno/requirements/built-in-classes/object/structure) for the no-reserved-keys guarantee, the `@field` / `%bucket['field']` access model, and the freeze axes.

The bucket's **contents** — what shape the hash actually takes for a given class — depends on the class:

- **Primitives** carry their value under the key `"value"`:

	~~~json
	"10": {"bucket": {"value": "Aslan"}, ...}
	"12": {"bucket": {"value": 1},       ...}
	"13": {"bucket": {"value": "Lord "}, ...}
	~~~

	This is the Drinian representation of the [primitive field](https://puck.uno/requirements/built-in-classes/object/structure#primitive-field) — the engine-managed slot the primitive-subclass constructor writes at instantiation and never mutates afterward. <!-- SPEC CONFLICT: built-in-classes/object/structure § Primitive field says "the primitive field lives alongside the bucket, not inside it" and is "not exposed at the Caspian level; engine-level methods reach it directly." The drinian examples store the primitive value INSIDE the bucket under the key `"value"` — placing it exactly where the object/structure spec says it does not live. Two possibilities: (a) the drinian examples are using an inline shorthand for a slot the engine actually keeps outside the visible bucket, or (b) the Drinian-internal representation genuinely stores the primitive in the bucket under a reserved key. Needs Miko decision. If (a), the examples should either use a distinct field name (e.g., top-level `primitive: <value>` on the object record) or add a note that `bucket: {value: X}` is shorthand for "primitive field = X, bucket = {}". If (b), the no-reserved-keys guarantee in built-in-classes/object/structure § Bucket needs a carve-out for `"value"` on primitive-carrying classes. -->

- **Hashes** map user keys to hash-element **reference IDs**, not to target values directly. `{name: 'Picard'}` in Caspian becomes:

	~~~json
	"2": {"bucket": {"name": "3"}, ...}
	~~~

	where `"3"` is the ID of a `core:hash_element` object whose target (via `references`) is the string `"Picard"`. Mutation of `$hash['name']` rebinds `references["3"]` to a new target — the bucket is not touched.

- **Arrays** are hashes keyed by integer-string index, otherwise identical to hashes:

	~~~json
	"9": {"bucket": {"0": "7", "1": "8"}, ...}
	~~~

	Element `"7"` is a `core:hash_element` (index 0) targeting the array's first element; `"8"` is index 1's element.

- **Variables** have an empty bucket:

	~~~json
	"1": {"bucket": {}, ...}
	~~~

	The variable's binding lives in `references`, not the bucket. See [Variable objects](#variable-objects).

- **Hash elements** have an empty top-level bucket; parent+key metadata lives on the per-platter bucket (see [Hash-element objects](#hash-element-objects)).

- **User-class instances** hold their `@field` state as ordinary bucket entries — the shape is whatever the class stores in its instance data. No reserved keys.

When a bucket entry is a reference to another object, the entry's value is the **reference object's ID** (which resolves via `references` to the target object's ID). Buckets never hold bare target IDs — the indirection through a reference object is what lets mutation rebind without touching the bucket. See [references § Reference classes](https://puck.uno/requirements/drinian/references#reference-classes) for the reference-class hierarchy.

**Shorthand form used in drinian/index.md.** Several snippets in [drinian/index.md](https://puck.uno/requirements/drinian/) inline the target's value directly inside the bucket as `{"value": X, "src": [...]}` rather than routing through `references` + `objects`. That form is explicitly called out as a readability shorthand — the [Note on representation](https://puck.uno/requirements/drinian/#worked-example-drinian-mid-execution) at the top of that section points at [mid-execution](https://puck.uno/requirements/drinian/examples/mid-execution) as the authoritative full form. This spec follows the canonical form.

### stack

The stack in Drinian is an **ordered array of platters**. The platter at index 0 is the top; method dispatch walks from top to bottom. Same shape as the language-facing spec at [built-in-classes/object/structure § Stack](https://puck.uno/requirements/built-in-classes/object/structure#stack).

~~~json
"14": {
	"bucket": {"value": "hello, Aslan"},
	"stack": [
		{"class": "core:string"}
	]
}
~~~

Each element is a platter — a hash holding some subset of the engine-recognized platter fields. Most platters just carry a `class` (see the [class field](#class-objects) below for the still-open question of the class value's shape). Two special platter kinds:

- **Shadow.** A platter carrying `shadow: true` marks the object's shadow — the home for singleton methods on this one object. Optional; conventionally at index 0 when it exists. See [built-in-classes/object/structure § Shadow](https://puck.uno/requirements/built-in-classes/object/structure#shadow).
- **Nested-object marker.** A platter carrying `nested: "<UUID>"` links this platter to a nested object whose data sits at the matching UUID-keyed entry in the parent's bucket. This is the ONLY platter kind that carries an ID (a UUID) — regular class platters are anonymous positional entries. See [built-in-classes/object/structure § Nested objects](https://puck.uno/requirements/built-in-classes/object/structure#nested-objects).

A composite example — a text object with a foreground color as a nested object, a shadow with a singleton method, and a warning:

~~~json
"14": {
	"role": "user",
	"src": ["a", 6],
	"bucket": {
		"content":                              "hello, Aslan",
		"9c440335-a5fa-406a-8676-1da39a1a4617": {"r": 255, "g": 0, "b": 0}
	},
	"stack": [
		{"shadow": true, "class": {}},
		{"class": "core:text"},
		{"warning": "deprecated: use `format` instead"},
		{
			"nested": "9c440335-a5fa-406a-8676-1da39a1a4617",
			"class":  "core:color"
		}
	]
}
~~~

Reading the stack top-to-bottom: shadow first (owns any singleton methods; class is `{}` when empty), then the text class (dispatched by default), a warning-only platter (`class` absent, dispatch skips it), and finally the nested-color platter (the UUID marker links to the bucket entry holding the color's data).

### comment

Not a real field — a **walkthrough-only annotation** used in the drinian examples to explain what each frame or object records. The intro to [drinian § Worked example](https://puck.uno/requirements/drinian/#worked-example-drinian-mid-execution) says explicitly: "real Drinian snapshots won't carry them."

Objects, frames, and any other Drinian entry in an example doc can carry `"comment": "…"` to explain the entry to a reader; the engine strips or ignores the field. Do not rely on `comment` for any runtime meaning.

## Class objects

Per [drinian § Classes are in Drinian](https://puck.uno/requirements/drinian/#classes-are-in-drinian):

> In Caspian, classes are objects like anything else. Every class — built-ins (string, array, hash, integer, etc.), runtime-registered classes (via `Class.new`), library-defined classes when a library loads — lives inside Drinian as an object, alongside frames, roles, and every other object.

That means every class has an entry in `objects` keyed by its object ID, with the same per-object fields (`role`, `bucket`, `stack`) as every other entry. The class's methods (the CaspM AST for each method body) live inside that record — see [drinian § The AST lives in Drinian](https://puck.uno/requirements/drinian/#the-ast-lives-in-drinian).

### The value of a platter's `class` field IS the class object

Not an ID, not a hash, not a string. The **actual class object** — the same one every instance of that class shares. All three of the notations that appear across the specs are just different ways to *write down* that in-memory pointer in a documentation format where you can't literally embed a running object:

| Notation | Where it's used | What it means |
|---|---|---|
| `"class": "core:string"` | Drinian examples (mid-execution, references, this page) | Shorthand label. Not a string primitive; not an ID; not a lookup key — a stand-in for "the actual `core:string` class object" that keeps the JSON readable. |
| `"class": <full class-object hash>` | `built-in-classes/object/structure` § class | The canonical serialized form. When a snapshot writes the platter out, this is what lands on disk. |
| `"class": <object-ID reference>` | `drinian/index.md` § Classes are in Drinian describes it in reference terms | The in-memory shape. The platter holds a reference to the class object living elsewhere in `objects`. |

All three describe the same thing at different levels. The Drinian examples use the short label form because writing every class-object hash inline would make the examples unreadable, but readers should understand that when they see `"class": "core:string"`, the platter holds the class object itself (not a string; not something waiting to be resolved).

### Convention in the examples on this page and under `drinian/examples/`

Class values are written as short identifiers (`"core:string"`, `"core:array"`, `"core:hash"`, `"core:hash_element"`, `"core:variable"`, `"core:number"`, and so on). Treat the identifier as an alias for the class object it names; the object itself lives elsewhere in `objects` — the class entry that identifier resolves to has the same per-object shape as any other entry (its `bucket` carries the class's own state, its `stack` carries whatever platters the class itself sits on, and its `bucket` also holds the CaspM AST for each method body).

The [snapshot serialization](#snapshot-serialization) rule — every object serialized through its class's `to_json` — applies to class objects too. So a snapshot that reaches a class through some platter's `class` field serializes the class inline the first time it's seen; subsequent uses in that same snapshot reuse the earlier entry by reference. Details of that serialization discipline are the serializer's business, not this spec's.

### Stale cross-reference

The [on_close example](https://puck.uno/requirements/drinian/examples/on-close) still links to a section titled "Classes are NOT in Drinian" — the archive's old wording that no longer matches the current spec. That example's prose also asserts "Built-in classes are loaded into engine-private state during bootstrap," which disagrees with `drinian/index.md § Classes are in Drinian`. The example needs a rewrite pass to catch up. Filed at [Open questions](#open-questions).

## Variable objects

A [variable object](https://puck.uno/requirements/built-in-classes/variable-object/) — instance of `core:variable` — is a first-class object representing the storage slot of a variable. It appears in `objects` like any other object:

~~~json
"1": {
	"role": "user",
	"bucket": {},
	"stack": [
		{"class": "core:variable", "bucket": {}}
	]
}
~~~

The variable's bucket is empty. Its identity (the object ID `"1"`) is what makes it a variable; its target lives in `references["1"]`. Assignment to the variable (`$foo = $bar`) rebinds the entry in `references`; the object record in `objects` doesn't change.

**How the frame reaches the variable.** A frame's `locals` maps the source-level name to the variable's object ID:

~~~json
"locals": {"names": "1", "count": "2"}
~~~

Not to the value the variable currently holds — to the variable object. Resolving the name `$names` from inside the frame: read `locals["names"]` → `"1"` (variable object ID) → look up `references["1"]` → `"9"` (target object ID) → look up `objects["9"]` for the target's structure.

Same shape backs the `$$name` syntax that returns the variable object directly (see [variable-object § Syntax](https://puck.uno/requirements/built-in-classes/variable-object/#syntax)) — that syntax just returns the variable object without dereferencing to its target.

`core:variable` declares `uspace: true` (see [references § Uspace](https://puck.uno/requirements/drinian/references#uspace-a-class-level-property)), so variable objects are GC roots. Every reachability trace walks out from these.

## Hash-element objects

A `core:hash_element` is a reference-class object that represents a single key inside a hash (or a single index inside an array). It appears in `objects` with an empty top-level bucket; its parent-hash reference and its key live on its **per-platter bucket**:

~~~json
"7": {
	"role": "user",
	"bucket": {},
	"stack": [
		{"class": "core:hash_element", "bucket": {"parent": "9", "key": 0}}
	]
}
~~~

Reading: this hash element belongs to hash `"9"` at key `0`. When `$hash['name'] = 'new value'` executes, the engine finds the hash-element object for the `'name'` key and rebinds `references[hash_element.id]` to the new target. The parent-and-key metadata on the per-platter bucket is engine-managed identity; user code doesn't set or mutate it directly.

`core:hash_element` declares `uspace: false` — the element is only reachable if the hash containing it is reachable through some uspace root. Making the element itself a root would double-count.

See [built-in-classes/object/structure § Bucket (per-platter)](https://puck.uno/requirements/built-in-classes/object/structure) for the per-platter-bucket mechanism the `parent` + `key` live on — same shape any class that needs private per-instance state uses.

## How references point into `objects`

Every entry in `references` is a `ref_id → target_id` pair; both sides are object IDs. Every one of those IDs must resolve to an entry in `objects` — the invariant the engine maintains on every reference mutation.

To trace what a variable currently holds:

1. Read the variable's ID from the frame's `locals` (or from wherever else the ID appears).
2. Look up that ID in `references` — value is the target object's ID.
3. Look up the target ID in `objects` — value is the target object's record.

To trace who points at a given target: walk `references` looking for entries whose value equals the target's ID. The engine maintains an inverse index for this walk (see [examples/references § Engine-internal: the inverse index](https://puck.uno/requirements/drinian/examples/references#engine-internal-the-inverse-index)) so orphan detection stays O(1) rather than O(references).

## Object lifecycle

**Creation.** When the engine creates a new object (variable declaration, hash-key first-assignment, string literal materialization, class instantiation, operator result, etc.), it:

1. Allocates a fresh object ID from the shared sequencer.
2. Inserts a record in `objects` with the appropriate `role`, `src` (if the source line is known), initial `bucket` contents (empty for reference objects, `{"value": X}` for primitives, `{parent, key}` on the platter bucket for hash elements), and `stack` (the class platter that identifies what the object is).
3. If the object is a reference class (`core:variable`, `core:hash_element`, future reference kinds), also inserts a row in `references` pointing at the reference's initial target.

**Live.** The object stays in `objects` as long as any reachability trace from a uspace root reaches it. Every mutation to `references` (rebinding a variable, reassigning a hash key, popping a frame that owned locals, etc.) triggers a trace from candidate orphans; anything that reaches a uspace root stays.

**Collection.** When a trace determines an object is unreachable, the engine:

1. Fires the object's `on_close` hook (see [examples/on-close](https://puck.uno/requirements/drinian/examples/on-close) for the strict handler rules — 2ms cap, no I/O, no allocation, no resurrection, uncatchable timeout abort). The handler runs inside a `call_stack` frame with `action: "on_close"`; the dying object stays alive for the duration of the handler via `$call.receiver`.
2. If the handler raises, the engine catches the error, appends a record to `state.gc_errors`, and continues — one bad handler doesn't break GC for other objects.
3. Removes the object's entry from `objects`.
4. Removes any `references` entries where the collected object was the target.
5. If the collected object was itself a reference (its ID appears as a key in `references`), removes that entry too.
6. Recurses on any objects orphaned by steps 4-5.

The object stays in `objects` until its collection completes. An inspector reading a snapshot mid-collection sees the dying object still present in `objects` with a frame carrying `action: "on_close"` on top of `call_stack`.

## Bucket shapes at a glance

Quick reference for the bucket shape a common class produces. Not a class-defining spec — the class defines its bucket; this table records what the drinian examples currently show.

| Class | Bucket | Notes |
|---|---|---|
| `core:variable` | `{}` | Binding lives in `references`; nothing on the object |
| `core:hash_element` | `{}` (top-level); `{parent, key}` on the per-platter bucket | Parent-hash ID and key |
| `core:string` | `{"value": "<utf-8 bytes>"}` | See SPEC CONFLICT at [bucket](#bucket) on whether `"value"` is a bucket key or an out-of-bucket engine slot |
| `core:number` | `{"value": <numeric>}` | Same conflict |
| `core:array` | `{"0": <ref_id>, "1": <ref_id>, …}` | Integer-string keys; values are `core:hash_element` reference IDs |
| `core:hash` | `{<user_key>: <ref_id>, …}` | Keys as-written by user; values are `core:hash_element` reference IDs |
| User class instance | `{@field_name: <value_or_ref_id>, …}` | Whatever the class stores in instance data |

## Snapshot serialization

The `objects` hash is written verbatim in a post-V1.0 snapshot (see [drinian § V1.0 scope](https://puck.uno/requirements/drinian/#v1-0-scope)): the top-level shape passes through unchanged, and each object's record serializes via the object's class's `to_json` method per [references § Snapshot serialization](https://puck.uno/requirements/drinian/references#snapshot-serialization).

Redaction of sensitive fields happens at that per-object serialization step through the deferred [on_snapshot hook](https://puck.uno/requirements/drinian/#on_snapshot--on_revive-class-hooks) — the object mutates its own bucket before the serializer reads it. The `objects` hash structure is unaffected; only the content of individual buckets changes.

V1.0 does not ship snapshot serialization; the objects hash exists in memory only. But the shape is fixed with serialization in mind: every field is representable in JSON without further encoding, integer-string keys round-trip losslessly, and no reference to a raw native handle appears at this level (native handles belong on the engine sidecar; see [ideas/drinian § Everything in Drinian is serializable](https://puck.uno/ideas/drinian/#everything-in-drinian-is-serializable) for the post-V1.0 direction). <!-- outbound-link-allowed - this is the design-brainstorm doc for the serialization discipline; the requirements tree does not yet own the serialization spec. Miko: replace with a requirements/ link once the serialization spec lands. -->

## Settled since first draft

- **Stack encoding: array.** Objects store platters in an ordered array, not a hash. Position 0 is the top; dispatch walks top-to-bottom. Matches [built-in-classes/object/structure § Stack](https://puck.uno/requirements/built-in-classes/object/structure#stack).
- **Platter IDs: UUIDs, but only for nested-object platters.** Regular class platters are anonymous positional entries with no ID. The UUID discipline exists specifically to link a nested-object platter to its matching bucket entry ([built-in-classes/object/structure § Nested objects](https://puck.uno/requirements/built-in-classes/object/structure#nested-objects)); it does not apply to stack platters generally.
- **`class` field on a platter: the actual class object.** Not a string, not an ID, not a hash — the class object itself. The three notations that appear across the specs (short identifier like `"core:string"`, full inline class-object hash, object-ID reference) are all different ways to write down the same in-memory pointer for a documentation format that can't literally embed a running object. See [Class objects](#class-objects) above.

All three decisions from Miko, 2026-08-04.

## Open questions

- **Where the primitive value actually lives.** [built-in-classes/object/structure § Primitive field](https://puck.uno/requirements/built-in-classes/object/structure#primitive-field) says the primitive field is "engine-managed" and "not exposed at the Caspian level," living "alongside the bucket, not inside it." The drinian examples put it inside the bucket under the key `"value"`. If the Drinian representation genuinely stores the primitive in the bucket, the no-reserved-keys guarantee for primitive-carrying classes needs revision. If the examples are using shorthand for a slot the engine stores outside the visible bucket, the shorthand should be spec'd out and the examples rewritten to show the real shape.

- **`src` on variable and hash-element objects.** The drinian examples currently show these without `src`. That may be because they're engine-managed identity objects born through the reference machinery rather than through a Caspian-source expression, in which case omission is correct. Or it may just be an oversight in the current examples. Needs a settled rule (probably: variable objects born from `$foo = X` on line N carry `src: ["file", N]`; anonymous engine-created reference objects do not).

- **The examples don't yet show class-object entries.** Per [drinian § Classes are in Drinian](https://puck.uno/requirements/drinian/#classes-are-in-drinian) every class has an `objects` entry; per the [class-field decision](#class-objects) above, the `"core:string"` label on a platter is shorthand for the actual class object. But the examples elide the class entries themselves — every `"core:string"` etc. in the current examples "resolves" to a class entry that doesn't appear in the JSON alongside the regular objects. Rewriting the examples to include even one class entry inline would make the shape concrete, at the cost of blowing up the example's size. Deferred until Miko wants the example to teach class-object structure explicitly.

- **The stale on_close.md cross-reference.** `examples/on-close.md` still links to the archive's "Classes are NOT in Drinian" section and asserts classes live in engine-private state. Neither matches the current spec. Needs a rewrite pass.

- **Object equality across snapshots.** Object IDs are not stable across runs (per [references § Object IDs](https://puck.uno/requirements/drinian/references#object-ids)). If a snapshot survives across runs (post-V1.0 revive), the ID scheme survives with it because it's part of the snapshot; but two independent snapshots from different processes have colliding IDs. Not solved at the engine level.

## Related

- [drinian](https://puck.uno/requirements/drinian/) — the overall Drinian state hash, of which `objects` is a part.
- [drinian/references](https://puck.uno/requirements/drinian/references) — the references hash that points into `objects` and grounds GC.
- [drinian/examples/mid-execution](https://puck.uno/requirements/drinian/examples/mid-execution) — the fullest worked example of the `objects` hash in use.
- [drinian/examples/references](https://puck.uno/requirements/drinian/examples/references) — smaller worked example focusing on how `references` and `objects` interlock.
- [built-in-classes/object/structure](https://puck.uno/requirements/built-in-classes/object/structure) — the language-facing spec for what an object IS (bucket / stack / platter model). This page's Drinian-internal shape aligns with that spec after the 2026-08-04 decisions on stack encoding, platter IDs, and the class-field value; the one remaining shape disagreement is the primitive-slot location, still flagged inline.
- [built-in-classes/variable-object](https://puck.uno/requirements/built-in-classes/variable-object/) — the Caspian-level spec for the variable class whose instances appear in `objects` as GC roots.
