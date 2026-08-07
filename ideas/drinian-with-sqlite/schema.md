# Schema

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_schema",
	"role": "the SQLite schema for the Drinian-with-SQLite design. Split out from index.md so the tables can be read (and eventually run through sqlite3) without scrolling past all the surrounding design prose. Companion to ideas/drinian-with-sqlite/ — see there for the framing, design decisions, and features the schema enables.",
	"status": "sketching 2026-08-07 — table shapes proposed; not committed"
}}
~~~

The SQLite schema for Drinian, extracted from [ideas/drinian-with-sqlite](https://www.puck.uno/ideas/drinian-with-sqlite/) for readability. Comments inline; see the companion page for the rationale, feature list, and trade-offs.

## Tables

~~~sql
-- Objects. One row per live object. Includes primitives (strings,
-- numbers), reference-class instances (variables, hash_elements),
-- user-class instances, classes, roles — and srcs, asts, and everything
-- else that used to want its own ID space. Regular autoincrement
-- primary key; no shared string-counter table.
create table objects (
    id       integer primary key autoincrement,
    role_pk  integer not null references objects(id),   -- owner role (itself an object)
    src_pk   integer references objects(id),            -- src entry (itself an object; see srcs sidecar)
    src_line integer,

    -- Native-handle escape hatch. Non-null for objects that carry an
    -- opaque host resource (file descriptor, socket, coroutine, C
    -- userdata) that can't be represented as an SQLite scalar. The
    -- content is a Lua-side reference key that resolves through the
    -- engine's handle registry; the schema doesn't inspect it, just
    -- keeps it alive alongside the object.
    handle_key text,

    -- Primitive slot. Two columns:
    --   pr_type — null for non-primitive objects; one of
    --             's' (string), 'n' (number), 'b' (boolean), 'u' (null)
    --             for primitive objects.
    --   pr_val  — the primitive value; polymorphic (SQLite typeless column).
    -- Both fields are immutable after insert (enforced by a BEFORE UPDATE
    -- trigger, not shown here).
    pr_type  text check (pr_type is null or pr_type in ('s', 'n', 'b', 'u')),
    pr_val,

    -- Per-pr_type shape checks. `is` (not `in`) so null cleanly evaluates
    -- to false — the `in` form would give NULL which SQLite's CHECK
    -- accepts as passing, silently letting bad values through.
    check (pr_type is null     or pr_val is not null or pr_type = 'u'),
    check (pr_type is not 'u'  or pr_val is null),
    check (pr_type is not 'b'  or pr_val is 0 or pr_val is 1),
    check (pr_type is not 'n'  or typeof(pr_val) in ('integer', 'real')),
    check (pr_type is not 's'  or typeof(pr_val) = 'text'),
    check (pr_type is not null or pr_val is null)   -- non-primitive → pr_val must be null too
);

-- Index on role_pk: "everything owned by X" — one lookup.
create index objects_role on objects(role_pk);

-- Per-object bucket. Key-value hash. Values are always object IDs
-- (buckets never inline primitives — primitives get their own object
-- row via objects.pr_type + objects.pr_val).
create table buckets (
    object_pk       integer not null references objects(id) on delete cascade,
    key             text    not null,
    value_object_pk integer not null references objects(id),
    primary key (object_pk, key)
);

-- Reverse index on value_object_pk: "who holds this object in their
-- bucket?" — one lookup instead of a whole-buckets scan. Used by GC
-- and by inspector queries.
create index buckets_value on buckets(value_object_pk);

-- Per-object stack. Ordered array of platters, position 0 at the top.
create table platters (
    object_pk   integer not null references objects(id) on delete cascade,
    position    integer not null,          -- 0 = top of stack
    class_pk    integer not null references objects(id),   -- the class object
    is_shadow   integer not null default 0 check (is_shadow in (0, 1)),
    nested_uuid text,                       -- non-null iff nested-object platter
    warning     text,                       -- optional annotation
    primary key (object_pk, position)
);

-- Reverse index on class_pk: "all instances of class X" — one lookup.
-- Enables introspection like "how many closures are alive?" without
-- a full-table scan.
create index platters_class on platters(class_pk);

-- References. Sidecar for reference-class objects (core:variable,
-- core:hash_element, ...). The row's id IS the reference-object's id;
-- target_pk points at what it currently resolves to.
--
-- Three GC-scratch columns route rows through the mark-and-drain
-- collector. Normal state: all three null. See index.md § GC for the
-- state machine and drain flow.
create table refs (
    id          integer primary key references objects(id) on delete cascade,
    target_pk   integer not null references objects(id),
    needs_trace integer check (needs_trace = 1),
    in_trace    integer check (in_trace    > 0),
    del         integer check (del         = 1)
);

-- Reverse index on target_pk: "who references this object?" is now a
-- single-index lookup. Orphan detection becomes a set-difference query.
create index refs_target on refs(target_pk);

-- Partial indexes so the drain's per-state queries hit only marked
-- rows rather than the whole refs table.
create index refs_needs_trace on refs(needs_trace) where needs_trace = 1;
create index refs_in_trace    on refs(in_trace)    where in_trace    is not null;
create index refs_del         on refs(del)         where del         = 1;

-- Roles. Sidecar for role-class objects. Trivet-style tree via
-- self-referencing parent_pk, plus the Trivet locks.
create table roles (
    id                  integer primary key references objects(id) on delete cascade,
    parent_pk           integer references roles(id),           -- null for root
    -- Materialized ancestor path — dot-separated IDs of ancestors,
    -- e.g., '.1.5.7.' for a role two hops under the root chain 1→5→7.
    -- Maintained by triggers on parent_pk changes. Enables O(1)
    -- ancestor/descendant queries via LIKE prefix matching.
    path                text    not null default '',
    -- Trivet-style tree locks. All boolean, all mutable in one
    -- direction only (enforced by triggers not shown here).
    root_locked         integer not null default 0 check (root_locked         in (0, 1)),
    moves_prohibited    integer not null default 0 check (moves_prohibited    in (0, 1)),
    allow_new_children  integer not null default 1 check (allow_new_children  in (0, 1))
);

-- Path index for ancestor/descendant queries.
create index roles_path on roles(path);

-- Source-file registry. Sidecar for src-entry objects. Every value
-- that carries a src stamp points its src_pk at an object with a row
-- here.
create table srcs (
    id   integer primary key references objects(id) on delete cascade,
    kind text    not null check (kind in ('file', 'uns')),
    path text    not null
);

-- ASTs. Sidecar for AST objects (top-level programs, function bodies,
-- method bodies, closure bodies). Body is a JSON blob — CaspM doesn't
-- need row-level SQL access, but the JSON1 extension can query into it.
create table asts (
    id     integer primary key references objects(id) on delete cascade,
    src_pk integer not null references objects(id),        -- src object
    body   text    not null                                -- CaspM tree as JSON
);

-- Call stack. Position 0 = bottom (root frame); top of array = the
-- currently-executing frame. In-flight exceptions live here too, with
-- action = 'exception' — they slot alongside frames as they unwind.
create table call_stack (
    position       integer primary key,
    action         text    not null check (action in (
        'top_level', 'function_call', 'function_invocation', 'method_call',
        'block', 'if_block', 'delegate_to', 'exception', 'on_close'
    )),
    role_pk        integer not null references objects(id),
    lexical_parent integer references call_stack(position),  -- null for root frame
    src_pk         integer references objects(id),
    src_line       integer,
    callable_pk    integer references objects(id),          -- Function/Method/Closure object
    receiver_pk    integer references objects(id),          -- %self for methods; null otherwise
    iterator_state text,                                    -- JSON: {"position": N, "of": M}
    delegations    text                                    -- JSON: {"agent": {}, ...}
);

-- Frame locals. Every variable binding in every frame. Cascade-drops
-- when its frame pops.
create table frame_locals (
    frame_position integer not null references call_stack(position) on delete cascade,
    name           text    not null,
    variable_pk    integer not null references objects(id),   -- the core:variable object
    primary key (frame_position, name)
);

-- GC error log. Records on_close handler failures. Small in healthy
-- programs; long list is a smell.
create table gc_errors (
    position  integer primary key autoincrement,
    class_pk  integer not null references objects(id),
    message   text    not null,
    src_pk    integer references objects(id),
    src_line  integer
);

-- Mutation history. Every insert / update / delete on the runtime
-- state gets a row here, maintained by triggers. Enables time-travel
-- debugging: "what was the state at time T?" replays from a snapshot.
-- Also: cheap "what changed between checkpoint A and B?" as a range
-- query. Kept as a separate concern — engines that don't want the
-- overhead skip installing the mutation-log triggers.
create table mutations (
    seq        integer primary key autoincrement,
    at         datetime not null default current_timestamp,
    kind       text not null check (kind in ('insert', 'update', 'delete')),
    table_name text not null,
    row_pk     text not null,     -- text so it can hold any table's PK
    before_row text,               -- JSON of the row before the change (null on insert)
    after_row  text                -- JSON of the row after the change (null on delete)
);

create index mutations_at         on mutations(at);
create index mutations_table_row  on mutations(table_name, row_pk);
~~~
