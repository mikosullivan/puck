~~~vibecode
{"doc": "sprint-walkthrough", "sprint": "numbers",
	"role": "Concrete example of the sprint's schema in action. Runs `$x = 1` through the sprint's engine (with a `%process.stop` afterward so the graph stays visible), dumps the full state of `objects` and `refs`, and walks through each row / each ref. Load-bearing illustration: the scalar `1` lands as `scalar_number = 1.0` (REAL affinity coerces the Lua integer input to a float on the way in), while `scalar_null` / `scalar_string` / `scalar_bool` all stay null. Under the pre-sprint schema this would have been one row with `scalar_type = 'n'` and `scalar_value = 1` in the polymorphic `blob` column."}
~~~

# `$x = 1` walkthrough

What the database looks like after Caspian runs a single assignment. Uses `%process.stop` immediately after the assignment so the walker halts before its tail drain reaps the orphaned chain — this leaves every object created by the dispatch visible for inspection.

## Source

~~~caspian
$x = 1
%process.stop
~~~

## What happens

- **Boot.** `engine.new()` opens the CVM. The schema seeds three role rows (engine, cache, user).
- **Cap + frame 0.** `run()` inserts the process cap (`control = 'f'`, `frame_process_cap = 1`, empty frame_ast, `frame_stmt_idx = 0`) and frame 0 under it (also `'f'`, `frame_parent = cap`, `frame_ast = <caspm>`, `frame_stmt_idx = 0`).
- **Statement 0 dispatches.** The `{in: 'as'}` handler routes to `frame:set_local_to_scalar('x', 1)` which:
	- calls `cvm:add_scalar(1, user)` — Lua's `type(1) == 'number'` picks the `scalar_number` column; REAL affinity coerces the integer to `1.0` at insert time.
	- calls `frame:ensure_own_scope()` — materializes the bucket → scopes → scopes[0] chain.
	- calls `cvm:upsert_ref(scopes[0], 'x', scalar_pk)` — binds `x` in the frame's own scope.
	- marks frame 0 `frame_gc = 1`.
- **Walker advances.** `frame_stmt_idx` 0 → 1, `frame_gc` auto-nulls.
- **Statement 1 dispatches.** `%process.stop` sets `engine.stopped = true`.
- **Walker halts.** Breaks before advancing again. `run_frame` skips its reap. `run()` returns `{complete = 0, stopped = 1, cap_pk}`.

At this point every row created above is still present in the DB. No drain has run.

## `objects` — 9 rows

Numbered by insertion order; UUIDs elided for readability. Only the columns that carry data on any row are shown; every other column is null.

Every user-created row's `owner_role` FK points at #03 (user) — omitted from the columns below so the table fits, but set on every row where `control` is not `'r'`.

<table class="tbl-cvm">
<thead>
<tr><th class="tbl-title-objects" colspan="11">objects</th></tr>
<tr><th>#</th><th>base</th><th>control</th><th>role core</th><th>role parent</th><th>scalar number</th><th>frame parent</th><th>frame process cap</th><th>frame gc</th><th>frame stmt idx</th><th class="col-comment">comment</th></tr>
</thead>
<tbody>
<tr class="tbl-row-role"><td>#01</td><td><code>o</code></td><td><code>r</code></td><td><code>e</code></td><td></td><td></td><td></td><td></td><td></td><td></td><td class="col-comment">engine core role — root of the role tree</td></tr>
<tr class="tbl-row-role"><td>#02</td><td><code>o</code></td><td><code>r</code></td><td><code>c</code></td><td>#01</td><td></td><td></td><td></td><td></td><td></td><td class="col-comment">cache core role — child of engine</td></tr>
<tr class="tbl-row-role"><td>#03</td><td><code>o</code></td><td><code>r</code></td><td><code>u</code></td><td>#01</td><td></td><td></td><td></td><td></td><td></td><td class="col-comment">user core role — child of engine; owns every user-created row</td></tr>
<tr class="tbl-row-frame"><td>#04</td><td><code>o</code></td><td><code>f</code></td><td></td><td></td><td></td><td></td><td><code>1</code></td><td></td><td><code>0</code></td><td class="col-comment">process cap — top of the call stack; empty <code>frame_ast</code>, stays at <code>frame_stmt_idx = 0</code> its whole life</td></tr>
<tr class="tbl-row-frame"><td>#05</td><td><code>o</code></td><td><code>f</code></td><td></td><td></td><td></td><td>#04</td><td></td><td></td><td><code>1</code></td><td class="col-comment">frame 0 — nested under the cap; <code>frame_stmt_idx = 1</code> because the walker advanced past <code>$x = 1</code> before halting</td></tr>
<tr><td>#06</td><td><code>o</code></td><td></td><td></td><td></td><td><code>1.0</code></td><td></td><td></td><td></td><td></td><td class="col-comment">the scalar — Lua integer <code>1</code> on input; REAL affinity coerced to <code>1.0</code> on insert</td></tr>
<tr><td>#07</td><td><code>h</code></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td class="col-comment">frame 0's bucket — holds frame 0's outgoing hash-refs</td></tr>
<tr><td>#08</td><td><code>a</code></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td class="col-comment">the <code>scopes</code> array — <code>scopes[0..]</code> is the frame's scope chain</td></tr>
<tr><td>#09</td><td><code>h</code></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td class="col-comment">scopes[0] — frame's own scope; where variable bindings land</td></tr>
</tbody>
</table>

## `refs` — 4 rows

| ref pk | parent | child |   key    | idx | comment                                                                                                     |
|:------:|:------:|:-----:|:--------:|:---:|:------------------------------------------------------------------------------------------------------------|
|   1    |  #05   |  #07  |          |  0  | frame 0 → bucket. Non-container parent hangs its bucket with a null key; the child's `'h'` disambiguates    |
|   2    |  #07   |  #08  | `scopes` |  0  | bucket → scopes array. Hash entry under the conventional key that pins scopes at a known name in the bucket |
|   3    |  #08   |  #09  |          |  0  | scopes → scopes[0]. Array entry at idx 0                                                                    |
|   4    |  #09   |  #06  |   `x`    |  0  | scopes[0] → scalar. Hash entry under key `'x'` — the actual variable binding                                |

## `needs_trace` — empty

Nothing was orphaned during dispatch (no rebind fired the after-update mark trigger). No cascades ran (frame 0 wasn't reaped — `%process.stop` skipped the reap).

## `scalars` view — 1 row

Derived read shape for scalar-carrying rows:

| object pk | scalar type | value |
|:---------:|:-----------:|:-----:|
|    #06    |     `n`     | `1.0` |

The view coalesces the four scalar_* columns into a single `value` field and derives the type discriminator (`s` / `n` / `b` / `u`) from which column is non-null. Callers that want "the scalar's value regardless of which column it lives in" go through here; callers that need to write specific columns go directly to `objects`.

## Contrast with the pre-sprint schema

Under the shape this sprint replaces, row #06 would have been:

| object pk | primitive | scalar type | scalar value |
|:---------:|:---------:|:-----------:|:------------:|
|    ...    |    `o`    |     `n`     |     `1`      |

One polymorphic `blob` column, one text discriminator, and no structural coercion of the value's type — `1` could land as SQLite INTEGER (integer affinity) or REAL depending on what the client bound. Under the sprint's shape, four typed columns replace the pair, the CHECK per column pins each affinity, and `scalar_number`'s REAL affinity means "everything is a float" is enforced by the storage layer rather than by convention.
