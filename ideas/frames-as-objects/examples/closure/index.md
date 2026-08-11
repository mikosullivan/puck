# Closure walkthrough

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_closure",
	"role": "step-by-step walkthrough of a closure returning up the call chain under the frames-as-objects sketch. Starts with the source loaded into frame 0 and grows one snapshot at a time. Introduces the lexical_parent column as the walkthrough gets to it. Sibling to end-of-bootstrap.",
	"status": "sketch"
}}
~~~

Working example, built up in small steps:

~~~caspian
$fn = function()
	$x = 1
	return closure()
end
~~~

Approximate CaspM (transpile + normalize):

~~~json
[
	[
		{"bwc": "="},
		{"v": "fn"},
		{"in": "fc", "call": [
			{"bwc": "function"},
			{"body": [
				[{"bwc": "="}, {"v": "x"}, {"v": 1}],
				[{"bwc": "return"}, {"in": "fc", "call": [{"bwc": "closure"}]}]
			]}
		]}
	]
]
~~~

## Code loaded into frame 0

Snapshot after bootstrap finishes — schema installed, user seeded, `processes` seeded with the bootstrap process, frame 0 pushed with the CaspM in its `ast`. `stmt_idx = 0` — about to dispatch statement 0 (the `$fn = function()…` assignment). No bucket yet — no locals have landed. Same structure as [end-of-bootstrap](https://www.puck.uno/ideas/frames-as-objects/examples/end-of-bootstrap/), just with different source.

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-objects" colspan="9">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar</th><th>ast</th><th>stmt_idx</th><th>idx</th><th>process</th><th>owner role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>h</code></td><td>—</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>f00d0000-0001-4000-8000-000000000001</code></td><td><code>o</code></td><td>—</td><td><em>CaspM above</em></td><td><code>0</code></td><td><code>0</code></td><td><code>1</code></td><td>user</td><td class="col-comment">frame 0 — outer script; about to dispatch the <code>$fn = function()…</code> assignment</td></tr>
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

<table class="tbl-mvm">
<thead>
<tr><th class="tbl-title-processes" colspan="1">processes</th></tr>
<tr><th>process pk</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td></tr>
</tbody>
</table>
