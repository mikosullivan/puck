# Schema

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_schema",
	"role": "Drinian's SQLite schema. `objects` table holds row shapes discriminated by a single `primitive` column — 'o' (object), 'h' (HashPrimitive), 'a' (ArrayPrimitive). Scalars are a variant of `primitive = 'o'` distinguished by `scalar_type` (scalar type). HashPrimitives serving as buckets carry `bucket_for` back-pointing at their owner; ArrayPrimitives serving as stacks carry `stack_for`. Only container primitives can be parents in `relationships`. Buckets and stacks are both lazy — Lua write layer creates them on demand. Scalars with no bucket/stack take a fast dispatch path through the built-in class for their `scalar_type` type. Uspace membership is derived dynamically from the `uspace` view over the anchor tables (locals, frame_amber, frame_delegations, frame columns) — no stored flag. GC uses two-column scratch (needs_trace / in_trace) — the drain deletes directly, and RESTRICT on relationships.child raises loudly if incoming references remain at delete time. Event registrations live in dedicated `instance_listeners` / `class_listeners` tables outside `relationships` — bookkeeping, not graph — with weak-ref lifetime via FK cascade.",
	"status": "iterating — st/sv renamed to scalar_type/scalar_value; scalar_value now blob-typed; inter-column table-level CHECK constraints moved inline to preceding columns to satisfy SQLite's grammar (all-column-defs-before-any-table-constraint)"
}}
~~~

Started 2026-08-07 from Fiona's current schema. Adapting as design decisions land.

## Design summary

Every Drinian row falls into one of these shapes, discriminated by `primitive`, `scalar_type`, `bucket_for`, and `stack_for`. One orthogonal pair sits alongside every row — omitted from the table for readability:

- **`source_pk` + `line`** (nullable pair) — the value's birth line in source. `source_pk` FKs a row in the `sources` registry. Both fields together or both null; immutable after INSERT (birth line doesn't change when the value moves).

Uspace membership is derived by the `uspace` view — a global UNION over anchor sources (root role, locals, frame_amber, frame_delegations, frame columns) across all frames in all processes. Not a stored column; always reflects current state.

| Row shape | primitive | scalar_type | scalar_value | bucket_for | stack_for |
|-----------|-----------|-----|-----|------------|-----------|
| HashPrimitive (standalone / root / internal) | `'h'` | null | null | null | null |
| HashPrimitive serving as a bucket | `'h'` | null | null | set | null |
| ArrayPrimitive (standalone / internal) | `'a'` | null | null | null | null |
| ArrayPrimitive serving as a stack | `'a'` | null | null | null | set |
| Plain full object (Hash, Array, MyClass, …) | `'o'` | null | null | null | null |
| StringPrimitive | `'o'` | `'s'` | text | null | null |
| NumberPrimitive | `'o'` | `'n'` | integer/real | null | null |
| BooleanPrimitive | `'o'` | `'b'` | 0/1 | null | null |
| NullPrimitive | `'o'` | `'u'` | null | null | null |

Rules baked into the schema:

