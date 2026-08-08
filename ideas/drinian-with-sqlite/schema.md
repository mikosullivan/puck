# Schema

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_schema",
	"role": "Drinian's SQLite schema. `objects` table holds row shapes discriminated by a single `primitive` column — false (full object), 'h' (HashPrimitive), 'a' (ArrayPrimitive). Scalars are a variant of `primitive = false` distinguished by `st` (scalar type). HashPrimitives serving as buckets carry `bucket_for` back-pointing at their owner; ArrayPrimitives serving as stacks carry `stack_for`. Only container primitives can be parents in `relationships`. Buckets and stacks are both lazy — Lua write layer creates them on demand. Scalars with no bucket/stack take a fast dispatch path through the built-in class for their `st` type. Every row carries a `uspace` NOT NULL boolean marking whether it's currently held in user space (provisional GC-anchor concept). GC uses two-column scratch (needs_trace / in_trace) — the drain deletes directly, and RESTRICT on relationships.child raises loudly if incoming references remain at delete time. Event registrations live in dedicated `instance_listeners` / `class_listeners` tables outside `relationships` — bookkeeping, not graph — with weak-ref lifetime via FK cascade.",
	"status": "iterating — GC drain algorithm documented, dropped del column, relationships.child RESTRICT (loud fail)"
}}
~~~

Started 2026-08-07 from Fiona's current schema. Adapting as design decisions land.

## Design summary

Every Drinian row falls into one of these shapes, discriminated by `primitive`, `st`, `bucket_for`, and `stack_for`. Several orthogonal fields sit alongside every row — omitted from the table for readability:

- **`uspace`** flag (0 or 1) — whether the row is currently held in user space.
- **`role_pk`** (NOT NULL FK) — every object's owner role. Set at INSERT, immutable. Roles own themselves; non-roles point at their owning role.
- **`role_parent`** (nullable FK) — set on role objects; points at the parent role in the tree. Null on non-role objects and on the root role (engine).
- **`source_pk` + `line`** (nullable pair) — the value's birth line in source. `source_pk` FKs a row in the `sources` registry. Both fields together or both null; immutable after INSERT (birth line doesn't change when the value moves).

| Row shape | primitive | st | sv | bucket_for | stack_for |
|-----------|-----------|-----|-----|------------|-----------|
| HashPrimitive (standalone / root / internal) | `'h'` | null | null | null | null |
| HashPrimitive serving as a bucket | `'h'` | null | null | set | null |
| ArrayPrimitive (standalone / internal) | `'a'` | null | null | null | null |
| ArrayPrimitive serving as a stack | `'a'` | null | null | null | set |
| Plain full object (Hash, Array, MyClass, …) | `false` | null | null | null | null |
| StringPrimitive | `false` | `'s'` | text | null | null |
| NumberPrimitive | `false` | `'n'` | integer/real | null | null |
| BooleanPrimitive | `false` | `'b'` | 0/1 | null | null |
| NullPrimitive | `false` | `'u'` | null | null | null |

Rules baked into the schema:

