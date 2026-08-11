# Hello world walkthrough

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_hello_world",
	"role": "the smallest possible walkthrough of loading a Caspian program — a single `puts 'hello world'` line — showing the source, the CaspM, and the MVM tables before and after Install CaspM. Sibling to ideas/frames/if-statement (adds if / elsif / else control flow). Intended as the first thing to read when learning how source lands in the MVM.",
	"status": "sketch"
}}
~~~

The smallest program:

~~~caspian
puts 'hello world'
~~~

## Transpile

Running the source through `transpile` + `normalize` produces:

~~~json
[
	[
		{"bwc": "puts"},
		{"v": "hello world"}
	]
]
~~~

One top-level statement row containing two atoms: `{bwc: "puts"}` (the bareword call) and `{v: "hello world"}` (the string literal argument). No calls collapse to `{in: "fc"}` here because `puts` at statement position is a bareword-command call, which the normalizer passes through unchanged in V1.

## MVM state just before code lands

Snapshot at the boundary between [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/) and [Stage → Install CaspM](https://www.puck.uno/requirements/bootstrap/stage/install-caspm/).

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="7">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>1</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>user / root role, seeded when the schema was installed</td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-relationships" colspan="5">relationships</th></tr>
<tr><th>rel pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frames" colspan="7">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>ast</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

`objects` has the seeded user/root role. `relationships` and `frames` are empty.

## MVM state after the code is loaded

After Install CaspM writes the outer-script callable and Set up frame 0 pushes the first frame:

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="7">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>1</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>user / root role, seeded when the schema was installed</td></tr>
<tr><td><code>a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5</code></td><td>null</td><td><code>o</code></td><td>null</td><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><em>CaspM above</em></td><td>outer-script callable — created during Install CaspM</td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-relationships" colspan="5">relationships</th></tr>
<tr><th>rel pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frames" colspan="7">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>ast</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>1</code></td><td><code>0</code></td><td><code>function_call</code></td><td><em>outer-script CaspM</em></td><td>null</td><td><code>0</code></td></tr>
</tbody>
</table>

One new `objects` row for the outer-script callable — the entire program is one row with the CaspM in its `ast` blob and `owner_role` pointing at the user seed (Install CaspM runs in the user role). One new `frames` row for frame 0, with `ast` = the outer script's CaspM (copied into the frame at push time) and `next_stmt_idx: 0` (about to dispatch row 0 of that ast — the `puts` call). The frame owns its ast — no FK back to the callable's `objects` row. `relationships` stays empty — nothing about `puts 'hello world'` implies a parent/child link between objects.

**Ownership rule:** every non-role object carries `owner_role` pointing at the role that created it. A row is EITHER a role (`role_parent` set) OR owned by one (`owner_role` set) — never both. The user seed is the one grandfathered exception (both null) because it exists before the enforcement trigger.

Bootstrap ends here. What happens next — walking frame 0's ast, dispatching the `puts` call, actually writing "hello world" to stdout — is execution, spec'd at [execution/](https://www.puck.uno/requirements/execution/).