- `primitive` is NOT NULL and has no default — every insert names the kind at creation time.
- Only container primitives (`primitive in ('h', 'a')`) can be parents in `relationships` — full objects and scalars can't have references directly; full objects reach their contents through their bucket / stack.
- **Role-shape alignment.** A row with `bucket_for` set must be a HashPrimitive (`primitive = 'h'`); a row with `stack_for` set must be an ArrayPrimitive (`primitive = 'a'`). An array can't be a bucket; a hash can't be a stack.
- **At most one role per row.** At most one of `bucket_for` / `stack_for` may be set on any given row. A row can't be both a bucket and a stack — enforced by `check (bucket_for is null or stack_for is null)`.
- **At most one bucket and one stack per owner.** `bucket_for` and `stack_for` are each `UNIQUE` — no two rows can be a bucket for the same owner (or a stack for the same owner). Rows where these columns are null don't collide because SQLite doesn't consider nulls in UNIQUE constraints.
- **Buckets and stacks are both lazy.** A plain full object gets neither at creation time. The Lua write layer creates them on demand — `ensure_bucket(obj_pk)` on the first field write, `ensure_stack(obj_pk)` on the first class-extension or shadow. Objects that live briefly and never need either save the row + constraint cost entirely. (Class dispatch for stack-less full objects is a design question we're deferring; probably a `class_pk` column when we get to it.)
- **Scalar fast path.** A scalar row (`primitive = 'o', scalar_type IS NOT NULL`) that has no bucket and no stack — no other row references it via `bucket_for` or `stack_for` — dispatches through the built-in class for its `scalar_type` type (StringPrimitive for `'s'`, NumberPrimitive for `'n'`, BooleanPrimitive for `'b'`, NullPrimitive for `'u'`). Scalars never auto-provision anything, so the fast path is the common case. Scalars that get extended (shadow methods, nested markers) fall back to full dispatch.
- Deleting a full object cascades via FK to delete its bucket (if present) + stack (`bucket_for` and `stack_for` FKs have ON DELETE CASCADE). No cleanup trigger.
- **Bucket / stack denormalization.** Owner rows also carry `bucket_pk` and `stack_pk` columns mirroring the collection-side `bucket_for` / `stack_for`. Redundant data — populated set-once by `objects_denormalize_bucket` / `_stack` triggers when the collection is inserted, then locked. Lets queries and dispatch skip a join.
- **`objects` is effectively immutable.** Identity columns (`object_pk`, `primitive`, `scalar_type`, `scalar_value`, `bucket_for`, `stack_for`) can never change. Denormalization columns (`bucket_pk`, `stack_pk`) are write-once. The only freely-mutable state is GC scratch (`needs_trace`, `in_trace`). Enforced by `objects_no_update`.
- Scalars are single-row leaves — a StringPrimitive is one row with `primitive = 'o'`, `scalar_type = 's'`, `scalar_value = <text>`.
- **Event listeners are bookkeeping, not graph.** Two dedicated tables — `instance_listeners` (for `.listen_to` registrations) and `class_listeners` (for `.listen_to_class`) — hold registration tuples. They live outside `relationships` so GC does NOT count them as reachability edges. Weak-ref lifetime falls out of `ON DELETE CASCADE`: when the broadcaster, class, or listener object is deleted, the registration cascade-deletes with it. Registration order is `reg_pk` (autoincrement). Composite `UNIQUE` on the tuple gives idempotent `.listen_to`.
- **Uspace is a global derived view, not a stored column.** `uspace` (view) unions the row-level anchor sources: root role (the user row), `locals.value_object_pk`, `frame_amber.namespace_hash_pk`, `frames.method_pk` / `method_class_pk` / `exception_class_pk`, and `frame_delegations.target_role_pk`. Any frame in any process contributes — shared object graph, so a reference from anywhere keeps the object alive. Membership is always current: when a frame pops and its anchor rows cascade, the previously-anchored objects drop out of the view automatically and become GC candidates. Roles (children of user in the tree) aren't a special case — they're regular objects reachable via relationships from user's bucket → 'children' array. Buckets and stacks aren't in the union either — they live inside their owner via bucket_for/stack_for cascade, and nothing normally makes them relationship children so they never become GC candidates. Listener registrations are NOT in the union — those are weak-ref by design.
- **Source-location tagging (`sources` + `source_pk` / `line`).** A dedicated `sources` table registers each file / URL that produces values or frames. Object rows and frame rows carry a `(source_pk, line)` pair back-pointing to their origin — the value's birth line, the frame's current line. Both null together when the source is unknown (engine internals, hand-written CaspM, source-less metaprogramming). On objects the pair is immutable; on frames the `line` advances as the frame executes.
- **AST storage on callables (`ast` column).** Function / method / closure objects carry their CaspM body in an `ast` blob column on `objects`, encoded as SQLite JSONB. The engine reads the current value on each call, thaws it to Lua-native form, and attaches the parsed tree to the frame executing it — no long-lived cache, no invalidation dance. Hot-patching an `ast` takes effect on the next call.
- **Roles are regular objects.** No schema-level role machinery — no `role_pk`, no `role_parent`, no dedicated triggers. User is seeded at pk = 1 (undeletable, intrinsic uspace root). Other roles are just objects held in user's role tree via bucket entries — each role carries a `'children'` array in its bucket pointing at its child roles. Tree invariants (single root, cycle prevention, ownership tracking) are enforced by engine-side code, not by the schema.
- **Call stack lives in dedicated tables.** Runtime frames don't fit the objects shape (no class dispatch, no bucket, no stack-of-platters), so they live in purpose-built tables: `processes` (plural), `frames`, `locals`, plus sidecars `frame_delegations` (role permission grants from `delegate_to` blocks), `frame_amber` (per-frame `%amber` namespace layer — init / remove / grant entries; `amber_cleared` on the frame is the full-surface walk-stop), and `captured_frames` (snapshot-by-reference of the frames below an in-flight exception).
- **Frame anchors are automatic via `uspace`.** Every frame-attached table (locals, frame_amber, frame_delegations, etc.) contributes to the uspace view. When a frame pops and its anchor rows cascade, the previously-anchored objects drop out of uspace automatically — no trigger to maintain, no engine-side release. The plural `processes` accommodates future features — coroutines, fork, multiple paused processes coexisting in one file, and **multiple concurrent instances of the same machine running over one shared object graph** — where each execution context is its own `processes` row. Concurrency semantics for the shared-graph case are language-level work; the storage substrate is ready. There's no seeded process — every engine creates its own `processes` row at startup and records the pk in the temp `current_process` table.
- **Rich frame kinds.** `frames.kind` covers the requirements' frame `action` values that we've settled on: `top_level`, `method_call`, `function_call`, `function_invocation`, `block`, `if_block`, `delegate_to`, `exception`, `on_close`. (Pause / revival isn't yet designed — no `'pause'` kind or pause-frame columns until it is.) Fields on `frames` are conditionally meaningful per kind (`method_pk` / `method_class_pk` on call frames, `iterator_position` / `iterator_of` on iteration frames, `exception_class_pk` / `exception_message` on exception frames). `lexical_parent_pk` on any frame links its scope's defining frame — variable lookup walks this chain, not the physical call stack.

## Schema

~~~sql
-- Drinian database design. One `objects` table holds row shapes
-- discriminated by the `primitive` column:
--   'h' → HashPrimitive (hash-shaped primitive container)
--   'a' → ArrayPrimitive (array-shaped primitive container)
--   'o' → object. Either a plain full object (with bucket + stack
--         reachable via bucket_for / stack_for on separate rows)
--         or a scalar primitive (with a scalar type in `scalar_type` and
--         value in `scalar_value`).
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
-- current_process: per-connection runtime state (TEMP table).
-- ------------------------------------------------------------
-- Simple key/value store for per-connection process state. TEMP
-- table: created fresh with each connection open, disappears
-- cleanly when the connection closes. Matches "one running
-- process per connection" — pause = close = current_process
-- vanishes; revive = new connection = fresh current_process
-- populated from persistent state in `main`.
--
-- Currently expected keys:
--   'current_process_pk' → integer, the active call stack's process_pk
--
-- More keys land as the engine grows to need them.
--
-- Because this is a TEMP table, the main schema file (run once
-- at DB creation) can't define it — it needs to be created every
-- time a connection opens. Companion setup file or engine-side
-- code applies this DDL:
--
--     create temp table current_process (
--         key text primary key,
--         value
--     );

create table objects (
	-- Primary key is a UUID4-shaped hex string generated at INSERT
	-- time from SQLite's ChaCha20-backed randomblob(). Built
	-- manually (the uuid() extension isn't compiled into stock
	-- SQLite builds); the expression yields a 36-char hyphenated
	-- lowercase string like 'a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5'
	-- — cryptographically random 128 bits with the standard
	-- UUID hyphen positions. See the "Design consideration:
	-- UUIDs as primary keys?" section for the trade-offs
	-- accepted.
	object_pk text primary key default (
		lower(
			substr(hex(randomblob(4)), 1, 8) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(2)), 1, 4) || '-' ||
			substr(hex(randomblob(6)), 1, 12)
		)
	),

	-- User marker. Exactly one row across the whole table can
	-- carry `user = 1` (enforced by UNIQUE + CHECK). Every other
	-- row leaves it null. Set at INSERT and immutable — the seed
	-- creates the user row with this set, nothing else ever gets
	-- it. Finding the user row is `select object_pk from objects
	-- where user` (truthy check; only user is non-null so the
	-- UNIQUE index picks it up directly).
	user integer unique check (user = 1),

	-- Persistent flag. If set (`persistent = 1`), the object is
	-- unconditionally in uspace — GC leaves it alone regardless of
	-- whether anything else anchors it. Null (the default) means
	-- normal reachability rules apply. Freely mutable via
	-- ordinary UPDATE (subject to the CHECK); an object can be
	-- pinned and later unpinned. Provisional shape — see where it
	-- goes.
	persistent integer check (persistent = 1),

	-- Role parentage. If set, this row is a role and role_parent
	-- points at its parent role. Null on the root role (user row)
	-- and on every non-role object. Immutable at INSERT — a role
	-- can't be reparented; that's what buys the schema-level
	-- cycle-freeness (a row can only reference a row that already
	-- exists, and no existing row can be repointed at a newer row).
	--
	-- Combined with the FK's `on delete cascade`, this column
	-- gives the role tree its own self-maintaining subsystem:
	-- single parent (one column, one value), cycle-free
	-- (immutability + insert-order), cascade cleanup (parent
	-- delete drops the subtree), and root-safety (the existing
	-- objects_no_delete_root_role trigger keeps user undeletable).
	--
	-- Roles are anchored in uspace via the uspace view's
	-- `where role_parent is not null` branch — the tree's rows
	-- are structurally pinned by the FK, not by general
	-- reachability. Role bucket contents still trace normally.
	--
	-- The schema does NOT enforce "role_parent must point at a
	-- role"; that stays a Lua-layer check. Cycle-freeness and
	-- single-parent-ness are the cheap wins the schema takes.
	role_parent text references objects(object_pk) on delete cascade,

	-- Row-kind discriminator. NOT NULL, no default: Drinian's write
	-- code names the row kind at INSERT time. Exactly one of:
	--   'o' → object (full object, or scalar primitive if scalar_type is set)
	--   'h' → HashPrimitive
	--   'a' → ArrayPrimitive
	primitive text not null check (primitive in ('o', 'h', 'a')),

	-- Scalar type. Only meaningful when primitive = 'o'. When set,
	-- this row is a scalar primitive; when null on a primitive =
	-- 'o' row, this row is a plain full object with a bucket +
	-- stack.
	--   's' string, 'n' number, 'b' boolean, 'u' null
	scalar_type text
		check (scalar_type in ('s', 'n', 'b', 'u'))
		check (primitive = 'o' or scalar_type is null),

	-- Scalar value. Meaningful only when `scalar_type` is set.
	-- Declared `blob` for no-affinity storage — SQLite doesn't
	-- coerce values in blob-affinity columns, so integers, reals,
	-- text, and null land in the row as their native type. The
	-- per-scalar-type shape checks below enforce the actual
	-- type-per-scalar_type rule. Checks use `is` (not `in`) so
	-- null cleanly evaluates to false — the `in` form would give
	-- NULL which SQLite's CHECK accepts as passing, silently
	-- letting null booleans through.
	scalar_value blob
		check (scalar_type is null or scalar_type != 'b' or scalar_value is 0 or scalar_value is 1)
		check (scalar_type is null or scalar_type != 'u' or scalar_value is null)
		check (scalar_type is null or scalar_type != 'n' or typeof(scalar_value) in ('integer', 'real'))
		check (scalar_type is null or scalar_type != 's' or typeof(scalar_value) = 'text')
		check (scalar_type is not null or scalar_value is null),

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
	bucket_for text unique references objects(object_pk) on delete cascade
		check (bucket_for is null or primitive = 'h'),
	stack_for  text unique references objects(object_pk) on delete cascade
		check (stack_for  is null or primitive = 'a')
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
	-- CHECK: only plain full objects (primitive = 'o' AND scalar_type null)
	-- can carry these columns.
	-- UNIQUE: no two owners share a bucket or stack — redundant with
	-- the bucket_for / stack_for UNIQUE, but a good safety net for
	-- the denormalization.
	bucket_pk integer unique
		check (bucket_pk is null or (primitive = 'o' and scalar_type is null)),
	stack_pk  integer unique
		check (stack_pk  is null or (primitive = 'o' and scalar_type is null)),

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
	line integer
		check (line is null or line > 0)
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
-- Role tree: partial index over just the role rows. The uspace
-- view's `where role_parent is not null` branch walks this;
-- role-tree traversal queries (find children of X) use it too.
create index objects_role_parent on objects(role_parent) where role_parent is not null;

-- Immutability rules:
--   Fully immutable from INSERT: object_pk, primitive, scalar_type, scalar_value,
--   bucket_for, stack_for, user, role_parent, source_pk, line.
--   Write-once (null → value, then locked): bucket_pk, stack_pk.
--   Freely mutable: persistent, GC scratch (needs_trace, in_trace).
create trigger objects_no_update
before update on objects
begin
	select case
		when new.object_pk is not old.object_pk
			then raise(abort, 'objects_pk_immutable: objects.object_pk is immutable')
		when new.primitive is not old.primitive
			then raise(abort, 'objects_primitive_immutable: objects.primitive is immutable')
		when new.scalar_type is not old.scalar_type
			then raise(abort, 'objects_scalar_type_immutable: objects.scalar_type is immutable')
		when new.scalar_value is not old.scalar_value
			then raise(abort, 'objects_scalar_value_immutable: objects.scalar_value is immutable')
		when new.bucket_for is not old.bucket_for
			then raise(abort, 'objects_bucket_for_immutable: objects.bucket_for is immutable')
		when new.stack_for is not old.stack_for
			then raise(abort, 'objects_stack_for_immutable: objects.stack_for is immutable')
		when new.user is not old.user
			then raise(abort, 'objects_user_immutable: objects.user is immutable')
		when new.role_parent is not old.role_parent
			then raise(abort, 'objects_role_parent_immutable: objects.role_parent is immutable (no role reparenting)')
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

-- The user row (marked `user = 1`) is the root role and cannot
-- be deleted. Every Drinian database starts with user seeded,
-- and nothing above the language layer can remove it. Non-root
-- uspace anchors are freely deletable (that's how an object
-- leaves user space in the first place). The role tree is
-- expressed as bucket contents rooted at user; the tree's
-- integrity is engine-side code, not schema-level enforcement.
create trigger objects_no_delete_root_role
before delete on objects
when old.user
begin
	select raise(abort, 'root_role_cannot_be_deleted: the user row cannot be deleted');
end;

-- Deletion callback machinery (on_close / on_delete UDF hook)
-- deferred. When the engine needs to invoke Caspian-level cleanup
-- on object delete, a trigger + UDF will land here.

-- Role tree lives in the `role_parent` column. A row IS a role
-- iff it has role_parent set (non-root) or user = 1 (root). The
-- schema enforces:
--   Single parent — one column, one value.
--   Cycle-free — role_parent is immutable and INSERT requires
--     the target row to exist, so cycles are structurally
--     impossible.
--   Cascade cleanup — FK on delete cascade drops the subtree.
--   Root safety — objects_no_delete_root_role keeps user
--     undeletable.
-- What the schema does NOT check: that role_parent points at a
-- row that's itself a role (Lua-layer check on INSERT). Also
-- naming, uniqueness of role names, class-ownership rules — all
-- Lua.
--
-- Roles still live in the object graph as ordinary rows with
-- their own bucket and stack. role_parent is an additional
-- pointer, not a replacement for bucket/stack — it's what makes
-- role lifetime independent of bucket-graph reachability.

-- Seed the root role. User is the root role: primitive = 'h'
-- for now (kept as a HashPrimitive per current design), user =
-- 1 marks it as root, persistent = 1 for consistency (the row
-- persists anyway via `where user`), role_parent = null (root
-- has no parent). Its object_pk is a fresh UUID from the
-- default.
insert into objects (primitive, user, persistent) values ('h', 1, 1);

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

	parent  text not null references objects(object_pk) on delete cascade,
	-- child uses ON DELETE RESTRICT so deleting an object with
	-- incoming references raises rather than silently nulling those
	-- references. Loud beats silent. If the trace was accurate and
	-- an object is unreferenced, the RESTRICT check passes; if
	-- something (typically an on_close-created edge) added a new
	-- incoming reference between mark and sweep, the delete raises
	-- and the exception propagates to whatever transaction wraps
	-- the operation.
	child   text not null references objects(object_pk) on delete restrict,

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
-- objects (primitive = 'o') and scalar primitives cannot appear
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
-- No uspace filter — the drain's trace handles uspace membership
-- via the uspace view (uspace rows terminate the trace
-- immediately as alive, a cheap wasted iteration compared to a
-- subquery on every mark-trigger fire).
create trigger relationships_mark_needs_trace_after_delete
after delete on relationships
begin
	update objects set needs_trace = 1 where object_pk = old.child;
end;

-- On UPDATE OF child: mark the OLD child when the slot is swung to
-- a different object. `is not` handles null-vs-value correctly in
-- the WHEN clause where `<>` would silently no-op on null.
create trigger relationships_mark_needs_trace_after_update_of_child
after update of child on relationships
when old.child is not new.child
begin
	update objects set needs_trace = 1 where object_pk = old.child;
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

	broadcaster_pk text not null references objects(object_pk) on delete cascade,
	listener_pk    text not null references objects(object_pk) on delete cascade,

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

	class_pk    text not null references objects(object_pk) on delete cascade,
	listener_pk text not null references objects(object_pk) on delete cascade,

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
-- `processes` is plural: the schema accommodates multiple
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
-- No seed row — each engine creates its own processes row on
-- startup and records its pk in current_process. Multi-process
-- features will create additional rows here at runtime.

create table processes (
	process_pk integer primary key autoincrement
);

-- No seed row. Every engine that opens a Drinian file creates
-- its own row here at startup and records the pk in
-- current_process; on the very first run against a fresh DB
-- that pk will be 1 (autoincrement), but nothing pins it — a
-- reviving process picks up the pk from persistent state or
-- allocates a fresh one as appropriate.

create table frames (
	frame_pk integer primary key autoincrement,

	-- Which call stack this frame belongs to.
	process_pk integer not null references processes(process_pk) on delete cascade,

	-- Position within process_pk's stack. Top = MAX(idx) for that process_pk.
	-- Non-negative; strictly monotonic per process_pk (push assigns
	-- idx = MAX(idx)+1; pop removes the MAX row). Composite
	-- uniqueness on (process_pk, idx) is declared at the end of
	-- this table — SQLite's grammar requires table-level
	-- constraints after all column definitions.
	idx integer not null check (idx >= 0),

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
	kind text not null check (kind in (
		'top_level', 'method_call', 'function_call', 'function_invocation',
		'block', 'if_block',
		'delegate_to', 'exception', 'on_close'
	)),

	-- Method dispatch info — meaningful on method_call,
	-- function_call, function_invocation, on_close frames.
	method_pk       text references objects(object_pk),
	method_class_pk text references objects(object_pk),

	-- Lexical parent link — the frame that owned the scope where
	-- THIS frame's code was DEFINED. Variable lookup walks this
	-- chain, not the physical call stack. Differs from the caller
	-- when a function is called from outside its defining scope.
	-- Null on top_level and engine-pushed frames. ON DELETE SET
	-- NULL: if the defining frame is popped and gone, the link
	-- goes stale (an engine-side concern, not a corruption).
	lexical_parent_pk integer references frames(frame_pk) on delete set null,

	-- Iterator state — meaningful on method_call frames for
	-- iteration methods (each, map, etc.). Together record where
	-- the iteration is so a suspended frame can resume from the
	-- right position.
	iterator_position integer check (iterator_position is null or iterator_position >= 0),
	iterator_of       integer
		check (iterator_of is null or iterator_of > 0)
		check ((iterator_position is null and iterator_of is null)
			or (iterator_position is not null and iterator_of is not null)),

	-- Exception details — meaningful on 'exception' frames only.
	-- exception_class_pk points at the exception's class object;
	-- exception_message is human-readable text carried alongside.
	exception_class_pk text references objects(object_pk),
	exception_message  text,

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
	line      integer
		check (line is null or line > 0)
		check ((source_pk is null and line is null) or (source_pk is not null and line is not null)),

	-- Composite uniqueness — one frame per (process_pk, idx) slot.
	-- Table-level because it spans two columns; sits here to
	-- satisfy SQLite's grammar (table constraints after column
	-- definitions).
	unique (process_pk, idx)
);