- `primitive` is NOT NULL and has no default — every insert names the kind at creation time.
- Only container primitives (`primitive in ('h', 'a')`) can be parents in `relationships` — full objects and scalars can't have references directly; full objects reach their contents through their bucket / stack.
- **Role-shape alignment.** A row with `bucket_for` set must be a HashPrimitive (`primitive = 'h'`); a row with `stack_for` set must be an ArrayPrimitive (`primitive = 'a'`). An array can't be a bucket; a hash can't be a stack.
- **At most one role per row.** At most one of `bucket_for` / `stack_for` may be set on any given row. A row can't be both a bucket and a stack — enforced by `check (bucket_for is null or stack_for is null)`.
- **At most one bucket and one stack per owner.** `bucket_for` and `stack_for` are each `UNIQUE` — no two rows can be a bucket for the same owner (or a stack for the same owner). Rows where these columns are null don't collide because SQLite doesn't consider nulls in UNIQUE constraints.
- **Buckets and stacks are both lazy.** A plain full object gets neither at creation time. The Lua write layer creates them on demand — `ensure_bucket(obj_pk)` on the first field write, `ensure_stack(obj_pk)` on the first class-extension or shadow. Objects that live briefly and never need either save the row + constraint cost entirely. (Class dispatch for stack-less full objects is a design question we're deferring; probably a `class_pk` column when we get to it.)
- **Scalar fast path.** A scalar row (`primitive = false, st IS NOT NULL`) that has no bucket and no stack — no other row references it via `bucket_for` or `stack_for` — dispatches through the built-in class for its `st` type (StringPrimitive for `'s'`, NumberPrimitive for `'n'`, BooleanPrimitive for `'b'`, NullPrimitive for `'u'`). Scalars never auto-provision anything, so the fast path is the common case. Scalars that get extended (shadow methods, nested markers) fall back to full dispatch.
- Deleting a full object cascades via FK to delete its bucket (if present) + stack (`bucket_for` and `stack_for` FKs have ON DELETE CASCADE). No cleanup trigger.
- **Bucket / stack denormalization.** Owner rows also carry `bucket_pk` and `stack_pk` columns mirroring the collection-side `bucket_for` / `stack_for`. Redundant data — populated set-once by `objects_denormalize_bucket` / `_stack` triggers when the collection is inserted, then locked. Lets queries and dispatch skip a join.
- **`objects` is effectively immutable.** Identity columns (`object_pk`, `primitive`, `st`, `sv`, `bucket_for`, `stack_for`) can never change. Denormalization columns (`bucket_pk`, `stack_pk`) are write-once. The only freely-mutable state is `uspace` and GC scratch (`needs_trace`, `in_trace`). Enforced by `objects_no_update`.
- Scalars are single-row leaves — a StringPrimitive is one row with `primitive = false`, `st = 's'`, `sv = <text>`.
- **Event listeners are bookkeeping, not graph.** Two dedicated tables — `instance_listeners` (for `.listen_to` registrations) and `class_listeners` (for `.listen_to_class`) — hold registration tuples. They live outside `relationships` so GC does NOT count them as reachability edges. Weak-ref lifetime falls out of `ON DELETE CASCADE`: when the broadcaster, class, or listener object is deleted, the registration cascade-deletes with it. Registration order is `reg_pk` (autoincrement). Composite `UNIQUE` on the tuple gives idempotent `.listen_to`.
- **Uspace flag.** Every row carries a `uspace` column, strict NOT NULL boolean (0 or 1), marking whether the object is currently held in user space (a variable, a collection element, or otherwise anchored). Uspace rows are the GC's anchor set — the trace terminates as soon as any uspace row appears in `in_trace`, and the mark triggers skip uspace rows entirely (a known-alive row is never a garbage candidate). Provisional shape — the final uspace mechanism may look different, but this gives a place to reason about GC anchors.
- **Object ownership (`role_pk`).** Every object carries a NOT NULL `role_pk` FK naming the role that owns it — set at INSERT, immutable, cascade-deletes with the owning role. Roles own themselves (engine's role_pk = 1, user's role_pk = 2). Ownership is the role of the code that conceptually created the object, not necessarily the runtime frame's role; see requirements/drinian/objects.
- **Source-location tagging (`sources` + `source_pk` / `line`).** A dedicated `sources` table registers each file / URL that produces values or frames. Object rows and frame rows carry a `(source_pk, line)` pair back-pointing to their origin — the value's birth line, the frame's current line. Both null together when the source is unknown (engine internals, hand-written CaspM, source-less metaprogramming). On objects the pair is immutable; on frames the `line` advances as the frame executes.
- **AST storage on callables (`ast` column).** Function / method / closure objects carry their CaspM body in an `ast` blob column on `objects`, encoded as SQLite JSONB. The engine reads the current value on each call, thaws it to Lua-native form, and attaches the parsed tree to the frame executing it — no long-lived cache, no invalidation dance. Hot-patching an `ast` takes effect on the next call.
- **Role tree (`role_parent`).** Roles form a tree rooted at engine (seeded at object_pk = 1). Engine's only child is user (seeded at object_pk = 2). All other roles descend from user. Cycles are impossible by construction — `role_parent` is immutable and FK-enforced, so a back edge can only be set at INSERT when the descendant doesn't yet exist. Seeded engine and user cannot be deleted; cascade delete on `role_parent` means any legitimately-deleted role takes its whole subtree with it.
- **Call stack lives in dedicated tables.** Runtime frames don't fit the objects shape (no class dispatch, no bucket, no stack-of-platters), so they live in purpose-built tables: `call_stacks` (plural), `frames`, `locals`, plus sidecars `frame_delegations` (role permission grants from `delegate_to` blocks), `frame_amber` (per-frame `%amber` namespace layer — init / remove / grant entries; `amber_cleared` on the frame is the full-surface walk-stop), and `captured_frames` (snapshot-by-reference of the frames below an in-flight exception).
- **Frame-anchored objects join uspace on attach; engine releases them.** Objects referenced from a frame's sidecar tables (currently `frame_amber` amber-namespace hashes) aren't reachable through the `relationships` graph the GC trace walks — they'd look orphan without help. A trigger marks the referenced hash `uspace = 1` on INSERT into `frame_amber`, keeping it out of GC's candidate set. The engine's Lua layer explicitly clears `uspace = 0` when the amber lifecycle ends (typically just before dropping the init'ing frame), after which the hash rejoins normal GC. Split trigger/engine responsibility on purpose: attachment is a schema fact (set at write time), release is engine policy (knows when the amber is really done). The same pattern will apply to other frame-anchor tables (`locals`, `frame_delegations`) when we close those anchoring gaps. The plural `call_stacks` accommodates future features — coroutines, fork, multiple paused processes coexisting in one file, and **multiple concurrent instances of the same machine running over one shared object graph** — where each execution context is its own `call_stacks` row. Concurrency semantics for the shared-graph case are language-level work; the storage substrate is ready. For now, Caspian runs exclusively in the seeded main stack at `cs_pk = 1`.
- **Rich frame kinds.** `frames.kind` covers the full set of requirements' frame `action` values: `top_level`, `method_call`, `function_call`, `function_invocation`, `block`, `if_block`, `delegate_to`, `exception`, `on_close`, `pause`. Fields on `frames` are conditionally meaningful per kind (`method_pk` / `method_class_pk` on call frames, `iterator_position` / `iterator_of` on iteration frames, `exception_class_pk` / `exception_message` on exception frames, `pause_reason` / `revival_payload_pk` on pause frames). `lexical_parent_pk` on any frame links its scope's defining frame — variable lookup walks this chain, not the physical call stack.

## Schema

~~~sql
-- Drinian database design. One `objects` table holds row shapes
-- discriminated by the `primitive` column:
--   'h'   → HashPrimitive (hash-shaped primitive container)
--   'a'   → ArrayPrimitive (array-shaped primitive container)
--   false → not a primitive collection. Either a plain full object
--           (with an auto-provisioned bucket + stack) or a scalar
--           primitive (with a scalar type in `st` and value in `sv`).
--
-- A HashPrimitive serving as a bucket carries `bucket_for` pointing
-- at its owner; an ArrayPrimitive serving as a stack carries
-- `stack_for`. Standard SQL "child references parent" idiom — ON
-- DELETE CASCADE from the owner cleans up bucket + stack via FK; no
-- cleanup trigger needed.
--
-- Only container primitives can be parents in the `relationships`
-- table. Full objects hold their contents in their bucket + stack;
-- scalars have no contents at all.

pragma foreign_keys = on;

-- Recursive triggers are ON. SQLite permits a manual trigger's
-- INSERT / UPDATE / DELETE to fire further manual triggers, and
-- turning OFF just to enforce non-recursion turned out to be more
-- work than the discipline it saved. We accept the setting but
-- treat non-recursion as a design principle: if propagation needs
-- to happen across rows or tables, do it explicitly in Lua rather
-- than lean on trigger chains. FK cascades are a separate mechanism
-- and their after-triggers fire regardless — mark triggers on
-- relationships continue to fire during bulk DELETEs.
pragma recursive_triggers = on;

-- ------------------------------------------------------------
-- Drinian marker table
-- ------------------------------------------------------------
-- The presence of this table signals "this database can be used as
-- Drinian." A generic SQLite file has no `drinian` table; a Drinian
-- database always does. Any Drinian tool can check for this table's
-- existence before treating the file as a Drinian store, and any
-- database that carries it is committing to the Drinian schema.
--
-- Append-only: once a row is inserted, it cannot be updated or
-- deleted. Every entry is a permanent birth-record. If we ever need
-- something mutable, it goes in a different table.

create table drinian (
	key text primary key,
	value text
);

