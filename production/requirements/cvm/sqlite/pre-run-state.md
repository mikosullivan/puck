~~~vibecode
{"doc": "note",
	"role": "CVM state at the moment the engine is constructed but hasn't yet started running a process. The schema seeds three core-role rows: engine (root), cache (child of engine), user (child of engine). All three are role primitives ('r') and pinned (persistent=1)."}
~~~

# Pre-run state

The CVM state right after `engine.new()` returns and before any process is run. `cvm.open()` has installed the schema and seeded the three core-role rows; nothing else has happened yet. This is the baseline the cache design starts from — the "empty ready-to-go" state.

All three seeded rows are role primitives (`primitive = 'r'`) and pinned (`persistent = 1`). The pin is mandatory for core roles: a cross-column CHECK rejects any core-role INSERT that leaves `persistent` null. Engine is the root of the role tree (`parent_role` null); cache and user hang off it via `parent_role`. See [roles](https://puck.uno/requirements/cvm/roles) for the full role-storage contract.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="6">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>core_role</th><th>parent_role</th><th>owner_role</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>eae0b9fb-…</code></td><td><code>r</code></td><td><code>e</code></td><td>null</td><td>null</td><td class="col-comment">engine — root of the core-role tree</td></tr>
<tr class="tbl-row-user"><td><code>692224e2-…</code></td><td><code>r</code></td><td><code>c</code></td><td><code>eae0b9fb-…</code></td><td><code>eae0b9fb-…</code></td><td class="col-comment">cache — child of engine, owned by engine</td></tr>
<tr class="tbl-row-user"><td><code>75af7662-…</code></td><td><code>r</code></td><td><code>u</code></td><td><code>eae0b9fb-…</code></td><td><code>eae0b9fb-…</code></td><td class="col-comment">user — child of engine, owned by engine</td></tr>
</tbody>
</table>

All three rows carry `persistent = 1`; column omitted from the display for brevity.
