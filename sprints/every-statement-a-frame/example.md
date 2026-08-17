~~~vibecode
{"doc": "sprint-note", "sprint": "every-statement-a-frame",
	"role": "Worked example: a two-statement CaspM script expanded into objects + refs. Shows what the sprint's design produces at rest, before execution starts. Statement-level expansion (each statement is a frame with a `kind` tag); scalars and names are plain scalar objects."}
~~~

# Worked example — two statements

Script:

~~~caspian
$x = 1
$y = 2
~~~

CaspM (normalized): `[[{"in":"as"},"x",{"v":1}], [{"in":"as"},"y",{"v":2}]]`

## The AST expanded

Every AST node becomes a row. The tree is walked by ref lookup instead of JSON parsing.

**objects** — nodes

| pk | primitive | kind | scalar_type | scalar_value |
|---|---|---|---|---|
| `blk-0` | `f` | `block` | null | null |
| `bucket-blk-0` | `h` | null | null | null |
| `arr-stmts` | `a` | null | null | null |
| `stmt-1` | `f` | `assign` | null | null |
| `bucket-stmt-1` | `h` | null | null | null |
| `stmt-2` | `f` | `assign` | null | null |
| `bucket-stmt-2` | `h` | null | null | null |
| `str-x` | `o` | null | `s` | `"x"` |
| `val-1` | `o` | null | `n` | `1` |
| `str-y` | `o` | null | `s` | `"y"` |
| `val-2` | `o` | null | `n` | `2` |

**refs** — edges

| pk | parent | child | key | idx |
|---|---|---|---|---|
| 1 | `bucket-blk-0` | `arr-stmts` | `statements` | 0 |
| 2 | `arr-stmts` | `stmt-1` | null | 0 |
| 3 | `arr-stmts` | `stmt-2` | null | 1 |
| 4 | `bucket-stmt-1` | `str-x` | `name` | 0 |
| 5 | `bucket-stmt-1` | `val-1` | `value` | 1 |
| 6 | `bucket-stmt-2` | `str-y` | `name` | 0 |
| 7 | `bucket-stmt-2` | `val-2` | `value` | 1 |

Plus the usual bucket denormalization: `blk-0.bucket_pk = bucket-blk-0`, `bucket-blk-0.bucket_for = blk-0`, and same for `stmt-1` and `stmt-2`. Omitted from the table for readability.

## Shape observations

- **The AST IS the object graph.** No JSON blob. `blk-0`'s bucket has a `statements` key pointing at an ArrayPrimitive; the array's elements are the statement frames in order.
- **Frames used for structure, not just execution.** `blk-0`, `stmt-1`, `stmt-2` are all `primitive = 'f'` — "frames with their own special fields" (`kind` here, plus whatever runtime state).
- **The old `ast` JSON column is gone.** Every AST node is either a frame (containers, statements) or a plain object (literals, names).
- **One-child-per-parent breaks.** `blk-0` has two statement children (via the array, not via `parent_frame`). Under this model, structural children go through refs; `parent_frame` becomes the *execution-stack* relationship only.
- **Ordering is `refs.idx`.** Statement order is the ref idx on the `arr-stmts` array.

## Execution overlay

Runtime state (locals, scope) lives on `blk-0`'s bucket alongside `statements`. When the walker dispatches `stmt-1`, that adds a `scope` key to `blk-0`'s bucket → hash → `x` → `val-1`. Runtime state and AST coexist in the same bucket, distinguished by key.

## Cost

11 objects + 7 refs for a two-line script. All 18 rows need to INSERT atomically at load-time — every intermediate state during the expansion would fail some check (dangling FK, missing owner, etc.). Mitigation: single savepoint around the whole load; the schema never has to see the intermediate rows.

Once loaded and at rest, everything satisfies its invariants. The walker's runtime motions only touch a few rows at a time.

## Open

- **kind field.** Where does the `kind` tag live? A new column on objects? A subset of the existing primitive discriminator? Something else?
- **Value atoms as their own rows.** Started here with names/values as separate scalar-object rows. Alternative: keep them inline on the statement frame (e.g., `str-x` and `val-1` collapse into columns on `stmt-1`). Row-count vs. uniformity tradeoff.
- **Runtime state vs. AST.** They share a bucket here. Should they be separated (own_scope on frame, ast on a different attachment)?
- **AST re-use across runs.** A parsed script becomes a tree. Is that tree cloned per run, or shared? Sharing needs immutability guarantees on the AST portion.
