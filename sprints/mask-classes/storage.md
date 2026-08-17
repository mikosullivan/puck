~~~vibecode
{"doc": "sprint-note", "sprint": "mask-classes",
	"role": "How masks live in the CVM database. Starts with the database as it is before the first command runs, then grows as the sprint layers in mask-related writes. Minimal display: only object_pk and comment columns; role rows and process rows hidden for now so the mask-related additions stand out as they land."}
~~~

# Storage

How masks live in the CVM database. Starts with the state before the first command runs and grows as the sprint layers in mask-related writes.

The seeded role rows (engine, cache, user) and any process cap are hidden from this view — the sprint's focus is on the mask-related objects that appear as commands run.

## Before the first command

Just after `cvm.open` returns and before any process has been seeded.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="3">objects</th></tr>
<tr><th>object pk</th><th>ec</th><th class="col-comment">comment</th></tr>
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

## The `ec` column

Marks a row as an instance of an engine (Lua) class. The value is a short string identifier — `class`, and eventually `function`, `array`, and others.

- **Immutable.** A row IS a `caspian/class` at INSERT; there's no rebind. If a different engine class is wanted, insert a different row.
- **No value constraint (yet).** The field takes any string. A naming scheme lands later.

## After the class mask is stored

The first mask-related write lands: one row appears in `objects` for the class mask itself.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="3">objects</th></tr>
<tr><th>object pk</th><th>ec</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>c010cafe-…</code></td><td><code>class</code></td><td class="col-comment">class mask</td></tr>
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
