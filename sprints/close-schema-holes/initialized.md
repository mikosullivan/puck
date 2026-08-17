~~~vibecode
{"doc": "sprint-note", "sprint": "close-schema-holes",
	"role": "Snapshot of the CVM objects table at initialized state — schema installed, three seeded role rows present (engine, cache, user), nothing else. All columns shown so the base state is fully explicit; useful reference when reasoning about what the roles rules currently enforce vs what still needs closing."}
~~~

# Initialized state

The CVM immediately after `cvm.open` returns. Schema DDL has run; the three seeded role rows are in `objects`. No process has been created yet.

## `objects`

Placeholder pks: `e0000000-…` (engine), `c0000000-…` (cache), `01111111-…` (user). Actual pks are UUIDs generated at install time.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="17">objects</th></tr>
<tr><th>object pk</th><th>primitive</th><th>scalar type</th><th>scalar value</th><th>core role</th><th>role parent</th><th>owner role</th><th>ast</th><th>stmt idx</th><th>process</th><th>parent frame</th><th>persistent</th><th>gc</th><th>needs trace</th><th>in trace</th><th>debug</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr><td><code>e0000000-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td><code>e</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">engine — root of the role tree; no parent, no owner</td></tr>
<tr><td><code>c0000000-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td><code>c</code></td><td><code>e0000000-…</code></td><td><code>e0000000-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">cache — child of engine, owned by engine</td></tr>
<tr><td><code>01111111-…</code></td><td><code>h</code></td><td>null</td><td>null</td><td><code>u</code></td><td><code>e0000000-…</code></td><td><code>e0000000-…</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td><code>1</code></td><td>null</td><td>null</td><td>null</td><td>null</td><td class="col-comment">user — child of engine, owned by engine</td></tr>
</tbody>
</table>

## What to notice

- **All three seeds are `primitive = 'h'`** — HashPrimitives. That's a convention held by the seed inserts but not currently enforced by any trigger (critique § 3). Any primitive could carry a `core_role` or `role_parent` under the current schema.
- **All three are `persistent = 1`** — pinned so GC never collects them.
- **Engine has no `role_parent` and no `owner_role`.** It's the root of the role tree, so `role_parent` naturally has nowhere to point. `owner_role` is null because the "non-role must have owner_role" trigger only fires when the row isn't a role — engine IS a role, so the requirement doesn't apply.
- **Cache and user set both `role_parent` and `owner_role` to engine.** Under the current rules, a role may carry an `owner_role` (it isn't forbidden); the seed inserts choose to.
