# First variable — walkthrough

~~~vibecode
{"doc": "sprint-walkthrough", "sprint": "first-variable",
	"role": "State-by-state walkthrough of the CVM tables as `$x = 1` executes. Restored from a file deleted in the frame-0 sprint's cleanup pass; parts are stale after frame-0 integration and the dispatch-cutover assimilation. See the Staleness note directly below for what needs updating before this walkthrough can serve as the sprint's contract."}
~~~

## Staleness note

Restored from git history (deleted in `b35e0d4`). Known-stale parts that need updating before this walkthrough is authoritative for the first-variable sprint:

- **CaspM shape.** ✅ **Fixed.** Old file used `{"bwc": "="}` for the assignment head and `{"v": "x"}` for the variable-name atom; both have been updated in place to `{"in": "as"}` and bare `"x"` respectively (5 occurrences of each replaced).
- **`objects.idx` column.** ✅ **Fixed.** Removed from every `objects` state table (header and data cells); `colspan` on the title row decremented from 9 to 8. `refs.idx` column is unaffected — that's a different column on a different table and still exists.
- **`frame:run` / execution loop shape.** ✅ **Fixed.** Rewritten around the actual `engine:run()` shape — Lua `ipairs` over the decoded ast, each row through `M:run_row`, which delegates to `dispatch(self.row_handlers, self, row)`. No `frame:run` method exists anywhere in shipping.
- **Dispatch language.** ✅ **Fixed.** "Picking the routine" section rewritten around the Handler chain — an assignment Handler subclass (`DispatchAs`) claims the row via its `:handle` method and calls into the CVM primitives. The routine names (`add_scalar`, `ensure_locals`, `add_ref`, `set_local_to_scalar`) are still correct and preserved.
- **Dead cross-links.** ✅ **Fixed.** The `end-of-bootstrap` link (pointed into the deleted `ideas/frames-as-objects/examples/end-of-bootstrap/` tree) rerouted to [Set up frame 0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/) — the surviving requirements spec that describes what happens right before this walkthrough starts. Also rewrote the "same shape as end-of-bootstrap snapshot" phrasing that referenced the deleted doc.
- **`processes.process_pk` type.** ✅ **Fixed.** `process` column values in all state tables updated from `<code>1</code>` to `<code>b8f4a2e1-9c3d-…</code>` — a truncated UUID-shaped stand-in matching the same pk used illustratively in the frame-0 sprint's tables.

Once those six fixes land, this walkthrough becomes the sprint's concrete state contract — the end-to-end test can assert each state table matches after the corresponding step.

## Original content follows

The smallest program that changes state:

~~~caspian
$x = 1
~~~

