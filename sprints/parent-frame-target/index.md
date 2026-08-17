~~~vibecode
{"doc": "sprint-index", "sprint": "parent-frame-target",
	"role": "Split from the retired close-schema-holes sprint (hole #2, marked CRITICAL in the parent sprint's index). Fixes the gap where `parent_frame` currently only requires the ROW HOLDING the pointer to be a frame (`check (primitive = 'f' or parent_frame is null)`) — not the row it POINTS AT. gc-cycle logic assumes both are frames. Sources: issue #1663 (ChatGPT critique § 2).",
	"status": "active — work not started"}
~~~

# parent-frame-target

Hole #2 from the ChatGPT critique. **Marked critical in the retired close-schema-holes sprint's index** — this is the strongest hole because later logic depends on the missing invariant.

The `parent_frame` column already has:

- `check (parent_frame is null or primitive = 'f')` — the ROW HOLDING the pointer must be a frame.
- FK `references objects(object_pk)` — the target must exist.

But nothing checks that the target row is itself a frame. The gc-cycle triggers (`frames_gc_set_deletes_children`, `frames_child_delete_requires_parent_gc`, etc.) all assume the parent is a frame; a `parent_frame` pointing at a HashPrimitive or a scalar would silently bypass those checks.

## Fix

Add a BEFORE INSERT trigger — `objects_parent_frame_must_be_frame` — that rejects when `new.parent_frame is not null and (select primitive from objects where object_pk = new.parent_frame) is not 'f'`. Mirrors the shape of the existing `objects_parent_role_must_be_role` and `objects_owner_role_must_be_role` triggers.

No UPDATE-side trigger needed: `objects_parent_frame_immutable` already blocks changing `parent_frame` after INSERT.

## Status

**Active.** Work not started. Scope: one new trigger + one new test.

## Integration

Direct add to shipping's `src/engine/cvm/schema.sql` right after `frames_parent_frame_not_self` (defense-in-depth against a frame being its own parent). Test lands in `tests/main/lua/engine/test_schema.lua`.
