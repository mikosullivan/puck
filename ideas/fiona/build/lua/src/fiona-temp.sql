-- Per-connection temp tables for Fiona's iterator support and the
-- drain's GC-callback machinery. Applied by fiona.lua's get_db every
-- time a connection opens — temp tables live in the connection's temp
-- schema and don't survive close, so this can't go in fiona.sql
-- (which is applied once at fresh-DB creation).
--
-- `iterators` is the roster of active iterator handles.
-- `iterator_elements` holds one row per element in each iterator's
-- snapshot; the FK cascade means deleting one row from `iterators`
-- drops that iterator's whole payload in one shot.
-- `process` holds runtime-mode flags (`in_gc_callback_phase`) and the
-- drain's monotonic counter (`in_trace_counter`); the auto-mark trigger
-- below reads from it. See specs/on-gc.md for the full mechanism.

create temp table if not exists iterators (
	iterator_pk integer primary key autoincrement,
	kind text,
	source_parent integer,
	created_at datetime default current_timestamp
);

create temp table if not exists iterator_elements (
	iterator_pk integer not null references iterators(iterator_pk) on delete cascade,
	position integer not null check (position >= 0),
	-- Populated by keys iterators; null for value / array iterators.
	key text,
	-- Populated by value / array iterators (snapshots the row identity,
	-- not the value); null for keys iterators. Insert-time referential
	-- integrity to main.relationships is enforced by the trigger below —
	-- a plain FK doesn't work because SQLite doesn't support foreign
	-- keys across schemas (temp → main). On delete of the referenced
	-- relationships row we do nothing special: the iterator element
	-- retains the now-dangling rel_pk, and the walk returns null when
	-- it can't find the referenced row.
	rel_pk integer,
	-- Exactly one of {key} or {rel_pk}. Both null (payload-less row) or
	-- both set (redundant snapshot) are meaningless.
	check (
		(key is not null and rel_pk is null) or
		(key is null and rel_pk is not null)
	),
	primary key (iterator_pk, position)
);

-- Insert-time referential integrity for rel_pk. Fires only when a
-- rel_pk is supplied (keys iterators leave it null and skip the check).
create temp trigger if not exists iterator_elements_check_rel_pk
before insert on iterator_elements
when new.rel_pk is not null and not exists (
	select 1 from main.relationships where rel_pk = new.rel_pk
)
begin
	select raise(abort, 'iterator_elements.rel_pk must reference an existing relationships row');
end;

-- ------------------------------------------------------------
-- Process table + auto-mark trigger — the drain's runtime-mode plumbing.
-- ------------------------------------------------------------

create temp table if not exists process (
	key text primary key,
	details
);

-- While the drain is firing its GC callbacks (marked by presence of
-- the `in_gc_callback_phase` row), any newly-inserted collection is
-- auto-marked in_trace using the next value vended by the
-- `in_trace_counter` row. Two primary-key hits, no aggregates.
create temp trigger if not exists collections_auto_mark_during_gc
after insert on collections
when exists (select 1 from process where key = 'in_gc_callback_phase')
begin
	update process set details = details + 1
		where key = 'in_trace_counter';
	update collections set in_trace = (
		select details from process where key = 'in_trace_counter'
	) where collection_pk = new.collection_pk;
end;