Picks up where [Set up frame 0](https://puck.uno/requirements/bootstrap/stage/set-up-frame-0/) leaves off — bootstrap complete, frame 0 pushed into the CVM with the assignment's CaspM in its `ast`, ready to dispatch. This walkthrough goes from there through the execution of the assignment, surfacing which multi-write operations naturally wrap in a transaction and which stand as observable checkpoints between them.

Approximate CaspM (transpile + normalize):

~~~json
[
	[
		{"in": "as"},
		"x",
		{"v": 1}
	]
]
~~~

## After bootstrap

Same shape as the post-bootstrap snapshot, just with `$x = 1`'s CaspM in frame 0's `ast`. User seed in place, `processes` seeded, frame 0 pushed with `stmt_idx = 0` — about to dispatch the assignment. No bucket yet.

**Reading the pks.** The pks below use mnemonic prefixes for readability — `f00d…` for frame 0, `ca7e…` for the scalar (as in "cache"), `b00d…` for the bucket, `10ca…` for the locals hash. The trailing `-000N` suffixes are stable identifiers, not creation-order counters (the scalar happens to be created before the bucket, so its `-4` predates the bucket's `-2`).

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>f</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>b8f4a2e1-9c3d-…</code></td><td>user</td><td class="col-comment"><code>[[{"in": "as"}, "x", {"v": 1}]]</code></td></tr>
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

## The execution loop

Once the engine has frame 0 pushed, `engine:run()` fetches the frame's `ast` from the CVM, JSON-decodes it, and iterates the rows:

~~~lua
for _, row in ipairs(cjson.decode(ast_json)) do
    self:run_row(row)
end
~~~

Each `run_row` call delegates to the row-head dispatch chain via `dispatch(self.row_handlers, self, row)`. `dispatch` walks the chain — each Handler in `row_handlers` gets offered the row and returns `true` (I claimed it), `false` (not my shape, next handler), or raises (I claimed it and hit a problem). First `true` wins; if no handler returns `true`, dispatch raises `unrecognized_row_head`, which `run_row` reshapes with the atom-keys detail appended before letting it propagate.

The frame's `ast` is a top-level flat array of statement rows; iterating it is iterating the AST. `stmt_idx` on the frame tracks how far dispatch has advanced (0 at push, incremented after each row), so on resume the loop knows where to pick up. When iteration exhausts the array, the frame is done.

## Dispatch statement 0

Statement 0 is the assignment `$x = 1`. The row that comes off the AST is:

~~~json
[{"in": "as"}, "x", {"v": 1}]
~~~

Three atoms: the head `{"in": "as"}` is the assignment-statement prefix (normalize-time internal primitive `as`), the second element `"x"` is a bare string naming the target local, the third `{"v": 1}` is the value atom holding the literal.

### Picking the routine

The engine's `row_handlers` chain gets each row via `dispatch`. An assignment Handler subclass — call it `DispatchAs` — recognizes this row by checking `type(row[1]) == 'table' and row[1]['in'] == 'as'`. When that check passes, the handler unpacks the row and calls the CVM primitives that actually perform the assignment.

Under this design, dispatch decisions live in each Handler's `:handle` method, not in a central switch. Adding a new construct is registering a new Handler subclass into `row_handlers`; no if/elseif chain in `run_row` to grow.

The Handler for `$x = 1` specifically routes to [`frame:set_local_to_scalar`](https://puck.uno/src/engine/cvm/frame.lua) with `name = 'x'`, `scalar_type = 'n'`, `scalar_value = 1`. That single primitive composes the writes below (`add_scalar` + `ensure_locals` + `add_ref`) into one specialized routine.

Other assignment shapes get their own Handlers (or their own branches inside this Handler) later:

- RHS being a name reference (`$x = $y`) goes to a name-lookup routine (not yet written).
- LHS being an attribute-target (`$obj.field = ...`) goes to a bucket-write routine (not yet written).
- Compound assignments (`$x += 1`) get their own path.

Each shape gets its own compiled path — no generic `set_variable` that pays a runtime dispatch cost per assignment. Dispatch happens once at the Handler level; the primitives it calls are shape-specific.

### Overview

The write block covered by `frame:set_local_to_scalar` — every write triggered by the assignment, in order:

~~~sql
-- 1. Create the scalar.
insert into objects (primitive, scalar_type, scalar_value, owner_role)
values ('o', 'n', 1, <user_pk>);
-- returns the scalar's object_pk

-- 2. Ensure frame 0's bucket exists (lazy). If frame 0's bucket_pk
--    is null, one INSERT creates it. The engine's cached statement
--    derives `owner_role` from the target row via `insert…select`
--    rather than passing it in:
--      insert into objects (primitive, bucket_for, owner_role)
--      select 'h', <frame_0_pk>, owner_role from objects
--      where object_pk = <frame_0_pk>;
--    The objects_denormalize_bucket trigger updates frame 0's
--    bucket_pk in the same statement — bucket creation is atomic
--    at the SQL layer, no engine-side wrapping needed.

-- 3. Ensure the locals hash exists inside the bucket (lazy). If
--    bucket['locals'] isn't already bound, two INSERTs create it:
--      insert into objects (primitive, owner_role)
--      values ('h', <user_pk>);
--      insert into refs (parent, child, key, idx)
--      values (<bucket_pk>, <new_hash_pk>, 'locals', 0);

-- 4. Bind the name inside the locals hash.
insert into refs (parent, child, key, idx)
values (<locals_pk>, <scalar_pk>, 'x', 0);
~~~

The transaction boundary and `stmt_idx` advance aren't `set_local_to_scalar`'s concern — that's the dispatcher's layer above (`engine:run_row` and the Handler `:handle` method that invokes this primitive). The Handler wraps each dispatch step in its own `begin`/`commit` and `M:run` advances `stmt_idx` after the row is handled. `set_local_to_scalar` just does the four writes above.

The "ensure the bucket exists" step is one lookup plus at most one INSERT. There is no Lua-side transaction or helper wrapping bucket creation — SQLite handles the atomicity via the `objects_denormalize_bucket` trigger. Inserting a HashPrimitive with `bucket_for` set is a single statement; the trigger updates the owner's `bucket_pk` in the same write.

## Start transaction

The engine issues `begin;`. Every subsequent write happens inside this transaction until `commit;` closes it. If the process dies at any point in between, SQLite discards the whole block and the CVM sees the state exactly as it was at this snapshot — the "about to dispatch statement 0" moment.

~~~sql
begin;
~~~

## Create the number

The engine evaluates the RHS first. The RHS is the literal `1` — a primitive scalar. [`engine:add_scalar`](https://www.puck.uno/src/engine/cvm/engine.lua#add-scalar-insert-a-scalar-objects-row-return-its-pk) materializes it as an objects row:

~~~sql
insert into objects (primitive, scalar_type, scalar_value, owner_role)
values ('o', 'n', 1, <user_pk>);
~~~

`owner_role = user`, no incoming refs. Orphan for now — the scalar exists, but nothing yet points at it. The subsequent steps set up the frame's local-storage machinery and finally bind `x` to this row.

### State after

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>f</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>b8f4a2e1-9c3d-…</code></td><td>user</td><td class="col-comment">frame 0 — <code>bucket_pk</code> still null</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — orphan</td></tr>
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

## Set `frame.locals['x']`

The engine writes the scalar's pk into the frame's locals under key `x`. On the surface, one assignment:

~~~
frame.locals['x'] = <scalar_pk>
~~~

The whole subtree below is what [`frame:set_local_to_scalar`](https://www.puck.uno/src/engine/cvm/frame.lua#set-local-to-scalar-specialized-routine-for-name-scalar) does — the one specialized routine for the scalar-RHS case. The scalar itself was materialized above in [Create the number](#create-the-number); the three subsections here walk the ensures and the bind that plant it into the frame's local scope. `set_local_to_scalar` composes `add_scalar` + `ensure_locals` + `add_ref` at the top level, and `ensure_locals` decomposes further into `frame.bucket` + `frame.locals` — that's why the subsections read as `frame.bucket`, `frame.locals`, `['x'] = <scalar_pk>` rather than the top-level three-call list.

Underneath, that composes into a tree of get-or-create operations. Each "ensure" branch is idempotent: does nothing if the target already exists, otherwise materializes it and writes to the DB. On a fresh frame — like this one — none of the targets exist, so every branch runs.

Two notations in the tree below refer to the same locals hash: `frame.locals` (the method that returns it) and `bucket['locals']` (the ref that stores it under the key `locals` inside the frame's bucket). One reads it, the other holds it.

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

Frame 0's `bucket_pk` is null, so the branch runs. [`object:bucket`](https://www.puck.uno/src/engine/cvm/object.lua#bucket-the-object-s-bucket-lazily-created) (inherited by frame) calls [`engine:add_bucket`](https://www.puck.uno/src/engine/cvm/engine.lua#add-bucket-insert-a-bucket-return-its-pk). One INSERT creates the HashPrimitive; the `objects_denormalize_bucket` trigger updates frame 0's `bucket_pk` inside the same statement — atomic at the SQL layer.

~~~sql
insert into objects (primitive, bucket_for, owner_role)
values ('h', <frame_0_pk>, <user_pk>);
~~~

#### State after

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>f</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>b8f4a2e1-9c3d-…</code></td><td>user</td><td class="col-comment">frame 0 — <code>bucket_pk</code> is now <code>b00d...</code> (denormalized by trigger)</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — still orphan</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket; <code>bucket_for</code> = <code>f00d...</code></td></tr>
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

`bucket` returns `b00d...`. `frame.locals` continues.

### `frame.locals` — ensure the locals hash

The bucket has no entry under key `locals`, so this branch runs. [`frame:ensure_locals`](https://www.puck.uno/src/engine/cvm/frame.lua#ensure-locals-get-or-create-the-frame-s-locals-hash) does two writes via [`engine:add_hash`](https://www.puck.uno/src/engine/cvm/engine.lua#add-hash-insert-a-standalone-hashprimitive-return-its-pk) and [`engine:add_ref`](https://www.puck.uno/src/engine/cvm/engine.lua#add-ref-insert-a-ref-row-return-its-ref-pk): the HashPrimitive that will be the locals hash, and the ref that stores it in the bucket under `locals`.

~~~sql
insert into objects (primitive, owner_role)
values ('h', <user_pk>);
-- returns the locals hash's object_pk

insert into refs (parent, child, key, idx)
values (<bucket_pk>, <locals_pk>, 'locals', 0);
~~~

After the first INSERT the row exists but is orphan; after the second it's reachable from frame 0's bucket under the key `locals`.

#### State after

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>f</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>b8f4a2e1-9c3d-…</code></td><td>user</td><td class="col-comment">frame 0</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — still orphan</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket</td></tr>
<tr><td><code>10ca0000-0001-4000-8000-000000000003</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">locals hash — reachable via frame 0's bucket under key <code>locals</code></td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>b00d...</code></td><td><code>10ca...</code></td><td><code>locals</code></td><td><code>0</code></td><td class="col-comment">frame 0's bucket → locals hash</td></tr>
</tbody>
</table>

`frame.locals` returns `10ca...`. The outer assignment resumes.

### `['x'] = <scalar_pk>` — bind the key

The last write: [`engine:add_ref`](https://www.puck.uno/src/engine/cvm/engine.lua#add-ref-insert-a-ref-row-return-its-ref-pk) inserts a ref from the locals hash to the scalar under key `x`.

~~~sql
insert into refs (parent, child, key, idx)
values (<locals_pk>, <scalar_pk>, 'x', 0);
~~~

The scalar is no longer orphan. Looking up `$x` in frame 0 walks: frame 0 → its bucket → the `locals` ref → the locals hash → the `x` ref → the scalar `1`.

#### State after

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>f</code></td><td>—</td><td><em>see comment</em></td><td><code>0</code></td><td><code>b8f4a2e1-9c3d-…</code></td><td>user</td><td class="col-comment">frame 0</td></tr>
<tr><td><code>ca7e0000-0001-4000-8000-000000000004</code></td><td><code>o</code></td><td><code>n</code> / <code>1</code></td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">scalar 1 — bound to name <code>x</code> in the locals hash</td></tr>
<tr><td><code>b00d0000-0001-4000-8000-000000000002</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">frame 0's bucket</td></tr>
<tr><td><code>10ca0000-0001-4000-8000-000000000003</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>user</td><td class="col-comment">locals hash</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="6">refs</th></tr>
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
