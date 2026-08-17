~~~vibecode
{"doc": "sprint-index", "sprint": "hash-array-key-semantics",
	"role": "Split from the retired close-schema-holes sprint (hole #1). Adds two `refs` triggers that enforce the hash-key vs array-idx convention at write time: `refs_hash_key_required` (hash parent ⇒ key not null) and `refs_array_key_forbidden` (array parent ⇒ key null). Sources: issue #1663 (ChatGPT critique § 1).",
	"status": "pre-integration — sprint schema + tests complete; shipping untouched"}
~~~

# hash-array-key-semantics

Hole #1 from the ChatGPT critique. The `refs` table already has `unique (parent, key)` and `unique (parent, idx)`, and the identifier-shape trigger `refs_hash_key_must_be_identifier` fires when a key IS present. But nothing enforces the key-vs-idx choice itself — a hash parent with a null-key entry and an array parent with a non-null-key entry are both silently accepted, then break downstream code that reads the ref graph by primitive.

## Fix

Two BEFORE INSERT triggers on `refs`:

- **`refs_hash_key_required`** — parent's `primitive = 'h'` and `new.key is null` → reject.
- **`refs_array_key_forbidden`** — parent's `primitive = 'a'` and `new.key is not null` → reject.

Both are INSERT-only because refs are immutable (`refs_no_update` blocks column edits).

## Status

**Pre-integration.** Sprint schema at [sprints/hash-array-key-semantics/src/schema.sql](https://puck.uno/sprints/hash-array-key-semantics/src/schema.sql); tests at [sprints/hash-array-key-semantics/tests/test_hash_array_keys.lua](https://puck.uno/sprints/hash-array-key-semantics/tests/test_hash_array_keys.lua). Shipping untouched.

## Integration

Two-trigger add to shipping's `src/engine/cvm/schema.sql` right after `refs_hash_key_must_be_identifier`. No column changes, no rename sweep. Test file promotes to `tests/main/lua/engine/test_schema.lua` as a new section, or stays standalone.
