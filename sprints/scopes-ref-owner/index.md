~~~vibecode
{"doc": "sprint-index", "sprint": "scopes-ref-owner",
	"role": "Split from the retired close-schema-holes sprint (hole #5). Design decision + trigger: what kind of parent can carry a ref keyed `'scopes'`? Currently any container. The scopes convention (frame.bucket → 'scopes' → ArrayPrimitive of hash scopes) is documented in requirements/cvm/scopes and enforced partially by refs_scopes_key_requires_array and refs_scopes_array_entries_must_be_hashes — but nothing pins the PARENT side to a frame's bucket. Sources: issue #1663 (ChatGPT critique § 5).",
	"status": "active — design decision needed before implementation"}
~~~

# scopes-ref-owner

Hole #5 from the ChatGPT critique. The scopes convention says:

- A frame's bucket carries a `key = 'scopes'` ref.
- That ref points at an ArrayPrimitive.
- The array's entries are hash-primitive scope rows.

Shipping enforces the middle two (`refs_scopes_key_requires_array`, `refs_scopes_array_entries_must_be_hashes`). It does not enforce the first — any container can carry a `key = 'scopes'` ref, not just a frame's bucket.

## Design decision

Before implementing, the concept needs a clear rule about which rows are valid parents for a `'scopes'` ref. Candidates:

- **Strict**: the parent must be a HashPrimitive AND must be the bucket of a frame (there's a `refs` row from a `'f'` row to this hash, and its idx = 0 or key = "bucket" or however buckets are marked). Requires knowing the "is this hash a frame's bucket?" question at INSERT time — likely a subquery join or a helper view.
- **Permissive**: the parent must be a HashPrimitive. Callers writing `'scopes'` outside a frame-bucket context would still be within the letter of the rule.
- **Status quo, documented**: leave open; document that `'scopes'` is a convention, not enforced on the parent side.

Miko to decide before implementation.

## Status

**Active.** Blocked on the design decision above. Once resolved: one trigger, one test.
