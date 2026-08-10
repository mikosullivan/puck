# If-statement walkthrough

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_if_statement",
	"role": "walkthrough of loading a Caspian script with if / elsif / else control flow into the MVM — source, CaspM, before-loading tables, after-loading tables. Sibling to ideas/hello-world (simpler on-ramp). Lives under ideas/frames/ as one of a series of increasingly rich load-example walkthroughs.",
	"status": "sketch"
}}
~~~

## MVM state just before code lands

Snapshot at the boundary between [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/) and [Stage → Install CaspM](https://www.puck.uno/requirements/bootstrap/stage/install-caspm/). Only the tables that matter for adding code; only the fields relevant to that.

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
<tr><th class="tbl-title-frames" colspan="8">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>method</th><th>method class</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frame-locals" colspan="3">frame_locals</th></tr>
<tr><th>frame pk</th><th>name</th><th>value object</th></tr>
</thead>
<tbody>
</tbody>
</table>

## Loading the script

Given this Caspian source:

~~~caspian
$x = 100

if $x > 0
	$y = 'positive'
	puts $y.upper
end
~~~

Running the source through `transpile` + `normalize` produces this CaspM (actual output from `src/engine/transpiler.lua` + `src/engine/normalize.lua`):

~~~json
[
	[
		{"in": "as"},
		"x",
		{"v": 100}
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
					"action": {
						"cl": {
							"pm": [],
							"bd": [
								[
									{"in": "as"},
									"y",
									{"v": "positive"}
								],
								[
									{"bwc": "puts"},
									[
										{"in": "fc"},
										{
											"fn": "upper",
											"rc": {"var": "y"}
										}
									]
								]
							]
						}
					}
				}
			]
		}}
	]
]
~~~

Two top-level statement rows: the assignment (`[{"in": "as"}, "x", {"v": 100}]`), and the if (a one-atom row wrapping the `{if: {conditions, else}}` atom). The `if` atom has a `conditions` array with one `{test, action}` entry — there's no `elsif` or `else` in the source, so the array has one entry and the `else` field is omitted entirely.

The condition `$x > 0` dispatches through `function_call` (`{"in": "fc"}`) with `fn: ">"`, `rc: {var: "x"}`, `a: [{v: 0}]`.

**The branch's `action` is a closure**, not a bare statement list — `{cl: {pm: [], bd: [<statements>]}}`, a closure envelope with empty params and a two-statement body. At execution time the engine invokes the closure with a fresh frame whose `lexical_parent` points at the enclosing frame, so `$y = 'positive'` lands in the block's own locals rather than the outer frame's. Reading `$x` inside the block walks up the `lexical_parent` chain to the enclosing frame's `x`. When the branch exits, the block's frame is popped and its locals go with it.

Inside the closure's body (`bd`), two statement rows:

- `$y = 'positive'` — an assignment: `[{"in": "as"}, "y", {"v": "positive"}]`.
- `puts $y.upper` — a bareword call to `puts` with a nested method-call atom as its argument: `[{"bwc": "puts"}, [{"in": "fc"}, {"fn": "upper", "rc": {"var": "y"}}]]`. The outer atom is the `puts` call; the inner `function_call` atom evaluates `$y.upper` and its result becomes the argument to `puts`. Nested function_call atoms in argument position work exactly the same way as top-level ones — same envelope shape, same dispatch.

Short keys throughout: `v` for value, `rc` for receiver, `fn` for function, `a` for args, `cl` for closure, `pm` for params, `bd` for body.

## MVM state after the code is loaded