create index frames_process_pk on frames(process_pk);

create table locals (
	-- Local variable bindings for a specific frame. Cascade-deletes
	-- with the frame — locals live and die with their frame.
	frame_pk integer not null references frames(frame_pk) on delete cascade,

	-- Variable name — inline text (no interning at storage level).
	name text not null,

	-- The object bound to this name. Plain reference: deleting a
	-- frame shouldn't delete objects the frame referenced, since
	-- they may be alive elsewhere.
	value_object_pk text not null references objects(object_pk),

	primary key (frame_pk, name)
);

create index locals_value on locals(value_object_pk);

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
	target_role_pk text not null references objects(object_pk) on delete cascade,
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
	namespace_hash_pk text references objects(object_pk),

	-- For 'grant' entries: the read / write permissions the callee
	-- receives across the role boundary. Both are 0 or 1.
	grant_read  integer check (grant_read is null or grant_read in (0, 1)),
	grant_write integer check (grant_write is null or grant_write in (0, 1))
);

create index frame_amber_frame_pk  on frame_amber(frame_pk);
create index frame_amber_namespace on frame_amber(namespace);
create index frame_amber_hash_pk   on frame_amber(namespace_hash_pk) where namespace_hash_pk is not null;

-- Amber namespace hashes are held in uspace by the uspace
-- view (which unions frame_amber.namespace_hash_pk into the
-- membership set). No trigger needed to anchor them; when the
-- frame_amber row cascades away on frame pop, the hash drops out
-- of the view naturally and rejoins the GC candidate pool.

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

