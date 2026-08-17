~~~vibecode
{"doc": "sprint-walkthrough", "sprint": "first-variable",
	"role": "State-by-state walkthrough of the CVM tables as `$x = 1` executes end-to-end. Each section is one at-rest state — table snapshot plus a one-line delta from the previous state. Objects and refs tables show every column of the schema so the reader can read the full shape without cross-referencing DDL.",
	"design": "A process is a `primitive='f'` cap row with `process=1` and `ast='[]'`. Frame 0 sits under the cap as a nested frame. Every command ends by pushing a marker child (also `primitive='f'`, `ast='[]'`, `gc=null` — terminal shape). Walker's advance couples stmt_idx += 1 with gc = 1 in one UPDATE; the AFTER-UPDATE cascade sweeps children. A bucket doesn't know it's a bucket — the owner→collection link lives entirely on the owner's mutable `bucket_pk` (or `stack_pk`) column. On frame delete a BEFORE-DELETE trigger reads the frame's `bucket_pk` and marks the target `needs_trace = 1` — bucket survives for GC to decide."}
~~~

# First variable — walkthrough

Program:

~~~caspian
$x = 1
~~~

Rules that shape every state below:

- **A process is a cap frame** — `primitive='f'`, `process=1`, `ast='[]'`, no parent. Its `object_pk` IS the process identity.
- **Frame 0 lives under the cap** as a nested frame (`parent_frame = cap_pk`, `process = null`).
- **Every command ends by pushing a marker child** — `primitive='f'`, `ast='[]'`, `gc=null` (terminal shape). Its presence signals "parent is mid-dispatch."
- **Walker's advance** is one UPDATE: `stmt_idx += 1, gc = 1`. The AFTER-UPDATE cascade sweeps child frames; the engine then resets `gc = null` once no children remain.
- **A bucket is a plain hash** — nothing on the bucket row points back at its owner. The link lives on the owner's `bucket_pk` column, which is mutable and can be shared across owners.
- **On frame delete** a BEFORE-DELETE trigger reads the frame's `bucket_pk` (and `stack_pk`) and marks the target `needs_trace = 1`. The bucket survives; GC decides its fate.

Placeholder pks in use (`user seed` = the `core_role='u'` row installed by the schema):

- `01111111-…` — user seed (`core_role = 'u'`)
- `0c72f81a-…` — cap
- `2dc612e0-…` — frame 0
- `07506201-…` — scalar
- `4c8e771b-…` — bucket
- `9a3b1e40-…` — scopes array
- `2e212b85-…` — scopes[0] (own scope)
- `4de89012-…` — marker

## After frame 0 is loaded

Cap seeded, frame 0 seeded under it. Nothing has run yet.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="19">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>bucket pk</th><th>stack pk</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>0</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">cap — process root</td></tr>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>0</code></td><td>null</td><td><code>0c72f81a-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">frame 0</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="9">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th>debug</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>

## After the assignment

Handler ran `set_local_to_scalar('x', 'n', 1)` — one savepoint. Materializes the scalar, ensures the bucket → scopes → scopes[0] chain, binds `x`, and pushes a marker child under frame 0. Frame 0's `stmt_idx` unchanged (walker hasn't advanced yet). Frame 0's `bucket_pk` gets set to the new bucket's pk by Larry's `add_bucket` (which inserts the bucket and updates the owner's pointer in one call).

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="19">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>bucket pk</th><th>stack pk</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>0</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">cap</td></tr>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>0</code></td><td>null</td><td><code>0c72f81a-…</code></td><td><code>4c8e771b-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">frame 0 — <code>bucket_pk</code> set</td></tr>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td><code>n</code></td><td><code>1</code></td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar <code>1</code></td></tr>
<tr><td><code>4c8e771b-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">bucket — plain hash, no back-reference</td></tr>
<tr><td><code>9a3b1e40-…</code></td><td><code>a</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes array</td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes[0] — own scope</td></tr>
<tr><td><code>4de89012-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>0</code></td><td>null</td><td><code>2dc612e0-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment"><strong>marker</strong> — terminal shape</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="9">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th>debug</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>4c8e771b-…</code></td><td><code>9a3b1e40-…</code></td><td><code>scopes</code></td><td><code>0</code></td><td>null</td><td class="col-comment">bucket</td><td class="col-comment">scopes array</td><td class="col-comment">bucket → scopes array</td></tr>
<tr><td><code>2</code></td><td><code>9a3b1e40-…</code></td><td><code>2e212b85-…</code></td><td>null</td><td><code>0</code></td><td>null</td><td class="col-comment">scopes array</td><td class="col-comment">scopes[0]</td><td class="col-comment">scopes[0]</td></tr>
<tr><td><code>3</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td>null</td><td class="col-comment">scopes[0]</td><td class="col-comment">scalar</td><td class="col-comment">scopes[0] → scalar</td></tr>
</tbody>
</table>

