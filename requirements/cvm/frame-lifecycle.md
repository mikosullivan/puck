~~~vibecode
{"doc": "note",
	"role": "Step-by-step trace of the CVM state through the lifecycle of a process: create_frame_0 pushes the process row and frame 0; the walker advances the frame's stmt_idx through its ast; the frame-0 shutdown deletes the frame (trigger flips processes.complete = 1); the engine's default auto-delete removes the process record. Every state along the way is a valid resume state."}
~~~

# Frame lifecycle

Step-by-step CVM state through the lifecycle of a process. Uses an empty program (`caspm = {}`) as the driving example — the ast column shows `[]` throughout, so the walker's while loop exits immediately and shutdown fires on the first iteration. A non-empty program only changes the ast string; the surrounding shape is the same.

Every state below is a valid resume state. If the database crashes at any moment (and it's persistent), the process can be resumed cleanly.

## After the process is added to `processes`

`initialize_process` has inserted one row into `processes` and returned its pk. Nothing else has changed yet — the user seed is still the only row in `objects`.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="3">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th></tr>
</thead>
<tbody>
<tr><td><code>36685fb5-…</code></td><td><code>0</code></td><td>null</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>user</th><th>owner_role</th><th>ast</th><th>stmt_idx</th><th>process</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>e87440b5-…</code></td><td><code>h</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed — root role, HashPrimitive, pinned</td></tr>
</tbody>
</table>

## After frame 0 is pushed to `objects`

The frame INSERT has now landed. `primitive = 'f'`, ast copied in as JSON, `stmt_idx = 0`, `process` set to the process pk from the previous step, `owner_role` set to the user seed. `parent_frame` is null (frame 0 has no parent frame). `bucket_pk` and `stack_pk` are null — the frame hasn't touched anything that would need a bucket or stack yet.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="3">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th></tr>
</thead>
<tbody>
<tr><td><code>b56705d4-…</code></td><td><code>0</code></td><td>null</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>user</th><th>owner_role</th><th>ast</th><th>stmt_idx</th><th>process</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>ac70370e-…</code></td><td><code>h</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>d5d2ad94-…</code></td><td><code>f</code></td><td>null</td><td><code>ac70370e-…</code></td><td><code>[]</code></td><td><code>0</code></td><td><code>b56705d4-…</code></td><td class="col-comment">frame 0 — freshly pushed, no dispatch yet, no bucket / stack</td></tr>
</tbody>
</table>

## Shutdown

Now that the frame has completed its cycle, it should remove itself from the frame stack. It must also set its parent (in this case the process) to a state that marks the completion of the process.

These two operations — **deleting the last frame** and **setting `processes.complete = 1`** — *must* be done together in a single transaction. This is not a soft rule; splitting them corrupts the process's observable state.

In the current implementation the atomicity is enforced by the `processes_complete_after_frame_0_delete` trigger: the walker issues one DELETE on the frame row, and the trigger flips `processes.complete = 1` as part of that same DELETE. One SQL statement, one atomic transition.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-processes" colspan="3">processes</th></tr>
<tr><th>process pk</th><th>complete</th><th>message</th></tr>
</thead>
<tbody>
<tr><td><code>b56705d4-…</code></td><td><code>1</code></td><td>null</td></tr>
</tbody>
</table>

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>user</th><th>owner_role</th><th>ast</th><th>stmt_idx</th><th>process</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>ac70370e-…</code></td><td><code>h</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
</tbody>
</table>

The process is now at a state in which any results from it can be reaped or ignored.

Typically the engine would next delete the process record. By default that's what Caspian will do. However, the engine can be configured (via `engine.auto_delete_process = false`) to leave the database at the current state.

If an attempt is made to run the process again that should raise an exception. The process is already completed.
