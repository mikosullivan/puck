~~~vibecode
{"doc": "template",
	"role": "Boilerplate for a page (or a section of one) that shows CVM state — objects, refs — at a moment in time. Used in traces, walkthroughs, and any spec that needs to point at 'here's what the DB looks like right now.' Copy the source, fill in the placeholders, run the values through cjson to get real pks."}
~~~

# CVM state page template

Boilerplate for a page (or a section of one) that shows CVM state at a moment in time. Used in traces, walkthroughs, and any spec that needs to point at "here's what the DB looks like right now."

## What the template gives you

- HTML tables using the `tbl-cvm` wrapper class and `tbl-title-<name>` title-row class.
- Standard column sets for the two tables (`objects`, `refs`). Processes aren't a separate table — a process is a `primitive='f'` cap row in `objects` with `process=1`.
- A `col-comment` column on each table for a short per-row description.
- `tbl-row-user` class marker for the user seed row when it appears.
- Conventions for placeholder pks — real UUIDs truncated with `…` after the first 8 hex chars (e.g. `<code>02d0bdec-…</code>`).

## Placeholder syntax

- **`{describe moment}`** — one-sentence description of the state (what just happened, what's about to happen).
- **`{first-8-of-pk}-…`** — placeholder for a real pk. When authoring against a running CVM, capture the actual pks and truncate to first 8 hex characters.
- **`{comment}`** — per-row description in the `col-comment` cell (e.g., "user seed", "frame 0 — freshly pushed").
- Whole rows (`<tr>...</tr>`) get deleted or duplicated as needed.

## Source

Copy from between the fence below into a fresh doc. Update the intro prose, the placeholders, and the number of `<tr>` rows per table. Empty tables just leave `<tbody></tbody>` — the empty body renders as "no rows" in Orlando.

~~~markdown
~~~vibecode
{"doc": "note",
	"role": "{one-line role — what this state represents}"}
~~~

# {Page title}

{One or two intro sentences describing the moment being captured — what just happened, what's about to happen, what the reader should know before looking at the tables.}

## `objects`

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="8">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>user</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-user"><td><code>{first-8}-…</code></td><td><code>h</code></td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user seed</td></tr>
<tr><td><code>{first-8}-…</code></td><td><code>{primitive}</code></td><td>null</td><td><code>{first-8}-…</code></td><td><code>{ast or null}</code></td><td><code>{stmt_idx or null}</code></td><td><code>{1 or null}</code></td><td class="col-comment">{comment}</td></tr>
</tbody>
</table>

The `process` column is `1` on a cap frame (top of a call stack — its `object_pk` IS the process identity) and null on every other row. `parent_frame` (shown in the expanded set as "parent frame") points a nested frame at its cap or at another nested frame.

{Optional per-table prose.}

## `refs`

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-refs" colspan="8">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th><th class="col-comment">from</th><th class="col-comment">to</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td>{ref_pk}</td><td><code>{first-8}-…</code></td><td><code>{first-8}-…</code></td><td>{key or null}</td><td>{idx}</td><td class="col-comment">{friendly name of parent, e.g. "bucket"}</td><td class="col-comment">{friendly name of child, e.g. "scopes array"}</td><td class="col-comment">{comment}</td></tr>
</tbody>
</table>

The `from` and `to` columns are display-only comments — they give friendly names for what the parent and child objects ARE conceptually (e.g., "bucket", "scopes array", "scopes[0]", "scalar"). Not stored in the DB.

{Optional per-table prose.}
~~~

## Column-set variants

The template above shows the columns that appear most. Adjust `colspan` on the title row if you add or remove columns.

**`objects` — expanded set** (when the state depends on columns not in the basic set, e.g., `parent_frame`, `role_parent`, GC scratch columns):

~~~html
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr>
	<th>object pk</th><th>primitive</th><th>scalar</th><th>user</th>
	<th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th>
	<th>process</th><th>parent frame</th><th class="col-comment">comment</th>
</tr>
~~~

Ownership of a bucket or stack is a normal `refs` row from the owner to the collection — no dedicated columns on `objects`. To show the ownership edge in a state, add the ref row to the `refs` table (parent = owner, child = bucket/stack, `key = null`).

**`refs` — minimal (drop the `from` / `to` / `comment` columns when readers don't need them)**:

~~~html
<tr><th class="tbl-title-refs" colspan="5">refs</th></tr>
<tr><th>ref pk</th><th>parent</th><th>child</th><th>key</th><th>idx</th></tr>
~~~

## Capturing real pks from a running CVM

To grab pks from an actual run, drive the engine with the state you want and dump:

~~~lua
local cjson = require('cjson')
for row in e.cvm:nrows('select object_pk from objects') do
	print(cjson.encode(row))
end
~~~

Then truncate each `object_pk` to the first 8 hex characters and drop into the template.

## Related

- Live examples using this template: [requirements/cvm/frame-lifecycle](https://puck.uno/requirements/cvm/frame-lifecycle), and any pre-run / trace pages under [sprints/](https://puck.uno/sprints/).
- CSS classes are defined in `orlando/client-assets/style.css`.