After [Stage → Install CaspM](https://www.puck.uno/requirements/bootstrap/stage/install-caspm/) writes the outer-script callable and [Set up frame 0](https://www.puck.uno/requirements/bootstrap/stage/set-up-frame-0/) pushes the top-level frame:

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="7">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>1</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>user / root role, seeded when the schema was installed</td></tr>
<tr><td><code>a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5</code></td><td>null</td><td><code>o</code></td><td>null</td><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><em>CaspM tree above</em></td><td>outer-script callable — created during Install CaspM</td></tr>
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
<tr><th class="tbl-title-frames" colspan="8">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>method</th><th>method class</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>1</code></td><td><code>0</code></td><td><code>function_call</code></td><td><code>a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5</code></td><td>null</td><td>null</td><td><code>0</code></td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frame-locals" colspan="3">frame_locals</th></tr>
<tr><th>frame pk</th><th>name</th><th>value object</th></tr>
</thead>
<tbody>
</tbody>
</table>

One new `objects` row for the outer-script callable — `primitive: 'o'` (full object), `role_parent: null` (not a role), `owner_role` pointing at the user seed row (Install CaspM runs in the user role — the only role that exists at bootstrap), `ast` holding the CaspM tree exactly as `transpile + normalize` produced it, closure envelope on `action` and all. One new `frames` row for frame 0 — `idx: 0` (bottom of the stack), `method` pointing at the outer-script object, `method_class: null` (bare function, not a method), `lexical_parent: null` (nothing encloses frame 0), `next_stmt_idx: 0` (about to dispatch row 0 of the callable's ast). `relationships` and `frame_locals` are empty — the script hasn't run yet, so no bindings and no object-graph edges.

**Ownership rule:** every non-role object carries `owner_role` pointing at the role that created it. The engine reads the current frame's role at each `insert into objects` and writes it into the new row. A row is EITHER a role (`role_parent` set — points to its parent role) OR owned by one (`owner_role` set) — never both. The user seed row is grandfathered: it exists before the enforcement trigger lands, so `role_parent` and `owner_role` are both null on that one row only. Every other object henceforth is anchored to some role.

**The if-branch closure is not yet an object.** The `{cl: {pm, bd}}` envelope for the block is structural data sitting inside the outer script's ast; it hasn't been instantiated as a live callable. That happens at execution time — when frame 0 runs, dispatches the if atom, evaluates `$x > 0` as truthy, and reaches the branch's `action`, the engine creates a fresh closure object at that moment, then invokes it. Same shape you sketched informally as `closure ... end.run`: create, then run. Nothing about the block exists in `objects` until then.

## MVM state after the first statement runs

The engine starts walking frame 0's ast, dispatches the first row `[{"in": "as"}, "x", {"v": 100}]`, and returns. The assignment ran; the number `100` came into existence as an object; `$x` is bound to it in frame 0's `frame_locals`. The engine's cursor into the ast now sits just before the second row (the if), waiting to be dispatched.

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>scalar value</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><code>1</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>user / root role, seeded when the schema was installed</td></tr>
<tr><td><code>a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5</code></td><td>null</td><td><code>o</code></td><td>null</td><td>null</td><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td><em>outer-script CaspM</em></td><td>outer-script callable — created during Install CaspM</td></tr>
<tr><td><code>c3d4e5f6-a7b8-4c9d-8e0f-1a2b3c4d5e6f</code></td><td>null</td><td><code>o</code></td><td><code>100</code></td><td>null</td><td><code>8d46aade-8e8d-dbd7-bee2-e23414e35fa5</code></td><td>null</td><td>number 100 — bound to $x in frame 0</td></tr>
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
<tr><th class="tbl-title-frames" colspan="8">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>method</th><th>method class</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>1</code></td><td><code>0</code></td><td><code>function_call</code></td><td><code>a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5</code></td><td>null</td><td>null</td><td><code>1</code></td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frame-locals" colspan="3">frame_locals</th></tr>
<tr><th>frame pk</th><th>name</th><th>value object</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>x</code></td><td><code>c3d4e5f6-a7b8-4c9d-8e0f-1a2b3c4d5e6f</code></td></tr>
</tbody>
</table>

Three things changed against the previous snapshot:

- **A new `objects` row** for the number 100. Every scalar in Caspian is a full object with `primitive: 'o'` and `scalar_value` holding the value. Assigning `$x = 100` allocated this row on the fly.
- **A new `frame_locals` row** binding `x` to that new number-object in frame 0. When the engine reads `$x` later (inside the if condition and inside the block), it walks frame 0's `frame_locals` for the name `x` and follows `value_object` to reach the number object.
- **Frame 0's `next_stmt_idx` advanced from 0 to 1.** Row 0 (the `$x = 100` assignment) has been dispatched and completed; row 1 (the if atom) is next. The engine writes this back to the DB as part of finishing each statement, so the pause point (right now) has enough state on disk to resume: close the connection, reopen later, read `next_stmt_idx`, hand row 1 to the dispatcher.

## Evaluating the if

The engine reads row 1 of frame 0's callable — `[{"if": {...}}]` — and dispatches to the if-handler. That handler walks `conditions` in order: evaluate each `test`; on the first truthy one, evaluate that entry's `action` and stop. If nothing matches and `else` is present, evaluate `else`. Return the last value.

For this program there's one condition, no else.

### Evaluate the condition

The `test` is `[{"in": "fc"}, {"fn": ">", "rc": {"var": "x"}, "a": [{"v": 0}]}]` — a function_call dispatching `>` on `$x` with argument `0`.

The engine:

1. Resolves the receiver `{var: "x"}` — walks frame 0's `frame_locals` for name `x`, follows `value_object` to the number-100 object.
2. Materializes the literal argument `{v: 0}` as a fresh scalar-number object.
3. Looks up `>` on the receiver's class (Number). Pushes a transient call frame for the method, runs it (compares the receiver's `scalar_value` to the argument's), returns a scalar-boolean `true` object. Pops the transient frame.

Two lasting objects rows land — the literal `0` and the boolean result `true`. The method's frame lived for the duration of the dispatch only; it and its `frame_locals` are gone by the time control returns to the if-handler.

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>scalar value</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td><code>8d46aade-…</code></td><td><code>1</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>user / root role</td></tr>
<tr><td><code>a1b2c3d4-…</code></td><td>null</td><td><code>o</code></td><td>null</td><td>null</td><td><code>8d46aade-…</code></td><td><em>outer-script CaspM</em></td><td>outer-script callable</td></tr>
<tr><td><code>c3d4e5f6-…</code></td><td>null</td><td><code>o</code></td><td><code>100</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>number 100 — bound to $x in frame 0</td></tr>
<tr><td><code>d4e5f6a7-…</code></td><td>null</td><td><code>o</code></td><td><code>0</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>number 0 — literal from the condition $x > 0</td></tr>
<tr><td><code>e5f6a7b8-…</code></td><td>null</td><td><code>o</code></td><td><code>true</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>boolean true — result of $x > 0</td></tr>
</tbody>
</table>

`frames` and `frame_locals` unchanged from the previous snapshot.

### Materialize the block closure and push its frame

The condition is truthy, so evaluate `action` — a `{cl: {pm: [], bd: [<statements>]}}` closure envelope. Two writes to the DB:

1. **New `objects` row for the closure.** Its `ast` is the closure envelope (params + body). `primitive: 'o'`, no `scalar_value`.
2. **New `frames` row** for the closure invocation. `frame_pk: 2`, `idx: 1` (next up the stack), `method` = the new closure's pk, `method_class: null` (bare closure, no defining class), `lexical_parent: 1` (the outer frame — this is what gives the block its lexical scope), `next_stmt_idx: 0` (about to dispatch the closure's first row).

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>scalar value</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td><code>8d46aade-…</code></td><td><code>1</code></td><td><code>h</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>user / root role</td></tr>
<tr><td><code>a1b2c3d4-…</code></td><td>null</td><td><code>o</code></td><td>null</td><td>null</td><td><code>8d46aade-…</code></td><td><em>outer-script CaspM</em></td><td>outer-script callable</td></tr>
<tr><td><code>c3d4e5f6-…</code></td><td>null</td><td><code>o</code></td><td><code>100</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>number 100 — bound to $x in frame 0</td></tr>
<tr><td><code>d4e5f6a7-…</code></td><td>null</td><td><code>o</code></td><td><code>0</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>number 0 — literal from the condition $x > 0</td></tr>
<tr><td><code>e5f6a7b8-…</code></td><td>null</td><td><code>o</code></td><td><code>true</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>boolean true — result of $x > 0</td></tr>
<tr><td><code>f6a7b8c9-…</code></td><td>null</td><td><code>o</code></td><td>null</td><td>null</td><td><code>8d46aade-…</code></td><td><em>closure envelope</em></td><td>if-branch closure — materialized when the branch fired</td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frames" colspan="8">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>method</th><th>method class</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>1</code></td><td><code>0</code></td><td><code>function_call</code></td><td><code>a1b2c3d4-…</code></td><td>null</td><td>null</td><td><code>1</code></td></tr>
<tr><td><code>2</code></td><td><code>1</code></td><td><code>1</code></td><td><code>function_call</code></td><td><code>f6a7b8c9-…</code></td><td>null</td><td><code>1</code></td><td><code>0</code></td></tr>
</tbody>
</table>

Frame 0 is paused mid-if — its `next_stmt_idx` is still `1` because the if statement hasn't returned yet. Frame 2 will run its body to completion; when it pops, control returns to frame 0's if-handler, and only THEN does frame 0 advance to `next_stmt_idx: 2`.

### Block statement 0: `$y = 'positive'`

The dispatcher moves to frame 2 (top of stack), reads its callable's ast row 0 — `[{"in": "as"}, "y", {"v": "positive"}]`. Same shape as `$x = 100` earlier: materialize the string as a fresh scalar-string object, bind `y` in frame 2's `frame_locals`. Frame 2's `next_stmt_idx` advances to 1.

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>scalar value</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td colspan="8"><em>… previous 6 rows …</em></td></tr>
<tr><td><code>a7b8c9d0-…</code></td><td>null</td><td><code>o</code></td><td><code>'positive'</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>string 'positive' — bound to $y in frame 2</td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frames" colspan="8">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>method</th><th>method class</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>1</code></td><td><code>0</code></td><td><code>function_call</code></td><td><code>a1b2c3d4-…</code></td><td>null</td><td>null</td><td><code>1</code></td></tr>
<tr><td><code>2</code></td><td><code>1</code></td><td><code>1</code></td><td><code>function_call</code></td><td><code>f6a7b8c9-…</code></td><td>null</td><td><code>1</code></td><td><code>1</code></td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frame-locals" colspan="3">frame_locals</th></tr>
<tr><th>frame pk</th><th>name</th><th>value object</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>x</code></td><td><code>c3d4e5f6-…</code></td></tr>
<tr><td><code>2</code></td><td><code>y</code></td><td><code>a7b8c9d0-…</code></td></tr>
</tbody>
</table>

`x` still lives in frame 1's row; `y` lands in frame 2's row. Two separate scopes; no leakage.

### Block statement 1: `puts $y.upper`

Row 1 is `[{"bwc": "puts"}, [{"in": "fc"}, {"fn": "upper", "rc": {"var": "y"}}]]` — a bareword call to `puts` with a nested method-call atom as the argument.

Evaluation order:

1. **Evaluate the argument first** — `[{"in": "fc"}, {"fn": "upper", "rc": {"var": "y"}}]`. Look up `y` in frame 2's `frame_locals` → the `'positive'` string. Push a transient call frame for `.upper`, run it (returns a fresh `'POSITIVE'` string object), pop. New objects row for the uppercased string.
2. **Call puts with that new string.** Push a transient call frame for `puts`, execute (writes `POSITIVE\n` to stdout via whatever wiring `%stdout` provides), returns null. Pop the puts frame.

Frame 2's `next_stmt_idx` advances to 2 (past the last row of its body — it's ready to return).

