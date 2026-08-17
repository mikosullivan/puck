~~~vibecode
{"doc": "sprint-note", "sprint": "mask-classes",
	"role": "The CVM database state before the first command runs — the starting point the sprint works forward from. Minimal display: only object_pk and comment columns; role rows and process rows hidden for now so the mask-related additions stand out as they land."}
~~~

# Pre-run state

Where the CVM sits before the first command runs. Just after `cvm.open` returns and before any process has been seeded.

The seeded role rows (engine, cache, user) and any process cap are hidden from this view — the sprint's focus is on the mask-related objects that will appear as we start dispatching commands.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="2">objects</th></tr>
<tr><th>object pk</th><th class="col-comment">comment</th></tr>
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