-- ------------------------------------------------------------
-- uspace — derived view of GC anchor set.
-- ------------------------------------------------------------
-- Membership in "uspace" is computed dynamically from actual
-- anchoring rather than stored as a column. Uspace is GLOBAL: an
-- object is in uspace if it's anchored by ANY frame in ANY
-- process. Under the shared-object-graph model, references from
-- any process count — GC sweeps only objects that no process
-- anchors.
--
-- An object is in uspace when it's:
--
--   * The root role (user, pk = 1).
--   * Held as a variable binding in any frame's locals.
--   * A namespace hash held in any frame's amber layer.
--   * The method being executed by some frame, or that method's
--     defining class.
--   * The exception class of an in-flight exception.
--   * The target of a role delegation on some frame.
--
-- Buckets and stacks are NOT in this list. They live inside their
-- owner via bucket_for / stack_for (ON DELETE CASCADE handles
-- owner-goes-so-bucket-goes at the FK level). Under normal
-- Drinian ops nothing puts a bucket or stack row as a child in
-- the relationships table, so mark triggers never fire on them —
-- they never become GC candidates.
--
-- Roles (children of user in the role tree) aren't a special
-- case — they're regular objects reachable via relationships from
-- user's bucket → 'children' array → child roles. Standard trace
-- reaches them from user (which IS in uspace).
--
-- The listener registration tables (instance_listeners,
-- class_listeners) are deliberately NOT in the union — their FK
-- cascade is documented as weak-ref lifetime, so a listener
-- registration is not enough to keep either party alive.
--
-- Cost per check: one indexed lookup per union branch. Anchor
-- tables have small row counts in typical programs; the UNION is
-- cheap in practice.

