# refs — renamed from relationships

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_sidequests_refs_rename",
	"role": "sidequest carried alongside the frames-as-objects brainstorm: the schema table `relationships` becomes `refs`, and its primary key `rel_pk` becomes `ref_pk`. Every trigger, index, error id, and comment renamed to match. Confined to ideas/frames-as-objects/ until promotion. Documents what changed, what wasn't touched, and the promotion coordination rule.",
	"status": "landed in ideas/, needs promotion"
}}
~~~

The schema table `relationships` is renamed to `refs`. The primary key column `rel_pk` becomes `ref_pk`. Reads cleaner, matches the mental model of the table being a set of references between objects.

## What changed

- **Table name:** `relationships` → `refs`
- **Column name:** `rel_pk` → `ref_pk`
- **Triggers:** `refs_parent_must_be_primitive_container`, `refs_no_update`, `refs_mark_needs_trace_after_delete`
- **Indexes:** `refs_parent`, `refs_child`
- **Error id:** `refs_immutable`

Every place the schema at [cvm.sql](https://www.puck.uno/ideas/frames-as-objects/src/cvm.sql), the ER diagram, or the walkthroughs mentioned `relationships` or `rel_pk` now uses the new names.

## What was NOT touched

- **CSS class `tbl-title-relationships`** in `orlando/client-assets/style.css`. It's a styling handle, not a semantic name, and it lives outside the `ideas/` folder. The class stays; the visible `<th>` content becomes "refs".
- **`src/engine/mvm.sql`** still uses the old names — the reference implementation matches the current `requirements/` spec, not the brainstorm.
- **Engine tests** at `tests/main/lua/engine/` still reference the old names.

## Promotion coordination

When frames-as-objects promotes to `requirements/`, the rename lands in this order:

1. Update `requirements/` docs — every mention of the `relationships` table or `rel_pk` column.
2. Update `src/engine/mvm.sql`.
3. Update the engine tests.
4. Run all tests and verify each passes.

Docs before code; code before tests. Doing them out of order breaks tests transiently.