## After frame 0 completes

Walker's advance on frame 0: `stmt_idx = 1, gc = 1` in one UPDATE. Cascade sweeps the marker (marker's gc is null, parent's gc is 1 — both delete rules pass). Engine resets frame 0's `gc = null`. Frame 0 now terminal: past its max, gc null, no children. Data rows untouched.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="19">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>bucket pk</th><th>stack pk</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>0</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">cap</td></tr>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>1</code></td><td>null</td><td><code>0c72f81a-…</code></td><td><code>4c8e771b-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">frame 0 — terminal</td></tr>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td><code>n</code></td><td><code>1</code></td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar</td></tr>
<tr><td><code>4c8e771b-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">bucket</td></tr>
<tr><td><code>9a3b1e40-…</code></td><td><code>a</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes array</td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes[0]</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="9">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th>debug</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>4c8e771b-…</code></td><td><code>9a3b1e40-…</code></td><td><code>scopes</code></td><td><code>0</code></td><td>null</td><td class="col-comment">bucket</td><td class="col-comment">scopes array</td><td class="col-comment">bucket → scopes array</td></tr>
<tr><td><code>2</code></td><td><code>9a3b1e40-…</code></td><td><code>2e212b85-…</code></td><td>null</td><td><code>0</code></td><td>null</td><td class="col-comment">scopes array</td><td class="col-comment">scopes[0]</td><td class="col-comment">scopes[0]</td></tr>
<tr><td><code>3</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td>null</td><td class="col-comment">scopes[0]</td><td class="col-comment">scalar</td><td class="col-comment">scopes[0] → scalar</td></tr>
</tbody>
</table>

## After frame 0 is deleted

Walker's advance on the cap: `stmt_idx = 1, gc = 1`. AFTER-UPDATE cascade fires — deletes frame 0 (its gc is null, cap's gc is now 1; both delete rules pass). BEFORE-DELETE trigger on frame 0 reads its `bucket_pk` and marks the bucket `needs_trace = 1` — the bucket survives with a needs-trace flag; nothing else about the bucket changes (no back-reference to clear). Cap is still mid-cycle here (`gc = 1`, not yet reset).

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="19">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>bucket pk</th><th>stack pk</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>1</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td class="col-comment">cap — mid-cycle (gc=1)</td></tr>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td><code>n</code></td><td><code>1</code></td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar</td></tr>
<tr><td><code>4c8e771b-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td class="col-comment">bucket — needs_trace=1</td></tr>
<tr><td><code>9a3b1e40-…</code></td><td><code>a</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes array</td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes[0]</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="9">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th>debug</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>4c8e771b-…</code></td><td><code>9a3b1e40-…</code></td><td><code>scopes</code></td><td><code>0</code></td><td>null</td><td class="col-comment">bucket</td><td class="col-comment">scopes array</td><td class="col-comment">bucket → scopes array</td></tr>
<tr><td><code>2</code></td><td><code>9a3b1e40-…</code></td><td><code>2e212b85-…</code></td><td>null</td><td><code>0</code></td><td>null</td><td class="col-comment">scopes array</td><td class="col-comment">scopes[0]</td><td class="col-comment">scopes[0]</td></tr>
<tr><td><code>3</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td>null</td><td class="col-comment">scopes[0]</td><td class="col-comment">scalar</td><td class="col-comment">scopes[0] → scalar</td></tr>
</tbody>
</table>