create view uspace as
	-- Root role (the user row) is intrinsically uspace.
	select object_pk from objects where user
	union
	-- Objects flagged persistent — pinned regardless of other anchors.
	select object_pk from objects where persistent
	union
	-- Role tree: every non-root role. Combined with the `where user`
	-- branch above (which picks up the root), this covers every
	-- role. Uses the objects_role_parent partial index.
	select object_pk from objects where role_parent is not null
	union
	-- Frame variable bindings.
	select value_object_pk from locals
	union
	-- Amber namespace hashes referenced from a frame.
	select namespace_hash_pk from frame_amber where namespace_hash_pk is not null
	union
	-- Method being called + defining class, for every live frame.
	select method_pk from frames where method_pk is not null
	union
	select method_class_pk from frames where method_class_pk is not null
	union
	-- Exception class while an exception is in flight.
	select exception_class_pk from frames where exception_class_pk is not null
	union
	-- Roles being granted permissions via delegate_to blocks.
	select target_role_pk from frame_delegations;
~~~

## GC drain algorithm

The drain runs on the Lua side, driven by the engine when memory pressure or an explicit trigger fires. It reads and mutates the GC scratch columns (`needs_trace`, `in_trace`) on `objects` and drives deletion via SQL. The whole pass wraps in a transaction so any RESTRICT FK violation rolls back atomically; the drain re-runs when conditions permit.

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
3. **If any visited row is in `uspace`** (`SELECT 1 FROM uspace WHERE object_pk = ?`), the component is reachable. Clear `in_trace` across the component, clear `needs_trace` on any marked rows. Everything survives.
4. **Otherwise**, the component is dead. Delete in `in_trace` order:
   - Sever relationships first (parent OR child in the dead component). Required because `relationships.child` is `ON DELETE RESTRICT` — cyclic references would otherwise block deletion.
   - DELETE the object rows. Outgoing relationships cascade via `ON DELETE CASCADE` on parent.

