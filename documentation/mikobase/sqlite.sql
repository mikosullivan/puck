-- Mikobase SQLite Schema

-- ============================================================
-- records
-- ============================================================

create table records (
	record_pk text primary key default (
		lower(
			hex(randomblob(4)) || '-' ||
			hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' ||
			substr('89ab', abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)), 2) || '-' ||
			hex(randomblob(6))
		)
	)
);

create trigger records_no_update
before update on records
begin
	select raise(fail, 'records rows are immutable');
end;

-- ============================================================
-- records_history
-- ============================================================

create table records_history (
	instance_pk    text primary key default (
		lower(
			hex(randomblob(4)) || '-' ||
			hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' ||
			substr('89ab', abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)), 2) || '-' ||
			hex(randomblob(6))
		)
	),
	record_pk  text not null references records(record_pk),
	updated_at text not null default (strftime('%Y-%m-%dT%H:%M:%f', 'now')),
	active     integer not null default 1 check(active in (0, 1)),
	bucket     text check(active = 0 or (bucket is not null and json_type(bucket) = 'object')),
	classes    text check(active = 0 or (classes is not null and json_type(classes) = 'object')),
	unique(record_pk, updated_at)
);

-- The `classes` column holds the platter stack as a JSON object keyed by
-- per-platter UUID; each value is a hash {class, bucket}. Per-platter
-- buckets live inside this structure, not in the row's top-level `bucket`
-- column.

create trigger records_history_no_update
before update on records_history
begin
	select raise(fail, 'records_history rows are immutable');
end;

-- Enforce unique class names among active class-definition records.
-- A class-definition record has a platter of class 'puck.uno/record/class'
-- in its `classes` hash; its name lives in that platter's bucket under `name`.
create trigger records_history_unique_class_name
before insert on records_history
when new.active = 1 and new.classes is not null
begin
	select raise(fail, 'duplicate class name')
	where
		exists (
			select 1
			from json_each(new.classes) np
			where json_extract(np.value, '$.class') = 'puck.uno/record/class'
		)
		and exists (
			select 1
			from current_records cr, json_each(cr.classes) op
			where
				cr.record_pk != new.record_pk
				and json_extract(op.value, '$.class') = 'puck.uno/record/class'
				and json_extract(op.value, '$.bucket.name') = (
					select json_extract(np.value, '$.bucket.name')
					from json_each(new.classes) np
					where json_extract(np.value, '$.class') = 'puck.uno/record/class'
					limit 1
				)
		);
end;

-- ============================================================
-- current_records view
-- ============================================================

-- The latest active history row for each record.
create view current_records as
with ranked as (
	select
		rh.*,
		row_number() over (
			partition by rh.record_pk
			order by rh.updated_at desc, rh.instance_pk desc
		) as row_num
	from records_history rh
)
select
	instance_pk,
	record_pk,
	updated_at,
	active,
	bucket,
	classes
from ranked
where row_num = 1
and active = 1;

-- ============================================================
-- files
-- ============================================================

create table files (
	file_pk    text primary key default (
		lower(
			hex(randomblob(4)) || '-' ||
			hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' ||
			substr('89ab', abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)), 2) || '-' ||
			hex(randomblob(6))
		)
	),
	created_at text not null default (strftime('%Y-%m-%dT%H:%M:%f', 'now')),
	size       integer not null,
	sha256     text not null unique
);

create trigger files_no_update
before update on files
begin
	select raise(fail, 'files rows are immutable');
end;

-- ============================================================
-- file_chunks
-- ============================================================

create table file_chunks (
	file_chunk_pk integer primary key,
	file_pk       text not null references files(file_pk) on delete cascade,
	chunk_index   integer not null check(chunk_index >= 0),
	content       blob not null,
	last          integer not null default 0 check(last in (0, 1)),
	unique(file_pk, chunk_index)
);

create unique index file_chunks_one_last_per_file
	on file_chunks(file_pk)
	where last = 1;

create trigger file_chunks_no_update
before update on file_chunks
begin
	select raise(fail, 'file_chunks rows are immutable');
end;
