~~~vibecode
{"doc": "requirements_cvm_scopes",
	"role": "The scopes convention for variable storage: a frame's bucket has a `scopes` key pointing at an ArrayPrimitive whose entries are hash primitives. Scope[0] is the frame's own locals; scope[1..] are captured scopes from enclosing closures. Hash keys inside a bucket must be Caspian-compliant identifiers. The `frame_scoped_vars` view flattens the whole chain into (frame_pk, scope_idx, var_name, value_pk) rows for lookup.",
	"key_concepts": ["scopes_array", "own_scope_at_index_zero", "captured_scopes", "hash_key_identifier_rule", "frame_scoped_vars"]}
~~~

# Scopes

Local variable storage under CVM. A frame's own locals live inside a HashPrimitive that hangs off the frame's bucket under a specific key; captured scopes from closures chain alongside it.

## The chain

Under a frame's [bucket](https://www.puck.uno/requirements/cvm/ownership), the special key `scopes` points at an ArrayPrimitive:

- `bucket` (HashPrimitive) → `scopes` → array of scope hashes
- `scopes[0]` — this frame's OWN scope hash (a HashPrimitive)
- `scopes[1]`, `scopes[2]`, ... — captured scopes from enclosing closures, if any

Every entry in the scopes array is a HashPrimitive. Inside each scope hash, keys are variable names and children are the values bound to them.

## Enforced by three triggers

The convention is enforced at the schema level so a violating write raises loudly:

1. **`refs_scopes_key_requires_array`** — a ref keyed `scopes` must point at an ArrayPrimitive.
2. **`refs_scopes_array_entries_must_be_hashes`** — inserting a ref into an array that's referenced by a scopes-keyed ref: the child must be a HashPrimitive.
3. **`refs_scopes_key_existing_entries_must_be_hashes`** — when a scopes-keyed ref is inserted, any existing entries in the target array must all be hashes (retro-check for the case where refs into the array were inserted before the scopes ref was attached).

Together these guarantee the shape: `scopes` → array → hashes, always.

## Not enforced: which rows may CARRY a `scopes` ref

By convention, a `'scopes'`-keyed ref lives on a **frame's bucket**. The schema does NOT enforce this on the parent side — any HashPrimitive can carry a `'scopes'` ref, whether or not it's a frame's bucket, and the three triggers above still fire on the child side. The looseness is intentional: enforcing "parent must be a frame's bucket" would require a subquery join on every ref insert, and the write path (`ensure_own_scope`) already places `scopes` refs on frame buckets and nowhere else. If a bug ever produces a `scopes` ref under a non-bucket hash, the child-side triggers keep the array-of-hashes shape correct; the misplaced ref just doesn't participate in `frame_scoped_vars` (which walks the chain from `object_bucket`).

## Hash-key identifier rule

Any key inside a hash primitive (which includes the scope hashes above) must be a Caspian-compliant identifier — starts with a letter or underscore, then letters, digits, or underscores. Enforced by the `refs_hash_key_must_be_identifier` trigger using a GLOB pattern:

- Accepted: `x`, `_foo`, `bar_2`, `Class1`
- Rejected: `1foo` (leading digit), `foo-bar` (dash), `foo bar` (space), the empty string

Array entries (which leave `key` null) are not affected — the rule only fires when `key` is set and the parent is a HashPrimitive.

## The `frame_scoped_vars` view

A flattened view over the whole chain — one row per (frame, scope position, var name):

- `frame_pk` — the frame's `object_pk`
- `scope_idx` — position in the scopes array (0 = own scope; 1+ = captured)
- `var_name` — the binding's key inside the scope hash
- `value_pk` — the child object bound to that key

Two typical query patterns:

**Effective binding** (nearest scope wins):
~~~sql
select value_pk from frame_scoped_vars
where frame_pk = ? and var_name = ?
order by scope_idx limit 1;
~~~

**Full dump** for a frame:
~~~sql
select * from frame_scoped_vars where frame_pk = ?;
~~~

All joins in the view are indexed — `refs_parent`, `refs` unique `(parent, key)`, and PK lookups on objects. No scans in either query plan.

## Graceful on broken chains

The view uses inner joins, so any missing link (no bucket, no scopes ref, empty scopes array, empty scope hash) returns zero rows rather than raising. A query on a nonexistent `frame_pk` returns zero rows. The view is a lookup surface, not a schema check.

## Write path

The engine's `frame:set_local_to_scalar(name, scalar_type, scalar_value)` writes a binding into scope[0]. In one savepoint it: materializes the scalar, ensures the bucket → scopes → scopes[0] chain exists (`ensure_own_scope`), and adds the ref binding `name` to the scalar. See [frame-lifecycle](./frame-lifecycle) for how the enclosing walker advance handles the marker that gets pushed alongside.
