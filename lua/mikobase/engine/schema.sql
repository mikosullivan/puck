create table records (
    record_pk text primary key
);

create trigger records_no_update
before update on records
begin
    select raise(fail, 'records rows are immutable');
end;

create table records_history (
    instance_pk    text primary key default (
        lower(
            hex(randomblob(4)) || '-' ||
            hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' ||
            substr('89ab', abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)), 2) || '-' ||
            hex(randomblob(6))
        )
    ),
    record_pk      text not null references records(record_pk),
    updated_at     text not null default (strftime('%Y-%m-%dT%H:%M:%f', 'now')),
    active         integer not null default 1 check(active in (0, 1)),
    bucket         text check(active = 0 or (bucket is not null and json_type(bucket) = 'object')),
    class          text check(active = 0 or class is not null),
    custom_classes text check(active = 0 or (custom_classes is not null and json_type(custom_classes) = 'object')),
    unique(record_pk, updated_at)
);

create trigger records_history_no_update
before update on records_history
begin
    select raise(fail, 'records_history rows are immutable');
end;

create trigger records_history_unique_class_name
before insert on records_history
when new.active = 1 and new.bucket is not null
begin
    select raise(fail, 'duplicate class name')
    where
        new.class = 'mikobase.com/record/class'
        and exists (
            select 1 from current_records
            where
                class = 'mikobase.com/record/class'
                and record_pk != new.record_pk
                and json_extract(bucket, '$.name') = json_extract(new.bucket, '$.name')
        );
end;

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
    class,
    custom_classes
from ranked
where row_num = 1
and active = 1;

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