Callback machinery (on_close and other per-delete engine hooks) is deferred — this section is a "loud + simple" drain today; callbacks will land alongside a new on-delete trigger when the design settles.

### Termination

Each iteration either clears `needs_trace` on the candidate (found alive) or deletes it (found dead). The count of `needs_trace = 1` rows strictly decreases per iteration. Cascade effects (deletes triggering the mark triggers on severed relationships) add more candidates, but the object graph is finite so the loop terminates.

### Failure modes

- **RESTRICT fires on delete.** Some row still has incoming references at delete time — trace missed something, or code between mark and sweep created a new edge. Transaction rolls back atomically. Whole GC pass undone. Whatever wrapper transaction (or catching mechanism) sits above the drain handles the exception.

## Design consideration: UUIDs as primary keys?

Currently every table uses `integer primary key autoincrement` for its pks — small sequential integers. Would switching to UUIDs earn its keep?

### What UUIDs would buy

- **Cross-database uniqueness.** Two independent Drinian databases could be merged without pk collision. Currently a snapshot from Process A and Process B both start at pk = 1; merging is a manual reconciliation task.
- **Distributed generation.** Multiple writers could allocate pks without coordinating. `autoincrement` is a single-writer-per-connection concept.
- **External reference stability.** An external system holding "object 42" as a reference to a specific Drinian object relies on that pk. Under integers, pks are stable within a single DB but not across DBs; UUIDs are stable everywhere.
- **Debugging trace disambiguation.** A log entry mentioning object 42 could mean many different objects across runs. A UUID is unambiguous.

