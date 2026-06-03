# Base class use

> **Stale.** Flagged in [issue 364](https://github.com/mikosullivan/puck/issues/364). The concepts here are about 90% right and the doc is useful as historical context, but the platter model is being redesigned from scratch rather than patched. Treat specific details here — per-platter bucket shape, hash-keyed-by-UUID layout, pinned/mutable region split, sticky/active flags, marker-class examples — as **previously proposed, not current spec**. Other docs that lean on this one (Trivet's per-platter storage, garbage collection's `on_close` multicast across platters, Mikobase requirements, lucy.md's object model) inherit the same caveat where they cite this doc's mechanisms.

~~~json
{"vibecode": {
	"doc": "base_class_use",
	"role": "exploring per-instance class chains as a primary mechanism for adding behavior to objects in Caspian — instead of subclassing, augment plain values with classes at runtime; also proposes per-platter private storage by enriching the classes array entries",
	"status": "stale; see banner at top of file and issue 364. Concepts ~90% right; redesign-from-scratch is the path forward.",
	"key_concepts": ["per_instance_class_chain", "tag_classes", "marker_classes",
		"capability_stamps", "behavior_addition_at_runtime",
		"alternative_to_subclassing", "sticky_vs_removable",
		"chain_order", "method_conflict",
		"platter_metaphor", "per_platter_bucket", "platter_records",
		"class_vs_classes_resolution"]
}}
~~~

This document explores an alternative way to add behavior to objects
in Caspian: **per-instance class chains** that can be modified at
runtime. Instead of declaring a subclass to extend a base type, a
program adds a class directly to an instance's chain. The instance
keeps its original base class but gains the methods, identity, and
markers contributed by the added class.

Caspian already supports this mechanism; this doc is about
formalizing it as a design pattern and exploring what it enables.

<a id="the-pattern"></a>
## The pattern

The canonical example:

~~~caspian
$foo = 'string'
$foo.object.classes.add 'foo.uno/upper'

puts $foo    # STRING
~~~

`$foo` starts as a plain string. Adding `foo.uno/upper` to its
class chain augments the instance — `puts` dispatches through the
chain, finds `foo.uno/upper`'s `to_string` override, and emits the
uppercased form.

The instance is still a string. It's just *also* a `foo.uno/upper`.
The class chain holds both, and method dispatch walks the chain.

**Dispatch order** (per
[lucy.md § The Class Stack](../requirements/caspian/lucy/index.md#the-class-stack)):
the shadow class is consulted first, then the class stack is walked
from top to bottom. The class an object was created with sits at
the bottom (first pushed). Subsequent `.classes.add` calls push to
the top — so **later additions shadow earlier ones**. There's no
privileged "base class"; the class an object is born with is just
the first in the stack.

This is why the `foo.uno/upper` example works: adding it puts it
above the original string class, so its `to_string` wins dispatch.

<a id="canonical-example-marker-classes"></a>
## Canonical example: marker classes

The simplest case is a class with **no methods**, just identity. The
engine and other code can read whether the marker is present to make
decisions.

The cleanest concrete example is `puck.uno/class/redact` (see
[snapshot redaction](https://github.com/mikosullivan/puck/issues/336)):

~~~caspian
@password = nil
$pw = secure_input()
$pw.object.classes.add 'puck.uno/class/redact'   # mark as sensitive
@password = $pw
~~~

The marker class adds nothing to `$pw`'s behavior during normal
execution. At snapshot time, the engine walks the class chain, sees
the marker, and emits `null` instead of the password's contents.

This is the cleanest possible use of per-instance class chains —
the class is purely a tag the engine reads.

<a id="what-this-pattern-enables"></a>
## What this pattern enables

- **Tags / markers** — classes with no methods, just identity. Read
  by the engine or by other code. Examples: redact, `audit_logged`,
  `tainted`, `validated`, lifecycle markers.
- **Capability stamps** — a value carries a class that asserts
  something about it. A value from user input carries `unvalidated`;
  trying to use it in a sensitive context raises until a
  `validate()` removes the stamp.
- **Per-instance behavior** — exactly the `foo.uno/upper` case. Two
  strings with the same content can behave differently because they
  have different class chains. Useful for instance-specific
  formatting, rendering, or serialization rules.
- **Cross-cutting concerns** — logging, profiling, debugging hooks
  added to specific values without changing the base class
  definition. The base class stays clean; instances opt in.
- **Lightweight composition** — instead of declaring a subclass for
  every variation, classes are mixed in à la carte. Closer to roles
  or traits than inheritance.

<a id="trade-offs"></a>
## Trade-offs to resolve

- **Class chain order is settled.** Push goes to the top of the
  stack (under shadow); dispatch walks top-to-bottom; later
  additions shadow earlier ones. See
  [lucy.md § The Class Stack](../requirements/caspian/lucy/index.md#the-class-stack).
- **Method conflicts between multiple added classes follow the same
  rule.** If two added classes both define `to_string`, the more
  recently added one wins because it sits higher in the stack.
  A class that needs to dispatch to a class lower in the stack
  uses `$obj.object.call_with($lower_class, 'method', ...)`.
- **Sticky vs removable.** Per-platter, not per-class. Each platter
  record carries its own `sticky: true` field if it's a sticky
  platter (omitted otherwise). See [Pinned and mutable regions](#pinned-and-mutable-regions)
  below for the full positioning rules.
- **Dispatch performance.** A per-instance class chain costs more
  than fixed-class dispatch. Implementations need cache-friendly
  representations — probably a denormalized class-chain pointer
  per instance, or a method-resolution cache.
- **Snapshot/revive of augmented instances.** The class chain has to
  be in the snapshot so revive reconstructs the same augmented
  behavior. Markers, capability stamps, and behavior-adding
  classes all need to round-trip.
- **Interaction with the `references` hash.** Each instance's
  class chain is part of its identity, stored on the object
  itself. The `references` hash maps reference objects to their
  targets but doesn't track classes attached to those targets;
  class membership is read directly off each object's `classes`
  field. No sibling concept needed.

<a id="pinned-and-mutable-regions"></a>
## Pinned and mutable regions

The class stack has two regions:

- **Pinned region** at the top — contiguous platters that are fixed
  in position. Cannot be moved, removed, or replaced. Engine-managed.
- **Mutable region** below — where user-added platters live.
  `.classes.add` inserts at the top of this region (which means
  immediately below the pinned region).

Visualized:

```
top of stack
   ↓
   ┌─────────────────────┐
   │ shadow              │  ← pinned, empty by default
   │ (other pinned)      │  ← pinned (e.g., truthiness)
   ├─────────────────────┤  ← pinned/mutable boundary
   │ <most recent add>   │  ← top of mutable region
   │ ...                 │
   │ <original class>    │  ← bottom of mutable region
   └─────────────────────┘
   ↓
bottom of stack
```

**Pinned platters** are added at instantiation by the engine and
locked at their absolute position. The pinned region grows
**downward** as the engine adds more — newer pinned platters
attach below older ones.

**`.classes.add` is engine-aware.** It finds the pinned/mutable
boundary and inserts above the top of the mutable region but
below the pinned region. User code can't accidentally push
something into the pinned region.

**Attempts to manipulate platters in the pinned region fail.**
Calling `.classes.remove(<pinned-id>)` raises; calling
`.classes.move(...)` on a pinned platter raises.

**Sticky platters in the mutable region** can be moved within
the mutable region but cannot be removed. If a sticky platter
drifts upward and touches the bottom of the pinned region, it
gets absorbed into the pinned region (locks at that position).

<a id="dispatch-after-unification"></a>
### Dispatch after the unification

Method resolution is now just "walk the stack top to bottom" —
no special rule for the shadow class. The shadow happens to be
at the top because it's a pinned platter at the top, not because
of a separate rule. The same is true for the `puck.uno/truthiness`
platter when present — it's a pinned platter in the pinned region,
participating in normal dispatch order. See
[object.md § Mechanism](../requirements/caspian/built-in-classes/object.md#bool-mechanism)
for how the truthiness platter encodes null / false / true via a
single class with a bucket-carried `truthy` field.

`$foo.object.classes` returns all platters in stack order
(top to bottom), **including the shadow platter at position 0**.
Programs that want to iterate only "user-relevant" platters can
filter by sticky/class-uns/etc.

<a id="engine-only"></a>
### `engine_only` class property

A class can declare `engine_only: true` at the class level. The
engine then refuses any `.classes.add` call that targets that
class — only the engine itself can push such a platter (typically
during primitive instantiation).

This is the mechanism behind locked-at-instantiation identity
properties. `puck.uno/truthiness` declares `engine_only: true`,
so a program can't fake its way into changing an object's
truthiness by adding the platter after the fact. Same idea
applies to any future identity-bearing platter that must only
exist when the engine put it there.

The property is at the class level, fixed for the class's
lifetime. Unlike `sticky` (which is per-platter and tracks
"can this be removed from this object"), `engine_only` tracks
"can user code create instances of this on any object." Both
properties can apply to the same class — typically do, since
identity-bearing platters are both pinned and engine-only.

There's no opt-out. The developer's "out" is to instantiate the
object they actually want — not to mutate identity after the
fact.

<a id="three-immutable-primitives"></a>
### Three immutable primitives

`null`, `true`, and `false` are special: their class stacks are
**fully locked**. You cannot:

- `.classes.add` anything to them
- `.classes.remove` anything from them
- Define methods on their shadow classes
- Mutate their buckets

The whole object — class stack, shadow, bucket — is engine-frozen.

Why: if any program could mutate `true` or `null`, every truthiness
check everywhere becomes unreliable. The cost of safety here is
absolute — these primitives sacrifice flexibility entirely so
everything else can rely on them.

The shape of a `null` (illustrative):

```json
{
    "classes": {
        "<shadow-id>": {"class": "puck.uno/class/shadow",  "bucket": {}},
        "<truthiness-id>": {"class": "puck.uno/truthiness",    "bucket": {"truthy": null}}
    },
    "bucket": {}
}
```

The shape of a `false`:

```json
{
    "classes": {
        "<shadow-id>": {"class": "puck.uno/class/shadow",  "bucket": {}},
        "<truthiness-id>": {"class": "puck.uno/truthiness",    "bucket": {"truthy": false}}
    },
    "bucket": {}
}
```

The shape of a `true` is the same as `false` but with
`bucket: {truthy: true}`. (Or `bucket: {}` — the absent and
`truthy: true` encodings are equivalent.)

Both platters are pinned. `puck.uno/truthiness` is also `engine_only`
(see above), which is what blocks `.classes.add 'puck.uno/truthiness'`
on a previously-truthy object. The entire primitive is immutable —
adding or removing anything raises.

<a id="alternative-not-replacement"></a>
## Alternative, not replacement

Subclassing still exists in Caspian. This pattern is a different
way to compose behavior, not the only way.

When to use which:

- **Subclassing** — when the new behavior is a coherent type with
  its own identity, used widely, defined statically. E.g.,
  `myapp.com/connection` extends a stream base class.
- **Per-instance class chain** — when behavior is per-instance,
  added dynamically, or used as a tag rather than a type. The
  base class doesn't change; specific instances get augmented.

The two coexist because they solve different problems.

<a id="per-platter-buckets"></a>
## Per-platter private storage

A class in the stack is a **platter** (mental metaphor: LP records
stacked on a turntable). Today every platter shares the same
`%bucket` for instance data — collisions between platters are the
developer's responsibility, and mix-ins manage the problem with the
soft `uns.<UNS>` namespace convention.

**Proposed change:** each platter gets its own private bucket,
formalizing what the `uns.<UNS>` convention has been doing by hand.

<a id="proposed-shape"></a>
### Proposed shape

Today the object's universal shape is `{bucket, classes}`, where
`classes` is a list of class references:

```json
{
    "bucket": {},
    "classes": [
        "foo.bar/gup",
        "foo.bar/bear"
    ]
}
```

The proposal changes `classes` from an array of class names into
a **hash keyed by platter ID**, with each value being a platter
record (the class reference plus its own private bucket):

```json
{
    "bucket": {},
    "classes": {
        "<id-1>": {"class": "foo.bar/gup",  "bucket": {}},
        "<id-2>": {"class": "foo.bar/bear", "bucket": {}}
    }
}
```

**Platter IDs are UUIDs** generated fresh per allocation from
libsodium. Object IDs use the engine's global sequencer
(integer-strings), but platter IDs cannot — they appear as **keys
inside user buckets** (via the per-platter-marker mechanism in
[nulls.md § Serialization](../requirements/caspian/built-in-classes/nulls.md#serialization))
where they need to be collision-safe against arbitrary user-chosen
field names. An integer-string `"7"` could collide with a user
bucket key; a UUID's 128-bit address space can't, in practice.

**Every UUID comes fresh from libsodium per call. No caching, no
seeded PRNG.** Caches and PRNG state are attack vectors — anyone
who can read them gets future UUIDs, which matters because
Mikobase record_pks leak externally through worldlet exports and
query results. Cache-based optimizations were considered and
rejected on security grounds; see
[#354](https://github.com/mikosullivan/puck/issues/354).

Why a hash, not an array of `{id, class, bucket}` records: the
ID is the platter's natural identifier, so putting it in the
key position (instead of repeating it inside each value) is
cleaner and gives O(1) lookup. Caspian's hashes preserve
insertion order, so the class stack's dispatch order (top to
bottom) is maintained naturally — the engine's `.classes.add`
method handles "add to the top of the stack" without exposing
hash-internal positioning to the user.

The top-level object's shape stays `{bucket, classes}` — same two
keys, no new universal reserved key. What changes is the shape of
the `classes` field: hash instead of array, entries are platter
records keyed by ID.

<a id="design-rationale"></a>
### Design rationale

Two strong constraints shaped this:

- **The bucket should be absolutely free-form, no reserved keys.**
  This rules out formalizing `bucket.uns` as an engine-managed
  namespace. The `uns.<UNS>` convention stays a soft convention,
  not a runtime mechanism. The top-level bucket remains genuinely
  developer-owned, with no special keys.

- **The object's universal shape should stay simple.** Adding a
  third top-level key like `other_buckets` or `platter_buckets`
  would change the shape every doc and tool understands. Even
  objects that never use per-platter storage would pay the
  conceptual cost.

The platter-record shape resolves both: top-level shape is
unchanged (still `{bucket, classes}`), and the bucket-no-reserved-
keys rule is preserved (it now applies recursively — both the
top-level bucket and each platter's own bucket are free-form).

<a id="bucket-policy"></a>
### Bucket policy

**The `bucket` field has no requirements beyond being a hash.**

This applies to every bucket in the system — the top-level
object bucket, every platter's private bucket, and any future
bucket the language introduces. The rules are minimal and uniform:

- **Buckets are always hashes.** The engine enforces this — a
  bucket is always a hash (possibly empty), never a scalar, array,
  or null. Code reading a bucket can rely on getting a hash; code
  writing to a bucket can rely on the container being a hash.
- **No reserved keys.** Inside any bucket, every key is the class
  designer's choice. The runtime never claims a key for its own
  purposes. There is no `uns`-reserved key, no `_meta`-reserved
  key, no `__type__`-reserved key — nothing.
- **No reserved value shapes.** Values inside a bucket can be any
  Caspian value. The runtime doesn't require certain keys to map
  to certain types.

The point of this policy: a bucket is purely the class designer's
storage. No mental overhead about which keys the runtime cares
about, no future-proofing against possible reservations, no
collision risk with framework conventions. The hash inside is
yours.

The per-platter bucket design above is what makes this policy
tenable. Without per-platter buckets, mix-ins had to namespace
their state somewhere — the soft `uns.<UNS>` convention was the
workaround. Per-platter buckets give every class its own
designated space, so no class has to encroach on another's
bucket via key conventions. The convention becomes obsolete.

<a id="bucket-allocation"></a>
### Bucket allocation

Open: whether each platter's `bucket` field is always allocated
(uniform shape) or lazy (only appears once written). Lean:
always present, for uniformity.

<a id="accessing-buckets"></a>
### Accessing buckets from inside a class

Shared object bucket (the default — what classes write to in the
common case):

```caspian
@foo = 'bar'              # shorthand for %bucket['foo'] = 'bar'
%bucket['foo']            # explicit
```

Platter's own private bucket (the special case — explicit syntax,
no sugar):

```caspian
%platter['foo'] = 'bar'   # writes to this platter's own bucket
%platter['foo']           # reads from this platter's own bucket
```

The asymmetry is deliberate. By default, a class writes to the
shared object bucket — same as today, no behavioral change for
existing code. Per-platter private storage is the rare case, and
the explicit `%platter[...]` syntax serves as a friction point
that signals "I'm doing something less common." No `@@foo`-style
shorthand for the platter-bucket case; if you want platter
isolation, you write it out.

The mental pairing:

| Source | Resolves to |
|---|---|
| `@foo` | `%bucket['foo']` (shared object bucket) |
| `%bucket['foo']` | shared object bucket, explicit |
| `%platter['foo']` | this platter's own bucket |

`%platter` returns the current platter's bucket — the bucket
field of the platter record corresponding to the class currently
executing. The engine knows which platter is active from method
dispatch (same mechanism that tracks the active class for
`call_with` and friends).

<a id="what-this-resolves"></a>
### What this resolves

- **Key collisions disappear.** Platter A and Platter B can both
  use `counter` in their own buckets without stepping on each
  other.
- **Encapsulation between platters.** A platter's internal
  bookkeeping is hidden from sibling platters even though they
  share the object.
- **Mix-in safety, no convention needed.** A mix-in class (e.g.,
  Trivet's node class) carries state in its own bucket; no need
  to remember to namespace under `bucket.uns.<self-uns>`.
- **The `uns.<UNS>` bucket convention becomes obsolete.** Mix-ins
  use their own platter bucket; the soft convention can be
  retired once the formal mechanism lands. Lucy.md's documentation
  of `uns` as a reserved bucket key would go away.
- **Extensible platter records.** Future platter-record fields
  (sticky flag, restricted-by, added_by, added_at, etc.) ride
  along inside the platter record without further universal shape
  changes.

<a id="class-vs-classes-resolution"></a>
### `class` vs `classes` — a long-standing tension resolved

A side benefit of this structural change: the word `class` has
historically done double duty in Caspian — sometimes meaning
"the kind of thing this hash is" (identity, the hash's own class),
sometimes meaning "a class as a value passed around" (a reference,
e.g., a query target). Code with both meanings in proximity is
hard to read.

By moving object identity to the `classes` field (plural, a hash
of platter records keyed by ID), the singular word `class` is
**freed from identity duty**. When `class` appears as a parameter,
field name, or variable, it's unambiguously "a class reference."

The platter record's `class` key is exactly that — a class
reference — so using `class` as the key is now natural and
descriptive, not an overload:

```json
{"class": "foo.bar/gup", "bucket": {}}
```

Compare to before, where the same word `class` would have been
the storage identity key (`{class: "foo.bar/gup", bucket: ...}`
read as "this hash IS a foo.bar/gup"). Same shape, but the
meaning shifts: now it reads as "this platter REFERENCES
foo.bar/gup."

`class 'foo.com/whatever'` remains the class declaration keyword,
unchanged. The tension was at the field-name level, not the
keyword level.

<a id="implications-for-other-docs"></a>
### Implications for other docs

Settled changes that propagate:

- [lucy.md § Two-Property Objects](../requirements/caspian/lucy/index.md) —
  needs updating to describe the platter-record shape. "Every
  object has classes (a list of platters) and a bucket (shared
  hash)."
- [lucy.md § %bucket](../requirements/caspian/lucy/index.md#bucket) — the `uns`
  bucket-key convention can be retired in favor of per-platter
  buckets.
- [skeletor.md](../requirements/caspian/skeletor/index.md) — snapshot/revive
  shape needs to handle the new structure: each platter record
  serializes with its class UNS and its bucket.
- mikobase records — currently `{class, bucket}`. Probably become
  `{classes: {<id>: {class, bucket}, ...}, bucket}` to match.
  Worth flagging this in the Mikobase spec.
- Every doc that says "object's class" needs to either say "the
  class an object is an instance of" (still meaningful) or
  reference "the object's classes" (the full stack).

<a id="active-field"></a>
## Active and inactive platters

Each platter carries an optional `active` field. The default is `true`,
and the field is omitted when it would be true — only inactive platters
explicitly carry `active: false`. So most platter records have just
`{class, bucket}` (or `{class, bucket, sticky}` if sticky); only
deactivated platters add the field.

**`.classes.remove(<id>)` doesn't actually remove the platter — it
sets `active: false`.** The platter's bucket and metadata stay in the
`classes` hash. The rationale is simple: rather than trace whether
the deactivated platter's bucket data is still needed by something
else, just keep it around. Removals are rare enough that the small
accumulation cost is worth not tracing.

**What `active: false` affects:**

- **Method dispatch** — the platter is skipped. Methods defined by
  its class aren't found through it.
- That's the whole effect.

**What `active: false` doesn't affect:**

- **`.object.isa?`** — still returns true if the class is in the
  stack, active or not. Class membership is independent of dispatch
  participation.
- **`.object.classes`** — returns the full stack including inactive
  platters (with their `active: false` field visible).
- **Engine scans for marker presence** (truthiness markers, redact,
  etc.) — the engine reads the full classes hash; an inactive
  marker platter is still found.
- **The platter's bucket data** — preserved. Reactivation restores
  full behavior including bucket contents.

**Sticky platters cannot be deactivated.** "Can't be removed" extends
to "can't be set inactive." Pinned-region platters and user-marked
sticky platters stay active for the object's lifetime by definition.

**Reactivation** — `.classes.set_active(<id>, true)` flips the
field back. The platter rejoins normal dispatch with its bucket
intact.

**Snapshot/revive** carries inactive platters through. Roundtrip is
exact.

<a id="method-resolution"></a>
## Method resolution

Method dispatch is **two-dimensional** — for any given method
lookup, the engine walks across the platter stack AND through
each platter's class's `inherits` chain. Both dimensions get
explored, with a discipline to avoid loops and duplicate work.

The walk:

1. Start with an empty **visited set** (per-dispatch, not cached).
2. Iterate the platter stack from top to bottom.
3. For each platter, walk up its class's `inherits` chain. At
   each class encountered:
   - If the class is already in the visited set, skip.
   - Otherwise add it to the visited set, then check whether it
     defines the method.
4. First match wins. If no platter yields a match across its
   inheritance chain, the method is unknown — raise
   `puck.uno/error/method_missing` (or similar).

<a id="unicast-vs-multicast"></a>
### Unicast vs multicast dispatch

The walk above is **unicast** — first match wins, stop. That's
the default for normal method dispatch (`$foo.bar`).

Some methods are **multicast** instead — same walk, but *every*
match invokes. The engine collects all matching handlers across
platters and inheritance chains, then invokes each in walk order
(top platter first, ancestor-class match before sibling-platter
match per the visited set's encounter order).

| Dispatch kind | Stops at | Used by |
|---|---|---|
| Unicast | First match | Regular method calls (`$foo.bar`) |
| Multicast | End of walk | Class-body lifecycle hooks (`on_close`, `after_set`, etc.) |

The two share the walk; they differ only in stopping rule.
Multicast isn't a special case grafted onto dispatch — it's a
second mode of the same walk, with a different terminator.

<a id="how-dispatch-kind-is-declared"></a>
#### How dispatch kind is declared

Dispatch kind is **a property of the function object**, not a
keyword in the declaration. Functions carry an `on_call` field;
the value selects between dispatch modes:

| `on_call` value | Dispatch |
|---|---|
| `:first` (or absent) | Unicast — first match wins |
| `:all` | Multicast — every match fires |

```caspian
class
    function &on_close($call)
        @socket.close
    end
    $on_close.on_call = :all      # declares this as multicast

    function &to_string()
        ...
    end
                                  # unicast (default)
end
```

Property assignment goes immediately after the function
definition by convention — the two-line pair carries the
visibility a keyword would have. See
[lucy.md § `on_call` property](../requirements/caspian/lucy/index.md#on-call-property)
for the full design (mutability, caching consequences, future
properties in the same family).

`on_close` is the canonical multicast case — every platter that
defines `on_close` gets to clean up its own state, not just the
top one. See
[garbage-collection.md § Multicast across platters](../requirements/caspian/garbage-collection.md#on-close-multicast).
The same model covers `after_set` / `after_delete` on hashes and
any future class-body lifecycle hook — see
[#343](https://github.com/mikosullivan/puck/issues/343).

Properties:

- **Cycles can't trap dispatch.** A class that somehow loops in
  its inheritance chain won't cause infinite walking — the
  visited set catches the loop.
- **Diamond inheritance handled.** If multiple platters share an
  ancestor class, that ancestor is checked once. No double-dispatch.
- **No cross-dispatch state.** The visited set is built and
  discarded within a single method call. No MRO cache to
  invalidate when class definitions change.
- **Cost.** O(platters × avg inheritance depth) per dispatch,
  bounded by the visited set to actual unique classes
  encountered. Tiny for typical programs.

**No MRO caching at this stage.** Caspian permits dynamic class
mutation (methods added or removed at runtime, classes loaded
mid-program), which makes MRO caches unsafe without invalidation
discipline. The per-dispatch visited-set approach is correct
under any class mutation. If real workloads later show dispatch
as a hot spot, more sophisticated caching with explicit
invalidation can be added as an optimization — but the
correctness guarantee (no stale dispatch) stays.

**`%platter` during inheritance walks.** When a method comes
from an inherited class (not the platter's own class), `%platter`
still returns the platter that initiated the inheritance walk —
the per-instance platter, not the resolved ancestor class. This
keeps per-platter bucket access stable regardless of where the
method came from.

**`call_with` semantics.** `$obj.object.call_with($class, 'method', ...)`
dispatches explicitly to the named class. Could optionally walk up
that class's inheritance chain if the named class doesn't define
the method — TBD as the API matures.

<a id="open-design-questions"></a>
## Open design questions

- **API surface for `classes.add`** — what does the method actually
  look like? Does it take a class object, a UNS string, or both?
  Does it also accept an initial bucket?
- **Accessing one's own platter bucket** — what's the syntax from
  inside a class method? `@field` currently accesses the shared
  bucket; do we need a different sigil (or method) for the
  platter's own bucket? Or is the platter's bucket the default and
  the shared bucket needs a different accessor?
- **Removal semantics** — what does `classes.remove` do when the
  class is sticky? Raise? Return false? And what happens to the
  platter's private bucket when the platter is removed — discarded?
- **Querying** — `classes.has?('puck.uno/class/redact')` to check
  whether a marker is present?
- **Iteration** — `classes.each do |platter| ... end` to walk the
  chain?
- **Snapshot serialization** — confirmed: each platter record
  serializes as a self-contained chunk with its class UNS and
  its bucket. Empty buckets either always shown as `{}` or omitted
  for compactness — see Bucket invariants above.
- **Empty buckets per platter — always present or lazy?** See
  Bucket invariants above.

To be filled in as the pattern crystallizes.