create trigger drinian_no_update
before update on drinian
begin
	select raise(abort, 'drinian_append_only: drinian is append-only; no updates allowed');
end;

create trigger drinian_no_delete
before delete on drinian
begin
	select raise(abort, 'drinian_append_only: drinian is append-only; no deletes allowed');
end;

insert into drinian (key, value) values ('schema', '6.0');

-- ------------------------------------------------------------
-- Sources: file / URL registry for source-location tagging.
-- ------------------------------------------------------------
-- Per requirements/drinian § Source-location tagging: every value
-- and every frame can carry a back-pointer to where it came from
-- in source. The registry sits here, one row per distinct source
-- (file path or URL). Value rows and frame rows carry a
-- source_pk + line pair pointing back.
--
-- Rows are add-or-remove-only — sources register on first
-- encounter and never mutate. `kind` extends when new source
-- shapes land (git URL, blob, etc.).

create table sources (
	source_pk integer primary key autoincrement,
	kind text not null check (kind in ('file', 'url')),
	path text not null
);

create trigger sources_no_update
before update on sources
begin
	select raise(abort, 'sources_no_update: sources rows are immutable; register a new row rather than mutating an existing one');
end;

-- ------------------------------------------------------------
-- Process: runtime state flags.
-- ------------------------------------------------------------
-- Simple key/value pairs of strings marking transient runtime
-- state. Rows come and go as the engine transitions between
-- phases. For flag-style entries the mere PRESENCE of the key is
-- enough — a row keyed 'in_gc' (value can be null or anything)
-- marks that a GC sweep is in progress. Other entries might
-- carry meaningful values. Triggers and UDFs subquery this table
-- to discover what phase the runtime is in.

create table process (
	key text primary key,
	value text
);

-- ------------------------------------------------------------
-- Objects: primitive containers, plain full objects, scalars.
-- ------------------------------------------------------------

create table objects (
	object_pk integer primary key autoincrement,

	-- Row-kind discriminator. NOT NULL, no default: Drinian's write
	-- code names the row kind at INSERT time. SQLite treats `false`
	-- as an alias for 0.
	--   false → full object (not a primitive collection)
	--   'h'   → HashPrimitive
	--   'a'   → ArrayPrimitive
	primitive not null check (primitive in (false, 'h', 'a')),

	-- Scalar type. Only meaningful when primitive = false. When set,
	-- this row is a scalar primitive; when null on a primitive =
	-- false row, this row is a plain full object with a bucket +
	-- stack.
	--   's' string, 'n' number, 'b' boolean, 'u' null
	st text check (st in ('s', 'n', 'b', 'u')),
	check (primitive = false or st is null),

	-- Scalar value. Meaningful only when `st` is set. Per-st shape
	-- checks use `is` (not `in`) so null cleanly evaluates to false
	-- — the `in` form would give NULL which SQLite's CHECK accepts
	-- as passing, silently letting null booleans through.
	sv,
	check (st is null or st != 'b' or sv is 0 or sv is 1),
	check (st is null or st != 'u' or sv is null),
	check (st is null or st != 'n' or typeof(sv) in ('integer', 'real')),
	check (st is null or st != 's' or typeof(sv) = 'text'),
	check (st is not null or sv is null),

	-- Role back-references. If bucket_for is set, this row is the
	-- bucket of the referenced full object; it must be a
	-- HashPrimitive. If stack_for is set, this row is the stack of
	-- the referenced full object; it must be an ArrayPrimitive. At
	-- most one may be set (a row can't be both a bucket and a
	-- stack). Full objects, scalars, and standalone container
	-- primitives (root, internal storage) leave both null.
	--
	-- FKs use ON DELETE CASCADE: deleting the owner deletes its
	-- bucket and stack in one shot via FK, no trigger required.
	--
	-- UNIQUE on each column: each owner has at most one bucket and
	-- one stack. SQLite doesn't consider nulls in UNIQUE
	-- constraints, so many rows with these columns null don't
	-- collide.
	bucket_for integer unique references objects(object_pk) on delete cascade,
	stack_for  integer unique references objects(object_pk) on delete cascade,
	check (bucket_for is null or primitive = 'h'),
	check (stack_for  is null or primitive = 'a'),
	check (bucket_for is null or stack_for is null),

	-- Denormalized owner-side back-links to the bucket and stack.
	-- Redundant with the bucket_for / stack_for columns on the
	-- collection rows (looking up a bucket via bucket_for is already
	-- indexed), but having the link directly on the owner row lets
	-- queries and dispatch paths skip a join. Nullable — plain full
	-- objects that don't yet have their bucket / stack lazily
	-- created leave these null.
	--
	-- Set-once by the objects_denormalize_bucket / _stack triggers
	-- when the corresponding collection is inserted; immutable
	-- afterward via objects_no_update. No FK — the trigger keeps
	-- the denormalization in sync, and adding FK cascade in the
	-- reverse direction of bucket_for would fight the cascade we
	-- already have.
	--
	-- CHECK: only plain full objects (primitive = false AND st null)
	-- can carry these columns.
	-- UNIQUE: no two owners share a bucket or stack — redundant with
	-- the bucket_for / stack_for UNIQUE, but a good safety net for
	-- the denormalization.
	bucket_pk integer unique,
	stack_pk  integer unique,
	check (bucket_pk is null or (primitive = false and st is null)),
	check (stack_pk  is null or (primitive = false and st is null)),

	-- Uspace flag. 1 → this object is in "uspace" (probably a
	-- variable or a collection element — held in user space). 0 →
	-- it isn't. Strict boolean: NOT NULL with no default, so
	-- Drinian's write code names the value at every INSERT.
	-- Provisional shape — the final design may look different, but
	-- this gives us a place to reason about the uspace anchor
	-- concept for GC.
	uspace integer not null check (uspace in (0, 1)),

	-- Owner role. Every object has a role that owns it — set at
	-- INSERT and immutable. Points at the role object that
	-- conceptually created this object (the expression-evaluator's
	-- role, not necessarily the runtime frame's role). See
	-- requirements/drinian/objects for the ownership semantics.
	-- Roles own themselves — engine's role_pk = 1, user's role_pk
	-- = 2. Non-role objects point at whichever role owns them. FK
	-- cascade: deleting a role sweeps its owned objects along with
	-- it.
	role_pk integer not null references objects(object_pk) on delete cascade,

	-- Role tree back-pointer. Null on non-role objects and on the
	-- root role (engine, pk=1). Set on every other role, pointing
	-- at that role's parent role in the tree.
	--
	-- The tree is enforced simply: role_parent is immutable (see
	-- objects_no_update), and ON DELETE CASCADE means deleting a
	-- role deletes its whole subtree. Cycles are impossible by
	-- construction — a back edge would require a role_parent
	-- pointing at a descendant, but role_parent is set at INSERT
	-- and the descendant doesn't exist yet at that moment (FK
	-- would fail). Once set, the parent is locked, so no legal
	-- write can close a cycle.
	--
	-- CHECK enforces the structural rule: engine (pk=1) has one
	-- child, user (pk=2); all other roles descend from user. Legal
	-- role_parent values are:
	--   null                — non-role objects and the engine root
	--   > 1                 — user (pk=2) or any of its descendants
	--   1 for object_pk = 2 — user's grandfathered seed row
	role_parent integer references objects(object_pk) on delete cascade,
	check (role_parent is null or role_parent > 1 or object_pk = 2),

	-- Source-location tagging. Per requirements/drinian §
	-- Source-location tagging: a value's src is its birth line.
	-- source_pk names the file / URL in the sources table; line is
	-- the 1-based line number. Both nullable and omitted together
	-- for values with no source line — engine internals,
	-- hand-written CaspM fixtures, truly source-less
	-- metaprogramming output. Both immutable after INSERT: a
	-- value's birth line doesn't change when the value moves
	-- through assignments or calls.
	source_pk integer references sources(source_pk) on delete restrict,
	line integer check (line is null or line > 0),
	check ((source_pk is null and line is null) or (source_pk is not null and line is not null)),

	-- AST body (function / method / closure). CaspM tree serialized
	-- as SQLite JSONB — the binary JSON format introduced in SQLite
	-- 3.45.0. JSON1 functions query into it transparently
	-- (json_extract, etc.) without full parse. Null on objects that
	-- aren't callables. Mutable — the engine reads the current
	-- value on each call and thaws it into Lua-native form
	-- attached to the frame, so an update to `ast` takes effect on
	-- the next call (hot-patch / metaprogramming friendly, no
	-- cache-invalidation dance).
	ast blob,

	-- Transient GC scratch. Both are 1 or null — CHECK doesn't
	-- fire on null, so no `X is null or` guard is needed.
	--
	-- needs_trace: 1 means this row is a candidate seed the drain
	-- should trace from. in_trace: positive integer giving the order
	-- the drain's callback loop fires against this row (see
	-- specs/on-gc.md).
	--
	-- No `del` column — the drain deletes objects directly instead
	-- of a mark-then-bulk-delete pattern. If an object still has
	-- incoming references at delete time (e.g., an on_close created
	-- a new one), the RESTRICT FK on relationships.child raises,
	-- and the exception propagates like any other. Loud beats
	-- silent.
	needs_trace integer check (needs_trace = 1),
	in_trace    integer check (in_trace > 0)
);

