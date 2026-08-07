# Fiona as Drinian

~~~vibecode
{"vibecode": {
	"doc": "ideas_fiona_as_drinian",
	"role": "spitball space for using Fiona (SQLite-backed object store, split out to mikosullivan/fiona 2026-08-03) as the storage layer for all of Drinian — Caspian's runtime state. Not committed to; V1 Drinian is the in-memory hash approach per requirements/drinian/. This directory is a reference for Fiona's current table shapes so we can brainstorm without opening the other repo every time.",
	"status": "brainstorm 2026-08-07 — table shapes only"
}}
~~~

Reference copy of Fiona's current tables — pulled from `mikosullivan/fiona/src/fiona.sql`, with triggers, indexes, and inline comments stripped. Two tables: `collections` (hashes and arrays) and `relationships` (parent-to-child-collection edges OR parent-to-scalar edges).

## Tables

~~~sql
create table collections (
	collection_pk integer primary key autoincrement,
	type text not null check (type in ('h', 'a')),
	tree text unique check (tree is null or tree != ''),
	needs_trace integer check (needs_trace is null or needs_trace = 1),
	in_trace    integer check (in_trace    is null or in_trace     > 0)
);

create table relationships (
	rel_pk  integer primary key autoincrement,
	parent  integer not null references collections(collection_pk) on delete cascade,
	child   integer references collections(collection_pk) on delete cascade,
	key     text,
	idx     not null,
	st      text check (st in ('s', 'n', 'b', 'u')),
	scalar,

	check (
		(child is not null and st is null and scalar is null) or
		(child is null and st is not null)
	),

	check (st is null or st != 'b' or scalar is 0 or scalar is 1),
	check (st is null or st != 'u' or scalar is null),
	check (st is null or st != 'n' or typeof(scalar) in ('integer', 'real')),
	check (st is null or st != 's' or typeof(scalar) = 'text'),

	check (typeof(idx) = 'integer'),
	check (idx >= 0),

	unique (parent, key),
	unique (parent, idx)
);
~~~

## Tree enforcement

Every write to `relationships` or `collections` potentially touches tree structure. Fiona enforces tree invariants at the DB level via triggers that fire on every write — but a partial-index gate keeps the per-write cost near zero when no trees exist.

Rough sketch, worked out with Miko 2026-08-07. Will land better plans down the road; this is the "simple correct starting point" version.

### The gate

Partial index on `collections.tree` where non-null:

~~~sql
create index collections_tree on collections(tree) where tree is not null;
~~~

Every tree-check trigger uses a `when` clause that consults the partial index:

~~~sql
create trigger tree_recheck_after_relationships_insert
after insert on relationships
when exists (select 1 from collections where tree is not null)
begin
	select check_all_trees();
end;
~~~

SQLite evaluates the `when` clause before firing the body. When the partial index is empty (no trees defined), the body never runs — per-write cost is one index probe (essentially free).

Same shape applies to six triggers total: `after insert / update / delete` on both `relationships` and `collections`.

### The walk

When the gate opens, `check_all_trees()` — a Lua UDF called from SQL:

1. Loads all tagged tree roots: `select collection_pk, tree from collections where tree is not null`.
2. For each root, walks the tree top-down through the `.<tree_name>` array chain.
3. Verifies structural invariants along the way:
	- **No cycles.** Any node visited twice is a cycle.
	- **Containment chain intact.** Every non-root member reaches the tagged root via `.<tree_name>` field chain.
	- **`root_locked` not mutated.** A locked tree's `collections.tree` value hasn't changed.
	- **`moves_prohibited` respected.** No `.<tree_name>` field on any node was repointed.
	- **`allow_new_children` respected.** Nodes that opted in didn't get new children.
4. Raises with a specific error ID on the first violation, using the Lua ID convention (`trivet_audit_cycle_detected:`, etc.).

### Cost

- **No trees present.** Gate short-circuits every trigger. Per-write cost is one index probe. Feature tax is negligible.
- **Trees present.** Cost per write is O(sum of tree sizes). For Drinian's roles tree (10-50 nodes, one tree), microseconds per write.

### Why this shape

- **Complete.** Every write is verified; nothing can corrupt a tree without being caught immediately.
- **Simple.** No separately-maintained `tree_members` table, no cache invalidation, no bookkeeping to keep in sync.
- **DB-level.** Raw SQL writes are caught the same as writes through Fiona's API.
- **Feature tax bounded.** Databases that don't use trees pay nothing.

### Future optimization directions

Pure performance work with no correctness impact — defer until profile says needed:

- **Only re-check trees whose nodes were touched by the write.** Requires knowing which collections are in which trees; membership cache or a targeted walk.
- **Incremental invariant checks.** Verify only the delta introduced by the current write instead of re-walking from scratch.
- **Per-node cached tree membership.** A `tree_members` materialized table updated on tree ops; membership becomes O(1) lookup instead of a walk.

None of these are needed for Drinian's scale. The starting shape above is good enough; the room for a much better plan is real but not the current priority.

