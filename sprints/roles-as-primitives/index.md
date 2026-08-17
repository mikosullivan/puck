~~~vibecode
{"doc": "sprint-index", "sprint": "roles-as-primitives",
	"role": "Sprint to promote roles from a column-marked shape (any primitive with core_role or role_parent set) to their own primitive value 'r'. Minimal role semantics — roles exist in a hierarchical tree and nothing else. Fixes critique § 3 by construction (a role IS a role because it's typed 'r'); collapses the roles view; removes cross-row role-check subqueries.",
	"status": "active — scope decided, work not started"}
~~~

# roles-as-primitives

Promote roles from "a hash-primitive with `core_role` or `role_parent` set" to their own primitive value: `'r'`. The role definition becomes structural, not conventional; downstream machinery simplifies.

Currently:
- The `roles` view is a UNION of two queries.
- "Is this row a role?" requires a view lookup.
- Nothing prevents a scalar, array, or frame from having `role_parent` set (critique § 3).
- The three seeded roles (engine, cache, user) are HashPrimitives by convention only.

Under `'r'`-as-primitive:
- The `roles` view collapses to `select object_pk from objects where primitive = 'r'`.
- "Is this row a role?" is a column read.
- Roles can't be any other primitive by construction.
- Seeded rows are `primitive = 'r'`.

## Rules for the new primitive

- **Roles exist in a strict hierarchical tree.** That's it.
- **No state.** Roles cannot be ref parents (no bucket, no stack, no children of any kind). Features that would give roles state land in a later slice, if ever.
- **Immutable `role_parent`** (unchanged from current schema). At INSERT, `role_parent` must reference an existing role; once set, never changes. Together these two rules mean the role tree is **cycle-free by construction** — no runtime cycle check is needed, ever. Worth a note in the spec so a future reader doesn't try to add one.
- **`core_role` stays** as the small enum distinguishing engine / cache / user among the `'r'` rows. Runtime-added roles are `'r'` with `core_role` null.
- **`owner_role`** FK still points at a role — still means "the role that created this row" — just now points at an `'r'` primitive row.

## Sprint work

1. **Schema changes** in `src/schema.sql`:
	- Add `'r'` to the `primitive` CHECK domain.
	- Broaden the "cannot be a ref parent" rule to include `'r'` (currently only scalars are forbidden; `'r'` joins that list).
	- Simplify `roles` view.
	- Simplify `objects_role_parent_must_be_role` and `objects_owner_role_must_be_role` — direct primitive check on the target row, no view subquery.
	- Update the three seed inserts (engine / cache / user) from `primitive = 'h'` to `primitive = 'r'`.
	- Consider whether `core_role` still needs its own CHECK / unique index / immutability trigger under the tighter primitive discriminator (yes — `core_role` still names three specific roles among all `'r'` rows).
2. **Tests** in `tests/`:
	- `'r'` primitive accepted at INSERT; roles created runtime-style (no core_role, `role_parent` set) work.
	- `'r'` cannot be a ref parent (all four child primitives rejected).
	- `role_parent` must reference an `'r'` row (typed check now, not view subquery).
	- Regression: the tree can't cycle by construction — noted in a test-side comment; nothing to actively test at the trigger layer since the guarantee is structural.
	- Seeded engine/cache/user rows have `primitive = 'r'` post-install.
3. **Spec draft** in `masks.md`-style — a single-section explainer, plus a callout on the cycle-free-by-construction property so it stays visible.

## Deferred (not this sprint)

- Roles-carry-state features — permissions, config, class registrations. If wanted later, either add container semantics to `'r'` or give roles a bucket-child pattern; that's its own slice.
- Migration of existing docs (walkthroughs, requirements/cvm/) that describe roles as HashPrimitives. Happens after promotion to shipping.

## Status

**Active.** Scope decided; work not started.