create index objects_needs_trace on objects(needs_trace) where needs_trace = 1;
create index objects_in_trace    on objects(in_trace)    where in_trace is not null;
create index objects_uspace      on objects(uspace)      where uspace = 1;

-- Immutability rules:
--   Fully immutable from INSERT: object_pk, primitive, st, sv,
--   bucket_for, stack_for, role_pk, role_parent, source_pk, line.
--   Write-once (null → value, then locked): bucket_pk, stack_pk.
--   Freely mutable: uspace, and GC scratch (needs_trace, in_trace).
create trigger objects_no_update
before update on objects
begin
	select case
		when new.object_pk is not old.object_pk
			then raise(abort, 'objects_pk_immutable: objects.object_pk is immutable')
		when new.primitive is not old.primitive
			then raise(abort, 'objects_primitive_immutable: objects.primitive is immutable')
		when new.st is not old.st
			then raise(abort, 'objects_st_immutable: objects.st is immutable')
		when new.sv is not old.sv
			then raise(abort, 'objects_sv_immutable: objects.sv is immutable')
		when new.bucket_for is not old.bucket_for
			then raise(abort, 'objects_bucket_for_immutable: objects.bucket_for is immutable')
		when new.stack_for is not old.stack_for
			then raise(abort, 'objects_stack_for_immutable: objects.stack_for is immutable')
		when new.role_pk is not old.role_pk
			then raise(abort, 'objects_role_pk_immutable: objects.role_pk is immutable')
		when new.role_parent is not old.role_parent
			then raise(abort, 'objects_role_parent_immutable: objects.role_parent is immutable')
		when new.source_pk is not old.source_pk
			then raise(abort, 'objects_source_pk_immutable: objects.source_pk is immutable')
		when new.line is not old.line
			then raise(abort, 'objects_line_immutable: objects.line is immutable')
		when old.bucket_pk is not null and new.bucket_pk is not old.bucket_pk
			then raise(abort, 'objects_bucket_pk_write_once: objects.bucket_pk is write-once')
		when old.stack_pk is not null and new.stack_pk is not old.stack_pk
			then raise(abort, 'objects_stack_pk_write_once: objects.stack_pk is write-once')
	end;
end;

-- Engine (object_pk = 1) and user (object_pk = 2) are the root
-- roles and cannot be deleted. Every Drinian database starts with
-- both seeded, and nothing above the language layer can remove
-- either. Non-root uspace anchors are freely deletable (that's how
-- an object leaves user space in the first place). Note that
-- role_parent uses ON DELETE CASCADE, so protecting engine and user
-- from direct deletion also protects the whole role tree from
-- accidental sweep.
create trigger objects_no_delete_root_roles
before delete on objects
when old.object_pk in (1, 2)
begin
	select raise(abort, 'root_role_cannot_be_deleted: engine (pk=1) and user (pk=2) cannot be deleted');
end;

