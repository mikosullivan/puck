~~~vibecode
{"doc": "requirements_cvm_ownership",
	"role": "Ownership of a bucket or stack is a normal refs row from the owner to the collection — no dedicated bucket_pk / stack_pk / bucket_for / stack_for columns. Non-container parents ('o' and 'f') are capped at one hash-child (their bucket) and one array-child (their stack). Sharing across owners falls out. Cascade cleanup runs through the standard refs_mark_needs_trace_after_delete trigger — no bespoke per-collection triggers.",
	"key_concepts": ["ownership_via_refs", "one_hash_one_array_cap", "shared_collections", "unified_gc_path"]}
~~~

# Ownership

An object's bucket and stack are just refs — rows in the `refs` table pointing from the owner to the collection. No dedicated columns anywhere on `objects` for "this row's bucket" or "this row's owner"; the whole ownership story lives in refs.

## The rule

A non-container parent — `primitive` in `('o', 'f')` — can hold **at most one HashPrimitive child (its bucket) and at most one ArrayPrimitive child (its stack)** as refs. Container parents (`'h'`, `'a'`) have no such cap: hashes and arrays hold as many refs as they need by their native semantics.

The cap is enforced by the `refs_owner_at_most_one_hash_and_one_array` trigger on `refs`. Trying to add a second hash-ref (or a second array-ref) under a non-container parent raises. Scalars are non-container objects too — a scalar can carry a bucket and a stack just like any other regular object.

## Shape of the ref

An owner→bucket (or owner→stack) ref uses `key = null` and follows the standard `refs` idx conventions:

- `parent` — the owner's `object_pk`
- `child` — the collection's `object_pk`
- `key` — `null` (the child's primitive tells you which is bucket vs stack)
- `idx` — auto-assigned, following the `add_ref` conventions

The child's `primitive` field disambiguates: a hash-child is the owner's bucket; an array-child is the owner's stack.

## Sharing

Because ownership is a ref, and refs impose no uniqueness on the child, **two owners can reference the same bucket** — a bucket doesn't know how many owners point at it. The engine's data-access layer supports this at the write level (you can add the same child under different parents); the GC substrate handles reachability correctly because it sees both incoming refs.

Sharing is an escape hatch for meta-programming scenarios. Common cases still have one owner per collection.

## Cascade cleanup

When an owner is deleted, its outgoing refs cascade-delete via the `refs.parent ON DELETE CASCADE` FK — including the owner→bucket ref. Each ref-delete fires the standard `refs_mark_needs_trace_after_delete` trigger, which marks the ref's `child` (the bucket) `needs_trace = 1`.

The bucket survives with a `needs_trace` flag. GC decides its fate: if any live root still reaches the bucket via some other ref, the bucket stays; otherwise GC sweeps it.

No dedicated per-collection triggers exist — the whole lifecycle runs through the standard refs-cleanup machinery.

## Looking up an object's collections

Two utility views expose the owner→collection edges directly:

- **[`object_bucket`](https://www.puck.uno/requirements/cvm/sql)** — `(object_pk, bucket_pk)` for every non-container object; `bucket_pk` is the object's one hash-child (or null).
- **[`object_stack`](https://www.puck.uno/requirements/cvm/sql)** — same shape for the one array-child.

Both use correlated subqueries filtered by `child.primitive` — guaranteed to return at most one row per owner by the one-hash-one-array cap.

## What this replaces

Earlier drafts carried dedicated `bucket_pk` / `stack_pk` columns on the owner and back-reference `bucket_for` / `stack_for` columns on the collection, with per-column immutability, target-primitive checks, and needs_trace triggers. All of that is gone — the refs table plus the one cap trigger cover it uniformly.

The only enforcement layer specific to ownership is the cap trigger. Everything downstream (change tracking, needs_trace marking, cascade behavior) runs through machinery that already exists for every other refs relationship.
