# frame-0

~~~vibecode
{"vibecode": {
	"doc": "sprints_frame_0",
	"role": "Sprint doc for finishing the Set up frame 0 sub-step of bootstrap — the last unwired piece of the Stage step. `engine:load(source)` currently transpiles + normalizes and stops; this sprint wires the INSERT that lands frame 0 as an `objects` row with `primitive='f'` and the CaspM in its `ast`. After this sprint closes, bootstrap is complete and the CVM holds a runnable frame."
}}
~~~

## Goal

Close the last open sub-step of bootstrap ([Set up frame 0](https://www.puck.uno/requirements/bootstrap/stage/set-up-frame-0/)). At the end of the sprint, `engine:load(source)` will leave the CVM holding frame 0 as an `objects` row with `primitive = 'f'`, the CaspM in its `ast`, and stack coordinates set. The runtime dispatch loop (a separate future sprint) can then pick that frame up and start executing.

## Sprint schema

This sprint works against its own schema copy at [sprints/frame-0/src/schema.sql](./src/schema.sql) — a fork of the shipping [src/engine/cvm/schema.sql](../../src/engine/cvm/schema.sql) with the sprint's in-flight changes. Merges back to shipping when the sprint closes.

**Sprint layout:**

- [`src/`](./src/) — the sprint's production files (`schema.sql`, `get_latest_frame.lua`, `initialize_process.lua`).
- [`tests/`](./tests/) — sprint-scoped tests, one per module. Run each with `lua5.4 sprints/frame-0/tests/test_<name>.lua`. Promotes into `tests/main/lua/engine/` when the sprint closes.

**Changes from shipping:**

- **`objects.idx` dropped.** Was schema-provisioning for a not-yet-spec'd revival flow; no current code reads it. If revival ever needs to identify the current frame from persistent state, the mechanism is spec'd then — could be `idx` again, could be a current-frame pointer on `processes`, could be an ordering derived from the `frame_parent` chain.
- **`processes.process_pk` → text UUID.** Was `integer primary key autoincrement`; now the same UUID4-shaped text pk `objects.object_pk` uses (hex-encoded randomblob assembled with UUID hyphen positions, defaulted at INSERT). Rationale: two independently-created CVM files should be joinable without pk collision — matches the discipline the object graph already runs on. `objects.process` FK follows: `integer` → `text`.
- **`objects.frame_parent` added.** Text FK back to `objects.object_pk`. Only frame 0 of a process binds to `processes` via `process`; every sub-frame (frame 1, 2, ...) sets `frame_parent` to the pk of the frame that pushed it and leaves `process` null. This leaves room for a future design where multiple processes share the tail of a call chain — fan-in via a shared frame that more than one process anchor points at, indirectly. See [Find latest](#find-latest) for how the walk uses it.

## Starting state — after Initialize VM, before Stage

At this point in bootstrap:

- Schema installed (the sprint copy above).
- `cvm` marker seeded with `('schema', '9.0')`.
- User seed inserted into `objects` — the root role, grandfathered.
- `processes`, `refs` empty.
- No frame yet — that's what this sprint adds. Create Frame 0's fresh branch also creates the process row.

**Implication for Initialize VM.** Under this sprint's flow, the process row is created HERE (in the fresh branch below), not in Initialize VM. Its [initialize-process-record](https://www.puck.uno/requirements/bootstrap/initialize-vm/initialize-process-record/) sub-step is deferred out of Initialize VM into Create Frame 0's fresh branch — this way bootstrap only creates a process in the case that actually needs one. Revival gets a process pk from the caller; fresh creates one here. Initialize VM drops to three sub-steps (Open the DB, Install infrastructure, Return the CVM handle).

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed (user=1, persistent=1); grandfathered — the only row with owner_role null under the CVM's XOR rule</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>

**Reading the pks.** Every UUID shown (user seed, frame 0, bootstrap process) is illustrative — the schema's `randomblob`-driven default generates a fresh UUID per row; the values here are stand-ins so the walkthrough can refer to them. The bootstrap process uses the placeholder `b8f4a2e1-9c3d-4a7b-8e12-6f5d9c4a3b21` throughout.

## Find/create frame

Bootstrap has one decision left: is this a fresh run, or a revival of an existing process? The two branches are two different routines.

### Find latest

`get_latest_frame(db, process_pk)` — the revival routine. Read-only lookup: returns the deepest on-stack frame in the given process, `nil` if the process has no frames, raises if the process pk isn't in the DB. Implementation at [`sprints/frame-0/src/get_latest_frame.lua`](./src/get_latest_frame.lua); tests at [`sprints/frame-0/tests/test_get_latest_frame.lua`](./tests/test_get_latest_frame.lua).

Three steps inside — each its own subsection below. All three are read-only; no writes to the DB under any outcome.

#### Verify the process exists

Precondition check — if the caller was told to revive a process that isn't in the DB, that's a caller-side bug and we raise early:

~~~sql
select 1 from processes where process_pk = ?;
~~~

No row match → raise `get_latest_frame_process_not_found` naming the pk the caller passed. Fail loudly at the earliest layer that can detect it, per [invariant violations](https://puck.uno/requirements/concepts#invariant-violations-crash-the-program).

#### Find frame 0

Under the sprint's schema only frame 0 of a process binds to `processes` via `process`; sub-frames chain via `frame_parent` (see [Sprint schema](#sprint-schema)). So the first hop is:

~~~sql
select object_pk from objects
where primitive = 'f' and process = ?;
~~~

At most one row matches — that's frame 0.

**Empty-process outcome is valid, not exceptional.** A process row that exists but has no frames on it is a legitimate state — we return `nil` and leave the database exactly as we found it. No delete of the empty process row, no insert of a placeholder frame, no write of any kind. Whether an empty process should eventually be reaped is a separate concern handled by a different routine at a different time.

#### Walk down the chain

A Lua loop, one hop per iteration. Each step asks for the child of the frame we're currently on:

~~~sql
select object_pk from objects
where primitive = 'f' and frame_parent = ?;
~~~

Bind the previous step's `object_pk` as the parameter. Under the current push model there's at most one such child per frame. When the query returns nothing, the frame we're currently on has no child — it IS the deepest. Return its pk.

**Why binding only frame 0 to the process.** Binding every frame directly to `processes` would foreclose future systems where multiple processes share the tail of a call chain (fan-in). Binding only frame 0 leaves that door open — future work can spec how a shared child frame is discovered from more than one process anchor without any schema change to sub-frames.

**Why a loop, not recursion.** Semantically identical here. A loop reads more directly and avoids Lua's stack cost for chains that could get deep. If a future design admits genuine tree-shaped stacks (multiple children per frame), recursion or an explicit worklist would replace the loop.

#### Return values

- Process exists, ≥1 frame on it → deepest frame's `object_pk`.
- Process exists, 0 frames → `nil`. Cleanup of empty processes is done later, not by this routine.
- Process doesn't exist → raise `get_latest_frame_process_not_found`.

### Create Frame 0

Fresh case — no process was specified. **Separate routine from `get_latest_frame`.** Split into two composable pieces so each is independently testable:

- **`initialize_process(db) → process_pk`** — implemented at [`sprints/frame-0/src/initialize_process.lua`](./src/initialize_process.lua); tests at [`sprints/frame-0/tests/test_initialize_process.lua`](./tests/test_initialize_process.lua). One INSERT, returns the fresh text UUID.
- **Frame 0 push** — not yet implemented. Will INSERT the frame with the process pk from above.

The eventual Create Frame 0 routine composes both under one `begin;`/`commit;` wrap so the two writes are atomic.

**CaspM comes from `engine.caspm`.** Create Frame 0 reads that slot directly — no transpile, no normalize inside this routine — and stashes the value in frame 0's `ast` column. Whatever populated the slot (currently `engine:load(source)`, potentially other loaders later) is out of this sprint's scope; the sprint just enforces that a slot value is what frame 0 carries. The precondition (slot is populated) is already vouched for upstream by `engine:run()`'s existing nil-check on `self.caspm`, so Create Frame 0 doesn't re-check.

**Strict-CaspM contract for now.** The slot must hold ready-to-dispatch CaspM. Feeding raw CaspJ (comment atoms, `line`/`value`/`body` keys, unfolded statement prefixes, undesugared pipes, etc.) into Create Frame 0 is a caller-side bug in this sprint. The strict-CaspM rule is deliberate — it keeps the skeleton walking without pulling transpiler behavior into this sprint's contract.

**Transpilation belongs at this exact spot.** When the eventual "accept CaspJ input" story lands (informed by [normalize-passthrough](../normalize-passthrough/) once its idempotence guarantee is in), the transpile / normalize hop lands **here** — at Create Frame 0's read of the `caspm` slot. Not at `load()` time, not somewhere between. This is the moment CaspM is actually consumed, the moment the engine's `transpiler` slot has to be resolved, and the natural convergence point for the future source / CaspJ / CaspM loaders. Locating it here is what lets multiple entry formats share one pipeline instead of each carrying its own transpile branch. See the [architectural note in Set up frame 0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/#this-is-where-transpilation-happens) for the promoted rule.

When Create Frame 0's code lands, it carries a markdown docstring comment at this exact spot declaring "this is the transpile point." Not written yet — code isn't written yet — but the location is pinned.

Two INSERTs (what the composed routine will do):

~~~sql
-- 1. Create the process. Text UUID defaulted from randomblob;
--    RETURNING hands the fresh pk back so the frame INSERT can bind
--    to it without a second query.
insert into processes default values
returning process_pk;
-- returns e.g. 'b8f4a2e1-9c3d-4a7b-8e12-6f5d9c4a3b21'

-- 2. Insert frame 0 with primitive='f', the transpiled CaspM in its
--    ast, and the process pk from step 1.
insert into objects (primitive, ast, process, stmt_idx, owner_role)
values ('f', <caspm_json>, <returned_process_pk>, 0, <user_pk>);
~~~

The engine holds both pks (process and frame 0) in Lua-side state after the two INSERTs, and returns the frame's pk to whoever called Set up frame 0 — that pk is bootstrap's resume point.

Column by column for the frame INSERT:

- `primitive = 'f'` — the frame primitive; distinct from `'o'` / `'h'` / `'a'`.
- `ast` — the CaspM tree serialized as JSON text. Biconditional with `primitive = 'f'`: every frame carries code; no non-frame does.
- `process = <returned_process_pk>` — the UUID that came back from the `processes` INSERT above.
- `stmt_idx = 0` — about to dispatch statement 0 of the ast.
- `owner_role = <user_pk>` — frame 0 runs as the user role.

State after the two INSERTs. `processes` (not shown) now holds one row with the returned pk; `objects` gains the frame:

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>f</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>b8f4a2e1-9c3d-…</code></td><td>user</td><td class="col-comment">frame 0 — <code>ast</code> holds the CaspM produced by Transpile; <code>process</code> points at the bootstrap process (illustrative pk <code>b8f4a2e1-9c3d-4a7b-8e12-6f5d9c4a3b21</code>)</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>

Bootstrap ends here. The CVM holds a runnable frame; the future runtime dispatch loop (separate sprint) picks up from `stmt_idx = 0` on this row.

**Crash-safe.** This is a valid resume point. The two INSERTs run inside a single transaction, so SQLite commits them as one unit — no partial state where the process row exists but frame 0 doesn't. If the process crashes after commit, next open finds both rows as shown above. If it crashes before commit, next open finds the [Starting state](#starting-state--after-initialize-vm-before-stage) — no process, no frame, ready for bootstrap to retry Create Frame 0. Every commit boundary in the CVM is a state the runtime can pick up from; that's the same property that makes [pause / resume](https://www.puck.uno/requirements/cvm/pause-resume/) work.
