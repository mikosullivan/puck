# First variable

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_first_variable",
	"role": "walkthrough of the CVM tables as the first variable assignment in a program executes. Sits between end-of-bootstrap (code loaded, nothing run) and later examples (closure, function call). Written to surface the granularity of the CVM's preserved state — where a step decomposes into finer snapshots, and where a Lua block runs atomically and the state jumps from one coherent moment to the next.",
	"status": "stub"
}}
~~~

The smallest program that changes state:

~~~caspian
$x = 1
~~~

Picks up where [end-of-bootstrap](https://www.puck.uno/ideas/frames-as-objects/examples/end-of-bootstrap/) leaves off and walks through the execution of this one assignment. Written slowly to surface which multi-write operations naturally wrap in a transaction and which stand as observable checkpoints between them.

Approximate CaspM (transpile + normalize):

~~~json
[
	[
		{"bwc": "="},
		{"v": "x"},
		{"v": 1}
	]
]
~~~

## After bootstrap

Same shape as the end-of-bootstrap snapshot, just with `$x = 1`'s CaspM in frame 0's `ast`. User seed in place, `processes` seeded, frame 0 pushed with `stmt_idx = 0` — about to dispatch the assignment. No bucket yet.

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment"><code>[[{"bwc": "="}, {"v": "x"}, {"v": 1}]]</code></td></tr>
</tbody>
</table>

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-relationships" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>

## The execution loop

Once the engine knows the frame about to start, it enters its main loop. Conceptually:

~~~
frame = [engine provided]

while next_frame(frame.run)
end

shut_down
~~~

Each iteration is one atomic step. `frame.run` does whatever it does inside its own write-block and hands back the next frame to run — matching the "endpoints are snapshottable, the interval is opaque" model established at [end-of-bootstrap](https://www.puck.uno/ideas/frames-as-objects/examples/end-of-bootstrap/#whats-on-that-frame). One loop turn = one transition between two "about to start" snapshots.

The exit condition doubles as the terminal check. When `frame.run` returns nothing, the loop ends and `shut_down` runs. That aligns with the terminal invariant: no frames left = program done.

`next_frame(...)` compresses "assign this to `frame` and tell me if the loop should keep going" into one call — cleaner than the more verbose `while (frame = frame.run()) do end` pattern.

## Dispatch statement 0

Statement 0 is a bareword call to `=` with two argument atoms — the LHS `{"v": "x"}` and the RHS `{"v": 1}`. The RHS is a primitive scalar; its value sits right there in the atom, so no nested frame is needed to evaluate it. The whole assignment fits in one atomic step of `frame.run`.

### Overview

The whole write block, `begin` to `commit`:

~~~sql
begin;

-- Create the scalar.
insert into objects (primitive, scalar_type, scalar_value, owner_role)
values ('o', 'n', 1, <user_pk>);
-- returns the scalar's object_pk

-- Ensure frame 0's bucket exists (lazy).
-- Check frame 0's bucket_pk. If null, one INSERT creates it:
--   insert into objects (primitive, bucket_for, owner_role)
--   values ('h', <frame_0_pk>, <user_pk>);
-- The objects_denormalize_bucket trigger updates frame 0's bucket_pk
-- in the same statement — bucket creation is atomic at the SQL layer,
-- no engine-side wrapping needed. Returns the bucket's object_pk.

-- Bind the name.
insert into refs (parent, child, key, idx)
values (<bucket_pk>, <scalar_pk>, 'x', 0);

-- Advance the dispatch pointer.
update objects set stmt_idx = 1 where object_pk = <frame_0_pk>;

commit;
~~~

The "ensure the bucket exists" step is one lookup plus at most one INSERT. There is no Lua-side transaction or helper wrapping bucket creation — SQLite handles the atomicity via the `objects_denormalize_bucket` trigger. Inserting a HashPrimitive with `bucket_for` set is a single statement; the trigger updates the owner's `bucket_pk` in the same write.

## Start transaction

The engine issues `begin;`. Every subsequent write happens inside this transaction until `commit;` closes it. If the process dies at any point in between, SQLite discards the whole block and the CVM sees the state exactly as it was at this snapshot — the "about to dispatch statement 0" moment.

~~~sql
begin;
~~~

## Create the number

The engine evaluates the RHS first. The RHS is the literal `1` — a primitive scalar. One INSERT materializes it as an objects row:

~~~sql
insert into objects (primitive, scalar_type, scalar_value, owner_role)
values ('o', 'n', 1, <user_pk>);
~~~

`owner_role = user`, no incoming refs. Orphan for now — the scalar exists, but nothing yet points at it. The subsequent steps set up the frame's local-storage machinery and finally bind `x` to this row.

### State after

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0 — <code>bucket_pk</code> still null</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — orphan</td></tr>
</tbody>
</table>

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-relationships" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>

## Set `frame.locals['x']`

The engine writes the scalar's pk into the frame's locals under key `x`. On the surface, one assignment:

~~~
frame.locals['x'] = <scalar_pk>
~~~

Underneath, that composes into a tree of get-or-create operations. Each "ensure" branch is idempotent: does nothing if the target already exists, otherwise materializes it and writes to the DB. On a fresh frame — like this one — none of the targets exist, so every branch runs:

~~~
frame.locals['x'] = <scalar_pk>
├── frame.locals               ensure the locals hash, return it
│     ├── frame.bucket      ensure the bucket, return it
│     │     └── create bucket      (1 write, denormalized in same statement)
│     └── bucket['locals']       ensure the locals hash key holds a hash
│           ├── create locals hash  (1 write)
│           └── insert bucket → locals ref, key='locals'  (1 write)
└── insert locals_hash → scalar ref, key='x'   (1 write)
~~~

Walked left-to-right, that's four DB writes across three call layers. Each is shown below with the tables at that moment.

### `frame.bucket` — ensure the bucket

Frame 0's `bucket_pk` is null, so the branch runs. One INSERT creates the HashPrimitive; the `objects_denormalize_bucket` trigger updates frame 0's `bucket_pk` inside the same statement — atomic at the SQL layer.

~~~sql
insert into objects (primitive, bucket_for, owner_role)
values ('h', <frame_0_pk>, <user_pk>);
~~~

#### State after

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0 — <code>bucket_pk</code> is now <code>b00d...</code> (denormalized by trigger)</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — still orphan</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket; <code>bucket_for</code> = <code>f00d...</code></td></tr>
</tbody>
</table>

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-relationships" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>

`bucket` returns `b00d...`. `frame.locals` continues.

### `frame.locals` — ensure the locals hash

The bucket has no entry under key `locals`, so this branch runs. Two writes: the HashPrimitive that will be the locals hash, and the ref that stores it in the bucket under `locals`.

~~~sql
insert into objects (primitive, owner_role)
values ('h', <user_pk>);
-- returns the locals hash's object_pk

insert into refs (parent, child, key, idx)
values (<bucket_pk>, <locals_pk>, 'locals', 0);
~~~

After the first INSERT the row exists but is orphan; after the second it's reachable from frame 0's bucket under the key `locals`.

#### State after

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — still orphan</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket</td></tr>
<tr><td><code>10ca0000-0001-4000-8000-000000000003</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">locals hash — reachable via frame 0's bucket under key <code>locals</code></td></tr>
</tbody>
</table>

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-relationships" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>b00d...</code></td><td><code>10ca...</code></td><td><code>locals</code></td><td><code>0</code></td><td class="col-comment">frame 0's bucket → locals hash</td></tr>
</tbody>
</table>

`frame.locals` returns `10ca...`. The outer assignment resumes.

### `['x'] = <scalar_pk>` — bind the key

The last write: insert a ref from the locals hash to the scalar under key `x`.

~~~sql
insert into refs (parent, child, key, idx)
values (<locals_pk>, <scalar_pk>, 'x', 0);
~~~

The scalar is no longer orphan. Looking up `$x` in frame 0 walks: frame 0 → its bucket → the `locals` ref → the locals hash → the `x` ref → the scalar `1`.

#### State after

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — bound to name <code>x</code> in the locals hash</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket</td></tr>
<tr><td><code>10ca0000-0001-4000-8000-000000000003</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">locals hash</td></tr>
</tbody>
</table>

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-relationships" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>b00d...</code></td><td><code>10ca...</code></td><td><code>locals</code></td><td><code>0</code></td><td class="col-comment">frame 0's bucket → locals hash</td></tr>
<tr><td><code>2</code></td><td><code>10ca...</code></td><td><code>ca7e...</code></td><td><code>x</code></td><td><code>0</code></td><td class="col-comment">locals hash → scalar 1, bound as <code>x</code></td></tr>
</tbody>
</table>

## Commit

The engine closes the transaction:

~~~sql
commit;
~~~

Every write since `begin;` becomes durable in one atomic block. The `objects` and `refs` tables look exactly as they did at the end of "Bind `x` to the number" — the commit doesn't change what's visible in a snapshot; it just makes those writes real.