<table>
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>user</th><th>primitive</th><th>scalar value</th><th>role parent</th><th>owner role</th><th>ast</th><th>comments</th></tr>
</thead>
<tbody>
<tr><td colspan="8"><em>… previous 7 rows …</em></td></tr>
<tr><td><code>b8c9d0e1-…</code></td><td>null</td><td><code>o</code></td><td><code>'POSITIVE'</code></td><td>null</td><td><code>8d46aade-…</code></td><td>null</td><td>string 'POSITIVE' — result of $y.upper</td></tr>
</tbody>
</table>

Frames and frame_locals unchanged from the previous snapshot (the transient `.upper` and `puts` frames each lived only for their dispatch and popped before we're back looking at the tables).

Side effect not in the DB: **`POSITIVE\n` written to `%stdout`.**

### Block frame pops

Frame 2's body is done (`next_stmt_idx: 2`, past the last row). The engine pops it. Two cascades fire:

- Frame 2's `frame_locals` row (the `y` binding) cascade-deletes. GC's mark-on-delete triggers fire on the `'positive'` string it pointed at.
- The closure object frame 2's `method` pointed at is no longer referenced from any live frame's `method`. It also gets marked for tracing.

Control returns to the if-handler in frame 0, which finishes and returns the block's last value (null, since `puts` returned null). Frame 0's `next_stmt_idx` advances to `2`.

<table>
<thead>
<tr><th class="tbl-title-frames" colspan="8">frames</th></tr>
<tr><th>frame pk</th><th>process pk</th><th>idx</th><th>type</th><th>method</th><th>method class</th><th>lexical parent</th><th>next stmt idx</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>1</code></td><td><code>0</code></td><td><code>function_call</code></td><td><code>a1b2c3d4-…</code></td><td>null</td><td>null</td><td><code>2</code></td></tr>
</tbody>
</table>

<table>
<thead>
<tr><th class="tbl-title-frame-locals" colspan="3">frame_locals</th></tr>
<tr><th>frame pk</th><th>name</th><th>value object</th></tr>
</thead>
<tbody>
<tr><td><code>1</code></td><td><code>x</code></td><td><code>c3d4e5f6-…</code></td></tr>
</tbody>
</table>

Objects unchanged at this instant — the GC candidates (the closure envelope object, the `'positive'` string, the temporary `0` and `true` and `'POSITIVE'` objects) are all marked but not yet swept. Whenever the collector runs, they go.

### Outer frame completes

Frame 0's `next_stmt_idx: 2` is past the callable's last row. Frame 0's body is done. The engine pops it — cascade-deletes frame 0's `frame_locals` (the `x` binding), which marks the number-100 object for tracing.

Frames table is empty. Frame_locals table is empty. The process's call stack has fully unwound; the program is done. Only the seeded user object, the outer-script callable, and any not-yet-collected transients remain in `objects`.