-- ============================================================
-- UDF hook: on_delete — the object-deletion callback surface.
-- ============================================================
-- Fires on non-GC deletes (explicit user code, FK cascade during
-- normal operation, direct DELETE). Invokes the
-- drinian_udf_on_delete Lua UDF, which handles all Caspian-level
-- cleanup:
--
--   * Walks the object's stack looking for an on_close method and
--     invokes it if defined (see requirements/drinian/objects for
--     the on_close spec).
--   * Releases any native handles the object owns.
--   * Fires internal engine events — "object deleted",
--     listener-registration removal, cache invalidations, etc.
--
-- Suppressed during GC. The WHEN clause skips this trigger
-- whenever the process table has an 'in_gc' key — GC runs
-- on_close in its own callback phase before the bulk DELETE, and
-- firing the UDF again during the delete would double-invoke
-- handlers. Non-GC deletes still go through the UDF because they
-- don't get GC's callback-phase treatment.
--
-- Exceptions from on_close are treated as normal Caspian
-- exceptions — no swallow-and-log. If a handler raises, the UDF
-- raises, the trigger raises, the DELETE aborts, and the
-- exception propagates to whatever transaction wraps the
-- operation. The program either catches it (via
-- transaction(catch: true) or explicit try/catch) or the process
-- ends. Loud beats silent.
--
-- The Lua engine registers drinian_udf_on_delete before opening
-- the database (per the Lua-owner contract in
-- ideas/drinian-with-sqlite/), so by the time any DELETE fires
-- this trigger, the UDF exists. Running this schema against a
-- SQLite that hasn't registered the UDF will fail on first
-- non-GC object delete.
create trigger objects_on_delete_hook
before delete on objects
when not exists (select 1 from process where key = 'in_gc')
begin
	select drinian_udf_on_delete(old.object_pk);
end;

-- Uspace rows (uspace = 1) are always alive by definition — the
-- drain treats them as anchors. Marking one as needs_trace is a
-- category error (we're claiming a known-alive row might be
-- garbage) and would make the drain spin. Belt-and-suspenders check
-- catching any accidental mark; the mark triggers themselves filter
-- uspace rows out of their UPDATE targets.
create trigger objects_uspace_no_needs_trace
before update on objects
when old.uspace = 1 and new.needs_trace
begin
	select raise(abort, 'uspace_cannot_be_marked: uspace rows cannot have needs_trace set');
end;

