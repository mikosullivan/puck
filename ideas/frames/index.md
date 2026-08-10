# Frames

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames",
	"role": "design-in-progress space for frame-shape questions. Currently: a snapshot of the MVM tables at the moment bootstrap finishes Initialize VM and Stage is about to run — the state Install CaspM is going to write into.",
	"status": "sketch"
}}
~~~

## MVM state just before code lands

Snapshot at the boundary between [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/) and [Stage → Install CaspM](https://www.puck.uno/requirements/bootstrap/stage/install-caspm/). Only the tables that matter for adding code; only the fields relevant to that.

<table>
<thead>
<tr><th class="pk-th">object_pk</th><th>user</th><th>primitive</th><th>role_parent</th><th>ast</th></tr>
</thead>
<tbody>
<tr><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>1</code></td><td><code>h</code></td><td>null</td><td>null</td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="pk-th-relationships">rel_pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<thead>
<tr><th class="pk-th-frames">frame_pk</th><th>process_pk</th><th>idx</th><th>type</th><th>method_pk</th><th>method_class_pk</th><th>lexical_parent_pk</th></tr>
</thead>
<tbody>
</tbody>
</table>

## Loading the script

Given this Caspian source:

~~~caspian
$x = 1

if $x > 0
	puts 'positive'
elseif $x < 0
	puts 'negative'
else
	puts 'zero'
end
~~~

Running the source through `transpile` + `normalize` produces this CaspM (actual output from `src/engine/transpiler.lua` + `src/engine/normalize.lua`):

~~~json
[
	[
		{"in": "as"},
		"x",
		{"v": 1}
	],
	[
		{"if": {
			"conditions": [
				{
					"test": [
						{"in": "fc"},
						{
							"fn": ">",
							"rc": {"var": "x"},
							"a": [{"v": 0}]
						}
					],
					"action": [
						[{"bwc": "puts"}, {"v": "positive"}]
					]
				},
				{
					"test": [
						{"in": "fc"},
						{
							"fn": "<",
							"rc": {"var": "x"},
							"a": [{"v": 0}]
						}
					],
					"action": [
						[{"bwc": "puts"}, {"v": "negative"}]
					]
				}
			],
			"else": [
				[{"bwc": "puts"}, {"v": "zero"}]
			]
		}}
	]
]
~~~

Two top-level statement rows: the assignment (`[{"in": "as"}, "x", {"v": 1}]`), and the if (a one-atom row wrapping the `{if: {conditions, else}}` atom). The `if` atom has a flat `conditions` array (source `elsif` chain flattens) with two `{test, action}` entries — one per truthy branch — and an `else` field for the fall-through statements. Omitting the `else` field entirely is the spec's signal for "no else clause"; here it's present because the source has one.

The `>` and `<` comparisons dispatch through `function_call` (`{"in": "fc"}`) with `fn`, `rc`, `a` (function name, receiver, args). Bareword `puts` stays as `{"bwc": "puts"}` inside its statement row. Short keys throughout: `v` for value, `rc` for receiver, `fn` for function, `a` for args.
