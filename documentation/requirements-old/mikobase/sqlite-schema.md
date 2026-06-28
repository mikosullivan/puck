# SQLite Schema

## `records`

~~~vibecode
{"vibecode": {
	"section": "records_table",
	"role": "defines the records identity table with immutable UUID pk and no-update trigger",
	"key_concepts": ["records", "record_pk", "UUID_v4", "randomblob", "immutable", "no_update_trigger"]
}}
~~~

```sql
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
```

## `records_history`

~~~vibecode
{"vibecode": {
	"section": "records_history_table",
	"role": "defines the append-only version history table with class name uniqueness trigger",
	"key_concepts": ["records_history", "instance_pk", "active", "bucket", "stack",
		"platter_stack", "whole_hash_for_class_definitions", "immutable_rows", "unique_class_name_trigger"]
}}
~~~

```sql
create table records_history (
	instance_pk  text primary key default (
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
	stack      text check(active = 0 or (stack is not null and json_type(stack) = 'object')),
	whole_hash integer not null default 0 check(whole_hash in (0, 1)),
	body       text check(whole_hash = 0 or (body is not null and json_type(body) = 'object')),
	unique(record_pk, updated_at)
);

-- An instance record uses the `bucket` and `stack` columns: `bucket` is the
-- object's data hash; `stack` is the ordered hash of platters (each platter
-- being {class, warning?, bucket?}). The platter at position 1 must be named
-- "shadow" — and when no "shadow" entry is present in the stack hash, an
-- empty shadow is understood to sit at position 1.
--
-- A class-definition record (an instance of puck.uno/class) uses the
-- whole-hash form instead: the row sets whole_hash = 1 and stores the
-- definition object (containing class='puck.uno/class' plus the definition's
-- name/inherits/fields/methods properties) in `body`. The `bucket` and
-- `stack` columns are null for whole-hash rows. See the worldlets reference
-- for both shapes.

create trigger records_history_no_update
before update on records_history
begin
	select raise(fail, 'records_history rows are immutable');
end;

-- Enforce unique class names among active class-definition records.
-- A class-definition record stores its definition in `body` with
-- whole_hash = 1 and body.class = 'puck.uno/class'; the class's name
-- is body.name.
create trigger records_history_unique_class_name
before insert on records_history
when new.active = 1
	and new.whole_hash = 1
	and json_extract(new.body, '$.class') = 'puck.uno/class'
begin
	select raise(fail, 'duplicate class name')
	where exists (
		select 1
		from current_records cr
		where
			cr.record_pk != new.record_pk
			and cr.whole_hash = 1
			and json_extract(cr.body, '$.class') = 'puck.uno/class'
			and json_extract(cr.body, '$.name') = json_extract(new.body, '$.name')
	);
end;
```

## Views

~~~vibecode
{"vibecode": {
	"section": "views",
	"role": "defines the current_records view that shows the latest active row per record",
	"key_concepts": ["current_records", "latest_active_row", "row_number", "tie_breaking_instance_pk",
		"active_filter"]
}}
~~~

```sql
-- current_records: the latest active history row for each record.
-- Tie-breaking uses instance_pk desc in case two rows share the same updated_at.
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
	stack,
	whole_hash,
	body
from ranked
where row_num = 1
and active = 1;
```

## `files`

~~~vibecode
{"vibecode": {
	"section": "files_table",
	"role": "defines the files metadata table with sha256 deduplication and immutability",
	"key_concepts": ["files", "file_pk", "sha256_unique", "created_at", "size", "immutable"]
}}
~~~

```sql
create table files (
	file_pk text primary key default (
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
```

## `file_chunks`

~~~vibecode
{"vibecode": {
	"section": "file_chunks_table",
	"role": "defines the file content storage table with chunk ordering and last-chunk marker",
	"key_concepts": ["file_chunks", "chunk_index", "content_blob", "last_flag", "one_last_per_file_index",
		"immutable"]
}}
~~~

```sql
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
```

## Notes

~~~vibecode
{"vibecode": {
	"section": "notes",
	"role": "summary of schema-wide invariants: immutability, soft deletes, historical reads, class column",
	"key_concepts": ["engine_generated_pks", "append_only", "soft_deletes", "historical_reads",
		"class_column_UNS", "built-in_classes_recognized", "empty_file_chunk"]
}}
~~~

- All primary keys are immutable and engine-generated; clients cannot supply PKs.
- PKs are UUID v4 values generated via `randomblob`, compatible with all SQLite versions.
- `records` and `records_history` are append-only; deletions are handled at the engine layer only.
- `files` and `file_chunks` are immutable once written; deletions are handled at the engine layer only.
- A record whose latest `records_history` row has `active = 0` is considered deleted and excluded from normal queries.
- Historical reads use an `updated_at` cutoff timestamp to find the latest row at or before that point in time.
- `unique(record_pk, updated_at)` prevents timestamp collisions within a record's history.
- An instance record's class identity lives in the `stack` column (a JSON object of platters); class names inside it are UNS strings. There is no foreign key to `records` — the engine validates class existence at write time.
- A class-definition record uses the whole-hash form (`whole_hash = 1`, definition object in `body`) rather than `bucket`+`stack`. Its `body.class` is `puck.uno/class` and `body.name` is the UNS being defined.
- Built-in classes (`puck.uno/record`, `puck.uno/class`, `puck.uno/reference`, `puck.uno/dbfile`, etc.) are recognized by the engine and do not need stored records.
- Empty files are represented by a single `file_chunks` row with `content = ''` and `last = 1`.
- Class name uniqueness is enforced by the `records_history_unique_class_name` trigger via `current_records`.
- The `current_records` view uses `instance_pk desc` as a tie-breaker when two rows share the same `updated_at`.
