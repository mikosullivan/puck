# Hash
<!--index: 5-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_hash",
	"role": "spec for Caspian's built-in hash class — ordered key-value map. Covers the literal form, key/value semantics (string keys, arbitrary values), insertion-ordered iteration, the guaranteed method surface (fetch, set, delete, keys, values, each, length, containment tests), and an opt-in note_deleted feature for recording explicit deletions that layered-lookup consumers like scope frames build on.",
	"status": "stub — literal form, ordering-preserved rule, and note_deleted opt-in feature spec'd; broader method surface TBD",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

A **hash** is an ordered map from string keys to arbitrary values. Every hash literal in Caspian source materializes into an instance.

## Literal form

~~~caspian
$table = {name: 'alice', age: 30, admin: true}
~~~

- Keys written as bare identifiers become string keys — `{name: ...}` is `{'name': ...}`.
- Keys can also be written as explicit strings — `{'name': 'alice'}`.
- Values can be any value.

**Keys are strings.** Unlike some languages (Ruby symbols, Python where any hashable is a key, JavaScript's ability to use numbers or symbols), Caspian hash keys are always strings.

In hash literal syntax, whatever token appears before the `:` becomes the string key. All three of these produce the same hash:

~~~caspian
{foo: 'bar'}       # bare identifier
{'foo': 'bar'}     # single-quoted string
{"foo": 'bar'}     # double-quoted string
~~~

Numeric-looking tokens work the same way — `{42: 'x'}` produces a hash with the string key `'42'`, identical to `{'42': 'x'}`.

At runtime, `[]` and `[]=` still require a string — `$h[42] = 'x'` and `$h[42]` raise because `42` is a number, not a string. The literal parser's "anything-before-colon-becomes-a-string" rule is a parse-time convenience, not a runtime coercion.

## Ordering

**Insertion order is preserved.** Iterating a hash produces keys in the order they were inserted, not sorted or hashed. This matches the Puck object convention (see [ecoverse § Object structure](https://puck.uno/documentation/ecoverse) if you need the wire-level story) — order is data, not an implementation detail.

## Method surface

TBD. Sub-page will list guaranteed methods (`[key]` fetch, `[key] = value` set, `.delete`, `.keys`, `.values`, `.each`, `.length`, containment tests).

## Noting deleted keys

Some consumers need to distinguish between "the key was never here" and "the key was explicitly deleted." Plain hashes don't carry that distinction — a `.delete` followed by `.has_key?` returns `false`, indistinguishable from a key that was never set. An opt-in feature lets a hash record its deletions.

### Opt-in per hash

Set `.note_deleted = true` to turn on deletion tracking. Off by default — hashes that don't need the feature don't pay the memory cost of a tombstone set.

~~~caspian
$hsh = {'a': 'b'}
$hsh.note_deleted = true
$hsh.note_deleted # true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
~~~

### The key doesn't need to have existed

`.delete` on a note-deleted hash records the key even if it was never present. The tombstone is a statement about visibility, not a record of what used to be there.

~~~caspian
$hsh = {}
$hsh.note_deleted = true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
~~~

### `.deleted?` raises on non-note-deleted hashes

If a hash isn't tracking deletions, it can't answer `.deleted?` honestly — returning `false` would be misleading (the key might have been deleted; the hash didn't record it). Raising is properly fail-loud.

~~~caspian
$hsh = {'a': 'b'}
$hsh.delete 'a'
$hsh.deleted? 'a' # raises
~~~

### Toggling off wipes the tombstones

Setting `.note_deleted = false` discards the recorded deletions. Turning it back on starts fresh — no silent preservation.

~~~caspian
$hsh = {'a': 'b'}
$hsh.note_deleted = true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
$hsh.note_deleted = false
$hsh.note_deleted = true
$hsh.deleted? 'a' # false
~~~

### Re-assigning un-tombstones the key

Setting a key that was previously tombstoned removes it from the tombstone set. `.has_key?` and `.deleted?` can never both be true for the same key.

~~~caspian
$hsh = {'a': 'b'}
$hsh.note_deleted = true
$hsh.delete 'a'
$hsh.deleted? 'a' # true
$hsh['a'] = 'bar'
$hsh.deleted? 'a' # false
~~~

### Why this exists

Layered lookup patterns — scope frames and similar walk-a-chain-of-hashes designs — need to distinguish "this layer never had the key" from "this layer explicitly deleted it." Without a tombstone marker, deleting a key in an inner layer silently un-shadows whatever was in an outer layer. The consumer (scope runtime, etc.) opts each frame in with `.note_deleted = true` so the walker can stop on an explicit delete instead of falling through.

## Freezing fields

<span class="tag">hash-freeze-field</span>

Individual fields in a hash can be frozen with `.freeze_field(key)`. Once frozen, any attempt to write a new value at that key raises. Reads are unaffected; `.delete` on a frozen key raises.

~~~caspian
$config = {debug: false, host: 'localhost'}
$config.freeze_field 'host'

$config['debug'] = true       # ok — debug not frozen
$config['host'] = 'other'     # raises — host is frozen
~~~

**Companion predicate: `.field_frozen?(key)`** returns `true` if `.freeze_field` has been called on the key, `false` otherwise. Parallel to variable-object's `.frozen?`.

~~~caspian
$config.field_frozen? 'host'   # true
$config.field_frozen? 'debug'  # false
~~~

**Freezing an unset key is allowed.** The key doesn't need to exist yet; the freeze marks it so any future write raises. `.field_frozen?` reflects the frozen marker regardless of whether the key was ever set.

~~~caspian
$hsh = {}
$hsh.freeze_field('foo')
$hsh.field_frozen?('foo') # true
$hsh['foo'] = 1           # raises
~~~

**Frozen fields cannot be deleted.** Freezing settles the whole field (both existence and value); `.delete` would undo the settlement.

~~~caspian
$hsh = {'a': 'b'}
$hsh.freeze_field('a')
$hsh.delete 'a' # raises
~~~

**Freezing is fine-grained.** Freezing one field doesn't freeze others; the hash as a whole stays mutable. Different fields can be frozen independently.

**Freezing is Caspian's constant mechanism for hash entries.** Same pattern that variable-objects use: assign the value freely, then freeze. No separate `const` field-declaration keyword — one primitive, applied through different access paths. See [variable-object § Freezing](https://puck.uno/requirements/built-in-classes/variable-object#freezing) for the parallel variable-level story.

**Common use: instance constants on `%bucket`.** Method bodies can freeze bucket fields to prevent later mutation:

~~~caspian
method &init($id)
	@id = $id
	%bucket.freeze_field 'id'  # @id is now immutable for this instance
end
~~~

## Freezing (whole-hash)

<span class="tag">hash-freeze</span>

For "no more writes to any key, no new keys, no removals" semantics, call `.freeze` **directly on the hash** (NOT on `.obj` — the primitive-contents freeze is a hash-instance concern, not a general-object concern; see [object/methods § freeze surface](https://puck.uno/requirements/built-in-classes/object/methods#freeze_bucket--freeze_stack--freeze) for the object-level split).

~~~caspian
$foo = {'a': 'b'}
$foo.freeze
$foo['b'] = 1     # raises
$foo.delete 'a'   # raises
~~~

**Two forms** — same bare / block pattern as the object-level freeze surface:

- **Bare `.freeze`** — permanent. There is no `unfreeze`.
- **Block `.freeze do ... end`** — locks for the block, releases at exit. Exception-safe.

~~~caspian
$foo = {}
$foo.freeze do
	# $foo is frozen inside this block
end
# $foo is mutable again out here
~~~

**Idempotent.** Calling `.freeze` on an already-frozen hash is a no-op.

**Companion predicate: `.frozen?`** returns `true` if `.freeze` has been called (or is active for a block form), `false` otherwise.

~~~caspian
$foo = {}
$foo.frozen?    # false
$foo.freeze
$foo.frozen?    # true
~~~

**Composes with `.freeze_field(key)`.** Fine-grained field-level freezes are preserved through hash-level freeze cycles:

- `.freeze_field(k)` early → the field is frozen individually.
- `.freeze` later → whole hash frozen; the individual field freeze is a strict subset of the whole-hash freeze.
- Block-form `.freeze do ... end` release → the block-form hash-wide freeze goes away, but any per-field freeze that was set separately stays.

**Distinct from `.obj.freeze_bucket`.** `.obj.freeze_bucket` freezes the hash's METADATA bucket (the `note_deleted` flag, the per-field freeze markers, etc.). It does NOT freeze the key-value contents. Use `.freeze` (direct) for that.

## Testing

- **Empty hash literal `{}` materializes to a Hash instance** — `{}.obj.isa?(Hash)` is `true`.
- **Populated hash literal materializes to a Hash instance** — `{a: 1}.obj.isa?(Hash)` is `true`.
- **Bare-identifier keys become string keys** — `{name: 'alice'}` is equal to `{'name': 'alice'}`.
- **Explicit string keys are preserved** — `{'name': 'alice'}` and `{name: 'alice'}` are indistinguishable at the value level.
- **Numeric-looking literal key stringifies** — `{42: 'x'}` equals `{'42': 'x'}`; both keyed by the string `'42'`.
- **Bare, single-quoted, and double-quoted key forms are equivalent** — `{foo: 'bar'}`, `{'foo': 'bar'}`, and `{"foo": 'bar'}` all produce the same hash.
- **Non-string key on `[]=` raises** — `$h[42] = 'x'` raises; the setter accepts only string keys.
- **Non-string key on `[]` raises** — `{'42': 'x'}[42]` raises; the getter accepts only string keys. `{'42': 'x'}['42']` is `'x'`.
- **Values may be any type** — a hash with a mix of number, string, boolean, null, array, hash, and user-object values constructs without error and reads each value back at its original identity.
- **Insertion order is preserved on iteration** — iterating `{c: 3, a: 1, b: 2}` yields keys in the order `c`, `a`, `b`, not alphabetical, not hashed.
- **Insertion order is preserved after overwriting an existing key** — writing a new value at an existing key does not move it to the end; its original position is kept.
- **Empty hash is truthy** — `if {} then :yes else :no end` evaluates to `:yes`.
- **Empty hash has length zero** — `{}.length` is `0`.
- **Populated hash length reflects entries** — `{a: 1, b: 2, c: 3}.length` is `3`.
- **Get by present key returns the value** — `{a: 1}['a']` is `1`.
- **Get by missing key returns `null`** — `{a: 1}['missing']` is `null`; the read does not raise.
- **Set by key adds a new entry** — after `$h = {}; $h['x'] = 5`, `$h['x']` is `5`.
- **Set by key overwrites an existing entry** — after `$h = {a: 1}; $h['a'] = 2`, `$h['a']` is `2`.
- **`.keys` returns keys in insertion order** — `{c: 3, a: 1}.keys` is `['c', 'a']`.
- **`.values` returns values in insertion order** — `{c: 3, a: 1}.values` is `[3, 1]`.
- **`.each` yields key/value pairs in insertion order** — collecting the pairs from `.each` on `{c: 3, a: 1}` produces `[['c', 3], ['a', 1]]`.
- **`.each` on empty hash yields nothing** — the block body never runs for `{}.each`.
- **Nested hashes compose** — `{outer: {inner: 42}}['outer']['inner']` is `42`.
- **Hash equality is recursive** — `{a: {b: 1}} == {a: {b: 1}}` is `true`.
- **Hashes with different insertion orders but same entries compare equal** — `{a: 1, b: 2} == {b: 2, a: 1}` is `true`; equality does not require matching order.
- **Hashes with different entries compare unequal** — `{a: 1} == {a: 2}` is `false`.
- **Unicode string keys are supported** — a hash keyed by a non-ASCII string (e.g. `'café'`) reads and writes at that key without normalization.
- **Empty and populated hashes are distinct instances** — two `{}` literals produce two Hash instances (no interning); mutating one does not affect the other.
- **Hash is truthy after all entries are removed** — a hash whose entries were all deleted still evaluates as truthy; only `false` and `null` are falsy.
- **`.note_deleted` defaults to `false`** — a freshly-constructed hash reads `.note_deleted` as `false`.
- **Enabling `.note_deleted` opts the hash in to deletion tracking** — after `.note_deleted = true`, `.delete` records the key in the tombstone set.
- **`.deleted?` returns `true` for a key deleted after opt-in** — after `$hsh = {'a': 'b'}; $hsh.note_deleted = true; $hsh.delete 'a'`, `$hsh.deleted? 'a'` is `true`.
- **`.deleted?` raises on a hash where `.note_deleted` is `false`** — regardless of whether the key was ever present, calling `.deleted?` on a non-note-deleted hash raises.
- **`.delete` on a note-deleted hash records a key that never existed** — after `$hsh = {}; $hsh.note_deleted = true; $hsh.delete 'a'`, `$hsh.deleted? 'a'` is `true`.
- **Setting `.note_deleted = false` wipes the tombstone set** — after toggling off then back on, a previously-tombstoned key is no longer `.deleted?`.
- **Re-assigning a tombstoned key un-tombstones it** — after `$hsh.delete 'a'; $hsh['a'] = 'bar'`, `$hsh.deleted? 'a'` is `false` and `$hsh.has_key? 'a'` is `true`.
- **`.freeze_field` prevents further writes at that key** — after `$h = {a: 1}; $h.freeze_field 'a'`, `$h['a'] = 2` raises.
- **`.freeze_field` leaves other keys mutable** — after `$h = {a: 1, b: 2}; $h.freeze_field 'a'`, `$h['b'] = 99` succeeds and `$h['b']` is `99`.
- **`.field_frozen?` returns true for frozen keys** — after `$h = {a: 1}; $h.freeze_field 'a'`, `$h.field_frozen? 'a'` is `true`.
- **`.field_frozen?` returns false for unfrozen keys** — for `$h = {a: 1, b: 2}` with only `a` frozen, `$h.field_frozen? 'b'` is `false`.
- **`.field_frozen?` on a never-touched key returns false** — `$h = {a: 1}; $h.field_frozen? 'nonexistent'` is `false`.
- **`.freeze_field` on an unset key succeeds** — `$h = {}; $h.freeze_field 'foo'` does not raise.
- **Frozen unset key rejects writes** — after `$h = {}; $h.freeze_field 'foo'`, `$h['foo'] = 1` raises.
- **`.field_frozen?` returns true for a frozen unset key** — after `$h = {}; $h.freeze_field 'foo'`, `$h.field_frozen? 'foo'` is `true`.
- **`.delete` on a frozen field raises** — after `$h = {a: 'b'}; $h.freeze_field 'a'`, `$h.delete 'a'` raises.
- **Bumping a frozen subscript raises** — after `$h = {a: 1}; $h.freeze_field 'a'`, `$h['a']++` raises (the underlying subscript-write is blocked by the freeze, same as `$h['a'] = 2`).
- **`.freeze_field` is idempotent** — calling `.freeze_field 'a'` twice on the same key does not raise on the second call.
- **`.freeze` (whole-hash) prevents writes to any key** — after `$h = {a: 1}; $h.freeze`, `$h['a'] = 2` raises.
- **`.freeze` prevents new keys** — after `$h = {}; $h.freeze`, `$h['x'] = 1` raises.
- **`.freeze` prevents removals** — after `$h = {a: 1}; $h.freeze`, `$h.delete 'a'` raises.
- **`.freeze` is idempotent** — calling `.freeze` twice on the same hash does not raise on the second call.
- **`.frozen?` returns false initially** — for a fresh `$h = {}`, `$h.frozen?` is `false`.
- **`.frozen?` returns true after `.freeze`** — after `$h = {}; $h.freeze`, `$h.frozen?` is `true`.
- **Block-form `.freeze` releases at block exit** — after `$h = {}; $h.freeze do end`, `$h.frozen?` is `false` and `$h['x'] = 1` succeeds.
- **`.frozen?` returns true inside block-form `.freeze`** — inside `$h.freeze do ... end`, `$h.frozen?` is `true`.
- **`.freeze` composes with `.freeze_field`** — after `$h = {a: 1, b: 2}; $h.freeze_field 'a'; $h.freeze do end`, `$h.field_frozen? 'a'` is still `true` after block exit.

## Related

- [Loops](https://puck.uno/requirements/syntax/loops) — the `.each` block form, `as $loop`, and every other loop construct.
- [Syntax § Variables and assignment](https://puck.uno/requirements/syntax/variables-and-assignment) — assignment to hash entries.