-- Role tree structural rule is enforced by the CHECK on
-- role_parent (see objects table). No trigger needed here — the
-- CHECK catches every attempt to make a role a direct child of
-- engine (only user's grandfathered seed row is exempt). User and
-- everything under user (pk > 1) are legal role_parent targets.

-- role_pk must reference an actual role — either engine (pk = 1)
-- or any object with role_parent set (which the role_parent CHECK
-- guarantees puts it in user's subtree). Self-reference is allowed
-- when the row being inserted itself qualifies as a role: engine
-- (pk = 1 and role_parent null) or any new role (role_parent set).
create trigger objects_role_pk_must_reference_role
before insert on objects
when
	-- Case 1: role_pk points at another row that is not a role
	(new.role_pk != new.object_pk
	 and not exists (
		select 1 from objects
		where object_pk = new.role_pk
		  and (object_pk = 1 or role_parent is not null)
	 ))
	or
	-- Case 2: self-reference but the new row is not a role itself
	-- (engine's self-ref is exempt; every other self-ref requires
	-- role_parent to be set)
	(new.role_pk = new.object_pk
	 and new.object_pk != 1
	 and new.role_parent is null)
begin
	select raise(abort, 'role_pk_must_reference_role: objects.role_pk must reference a role (engine, user, or a descendant of user)');
end;

-- Seed the two root roles. Engine at object_pk = 1 with
-- role_parent null (it's the top of the tree). User at object_pk =
-- 2 with role_parent = 1. Roles own themselves — engine's role_pk
-- = 1, user's role_pk = 2. Both are HashPrimitives (containers)
-- and uspace = 1 (permanent anchors). Both explicitly name their
-- object_pk so the self-referencing role_pk resolves against the
-- row being inserted (SQLite deferred-FK check at end of
-- statement).
insert into objects (object_pk, primitive, uspace, role_pk) values (1, 'h', 1, 1);
insert into objects (object_pk, primitive, uspace, role_pk, role_parent) values (2, 'h', 1, 2, 1);

-- ------------------------------------------------------------
-- Bucket + stack: lazily created by the Lua write layer.
-- ------------------------------------------------------------
-- Neither bucket nor stack is auto-provisioned by trigger. The Lua
-- write API creates them on demand via ensure_bucket(obj_pk) and
-- ensure_stack(obj_pk) — the first field write creates the bucket,
-- the first class-extension or shadow creates the stack. Objects
-- that live briefly and touch neither save the row + constraint
-- cost entirely.

-- ------------------------------------------------------------
-- Denormalization triggers — keep owner-side bucket_pk / stack_pk
-- in sync with collection-side bucket_for / stack_for.
-- ------------------------------------------------------------

-- When a bucket is inserted (HashPrimitive with bucket_for set),
-- write the new bucket's object_pk into the owner's bucket_pk. The
-- owner's bucket_pk was null; this null→value transition is
-- allowed by objects_no_update, and after it lands the field is
-- locked.
create trigger objects_denormalize_bucket
after insert on objects
when new.bucket_for is not null
begin
	update objects set bucket_pk = new.object_pk where object_pk = new.bucket_for;
end;

-- Same for stack.
create trigger objects_denormalize_stack
after insert on objects
when new.stack_for is not null
begin
	update objects set stack_pk = new.object_pk where object_pk = new.stack_for;
end;

-- ------------------------------------------------------------
-- Relationships: parent-to-child object edges.
-- ------------------------------------------------------------
-- Every row is an object-to-object edge. The parent must be a
-- container primitive ('h' or 'a') — full objects and scalars
-- cannot be parents. Enforced by trigger below.

create table relationships (
	rel_pk  integer primary key autoincrement,

	parent  integer not null references objects(object_pk) on delete cascade,
	-- child uses ON DELETE RESTRICT so deleting an object with
	-- incoming references raises rather than silently nulling those
	-- references. Loud beats silent. If the trace was accurate and
	-- an object is unreferenced, the RESTRICT check passes; if
	-- something (typically an on_close-created edge) added a new
	-- incoming reference between mark and sweep, the delete raises
	-- and the exception propagates to whatever transaction wraps
	-- the operation.
	child   integer not null references objects(object_pk) on delete restrict,

	-- Hash-style entries store a text `key`. Array-style entries
	-- leave key null and use idx as position. Class-level dispatch
	-- (HashPrimitive vs ArrayPrimitive) interprets which is which;
	-- storage does not care.
	key     text,

	-- idx is required for every row: array-style entries use it as
	-- position, hash-style entries use it as insertion order for
	-- iteration.
	idx     integer not null check (idx >= 0),

	-- No two relationships from the same parent share a key or idx.
	-- Null-key rows (array-style) don't collide on the (parent, key)
	-- constraint because SQLite doesn't consider nulls in UNIQUE
	-- constraints.
	unique (parent, key),
	unique (parent, idx)
);

create index relationships_parent on relationships(parent);
create index relationships_child  on relationships(child);

-- Only container primitives ('h' or 'a') can be parents. Full
-- objects (primitive = false) and scalar primitives cannot appear
-- as parent — they don't have references. Full objects route
-- through their bucket / stack.
create trigger relationships_parent_must_be_primitive_container
before insert on relationships
when (select primitive from objects where object_pk = new.parent) not in ('h', 'a')
begin
	select raise(abort, 'parent_must_be_primitive_container: only HashPrimitives and ArrayPrimitives can be parents in relationships');
end;

-- Identity is (rel_pk, parent, key). Content — child, idx — is
-- mutable. Swinging child from one object to another is legal; the
-- mark trigger below catches the object-edge-severed case.
create trigger relationships_no_update
before update on relationships
begin
	select case
		when new.rel_pk is not old.rel_pk
			then raise(abort, 'relationships_pk_immutable: relationships.rel_pk is immutable')
		when new.parent is not old.parent
			then raise(abort, 'relationships_parent_immutable: relationships.parent is immutable')
		when new.key is not old.key
			then raise(abort, 'relationships_key_immutable: relationships.key is immutable')
	end;
end;

-- ------------------------------------------------------------
-- Mark triggers — the trace's worklist populator.
-- ------------------------------------------------------------

-- On DELETE of a relationship: mark the old child as needs_trace.
-- The `where ... and uspace = 0` filter on the UPDATE naturally
-- skips uspace anchors (already known alive, no need to trace) —
-- if the old child is a uspace row, the UPDATE matches zero rows
-- and is a silent no-op, no separate WHEN guard needed.
create trigger relationships_mark_needs_trace_after_delete
after delete on relationships
begin
	update objects set needs_trace = 1
		where object_pk = old.child and uspace = 0;
end;

-- On UPDATE OF child: mark the OLD child when the slot is swung to
-- a different object. Same uspace filter — the mark is a no-op if
-- the old child is a uspace anchor. `is not` handles null-vs-value
-- correctly in the WHEN clause where `<>` would silently no-op on
-- null.
create trigger relationships_mark_needs_trace_after_update_of_child
after update of child on relationships
when old.child is not new.child
begin
	update objects set needs_trace = 1
		where object_pk = old.child and uspace = 0;
end;

-- ------------------------------------------------------------
-- Instance-level event listeners.
-- ------------------------------------------------------------
-- A listener registers to be called when a specific broadcaster
-- emits a specific event. Spec: requirements/events/index.
--
-- Registrations are bookkeeping, not graph edges — they live
-- outside `relationships` so GC does NOT count them as reachability.
-- Weak-ref lifetime falls out of ON DELETE CASCADE: when either
-- party's `objects` row is deleted (typically because GC decided it
-- was unreachable), the registration cascade-deletes.

create table instance_listeners (
	reg_pk integer primary key autoincrement,

	broadcaster_pk integer not null references objects(object_pk) on delete cascade,
	listener_pk    integer not null references objects(object_pk) on delete cascade,

	-- event and method names are inline text, not references to
	-- StringPrimitive objects. Interning is an engine-layer
	-- optimization if it turns out to matter; storage keeps it
	-- simple.
	event_name  text not null,
	method_name text not null,

	-- Idempotent: `.listen_to` called twice with the same combo is
	-- one registration, not two. The Lua write API uses INSERT OR
	-- IGNORE to swallow the collision silently.
	unique (broadcaster_pk, event_name, listener_pk, method_name)
);

-- Dispatch lookup: given a broadcaster + event, find its listeners.
create index instance_listeners_broadcaster on instance_listeners(broadcaster_pk, event_name);

-- Unlisten-all lookup: given a listener, find all its rows.
create index instance_listeners_listener on instance_listeners(listener_pk);

-- Registrations are add-or-remove-only. Every field is immutable
-- after INSERT; to change a registration, DELETE and INSERT.
create trigger instance_listeners_no_update
before update on instance_listeners
begin
	select raise(abort, 'instance_listeners_no_update: instance_listeners rows are immutable; delete and re-insert to change');
end;

-- ------------------------------------------------------------
-- Class-level event listeners.
-- ------------------------------------------------------------
-- Same shape as instance_listeners but keyed by class rather than a
-- specific broadcaster instance. When any instance of the class
-- (or a descendant, via the engine's ancestor-chain walk)
-- broadcasts the event, dispatch fires this registration. Classes
-- in Caspian are ordinary objects, so `class_pk` targets `objects`
-- like any other reference. Spec:
-- requirements/events/listen-to-class.

create table class_listeners (
	reg_pk integer primary key autoincrement,

	class_pk    integer not null references objects(object_pk) on delete cascade,
	listener_pk integer not null references objects(object_pk) on delete cascade,

	event_name  text not null,
	method_name text not null,

	unique (class_pk, event_name, listener_pk, method_name)
);

create index class_listeners_class    on class_listeners(class_pk, event_name);
create index class_listeners_listener on class_listeners(listener_pk);

create trigger class_listeners_no_update
before update on class_listeners
begin
	select raise(abort, 'class_listeners_no_update: class_listeners rows are immutable; delete and re-insert to change');
end;

-- ------------------------------------------------------------
-- Call stacks, frames, and local bindings.
-- ------------------------------------------------------------
-- Runtime execution state lives in dedicated tables outside
-- `objects`. Frames aren't user-visible objects (no class dispatch,
-- no bucket, no stack-of-platters) — they're highly structured
-- engine bookkeeping and get a purpose-built shape.
--
-- `call_stacks` is plural: the schema accommodates multiple
-- execution contexts coexisting in one Drinian file. Cases the
-- plural is ready for:
--   * Coroutines — cooperative yield / resume, each their own stack.
--   * Fork children — engine-granted opt-in concurrency.
--   * Multiple paused processes each waiting for their own resume
--     signal, coexisting in one file.
--   * Multiple concurrent instances of the same machine running
--     over one shared object graph — a real concurrency model
--     within one Drinian, with semantics (row contention,
--     isolation, coordination) to work out but the storage
--     substrate ready.
--
-- For now Caspian runs exclusively in the seeded main stack at
-- cs_pk = 1; the multi-stack features will create additional rows
-- here when they land.

create table call_stacks (
	cs_pk integer primary key autoincrement
);

-- Seed the main call stack. cs_pk = 1 is the default context every
-- current Caspian program runs in.
insert into call_stacks default values;

create table frames (
	frame_pk integer primary key autoincrement,

	-- Which call stack this frame belongs to.
	cs_pk integer not null references call_stacks(cs_pk) on delete cascade,

	-- Position within cs_pk's stack. Top = MAX(idx) for that cs_pk.
	-- Non-negative; strictly monotonic per cs_pk (push assigns
	-- idx = MAX(idx)+1; pop removes the MAX row).
	idx integer not null check (idx >= 0),
	unique (cs_pk, idx),

	-- Frame kind — the `action` field from requirements/drinian.
	-- Each value maps to a different structural role a frame can
	-- play. Fields below are conditionally meaningful per kind
	-- (documented inline); the engine's write layer enforces the
	-- kind → field discipline. Schema stays loose on cross-kind
	-- CHECK constraints to keep things simple.
	--
	--   top_level          — the outermost frame of a call stack
	--   method_call        — a dispatch into a method
	--   function_call      — a Caspian-source function call
	--   function_invocation — an engine invocation of a callable
	--   block              — a do-block scope
	--   if_block           — an if-body scope
	--   delegate_to        — a %role.delegate_to block (carries delegations)
	--   exception          — an in-flight raised exception
	--   on_close           — an engine-pushed on_close handler
	--   pause              — a pause-resume marker (see pause-resume idea)
	kind text not null check (kind in (
		'top_level', 'method_call', 'function_call', 'function_invocation',
		'block', 'if_block',
		'delegate_to', 'exception', 'on_close', 'pause'
	)),

	-- Method dispatch info — meaningful on method_call,
	-- function_call, function_invocation, on_close frames.
	method_pk       integer references objects(object_pk),
	method_class_pk integer references objects(object_pk),

	-- Lexical parent link — the frame that owned the scope where
	-- THIS frame's code was DEFINED. Variable lookup walks this
	-- chain, not the physical call stack. Differs from the caller
	-- when a function is called from outside its defining scope.
	-- Null on top_level and engine-pushed frames. ON DELETE SET
	-- NULL: if the defining frame is popped and gone, the link
	-- goes stale (an engine-side concern, not a corruption).
	lexical_parent_pk integer references frames(frame_pk) on delete set null,

	-- Iterator state — meaningful on method_call frames for
	-- iteration methods (each, map, etc.). Together let the
	-- iteration resume across pause/revive.
	iterator_position integer check (iterator_position is null or iterator_position >= 0),
	iterator_of       integer check (iterator_of is null or iterator_of > 0),
	check ((iterator_position is null and iterator_of is null)
		or (iterator_position is not null and iterator_of is not null)),

	-- Exception details — meaningful on 'exception' frames only.
	-- exception_class_pk points at the exception's class object;
	-- exception_message is human-readable text carried alongside.
	exception_class_pk integer references objects(object_pk),
	exception_message  text,

	-- Pause-frame extras — meaningful on 'pause' frames. See
	-- ideas/drinian-with-sqlite/pause-resume for the semantics.
	-- pause_reason is developer context; revival_payload_pk points
	-- at the hash object populated by whoever resumes.
	pause_reason        text,
	revival_payload_pk  integer references objects(object_pk),

	-- Amber full-walk-stop marker. 1 → this frame called
	-- %amber.clear (or entered a %amber.clear do end block), so
	-- descendants see empty amber until the frame exits. null →
	-- this frame did not clear. See requirements/amber § Clear
	-- with .clear. Namespace-specific hides live in frame_amber
	-- with kind = 'remove'; this flag is the whole-surface stop.
	amber_cleared integer check (amber_cleared is null or amber_cleared = 1),

	-- Source-location for this frame — where in source the frame
	-- currently is. source_pk names the file / URL; line advances
	-- as the frame executes (the one column on `frames` where
	-- mutation is expected during a frame's lifetime).
	source_pk integer references sources(source_pk) on delete restrict,
	line      integer check (line is null or line > 0),
	check ((source_pk is null and line is null) or (source_pk is not null and line is not null))
);

create index frames_cs_pk on frames(cs_pk);

create table locals (
	-- Local variable bindings for a specific frame. Cascade-deletes
	-- with the frame — locals live and die with their frame.
	frame_pk integer not null references frames(frame_pk) on delete cascade,

	-- Variable name — inline text (no interning at storage level).
	name text not null,

	-- The object bound to this name. Plain reference: deleting a
	-- frame shouldn't delete objects the frame referenced, since
	-- they may be alive elsewhere.
	value_object_pk integer not null references objects(object_pk),

	primary key (frame_pk, name)
);

-- ------------------------------------------------------------
-- Frame delegations — role permission grants.
-- ------------------------------------------------------------
-- A %role.delegate_to(X) do ... end block pushes a frame with
-- kind = 'delegate_to' and one row here per target role receiving
-- the elevation. Permission resolution walks the call stack
-- looking for matching (target_role_pk == current_role_pk)
-- delegations. When the frame pops, the rows cascade with it —
-- the grant is gone without a separate cleanup step.
create table frame_delegations (
	frame_pk       integer not null references frames(frame_pk) on delete cascade,
	target_role_pk integer not null references objects(object_pk) on delete cascade,
	primary key (frame_pk, target_role_pk)
);

create index frame_delegations_target_role on frame_delegations(target_role_pk);

-- ------------------------------------------------------------
-- Frame amber — ambient per-frame namespaced context.
-- ------------------------------------------------------------
-- Backs the %amber surface (requirements/amber). Each row is one
-- namespace-specific entry in a frame's amber layer:
--
--   'init'   — frame init'd this namespace; namespace_hash_pk
--              points at the HashPrimitive that IS the namespace.
--              Reads in this frame and its descendants resolve to
--              that hash via the aggregate-hash walk.
--   'remove' — frame hid this namespace from its own view
--              downward (tombstone). Ancestor's namespace is
--              invisible from this frame until it exits.
--   'grant'  — frame granted this namespace across a role-boundary
--              call, with grant_read / grant_write permission
--              flags. Callee in the other role sees the namespace
--              via the grant during a single hop.
--
-- The full-surface walk-stop (%amber.clear) lives as the
-- amber_cleared column on `frames`, not in this table — .clear is
-- a frame-level state, not a namespace-specific entry.
--
-- The engine's amber resolver walks a frame's ancestors: it stops
-- at any frame with amber_cleared = 1, otherwise scans this table
-- for the requested namespace, honoring 'remove' tombstones,
-- 'init' hits, and 'grant' cross-boundary permissions.
--
-- Cascade-deletes with the frame — when the frame that added the
-- entry pops, the entry is gone. Block-form scopes (.init do end,
-- .grant do end) get their own transient frame that carries these
-- entries and pops at block exit.

create table frame_amber (
	entry_pk integer primary key autoincrement,

	frame_pk integer not null references frames(frame_pk) on delete cascade,

	-- Namespace identifier (domain-shaped per amber spec).
	namespace text not null,

	kind text not null check (kind in ('init', 'remove', 'grant')),

	-- For 'init' entries: the HashPrimitive object that backs this
	-- namespace. Null otherwise.
	namespace_hash_pk integer references objects(object_pk),

	-- For 'grant' entries: the read / write permissions the callee
	-- receives across the role boundary. Both are 0 or 1.
	grant_read  integer check (grant_read is null or grant_read in (0, 1)),
	grant_write integer check (grant_write is null or grant_write in (0, 1))
);

create index frame_amber_frame_pk  on frame_amber(frame_pk);
create index frame_amber_namespace on frame_amber(namespace);
create index frame_amber_hash_pk   on frame_amber(namespace_hash_pk) where namespace_hash_pk is not null;

-- ------------------------------------------------------------
-- Frame-anchor GC integration for amber hashes.
-- ------------------------------------------------------------
-- Amber namespace hashes are regular objects but the reference
-- from a frame lives in frame_amber, NOT in the relationships
-- table the GC trace walks. Without help, an amber hash held only
-- by frame_amber would look orphan and get swept.
--
-- Solution: mark the hash as uspace = 1 when it enters frame_amber
-- via an 'init' or 'grant' row. It stays uspace until the engine
-- (Lua layer) explicitly clears the flag when the amber lifecycle
-- ends — usually just before dropping the init'ing frame.

create trigger frame_amber_anchor_hash_on_insert
after insert on frame_amber
when new.namespace_hash_pk is not null
begin
	update objects set uspace = 1 where object_pk = new.namespace_hash_pk;
end;

-- ------------------------------------------------------------
-- Captured stack — snapshot-by-reference for exception frames.
-- ------------------------------------------------------------
-- When an exception is raised, the engine snapshots the frames
-- below it into this table by reference (not by copy). The
-- captured references let a debugger or uncaught-error handler
-- see the stack that led to the raise, even after the frames
-- have popped during unwinding. See requirements/drinian §
-- Capture-by-reference for the cost model.
--
-- Cascade behavior: if the exception frame is deleted (exception
-- caught, or the whole call stack collapses), the captures go
-- with it. If a referenced frame is deleted (unwound past),
-- the row goes too — the capture becomes partial rather than
-- broken. That matches "point-in-time snapshot" semantics: what
-- survives is what's still there.
create table captured_frames (
	exception_frame_pk  integer not null references frames(frame_pk) on delete cascade,
	position            integer not null check (position >= 0),
	referenced_frame_pk integer not null references frames(frame_pk) on delete cascade,
	primary key (exception_frame_pk, position)
);

create index captured_frames_referenced on captured_frames(referenced_frame_pk);
~~~

## GC drain algorithm

The drain runs on the Lua side, driven by the engine when memory pressure or an explicit trigger fires. It reads and mutates the GC scratch columns (`needs_trace`, `in_trace`) on `objects` and drives deletion via SQL. The whole pass wraps in a transaction so any raise from `on_close` or a RESTRICT FK violation rolls back atomically; the drain re-runs when conditions permit.

### Setup

Insert a row `('in_gc', anything)` into `process`. That row gates the `objects_on_delete_hook` UDF, so it doesn't double-invoke `on_close` during the drain's own callback phase.

### Main loop — trace and sweep interleaved per candidate

~~~
while object = get_next_needs_trace() do
	run_trace(object)
end
~~~

**`get_next_needs_trace()`** — `SELECT object_pk FROM objects WHERE needs_trace = 1 LIMIT 1`. Hits the `objects_needs_trace` partial index; O(log n). Returns null when no candidates remain; loop terminates. Some candidates may already be gone (gobbled by a previous trace's cascade); the query just returns whatever's left.

**`run_trace(object)`**:

1. Stamp `in_trace = counter++` on the candidate.
2. Walk upward — `SELECT parent FROM relationships WHERE child = current_pk` — and stamp `in_trace` on each parent (skipping already-stamped rows — visited set).
3. **If any visited row has `uspace = 1`**, the component is reachable. Clear `in_trace` across the component, clear `needs_trace` on any marked rows. Everything survives.
4. **Otherwise**, the component is dead. Delete in `in_trace` order:
   - Sever relationships first (parent OR child in the dead component). Required because `relationships.child` is `ON DELETE RESTRICT` — cyclic references would otherwise block deletion.
   - Fire `on_close` via `drinian_udf_on_delete` on each row in `in_trace` order.
   - DELETE the object rows. Outgoing relationships cascade via `ON DELETE CASCADE` on parent.

### Ordering guarantee

`on_close` handlers fire in `in_trace` order — deterministic cleanup direction is available if handlers need to depend on it. Matches the earlier design decision that on_close order IS defined (not a "no_cleanup_order_dependency" rule).

### Termination

Each iteration either clears `needs_trace` on the candidate (found alive) or deletes it (found dead). The count of `needs_trace = 1` rows strictly decreases per iteration. Cascade effects (deletes triggering the mark triggers on severed relationships) add more candidates, but the object graph is finite so the loop terminates.

### Cleanup

Delete the `'in_gc'` row from `process`. Commit the transaction.

### Failure modes

- **`on_close` raises.** Exception propagates through the UDF; the transaction rolls back atomically. Whole GC pass is undone. Whatever wrapper transaction (or catching mechanism) sits above the drain handles the exception.
- **RESTRICT fires on delete.** Same shape — some row still has incoming references at delete time (typically an `on_close` created a fresh edge). Transaction rolls back. Handled the same way.
- **Runaway allocation.** An `on_close` that allocates and stores objects reachable from uspace produces persistent state that survives the drain. That's fine — the objects were legitimately created. If it allocates unreachable objects, the next drain picks them up as needs_trace candidates.

