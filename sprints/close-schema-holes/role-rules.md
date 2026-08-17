~~~vibecode
{"doc": "sprint-note", "sprint": "close-schema-holes",
	"role": "Report of the current rules on role records in the CVM schema — what a role IS, what the schema enforces on core_role / role_parent / owner_role, and what's documented-but-not-enforced. Baseline for the sprint's decisions about which role-related holes to close."}
~~~

# Role rules — current state

Report of what the CVM schema currently enforces on role records, so the sprint has a clear baseline before deciding which role-related holes to close.

## What a role IS

The **`roles` view** is the source of truth:

~~~sql
create view roles as
	select object_pk from objects where core_role = 'e'
	union
	select object_pk from objects where role_parent is not null;
~~~

A row is a role if:

- It carries `core_role = 'e'` (the engine root), or
- It has any non-null `role_parent` (which reaches cache, user, and every runtime-added role).

Note the view does NOT include `core_role = 'c'` or `'u'` by their `core_role` alone — the seeded cache and user rows appear only because they also have `role_parent` set. A row with `core_role = 'c'` but no `role_parent` would fall outside the view.

## What the schema currently enforces

### `core_role`

- **Domain restricted** to `('e', 'c', 'u')` — column CHECK.
- **Unique per value** — partial unique index `objects_core_role`, `where core_role is not null`.
- **Immutable** — `objects_core_role_immutable` trigger rejects updates that change the value.

### `role_parent`

- **FK to `objects(object_pk)`** with `ON DELETE CASCADE` — if the parent role is deleted, cascade removes its descendants.
- **Must reference an existing role** at INSERT — `objects_role_parent_must_be_role` trigger checks the `roles` view.
- **Cannot equal self** — `objects_role_parent_not_self` trigger.
- **Immutable** — `objects_role_parent_immutable` trigger. Load-bearing: this is what keeps the role tree cycle-free without a recursive check.

### `owner_role`

- **FK to `objects(object_pk)`** (no cascade).
- **Must be a role** at INSERT — `objects_owner_role_must_be_role` trigger.
- **Cannot equal self** — `objects_owner_role_not_self` trigger.
- **Immutable** — `objects_owner_role_immutable` trigger.
- **Required for non-role rows** — `objects_owner_role_required_on_non_roles` trigger raises if a new row has `core_role null AND role_parent null AND owner_role null`. Roles themselves may omit `owner_role` — the engine seed does.

### Core-role rows

- **Cannot be deleted** — `objects_no_delete_root_role` trigger.
- **Cannot be updated** (most fields) — `objects_no_update_root_role` trigger. Also the source of the [critique § 7](./critique#7-references-to-immutable-core-roles-may-become-undeletable) blocker on ref delete: when a ref whose child is a core role is deleted, the mark-needs-trace trigger tries to set `needs_trace = 1` on the core role, and this trigger blocks it.

### Indexes

- `objects_core_role` — partial unique on `core_role`, `where core_role is not null`.
- `objects_role_parent` — partial index on `role_parent`, `where role_parent is not null`.
- `objects_owner_role` — partial index on `owner_role`, `where owner_role is not null`.

## What's NOT enforced

**No constraint on the primitive of a role.** The schema allows a `primitive = 'o'` scalar or `primitive = 'f'` frame to carry a `core_role` or `role_parent`. The seeded core roles are all `primitive = 'h'`, suggesting the intent is hash-only, but nothing rejects other primitives. Critique § 3 flags this as design-dependent — decide whether "role ⇒ primitive = 'h'" is the invariant, or whether arbitrary objects are legitimately allowed.

## Seeded state

At the moment `cvm.open` returns, three role rows are already present. See [initialized](./initialized) for the full snapshot with all columns:

- **engine** — `primitive='h'`, `core_role='e'`, `persistent=1`. No `role_parent`, no `owner_role`.
- **cache** — `primitive='h'`, `core_role='c'`, `role_parent=engine`, `owner_role=engine`, `persistent=1`.
- **user** — `primitive='h'`, `core_role='u'`, `role_parent=engine`, `owner_role=engine`, `persistent=1`.

## Related

- [initialized](./initialized) — objects table at initialized state, all columns
- [critique](./critique) — full ChatGPT critique text (issue #1663)
- [index](./index) — sprint index with the derived holes list
