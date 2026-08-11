# After bootstrap

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_end_of_bootstrap",
	"role": "walkthrough of the CVM tables at the boundary between bootstrap and execution under the frames-as-objects sketch. Same 'puts hello world' source as ideas/frames/hello-world so the two can be diffed side by side; here the frame is an objects row and its bookkeeping (process, idx, next_stmt_idx) lives as scalar entries in the frame-object's bucket. Sibling to ideas/frames-as-objects/examples/closure/.",
	"status": "sketch"
}}
~~~

Under the frames-as-objects sketch, frame 0 is an `objects` row instead of a `frames` row. The bookkeeping that used to live in `frames` columns — process, idx, next_stmt_idx — lives as scalar entries in the frame-object's bucket. This walkthrough shows the CVM tables at the boundary between bootstrap and execution.

Same source as [hello-world](https://www.puck.uno/ideas/frames/hello-world):

~~~caspian
puts 'hello world'
~~~

Same CaspM after transpile + normalize:

~~~json
[
	[
		{"bwc": "puts"},
		{"v": "hello world"}
	]
]
~~~

**Note on the `comment` column.** The last column in the `objects` tables is a real schema field (declared as `debug`; shown as "comment" here for readability). See the [Frames as objects root page](https://www.puck.uno/ideas/frames-as-objects/#the-debug-column) for what it holds and why.

## After Initialize VM

Schema installed, pragmas set, user seed written, `processes` seeded with the bootstrap process. `current_process` (temp) records the active process_pk. `refs` is empty.

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed (user=1, persistent=1); grandfathered — the only row with owner_role null under the CVM's XOR rule</td></tr>
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

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-processes" colspan="1">processes</th></tr>
<tr><th>process pk</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td></tr>
</tbody>
</table>

## After Set up frame 0

Frame 0 lands as an `objects` row: `primitive = 'o'`, `ast` holds the CaspM tree directly, `stmt_idx = 0` (about to dispatch row 0 of the ast), `idx = 0` (stack position 0), `process = 1` (the bootstrap process), `owner_role` points at the user seed.

No bucket is created — this frame has no locals to hold. `lexical_parent` is absent (root scope, no enclosing frame). `stmt_idx`, `idx`, and `process` all used to sit as bucket entries; promoting each to a column on `objects` saves three rows per bucket entry. For a frame with no locals, that means no bucket row at all, no scalar rows, no `refs` rows.

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>CaspM above</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0 — folded frame</td></tr>
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

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-processes" colspan="1">processes</th></tr>
<tr><th>process pk</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td></tr>
</tbody>
</table>

## Finding the current frame

Bootstrap has laid down the state. Before the engine can run anything, it has to figure out which frame is about to start — the resume point. On a fresh open this happens to be frame 0, but the engine does the same lookup whether the DB is fresh or being revived from a paused session.

### Which frame?

There could be frames in the database from other processes — paused stacks, coroutines, whatever else shares the CVM file. The engine needs the frame that belongs to *its* process.

It knows its current process's pk — bootstrap wrote it into the `current_process` TEMP table. From there, finding frame 0 for that process is one query:

~~~sql
select object_pk
from objects
where process = (select value from current_process where key = 'current_process_pk')
  and idx = 0;
~~~

That returns the outermost frame of the current process — the one the engine starts looking at.

### Walk to the last frame

Frame 0 is only the top of the stack. If any nested frames exist, the engine has to walk down to the deepest one — the frame that's actually mid-execution.

The walk lives in Lua, not in a SQLite `with recursive`. SQLite's recursive CTE has a per-connection cap we don't want to inherit; a Lua loop can go as deep as the call stack allows.

~~~lua
--[[ {
	"in":  {"db": "SQLite handle", "process_pk": "current process's pk", "frame_0_pk": "the pk returned by the frame-0 query"},
	"out": "the deepest frame's object_pk — the frame the engine is currently on",
	"note": "walks one step at a time. Terminates when no frame exists at the next idx."
} ]]
local function find_last_frame(db, process_pk, frame_0_pk)
	local current_pk = frame_0_pk
	local depth = 0

	while true do
		local next_pk = nil
		local sql = string.format(
			"select object_pk from objects where process = %d and idx = %d",
			process_pk, depth + 1
		)

		for row in db:nrows(sql) do
			next_pk = row.object_pk
		end

		if not next_pk then
			return current_pk
		end

		current_pk = next_pk
		depth = depth + 1
	end
end
~~~

At end-of-bootstrap the walk terminates immediately: no frame exists at `idx = 1`, so the loop returns frame 0's pk on its first iteration. But the same code handles any stack depth on a revive — the loop is bounded by the actual call depth of the program, not by any engine-side constant.

### What's on that frame

We have now found the moment of execution. This frame was just about to start.

That's the finest granularity of CVM state. Every clean snapshot has exactly one "about to start" frame — the deepest one — and everything above it is paused waiting on it. Between two such snapshots the engine did an atomic block of work: pushed a nested frame, ran writes, popped, advanced `stmt_idx`. That interval is opaque; only the endpoints are persistent state.

Two properties fall out:

- **Pause / resume needs no extra machinery.** Close the DB at any snapshot, reopen later, keep going. The "about to start" frame is the resume point by construction.
- **Terminal state is well-defined.** When the outermost frame's last statement finishes and it pops, no frame is left. That's the "program done" state, as observable as any mid-program snapshot — no separate flag needed.

One caveat: an OS-level kill mid-writes leaves a state that isn't a clean "about to start" snapshot. Restoring one — by rolling back the writes or cleaning up the dangling rows — is the recovery model's job. That's a recovery invariant, not a state invariant; every intended stopping point still is "a frame about to start."

## Load the ast

Knowing which frame is current isn't enough — the engine still needs the ast in a form it can dispatch against. It reads `objects.ast` for the current frame — stored as JSON text — and parses it into a Lua-native tree attached to the frame's runtime context. The DB copy stays canonical; the parsed form lives in engine memory and gets re-parsed from scratch on any resume-from-pause.

It also reads the frame's `stmt_idx` — the position in the ast where dispatch picks up. At end-of-bootstrap it's 0 (bootstrap just pushed frame 0), but in general it can be any non-negative integer: a frame resumed mid-execution carries whatever `stmt_idx` was persisted at the last snapshot.

The rule generalizes past bootstrap: **whenever a frame becomes the current frame, load its ast and note its `stmt_idx`.** Bootstrap does it here for frame 0; later, when a `frame.run` call pushes a new frame, the same load-ast + read-stmt_idx routine runs for the new frame. Same operation, two triggers.

## Bootstrap ends here

Frame 0 is an ordinary object in the graph, and the engine knows it as the resume point. If a closure inside the loaded program later captures frame 0's scope, the closure holds an object-graph reference to the bucket, and everything reachable from the bucket stays alive as long as the closure does. No special-case cascade rule for frames, no "lexical_parent SET NULL" resignation — the design motivation is exactly that this fall-out of the object-graph GC is what closures need.

The next step — walking frame 0's ast, dispatching the `puts` call, actually writing "hello world" to stdout — is execution.
