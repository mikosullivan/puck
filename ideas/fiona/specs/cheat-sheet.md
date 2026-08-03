# Fiona cheat sheet

~~~vibecode
{"vibecode": {
	"doc": "ideas_fiona_specs_cheat_sheet",
	"role": "One-page reference of Fiona's public surface — signatures and one-line summaries. Detailed semantics live in the sibling index.md.",
	"status": "living reference"
}}
~~~

Quick reference for Fiona's public API. See [index](./) for detailed semantics on each call.

## Methods

| Call | Returns |
| --- | --- |
| `db:add_array()` | `collection_pk` |
| `db:add_hash()` | `collection_pk` |
| `db:atomic(fn)` | whatever `fn` returns |
| `db:close()` | — |
| `db:delete_array_element(parent, idx)` | `boolean` — shifts sibling idxs down |
| `db:delete_hash_element(parent, key)` | `boolean` |
| `db:gc_errors()` | list of `{collection_pk, message, trace_order}` from the last drain |
| `db:get_array_element(parent, idx)` | `collection_pk \| scalar \| nil` |
| `db:get_array_length(parent)` | `integer` — max idx + 1 |
| `fiona.get_db(path, mode)` | `db` handle |
| `db:get_hash_element(parent, key)` | `collection_pk \| scalar \| nil` |
| `db:get_hash_length(parent)` | `integer` — count of entries |
| `db:is_array(pk)` | `boolean` — true iff row exists AND is an array |
| `db:is_hash(pk)` | `boolean` — true iff row exists AND is a hash |
| `db:keys(parent)` | for-loop iterator over keys / idxs |
| `db:meta()` | hash of the meta table |
| `db:on_gc(fn)` | — register close hook; `nil` clears |
| `db:pairs(parent)` | for-loop iterator over (key/idx, value) |
| `db:set_array_ref(parent, idx, ref_pk)` | — |
| `db:set_array_scalar(parent, idx, value)` | — |
| `db:set_hash_ref(parent, key, ref_pk)` | — |
| `db:set_hash_scalar(parent, key, value)` | — |
| `db:values(parent)` | for-loop iterator over values |

## API

Once you have a `db` handle, the natural Lua idioms map to Fiona calls like this. The parent's `collection_pk` (from `add_hash` / `add_array`) takes the place of the local variable that would name the table in native Lua.

| Native Lua | Fiona equivalent |
| --- | --- |
| `t = {}` (hash) | `local t = db:add_hash()` |
| `t = {}` (array) | `local t = db:add_array()` |
| `t.foo = "bar"` | `db:set_hash_scalar(t, "foo", "bar")` |
| `t.child = {}` | `db:set_hash_ref(t, "child", db:add_hash())` |
| `t.foo` | `db:get_hash_element(t, "foo")` |
| `t.foo = nil` (delete) | `db:delete_hash_element(t, "foo")` |
| `arr[3] = "x"` (1-indexed) | `db:set_array_scalar(arr, 2, "x")` (0-indexed) |
| `arr[3]` | `db:get_array_element(arr, 2)` |
| `#arr` | `db:get_array_length(arr)` |
| count of hash entries | `db:get_hash_length(t)` |
| `table.remove(arr, 3)` | `db:delete_array_element(arr, 2)` |
| `t = {a = 1, b = 2}` (literal) | build with successive `set_hash_scalar` calls, wrapped in `db:atomic()` |
| `for k in pairs(t) do ... end` | `for k in db:keys(t) do ... end` |
| `for _, v in pairs(t) do ... end` | `for v in db:values(t) do ... end` |
| `for k, v in pairs(t) do ... end` | `for k, v in db:pairs(t) do ... end` |
| `for i, v in ipairs(arr) do ... end` | `for i, v in db:pairs(arr) do ... end` (yields 0-based idxs) |
