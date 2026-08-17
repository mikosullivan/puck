~~~vibecode
{"doc": "sprint-index", "sprint": "scope-chain-validation",
	"role": "Codex review finding #1690. `frame_scoped_vars` view assumes a well-formed scope chain (bucket → 'scopes' → array → scope hashes → var refs). Some structural facts the view depends on are enforced (scopes-array-must-be-hashes, hash-key-identifier), but Codex flags additional shape rules that aren't validated at the schema layer. Source: issue #1690.",
	"status": "active — blocked on closure-capture design"}
~~~

# scope-chain-validation

Issue #1690. `frame_scoped_vars` walks:

- frame → bucket (via refs)
- bucket → 'scopes' array (via ref keyed 'scopes')
- array → each scope hash (array entries must be hashes — enforced)
- scope hash → var name → value

Enforced already:
- `refs_scopes_key_requires_array` — scopes key must point at an ArrayPrimitive.
- `refs_scopes_array_entries_must_be_hashes` — entries in a scopes array must be HashPrimitives.
- `refs_scopes_key_existing_entries_must_be_hashes` — retro-check on the existing entries at scopes-ref INSERT.
- `refs_hash_key_must_be_identifier` — variable names inside scope hashes are Caspian identifiers.

Codex flagged three additional gaps that may or may not be worth encoding:

1. **Every scope hash entry has required fields.** If closures capture parent scopes via a `_parent` field (or similar), the schema doesn't enforce presence.
2. **Scopes properly chained.** If scope[N] should reference scope[N-1] via a `_parent` field, no schema rule verifies it.
3. **Variable-name uniqueness within a scope.** Already enforced by refs' `unique (parent, key)` — no gap.

## Design decision

Gaps #1 and #2 depend on the closure-capture design, which is DEFERRED in the CVM spec (see `requirements/cvm/index.md` "Deferred: closure capture reconciliation"). Nothing to enforce until that design lands. This sprint sits idle until then, or gets rejected if the closure-capture design ends up not needing per-scope structural fields.

Gap #3 is already covered.

## Status

**Active.** Blocked on the closure-capture design.
