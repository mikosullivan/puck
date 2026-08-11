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
<tr><th class="tbl-title-relationships" colspan="5">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
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

## Create the bucket

The engine wants to write into `frame.locals` — the frame's locals hash. But frame 0 doesn't have one yet (its `bucket_pk` is null in the After-bootstrap snapshot). Before anything can bind into it, the bucket itself has to exist.

The engine inserts a HashPrimitive whose `bucket_for` points at frame 0:

~~~sql
insert into objects (primitive, bucket_for, owner_role)
values ('h', <frame_0_pk>, <user_pk>);
~~~

**Bucket creation is atomic at the SQL layer.** That one INSERT is the whole write. SQLite fires the `objects_denormalize_bucket` trigger within the same statement, which updates frame 0's `bucket_pk` to point at the new bucket. From the caller's side, one statement went in and both the new row and the denormalized back-link are present. No engine-side transaction wrapping, no helper — the atomicity is a property of the schema.

### State after

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0 — <code>bucket_pk</code> is now <code>b00d...</code> (denormalized by trigger); ast unchanged</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket; <code>bucket_for</code> = <code>f00d...</code></td></tr>
</tbody>
</table>

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-relationships" colspan="5">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

The bucket exists but is empty — no refs rows yet.

## Create the locals hash

Now the engine creates a HashPrimitive to hold the frame's local bindings — the object that `frame.locals` will eventually return. One INSERT:

~~~sql
insert into objects (primitive, owner_role)
values ('h', <user_pk>);
~~~

No `bucket_for`, no refs. The row is orphaned in the object graph for now — inside the running transaction that's fine; the engine's Lua-side holds a reference to the new pk, and a later step in this transaction attaches it into frame 0's bucket.

### State after

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0 — <code>bucket_pk</code> = <code>b00d...</code>; ast unchanged</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket; <code>bucket_for</code> = <code>f00d...</code></td></tr>
<tr><td><code>10ca0000-0001-4000-8000-000000000003</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">locals hash — orphan for now; will be attached into frame 0's bucket in a later step</td></tr>
</tbody>
</table>

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-relationships" colspan="5">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

Still no refs. Three HashPrimitive-shaped objects (the user seed, frame 0's bucket, the fresh locals hash) but only the bucket is currently linked into the graph via `bucket_for`. The locals hash sits by itself.
