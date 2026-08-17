~~~vibecode
{"doc": "sprint-note", "sprint": "roles-as-primitives",
	"role": "Draft spec text for the roles-as-primitives design — a role is an `objects` row with `primitive = 'r'`. Single-section explainer, in the shape it'll take when promoted to requirements/cvm/roles.md."}
~~~

# Roles

A **role** is an `objects` row with `primitive = 'r'`. The row-kind discriminator carries the whole "is this a role?" answer — no view lookup, no composite column test.

## What a role does

Under the current CVM design, a role has one job: **exist in a strict hierarchical tree.** That's it. Roles don't hold state, they don't have buckets or stacks, and they can't be referenced from `refs`. If role-carried state is wanted later (permissions, config, class registrations, whatever), that's a separate slice with its own storage rules.

## Storage rules

- **`primitive = 'r'`.** The whole discriminator; the `roles` view is `select object_pk from objects where primitive = 'r'`.
- **`core_role`** — nullable text; when set, must be one of `'e'` (engine), `'c'` (cache), `'u'` (user). Cross-column checked so only `'r'` rows can carry it.
- **`parent_role`** — nullable FK to `objects(object_pk)`. Cross-column checked so only `'r'` rows can carry it. The target must be an `'r'` row (enforced by `objects_parent_role_must_be_role`).
- **Roles can't be `refs` parents.** `refs_role_cannot_be_parent` blocks any INSERT into `refs` where the parent row's primitive is `'r'`. Roles are structurally leaves in the object graph — nothing hangs off them.

## The role tree

- **Single root.** Only the engine role (`core_role = 'e'`) may have `parent_role = null`. Every other role — cache, user, and any runtime-added role — must have a `parent_role`. Enforced by `objects_only_engine_can_be_role_root`.
- **`parent_role` is immutable.** Set at INSERT; never changes.
- **Cycle-free by construction.** At INSERT time, `parent_role` must reference an already-existing role. Combined with immutability, the tree can only grow downward from existing nodes — no back-edge can form. **No runtime cycle check exists because none is needed.** A future reader shouldn't wonder where the cycle guard lives; the invariant is structural.
- **Delete rules.** Core roles can't be deleted (`objects_no_delete_root_role`). A runtime role can be deleted only when nothing references it: `parent_role` FK is `NO ACTION` (RESTRICT), so a role with descendants blocks; `owner_role` FK is also `NO ACTION`, so a role that owns other rows blocks. Deletion must work leaves-inward.

## `owner_role` is not the same thing

Any row (not just roles) can have `owner_role` set — that's the role that CREATED the row. Non-role rows are REQUIRED to have `owner_role` set (`objects_owner_role_required_on_non_roles`); role rows may omit it (the engine seed does). The `owner_role` FK must point at an `'r'` row (`objects_owner_role_must_be_role`), just like `parent_role`.

## Why not use `'h'` for roles

Earlier drafts stored roles as HashPrimitives (`primitive = 'h'`) marked by having `core_role` or `parent_role` set. That worked but had two costs:

- **"Is this row a role?" required the `roles` view** — a UNION of two queries. Under `'r'`, it's a column read.
- **Nothing prevented other primitives from becoming roles.** A scalar or frame with `parent_role` set was structurally a role per the view, even though nothing in the design supported that. `'r'`-as-primitive closes the hole by construction.

## Related

- [ownership](https://puck.uno/requirements/cvm/ownership) — buckets and stacks as refs; the one-hash-one-array cap on non-container parents. Roles are non-containers with a stricter rule (no refs at all).
- [garbage-collection](https://puck.uno/requirements/cvm/garbage-collection/) — the mark-triggers substrate. Roles participate as reachability anchors (pinned) but never as ref sources.
