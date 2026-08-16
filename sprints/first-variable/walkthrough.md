~~~vibecode
{"doc": "sprint-walkthrough", "sprint": "first-variable",
	"role": "State-by-state walkthrough of the CVM tables as `$x = 1` executes end-to-end. Each section is one at-rest state — table snapshot plus a one-line delta from the previous state.",
	"design": "GC markers live in the frame stack (`primitive = 'f'`, `gc = 1`) but are not frames — no bucket, no stack. Every command ends by placing one. Drop-and-replace on frame drops; GC-marker drops are not replaced."}
~~~

# First variable — walkthrough

Program:

~~~caspian
$x = 1
~~~

Rules that shape every state below:

- **GC markers are not frames.** Structurally rows in the frame stack; semantically bookkeeping only. No bucket, no stack.
- **Every command ends by placing a GC marker** as child of the dispatching frame — same savepoint as the writes.
- **Drop-and-replace:** dropping a frame inserts a GC marker in its place, inheriting the anchor (`parent_frame` for nested, `process_pk` for frame 0). GC-marker removals are **not** replaced.

## After frame 0 is loaded

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="4">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>a3f2c8b1-…</code></td><td><code>0</code></td><td>null</td><td class="col-comment">fresh</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>gc</th><th>scalar value</th><th>frame parent</th><th>process pk</th><th>ast</th><th>stmt idx</th><th>needs trace</th><th>in trace</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td><code>a3f2c8b1-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>0</code></td><td>null</td><td>null</td><td class="col-comment">frame 0</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="5">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

## After the assignment

Handler ran `set_local_to_scalar('x', 'n', 1)`: scalar, bucket, locals hash, both refs, GC marker — all in one savepoint. Frame 0's `stmt_idx` unchanged.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="4">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>a3f2c8b1-…</code></td><td><code>0</code></td><td>null</td><td class="col-comment">unchanged</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>gc</th><th>scalar value</th><th>frame parent</th><th>process pk</th><th>ast</th><th>stmt idx</th><th>needs trace</th><th>in trace</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td><code>a3f2c8b1-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>0</code></td><td>null</td><td>null</td><td class="col-comment">frame 0</td></tr>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar <code>1</code></td></tr>
<tr><td><code>4c8e771b-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">bucket — <code>bucket_for = 2dc612e0-…</code></td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">locals hash</td></tr>
<tr><td><code>4de89012-…</code></td><td><code>f</code></td><td><code>1</code></td><td>null</td><td><code>2dc612e0-…</code></td><td>null</td><td><code>[]</code></td><td><code>0</code></td><td>null</td><td>null</td><td class="col-comment"><strong>GC marker</strong></td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>4c8e771b-…</code></td><td><code>2e212b85-…</code></td><td><code>locals</code></td><td><code>0</code></td><td class="col-comment">bucket → locals</td></tr>
<tr><td><code>2</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td class="col-comment">locals → scalar</td></tr>
</tbody>
</table>

## After the GC marker's empty pass

Walker dispatched the marker; `needs_trace` queue was empty. Marker deleted, frame 0's `stmt_idx` advanced to `1`. One savepoint.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="4">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>a3f2c8b1-…</code></td><td><code>0</code></td><td>null</td><td class="col-comment">unchanged</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>gc</th><th>scalar value</th><th>frame parent</th><th>process pk</th><th>ast</th><th>stmt idx</th><th>needs trace</th><th>in trace</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>2dc612e0-…</code></td><td><code>f</code></td><td>null</td><td>null</td><td>null</td><td><code>a3f2c8b1-…</code></td><td><code>[[{"in":"as"},"x",{"v":1}]]</code></td><td><code>1</code></td><td>null</td><td>null</td><td class="col-comment">frame 0 — past max, no children</td></tr>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar <code>1</code></td></tr>
<tr><td><code>4c8e771b-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">bucket</td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">locals</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>4c8e771b-…</code></td><td><code>2e212b85-…</code></td><td><code>locals</code></td><td><code>0</code></td><td class="col-comment">bucket → locals</td></tr>
<tr><td><code>2</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td class="col-comment">locals → scalar</td></tr>
</tbody>
</table>

## After frame 0 is dropped

Drop-and-replace fires. Frame 0 deleted; cascade wipes bucket and ref 1; trigger marks locals `needs_trace = 1`. A GC marker inserted with `process_pk = a3f2c8b1-…`. One savepoint.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="4">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>a3f2c8b1-…</code></td><td><code>0</code></td><td>null</td><td class="col-comment">GC marker is still a live child — not complete</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>gc</th><th>scalar value</th><th>frame parent</th><th>process pk</th><th>ast</th><th>stmt idx</th><th>needs trace</th><th>in trace</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>07506201-…</code></td><td><code>o</code></td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">scalar</td></tr>
<tr><td><code>2e212b85-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td class="col-comment">locals — needs_trace = 1</td></tr>
<tr><td><code>b8d3faa4-…</code></td><td><code>f</code></td><td><code>1</code></td><td>null</td><td>null</td><td><code>a3f2c8b1-…</code></td><td><code>[]</code></td><td><code>0</code></td><td>null</td><td>null</td><td class="col-comment"><strong>GC marker</strong> — anchored to the process</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="6">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>2</code></td><td><code>2e212b85-…</code></td><td><code>07506201-…</code></td><td><code>x</code></td><td><code>0</code></td><td class="col-comment">locals → scalar</td></tr>
</tbody>
</table>

## After GC sweeps the orphans

Walker dispatches the marker; GC loops the `needs_trace` queue, each item its own savepoint. Locals deleted (cascade marks scalar), then scalar deleted. Queue empty.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="4">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>a3f2c8b1-…</code></td><td><code>0</code></td><td>null</td><td class="col-comment">marker still live — not complete</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>gc</th><th>scalar value</th><th>frame parent</th><th>process pk</th><th>ast</th><th>stmt idx</th><th>needs trace</th><th>in trace</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>b8d3faa4-…</code></td><td><code>f</code></td><td><code>1</code></td><td>null</td><td>null</td><td><code>a3f2c8b1-…</code></td><td><code>[]</code></td><td><code>0</code></td><td>null</td><td>null</td><td class="col-comment">GC marker — work done</td></tr>
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

## After the process is retired

Walker deletes the GC marker (no replacement — it's a marker). Last-frame trigger flips `complete = 1`.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="4">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>a3f2c8b1-…</code></td><td><code>1</code></td><td>null</td><td class="col-comment">complete = 1; persists for the caller to reap</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>gc</th><th>scalar value</th><th>frame parent</th><th>process pk</th><th>ast</th><th>stmt idx</th><th>needs trace</th><th>in trace</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
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