## After the process closes

Engine resets cap's `gc = null` — cap is now terminal (stmt_idx=1, gc=null, no children). **This is the "program is done" state.** The engine hasn't marked the cap `needs_trace = 1` yet, so the cap itself still sits — but the script has been run.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="19">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>bucket pk</th><th>stack pk</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>1</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">cap — terminal, awaiting reap</td></tr>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td><code>n</code></td><td><code>1</code></td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar</td></tr>
<tr><td><code>4c8e771b-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td class="col-comment">bucket — needs_trace=1</td></tr>
<tr><td><code>9a3b1e40-…</code></td><td><code>a</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes array</td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes[0]</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="9">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th>debug</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>4c8e771b-…</code></td><td><code>9a3b1e40-…</code></td><td><code>scopes</code></td><td><code>0</code></td><td>null</td><td class="col-comment">bucket</td><td class="col-comment">scopes array</td><td class="col-comment">bucket → scopes array</td></tr>
<tr><td><code>2</code></td><td><code>9a3b1e40-…</code></td><td><code>2e212b85-…</code></td><td>null</td><td><code>0</code></td><td>null</td><td class="col-comment">scopes array</td><td class="col-comment">scopes[0]</td><td class="col-comment">scopes[0]</td></tr>
<tr><td><code>3</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td>null</td><td class="col-comment">scopes[0]</td><td class="col-comment">scalar</td><td class="col-comment">scopes[0] → scalar</td></tr>
</tbody>
</table>

## Trace begins

Engine's GC picks the bucket off the `needs_trace` queue: `needs_trace = null, in_trace = 1`. The bucket is now in progress — GC will trace its reachability from roots (roles, persistent objects, other live process caps) and decide whether to sweep it or clear its flags.

**Out of sprint scope.** GC isn't wired in [larry:run](./larry.lua); this section is what will happen once GC-substrate integration lands.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="19">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>bucket pk</th><th>stack pk</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>0c72f81a-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td><code>[]</code></td><td><code>1</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">cap</td></tr>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td><code>n</code></td><td><code>1</code></td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar</td></tr>
<tr><td><code>4c8e771b-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td class="col-comment">bucket — in_trace=1 (being traced)</td></tr>
<tr><td><code>9a3b1e40-…</code></td><td><code>a</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes array</td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>01111111-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scopes[0]</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="9">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th>debug</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>4c8e771b-…</code></td><td><code>9a3b1e40-…</code></td><td><code>scopes</code></td><td><code>0</code></td><td>null</td><td class="col-comment">bucket</td><td class="col-comment">scopes array</td><td class="col-comment">bucket → scopes array</td></tr>
<tr><td><code>2</code></td><td><code>9a3b1e40-…</code></td><td><code>2e212b85-…</code></td><td>null</td><td><code>0</code></td><td>null</td><td class="col-comment">scopes array</td><td class="col-comment">scopes[0]</td><td class="col-comment">scopes[0]</td></tr>
<tr><td><code>3</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td>null</td><td class="col-comment">scopes[0]</td><td class="col-comment">scalar</td><td class="col-comment">scopes[0] → scalar</td></tr>
</tbody>
</table>

## After the engine reaps the process

Trace concludes: the bucket has no incoming refs from any root, so GC sweeps it. Sweeping the bucket cascades its outgoing refs, marking their targets `needs_trace = 1`; the trace loop runs on each in turn until the queue is dry. Engine also marks the cap `needs_trace = 1`; same fate. DB back to just the seed rows.

**Out of sprint scope**, same as above.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="19">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>bucket pk</th><th>stack pk</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="9">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th>debug</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
</tbody>
</table>
