# SQLite Design

## Purpose

This document describes the intended design for a future SQLite engine for Mikobase.

These are SQLite-engine design requirements, not universal rules for every engine.

## Core Position

The SQLite engine should preserve the same high-level Mikobase model as the PostgreSQL engine:

- append-only versioned classes
- append-only versioned records
- derived current state from latest history rows
- inheritance-aware class lookup
- Q0 support over current visible records

But SQLite has a different operating model:

- one database file is effectively one tenant
- there is no tenant-selection context like `api.current_tenant_pk`
- some invariants that PostgreSQL currently enforces with triggers or schema-level routines may need to move into Ruby engine code

## Tenant Model

SQLite does not have a meaningful tenant concept inside a single database file.

For the SQLite engine:

- each SQLite database file should be treated as exactly one tenant
- tenant switching should not exist within a connection
- there should be no `tenants` table
- there should be no per-row `tenant_pk` on classes, records, or history rows
- there should be no SQLite equivalent of `api.current_tenant_pk`

This simplifies the engine substantially.

Where PostgreSQL uses tenant scoping to prevent cross-tenant access, SQLite should rely on the simpler rule that everything in the file already belongs to the same logical tenant.

## Schema Direction

The SQLite engine should still use split identity and history tables.

Expected identity tables:

- `classes`
- `records`

Expected history tables:

- `classes_history`
- `records_history`

These tables should keep the same conceptual responsibilities as in PostgreSQL:

- identity tables hold stable object identity
- history tables hold append-only versions
- current state is determined from the latest visible history row

## Append-Only Strategy

Append-only behavior should remain a core rule in SQLite.

Where practical, SQLite should enforce this in the database itself:

- primary keys
- foreign keys
- unique indexes
- `not null` constraints
- triggers that reject forbidden updates

If SQLite cannot enforce a rule cleanly at the database layer, the Ruby engine must enforce it before writing.

The design preference is:

1. enforce in SQLite schema when it is straightforward and reliable
2. otherwise enforce in the SQLite engine layer
3. do not silently weaken invariants just because SQLite is simpler than PostgreSQL

## Class Model

SQLite should preserve the same class model:

- `classes` stores stable class identity
- `classes_history` stores versioned class definitions
- `inherits` should still point to a specific class-history row, not merely to a class identity row

This keeps inheritance version-aware and consistent with the current product model.

The following class rules should still apply:

- a class version may inherit from another class version
- self-inheritance must be rejected
- circular inheritance must be rejected
- inheritance should reference the latest visible parent version
- inheritance should not target a deleted parent version

Some of those checks may be difficult to express purely in SQLite schema objects. In those cases the SQLite engine layer should validate them before insert.

## Record Model

SQLite should preserve the same record model:

- `records` stores stable record identity
- `records_history` stores append-only record versions
- each record version stores the record payload in `bucket`
- each record version may optionally store `class_pk`
- each record version stores `custom_classes`

The same logical rules should still apply:

- a record may be untyped
- if typed, its class must resolve to a visible active class
- record references in `bucket` should still be validated
- file references should still be validated if file support exists in SQLite

## Current-State Resolution

The SQLite engine should derive current visible rows from history tables in the same way PostgreSQL does conceptually:

- choose the latest history row for each identity
- optionally apply a timestamp cutoff
- include only rows whose latest visible version is active

SQLite may implement this with views, queries, or a mixture of database objects and Ruby code.

The exact mechanism is less important than preserving the same behavior.

## Timestamp Context

The PostgreSQL engine uses connection-local settings such as:

- `api.current_tenant_pk`
- `api.current_timestamp`

SQLite should not attempt to mirror that mechanism literally.

For SQLite:

- tenant context should not exist
- timestamp context may still exist, but it should likely be engine-managed rather than connection-setting-based

That means the SQLite Ruby engine may need to hold a cutoff timestamp value and inject it into queries or validation logic when reading or appending history rows.

## Open Modes and Locks

The SQLite engine should open with an explicit mode string rather than assuming one default behavior.

The intended meanings are:

- `rw` means read-write mode
- `r` means read-only mode
- `w` is reserved for future write-only support

For now, `w` should not be implemented.

The main purpose of the mode is lock selection:

- `rw` should acquire an exclusive database lock
- `r` should acquire a shared database lock

This is not primarily an abstract permission system. It is an opening and locking model for the SQLite database file.

The SQLite engine constructor should therefore reject invalid or empty mode strings.

At minimum:

- a mode with neither read nor write intent should raise `ArgumentError`
- `w` should raise until write-only behavior is intentionally designed and implemented

This also means lock behavior should not be hardcoded unconditionally in the low-level connection object.

Instead:

- the chosen engine open mode should determine the requested SQLite locking behavior
- the Ruby engine should be the place where open intent is interpreted

## API Surface

DBMS-specific engines should only need to support `q0` and the lower-level engine hooks that `q0` execution requires.

Methods such as `records()` and `by_class()` are already defined in `Mikobase::Engine` in terms of Q0, so SQLite does not need engine-specific implementations of those methods.

But it does not need to expose the same SQL-facing interface as PostgreSQL.

In PostgreSQL, much of the public interaction is intentionally routed through the `api` schema.

SQLite does not need an `api` schema and should not imitate that structure mechanically. Instead:

- the Ruby engine may be the primary public interface
- SQLite views may still be used for convenience if helpful
- SQL layout should be shaped around correctness and clarity, not PostgreSQL feature parity

## Constraint Placement

The SQLite engine should keep as much logic as possible in the database itself, but must be pragmatic.

Good candidates for SQLite-side enforcement:

- primary keys
- foreign keys
- unique indexes
- append-only update rejection triggers
- simple existence checks

Likely candidates for Ruby-engine enforcement when needed:

- latest-parent-version validation
- circular inheritance checks
- validation that a class delete is blocked while active records still reference it
- recursive reference validation inside `bucket`
- any rule that would require PostgreSQL-specific recursive trigger logic or connection-local state

## Class Deletion

The SQLite engine should preserve the current product rule that a class cannot be deleted while active records still reference it.

If SQLite can enforce that with triggers or carefully structured queries, it should.

If not, the Ruby engine must check for active referencing records before appending the deleted class-history row.

## File and Record References

The SQLite engine should preserve the meaning of:

- `mikobase.com/reference`
- `mikobase.com/file`

That means SQLite must still validate:

- record references point to an active current record in the same database
- file references point to an existing file row if the SQLite engine supports file storage

As in other areas, enforcement may be split between SQLite schema logic and Ruby engine logic.

## File Storage

SQLite file storage should move away from a single `files.content` blob.

The preferred SQLite design is:

- `files` is an identity and metadata table
- `file_chunks` stores the binary content in ordered chunks
- file reconstruction is done by reading `file_chunks` in chunk order for one `file_pk`

This is a better fit for SQLite because it avoids treating one large file as one giant row value.

The intended responsibility split is:

- `files` stores stable file identity
- `files` stores metadata such as `size` and `sha256`
- `file_chunks` stores the actual bytes

Conceptually, the schema should look like:

```sql
create table files (
	file_pk text primary key,
	created_at text not null default current_timestamp,
	size integer not null,
	sha256 text not null unique
);

create table file_chunks (
	file_chunk_pk integer primary key,
	file_pk text not null references files(file_pk) on delete cascade,
	chunk_index integer not null,
	content blob not null,
	last integer not null default 0 check(last in (0, 1)),
	unique(file_pk, chunk_index)
);

create unique index file_chunks_one_last_per_file
	on file_chunks(file_pk)
	where last = 1;
```

The important design points are:

- `sha256` should remain unique so `ensure_file` can continue deduplicating by content
- `chunk_index` is required so chunks can be reassembled deterministically
- `last` is useful as a consistency marker, but it is not a substitute for ordering
- `file_pk` foreign keys must reference `files(file_pk)` explicitly

The SQLite engine should treat chunk rows as append-only content rows.

That means SQLite should reject updates to:

- `files`
- `file_chunks`

Deletes should be handled conservatively:

- direct file deletion should still be blocked while active records reference the file
- if file deletion is supported at all, it should delete the identity row and its chunks together

## File Chunk Semantics

The SQLite engine should make the chunk model explicit.

Expected chunk rules:

- `chunk_index` starts at `0`
- chunk indexes are contiguous for a given file
- exactly one chunk should be marked `last = 1` for any non-empty file
- no chunk after the `last` chunk is valid

Some of those rules are awkward to express purely in SQLite constraints.

The design preference is:

- keep simple integrity in SQLite schema
- enforce sequence completeness and terminal-chunk correctness in Ruby when needed

The Ruby write path should therefore be responsible for:

- splitting the source file into fixed-size chunks
- inserting `files` first
- inserting `file_chunks` in order
- marking only the final chunk as `last = 1`
- validating that the stored chunk stream matches `size` and `sha256` expectations

## Empty Files

The SQLite design should allow empty files.

The preferred representation is:

- a row exists in `files`
- no rows exist in `file_chunks`

This is simpler than inventing a synthetic empty terminal chunk.

Under that rule:

- `size = 0`
- `sha256` is the hash of empty content
- `last` only applies when at least one chunk exists

## Security and Resource Direction

This chunked design is partly about correctness and partly about operational safety.

The goal is not merely to change table shape. The goal is to avoid the current strategy where one file is assembled into one large blob value during storage.

For SQLite, the intended direction is:

- chunk writes incrementally
- chunk reads incrementally
- avoid a schema design that encourages one giant `blob` column per file row

That does not by itself guarantee low-memory behavior, but it creates a design that can support streaming or bounded-memory implementation later.

## Q0

Q0 should remain engine-agnostic at the language level.

The SQLite implementation should support the same Q0 features as the PostgreSQL implementation where practical, including:

- root `select`
- `class`
- `path`
- `where`
- `then`
- `any`
- placeholder objects such as `{"anything": true}`, `{"truthy": true}`, and `{"array": true}`
- operator objects such as `{"equals": "...", "case-sensitive": false}`

If some parts are awkward to express efficiently in raw SQLite, they may be executed partly in Ruby after fetching candidate rows.

The design priority is correctness first, then efficiency.

## Engine Boundary

The SQLite engine should not leak SQLite-specific shortcuts into engine-agnostic code.

Engine-agnostic layers should continue to think in terms of:

- current records
- current classes
- append-only history
- inheritance-aware class resolution
- Q0 result rows

SQLite-specific compromises should be contained inside the SQLite engine implementation.

## Proposed Development Order

The SQLite engine should likely be built in stages:

1. schema initialization
2. append-only identity and history tables
3. current-record and current-class resolution
4. class inheritance validation
5. record insert/delete behavior
6. Q0 support
7. reference validation
8. parity testing against existing PostgreSQL behavior where applicable

## Main Design Principle

The SQLite engine should be simpler than PostgreSQL in tenancy and deployment, but not weaker in data model semantics.

The right approach is:

- remove tenant machinery that no longer makes sense
- keep all core Mikobase versioning rules
- enforce those rules in SQLite itself when possible
- move the remaining logic into the Ruby engine layer when necessary