Generation cost isn't the issue — SQLite ships a `uuid()` extension function (`ext/misc/uuid.c`) that generates UUID4 values directly. Not compiled into every SQLite build by default, but trivially includable, and roughly equivalent to a plain `randomblob(16)` in cost.

### What UUIDs would cost — even if we don't use their uniqueness features

Every table would pay:

- **Storage.** Sequential integers are 1–4 bytes each; UUIDs are 16 bytes (as blob) or 36 bytes (as text). Every FK column, every index, every `relationships` row (parent + child = two pk columns) roughly 5x its pk-related storage. Rough estimate for a 100K-object program: ~1–2 MB integer pks → ~5–10 MB UUID pks. Whole database roughly doubles or triples in size.
- **Index performance.** B-tree indexes hold fewer entries per page with larger keys. More page reads per lookup, more page faults for large scans.
- **B-tree write locality.** Sequential integers append to the end of the B-tree — a hot handful of pages. Random UUIDs scatter across the whole tree, dirtying many pages per write. Real-world write throughput drops noticeably (2–3x slower for insert-heavy workloads).
- **Rowid alias loss.** With `INTEGER PRIMARY KEY`, SQLite makes the pk column an alias for the internal rowid — zero storage overhead. With a UUID pk, either the table is `WITHOUT ROWID` (works but has other constraints and quirks) or the table carries both a rowid AND the pk (extra storage plus an extra lookup layer).
- **Human readability.** `role_pk = 1` scans instantly; `role_pk = '9c440335-a5fa-406a-8676-1da39a1a4617'` doesn't. All debugging output, snapshot inspection, and SQL prompts pay this cost forever.
- **JSON payload size.** Anywhere pks appear in JSON (the `ast` blob's structure, snapshot serialization), UUIDs make the payload larger.

### When UUIDs would earn their keep

- Merging Drinian files from different processes — multi-agent coordination, sync patterns.
- Long-lived external references to specific objects across DB lifetimes (bookmarks, permalinks, cross-system audit trails).
- Multi-writer scenarios without coordinated pk allocation — cross-process concurrent writes to one shared DB (a scenario the current design doesn't have and would need substantial other work to support).

### When they wouldn't

- V1 single-process, single-writer Drinian.
- Pause/resume within a single DB file lineage (the file survives — pks survive with it).
- Every scenario the current schema serves.

### The "cost if you don't use it" test

Feature tax is real and unrewarded for the common case. The scenarios where UUIDs help are outside V1 scope; the scenarios where they hurt are every read, every write, every trace, every scan.

### If we ever need cross-DB uniqueness

The cheapest way to add it later is an **optional UUID sidecar column** on `objects` (or a sidecar table keyed `object_pk → uuid`) — set on the specific objects that need cross-DB identity, null everywhere else. Pay per-use; keep the integer pk fast path for everything else.

### Randomness source: OS entropy vs SQLite's internal PRNG

Even if we accepted the storage / performance costs above, there's a policy question: **Caspian requires random-value generation (UUIDs, session tokens, etc.) to use OS-supplied entropy.** The Lua-side UUID library we already rely on calls the OS's random device (`/dev/urandom` on Linux) on every generation, for regulatory compliance and to keep predictable-PRNG bugs out of the security surface.

If we adopted UUIDs, we'd need to know: does SQLite's `uuid()` extension (or `randomblob()`) satisfy that constraint?

**What SQLite actually does.** SQLite's `sqlite3_randomness()` API — which backs `randomblob(N)`, `random()`, and (indirectly) the `uuid` extension — uses a ChaCha20 stream cipher as its internal PRNG. On the first call after library load, SQLite seeds the generator by reading bytes from `/dev/urandom` (or the platform equivalent). Subsequent calls generate bytes from the ChaCha20 stream — no further syscall.

So SQLite's generator is:

- **Cryptographically strong** — ChaCha20 is a modern crypto primitive.
- **OS-seeded** — the initial state comes from OS entropy.
- **Not "per-byte from OS entropy"** — generation runs from the internal cipher stream after the initial seeding.

**Whether that satisfies Caspian's requirement is interpretive.** Two readings:

- **Strict.** "Every random byte comes fresh from OS entropy." SQLite fails this — we'd need a Lua UDF that reads `/dev/urandom` per generation.
- **Pragmatic.** "The entropy source is OS-provided; generation is cryptographically strong." SQLite passes — its built-in is fine.

**Cost comparison:**

- **SQLite native** (`uuid()` or `randomblob(16)`): microseconds per generation, in-process ChaCha20, no syscall after startup seeding.
- **Lua UDF calling `/dev/urandom` per UUID:** syscall + Lua-callback overhead per generation. Order of magnitude slower than the SQLite native path (still fast in absolute terms, but noticeable at scale).

If we ever adopted UUIDs and interpreted the requirement strictly, the total UUID cost stacks: storage overhead (previous subsection) + slower generation (this one). If we interpret it pragmatically, only the storage overhead remains.

### Recommendation

Stay with integer pks. Feature tax is 2–3x storage and comparable performance overhead; the randomness-policy question adds another decision to resolve; benefit is a scenario we don't have yet. Revisit only if concrete workloads require it, and even then prefer a per-object opt-in via the sidecar approach.

